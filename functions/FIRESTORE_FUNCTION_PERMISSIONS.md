# Cloud Functions runtime IAM (Firestore + FCM)

The **same** runtime service account (often `vioraa@appspot.gserviceaccount.com` for Gen 1) needs **separate** roles for Firestore and for **sending FCM** from `notifications-sendPush`.

---

## A. FCM: `cloudmessaging.messages.create` / `messaging/mismatched-credential`

If logs show:

```text
Permission 'cloudmessaging.messages.create' denied on resource '.../projects/vioraa'
errorCode: messaging/mismatched-credential
```

the function identity cannot call the **Firebase Cloud Messaging API**.

### 1) Enable the API (if needed)

**APIs & Services** → **Library** → enable **Firebase Cloud Messaging API** (or run):

```bash
gcloud services enable fcm.googleapis.com --project=vioraa
```

### 2) Grant FCM Admin to the **runtime** service account

**Cloud Functions** → **`notifications-sendPush`** → **Configuration** → copy **Runtime service account**.

**IAM & Admin** → **IAM** → **Grant access**

- **Principal:** that service account (often `vioraa@appspot.gserviceaccount.com`)
- **Role:** **Firebase Cloud Messaging Admin** — IAM id `roles/firebasecloudmessaging.admin`

### 3) gcloud (optional)

```bash
gcloud config set project vioraa

gcloud projects add-iam-policy-binding vioraa \
  --member="serviceAccount:vioraa@appspot.gserviceaccount.com" \
  --role="roles/firebasecloudmessaging.admin"
```

(Replace `--member` if your function uses a different runtime SA.)

Wait 1–2 minutes, then retry the callable / notification.

---

## B. Firestore: `PERMISSION_DENIED` / code 7 on `document.get` / `batch.commit`

If Cloud Logging shows:

```text
7 PERMISSION_DENIED: Missing or insufficient permissions.
```

…with a stack pointing at `@google-cloud/firestore` / `document-reference` / `get`, the **function’s runtime service account** is not allowed to use Firestore.

## 1. See which account the function uses

**Google Cloud Console** → **Cloud Functions** → open **`revenuecatSubscriptionWebhook`** → **Configuration** → **Runtime, build…** → **Runtime service account**.

Typical for **1st gen** Firebase functions on project **`vioraa`**:

- `vioraa@appspot.gserviceaccount.com`  
  (App Engine default)

If yours is different, use that email in the steps below.

## 2. Grant Firestore access (Console)

**IAM & Admin** → **IAM** → **Grant access**

- **Principal:** the runtime service account from step 1  
- **Role:** **Cloud Datastore User** (`roles/datastore.user`)

Save, wait ~1–2 minutes, then retry the RevenueCat webhook.

## 3. Same thing with gcloud (optional)

```bash
gcloud config set project vioraa

gcloud projects add-iam-policy-binding vioraa \
  --member="serviceAccount:vioraa@appspot.gserviceaccount.com" \
  --role="roles/datastore.user"
```

(Replace the member if your function uses another service account.)

## 4. If Firestore still fails

- Confirm **Cloud Firestore API** is enabled: APIs & Services → enable `firestore.googleapis.com`.
- Confirm the function deploys into the **same GCP project** as the Firestore database (`vioraa`).
- Org **constraints** (e.g. denying default SA usage) must be adjusted by an org admin.

---

## Summary checklist (Gen 1 default SA)

| Need | Role (IAM id) |
|------|----------------|
| Firestore read/write (webhooks, triggers) | `roles/datastore.user` |
| Send FCM from `notifications-sendPush` / `onMessageCreated` | `roles/firebasecloudmessaging.admin` |

**Note:** RevenueCat **Bearer** tokens and **App Check** are unrelated. The Admin SDK in the function uses the **runtime service account** for Firestore + FCM.
