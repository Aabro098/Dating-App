// const admin = require("firebase-admin");

// // Gen 1 (Classic) functions — avoids Gen2 Cloud Run / Eventarc IAM checks that
// // often fail without Project IAM Admin. See functions/GEN1_DEPLOY_NOTES.md
// admin.initializeApp();

// exports.notifications = require("./notifications/push");
// const messageNotifications = require("./notifications/onMessageCreated");
// exports.onMessageCreated = messageNotifications.onMessageCreated;
// exports.revenuecatWebhook = require("./revenuecat/webhook").revenuecatWebhook;
// const subWebhook = require("./revenuecat/subscriptionWebhook");
// exports.revenuecatSubscriptionWebhook =
//   subWebhook.revenuecatSubscriptionWebhook;
// const subCurrentSync = require("./revenuecat/subscriptionCurrentToLogSync");
// exports.onSubscriptionCurrentWritten =
//   subCurrentSync.onSubscriptionCurrentWritten;
// const accountDeletionRequest = require("./accountDeletion/request");
// exports.accountDeletionRequest = accountDeletionRequest.accountDeletionRequest;
// const accountDeletionProcessor = require("./accountDeletion/processor");
// exports.onAccountDeletionJobWrite =
//   accountDeletionProcessor.onAccountDeletionJobWrite;

const admin = require("firebase-admin");

admin.initializeApp();

exports.notifications = require("./notifications/push");

const messageNotifications = require("./notifications/onMessageCreated");
exports.onMessageCreated = messageNotifications.onMessageCreated;

exports.revenuecatWebhook = require("./revenuecat/webhook").revenuecatWebhook;

const subWebhook = require("./revenuecat/subscriptionWebhook");
exports.revenuecatSubscriptionWebhook =
  subWebhook.revenuecatSubscriptionWebhook;

const subCurrentSync = require("./revenuecat/subscriptionCurrentToLogSync");
exports.onSubscriptionCurrentWritten =
  subCurrentSync.onSubscriptionCurrentWritten;

// Account deletion
const accountDeletionRequest = require("./accountDeletion/request");
exports.accountDeletionRequest =
  accountDeletionRequest.accountDeletionRequest;
exports.accountDeletionStatus =
  accountDeletionRequest.accountDeletionStatus;

const accountDeletionProcessor = require("./accountDeletion/processor");
exports.onAccountDeletionJobWrite =
  accountDeletionProcessor.onAccountDeletionJobWrite;
