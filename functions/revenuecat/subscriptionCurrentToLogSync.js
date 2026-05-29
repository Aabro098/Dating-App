const functions = require("firebase-functions/v1");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

/**
 * Normalize Play purchase_token from Firestore (string or legacy array).
 * @param {FirebaseFirestore.DocumentData|undefined} data
 * @return {string|null}
 */
function purchaseTokenString(data) {
  if (!data) return null;
  const pt = data.purchase_token;
  if (typeof pt === "string" && pt.trim()) return pt.trim();
  if (Array.isArray(pt) && pt.length) {
    const s = String(pt[0]).trim();
    return s || null;
  }
  return null;
}

/**
 * On `Subscription/current` write, merge purchase_token and first/last purchase
 * times into `Subscription_logs/{subscriptionLogEventId}` (Admin SDK; clients
 * may be denied write on Subscription_logs).
 */
exports.onSubscriptionCurrentWritten = functions.region("us-central1")
    .firestore.document("Users/{userId}/Subscription/current")
    .onWrite(async (change, context) => {
      if (!change.after.exists) return null;
      const data = change.after.data();
      if (!data) return null;

      const logEventId = data.subscriptionLogEventId != null ?
        String(data.subscriptionLogEventId).trim() : "";
      if (!logEventId) return null;

      const db = admin.firestore();
      const logRef = db.collection("Subscription_logs").doc(logEventId);
      const logSnap = await logRef.get();
      if (!logSnap.exists) {
        logger.info("subscriptionCurrentToLogSync: log missing, skip", {
          userId: context.params.userId,
          logEventId,
        });
        return null;
      }

      const patch = {};
      const tokenStr = purchaseTokenString(data);
      const existing = logSnap.data() || {};
      const existingTok = purchaseTokenString(existing);

      if (tokenStr && tokenStr !== existingTok) {
        patch.purchase_token = tokenStr;
        patch.tokens = [tokenStr];
        patch.purchase_token_updated_at =
          admin.firestore.FieldValue.serverTimestamp();
      }

      if (data.firstPurchaseAt != null) {
        patch.firstPurchaseAt = data.firstPurchaseAt;
      }
      if (data.lastPurchaseAt != null) {
        patch.lastPurchaseAt = data.lastPurchaseAt;
      }

      if (Object.keys(patch).length === 0) return null;

      try {
        await logRef.set(patch, {merge: true});
        logger.info("subscriptionCurrentToLogSync: merged", {
          userId: context.params.userId,
          logEventId,
          keys: Object.keys(patch),
        });
      } catch (err) {
        logger.error("subscriptionCurrentToLogSync failed", err);
      }
      return null;
    });
