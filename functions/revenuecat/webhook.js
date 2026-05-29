const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");

/**
 * RevenueCat webhook (Gen 1): NON_RENEWING_PURCHASE → coins.
 * URL after deploy: https://us-central1-vioraa.cloudfunctions.net/revenuecatWebhook
 */
exports.revenuecatWebhook = functions.region("us-central1")
    .https.onRequest(async (req, res) => {
      try {
        const authHeader = req.headers.authorization;
        const expectedToken =
      "Bearer b5de175e394aee9bdf9c645a77f4d2c1a3f3f385b7f534bdbc4a2d8ad633c981";

        if (authHeader !== expectedToken) {
          logger.warn("Unauthorized RevenueCat webhook call", {
            received: authHeader,
          });
          return res.status(401).send("Unauthorized");
        }
        const db = admin.firestore();

        const event = req.body.event;

        if (event.type !== "NON_RENEWING_PURCHASE") {
          return res.status(200).send("Ignored event type");
        }

        const userId = event.app_user_id;
        const productId = event.product_id;
        const transactionId = event.transaction_id;
        const price = event.price_in_purchased_currency;

        if (!userId || !transactionId || !productId) {
          logger.error("Missing required fields", event);
          return res.status(400).send("Invalid payload");
        }

        const txnRef = db.collection("Transactions").doc(transactionId);
        const txnSnap = await txnRef.get();

        if (txnSnap.exists) {
          logger.info("Transaction already processed", transactionId);
          return res.status(200).send("Already processed");
        }

        const coins = extractCoinAmount(productId);

        const userRef = db.collection("Users").doc(userId);

        await db.runTransaction(async (t) => {
          t.set(txnRef, {
            transactionId,
            uId: userId,
            planId: productId,
            coins: coins,
            price: price,
            date: admin.firestore.FieldValue.serverTimestamp(),
            source: "revenuecat",
          });

          t.update(userRef, {
            coins: admin.firestore.FieldValue.increment(coins),
          });
        });

        logger.info("Coins credited successfully", {
          userId,
          transactionId,
          coins,
        });

        return res.status(200).send("Success");
      } catch (error) {
        logger.error("RevenueCat webhook error", error);
        return res.status(500).send("Internal error");
      }
    });

/**
 * @param {string} productId
 * @return {number}
 */
function extractCoinAmount(productId) {
  if (!productId) return 0;

  if (productId.includes("starter")) return 40;
  if (productId.includes("deluxe")) return 100;
  if (productId.includes("premium")) return 500;
  if (productId.includes("elite")) return 5000;

  return 0;
}
