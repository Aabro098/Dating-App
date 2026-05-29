# Firebase App Check — Firestore & backend protection

App Check proves requests come from **your real app** (Play Integrity / App Attest / debug token), not from a random script that has your `google-services.json` or REST calls with only an API key. **Turn on enforcement in the Console** so Firebase rejects invalid or missing tokens before Firestore rules run.

## What this repo configures

| Layer | Behavior |
|--------|----------|
| **Flutter** (`lib/main.dart`) | **TEMPORARY:** App Check activation is **commented out**. When re-enabled: activate **after** `Firebase.initializeApp()` (via `Globals.init()`). |
| **Android** (`android/app/build.gradle.kts`) | `firebase-appcheck-debug` (debug) + `firebase-appcheck-playintegrity` (release) |
| **Callable Functions** | **TEMPORARY:** `enforceAppCheck: false` in `functions/notifications/push.js` — set back to `true` when client App Check is on. |
| **HTTP webhooks** | RevenueCat webhooks use the **Admin SDK** — they do **not** need App Check (server-side). |

## Required: Firebase Console

### 1. Register each app (Build → App Check)

- **Android** → Play Integrity API (same Google Cloud project as Firebase).
- **iOS** → App Attest (enable capability in Xcode: Signing & Capabilities → App Attest).
- **Web** (if you ship web) → Register reCAPTCHA v3 and put the site key in `RECAPTCHA_SITE_KEY`.

### 2. Debug builds & emulators

1. Run the app (debug).
2. Copy the **App Check debug token** from Logcat (Android) or Xcode console (iOS).
3. Firebase Console → App Check → **Manage debug tokens** → add the token.

Every developer machine needs its own debug token, or builds will fail once enforcement is on.

### 3. Enable enforcement (this blocks unauthorized Firestore access)

1. Firebase Console → **App Check**.
2. Open **APIs** / product list (or each product):
   - **Cloud Firestore** → **Enforce**
   - **Cloud Storage** (if the app uses it) → **Enforce**
3. Start with **“Monitor”** mode if you want to see metrics before flipping **Enforce**.

After enforcement, only clients that send a **valid App Check token** (your registered app + attestation) can use that product. Leaked config files alone are not enough.

### 4. Optional: stricter Security Rules

Console enforcement is the main gate. You can also require an App Check–aware client in rules using `request.app != null` (see `firestore.rules.appcheck.snippet`). Merge snippets into your real `firestore.rules` — do not deploy rules you have not tested.

## Production checklist

- [ ] Play Integrity enabled in Google Cloud for the Android app
- [ ] App Attest (or Device Check) for iOS in Firebase + Xcode capability
- [ ] All team debug tokens registered
- [ ] Firestore (and Storage if used) enforcement enabled after testing
- [ ] Release build tested on a **real device** (not only emulator)

## What App Check does *not* replace

- **Security Rules** still control *who* can read/write which documents (`request.auth`, paths, etc.).
- **Authentication** is still required for user data; App Check only attests the **client binary**.
- **Admin SDK**, Cloud Functions using `admin`, and trusted webhooks are not subject to client App Check.

## Web reCAPTCHA (optional)

```bash
flutter run --dart-define=RECAPTCHA_SITE_KEY=your_site_key
```

## References

- [Firestore + App Check](https://firebase.google.com/docs/app-check/firestore)
- [Flutter App Check](https://firebase.google.com/docs/app-check/flutter/default-providers)
- [Callable enforceAppCheck](https://firebase.google.com/docs/app-check/cloud-functions)
