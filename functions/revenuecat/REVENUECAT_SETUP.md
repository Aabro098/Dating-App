# RevenueCat subscription webhook – setup steps

## 1. Set your secret token (and redeploy)

1. Open `functions/revenuecat/subscriptionWebhook.js`.
2. Replace the placeholder with a strong secret (e.g. generate one: `openssl rand -hex 32`):
   ```js
   const expectedToken = "Bearer YOUR_ACTUAL_SECRET_TOKEN_HERE";
   ```
3. Redeploy:
   ```bash
   nvm use 20
   firebase deploy --only functions:revenuecatSubscriptionWebhook
   ```

Use the **same** token in step 3 below when adding the webhook in RevenueCat.

---

## 2. Get your webhook URL

Your function URL (project **vioraa**, region us-central1):

```
https://us-central1-vioraa.cloudfunctions.net/revenuecatSubscriptionWebhook
```

---

## 3. Add webhook in RevenueCat

1. Go to **RevenueCat dashboard**: https://app.revenuecat.com  
2. Select your **project** (the one used by the Viora app).
3. In the left sidebar go to **Integrations** → **Webhooks** (or **Project settings** → **Webhooks**).
4. Click **+ New** / **Add webhook**.
5. Fill in:
   - **URL:** `https://us-central1-vioraa.cloudfunctions.net/revenuecatSubscriptionWebhook`
   - **Authorization:** choose “Custom header” or “Authorization” and set:
     - Header: `Authorization`
     - Value: `Bearer YOUR_ACTUAL_SECRET_TOKEN_HERE` (same as in step 1)
6. **Events:** leave default (all events) or select at least:
   - INITIAL_PURCHASE  
   - RENEWAL  
   - EXPIRATION  
   - CANCELLATION  
   - PRODUCT_CHANGE  
   - SUBSCRIPTION_EXTENDED  
   (Your function ignores NON_RENEWING_PURCHASE; that can stay on your existing coins webhook.)
7. Save the webhook.

---

## 4. Test

- In RevenueCat, use **Send test event** for the new webhook (if available).
- Or make a test subscription purchase in the app and check:
  - Firestore **Subscription_logs** for a new doc.
  - **Users/{your-uid}** → `subscription` map updated with `product_id`, `expiration_time`, `entitlement_status`.

---

## Summary

| Item        | Value |
|------------|--------|
| Webhook URL | `https://us-central1-vioraa.cloudfunctions.net/revenuecatSubscriptionWebhook` |
| Auth header | `Authorization: Bearer <your_secret_token>` |
| Token      | Set in `subscriptionWebhook.js` and in RevenueCat (same value). |
