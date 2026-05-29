# RevenueCat Subscription Webhook

This webhook handles **subscription** events (monthly plans: `starter_monthly`, `deluxe_monthly`, `premium_monthly`, `elite_monthly`). The existing `revenuecatWebhook` handles **one-time / coins** (`NON_RENEWING_PURCHASE`).

## What it does

1. **Subscription_logs** – Every subscription event is stored in the `Subscription_logs` collection (platform-wide record) with:
   - `eventType`, `appUserId`, `productId`, `expirationAtMs`, `transactionId`, `store`, `price`, etc.

2. **Users/{uid}** – The user document is updated with a `subscription` map so the app can:
   - Show expiry date
   - Enforce plan-wise access
   - Use `SubscriptionState` / `getSubscriptionDisplayInfo()` as already implemented

   - **Active renewing** (INITIAL_PURCHASE, RENEWAL, UNCANCELLATION, etc.): `Users/{uid}/Subscription/current` with `product_id`, `expiration_*`, `entitlement_status = "active"`, `willRenew: true`
   - **Cancelled but still paid until period end** (`CANCELLATION`): same doc stays **active** until `expiration_at_ms`, with `willRenew: false`, `cancelReason`, `subscriptionCancelledAt`
   - **Expired** (`EXPIRATION` only): entitlement cleared, `willRenew: false`, `subscriptionOwnerId` cleared

## Setup

1. **Deploy the function**
   ```bash
   firebase deploy --only functions:revenuecatSubscriptionWebhook
   ```

2. **Get the webhook URL**  
   Example: `https://us-central1-YOUR_PROJECT.cloudfunctions.net/revenuecatSubscriptionWebhook`

3. **Set the auth token**  
   In `functions/revenuecat/subscriptionWebhook.js`, set:
   ```js
   const expectedToken = "Bearer YOUR_SECRET_TOKEN";
   ```
   Use a strong random token (e.g. generate one and store in Secret Manager or env).

4. **Configure in RevenueCat**
   - Dashboard → Project → Integrations → Webhooks
   - Add a new webhook URL (the subscription one above)
   - Set **Authorization** header: `Bearer YOUR_SECRET_TOKEN`
   - This webhook handles: INITIAL_PURCHASE, RENEWAL, EXPIRATION, CANCELLATION, PRODUCT_CHANGE, SUBSCRIPTION_EXTENDED, etc.  
   - Keep your existing webhook for one-time/coins if you use it.

## Idempotency

Events are deduplicated by `event.id` in `Subscription_logs`. Retries from RevenueCat will not double-write.
