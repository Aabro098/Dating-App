const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");

const JOBS_COLLECTION = "AccountDeletionJobs";
const USERS_COLLECTION = "Users";
const DELETED_ACCOUNTS_COLLECTION = "DeletedAccounts";
const DELETION_CONFIRMATIONS_COLLECTION = "DeletionConfirmations";
const CHAT_ROOMS_COLLECTION = "ChatRooms";

const MESSAGES_COLLECTION = "Messages";
const DELETED_MESSAGES_COLLECTION = "DeletedMessages";

const USER_SUBCOLLECTIONS = [
  "MyFav",
  "FavOnMe",
  "CrushOnMe",
  "MyCrush",
  "Notifications",
  "Sessions",
  "Subscription",
];

const GROUP_SUBCOLLECTIONS_TO_CLEAN = [
  "MyFav",
  "CrushOnMe",
  "MyCrush",
  "FavOnMe",
  "Notifications",
];

exports.onAccountDeletionJobWrite = functions
    .region("us-central1")
    .firestore.document(`${JOBS_COLLECTION}/{uid}`)
    .onWrite(async (change, context) => {
      if (!change.after.exists) return null;

      const uid = context.params.uid;
      const data = change.after.data() || {};

      if (data.status !== "queued") return null;

      const db = admin.firestore();
      const jobRef = change.after.ref;

      const locked = await acquireJobLock(db, jobRef);
      if (!locked) return null;

      try {
        logger.info("Account deletion started", {uid});

        const summary = await runAccountDeletion(db, uid, jobRef);

        await jobRef.set(
            {
              status: "completed",
              step: "done",
              error: null,
              summary,
              finishedAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        logger.info("Account deletion completed", {uid, summary});
      } catch (error) {
        const normalized = normalizeError(error);

        logger.error("Account deletion failed", {
          uid,
          error: normalized,
        });

        await jobRef.set(
            {
              status: "failed",
              step: "failed",
              error: {
                code: normalized.code,
                message: normalized.message,
                stack: normalized.stack,
                name: normalized.name,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
              },
              finishedAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );
      }

      return null;
    });

/**
 * Acquires a lock on the deletion job to prevent concurrent processing.
 * @param {FirebaseFirestore.Firestore} db The Firestore database instance
 * @param {FirebaseFirestore.DocumentReference} jobRef Reference to the deletion job
 * @return {Promise<boolean>} True if lock acquired, false otherwise
 */
async function acquireJobLock(db, jobRef) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(jobRef);

    if (!snap.exists) return false;

    const data = snap.data() || {};

    if (data.status !== "queued") return false;

    tx.set(
        jobRef,
        {
          status: "running",
          step: "starting",
          startedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          error: null,
        },
        {merge: true},
    );

    return true;
  });
}

/**
 * Runs the complete account deletion workflow.
 * @param {FirebaseFirestore.Firestore} db The Firestore database instance
 * @param {string} uid User ID to delete
 * @param {FirebaseFirestore.DocumentReference} jobRef Reference to the deletion job
 * @return {Promise<Object>} Summary of deletion operations
 */
