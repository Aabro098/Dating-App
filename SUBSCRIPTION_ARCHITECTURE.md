# Subscription Architecture (per client spec)

## Core principles

1. **UI never directly:**
   - Calls RevenueCat SDK (except via `SubscriptionService` for purchase + `logIn`/`logOut`)
   - Writes Firestore subscription docs

2. **Firebase UID** = identity; **RevenueCat App User ID** = same Firebase UID (after `logInRevenueCat`)

3. **Firestore** `Users/{uid}/Subscription/current` = cached state for UI & gating (webhook writes only)

4. **RevenueCat** = billing source of truth; **strict ownership** = Firestore row must have `subscriptionOwnerId == uid`

---

## Google Play identity: what is *not* possible vs what we do

Google Play Billing does **not** expose a stable “Google account id” you can bind to a Firebase user. You **cannot** hard-enforce “Play account G1 may only ever be used with Viora user A” at the OS or Play API level. Enforcement is **app-side + RevenueCat + backend**, not a direct Play↔user link in Firebase.

### What we control (production pattern)

| Requirement | Viora implementation |
|-------------|----------------------|
| Require login before purchase | Firebase Auth; `Purchases.logIn(uid)` via `SubscriptionService.logInRevenueCat` / `refreshRevenueCatIdentity` (splash, home, auth). |
| Detect subscription state before paywall | Firestore `Users/{uid}/Subscription/current` for UI; `shouldBlockPurchaseBeforePlay(uid)` before opening Play billing (RC + Firestore ownership). |
| “Original owner” vs current user | `CustomerInfo.originalAppUserId` compared to current Firebase `uid` in `shouldBlockPurchaseBeforePlay` (uses raw `getCustomerInfo()`, not UID-aligned retries). |
| Backend ownership | Webhook sets `subscriptionOwnerId` from RevenueCat `app_user_id`; `subscriptionFirestoreOwnedBy(state, uid)` for gating. |

### RevenueCat dashboard setting (must align with product)

| Setting | Effect on shared device / same Play account |
|---------|---------------------------------------------|
| **Transfer subscription to new App User ID** | Subscription can **move** to User B when B logs in → undermines “this sub belongs to another Viora account.” |
| **Keep with original App User ID** (recommended for strict per–Viora-user ownership) | Subscription **stays** on the purchaser’s app user id → `originalAppUserId` can remain A while B is logged in → matches our mismatch detection. |

**Product decision:** If the client wants “same Play account, different Viora user = block,” use **Keep with original App User ID** and rely on `shouldBlockPurchaseBeforePlay` + Firestore `subscriptionOwnerId`. If they prefer “whoever is logged in gets the sub,” use **Transfer** and **do not** block on cross-account (by design).

### Store sync on login (restore-equivalent)

`refreshRevenueCatIdentity(uid)` calls `logIn`, invalidates RC cache, and `Purchases.syncPurchases()` so local Play state is merged before paywall checks. This is the Android-oriented equivalent of “restore then evaluate” in the guides.

### Honest limitation

A user can still reach Google’s purchase UI in edge cases; we **shape UX and entitlement** (wrong-account dialog, block before sheet where detectable), we do **not** override Google Play’s billing rules.

---

## Strict ownership (critical)

| Rule | Detail |
|------|--------|
| **Webhook** | On every active event (`INITIAL_PURCHASE`, `RENEWAL`, …), sets `subscriptionOwnerId: userId` (RevenueCat `app_user_id`). On `EXPIRATION`, clears owner and **deletes** product/expiry fields so the cache cannot imply premium. |
| **Client read** | `SubscriptionService.subscriptionFirestoreOwnedBy(state, uid)` requires non-empty `subscriptionOwnerId == uid`. Otherwise `getSubscriptionDisplayInfo` / `isSubscriptionActive` treat the user as **not subscribed** (no UI premium, no Firestore-based gating). |
| **Account switch** | `logOutRevenueCat()` on session reset / logout / disabled account. `logInRevenueCat(uid)` calls `Purchases.logOut()` first if the in-memory UID changed so Play/RC identity does not bleed across Viora accounts on one device. |

