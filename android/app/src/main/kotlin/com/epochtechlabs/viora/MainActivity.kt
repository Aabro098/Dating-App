package com.epochtechlabs.viora

import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.QueryPurchasesParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.interfaces.SyncPurchasesCallback
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.epochtechlabs.viora/revenuecat_bridge",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "syncPurchasesAwaitReceiptError" ->
                    syncPurchasesWithReceiptErrorResult(result)
                "querySubscriptionPurchaseTokens" ->
                    querySubscriptionPurchaseTokens(result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Returns a map of Play **subscription product id** → **purchase token** for active subs.
     * RevenueCat webhooks do not include this token; used to merge `purchase_token` into Firestore.
     */
    private fun querySubscriptionPurchaseTokens(result: MethodChannel.Result) {
        val answered = AtomicBoolean(false)
        fun finish(map: Map<String, String>) {
            if (answered.compareAndSet(false, true)) {
                result.success(map)
            }
        }

        // Billing 7+ (RC purchases → billing 8.x): no-arg enablePendingPurchases() removed.
        val pendingParams = PendingPurchasesParams.newBuilder()
            .enableOneTimeProducts()
            .enablePrepaidPlans()
            .build()
        val client = BillingClient.newBuilder(this)
            .setListener { _, _ -> }
            .enablePendingPurchases(pendingParams)
            .build()

        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: BillingResult) {
                if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
                    client.endConnection()
                    finish(emptyMap())
                    return
                }
                client.queryPurchasesAsync(
                    QueryPurchasesParams.newBuilder()
                        .setProductType(BillingClient.ProductType.SUBS)
                        .build(),
                ) { _, purchases ->
                    val out = HashMap<String, String>()
                    for (p in purchases) {
                        val token = p.purchaseToken
                        for (pid in p.products) {
                            out[pid] = token
                        }
                    }
                    client.endConnection()
                    finish(out)
                }
            }

            override fun onBillingServiceDisconnected() {
                try {
                    client.endConnection()
                } catch (_: Exception) {
                }
                finish(emptyMap())
            }
        })
    }

    /**
     * Uses RevenueCat’s real [SyncPurchasesCallback]. The Flutter [purchases_flutter] plugin’s
     * `syncPurchases` calls native code but completes the method channel with success immediately,
     * so [PurchasesError] (e.g. receipt already in use) never reaches Dart.
     */
    private fun syncPurchasesWithReceiptErrorResult(result: MethodChannel.Result) {
        try {
            Purchases.sharedInstance.syncPurchases(
                object : SyncPurchasesCallback {
                    override fun onSuccess(customerInfo: CustomerInfo) {
                        result.success(
                            mapOf(
                                "ok" to true,
                            ),
                        )
                    }

                    override fun onError(error: PurchasesError) {
                        val name = error.code.name
                        val receiptConflict =
                            name.contains("ReceiptAlreadyInUse", ignoreCase = true) ||
                                name.contains("ReceiptInUseByOtherSubscriber", ignoreCase = true) ||
                                name.contains("PurchaseBelongsToOtherUser", ignoreCase = true)
                        result.success(
                            mapOf(
                                "ok" to false,
                                "receiptConflict" to receiptConflict,
                                "errorCode" to name,
                                "message" to (error.message ?: ""),
                                "underlying" to (error.underlyingErrorMessage ?: ""),
                            ),
                        )
                    }
                },
            )
        } catch (e: Exception) {
            result.error("RC_SYNC", e.message, null)
        }
    }
}