async function runAccountDeletion(db, uid, jobRef) {
  const summary = {
    confirmationLogged: false,
    archivedUserData: false,
    archivedSubcollectionDocs: 0,
    archivedChatRooms: 0,
    archivedMessages: 0,
    archivedTopLevelMessages: 0,
    deletedTopLevelMessages: 0,
    deletedChatRooms: 0,
    deletedChatMessages: 0,
    deletedOwnSubcollectionDocs: 0,
    deletedExternalRefs: 0,
    clearedPresenceAndToken: false,
    deletedUserDoc: false,
    deletedAuthUser: false,
  };

  const jobSnap = await jobRef.get();
  const request = jobSnap.get("request") || {};

  await updateJobStep(jobRef, "log_deletion_confirmation");
  await logDeletionConfirmation(db, uid, request);
  summary.confirmationLogged = true;

  await updateJobStep(jobRef, "archive_user_data");
  const archiveSummary = await archiveUserDataForDeletion(db, uid);
  summary.archivedUserData = true;
  summary.archivedSubcollectionDocs = archiveSummary.archivedSubcollectionDocs;
  summary.archivedChatRooms = archiveSummary.archivedChatRooms;
  summary.archivedMessages = archiveSummary.archivedMessages;

  await updateJobStep(jobRef, "archive_and_delete_top_level_messages");
  const messagesSummary = await archiveAndDeleteUserMessages(db, uid);
  summary.archivedTopLevelMessages = messagesSummary.archivedMessages;
  summary.deletedTopLevelMessages = messagesSummary.deletedMessages;

  await updateJobStep(jobRef, "delete_chat_rooms");
  const chatSummary = await deleteUserChatRooms(db, uid);
  summary.deletedChatRooms = chatSummary.deletedChatRooms;
  summary.deletedChatMessages = chatSummary.deletedChatMessages;

  await updateJobStep(jobRef, "delete_user_subcollections");
  summary.deletedOwnSubcollectionDocs = await deleteUserSubcollections(
      db,
      uid,
      USER_SUBCOLLECTIONS,
  );

  await updateJobStep(jobRef, "remove_user_from_other_docs");
  summary.deletedExternalRefs = await removeUserFromOthersData(
      db,
      uid,
      GROUP_SUBCOLLECTIONS_TO_CLEAN,
  );

  await updateJobStep(jobRef, "clear_presence_and_token");
  await setUserOfflineAndClearToken(db, uid);
  summary.clearedPresenceAndToken = true;

  await updateJobStep(jobRef, "delete_user_doc");
  await db.collection(USERS_COLLECTION).doc(uid).delete();
  summary.deletedUserDoc = true;

  // await updateJobStep(jobRef, "delete_auth_user");
  // summary.deletedAuthUser = await deleteAuthUser(uid);
  // Keep authentication data in Firebase Auth - only delete from Firestore
  summary.deletedAuthUser = false;

  return summary;
}

/**
 * Updates the current step of the deletion job.
 * @param {FirebaseFirestore.DocumentReference} jobRef Reference to the deletion job
 * @param {string} step The step name to set
 * @return {Promise<void>}
 */
