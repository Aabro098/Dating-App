const functions = require("firebase-functions/v1");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

// Gen 1 callable — same name: notifications-sendPush (nested export).

exports.sendPush = functions.region("us-central1").https.onCall(
    async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "User must be authenticated",
        );
      }

      const token = data.token;
      const topic = data.topic;
      const title = data.title;
      const body = data.body;
      const rawData = data.data || {};

      const outData = {};
      for (const [key, value] of Object.entries(rawData)) {
        if (value !== undefined && value !== null) {
          outData[key] = String(value);
        }
      }

      if ((!token && !topic) || !title || !body) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "token OR topic, title and body are required",
        );
      }

      const message = {
        notification: {
          title,
          body,
        },
        data: outData,

        android: {
          priority: "high",
          notification: {
            sound: "default",
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        apns: {
          headers: {
            "apns-priority": "10",
          },
          payload: {
            aps: {
              sound: "default",
            },
          },
        },
      };

      if (token) {
        message.token = token;
      } else {
        message.topic = topic;
      }

      try {
        const result = await admin.messaging().send(message);
        logger.info("FCM send success", {messageId: result});
        return {success: true, messageId: result};
      } catch (error) {
        logger.error("FCM send error", {
          error: error.message,
          errorCode: error.code,
          token: token || "N/A",
          topic: topic || "N/A",
        });
        throw new functions.https.HttpsError(
            "internal",
            `Failed to send notification: ${error.message}`,
        );
      }
    },
);
