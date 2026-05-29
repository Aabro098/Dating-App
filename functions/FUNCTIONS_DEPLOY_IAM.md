# Fix: “Failed to modify the IAM policy” when deploying Functions

**This repo uses Gen 1 (Classic) functions** — you usually **won’t** see this error.  
Keep this doc if you **move to Gen 2** again.

---

Firebase CLI needs **project-level IAM bindings** for **2nd gen** functions (Cloud Run + Eventarc). If the CLI cannot apply them automatically, add them yourself.

## Option A — `gcloud` (fastest)

### 1. Install Google Cloud SDK (your error was `gcloud: command not found`)

**macOS (Homebrew):**

```bash
brew install --cask google-cloud-sdk
```

Restart the terminal (or `source "$(brew --prefix)/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc"` if the installer prints a path).

**Verify:**

```bash
gcloud version
```

### 2. Log in and set project

```bash
gcloud auth login
gcloud config set project vioraa
```

### 3. Run the script from this folder

```bash
cd functions
./fix-functions-iam.sh
```

### 4. Deploy again

```bash
cd ..
./deploy-functions.sh
```

---

## Option B — Google Cloud Console (no `gcloud`)

1. Open **[IAM for project vioraa](https://console.cloud.google.com/iam-admin/iam?project=vioraa)** (must be Owner or **Project IAM Admin**).

2. Click **Grant access** (or **Add**).

3. **First principal** — paste exactly:

   `service-877294522958@gcp-sa-pubsub.iam.gserviceaccount.com`  

   Role: **Service Account Token Creator** (`roles/iam.serviceAccountTokenCreator`)  
   Save.

4. **Second principal** — paste exactly:

   `877294522958-compute@developer.gserviceaccount.com`  

   Add **two** roles on the same row (or grant twice if the UI only allows one at a time):

   - **Cloud Run Invoker** (`roles/run.invoker`)
   - **Eventarc Event Receiver** (`roles/eventarc.eventReceiver`)

5. Run `./deploy-functions.sh` again.

---

## If deploy still fails

- Confirm Firebase CLI project: `firebase use` → should be **vioraa**.
- Confirm GCP project number **877294522958** matches [Firebase project settings](https://console.firebase.google.com/) → Project settings → General (Project ID `vioraa`).
