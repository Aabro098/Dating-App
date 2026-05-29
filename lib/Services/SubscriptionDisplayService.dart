import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/SubscriptionPlanDisplay.dart';
import 'SubscriptionService.dart';

/// Loads subscription UI from Firestore:
/// - [Subscriptions/billingPeriods] → `default`: `monthly` | `yearly`
/// - [Subscriptions/plans] → gender → monthly[] | yearly[]: entitlementId, basePlan, …
/// - [Subscriptions/displayData] → monthly | yearly → { planKey: { planName, … } }
///
/// **Important:** [entitlementId] (e.g. women_control) often does **not** match [displayData] map keys
/// (e.g. deluxe). We merge by matching [basePlan] fields and fall back to derived keys so Subscribe
/// gets a [googlePlanKey] that matches RevenueCat / Play.
class SubscriptionDisplayService {
  static const String _collectionSubscriptions = 'Subscriptions';
  static const String _docDisplayData = 'displayData';
  static const String _docBillingPeriods = 'billingPeriods';
  static const String _fieldPlanOrder = 'planOrder';
  static const String _docPlans = 'plans';
  static const String _docEntitlementFeatures = 'entitlementFeatures';

  /// Labels for keys under [Subscriptions/entitlementFeatures/{tier}].
  static const Map<String, String> _entitlementFeatureTitles = {
    'messaging': 'Messaging',
    'ai_bio': 'AI Bio generation',
    'image_view': 'Image view',
    'online_only': 'Online users only',
    'about_visible': 'About visible',
    'minimum_photos_slider': 'Minimum photos slider',
    'in_top_picks': 'In Top Picks',
    'verified_profiles': 'Verified profiles',
  };

  /// Fixed UI order for known tiers (prefix / equality match).
  static const List<String> _displayOrder = [
    'starter_monthly',
    'deluxe_monthly',
    'premium_monthly',
    'elite_monthly',
    'starter_yearly',
    'deluxe_yearly',
    'premium_yearly',
    'elite_yearly',
    'women_control',
    'women_plus',
    'women_power',
  ];

  static int _orderIndexForPlanKey(String planKey) {
    final k = planKey.toLowerCase().replaceAll(' ', '_');
    for (var i = 0; i < _displayOrder.length; i++) {
      final o = _displayOrder[i];
      if (k == o || k.contains(o) || o.contains(k)) return i;
    }
    return _displayOrder.length;
  }

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// `deluxe-monthly` → `deluxe`, `women-control-monthly` → `women_control`
  static String? _displayKeyFromBasePlan(String? basePlan) {
    if (basePlan == null || basePlan.isEmpty) return null;
    final parts = basePlan.toLowerCase().trim().split('-');
    if (parts.length < 2) return parts.isEmpty ? null : parts.first;
    final last = parts.last;
    if (last == 'monthly' || last == 'yearly') {
      return parts.sublist(0, parts.length - 1).join('_');
    }
    return parts.join('_');
  }

  /// Prefer Play-style ids: `deluxe-monthly` → `deluxe_monthly` (common RC / store shape).
  static String _basePlanToUnderscoreId(String basePlan) {
    return basePlan.trim().toLowerCase().replaceAll('-', '_');
  }

  /// Find displayData entry (monthly or yearly map) for one catalog row from [Subscriptions/plans].
  static MapEntry<String, Map<String, dynamic>>? _findDisplayForCatalogEntry(
    Map<String, dynamic> displayPeriodMap,
    Map<String, dynamic> catalogEntry,
  ) {
    final entitlementId = catalogEntry['entitlementId']?.toString().trim();
    final basePlan = catalogEntry['basePlan']?.toString().trim();

    if (entitlementId != null &&
        entitlementId.isNotEmpty &&
        displayPeriodMap[entitlementId] is Map<String, dynamic>) {
      return MapEntry(
        entitlementId,
        Map<String, dynamic>.from(
          displayPeriodMap[entitlementId] as Map<String, dynamic>,
        ),
      );
    }

    if (basePlan != null && basePlan.isNotEmpty) {
      final bpLower = basePlan.toLowerCase();
      for (final e in displayPeriodMap.entries) {
        if (e.value is! Map<String, dynamic>) continue;
        final m = e.value as Map<String, dynamic>;
        final db = m['basePlan']?.toString().trim().toLowerCase();
        if (db != null && db == bpLower) {
          return MapEntry(e.key, Map<String, dynamic>.from(m));
        }
      }
    }

    final derived = _displayKeyFromBasePlan(basePlan);
    if (derived != null &&
        derived.isNotEmpty &&
        displayPeriodMap[derived] is Map<String, dynamic>) {
      return MapEntry(
        derived,
        Map<String, dynamic>.from(
          displayPeriodMap[derived] as Map<String, dynamic>,
        ),
      );
    }

    for (final e in displayPeriodMap.entries) {
      if (e.value is! Map<String, dynamic>) continue;
      final m = e.value as Map<String, dynamic>;
      final dgk =
          (m['googlePlanKey'] ?? m['productId'])?.toString().trim().toLowerCase();
      if (dgk == null || dgk.isEmpty) continue;
      if (basePlan != null &&
          dgk == _basePlanToUnderscoreId(basePlan)) {
        return MapEntry(e.key, Map<String, dynamic>.from(m));
      }
      if (entitlementId != null &&
          (dgk.contains(entitlementId.toLowerCase()) ||
              entitlementId.toLowerCase().contains(dgk.split('_').first))) {
        return MapEntry(e.key, Map<String, dynamic>.from(m));
      }
    }

    return null;
  }

