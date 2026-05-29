class FeatureConfig {
  final bool? enabled;
  final int? limit;
  final int? period;

  FeatureConfig({this.enabled, this.limit, this.period});

  factory FeatureConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return FeatureConfig();

    return FeatureConfig(
      enabled: map['enabled'] as bool?,
      limit: map['limit'] as int?,
      period: map['period'] as int?,
    );
  }
}

class PlanFeatures {
  final Map<String, FeatureConfig> features;

  PlanFeatures({required this.features});

  factory PlanFeatures.fromMap(Map<String, dynamic>? map) {
    if (map == null) return PlanFeatures(features: {});

    final parsed = <String, FeatureConfig>{};

    map.forEach((key, value) {
      parsed[key] = FeatureConfig.fromMap(value);
    });

    return PlanFeatures(features: parsed);
  }

  FeatureConfig? getFeature(String key) {
    return features[key];
  }
}

class SubscriptionModel {
  final Map<String, PlanFeatures> plans;

  SubscriptionModel({required this.plans});

  factory SubscriptionModel.fromMap(Map<String, dynamic>? map) {
    if (map == null) return SubscriptionModel(plans: {});

    final parsedPlans = <String, PlanFeatures>{};

    map.forEach((key, value) {
      parsedPlans[key] = PlanFeatures.fromMap(value);
    });

    return SubscriptionModel(plans: parsedPlans);
  }
}
