# Gen 1 (Classic) Cloud Functions — why & what to update

## Why

Firebase **2nd gen** deploy talks to **Cloud Run + Eventarc + Pub/Sub** and the CLI often needs to **change GCP IAM** on the project. If that step fails (common without Owner / Project IAM Admin), deploy stops with:

> Failed to verify the project has the correct IAM bindings

**Gen 1** uses the older **Cloud Functions (1st gen)** stack and usually **does not** hit that same IAM verification path, so deploy tends to work with normal **Firebase** / **Cloud Functions Developer** access.

## One-time: remove old Gen 2 functions (required if you see “Cannot set CPU … gen 1”)

Gen 2 and Gen 1 cannot share the same function name in-place. Delete the old ones, then deploy:

```bash
firebase login
firebase use vioraa

firebase functions:delete notifications-sendPush --region us-central1 --force
firebase functions:delete revenuecatWebhook --region us-central1 --force
firebase functions:delete revenuecatSubscriptionWebhook --region us-central1 --force
# Only if this trigger was ever deployed as gen2:
firebase functions:delete onMessageCreated --region us-central1 --force
```

Then from repo root: `./deploy-functions.sh`

## After you deploy

1. **RevenueCat** — If webhooks were pointed at **\*.a.run.app** (gen2) URLs, switch them to:

   - `https://us-central1-vioraa.cloudfunctions.net/revenuecatWebhook`
   - `https://us-central1-vioraa.cloudfunctions.net/revenuecatSubscriptionWebhook`

   (Same paths are already used in `REVENUECAT_SETUP.md`.)

2. **Callable** — The app should keep using  
   `FirebaseFunctions` + `httpsCallable('notifications-sendPush')`  
   (no change needed for the URL in Dart).

3. **First deploy after this change** — Firebase may **replace** previous gen2 instances with gen1 for the same names. Check the deploy log for the printed URLs.

## If you ever move back to gen2

You’ll need the IAM bindings in `FUNCTIONS_DEPLOY_IAM.md` (or a project owner to run `fix-functions-iam.sh`).
