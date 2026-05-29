const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");

const JOBS_COLLECTION = "AccountDeletionJobs";

exports.accountDeletionRequest = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
      if (!context.auth || !context.auth.uid) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Authentication required.",
        );
      }

      const uid = context.auth.uid;
      const db = admin.firestore();
      const jobRef = db.collection(JOBS_COLLECTION).doc(uid);

      const hasActiveSubscription = data?.hasActiveSubscription === true;

      const activeProductIds = Array.isArray(data?.activeProductIds) ?
      data.activeProductIds
          .map((v) => String(v || "").trim())
          .filter(Boolean)
          .slice(0, 20) :
      [];

      const deletionMethod = String(data?.deletionMethod || "in_app_settings")
          .trim()
          .slice(0, 64);

      const deviceType = String(data?.deviceType || "android")
          .trim()
          .slice(0, 32);

      let response = {
        accepted: true,
        jobId: uid,
        status: "queued",
        retried: false,
      };

      await db.runTransaction(async (tx) => {
        const snap = await tx.get(jobRef);

        if (snap.exists) {
          const existing = snap.data() || {};
          const status = String(existing.status || "");

          if (status === "queued" || status === "running") {
            response = {
              accepted: true,
              jobId: uid,
              status,
              retried: false,
            };
            return;
          }
        }

        const attempts = snap.exists ? Number(snap.get("attempts") || 0) : 0;

        tx.set(
            jobRef,
            {
              uid,
              status: "queued",
              step: "queued",
              attempts: attempts + 1,
              requestedAt: admin.firestore.FieldValue.serverTimestamp(),
              startedAt: null,
              finishedAt: null,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              error: null,
              request: {
                hasActiveSubscription,
                activeProductIds,
                deletionMethod,
                deviceType,
              },
              source: "mobile_app_callable",
              triggeredByUid: uid,
              platform: deviceType,
            },
            {merge: true},
        );

        response = {
          accepted: true,
          jobId: uid,
          status: "queued",
          retried: attempts > 0,
        };
      });

      logger.info("Account deletion requested", response);

      return response;
    });

exports.accountDeletionStatus = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
      if (!context.auth || !context.auth.uid) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Authentication required.",
        );
      }

      const uid = context.auth.uid;
      const db = admin.firestore();

      const snap = await db.collection(JOBS_COLLECTION).doc(uid).get();

      if (!snap.exists) {
        return {
          exists: false,
          status: "not_found",
          completed: false,
          failed: false,
          message: "Deletion job not found.",
        };
      }

      const job = snap.data() || {};
      const status = String(job.status || "unknown");

      return {
        exists: true,
        jobId: uid,
        status,
        step: String(job.step || ""),
        completed: status === "completed",
        failed: status === "failed",
        message: getSafeErrorMessage(job),
        summary: job.summary || null,
      };
    });

function getSafeErrorMessage(job) {
  const error = job?.error;

  if (!error) return "";

  if (typeof error === "string") {
    return error.slice(0, 500);
  }

  if (typeof error === "object" && error.message) {
    return String(error.message).slice(0, 500);
  }

  return "Account deletion failed.";
}