  /// Purchase / RevenueCat id: prefer [Subscriptions/plans] row fields over
  /// [displayData], because when `displayData.yearly` is missing we merge monthly
  /// display copy and its `googlePlanKey` would wrongly point at monthly products.
  static String? _resolveGooglePlanKey(
    Map<String, dynamic> catalogEntry,
    Map<String, dynamic>? displayFields,
  ) {
    final basePlan = catalogEntry['basePlan']?.toString().trim();
    if (basePlan != null && basePlan.isNotEmpty) {
      return _basePlanToUnderscoreId(basePlan);
    }

    final fromCatalog = catalogEntry['googlePlanKey']?.toString().trim();
    if (fromCatalog != null && fromCatalog.isNotEmpty) return fromCatalog;

    if (displayFields != null) {
      final fromDisplay =
          (displayFields['googlePlanKey'] ?? displayFields['productId'])
              ?.toString()
              .trim();
      if (fromDisplay != null && fromDisplay.isNotEmpty) return fromDisplay;
    }

    final entitlementId = catalogEntry['entitlementId']?.toString().trim();
    if (entitlementId != null && entitlementId.isNotEmpty) {
      return entitlementId;
    }
    return null;
  }

  /// `monthly` | `yearly` from snapshot. Defaults to monthly.
  static String _defaultPeriodFromBillingSnap(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final raw = snap.data()?['default']?.toString().trim().toLowerCase();
    if (raw == 'yearly' || raw == 'annual' || raw == 'year') {
      return 'yearly';
    }
    return 'monthly';
  }

  /// Parse [Subscriptions/plans] → gender → [period] array (maps with entitlementId, basePlan, …).
  static List<Map<String, dynamic>> _parsePlansCatalog(
    String gender,
    Map<String, dynamic>? plansData,
    String period,
  ) {
    if (plansData == null) return [];
    final g = plansData[gender.toLowerCase().trim()];
    if (g is! Map<String, dynamic>) return [];
    final listRaw = g[period];
    if (listRaw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final e in listRaw) {
      if (e is Map) {
        out.add(Map<String, dynamic>.from(e));
      }
    }
    return out;
  }

  /// Merge [plans] catalog with [displayData] for the **default** billing period
  /// ([Subscriptions/billingPeriods] `default` field).
  static Future<List<SubscriptionPlanDisplay>> fetchMonthlyPlans(
    String gender,
  ) async {
    return fetchPlansForDefaultBillingPeriod(gender);
  }

