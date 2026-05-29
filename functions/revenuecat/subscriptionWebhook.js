const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");

/** Subscription event types we handle (exclude NON_RENEWING_PURCHASE). */
const SUBSCRIPTION_EVENT_TYPES = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "EXPIRATION",
  "CANCELLATION",
  "UNCANCELLATION",
  "PRODUCT_CHANGE",
  "SUBSCRIPTION_EXTENDED",
  "SUBSCRIPTION_PAUSED",
  "BILLING_ISSUE",
  "TEMPORARY_ENTITLEMENT_GRANT",
  "TEST",
]);

/** Events that grant or extend active access. */
const ACTIVE_EVENTS = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "UNCANCELLATION",
  "PRODUCT_CHANGE",
  "SUBSCRIPTION_EXTENDED",
  "TEMPORARY_ENTITLEMENT_GRANT",
  "TEST",
]);

/**
 * Only true expiration revokes access.
 * CANCELLATION keeps access until expiration_at_ms.
 */
const EXPIRATION_EVENT = "EXPIRATION";

/**
 * Play / store transaction identifiers (order ids). Not Play Billing
 * purchase_token.
 * @param {object} event RevenueCat webhook event
 * @return {string[]}
 */
function buildTransactionTokens(event) {
  const t = [];
  if (event.original_transaction_id) {
    t.push(String(event.original_transaction_id));
  }
  if (event.transaction_id &&
      String(event.transaction_id) !==
      String(event.original_transaction_id)) {
    t.push(String(event.transaction_id));
  }
  return t;
}

/**
 * @param {number|string|undefined|null} raw
 * @return {number|null} epoch milliseconds
 */
function coerceMillis(raw) {
  if (raw == null || raw === "") return null;
  const n = typeof raw === "string" ? parseFloat(raw) : Number(raw);
  if (!Number.isFinite(n) || n <= 0) return null;
  if (n < 1e12) return Math.round(n * 1000);
  return Math.round(n);
}

/**
 * @param {object} event RevenueCat webhook event
 * @return {number|null} purchased_at in ms
 */
function purchasedAtMillisFromEvent(event) {
  let ms = coerceMillis(event.purchased_at_ms);
  if (ms != null) return ms;
  ms = coerceMillis(event.purchased_at);
  if (ms != null) return ms;
  return null;
}

/**
 * @param {object} event RevenueCat webhook event
 * @return {number|null} event time in ms
 */
function eventTimestampMillisFromEvent(event) {
  let ms = coerceMillis(event.event_timestamp_ms);
  if (ms != null) return ms;
  ms = coerceMillis(event.event_timestamp);
  if (ms != null) return ms;
  return null;
}

/**
 * Subscription start (store); good for firstPurchaseAt on renewals.
 * @param {object} event RevenueCat webhook event
 * @return {number|null}
 */
function originalPurchaseMillisFromEvent(event) {
  let ms = coerceMillis(event.original_purchase_date_ms);
  if (ms != null) return ms;
  ms = coerceMillis(event.original_purchased_at_ms);
  if (ms != null) return ms;
  if (typeof event.original_purchase_date === "string") {
    const d = Date.parse(event.original_purchase_date);
    if (Number.isFinite(d)) return d;
  }
  return null;
}

/**
 * Infer entitlement slug from product id when RC sends empty entitlement_ids.
 * @param {string|null|undefined} productId
 * @return {string|null}
 */
function entitlementIdFromProductId(productId) {
  if (!productId) return null;
  const s = String(productId).toLowerCase();
  if (s.includes("elite")) return "elite";
  if (s.includes("premium")) return "premium";
  if (s.includes("deluxe")) return "deluxe";
  if (s.includes("starter")) return "starter";
  return null;
}

/**
 * @param {object} event RevenueCat event
 * @param {string|null|undefined} productId SKU
 * @return {object} entitlementId and entitlementIds
 */
function resolveEntitlementFields(event, productId) {
  const raw = Array.isArray(event.entitlement_ids) ?
    event.entitlement_ids.filter(Boolean) : [];
  if (raw.length > 0) {
    return {entitlementId: raw[0], entitlementIds: raw};
  }
  if (event.entitlement_id) {
    const id = String(event.entitlement_id);
    return {entitlementId: id, entitlementIds: [id]};
  }
  const inferred = entitlementIdFromProductId(productId);
  if (inferred) {
    return {entitlementId: inferred, entitlementIds: [inferred]};
  }
  return {entitlementId: null, entitlementIds: []};
}