async function updateJobStep(jobRef, step) {
  await jobRef.set(
      {
        step,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
  );
}

/**
 * Logs deletion confirmation record in the database.
 * @param {FirebaseFirestore.Firestore} db The Firestore database instance
 * @param {string} uid User ID being deleted
 * @param {Object} request The deletion request data
 * @return {Promise<void>}
 */
async function logDeletionConfirmation(db, uid, request) {
  const userRef = db.collection(USERS_COLLECTION).doc(uid);
  const subscriptionRef = userRef.collection("Subscription").doc("current");

  const [userSnap, subscriptionSnap, authUser] = await Promise.all([
    userRef.get(),
    subscriptionRef.get(),
    admin.auth().getUser(uid).catch(() => null),
  ]);

  const userData = userSnap.exists ? userSnap.data() || {} : {};
  const subscriptionData = subscriptionSnap.exists ?
    subscriptionSnap.data() || {} :
    {};

  const hasActiveSubscription = request.hasActiveSubscription === true;

  const activeProductIds = Array.isArray(request.activeProductIds) ?
    request.activeProductIds.map(String).filter(Boolean).slice(0, 20) :
    [];

  const deletionMethod = String(request.deletionMethod || "in_app_settings")
      .trim()
      .slice(0, 64);

  const deviceType = String(request.deviceType || "android").trim().slice(0, 32);

  const email = authUser?.email || stringOrNull(userData.email);
  const phone = authUser?.phoneNumber || stringOrNull(userData.phone);
  const identifier = phone || email || uid;

  const providerIds = Array.isArray(authUser?.providerData) ?
    authUser.providerData
        .map((p) => stringOrNull(p.providerId))
        .filter(Boolean) :
    [];

  const productId =
    stringOrNull(subscriptionData.productId) ||
    stringOrNull(subscriptionData.product_id) ||
    activeProductIds[0] ||
    null;

  await db.collection(DELETION_CONFIRMATIONS_COLLECTION).doc(uid).set(
      {
        uid,
        confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
        deletionRequestedAt: admin.firestore.FieldValue.serverTimestamp(),

        identifier,
        identifiers: {
          phone,
          email,
          primary: identifier,
          providerIds,
        },

        email,
        phone,

        device_type: deviceType,
        platform: deviceType,
        deletionMethod,
        recordedBy: "accountDeletionRequest",

        location: {
          city: stringOrNull(userData.city),
          latitude: numberOrNull(userData.latitude),
          longitude: numberOrNull(userData.longitude),
        },

        hadActiveSubscription: hasActiveSubscription,
        activeSubscriptionIds: activeProductIds,
        acceptedSubscriptionPolicy: hasActiveSubscription,

        subscription: {
          hasActiveSubscription,
          activeProductIds,
          productId,
          renewal: {
            willRenew: toNullableBool(subscriptionData.willRenew),
            expirationTime:
            subscriptionData.expiration_time ||
            subscriptionData.expirationTime ||
            subscriptionData.expires_at ||
            null,
            renewalNumber:
            subscriptionData.renewal_number ||
            subscriptionData.renewalNumber ||
            null,
          },
          subscription_start_time: subscriptionData.firstPurchaseAt || null,
          subscription_last_purchase_time: subscriptionData.lastPurchaseAt || null,
        },
      },
      {merge: true},
  );
}

async function archiveAndDeleteUserMessages(db, uid) {
  const summary = {
    archivedMessages: 0,
    deletedMessages: 0,
  };

  const sentSnap = await db
      .collection(MESSAGES_COLLECTION)
      .where("uid", "==", uid)
      .get();

  const receivedSnap = await db
      .collection(MESSAGES_COLLECTION)
      .where("receiver", "==", uid)
      .get();

  const docsById = new Map();

  for (const doc of sentSnap.docs) {
    docsById.set(doc.id, doc);
  }

  for (const doc of receivedSnap.docs) {
    docsById.set(doc.id, doc);
  }

  const docs = Array.from(docsById.values());

  if (!docs.length) return summary;

  for (let i = 0; i < docs.length; i += 450) {
    const batch = db.batch();
    const chunk = docs.slice(i, i + 450);

    for (const doc of chunk) {
      const data = doc.data() || {};

      const deletedMessageRef = db
          .collection(DELETED_MESSAGES_COLLECTION)
          .doc(doc.id);

      batch.set(
          deletedMessageRef,
          {
            ...data,
            deletedBecauseOfUid: uid,
            archivedAt: admin.firestore.FieldValue.serverTimestamp(),
            deletedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true},
      );

      batch.delete(doc.ref);

      summary.archivedMessages += 1;
      summary.deletedMessages += 1;
    }

    await batch.commit();
  }

  return summary;
}

async function archiveUserDataForDeletion(db, uid) {
  const userRef = db.collection(USERS_COLLECTION).doc(uid);
  const archiveRef = db.collection(DELETED_ACCOUNTS_COLLECTION).doc(uid);

  const userSnap = await userRef.get();

  const summary = {
    archivedSubcollectionDocs: 0,
    archivedChatRooms: 0,
    archivedMessages: 0,
  };

  if (!userSnap.exists) {
    await archiveRef.set(
        {
          oldUid: uid,
          deletedAt: admin.firestore.FieldValue.serverTimestamp(),
          deletionReason: "user_requested",
          userDocumentMissing: true,
        },
        {merge: true},
    );

    return summary;
  }

  const userData = userSnap.data() || {};

  await archiveRef.set(
      {
        ...userData,
        oldUid: uid,
        phoneNumber: userData.phone || null,
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        scheduledPermanentDeletionAt: new Date(
            Date.now() + 30 * 24 * 60 * 60 * 1000,
        ).toISOString(),
        deletionReason: "user_requested",
      },
      {merge: true},
  );

  for (const collectionName of USER_SUBCOLLECTIONS) {
    const count = await copySubcollectionToArchive({
      db,
      fromRef: userRef.collection(collectionName),
      toRef: archiveRef.collection(collectionName),
    });

    summary.archivedSubcollectionDocs += count;
  }

  const chatRoomsSnap = await db
      .collection(CHAT_ROOMS_COLLECTION)
      .where("users", "array-contains", uid)
      .get();

  for (const chatDoc of chatRoomsSnap.docs) {
    await archiveRef.collection(CHAT_ROOMS_COLLECTION).doc(chatDoc.id).set(
        {
          ...chatDoc.data(),
          archivedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
    );

    summary.archivedChatRooms += 1;

    const messageCount = await copySubcollectionToArchive({
      db,
      fromRef: chatDoc.ref.collection("messages"),
      toRef: archiveRef
          .collection(CHAT_ROOMS_COLLECTION)
          .doc(chatDoc.id)
          .collection("messages"),
    });

    summary.archivedMessages += messageCount;
  }

  return summary;
}

/**
 * Copies a subcollection to archive before deletion.
 * @param {Object} params Function parameters
 * @param {FirebaseFirestore.Firestore} params.db The Firestore database instance
 * @param {FirebaseFirestore.DocumentReference} params.fromRef Source document reference
 * @param {FirebaseFirestore.DocumentReference} params.toRef Target archive reference
 * @return {Promise<number>} Number of documents copied
 */
async function copySubcollectionToArchive({db, fromRef, toRef}) {
  const snap = await fromRef.get();
  if (snap.empty) return 0;

  let copied = 0;

  for (let i = 0; i < snap.docs.length; i += 450) {
    const batch = db.batch();
    const chunk = snap.docs.slice(i, i + 450);

    for (const doc of chunk) {
      batch.set(toRef.doc(doc.id), {
        ...doc.data(),
        // archivedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      copied += 1;
    }

    await batch.commit();
  }

  return copied;
}

async function deleteUserChatRooms(db, uid) {
  const summary = {
    deletedChatRooms: 0,
    deletedChatMessages: 0,
  };

  const snap = await db
      .collection(CHAT_ROOMS_COLLECTION)
      .where("users", "array-contains", uid)
      .get();

  for (const chatDoc of snap.docs) {
    const deletedMessages = await deleteCollectionDocs(
        db,
        chatDoc.ref.collection("messages"),
    );

    summary.deletedChatMessages += deletedMessages;

    await chatDoc.ref.delete();
    summary.deletedChatRooms += 1;
  }

  return summary;
}

async function deleteUserSubcollections(db, uid, subcollections) {
  const userRef = db.collection(USERS_COLLECTION).doc(uid);
  let deleted = 0;

  for (const collectionName of subcollections) {
    deleted += await deleteCollectionDocs(db, userRef.collection(collectionName));
  }

  return deleted;
}

async function removeUserFromOthersData(db, uid, collectionNames) {
  let deleted = 0;

  for (const collectionName of collectionNames) {
    const snap = await db
        .collectionGroup(collectionName)
        .where("uid", "==", uid)
        .get();

    deleted += await deleteDocsBySnapshot(db, snap.docs);
  }

  return deleted;
}

async function setUserOfflineAndClearToken(db, uid) {
  const userRef = db.collection(USERS_COLLECTION).doc(uid);

  await userRef.set(
      {
        isOnline: false,
        fcmToken: null,
        lastOnline: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
  );
}

// async function deleteAuthUser(uid) {
//   try {
//     await admin.auth().deleteUser(uid);
//     return true;
//   } catch (error) {
//     if (String(error?.code || "") === "auth/user-not-found") {
//       return false;
//     }
//
//     throw error;
//   }
// }

async function deleteCollectionDocs(db, collectionRef) {
  const snap = await collectionRef.get();
  return deleteDocsBySnapshot(db, snap.docs);
}

async function deleteDocsBySnapshot(db, docs) {
  if (!docs.length) return 0;

  let deleted = 0;

  for (let i = 0; i < docs.length; i += 450) {
    const batch = db.batch();
    const chunk = docs.slice(i, i + 450);

    for (const doc of chunk) {
      batch.delete(doc.ref);
      deleted += 1;
    }

    await batch.commit();
  }

  return deleted;
}

function stringOrNull(value) {
  if (typeof value !== "string") return null;

  const trimmed = value.trim();
  return trimmed.length ? trimmed : null;
}

function numberOrNull(value) {
  if (typeof value === "number" && Number.isFinite(value)) return value;

  if (typeof value === "string") {
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  }

  return null;
}

function toNullableBool(value) {
  if (typeof value === "boolean") return value;

  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();

    if (normalized === "true") return true;
    if (normalized === "false") return false;
  }

  return null;
}

function normalizeError(error) {
  return {
    message: String(error?.message || error || "Unknown error").slice(0, 500),
    code: String(error?.code || "unknown"),
    stack: String(error?.stack || "").slice(0, 1500),
    name: String(error?.name || "Error"),
  };
}
