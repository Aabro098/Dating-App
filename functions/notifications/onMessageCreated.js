const functions = require("firebase-functions/v1");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

/**
 * Firestore trigger (Gen 1): new doc in Messages/{messageId} → FCM to receiver.
 */
exports.onMessageCreated = functions.region("us-central1")
    .firestore.document("Messages/{messageId}")
    .onCreate(async (snapshot, context) => {
      const messageId = context.params.messageId;
      const message = snapshot.data();
      if (!message) return;

      const senderId = message.uid;
      const receiverId = message.receiver;
      const text = message.text || "";

      if (senderId === receiverId) return;

      try {
        const [senderDoc, receiverDoc] = await Promise.all([
          admin.firestore().collection("Users").doc(senderId).get(),
          admin.firestore().collection("Users").doc(receiverId).get(),
        ]);

        const senderName = senderDoc.exists ?
          (senderDoc.data()?.name || "Someone") : "Someone";
        const receiverData = receiverDoc.exists ? receiverDoc.data() : null;
        const fcmToken = receiverData?.fcmToken;

        // Bot/admin profiles store fcmToken="Admin". In that case, notify Admin
        // topic
        // so admins can open the bot inbox (BotChatsScreen).
        const isAdminTopic = fcmToken === "Admin";

        if (
          !fcmToken ||
          fcmToken === "null" ||
          (!isAdminTopic && fcmToken.length < 100)
        ) {
          logger.info("Skipping notification: invalid/missing receiver token", {
            receiverId,
            hasToken: !!fcmToken,
            tokenType: isAdminTopic ? "AdminTopic" : "Direct",
          });
          return;
        }

        const body = text.length > 100 ? text.substring(0, 100) + "..." : text;
        const title = isAdminTopic ?
          `BOTs Chat from ${senderName}` :
          `Message from ${senderName}`;

        // Unique id + tag per message so Android does not replace queued
        // notifications when the device was offline (constant id caused only
        // the last message to show after reconnect).
        const messagePayload = {
          notification: {title, body},
          data: {
            click_action: "FLUTTER_NOTIFICATION_CLICK",
            id: String(messageId),
            status: "done",
            // For user-to-user messages: open MessagesScreen(uId=senderId)
            // For user-to-bot messages (Admin topic):
            // open BotChatsScreen(botId=receiverId)
            uid: isAdminTopic ? receiverId : senderId,
          },
          ...(isAdminTopic ? {topic: "Admin"} : {token: fcmToken}),
          android: {
            priority: "high",
            // Omit collapseKey so each message is delivered when back online.
            notification: {
              sound: "default",
              clickAction: "FLUTTER_NOTIFICATION_CLICK",
              // Distinct tag = separate status-bar entries (same tag replaces).
              tag: `viora_msg_${messageId}`,
            },
          },
          apns: {
            headers: {"apns-priority": "10"},
            payload: {aps: {sound: "default"}},
          },
        };

        const result = await admin.messaging().send(messagePayload);
        logger.info("Message notification sent", {
          messageId: result,
          receiverId,
          senderName,
        });
      } catch (error) {
        logger.error("Failed to send message notification", {
          error: error.message,
          receiverId,
          senderId,
        });
      }
    });