/** Newly added on 2024-06-17:
 * Extract the messaging limit from entitlementFeatures payload.
 * @param {object|null} entitlementFeatures
 * @return {number|null}
 */
function getMessagingLimitFromEntitlementFeatures(entitlementFeatures) {
  const messaging = entitlementFeatures && entitlementFeatures.messaging;
  if (!messaging) return null;
  const rawLimit = messaging.limit;
  const parsed = typeof rawLimit === "number" ? rawLimit : Number(rawLimit);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : null;
}

/**
 * Newly added from here on 2024-06-17:
 * Fetch entitlementFeatures for a given entitlementId from Subscriptions/entitlementFeatures doc.
 * Returns the tier-specific features (e.g. deluxe, elite, premium, etc).
 * @param {FirebaseFirestore.Firestore} db
 * @param {string|null} entitlementId
 * @return {Promise<object|null>}
 */
async function fetchEntitlementFeatures(db, entitlementId) {
  if (!entitlementId) return null;
  try {
    const tierKey = String(entitlementId).toLowerCase().trim();
    if (!tierKey) return null;

    const docRef = db.collection("Subscriptions").doc("entitlementFeatures");
    const docSnap = await docRef.get();

    if (!docSnap.exists) {
      logger.info("Subscriptions/entitlementFeatures doc not found");
      return null;
    }

    const data = docSnap.data();
    if (!data) return null;

    const tierData = data[tierKey];
    if (!tierData) {
      logger.info("Entitlementid features not found for tier", {
        tierKey,
      });
      return null;
    }

    return tierData;
  } catch (error) {
    logger.error("Error fetching entitlementFeatures", {
      entitlementId,
      error: error.message,
    });
    return null;
  }
}
// Upto here it is newly added

/**
 * RevenueCat subscription webhook handler.
 *
 * - Writes each subscription event to root `Subscription_logs` only.
 * - Updates Users/{uid}/Subscription/current for expiry, plan-wise access, UI.
 *
 * Google Play: RevenueCat does **not** send Billing `purchase_token`.
 * `tokens` + string `purchase_token` on `Subscription/current` come from the
 * Android app (Play Billing) only. The webhook sets `subscriptionLogEventId`
 * on `Subscription/current` to the RevenueCat `event.id` (same as the
 * `Subscription_logs` document id) so the app can merge device-only fields
 * into that single log row.
 *
 * There are no literal `firstPurchaseAt` / `lastPurchaseAt` keys in the JSON.
 * They are derived from `purchased_at_ms` (primary) and
 * `event_timestamp_ms` (fallback): `lastPurchaseAt` = that instant for this
 * event; `firstPurchaseAt` on `Subscription/current` is set on
 * INITIAL_PURCHASE/TEST or backfilled once if missing.
 *
 * Set webhook URL in RevenueCat and Bearer token below.
 */
