#!/usr/bin/env bash
# One-time fix when `firebase deploy --only functions` fails with:
#   "Failed to verify the project has the correct IAM bindings"
#
# Run locally (not in CI) while logged into gcloud as Owner or Project IAM Admin:
#   gcloud auth login
#   gcloud config set project vioraa
#   chmod +x fix-functions-iam.sh && ./fix-functions-iam.sh
#
# Project number 877294522958 must match Firebase project vioraa (see firebase.json).

set -euo pipefail
PROJECT_ID="vioraa"
PROJECT_NUM="877294522958"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "ERROR: gcloud is not installed or not on your PATH."
  echo ""
  echo "  macOS:  brew install --cask google-cloud-sdk"
  echo "  Then open a new terminal and run: gcloud auth login"
  echo ""
  echo "Or add the IAM bindings in the browser (no gcloud):"
  echo "  See: functions/FUNCTIONS_DEPLOY_IAM.md  (Option B)"
  exit 1
fi

echo "Applying IAM bindings for Cloud Functions (2nd gen) on ${PROJECT_ID}..."

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:service-${PROJECT_NUM}@gcp-sa-pubsub.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${PROJECT_NUM}-compute@developer.gserviceaccount.com" \
  --role="roles/run.invoker"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${PROJECT_NUM}-compute@developer.gserviceaccount.com" \
  --role="roles/eventarc.eventReceiver"

echo "Done. Retry from repo root: ./deploy-functions.sh"