**Legacy docs** without `subscriptionOwnerId` will **not** show as subscribed until the next webhook (or a one-time Firestore backfill). Backfill example: set `subscriptionOwnerId` to the parent user id for each `Users/{uid}/Subscription/current` that is still active.

---

## Data flow

### Display (subscription status, plan list, features)

| Data | Source | Who reads |
|------|--------|-----------|
| Subscription status | Firestore `Users/{uid}/Subscription/current` | `SubscriptionService` → UI |
| Plan list, features | Firestore `SUBSCRIPTION/displayData` (or configured path) | `SubscriptionDisplayService` |

**Display path is Firestore-only** — no `getCustomerInfo()` for UI.

### Purchase flow

1. User taps Subscribe → `SubscriptionService.purchaseSubscription`
2. RevenueCat + Google Play complete purchase
3. Webhook updates `Users/{uid}/Subscription/current` with `subscriptionOwnerId`
4. UI refetches via `SubscriptionService`

### RevenueCat sync

- **Login / splash / home:** `SubscriptionService.logInRevenueCat(uid)`
- **Logout / reset / disabled account / Google sign-out:** `SubscriptionService.logOutRevenueCat()` (also triggered from `Globals.resetInitialization()`)

### QA: Active subscription, account deleted, reinstall, log in again

**Google Play:** The subscription remains on the **Google Play account** until the user cancels it in Play (or it expires). Deleting the Viora/Firebase account does **not** cancel the underlying Play billing contract.

**App / Firebase:** Account deletion removes the user doc and Auth user. Re-signing up with the same phone/Google typically creates a **new Firebase UID** (not the old one).

**RevenueCat (expected):** On a fresh install, after login the app calls `refreshRevenueCatIdentity(uid)` (splash, home), which `logIn`s the **current** Firebase UID and `syncPurchases()` so Play receipts are sent to RevenueCat again. Entitlements can become **active** for that `app_user_id` as long as the Play subscription is still valid and RevenueCat accepts the receipt—**unless** the user cancelled in Play or RevenueCat project rules block the transfer (e.g. receipt still “owned” by another RC app user if dashboard is set to **Keep with original App User ID** and the old uid still holds the subscription in RC).

**Firestore cache:** `Users/{uid}/Subscription/current` for the **new** uid is empty until the webhook processes events; premium UI that relies on `subscriptionOwnerId` may update shortly after RC + webhook catch up.

### QA: Cancel in Play, then re-subscribe before period ends

Example: monthly sub starts **Jan 1**, user cancels in **Google Play** on **Jan 10**, paid access continues until **Jan 31**. User taps subscribe again on **Jan 20**.

| Layer | Expected |
|-------|----------|
| **Google Play** | Turning auto-renew back on for the same product is a **plan change / resubscribe** flow: billing typically schedules the **next charge after the current period** (e.g. **Feb 1** for a monthly that ends Jan 31). Exact dates are always shown in Play. |
| **RevenueCat (SDK)** | While still in the paid period after cancel: entitlement **`isActive` = true**, **`willRenew` = false** (no renewal at period end until user fixes billing). After a successful re-subscribe / uncancel path: **`isActive` = true**, **`willRenew` = true**. |
| **Viora Firestore** | Webhook **`CANCELLATION`** writes `willRenew: false`, keeps `status`/`entitlement_status` active until expiry. Webhook **`INITIAL_PURCHASE` / `RENEWAL` / active events** in `ACTIVE_EVENTS` sets `willRenew: true` and clears cancel fields when RC sends them. |
| **Payment UI** | `SubscriptionDisplayInfo` prefers **Firestore** for `willRenew` when the cache is owned and active (`getSubscriptionDisplayInfo`), so banners match webhook-driven cancel vs renew copy. |

---

## Firestore writes

Only **subscription webhook** updates `Users/{uid}/Subscription/current` (app must not write it).

---

## File roles

| File | Role |
|------|------|
| `SubscriptionService.dart` | RC purchase + logIn/logOut; Firestore reads; strict ownership helpers |
| `SubscriptionDisplayService.dart` | Plans/features from Firestore |
| `functions/revenuecat/subscriptionWebhook.js` | Writes `current` + `subscriptionOwnerId`; clears product on expiration |
| `PaymentScreen` | UI via `SubscriptionService` only |
