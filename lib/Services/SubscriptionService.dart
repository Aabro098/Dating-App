// Subscription purchase flow: RevenueCat = source of truth for entitlements;
// Firestore = cache (webhook writes Subscription_logs + user subscription map).

import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../models/SubscriptionPlanDisplay.dart';
import '../models/SubscriptionState.dart';
import 'exceptions/error_handler.dart';
import 'exceptions/app_exceptions.dart';

/// Live subscription info for UI (active product id, expiry). From RevenueCat or Firestore.
class SubscriptionDisplayInfo {
  final String? activeProductStoreId;
  final DateTime? expirationTime;
  final bool isActive;

  /// True when plan is set to auto-renew; false after user cancels in store.
  final bool willRenew;

  /// RevenueCat / Firestore entitlement id (e.g. deluxe, elite) for feature lists.
  final String? entitlementId;

  /// Feature configuration for the active subscription (e.g. messaging limits, enabled features).
  final PlanFeatures? entitlementFeatures;

  const SubscriptionDisplayInfo({
    this.activeProductStoreId,
    this.expirationTime,
    this.isActive = false,
    this.willRenew = true,
    this.entitlementId,
    this.entitlementFeatures,
  });
}

class SubscriptionService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Android: same process as [purchases_flutter], but [SyncPurchasesCallback] surfaces errors.
  static final MethodChannel _revenueCatAndroidBridge = MethodChannel(
    'com.epochtechlabs.viora/revenuecat_bridge',
  );

  /// RevenueCat webhooks do not include Play `purchase_token`. [ensureSubscriptionCurrentListenerForPurchaseTokenLog]
  /// watches `Subscription/current`; when `subscriptionLogEventId` and `purchase_token` are both set,
  /// the same token is merged into `Subscription_logs/{id}` if the log does not already hold it.
  /// [refreshRevenueCatIdentity] also syncs from Billing on a throttle; purchases call
  /// [_syncAndroidPurchaseTokenToFirestore] without throttle (writes `current` only; log update follows from the snapshot).
  static final Map<String, DateTime> _lastPurchaseTokenFirestoreSync = {};
  static const Duration _purchaseTokenFirestoreThrottle = Duration(hours: 6);

  /// Fills `current.purchase_token` when webhook set `subscriptionLogEventId` first (throttled).
  static final Map<String, DateTime> _lastBillingFillWhenLogIdWithoutToken = {};

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _subscriptionCurrentPurchaseTokenListener;
  static String? _subscriptionCurrentPurchaseTokenListenerUid;

  static void _cancelSubscriptionCurrentPurchaseTokenListener() {
    _subscriptionCurrentPurchaseTokenListener?.cancel();
    _subscriptionCurrentPurchaseTokenListener = null;
    _subscriptionCurrentPurchaseTokenListenerUid = null;
  }

  static String? _purchaseTokenStringFromFirestoreValue(dynamic v) {
    if (v is String) {
      final t = v.trim();
      if (t.isNotEmpty) return t;
    }
    if (v is Iterable) {
      for (final e in v) {
        final s = e?.toString().trim();
        if (s != null && s.isNotEmpty) return s;
      }
    }
    return null;
  }

  /// Webhook may land after Billing; listen to [Subscription/current] and merge token into
  /// [Subscription_logs/{subscriptionLogEventId}] only when both are present. Skips if the log
  /// already has the same token.
  static void ensureSubscriptionCurrentListenerForPurchaseTokenLog(String uid) {
    if (uid.isEmpty) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_subscriptionCurrentPurchaseTokenListenerUid == uid &&
        _subscriptionCurrentPurchaseTokenListener != null) {
      return;
    }
    _cancelSubscriptionCurrentPurchaseTokenListener();
    _subscriptionCurrentPurchaseTokenListenerUid = uid;
    _subscriptionCurrentPurchaseTokenListener = _firestore
        .collection('Users')
        .doc(uid)
        .collection('Subscription')
        .doc('current')
        .snapshots()
        .listen(
          (DocumentSnapshot<Map<String, dynamic>> snap) {
            unawaited(
              _handleCurrentSubscriptionSnapshotForPurchaseTokenLog(uid, snap),
            );
          },
          onError: (Object e) {
            if (kDebugMode) {
              debugPrint(
                '[SubscriptionService] Subscription/current listener: $e',
              );
            }
          },
        );
  }

  static Future<void> _handleCurrentSubscriptionSnapshotForPurchaseTokenLog(
    String uid,
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) async {
    if (!_authUidStill(uid)) return;
    if (!snap.exists) return;
    final data = snap.data();
    if (data == null) return;

    final logRaw = data['subscriptionLogEventId'];
    final logId = logRaw?.toString().trim();
    if (logId == null || logId.isEmpty) return;

    final tokenStr = _purchaseTokenStringFromFirestoreValue(
      data['purchase_token'],
    );
    if (tokenStr == null || tokenStr.isEmpty) {
      final now = DateTime.now();
      final last = _lastBillingFillWhenLogIdWithoutToken[uid];
      if (last != null && now.difference(last) < const Duration(seconds: 20)) {
        return;
      }
      _lastBillingFillWhenLogIdWithoutToken[uid] = now;
      final hint =
          data['purchase_token_product_id']?.toString() ??
          data['productId']?.toString() ??
          data['product_id']?.toString();
      await _syncAndroidPurchaseTokenToFirestore(
        uid,
        hint?.trim().isNotEmpty == true ? hint : null,
        respectThrottle: false,
      );
      return;
    }

    await _maybeMergePurchaseTokenToSubscriptionLogDoc(
      uid,
      logId,
      tokenStr,
      data,
    );
  }

  static Future<void> _maybeMergePurchaseTokenToSubscriptionLogDoc(
    String uid,
    String logEventId,
    String token,
    Map<String, dynamic> currentData,
  ) async {
    if (!_authUidStill(uid)) return;
    try {
      final logRef = _firestore.collection('Subscription_logs').doc(logEventId);
      final logSnap = await logRef.get();
      if (!logSnap.exists) return;

      final existing =
          _purchaseTokenStringFromFirestoreValue(
            logSnap.data()?['purchase_token'],
          ) ??
          _purchaseTokenStringFromFirestoreValue(logSnap.data()?['tokens']);

      final patch = <String, dynamic>{};
      if (existing != token) {
        patch['purchase_token'] = token;
        patch['tokens'] = <String>[token];
        patch['purchase_token_updated_at'] = FieldValue.serverTimestamp();
      }
      final fp = currentData['firstPurchaseAt'];
      final lp = currentData['lastPurchaseAt'];
      if (fp != null) patch['firstPurchaseAt'] = fp;
      if (lp != null) patch['lastPurchaseAt'] = lp;

      if (patch.isEmpty) return;

      await logRef.set(patch, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] _maybeMergePurchaseTokenToSubscriptionLog: $e',
        );
      }
    }
  }

  /// Last UID we bound to RevenueCat this process (strict account switching).
  static String? _lastPurchasesBoundUid;

  // --- Subscription display cache (speeds Payment screen after [preloadSubscriptionDisplayForUser]) ---
  static SubscriptionDisplayInfo? _subscriptionDisplayCache;
  static String? _subscriptionDisplayCacheUid;
  static DateTime? _subscriptionDisplayCacheAt;
  static const Duration _subscriptionDisplayCacheTtl = Duration(seconds: 90);

  static Future<SubscriptionDisplayInfo?>? _subscriptionDisplayInfoInFlight;
  static String? _subscriptionDisplayInfoInFlightUid;

  /// Drop cached [SubscriptionDisplayInfo] (call on logout / before forced refresh).
  static void invalidateSubscriptionDisplayCache() {
    _subscriptionDisplayCache = null;
    _subscriptionDisplayCacheUid = null;
    _subscriptionDisplayCacheAt = null;
    _subscriptionDisplayInfoInFlight = null;
    _subscriptionDisplayInfoInFlightUid = null;
    _cancelSubscriptionCurrentPurchaseTokenListener();
    _lastBillingFillWhenLogIdWithoutToken.clear();
  }

  static SubscriptionDisplayInfo? _subscriptionDisplayCacheHit(String uid) {
    if (_subscriptionDisplayCache == null ||
        _subscriptionDisplayCacheUid != uid ||
        _subscriptionDisplayCacheAt == null) {
      return null;
    }
    if (DateTime.now().difference(_subscriptionDisplayCacheAt!) >=
        _subscriptionDisplayCacheTtl) {
      return null;
    }
    return _subscriptionDisplayCache;
  }

  /// Instant Payment UI (banner): last known display for [uid], ignoring TTL. Remote fetch
  /// updates right after; avoids waiting on RevenueCat before showing prior subscription state.
  static SubscriptionDisplayInfo? peekCachedSubscriptionDisplay(String uid) {
    if (uid.isEmpty) return null;
    if (_subscriptionDisplayCacheUid != uid) return null;
    return _subscriptionDisplayCache;
  }

  /// Run after login (non-blocking) so Payment / plans screen can reuse cache + warm RC.
  static void preloadSubscriptionDisplayForUser(String uid) {
    if (uid.isEmpty) return;
    ensureSubscriptionCurrentListenerForPurchaseTokenLog(uid);
    unawaited(() async {
      try {
        // Same path as Payment screen (coalesces in-flight; fills cache when done).
        await getSubscriptionDisplayInfo(uid);
        if (kDebugMode) {
          debugPrint(
            '[SubscriptionService] preloadSubscriptionDisplayForUser done uid=$uid',
          );
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[SubscriptionService] preloadSubscriptionDisplayForUser: $e',
          );
        }
      }
    }());
  }

  static bool _authUidStill(String uid) =>
      _auth.currentUser != null && _auth.currentUser!.uid == uid;

  /// RevenueCat throws if [Purchases.logOut] is called while the SDK user is still anonymous.
  static bool _isLogoutAnonymousUserError(Object e) {
    if (e is! PlatformException) return false;
    final msg = (e.message ?? '').toLowerCase();
    if (e.code == '22') return true;
    if (msg.contains('anonymous') && msg.contains('logout')) return true;
    final d = e.details;
    if (d is Map &&
        d['readable_error_code'] == 'LogOutWithAnonymousUserError') {
      return true;
    }
    final code = PurchasesErrorHelper.getErrorCode(e);
    return code == PurchasesErrorCode.logOutWithAnonymousUserError;
  }

  /// Play / RevenueCat "duplicate" purchase — same Google account already has this sub elsewhere.
  static bool _purchaseErrorLooksLikeAlreadySubscribed(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('item_already_owned') ||
        s.contains('itemalreadyowned') ||
        s.contains('product_already_purchased') ||
        s.contains('already_purchased') ||
        s.contains('receipt_in_use') ||
        s.contains('receipt already') ||
        (s.contains('already') &&
            (s.contains('subscrib') ||
                s.contains('owned') ||
                s.contains('purchased'))) ||
        (s.contains('you ') &&
            s.contains('already') &&
            s.contains('subscrib')) ||
        (s.contains('you\'re') &&
            s.contains('already') &&
            s.contains('subscrib'))) {
      return true;
    }
    if (e is PlatformException) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.productAlreadyPurchasedError ||
          code == PurchasesErrorCode.receiptAlreadyInUseError ||
          code == PurchasesErrorCode.receiptInUseByOtherSubscriberError ||
          code == PurchasesErrorCode.purchaseBelongsToOtherUser) {
        return true;
      }
    }
    return false;
  }

  /// Kotlin [PurchasesErrorCode.name] from native [SyncPurchasesCallback.onError].
  static bool _revenueCatNativeErrorCodeIndicatesReceiptConflict(String? code) {
    if (code == null || code.isEmpty) return false;
    final s = code.toLowerCase();
    return s.contains('receiptalreadyinuse') ||
        s.contains('receiptinusebyothersubscriber') ||
        (s.contains('purchasebelongs') && s.contains('other'));
  }

  /// Android only — [purchases_flutter] `syncPurchases` does not await or forward errors.
  static Future<bool> _androidNativeSyncIndicatesReceiptConflict() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      print(
        '[RC native sync] skip: kIsWeb=$kIsWeb platform=$defaultTargetPlatform',
      );
      return false;
    }
    try {
      final raw = await _revenueCatAndroidBridge.invokeMethod<Object>(
        'syncPurchasesAwaitReceiptError',
      );
      print(
        '[RC native sync] syncPurchasesAwaitReceiptError raw type=${raw.runtimeType} '
        'value=$raw',
      );

      if (raw == null) {
        print('[RC native sync] raw is null → receiptConflict=false');
        return false;
      }
      if (raw is! Map) {
        print(
          '[RC native sync] raw is not Map (actual: ${raw.runtimeType}) → '
          'receiptConflict=false',
        );
        return false;
      }

      final map = Map<Object?, Object?>.from(raw);
      print('[RC native sync] parsed map entries:');
      map.forEach((key, value) {
        print('[RC native sync]   $key = $value (${value?.runtimeType})');
      });

      final ok = map['ok'];
      final receiptConflict = map['receiptConflict'];
      final errorCode = map['errorCode'];
      final message = map['message'];
      final underlying = map['underlying'];

      if (ok == true) {
        print(
          '[RC native sync] ok=true → receiptConflict=false '
          '(errorCode=$errorCode message=$message)',
        );
        return false;
      }
      if (receiptConflict == true) {
        print(
          '[RC native sync] receiptConflict=true → receiptConflict=true '
          '(errorCode=$errorCode message=$message underlying=$underlying)',
        );
        return true;
      }

      final codeStr = errorCode?.toString();
      final fromCode = _revenueCatNativeErrorCodeIndicatesReceiptConflict(
        codeStr,
      );
      print(
        '[RC native sync] ok!=true, receiptConflict!=true; '
        'errorCode=$codeStr inferredReceiptConflict=$fromCode '
        'message=$message underlying=$underlying',
      );
      return fromCode;
    } catch (e, st) {
      print(
        '[RC native sync] invokeMethod/syncPurchasesAwaitReceiptError exception: $e',
      );
      print('[RC native sync] stack: $st');
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] _androidNativeSyncIndicatesReceiptConflict: $e',
        );
      }
      return false;
    }
  }

  /// Play Billing [Purchase.getPurchaseToken] — not sent by RevenueCat webhooks. Merges into
  /// `Users/{uid}/Subscription/current`. Set [respectThrottle] on background identity refresh only.
  static Future<void> _syncAndroidPurchaseTokenToFirestore(
    String uid,
    String? preferredStoreProductId, {
    bool respectThrottle = false,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (respectThrottle) {
      final last = _lastPurchaseTokenFirestoreSync[uid];
      if (last != null &&
          DateTime.now().difference(last) < _purchaseTokenFirestoreThrottle) {
        return;
      }
    }
    try {
      final raw = await _revenueCatAndroidBridge.invokeMethod<dynamic>(
        'querySubscriptionPurchaseTokens',
      );
      if (raw is! Map) return;
      final tokensByProduct = <String, String>{};
      raw.forEach((k, v) {
        final ks = k?.toString();
        final vs = v?.toString();
        if (ks != null && vs != null && ks.isNotEmpty && vs.isNotEmpty) {
          tokensByProduct[ks] = vs;
        }
      });
      if (tokensByProduct.isEmpty) return;

      String? token;
      String? matchedKey;
      final pref = preferredStoreProductId?.trim();
      if (pref != null && pref.isNotEmpty) {
        if (tokensByProduct.containsKey(pref)) {
          token = tokensByProduct[pref];
          matchedKey = pref;
        } else {
          final prefLower = pref.toLowerCase();
          final base = prefLower.split(':').first;
          for (final e in tokensByProduct.entries) {
            final kl = e.key.toLowerCase();
            if (kl == prefLower ||
                prefLower.contains(kl) ||
                kl.contains(base)) {
              token = e.value;
              matchedKey = e.key;
              break;
            }
          }
        }
      }
      token ??= tokensByProduct.values.first;
      matchedKey ??= tokensByProduct.keys.first;

      await _firestore
          .collection('Users')
          .doc(uid)
          .collection('Subscription')
          .doc('current')
          .set({
            'purchase_token': token,
            'tokens': <String>[token],
            'purchase_token_product_id': matchedKey,
            'purchase_token_updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (respectThrottle) {
        _lastPurchaseTokenFirestoreSync[uid] = DateTime.now();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] _syncAndroidPurchaseTokenToFirestore: $e',
        );
      }
    }
  }

  /// Writes Play `purchase_token` when the user has an active RC entitlement (webhook omits it).
  static Future<void> _syncPurchaseTokenFromBillingAfterIdentity(
    String uid,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final info = await getCustomerInfo();
      if (info == null || info.entitlements.active.isEmpty) return;
      String? productHint;
      for (final e in info.entitlements.active.values) {
        final id = e.productIdentifier.trim();
        if (id.isNotEmpty) {
          productHint = id;
          break;
        }
      }
      await _syncAndroidPurchaseTokenToFirestore(
        uid,
        productHint,
        respectThrottle: true,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] _syncPurchaseTokenFromBillingAfterIdentity: $e',
        );
      }
    }
  }

  /// True when [Purchases.syncPurchases] fails because this Play receipt is tied to another RC app user.
  static bool _syncPurchasesErrorIsOtherSubscriberReceipt(Object e) {
    if (e is PlatformException) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.receiptAlreadyInUseError ||
          code == PurchasesErrorCode.receiptInUseByOtherSubscriberError ||
          code == PurchasesErrorCode.purchaseBelongsToOtherUser) {
        return true;
      }
    }
    final s = e.toString().toLowerCase();
    return s.contains('another active subscriber') ||
        (s.contains('receipt') &&
            s.contains('another') &&
            s.contains('subscriber')) ||
        s.contains('receipt already in use');
  }

  /// True when [CustomerInfo.latestExpirationDate] is in the future (current subscription window).
  ///
  /// Purchase-blocking heuristics use this only (not every entry in [allExpirationDates]).
  /// Per-product dates can remain briefly after cancel/expiry and caused false "Purchase unavailable"
  /// for the next Viora user on the same Play account.
  static bool _latestRcSubscriptionExpirationIsFuture(
    CustomerInfo info,
    DateTime now,
  ) {
    final latestRaw = info.latestExpirationDate;
    if (latestRaw == null || latestRaw.isEmpty) return false;
    final d = DateTime.tryParse(latestRaw);
    return d != null && d.isAfter(now);
  }

  /// Tier base for comparison, e.g. `deluxe_yearly` / `deluxe_monthly` → `deluxe`.
  static String _tierBaseFromCanonicalPlanKey(String? productId) {
    final key = canonicalPlanKeyForActiveMatch(productId);
    if (key.isEmpty) return '';
    final lastUnd = key.lastIndexOf('_');
    if (lastUnd <= 0) return key.toLowerCase();
    final suffix = key.substring(lastUnd + 1).toLowerCase();
    if (suffix == 'yearly' || suffix == 'monthly') {
      return key.substring(0, lastUnd).toLowerCase();
    }
    return key.toLowerCase();
  }

  /// SKUs that best represent **this** Play receipt for tier comparison — **not** the full
  /// [CustomerInfo.allPurchasedProductIdentifiers] list (that includes old tiers; matching any
  /// stale deluxe SKU would hide a deluxe vs premium mismatch with the current receipt).
  ///
  /// When [CustomerInfo.entitlements.active] is empty, **do not** use [allExpirationDates]
  /// “future” rows — RC can still list a future expiry for an old tier while the real Play
  /// subscription is another SKU ([ReceiptAlreadyInUseError] / receipt on another Viora user).
  /// In that case use the **latest** [allPurchaseDates] entry only.
  static List<String> _rcSkusForReceiptTierComparison(
    CustomerInfo info,
    DateTime now,
  ) {
    final hasRcEntitlement = info.entitlements.active.isNotEmpty;

    if (hasRcEntitlement) {
      final withFutureExp = <String>[];
      for (final e in info.allExpirationDates.entries) {
        final exp = DateTime.tryParse(e.value ?? '');
        if (exp != null && exp.isAfter(now)) {
          withFutureExp.add(e.key);
        }
      }
      if (withFutureExp.isNotEmpty) return withFutureExp;
    }

    String? bestSku;
    DateTime? bestDate;
    for (final e in info.allPurchaseDates.entries) {
      final d = DateTime.tryParse(e.value ?? '');
      if (d == null) continue;
      if (bestDate == null || d.isAfter(bestDate)) {
        bestDate = d;
        bestSku = e.key;
      }
    }
    if (bestSku != null) return [bestSku];

    return info.allPurchasedProductIdentifiers.toList();
  }

  /// Inactive Firestore cache (e.g. expired) says one plan, but the Play receipt synced into
  /// RC lists different subscription SKUs — common when the Play account's active purchase
  /// belongs to another Viora user ([ReceiptAlreadyInUseError] on POST /receipts) while this
  /// user's doc still has stale webhook data.
  static bool _inactiveFirestoreSubscriptionMismatchesRcReceipt(
    SubscriptionState? state,
    CustomerInfo? info,
  ) {
    if (state == null || state.isActive) return false;
    if (info == null) return false;
    if (info.entitlements.active.isNotEmpty) return false;

    final now = DateTime.now();
    // No live subscription on this Play profile — stale Firestore tier vs historical RC SKUs must not block.
    if (info.activeSubscriptions.isEmpty &&
        !_latestRcSubscriptionExpirationIsFuture(info, now)) {
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] _inactiveFirestoreSubscriptionMismatchesRcReceipt: '
          'no activeSubscriptions + latest exp not future — no block',
        );
      }
      return false;
    }

    final fsTier = _tierBaseFromCanonicalPlanKey(state.productId);
    if (fsTier.isEmpty) return false;

    final skus = _rcSkusForReceiptTierComparison(info, now);
    if (skus.isEmpty) return false;

    if (kDebugMode) {
      debugPrint(
        '[SubscriptionService] _inactiveFirestoreSubscriptionMismatchesRcReceipt: '
        'fsTier=$fsTier skusCompared=$skus',
      );
    }

    if (skus.length == 1) {
      final rcTier = _tierBaseFromCanonicalPlanKey(skus.first);
      if (rcTier.isEmpty) return false;
      if (rcTier == fsTier) {
        if (kDebugMode) {
          debugPrint(
            '[SubscriptionService] _inactiveFirestoreSubscriptionMismatchesRcReceipt: '
            'single-sku tier match — no block',
          );
        }
        return false;
      }
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] _inactiveFirestoreSubscriptionMismatchesRcReceipt: '
          'single-sku tier mismatch — block',
        );
      }
      return true;
    }

    // Multiple SKUs (fallback list): **any** tier different from Firestore means conflict
    // (e.g. [deluxe*, premium*] with Firestore deluxe — cannot trust "any match").
    for (final rc in skus) {
      final rcTier = _tierBaseFromCanonicalPlanKey(rc);
      if (rcTier.isNotEmpty && rcTier != fsTier) {
        if (kDebugMode) {
          debugPrint(
            '[SubscriptionService] _inactiveFirestoreSubscriptionMismatchesRcReceipt: '
            'multi-sku tier mismatch rc=$rc rcTier=$rcTier — block',
          );
        }
        return true;
      }
    }
    if (kDebugMode) {
      debugPrint(
        '[SubscriptionService] _inactiveFirestoreSubscriptionMismatchesRcReceipt: '
        'multi-sku all tiers match Firestore — no block',
      );
    }
    return false;
  }

  /// Play still has subscription dates / SKUs on the receipt, but this Firebase user has no
  /// entitlement and no **active** Firestore row owned by them — typical when the same Google account
  /// purchased under a different Viora uid (RC "transfer" / [originalAppUserId] aligned to B).
  static bool _customerInfoSuggestsPlaySubNotOwnedByThisFirebaseUser(
    CustomerInfo? info,
    SubscriptionState? state,
    String uid,
  ) {
    if (info == null) return false;
    if (subscriptionFirestoreOwnedBy(state, uid) &&
        (state?.isActive ?? false)) {
      return false;
    }
    if (_revenueCatShowsActiveSubscription(info)) return false;
    final now = DateTime.now();
    if (!_latestRcSubscriptionExpirationIsFuture(info, now)) return false;
    if (info.entitlements.active.isNotEmpty) return false;
    if (info.activeSubscriptions.isNotEmpty) return false;
    if (info.allPurchasedProductIdentifiers.isEmpty) return false;
    return true;
  }

  /// No-op when already anonymous; does not report to [ErrorHandler].
  static Future<void> _purchasesLogOutIgnoringAnonymous() async {
    try {
      await Purchases.logOut();
    } catch (e) {
      if (_isLogoutAnonymousUserError(e)) {
        if (kDebugMode) {
          debugPrint(
            '[SubscriptionService] Purchases.logOut skipped (anonymous user)',
          );
        }
        return;
      }
      rethrow;
    }
  }

  /// Call on logout / account removal so the next user does not inherit Play billing + RC identity.
  static Future<void> logOutRevenueCat() async {
    invalidateSubscriptionDisplayCache();
    try {
      await _purchasesLogOutIgnoringAnonymous();
      _lastPurchasesBoundUid = null;
      if (kDebugMode)
        debugPrint('[SubscriptionService] RevenueCat logOut done');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[SubscriptionService] RevenueCat logOut: $e');
      ErrorHandler.handle(null, e, st, true);
    }
  }

  /// Explicit logout cleanup for subscription state.
  ///
  /// If a cached plan exists for the current user, logs it for observability,
  /// then always clears in-memory cache and detaches RevenueCat identity.
  static Future<void> clearSubscriptionCacheOnLogout({String? uid}) async {
    final effectiveUid = uid ?? _auth.currentUser?.uid;

    if (effectiveUid != null) {
      final cached = peekCachedSubscriptionDisplay(effectiveUid);
      final hadPlanInCache =
          cached != null &&
          (cached.isActive ||
              (cached.activeProductStoreId?.isNotEmpty ?? false) ||
              cached.expirationTime != null);
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] logout cache cleanup uid=$effectiveUid '
          'hadPlanInCache=$hadPlanInCache',
        );
      }
    }

    await logOutRevenueCat();
  }

  /// Firestore subscription cache must explicitly belong to this Firebase user (webhook sets [subscriptionOwnerId]).
  /// Rows without [subscriptionOwnerId] are not trusted for premium UI / access — avoids cross-account leakage on shared devices.
  static bool subscriptionFirestoreOwnedBy(
    SubscriptionState? state,
    String uid,
  ) {
    if (state == null) return false;
    final o = state.subscriptionOwnerId?.trim();
    if (o == null || o.isEmpty) return false;
    return o == uid;
  }

  /// Call after Firebase auth is ready (splash, home, post-login) so Play + RevenueCat
  /// match this uid. Invalidates cache and syncs store state.
  static Future<void> refreshRevenueCatIdentity(String uid) async {
    ensureSubscriptionCurrentListenerForPurchaseTokenLog(uid);
    await logInRevenueCat(uid);
    try {
      await Purchases.invalidateCustomerInfoCache();
    } catch (_) {}
    await _syncPurchasesBestEffort();
    // Do not block splash/navigation on BillingClient (can hang on some devices).
    unawaited(
      _syncPurchaseTokenFromBillingAfterIdentity(uid).catchError((Object e) {
        if (kDebugMode) {
          debugPrint(
            '[SubscriptionService] background purchase_token sync failed: $e',
          );
        }
      }),
    );
  }

  /// Ensure RevenueCat App User ID matches Firebase UID. Logs out first when switching accounts in-process.
  /// Returns [CustomerInfo] from [Purchases.logIn] when successful (authoritative right after bind).
  static Future<CustomerInfo?> logInRevenueCat(String uid) async {
    try {
      if (_lastPurchasesBoundUid != null && _lastPurchasesBoundUid != uid) {
        if (kDebugMode) {
          debugPrint(
            '[SubscriptionService] RC uid switch $_lastPurchasesBoundUid → $uid, logging out first',
          );
        }
        await _purchasesLogOutIgnoringAnonymous();
        _lastPurchasesBoundUid = null;
      }
      final logInResult = await Purchases.logIn(uid);
      _lastPurchasesBoundUid = uid;
      developer.log(
        'RC logIn uid=$uid created=${logInResult.created} '
        'activeEntitlements=${logInResult.customerInfo.entitlements.active.length} '
        'originalAppUserId=${logInResult.customerInfo.originalAppUserId}',
        name: 'SubscriptionService.subUI',
      );
      return logInResult.customerInfo;
    } catch (e, st) {
      if (kDebugMode) debugPrint('[SubscriptionService] logIn error: $e');
      ErrorHandler.handle(null, e, st, true);
      return null;
    }
  }

  /// Drops stale SDK cache, syncs Play/Store, then returns [CustomerInfo] whose [originalAppUserId]
  /// matches [uid] (avoids wrong `willRenew` / entitlements right after account switch).
  static Future<CustomerInfo?> _customerInfoMatchingUid(
    String uid, {
    CustomerInfo? seed,
  }) async {
    CustomerInfo? info = seed ?? await getCustomerInfo();
    for (var attempt = 0; attempt < 3; attempt++) {
      if (info == null) break;
      if (info.originalAppUserId == uid) {
        if (attempt > 0) {
          developer.log(
            'RC CustomerInfo matched uid after $attempt retries',
            name: 'SubscriptionService.subUI',
          );
        }
        return info;
      }
      developer.log(
        'RC CustomerInfo uid mismatch: want=$uid got=${info.originalAppUserId} '
        'attempt=$attempt — invalidate + sync + retry',
        name: 'SubscriptionService.subUI',
      );
      try {
        await Purchases.invalidateCustomerInfoCache();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SubscriptionService] invalidateCustomerInfoCache: $e');
        }
      }
      await _syncPurchasesBestEffort();
      await Future<void>.delayed(Duration(milliseconds: 120 * (attempt + 1)));
      info = await getCustomerInfo();
    }
    return info;
  }

  /// Read subscription state from Firestore.
  /// Prefers Users/{uid}/Subscription/current (subcollection); fallback Users/{uid}.subscription (legacy).
  static Future<SubscriptionState?> getSubscriptionStateFromFirestore(
    String uid,
  ) async {
    try {
      final currentRef = _firestore
          .collection('Users')
          .doc(uid)
          .collection('Subscription')
          .doc('current');
      final currentSnap = await currentRef.get();
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] getSubscriptionStateFromFirestore: Subscription/current exists=${currentSnap.exists}',
        );
      }
      if (currentSnap.exists && currentSnap.data() != null) {
        final data = currentSnap.data()!;
        if (kDebugMode) {
          debugPrint(
            '[SubscriptionService] Subscription/current data keys: ${data.keys.toList()} '
            'product_id=${data['product_id']} productId=${data['productId']} status=${data['status']}',
          );
        }
        final state = SubscriptionState.fromCurrentDoc(data);
        if (state != null) {
          if (kDebugMode) {
            debugPrint(
              '[SubscriptionService] state from current: productId=${state.productId} '
              'isActive=${state.isActive} expirationTime=${state.expirationTime}',
            );
          }
          return state;
        }
      }
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] fallback to Users/$uid subscription map',
        );
      }
      final userDoc = await _firestore.collection('Users').doc(uid).get();
      if (!userDoc.exists) {
        if (kDebugMode) {
          debugPrint(
            '[SubscriptionService] getSubscriptionStateFromFirestore: user doc not found',
          );
        }
        return null;
      }
      final state = SubscriptionState.fromUserData(userDoc.data());
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] state from user doc: ${state != null} productId=${state?.productId}',
        );
      }
      return state;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SubscriptionService] Firestore subscription read: $e');
      }
      ErrorHandler.handle(null, e, st, true);
      return null;
    }
  }

  /// Stream of subscription events for this user (RevenueCat webhook → `Subscription_logs`).
  static Stream<QuerySnapshot<Map<String, dynamic>>> subscriptionHistoryStream(
    String uid,
  ) {
    return _firestore
        .collection('Subscription_logs')
        .where('appUserId', isEqualTo: uid)
        .orderBy('serverReceivedAt', descending: true)
        .limit(100)
        .snapshots();
  }

  /// Get CustomerInfo from RevenueCat (source of truth for entitlement).
  static Future<CustomerInfo?> getCustomerInfo() async {
    try {
      return await Purchases.getCustomerInfo();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[SubscriptionService] getCustomerInfo: $e');
      ErrorHandler.handle(null, e, st, true);
      return null;
    }
  }

  /// Pull latest store state into RevenueCat before reading [CustomerInfo] (payment UI, expiry).
  static Future<void> _syncPurchasesBestEffort() async {
    try {
      await Purchases.syncPurchases();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SubscriptionService] syncPurchases (non-fatal): $e');
      }
    }
  }

  /// Whether the current user has an active subscription.
  /// Strict ownership: [subscriptionOwnerId] must equal [uid] (set by webhook).
  static Future<bool> isSubscriptionActive(String uid) async {
    final state = await getSubscriptionStateFromFirestore(uid);
    if (state == null || !subscriptionFirestoreOwnedBy(state, uid))
      return false;
    return state.isActive;
  }

  /// True when RevenueCat reports a **billing issue** on an active entitlement (e.g. payment
  /// failed in Google Play). Access may continue during grace — show payment UI to fix the card.
  static Future<bool> hasActiveSubscriptionBillingIssue(String uid) async {
    try {
      await refreshRevenueCatIdentity(uid);
      final info = await getCustomerInfo();
      if (info == null) return false;
      for (final e in info.entitlements.active.values) {
        final b = e.billingIssueDetectedAt;
        if (b != null && b.isNotEmpty) return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] hasActiveSubscriptionBillingIssue: $e',
        );
      }
      return false;
    }
  }

  /// Use only the part before ":" from product id (e.g. deluxe_monthly:deluxe-m → deluxe_monthly).
  static String normalizeProductId(String? productId) {
    if (productId == null || productId.isEmpty) return '';
    final trimmed = productId.trim();
    final idx = trimmed.indexOf(':');
    if (idx < 0) return trimmed;
    return trimmed.substring(0, idx).trim();
  }

  /// Old RevenueCat product ids (not used for new purchases). Map to new plan keys only for display/comparison.
  static const Map<String, String> _oldProductIdToNewPlanKey = {
    'viora_starter': 'starter_monthly',
    'viora_deluxe': 'deluxe_monthly',
    'viora_premium': 'premium_monthly',
    'viora_elite_2500': 'elite_monthly',
  };

  /// Normalize product id (strip after ":") and convert old keys to new plan keys. Use only new keys (starter_monthly, etc.).
  static String toProductIdForDisplay(String? productId) {
    final base = normalizeProductId(productId);
    if (base.isEmpty) return '';
    final lower = base.toLowerCase();
    return _oldProductIdToNewPlanKey[lower] ?? base;
  }

  /// Play/RC ids like `deluxe_monthly:deluxe-yearly` must match UI plan keys `deluxe_yearly`.
  /// Use this for [isPlanActive] and any "which card is active" logic.
  static String canonicalPlanKeyForActiveMatch(String? productId) {
    final raw = productId?.trim();
    if (raw == null || raw.isEmpty) return '';
    final lower = raw.toLowerCase();
    if (lower.contains(':')) {
      final idx = lower.indexOf(':');
      final suffix = lower.substring(idx + 1).trim();
      final fromSuffix = _suffixToCanonicalPlanKey(suffix);
      if (fromSuffix.isNotEmpty) return fromSuffix;
    }
    return toProductIdForDisplay(raw).toLowerCase();
  }

  /// Maps segment after `:` (e.g. `deluxe-yearly`) to `deluxe_yearly`.
  static String _suffixToCanonicalPlanKey(String suffix) {
    final s = suffix.trim().toLowerCase().replaceAll('_', '-');
    if (s.isEmpty) return '';
    final segs = s.split('-');
    if (segs.isEmpty) return '';
    final last = segs.last;
    if (last == 'yearly' || last == 'annual') {
      final tier = segs.sublist(0, segs.length - 1).join('_');
      return '${tier}_yearly';
    }
    if (last == 'monthly') {
      final tier = segs.sublist(0, segs.length - 1).join('_');
      return '${tier}_monthly';
    }
    return '';
  }

  /// Key under [Subscriptions/entitlementFeatures] for this subscriber.
  /// Prefer [entitlementId] from Firestore; else infer from [productId] (e.g. deluxe_monthly → deluxe).
  static String? entitlementFeaturesFirestoreKey({
    String? entitlementId,
    String? productId,
  }) {
    final e = entitlementId?.trim();
    if (e != null && e.isNotEmpty) return e.toLowerCase();
    final base = normalizeProductId(productId ?? '').toLowerCase();
    if (base.isEmpty) return null;
    const women = ['women_control', 'women_plus', 'women_power'];
    for (final w in women) {
      if (base == w || base.startsWith('${w}_')) return w;
    }
    final und = base.indexOf('_');
    if (und > 0) return base.substring(0, und);
    return base;
  }

  /// Compare cached subscription rows for “webhook updated something”.
  static bool subscriptionDisplaySnapshotEquals(
    SubscriptionDisplayInfo? a,
    SubscriptionDisplayInfo? b,
  ) {
    if (identical(a, b)) return true;
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.isActive == b.isActive &&
        a.activeProductStoreId == b.activeProductStoreId &&
        a.expirationTime == b.expirationTime &&
        a.willRenew == b.willRenew &&
        a.entitlementId == b.entitlementId &&
        (a.entitlementFeatures == b.entitlementFeatures ||
            ((a.entitlementFeatures?.features.length ?? 0) ==
                (b.entitlementFeatures?.features.length ?? 0)));
  }

  /// After a **successful** purchase only: fetch immediately, then every [pollInterval]
  /// until the purchased plan shows as active, or snapshot differs from [baseline]
  /// (webhook touched Firestore), or [maxAttempts] polls.
  ///
  /// First fetch has **no** leading delay so RC/Firestore can update right away.
  /// [onPoll] is invoked after each fetch so the UI can refresh without waiting for the
  /// full poll loop (subscribe button loader should already be cleared by the caller).
  static Future<SubscriptionDisplayInfo?> pollSubscriptionDisplayAfterPurchase(
    String uid,
    SubscriptionPlanDisplay purchasedPlan,
    SubscriptionDisplayInfo? baseline, {
    Duration pollInterval = const Duration(seconds: 3),
    int maxAttempts = 120,
    void Function(SubscriptionDisplayInfo? info)? onPoll,
  }) async {
    bool shouldStop(SubscriptionDisplayInfo? info) {
      if (info == null) return false;
      if (isPlanActive(purchasedPlan, info)) return true;
      if (!subscriptionDisplaySnapshotEquals(baseline, info)) return true;
      return false;
    }

    SubscriptionDisplayInfo? last;
    for (var i = 0; i < maxAttempts; i++) {
      if (i > 0) await Future<void>.delayed(pollInterval);
      last = await getSubscriptionDisplayInfo(uid, forceRefresh: true);
      onPoll?.call(last);
      if (shouldStop(last)) return last;
    }
    return last;
  }

  /// Live subscription info for UI: Firestore for ownership + plan cache.
  ///
  /// When [forceRefresh] is false, returns a recent cached result if available, or awaits an
  /// in-flight fetch for the same [uid] (avoids duplicate RC work with [preloadSubscriptionDisplayForUser]).
  static Future<SubscriptionDisplayInfo?> getSubscriptionDisplayInfo(
    String uid, {
    bool forceRefresh = false,
  }) async {
    if (uid.isEmpty) return null;

    if (!forceRefresh) {
      final hit = _subscriptionDisplayCacheHit(uid);
      if (hit != null) {
        developer.log(
          'getSubscriptionDisplayInfo cache hit uid=$uid',
          name: 'SubscriptionService.subUI',
        );
        return hit;
      }
      if (_subscriptionDisplayInfoInFlightUid == uid &&
          _subscriptionDisplayInfoInFlight != null) {
        developer.log(
          'getSubscriptionDisplayInfo awaiting in-flight uid=$uid',
          name: 'SubscriptionService.subUI',
        );
        return _subscriptionDisplayInfoInFlight!;
      }
    }

    final fut = _fetchSubscriptionDisplayInfo(uid);
    if (!forceRefresh) {
      _subscriptionDisplayInfoInFlightUid = uid;
      _subscriptionDisplayInfoInFlight = fut;
    }
    try {
      final result = await fut;
      // Avoid writing cache if user logged out while fetch was in flight.
      if (_authUidStill(uid)) {
        _subscriptionDisplayCache = result;
        _subscriptionDisplayCacheUid = uid;
        _subscriptionDisplayCacheAt = DateTime.now();
      }
      return result;
    } finally {
      if (!forceRefresh && _subscriptionDisplayInfoInFlightUid == uid) {
        _subscriptionDisplayInfoInFlight = null;
        _subscriptionDisplayInfoInFlightUid = null;
      }
    }
  }

  /// Network + merge (Firestore read runs in parallel with RC invalidate/sync/customerInfo).
  static Future<SubscriptionDisplayInfo?> _fetchSubscriptionDisplayInfo(
    String uid,
  ) async {
    try {
      developer.log(
        'getSubscriptionDisplayInfo fetch start uid=$uid',
        name: 'SubscriptionService.subUI',
      );
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] _fetchSubscriptionDisplayInfo uid=$uid',
        );
      }

      final loginCustomerInfo = await logInRevenueCat(uid);

      final stateFuture = getSubscriptionStateFromFirestore(uid);
      final rcFuture = () async {
        try {
          await Purchases.invalidateCustomerInfoCache();
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[SubscriptionService] invalidateCustomerInfoCache: $e');
          }
        }
        await _syncPurchasesBestEffort();
        return _customerInfoMatchingUid(uid, seed: loginCustomerInfo);
      }();

      final results = await Future.wait<Object?>([stateFuture, rcFuture]);
      final state = results[0] as SubscriptionState?;
      final customerInfo = results[1] as CustomerInfo?;

      final rcInfo = _subscriptionDisplayInfoFromCustomerInfo(customerInfo);

      _logRevenueCatEntitlementsForSubUi(customerInfo);

      SubscriptionDisplayInfo? fromFirestore;
      if (state != null && subscriptionFirestoreOwnedBy(state, uid)) {
        if (state.productId != null || state.expirationTime != null) {
          final canon = canonicalPlanKeyForActiveMatch(state.productId);
          final outId = canon.isNotEmpty
              ? canon
              : toProductIdForDisplay(state.productId);
          if (kDebugMode) {
            debugPrint(
              '[SubscriptionService] from Firestore: activeProductStoreId=$outId '
              'expirationTime=${state.expirationTime} isActive=${state.isActive}',
            );
          }
          developer.log(
            'Firestore owned: productId=${state.productId} displayKey=$outId '
            'exp=${state.expirationTime} isActive=${state.isActive}',
            name: 'SubscriptionService.subUI',
          );
          final eid = state.entitlementId?.trim();
          fromFirestore = SubscriptionDisplayInfo(
            activeProductStoreId: outId.isEmpty ? state.productId : outId,
            expirationTime: state.expirationTime,
            isActive: state.isActive,
            willRenew: state.willRenew,
            entitlementId: (eid != null && eid.isNotEmpty) ? eid : null,
            entitlementFeatures: state.entitlementFeatures,
          );
        }
      } else if (kDebugMode &&
          state != null &&
          (state.productId != null || state.expirationTime != null)) {
        debugPrint(
          '[SubscriptionService] Firestore cache not owned by uid=$uid '
          '(owner=${state.subscriptionOwnerId}) — may use RC fallback',
        );
        developer.log(
          'Firestore NOT owned by uid=$uid owner=${state.subscriptionOwnerId}',
          name: 'SubscriptionService.subUI',
        );
      }

      if (fromFirestore != null && fromFirestore.isActive) {
        developer.log(
          'banner willRenew from Firestore only: ${fromFirestore.willRenew}',
          name: 'SubscriptionService.subUI',
        );
        return SubscriptionDisplayInfo(
          activeProductStoreId: fromFirestore.activeProductStoreId,
          expirationTime:
              fromFirestore.expirationTime ?? rcInfo?.expirationTime,
          isActive: true,
          willRenew: fromFirestore.willRenew,
          entitlementId: fromFirestore.entitlementId,
          entitlementFeatures: fromFirestore.entitlementFeatures,
        );
      }

      if (rcInfo != null && rcInfo.isActive) {
        developer.log(
          'RC active exists but ignored (no Firestore owned+active state). '
          'strict ownership enforced for uid=$uid',
          name: 'SubscriptionService.subUI',
        );
      }

      if (fromFirestore != null) {
        return fromFirestore;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SubscriptionService] _fetchSubscriptionDisplayInfo: $e');
      }
      developer.log(
        'getSubscriptionDisplayInfo error: $e',
        name: 'SubscriptionService.subUI',
      );
      return null;
    }
  }

  static void _logRevenueCatEntitlementsForSubUi(CustomerInfo? info) {
    if (info == null) {
      developer.log(
        'CustomerInfo is null after sync (cannot read willRenew)',
        name: 'SubscriptionService.subUI',
      );
      return;
    }
    final active = info.entitlements.active;
    if (active.isEmpty) {
      developer.log(
        'RC entitlements.active is empty',
        name: 'SubscriptionService.subUI',
      );
      return;
    }
    for (final e in active.values) {
      developer.log(
        'RC entitlement: id=${e.identifier} productId=${e.productIdentifier} '
        'isActive=${e.isActive} willRenew=${e.willRenew} exp=${e.expirationDate}',
        name: 'SubscriptionService.subUI',
      );
    }
  }

  /// Active entitlement from RevenueCat SDK (same [uid] as [logInRevenueCat]).
  static SubscriptionDisplayInfo? _subscriptionDisplayInfoFromCustomerInfo(
    CustomerInfo? info,
  ) {
    if (info == null) return null;
    final active = info.entitlements.active;
    if (active.isEmpty) return null;
    EntitlementInfo? picked;
    for (final e in active.values) {
      if (e.isActive) {
        picked = e;
        break;
      }
    }
    picked ??= active.values.first;
    if (!picked.isActive) return null;

    DateTime? exp;
    final expRaw = picked.expirationDate;
    if (expRaw != null && expRaw.isNotEmpty) {
      exp = DateTime.tryParse(expRaw);
    }
    final now = DateTime.now();
    if (exp == null || !exp.isAfter(now)) {
      developer.log(
        'RC entitlement rejected for active display: '
        'product=${picked.productIdentifier} willRenew=${picked.willRenew} '
        'exp=$exp now=$now',
        name: 'SubscriptionService.subUI',
      );
      // For this app, subscriptions are monthly and must have a future expiry.
      // If expiry is missing/past, do not mark plan as active from RC fallback.
      return null;
    }
    final rawPid = picked.productIdentifier;
    final canon = canonicalPlanKeyForActiveMatch(rawPid);
    final norm = canon.isNotEmpty ? canon : toProductIdForDisplay(rawPid);
    final outId = norm.isEmpty ? rawPid : norm;
    return SubscriptionDisplayInfo(
      activeProductStoreId: outId,
      expirationTime: exp,
      isActive: true,
      willRenew: picked.willRenew,
      entitlementId: picked.identifier,
      entitlementFeatures: null,
    );
  }

  /// Normalize plan key for comparison: lowercase, spaces → underscores (e.g. "Deluxe Monthly" → "deluxe_monthly").
  static String _normalizePlanKey(String? key) {
    if (key == null || key.isEmpty) return '';
    return key.toLowerCase().replaceAll(' ', '_').trim();
  }

  /// Returns true if the given plan is the user's current active plan.
  /// Store ids like `deluxe_monthly:deluxe-yearly` are matched via [canonicalPlanKeyForActiveMatch] to `deluxe_yearly`.
  static bool isPlanActive(
    SubscriptionPlanDisplay plan,
    SubscriptionDisplayInfo? displayInfo,
  ) {
    if (kDebugMode) {
      debugPrint(
        '[SubscriptionService] isPlanActive: plan.planKey=${plan.planKey} plan.googlePlanKey=${plan.googlePlanKey} '
        'displayInfo=${displayInfo != null} isActive=${displayInfo?.isActive} activeProductStoreId=${displayInfo?.activeProductStoreId}',
      );
    }
    if (displayInfo == null || !displayInfo.isActive) {
      if (kDebugMode)
        debugPrint(
          '[SubscriptionService] isPlanActive: false (no displayInfo or not active)',
        );
      return false;
    }
    final rawProductId = displayInfo.activeProductStoreId;
    if (rawProductId == null || rawProductId.isEmpty) {
      if (kDebugMode)
        debugPrint(
          '[SubscriptionService] isPlanActive: false (activeProductStoreId null/empty)',
        );
      return false;
    }
    // `deluxe_monthly:deluxe-yearly` → deluxe_yearly (matches [googlePlanKey] on yearly cards)
    final activeProductKey = canonicalPlanKeyForActiveMatch(rawProductId);
    if (activeProductKey.isEmpty) {
      if (kDebugMode)
        debugPrint(
          '[SubscriptionService] isPlanActive: false (normalized activeProductKey empty)',
        );
      return false;
    }
    final planKeyNorm = _normalizePlanKey(plan.planKey);
    final rawGk = plan.googlePlanKey;
    final googleCanon = (rawGk != null && rawGk.isNotEmpty)
        ? canonicalPlanKeyForActiveMatch(rawGk)
        : '';
    final googleKeyNorm = (rawGk != null && rawGk.isNotEmpty)
        ? (googleCanon.isNotEmpty ? googleCanon : _normalizePlanKey(rawGk))
        : '';
    if (kDebugMode) {
      debugPrint(
        '[SubscriptionService] isPlanActive: rawProductId=$rawProductId activeProductKey=$activeProductKey '
        'planKeyNorm=$planKeyNorm googleKeyNorm=$googleKeyNorm',
      );
    }
    if (googleKeyNorm.isEmpty && planKeyNorm.isEmpty) {
      if (kDebugMode)
        debugPrint(
          '[SubscriptionService] isPlanActive: false (both plan keys empty)',
        );
      return false;
    }
    if (activeProductKey == googleKeyNorm || activeProductKey == planKeyNorm) {
      if (kDebugMode)
        debugPrint(
          '[SubscriptionService] isPlanActive: true (match googleKeyNorm or planKeyNorm)',
        );
      return true;
    }
    final mapped =
        _planIdToRevenueCatStoreId[planKeyNorm] ??
        _planIdToRevenueCatStoreId[googleKeyNorm];
    final result =
        mapped != null &&
        canonicalPlanKeyForActiveMatch(mapped) == activeProductKey;
    if (kDebugMode)
      debugPrint(
        '[SubscriptionService] isPlanActive: mapped=$mapped result=$result',
      );
    return result;
  }

  /// Male image sending: premium/elite (Firestore + strict owner), not RevenueCat SDK.
  static Future<bool> canSendImagesForUser(String uid) async {
    final state = await getSubscriptionStateFromFirestore(uid);
    if (state == null ||
        !subscriptionFirestoreOwnedBy(state, uid) ||
        !state.isActive) {
      return false;
    }
    final key = toProductIdForDisplay(state.productId).toLowerCase();
    return key.contains('premium') || key.contains('elite');
  }

  /// True when this device’s Play billing is tied to another Viora user (Scenario 4).
  ///
  /// **Light** check for subscription tab UI only: RC [originalAppUserId] ≠ uid (with active
  /// entitlements) or Firestore [subscriptionOwnerId] ≠ uid. Does **not** use Play
  /// `activeSubscriptions` so users without a subscription are not shown “blocked” by mistake.
  ///
  /// For blocking **before** opening Google Play billing, use [shouldBlockPurchaseBeforePlay].
  ///
  /// RevenueCat may still report [originalAppUserId] as an anonymous id briefly after
  /// [logIn]; do not treat that as another Viora account.
  static bool _isRevenueCatAnonymousAppUserId(String appUserId) {
    return appUserId.startsWith(r'$RCAnonymousID') ||
        appUserId.startsWith(r'$RCAnonymous');
  }

  /// Play-backed subscription visible in RC ([activeSubscriptions] and/or future entitlement expiry).
  ///
  /// Does **not** infer "active" from product id alone when [activeSubscriptions] is empty — RevenueCat
  /// can keep rows in [entitlements.active] with [EntitlementInfo.isActive]==true and no expiry after
  /// Google Play has removed the subscription; that caused false Scenario 4 blocks (Purchase unavailable).
  static bool _revenueCatShowsActiveSubscription(CustomerInfo? info) {
    if (info == null) return false;
    if (info.activeSubscriptions.isNotEmpty) return true;
    final now = DateTime.now();
    for (final e in info.entitlements.active.values) {
      if (!e.isActive) continue;
      final expRaw = e.expirationDate;
      if (expRaw != null && expRaw.isNotEmpty) {
        final d = DateTime.tryParse(expRaw);
        if (d != null && d.isAfter(now)) {
          return true;
        }
        continue;
      }
      // Per-entitlement expiry often missing; fall back to customer-level window only.
      final latestRaw = info.latestExpirationDate;
      if (latestRaw != null && latestRaw.isNotEmpty) {
        final ld = DateTime.tryParse(latestRaw);
        if (ld != null && ld.isAfter(now)) {
          return true;
        }
      }
    }
    return false;
  }

  /// RevenueCat snapshot for account-deletion UX: Play billing can continue after the app account is removed.
  static Future<({bool hasActiveSubscription, List<String> activeProductIds})>
  getSubscriptionSnapshotForAccountDeletion() async {
    try {
      final info = await Purchases.getCustomerInfo();
      final has = _revenueCatShowsActiveSubscription(info);
      final ids = <String>{...info.activeSubscriptions};
      if (has && ids.isEmpty) {
        for (final e in info.entitlements.active.values) {
          if (e.isActive) ids.add(e.productIdentifier);
        }
      }
      return (hasActiveSubscription: has, activeProductIds: ids.toList());
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] getSubscriptionSnapshotForAccountDeletion: $e',
        );
      }
      return (hasActiveSubscription: false, activeProductIds: <String>[]);
    }
  }

  /// **Strict** — run immediately before [Purchases.purchasePackage] / Play sheet.
  ///
  /// Covers:
  /// - Another RC app user id owns the Play sub ([originalAppUserId] ≠ uid).
  /// - Firestore cache says subscription belongs to another Firebase uid.
  /// - **Scenario 4**: This Google Play account still has an active subscription in RC
  ///   (`activeSubscriptions` / subscription entitlements) but Firestore does not record
  ///   [subscriptionOwnerId] == uid (e.g. User A purchased, User B logged in; RC may transfer
  ///   `originalAppUserId` to B so the light check alone is not enough).
  /// - **Scenario 5**: Same Play account, purchase belongs to another Viora uid: RC shows no
  ///   entitlements / active subs but [CustomerInfo.latestExpirationDate] is still in the
  ///   future and [allPurchasedProductIdentifiers] is non-empty — [_revenueCatShowsActiveSubscription]
  ///   stays false so Scenario 4 alone does not run. Also: an extra [Purchases.syncPurchases]
  ///   after [refreshRevenueCatIdentity] may throw receipt-in-use (the identity refresh swallows
  ///   sync errors in [_syncPurchasesBestEffort]).
  ///
  /// Uses a short Firestore re-check to avoid false positives when the webhook lags RC right
  /// after a legitimate purchase on this uid.
  ///
  /// **Important:** Do not use [_customerInfoMatchingUid] here — it retries until
  /// `originalAppUserId == uid`, which hides Scenario 4 (User A purchased, User B logged in;
  /// RC may still show A's id, or we need raw Play/entitlement state before RC "aligns" app user id).
  static Future<bool> shouldBlockPurchaseBeforePlay(
    String currentUserId,
  ) async {
    await refreshRevenueCatIdentity(currentUserId);

    // Android: [purchases_flutter] `Purchases.syncPurchases()` completes the method channel
    // before the native POST /receipts finishes, so [ReceiptAlreadyInUseError] only appears
    // in logcat. [MainActivity] uses [SyncPurchasesCallback] and returns the error to Dart.
    if (await _androidNativeSyncIndicatesReceiptConflict()) {
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] shouldBlockPurchaseBeforePlay: native Android sync '
          'onError (receipt conflict) — block before Play sheet',
        );
      }
      return true;
    }

    // iOS / other: try Dart `syncPurchases` in case the plugin forwards errors.
    if (defaultTargetPlatform != TargetPlatform.android) {
      try {
        await Purchases.syncPurchases();
      } catch (e) {
        if (_syncPurchasesErrorIsOtherSubscriberReceipt(e)) {
          if (kDebugMode) {
            debugPrint(
              '[SubscriptionService] shouldBlockPurchaseBeforePlay: syncPurchases '
              'receipt conflict — block before Play sheet: $e',
            );
          }
          return true;
        }
      }
    }

    var info = await getCustomerInfo();
    var state = await getSubscriptionStateFromFirestore(currentUserId);

    if (kDebugMode) {
      final orig = info?.originalAppUserId ?? '';
      debugPrint(
        '[SubscriptionService] shouldBlockPurchaseBeforePlay: uid=$currentUserId '
        'originalAppUserId=$orig activeSubs=${info?.activeSubscriptions.length ?? 0} '
        'entitlements=${info?.entitlements.active.length ?? 0} '
        'firestoreOwner=${state?.subscriptionOwnerId} '
        'latestExp=${info?.latestExpirationDate} '
        'purchasedIds=${info?.allPurchasedProductIdentifiers.length ?? 0}',
      );
    }

    // Another RevenueCat app user id still owns this device's billing (explicit mismatch).
    if (info != null) {
      final orig = info.originalAppUserId.trim();
      final hasRcActivity =
          info.entitlements.active.isNotEmpty ||
          info.activeSubscriptions.isNotEmpty;
      if (hasRcActivity &&
          orig.isNotEmpty &&
          orig != currentUserId &&
          !_isRevenueCatAnonymousAppUserId(orig)) {
        return true;
      }
    }

    if (state != null && state.isActive) {
      final ownerId = state.subscriptionOwnerId?.trim();
      if (ownerId != null && ownerId.isNotEmpty && ownerId != currentUserId) {
        return true;
      }
    }

    if (_inactiveFirestoreSubscriptionMismatchesRcReceipt(state, info)) {
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] shouldBlockPurchaseBeforePlay: inactive Firestore plan '
          'does not match RC purchased SKUs (likely receipt owned by another Viora user)',
        );
      }
      return true;
    }

    if (_customerInfoSuggestsPlaySubNotOwnedByThisFirebaseUser(
      info,
      state,
      currentUserId,
    )) {
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] shouldBlockPurchaseBeforePlay: Scenario 5 '
          '(future exp, purchased SKUs, no entitlement, not active Firestore owner)',
        );
      }
      return true;
    }

    // Play subscription active in RC but Firestore does not attribute this Firebase uid (Scenario 4).
    // If Firestore already says inactive/expired and Play has no SKU, trust that — RC entitlements can lag.
    final skipScenario4StaleRc =
        info != null &&
        info.activeSubscriptions.isEmpty &&
        state != null &&
        !state.isActive;

    if (!skipScenario4StaleRc &&
        _revenueCatShowsActiveSubscription(info) &&
        !subscriptionFirestoreOwnedBy(state, currentUserId)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      await _syncPurchasesBestEffort();
      state = await getSubscriptionStateFromFirestore(currentUserId);
      if (subscriptionFirestoreOwnedBy(state, currentUserId)) {
        return false;
      }
      info = await getCustomerInfo();
      if (!_revenueCatShowsActiveSubscription(info)) {
        return false;
      }
      return true;
    }
    if (skipScenario4StaleRc && kDebugMode) {
      debugPrint(
        '[SubscriptionService] shouldBlockPurchaseBeforePlay: Scenario 4 skipped — '
        'Firestore inactive + no Play activeSubscriptions',
      );
    }

    return false;
  }

  static Future<bool> shouldBlockPurchaseDueToOtherVioraAccount(
    String currentUserId,
  ) async {
    await refreshRevenueCatIdentity(currentUserId);

    final info = await _customerInfoMatchingUid(currentUserId);
    final state = await getSubscriptionStateFromFirestore(currentUserId);

    if (info != null && info.entitlements.active.isNotEmpty) {
      final orig = info.originalAppUserId.trim();
      if (orig.isNotEmpty &&
          orig != currentUserId &&
          !_isRevenueCatAnonymousAppUserId(orig)) {
        return true;
      }
    }

    if (state != null && state.isActive) {
      final ownerId = state.subscriptionOwnerId?.trim();
      if (ownerId != null && ownerId.isNotEmpty && ownerId != currentUserId) {
        return true;
      }
    }

    return false;
  }

  /// Scenario 4: This device's Google Play account has a sub linked to another Viora user.
  static Future<bool> isWrongAccount(String currentUserId) async {
    return shouldBlockPurchaseDueToOtherVioraAccount(currentUserId);
  }

  // --- Entitlement Features Helpers (UI convenience methods) ---

  /// Get subscription features for the current user (ready for UI consumption).
  /// Returns [PlanFeatures] with all feature limits and enabled statuses.
  /// Perfect for displaying feature lists, checking limits before allowing actions.
  static Future<PlanFeatures?> getEntitlementFeaturesForUser(String uid) async {
    final state = await getSubscriptionStateFromFirestore(uid);
    if (state == null || !subscriptionFirestoreOwnedBy(state, uid)) {
      return null;
    }
    return state.entitlementFeatures;
  }

  /// Get feature limit for a specific feature (e.g. messaging).
  /// Returns null if feature not found or subscription inactive.
  /// Usage: `await SubscriptionService.getFeatureLimit(uid, 'messaging')` → 100
  static Future<int?> getFeatureLimit(String uid, String featureKey) async {
    final features = await getEntitlementFeaturesForUser(uid);
    return features?.getFeatureLimit(featureKey);
  }

  /// Check if a specific feature is enabled for the user.
  /// Usage: `await SubscriptionService.isFeatureEnabled(uid, 'ai_bio')` → true
  static Future<bool> isFeatureEnabled(String uid, String featureKey) async {
    final features = await getEntitlementFeaturesForUser(uid);
    return features?.isFeatureEnabled(featureKey) ?? false;
  }

  /// Get specific feature config (enabled, limit, period).
  /// Usage: `await SubscriptionService.getFeatureConfig(uid, 'messaging')`
  static Future<FeatureConfig?> getFeatureConfig(
    String uid,
    String featureKey,
  ) async {
    final features = await getEntitlementFeaturesForUser(uid);
    return features?.getFeature(featureKey);
  }

  /// Firestore plan id → RevenueCat / Play **store** product id (see RC dashboard).
  /// Many products use `tier_monthly:tier-monthly|yearly` even for yearly SKUs.
  static const Map<String, String> _planIdToRevenueCatStoreId = {
    'starter_monthly': 'starter_monthly:starter-monthly',
    'deluxe_monthly': 'deluxe_monthly:deluxe-monthly',
    'premium_monthly': 'premium_monthly:premium-monthly',
    'elite_monthly': 'elite_monthly:elite-monthly',
    'starter_yearly': 'starter_monthly:starter-yearly',
    'deluxe_yearly': 'deluxe_monthly:deluxe-yearly',
    'premium_yearly': 'premium_monthly:premium-yearly',
    'elite_yearly': 'elite_monthly:elite-yearly',
    'women_control_monthly': 'women_control:women-control-monthly',
    'women_plus_monthly': 'women_plus:women-plus-monthly',
    'women_power_monthly': 'women_power:women-power-monthly',
    'women_control_yearly': 'women_control:women-control-yearly',
    'women_plus_yearly': 'women_plus:women-plus-yearly',
    'women_power_yearly': 'women_power:women-power-yearly',
    'viora_starter': 'starter_monthly:starter-monthly',
    'viora_deluxe': 'deluxe_monthly:deluxe-monthly',
    'viora_premium': 'premium_monthly:premium-monthly',
    'viora_elite_2500': 'elite_monthly:elite-monthly',
  };

  /// Builds Play/RC ids like `deluxe_monthly:deluxe-yearly` from app keys `deluxe_yearly`.
  /// Women tiers use `women_control:women-control-yearly` (see RevenueCat product catalog).
  static List<String> _colonStylePlayStoreIds(String planKey) {
    final k = planKey.trim().toLowerCase();
    final m = RegExp(r'^([a-z0-9_]+)_(yearly|monthly)$').firstMatch(k);
    if (m == null) return const [];
    final tier = m.group(1)!;
    final period = m.group(2)!;
    final hyphen = tier.replaceAll('_', '-');
    if (tier.startsWith('women_')) {
      return ['$tier:$hyphen-$period'];
    }
    return ['${tier}_monthly:$tier-$period'];
  }

  /// Hyphen vs underscore and Play base-plan shapes (deluxe-monthly ↔ deluxe_monthly).
  static Set<String> _productIdVariants(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return {};
    final lower = s.toLowerCase();
    final out = <String>{s, lower};
    out.add(lower.replaceAll('-', '_'));
    out.add(lower.replaceAll('_', '-'));
    if (lower.contains(':')) {
      final prefix = lower.split(':').first;
      out.add(prefix);
      out.add(prefix.replaceAll('-', '_'));
    }
    return out;
  }

  /// Find RevenueCat Package by googlePlanKey (plan id from Firestore, e.g. elite_monthly).
  /// Tries exact match, mapped store id, alternate store ids. Retries once if offerings empty.
  static Future<Package?> findPackageByGooglePlanKey(
    String? googlePlanKey,
  ) async {
    if (googlePlanKey == null || googlePlanKey.isEmpty) return null;
    try {
      Offerings offerings = await Purchases.getOfferings();
      if (kDebugMode) {
        debugPrint(
          '[SubscriptionService] Looking for googlePlanKey: "$googlePlanKey"',
        );
      }
      if (offerings.all.isEmpty || offerings.current == null) {
        await Future.delayed(const Duration(milliseconds: 500));
        offerings = await Purchases.getOfferings();
      }
      if (kDebugMode && offerings.all.isNotEmpty) {
        for (final entry in offerings.all.entries) {
          for (final pkg in entry.value.availablePackages) {
            debugPrint(
              '[SubscriptionService]   Offering "${entry.key}" pkg: id=${pkg.identifier}, storeId=${pkg.storeProduct.identifier}',
            );
          }
        }
      }
      final keyLower = googlePlanKey.trim().toLowerCase();
      final keyPrefix = keyLower.contains(':')
          ? keyLower.split(':').first
          : keyLower;
      final idsToTry = <String>{
        ..._productIdVariants(googlePlanKey),
        ..._productIdVariants(keyPrefix),
        if (_planIdToRevenueCatStoreId[keyLower] != null)
          _planIdToRevenueCatStoreId[keyLower]!,
        if (_planIdToRevenueCatStoreId[keyPrefix] != null)
          _planIdToRevenueCatStoreId[keyPrefix]!,
        ..._colonStylePlayStoreIds(googlePlanKey),
      }..removeWhere((e) => e.isEmpty);

      Package? matchBy(String id) {
        if (id.isEmpty) return null;
        final idLower = id.toLowerCase();
        for (final offering in offerings.all.values) {
          for (final pkg in offering.availablePackages) {
            final pkgId = pkg.identifier;
            final storeId = pkg.storeProduct.identifier;
            final pkgIdLower = pkgId.toLowerCase();
            final storeIdLower = storeId.toLowerCase();
            if (pkgId == id || storeId == id) return pkg;
            if (pkgIdLower == idLower || storeIdLower == idLower) return pkg;
            if (storeIdLower.contains(idLower) ||
                idLower.contains(storeIdLower))
              return pkg;
          }
        }
        return null;
      }

      for (final id in idsToTry) {
        final pkg = matchBy(id);
        if (pkg != null) {
          if (kDebugMode)
            debugPrint(
              '[SubscriptionService] Matched "$googlePlanKey" via id "$id"',
            );
          return pkg;
        }
      }
      return null;
    } catch (e, st) {
      if (kDebugMode) debugPrint('[SubscriptionService] findPackage: $e');
      ErrorHandler.handle(null, e, st, true);
      return null;
    }
  }

  /// Load monthly subscription product by store id. Use when product is not in an Offering.
  /// Tries multiple product IDs (RevenueCat/Play Store may use different formats).
  static Future<StoreProduct?> findStoreProductByPlanKey(
    String? googlePlanKey,
  ) async {
    if (googlePlanKey == null || googlePlanKey.isEmpty) return null;
    try {
      final keyLower = googlePlanKey.trim().toLowerCase();
      final keyPrefix = keyLower.contains(':')
          ? keyLower.split(':').first
          : keyLower;
      final idsToTry = <String>{
        ..._productIdVariants(googlePlanKey),
        ..._productIdVariants(keyPrefix),
        if (_planIdToRevenueCatStoreId[keyLower] != null)
          _planIdToRevenueCatStoreId[keyLower]!,
        if (_planIdToRevenueCatStoreId[keyPrefix] != null)
          _planIdToRevenueCatStoreId[keyPrefix]!,
        ..._colonStylePlayStoreIds(googlePlanKey),
        if (keyPrefix.contains('starter')) 'viora_starter',
        if (keyPrefix.contains('deluxe')) 'viora_deluxe',
        if (keyPrefix.contains('premium')) 'viora_premium',
        if (keyPrefix.contains('elite')) 'viora_elite_2500',
        if (keyPrefix.contains('women')) ..._productIdVariants(keyPrefix),
      }..removeWhere((s) => s.isEmpty);
      final storeIds = idsToTry.toList();
      var products = await Purchases.getProducts(
        storeIds,
        productCategory: ProductCategory.subscription,
        type: PurchaseType.subs,
      );
      if (products.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 300));
        products = await Purchases.getProducts(
          storeIds,
          productCategory: ProductCategory.subscription,
          type: PurchaseType.subs,
        );
      }
      if (products.isEmpty) return null;
      final keyNorm = keyPrefix.replaceAll(' ', '_');
      final match = products.where((p) {
        final id = p.identifier.toLowerCase();
        return id == keyLower ||
            id == keyNorm ||
            id.contains(keyPrefix) ||
            keyPrefix.contains(id.split('_').first);
      }).firstOrNull;
      if (match != null && kDebugMode)
        debugPrint(
          '[SubscriptionService] Loaded product via getProducts: ${match.identifier}',
        );
      return match ?? products.first;
    } catch (e, st) {
      if (kDebugMode) debugPrint('[SubscriptionService] findStoreProduct: $e');
      ErrorHandler.handle(null, e, st, true);
      return null;
    }
  }

  /// Run subscription purchase with scenario checks. Returns true on success.
  /// Allows purchasing a new plan even when user already has one (upgrade/downgrade).
  /// Handles: Scenario 4 (wrong account), then purchase.
  ///
  /// [onWrongAccount] optional UI when Play billing is tied to another Viora user
  /// (avoids [SubscriptionService] importing dialog code / circular imports).
  static Future<bool> purchaseSubscription(
    BuildContext context,
    SubscriptionPlanDisplay plan, {
    Future<void> Function(BuildContext context)? onWrongAccount,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      ErrorHandler.handle(context, UnauthorizedException(), null);
      return false;
    }

    if (await shouldBlockPurchaseBeforePlay(uid)) {
      if (context.mounted) {
        if (onWrongAccount != null) {
          await onWrongAccount(context);
        } else {
          ErrorHandler.showError(
            context,
            'This Google Play account has an active subscription linked to another Viora account.',
          );
        }
      }
      return false;
    }

    final googlePlanKey = plan.googlePlanKey;
    if (googlePlanKey == null || googlePlanKey.isEmpty) {
      ErrorHandler.handle(
        context,
        PaymentException(message: 'This plan is not available for purchase.'),
        null,
      );
      return false;
    }

    final state = await getSubscriptionStateFromFirestore(uid);
    final customerInfo = await getCustomerInfo();
    final hadActivePlan =
        customerInfo?.entitlements.active.isNotEmpty ??
        state?.isActive ??
        false;

    Package? pkg = await findPackageByGooglePlanKey(googlePlanKey);
    StoreProduct? storeProduct = pkg?.storeProduct;

    if (pkg == null) {
      storeProduct = await findStoreProductByPlanKey(googlePlanKey);
      if (storeProduct == null) {
        if (context.mounted) {
          ErrorHandler.handle(
            context,
            PaymentException(
              message:
                  'This plan is not available right now. Please try again later.',
            ),
            null,
          );
        }
        return false;
      }
    }

    try {
      if (pkg != null) {
        await Purchases.purchasePackage(pkg);
      } else {
        await Purchases.purchaseStoreProduct(storeProduct!);
      }
      final info = await Purchases.getCustomerInfo();
      final success = info.entitlements.active.isNotEmpty;
      if (success && context.mounted) {
        final message = hadActivePlan
            ? 'Plan updated. Your new benefits are now active.'
            : 'Subscription activated. Premium benefits are now active.';
        ErrorHandler.showSuccess(context, message);
      }
      if (success) {
        final storeId =
            pkg?.storeProduct.identifier ?? storeProduct?.identifier;
        await _syncAndroidPurchaseTokenToFirestore(uid, storeId);
      }
      return success;
    } catch (e, st) {
      // When Play says "already subscribed" / duplicate purchase: sync then decide
      // using Firestore ownership — RC may show entitlements for the logged-in uid
      // even when the subscription is tied to another Viora account on this Play user.
      final looksAlreadyOwned = _purchaseErrorLooksLikeAlreadySubscribed(e);
      if (looksAlreadyOwned) {
        developer.log(
          'purchaseSubscription already-owned path: $e',
          name: 'SubscriptionService.subUI',
        );
        try {
          await Purchases.syncPurchases();
          final restored = await Purchases.getCustomerInfo();
          final stateAfter = await getSubscriptionStateFromFirestore(uid);
          final firestoreOwnedActive =
              subscriptionFirestoreOwnedBy(stateAfter, uid) &&
              (stateAfter?.isActive ?? false);

          if (firestoreOwnedActive) {
            if (context.mounted) {
              final msg = _revenueCatShowsActiveSubscription(restored)
                  ? 'Subscription already active on this Play account. Restored successfully.'
                  : 'Subscription active for your account.';
              ErrorHandler.showSuccess(context, msg);
            }
            final storeId =
                pkg?.storeProduct.identifier ?? storeProduct?.identifier;
            await _syncAndroidPurchaseTokenToFirestore(uid, storeId);
            return true;
          }
          if (context.mounted) {
            if (onWrongAccount != null) {
              await onWrongAccount(context);
            } else {
              ErrorHandler.showError(
                context,
                'This Google Play account has an active subscription linked to another Viora account.',
              );
            }
          }
          return false;
        } catch (restoreError) {
          developer.log(
            'purchaseSubscription already-owned recovery failed: $restoreError',
            name: 'SubscriptionService.subUI',
          );
        }
      }
      if (e is AppException) {
        if (context.mounted) ErrorHandler.showError(context, e.userMessage);
        return false;
      }
      final appEx = ErrorHandler.convert(e, st);
      if (context.mounted) ErrorHandler.showError(context, appEx.userMessage);
      return false;
    }
  }
}