// URL: https://us-central1-vioraa.cloudfunctions.net/revenuecatSubscriptionWebhook
exports.revenuecatSubscriptionWebhook = onRequest({region: "us-central1"},
    async (req, res) => {
      try {
        const authHeader = req.headers.authorization;
        const expectedToken = "Bearer " +
          "e53311de270cde2936453354368b7e193077bc78b714c2831969cf2989243a1d";

        if (authHeader !== expectedToken) {
          logger.warn("Unauthorized RevenueCat subscription webhook", {
            received: authHeader ? "present" : "missing",
          });
          return res.status(401).send("Unauthorized");
        }

        const db = admin.firestore();
        const event = req.body?.event;
        if (!event || !event.type) {
          logger.error("Missing event or event.type", req.body);
          return res.status(400).send("Invalid payload");
        }

        if (!SUBSCRIPTION_EVENT_TYPES.has(event.type)) {
          return res.status(200).send("Ignored event type");
        }

        const userId = event.app_user_id;
        if (!userId) {
          if (event.type === "TRANSFER") {
            return res.status(200)
                .send("Transfer event skipped (no app_user_id)");
          }
          logger.error("Missing app_user_id", event);
          return res.status(400).send("Invalid payload");
        }

        const txn = event.transaction_id || "none";
        const eventId = event.id || `evt_${Date.now()}_${txn}`;

        /**
         * Play Store order id from webhook (`GPA...`); not Billing
         * purchase_token.
         */
        const googlePlayOrderId =
          event.store === "PLAY_STORE" ? (event.transaction_id || null) : null;

        const productIdForEntitlement =
          event.new_product_id || event.product_id || null;
        const resolved = resolveEntitlementFields(
            event, productIdForEntitlement);
        const resolvedEntitlementId = resolved.entitlementId;
        const resolvedEntitlementIds = resolved.entitlementIds;
        const storeOrderIds = buildTransactionTokens(event);
        const purchasedMs = purchasedAtMillisFromEvent(event);
        const eventMs = eventTimestampMillisFromEvent(event);
        const purchaseTimestamp = purchasedMs != null ?
          admin.firestore.Timestamp.fromMillis(purchasedMs) :
          null;
        const eventTimestamp = eventMs != null ?
          admin.firestore.Timestamp.fromMillis(eventMs) :
          null;

        const lastPurchaseResolved =
          purchaseTimestamp || eventTimestamp ||
          admin.firestore.Timestamp.now();
        const logLastPurchaseAt = lastPurchaseResolved;
        const purchasedAtMsForDoc = purchasedMs ?? eventMs ?? null;

        const statusFromEvent = ACTIVE_EVENTS.has(event.type) ? "active" :
          event.type === EXPIRATION_EVENT ? "expired" :
          event.type === "CANCELLATION" ? "cancelled" : null;

        const logRef = db.collection("Subscription_logs").doc(eventId);
        const userCurrentRef = db.collection("Users").doc(userId)
            .collection("Subscription").doc("current");

        const runUpdate = async () => {
          const currentSnap = await userCurrentRef.get();
          const existingFirst = currentSnap.get("firstPurchaseAt");

          const originalMs = originalPurchaseMillisFromEvent(event);
          const originalPurchaseTs = originalMs != null ?
            admin.firestore.Timestamp.fromMillis(originalMs) :
            null;

          const logFirstForRow =
            (event.type === "INITIAL_PURCHASE" || event.type === "TEST") ?
              (originalPurchaseTs || logLastPurchaseAt) :
              (existingFirst || originalPurchaseTs || null);

          const logDoc = {
            eventId: eventId,
            eventType: event.type,
            appUserId: userId,
            originalAppUserId: event.original_app_user_id || null,
            productId: event.product_id || null,
            newProductId: event.new_product_id || null,
            entitlementIds: resolvedEntitlementIds.length ?
              resolvedEntitlementIds :
              (event.entitlement_ids || []),
            entitlementId: resolvedEntitlementId,
            storeOrderIds: storeOrderIds,
            lastPurchaseAt: logLastPurchaseAt,
            firstPurchaseAt: logFirstForRow,
            periodType: event.period_type || null,
            purchasedAtMs: purchasedAtMsForDoc,
            expirationAtMs: event.expiration_at_ms ?? null,
            transactionId: event.transaction_id || null,
            originalTransactionId: event.original_transaction_id || null,
            googlePlayOrderId: googlePlayOrderId,
            store: event.store || null,
            environment: event.environment || null,
            price: event.price ?? null,
            priceInPurchasedCurrency: event.price_in_purchased_currency ?? null,
            currency: event.currency || null,
            countryCode: event.country_code || null,
            cancelReason: event.cancel_reason || null,
            expirationReason: event.expiration_reason || null,
            renewalNumber: event.renewal_number ?? null,
            eventTimestampMs: eventMs ?? null,
            serverReceivedAt:
              admin.firestore.FieldValue.serverTimestamp(),
            status: statusFromEvent,
          };

          const batch = db.batch();

          batch.set(logRef, logDoc, {merge: true});

          const isActiveEvent = ACTIVE_EVENTS.has(event.type);

          if (isActiveEvent && (event.product_id || event.new_product_id)) {
            const productId = event.new_product_id || event.product_id;
            const expirationAtMs = event.expiration_at_ms;
            const expirationTime = expirationAtMs ?
              admin.firestore.Timestamp.fromMillis(expirationAtMs) :
              null;

            let firstPurchaseTs = null;
            if (event.type === "INITIAL_PURCHASE" || event.type === "TEST") {
              firstPurchaseTs = originalPurchaseTs || lastPurchaseResolved;
            } else if (!existingFirst) {
              firstPurchaseTs = originalPurchaseTs || lastPurchaseResolved;
            }

            const eid = resolvedEntitlementId;
            const eids = resolvedEntitlementIds.length ?
              resolvedEntitlementIds :
              (eid ? [eid] : []);

            // Fetch entitlementFeatures based on entitlementId.
            // Populates entitlementFeatures field on Subscription/current for
            // active events, storing tier-specific features (deluxe, elite,
            // premium, etc.) for UI and access control.
            const entitlementFeatures =
              await fetchEntitlementFeatures(db, eid);
            // Newly added on 2024-06-17:
            // Extract messaging limit from entitlementFeatures to update
            // user's coins.
            const messagingLimit =
              getMessagingLimitFromEntitlementFeatures(entitlementFeatures);

            const activePatch = {
              product_id: productId,
              productId: productId,
              expiration_time: expirationTime,
              expirationTime: expirationTime,
              expiry_date: expirationTime,
              expires_at: expirationTime,
              entitlementId: eid || null,
              entitlement_ids: eids,
              // newly added
              entitlementFeatures: entitlementFeatures || null,
              entitlement_status: "active",
              status: "active",
              willRenew: true,
              subscriptionOwnerId: userId,
              subscriptionLogEventId: eventId,
              googlePlayOrderId: googlePlayOrderId || null,
              entitlement_updated_time:
                admin.firestore.FieldValue.serverTimestamp(),
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
              lastPurchaseAt: lastPurchaseResolved,
            };
            if (firstPurchaseTs) {
              activePatch.firstPurchaseAt = firstPurchaseTs;
            }
            // Completely replace the old subscription instead of merging
            // This ensures old fields don't persist when rewriting subscription
            batch.set(userCurrentRef, activePatch, {merge: false});
            // Newly Added on 2024-06-17: If messaging limit is present, update user's coins.
            if (messagingLimit != null) {
              batch.set(db.collection("Users").doc(userId), {
                coins: messagingLimit,
                lastDate: lastPurchaseResolved,
                updated_at: admin.firestore.FieldValue.serverTimestamp(),
              }, {merge: true});
            } else {
              logger.info("Messaging limit missing in entitlementFeatures; skipping coins update", {
                userId,
                entitlementId: eid,
              });
            }
          } else if (event.type === "EXPIRATION") {
            // Avoid overwriting a newer active subscription with a late expiration
            // If the currently stored `lastPurchaseAt` is newer than this
            // expiration event's timestamp, skip applying the expiration.
            try {
              const currentEventId = currentSnap.get("subscriptionLogEventId");
              const currentLast = currentSnap.get("lastPurchaseAt");
              const eventTs = eventMs || null;

              const shouldApplyExpiry = (() => {
                if (!currentLast || !eventTs) return true;
                try {
                  const currMs = (typeof currentLast.toMillis === "function") ?
                    currentLast.toMillis() : null;
                  if (currMs && currMs > eventTs) {
                    return false;
                  }
                } catch (e) {
                  // Fall through to apply expiry if we can't compare
                }
                // If subscriptionLogEventId explicitly matches this eventId,
                // allow applying expiry (this is the expected case).
                if (currentEventId && String(currentEventId) !== String(eventId)) {
                  // If current event id differs but timestamps don't indicate
                  // a newer subscription, still apply expiry.
                }
                return true;
              })();

              if (!shouldApplyExpiry) {
                logger.info("Skipping expiration: newer subscription present", {
                  userId,
                  eventId,
                });
              } else {
                batch.set(userCurrentRef, {
                  entitlement_status: "expired",
                  status: "expired",
                  willRenew: false,
                  subscriptionOwnerId: null,
                  product_id: admin.firestore.FieldValue.delete(),
                  productId: admin.firestore.FieldValue.delete(),
                  expiration_time: admin.firestore.FieldValue.delete(),
                  expirationTime: admin.firestore.FieldValue.delete(),
                  expiry_date: admin.firestore.FieldValue.delete(),
                  expires_at: admin.firestore.FieldValue.delete(),
                  purchase_token: admin.firestore.FieldValue.delete(),
                  tokens: admin.firestore.FieldValue.delete(),
                  googlePlayOrderId: admin.firestore.FieldValue.delete(),
                  cancelReason: admin.firestore.FieldValue.delete(),
                  subscriptionCancelledAt: admin.firestore.FieldValue.delete(),
                  entitlementId: admin.firestore.FieldValue.delete(),
                  entitlement_ids: admin.firestore.FieldValue.delete(),
                  // newly added
                  entitlementFeatures: admin.firestore.FieldValue.delete(),
                  firstPurchaseAt: admin.firestore.FieldValue.delete(),
                  lastPurchaseAt: admin.firestore.FieldValue.delete(),
                  subscriptionLogEventId: admin.firestore.FieldValue.delete(),
                  entitlement_updated_time:
                    admin.firestore.FieldValue.serverTimestamp(),
                  updated_at: admin.firestore.FieldValue.serverTimestamp(),
                }, {merge: true});
              }
            } catch (err) {
              logger.error("Error while processing expiration guard", err);
              batch.set(userCurrentRef, {
                entitlement_status: "expired",
                status: "expired",
                willRenew: false,
                subscriptionOwnerId: null,
                product_id: admin.firestore.FieldValue.delete(),
                productId: admin.firestore.FieldValue.delete(),
                expiration_time: admin.firestore.FieldValue.delete(),
                expirationTime: admin.firestore.FieldValue.delete(),
                expiry_date: admin.firestore.FieldValue.delete(),
                expires_at: admin.firestore.FieldValue.delete(),
                purchase_token: admin.firestore.FieldValue.delete(),
                tokens: admin.firestore.FieldValue.delete(),
                googlePlayOrderId: admin.firestore.FieldValue.delete(),
                cancelReason: admin.firestore.FieldValue.delete(),
                subscriptionCancelledAt: admin.firestore.FieldValue.delete(),
                entitlementId: admin.firestore.FieldValue.delete(),
                entitlement_ids: admin.firestore.FieldValue.delete(),
                // newly added
                entitlementFeatures: admin.firestore.FieldValue.delete(),
                firstPurchaseAt: admin.firestore.FieldValue.delete(),
                lastPurchaseAt: admin.firestore.FieldValue.delete(),
                subscriptionLogEventId: admin.firestore.FieldValue.delete(),
                entitlement_updated_time:
                  admin.firestore.FieldValue.serverTimestamp(),
                updated_at: admin.firestore.FieldValue.serverTimestamp(),
              }, {merge: true});
            }
          } else if (event.type === "CANCELLATION") {
            const productId = event.new_product_id || event.product_id;
            const expirationAtMs = event.expiration_at_ms;
            const expirationTime = expirationAtMs ?
              admin.firestore.Timestamp.fromMillis(expirationAtMs) :
              null;
            const cancelledAtMs = event.event_timestamp_ms;
            const cancelledAt = cancelledAtMs ?
              admin.firestore.Timestamp.fromMillis(cancelledAtMs) :
              admin.firestore.FieldValue.serverTimestamp();
            const cancelEid = resolvedEntitlementId;
            const cancelEids = resolvedEntitlementIds.length ?
              resolvedEntitlementIds :
              (cancelEid ? [cancelEid] : []);
            const cancelLastAt =
                purchaseTimestamp || eventTimestamp || cancelledAt;

            // Fetch entitlementFeatures for cancellation event
            // newly added
            const cancelEntitlementFeatures =
              await fetchEntitlementFeatures(db, cancelEid);

            const cancelPatch = {
              product_id: productId,
              productId: productId,
              expiration_time: expirationTime,
              expirationTime: expirationTime,
              expiry_date: expirationTime,
              expires_at: expirationTime,
              entitlementId: cancelEid || null,
              entitlement_ids: cancelEids,
              // newly added
              entitlementFeatures: cancelEntitlementFeatures || null,
              entitlement_status: "active",
              status: "active",
              willRenew: false,
              cancelReason: event.cancel_reason || null,
              subscriptionCancelledAt: cancelledAt,
              subscriptionOwnerId: userId,
              googlePlayOrderId: googlePlayOrderId || null,
              entitlement_updated_time:
                admin.firestore.FieldValue.serverTimestamp(),
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            };
            if (cancelLastAt) {
              cancelPatch.lastPurchaseAt = cancelLastAt;
            }
            batch.set(userCurrentRef, cancelPatch, {merge: true});
          }

          await batch.commit();
        };

        const existingLog = await logRef.get();
        if (existingLog.exists) {
          logger.info("Subscription event already processed", {eventId});
          return res.status(200).send("Already processed");
        }

        await runUpdate();

        logger.info("Subscription webhook processed", {
          eventId,
          eventType: event.type,
          userId,
          productId: event.product_id || event.new_product_id,
        });

        return res.status(200).send("Success");
      } catch (error) {
        logger.error("RevenueCat subscription webhook error", error);
        return res.status(500).send("Internal error");
      }
    });
