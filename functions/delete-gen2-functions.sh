#!/usr/bin/env bash
# Run ONCE before first Gen1 deploy if you had Gen2 functions and see:
#   "Cannot set CPU ... because they are GCF gen 1"
#
# Requires: firebase login, firebase use vioraa

set -euo pipefail
REGION="us-central1"

for name in notifications-sendPush revenuecatWebhook revenuecatSubscriptionWebhook onMessageCreated; do
  echo "Deleting (ignore errors if missing): $name"
  firebase functions:delete "$name" --region "$REGION" --force || true
done

echo "Done. Deploy: cd .. && ./deploy-functions.sh"