  /// Loads plans for [Subscriptions/billingPeriods.default] (`monthly` or `yearly`).
  static Future<List<SubscriptionPlanDisplay>> fetchPlansForDefaultBillingPeriod(
    String gender,
  ) async {
    try {
      final col = _firestore.collection(_collectionSubscriptions);
      final snaps = await Future.wait([
        col.doc(_docBillingPeriods).get(),
        col.doc(_docPlans).get(),
        col.doc(_docDisplayData).get(),
      ]);
      final billingSnap = snaps[0];
      final plansSnap = snaps[1];
      final displaySnap = snaps[2];

      var period = _defaultPeriodFromBillingSnap(billingSnap);
      if (kDebugMode) {
        debugPrint(
          '[$SubscriptionDisplayService] default billing period: $period',
        );
      }

      var catalog = _parsePlansCatalog(gender, plansSnap.data(), period);
      if (catalog.isEmpty && period == 'yearly') {
        if (kDebugMode) {
          debugPrint(
            '[$SubscriptionDisplayService] yearly catalog empty, falling back to monthly',
          );
        }
        catalog = _parsePlansCatalog(gender, plansSnap.data(), 'monthly');
      }

      Map<String, dynamic> displayPeriodMap = {};
      if (displaySnap.exists) {
        final data = displaySnap.data();
        final m = data?[period];
        if (m is Map<String, dynamic>) {
          displayPeriodMap = Map<String, dynamic>.from(m);
        } else if (period == 'yearly' &&
            data?['monthly'] is Map<String, dynamic>) {
          displayPeriodMap =
              Map<String, dynamic>.from(data!['monthly'] as Map<String, dynamic>);
          if (kDebugMode) {
            debugPrint(
              '[$SubscriptionDisplayService] displayData.$period missing, '
              'using displayData.monthly for merge',
            );
          }
        }
      }

      final plans = <SubscriptionPlanDisplay>[];

      if (catalog.isNotEmpty) {
        for (final entry in catalog) {
          final match = _findDisplayForCatalogEntry(displayPeriodMap, entry);
          final String planKey;
          final Map<String, dynamic> displayFields;
          if (match != null) {
            planKey = match.key;
            displayFields = match.value;
          } else {
            planKey = entry['entitlementId']?.toString().trim() ??
                _displayKeyFromBasePlan(entry['basePlan']?.toString()) ??
                'plan_${plans.length}';
            displayFields = {};
            if (kDebugMode) {
              debugPrint(
                '[$SubscriptionDisplayService] No displayData match for catalog entry '
                'entitlement=${entry['entitlementId']} basePlan=${entry['basePlan']} — using minimal card',
              );
            }
          }

          var plan = SubscriptionPlanDisplay.fromMap(planKey, displayFields);
          final resolvedKey = _resolveGooglePlanKey(entry, displayFields);
          if (resolvedKey == null || resolvedKey.isEmpty) {
            if (kDebugMode) {
              debugPrint(
                '[$SubscriptionDisplayService] Could not resolve googlePlanKey for $planKey',
              );
            }
            continue;
          }

          final entryName = entry['planName']?.toString().trim();
          plan = SubscriptionPlanDisplay(
            planKey: plan.planKey,
            planName: plan.planName.isNotEmpty
                ? plan.planName
                : (entryName != null && entryName.isNotEmpty
                    ? entryName
                    : plan.planName),
            cardBg: plan.cardBg,
            features: plan.features.isNotEmpty
                ? plan.features
                : _stringList(entry['features']),
            pointIcon: plan.pointIcon,
            price: plan.price.isNotEmpty
                ? plan.price
                : (entry['price']?.toString() ?? ''),
            shortDescription: plan.shortDescription.isNotEmpty
                ? plan.shortDescription
                : (entry['shortDescription']?.toString() ?? ''),
            eliteExp: plan.eliteExp,
            mostChosen: plan.mostChosen,
            googlePlanKey: resolvedKey,
          );
          plan = _ensureBadgesFromPlanKey(plan);
          plans.add(plan);
        }
      }

      if (plans.isEmpty) {
        List<String> keys;
        final orderRaw = displaySnap.data()?[_fieldPlanOrder];
        if (orderRaw is List) {
          keys = orderRaw
              .map((e) => e?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
          keys.addAll(
            displayPeriodMap.keys.where((k) => !keys.contains(k)),
          );
        } else {
          keys = displayPeriodMap.keys.toList();
        }

        for (final key in keys) {
          final planData = displayPeriodMap[key];
          if (planData is! Map<String, dynamic>) continue;
          var plan = SubscriptionPlanDisplay.fromMap(key, planData);
          if (plan.googlePlanKey == null || plan.googlePlanKey!.isEmpty) {
            final bp = planData['basePlan']?.toString().trim();
            final fallback = bp != null && bp.isNotEmpty
                ? _basePlanToUnderscoreId(bp)
                : key;
            plan = SubscriptionPlanDisplay(
              planKey: plan.planKey,
              planName: plan.planName,
              cardBg: plan.cardBg,
              features: plan.features,
              pointIcon: plan.pointIcon,
              price: plan.price,
              shortDescription: plan.shortDescription,
              eliteExp: plan.eliteExp,
              mostChosen: plan.mostChosen,
              googlePlanKey: fallback,
            );
          }
          plan = _ensureBadgesFromPlanKey(plan);
          plans.add(plan);
        }
      }

      plans.sort(
        (a, b) => _orderIndexForPlanKey(
          a.planKey,
        ).compareTo(_orderIndexForPlanKey(b.planKey)),
      );

      if (kDebugMode) {
        debugPrint(
          '[$SubscriptionDisplayService] loaded ${plans.length} plans: '
          '${plans.map((p) => '${p.planKey}→${p.googlePlanKey}').join(', ')}',
        );
      }
      return plans;
    } catch (e, st) {
      debugPrint('[$SubscriptionDisplayService] Error fetching plans: $e');
      if (kDebugMode) debugPrint(st.toString());
      return [];
    }
  }

  static List<String> _stringList(dynamic v) {
    if (v is! List) return const [];
    return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
  }

  /// Enabled features for the subscriber from [Subscriptions/entitlementFeatures].
  /// Resolves tier via [SubscriptionService.entitlementFeaturesFirestoreKey].
  static Future<List<String>> fetchEnabledEntitlementFeatureLabels({
    String? entitlementId,
    String? productId,
  }) async {
    final key = SubscriptionService.entitlementFeaturesFirestoreKey(
      entitlementId: entitlementId,
      productId: productId,
    );
    if (key == null || key.isEmpty) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_collectionSubscriptions)
          .doc(_docEntitlementFeatures)
          .get();
      final data = snap.data();
      if (data == null) return [];
      final tier = data[key];
      if (tier is! Map<String, dynamic>) {
        if (kDebugMode) {
          debugPrint(
            '[$SubscriptionDisplayService] entitlementFeatures[$key] '
            'missing or not a map',
          );
        }
        return [];
      }
      final out = <String>[];
      for (final e in tier.entries) {
        final name = e.key;
        final v = e.value;
        if (v is! Map) continue;
        final m = Map<String, dynamic>.from(v);
        if (!_isEntitlementFeatureOn(m)) continue;
        out.add(_formatEntitlementFeatureLabel(name, m));
      }
      out.sort();
      return out;
    } catch (e, st) {
      debugPrint('[$SubscriptionDisplayService] entitlementFeatures: $e');
      if (kDebugMode) debugPrint(st.toString());
      return [];
    }
  }

  /// Firestore may omit [enabled] for quota-style features (e.g. messaging: limit+period only).
  /// Only [enabled] == false turns a feature off.
  static bool _isEntitlementFeatureOn(Map<String, dynamic> m) {
    if (m['enabled'] == false) return false;
    if (m['enabled'] == true) return true;
    if (m.containsKey('limit') || m.containsKey('period')) return true;
    return m.isNotEmpty;
  }

  static String _formatEntitlementFeatureLabel(
    String featureKey,
    Map<String, dynamic> raw,
  ) {
    final title = _entitlementFeatureTitles[featureKey] ??
        featureKey
            .replaceAll('_', ' ')
            .split(' ')
            .map(
              (w) => w.isEmpty
                  ? ''
                  : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
            )
            .join(' ');
    if (featureKey == 'messaging') {
      final limit = raw['limit'];
      final period = raw['period']?.toString() ?? 'day';
      if (limit is num && limit < 0) {
        return '$title (unlimited per $period)';
      }
      if (limit is num) {
        return '$title ($limit per $period)';
      }
    }
    return title;
  }

  static SubscriptionPlanDisplay _ensureBadgesFromPlanKey(
    SubscriptionPlanDisplay plan,
  ) {
    final k = plan.planKey.toLowerCase();
    final gk = (plan.googlePlanKey ?? '').toLowerCase();
    final blob = '$k $gk';
    final hasElite = plan.eliteExp || blob.contains('elite');
    final hasMostChosen = plan.mostChosen || blob.contains('premium');
    if (!hasElite && !hasMostChosen) return plan;
    return SubscriptionPlanDisplay(
      planKey: plan.planKey,
      planName: plan.planName,
      cardBg: plan.cardBg,
      features: plan.features,
      pointIcon: plan.pointIcon,
      price: plan.price,
      shortDescription: plan.shortDescription,
      eliteExp: hasElite,
      mostChosen: hasMostChosen,
      googlePlanKey: plan.googlePlanKey,
    );
  }

  static List<SubscriptionPlanDisplay> getDefaultPlans() => [];
}
