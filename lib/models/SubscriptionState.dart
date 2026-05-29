import 'package:cloud_firestore/cloud_firestore.dart';

/// Feature configuration for subscription plans (enabled flag, quota limits, etc).
class FeatureConfig {
  final bool? enabled;
  final int? limit;
  final int? period;

  const FeatureConfig({this.enabled, this.limit, this.period});

  factory FeatureConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const FeatureConfig();

    return FeatureConfig(
      enabled: map['enabled'] as bool?,
      limit: map['limit'] as int?,
      period: map['period'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (enabled != null) 'enabled': enabled,
      if (limit != null) 'limit': limit,
      if (period != null) 'period': period,
    };
  }
}

/// Collection of features for a subscription plan (e.g. premium, elite, deluxe).
class PlanFeatures {
  final Map<String, FeatureConfig> features;

  const PlanFeatures({required this.features});

  factory PlanFeatures.fromMap(Map<String, dynamic>? map) {
    if (map == null) return PlanFeatures(features: {});

    final parsed = <String, FeatureConfig>{};
    map.forEach((key, value) {
      parsed[key] = FeatureConfig.fromMap(value as Map<String, dynamic>?);
    });

    return PlanFeatures(features: parsed);
  }

  Map<String, dynamic> toMap() {
    final result = <String, dynamic>{};
    features.forEach((key, value) {
      result[key] = value.toMap();
    });
    return result;
  }

  FeatureConfig? getFeature(String key) {
    return features[key];
  }

  bool isFeatureEnabled(String key) {
    return getFeature(key)?.enabled ?? false;
  }

  int? getFeatureLimit(String key) {
    return getFeature(key)?.limit;
  }
}

/// Subscription/entitlement state stored on User document (written by webhook, read by app).
/// RevenueCat = source of truth for entitlements; Firestore = cache + features.
class SubscriptionState {
  final String? entitlementId;
  final String? entitlementStatus;
  final DateTime? entitlementUpdatedTime;
  final String? subscriptionOwnerId;
  final String? productId;
  final DateTime? expirationTime;

  /// From RevenueCat webhook → Firestore. false after CANCELLATION until period ends.
  final bool willRenew;

  /// Feature configuration for the active subscription plan (e.g. messaging limits, enabled features).
  final PlanFeatures? entitlementFeatures;

  const SubscriptionState({
    this.entitlementId,
    this.entitlementStatus,
    this.entitlementUpdatedTime,
    this.subscriptionOwnerId,
    this.productId,
    this.expirationTime,
    this.willRenew = true,
    this.entitlementFeatures,
  });

  bool get isActive {
    final status = entitlementStatus?.toLowerCase();
    if (status == 'expired') return false;
    final ok = status == 'active' || (status == null && productId != null);
    if (!ok) return false;
    // Monthly subs always have an expiry from the webhook. If it's missing, the
    // cache is incomplete/stale — do not treat as active (avoids ACTIVE_PACK +
    // "renews on: —" when EXPIRATION cleared dates but left status behind).
    if (expirationTime == null) return false;
    return expirationTime!.isAfter(DateTime.now());
  }

  /// Read from Users/{uid}/Subscription/current document (flat keys).
  static SubscriptionState? fromCurrentDoc(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return null;
    final exp =
        data['expiration_time'] ??
        data['expirationTime'] ??
        data['expiry_date'] ??
        data['expires_at'];
    final status =
        data['entitlement_status'] ??
        data['entitlementStatus'] ??
        data['status'];
    final productId = data['productId'] ?? data['product_id'];
    final wr = data['willRenew'];
    final willRenewBool = wr == null
        ? true
        : (wr is bool ? wr : wr.toString().toLowerCase() == 'true');

    // Parse entitlementFeatures map
    final entitlementFeaturesRaw = data['entitlementFeatures'];
    PlanFeatures? entitlementFeatures;
    if (entitlementFeaturesRaw is Map<String, dynamic>) {
      entitlementFeatures = PlanFeatures.fromMap(entitlementFeaturesRaw);
    }

    return SubscriptionState(
      entitlementId: data['entitlementId'] as String?,
      entitlementStatus: status?.toString(),
      entitlementUpdatedTime: _parseTimestamp(
        data['entitlement_updated_time'] ?? data['entitlementUpdatedTime'],
      ),
      subscriptionOwnerId: data['subscriptionOwnerId'] as String?,
      productId: productId?.toString(),
      expirationTime: _parseTimestamp(exp),
      willRenew: willRenewBool,
      entitlementFeatures: entitlementFeatures,
    );
  }

  /// Read from Users/{uid} document. Expects a "subscription" map (legacy).
  static SubscriptionState? fromUserData(Map<String, dynamic>? userData) {
    if (userData == null) return null;
    final sub = userData['subscription'];
    if (sub is! Map<String, dynamic>) return null;
    return fromCurrentDoc(sub);
  }

  static DateTime? _parseTimestamp(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
