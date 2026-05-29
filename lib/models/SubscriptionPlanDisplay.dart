/// Represents one subscription plan's display data from Firestore
/// SUBSCRIPTION/displayData → monthly → { planKey: { planName, features, price, googlePlanKey, ... } }
class SubscriptionPlanDisplay {
  /// Firestore key (e.g. starter, deluxe, premium, elite)
  final String planKey;

  /// Display name: from planName if set, else capitalized planKey
  final String planName;

  /// "1" = normal background, "2" = 3rd plan card style, "3" = last/elite card style
  final String cardBg;

  /// Feature bullet points
  final List<String> features;

  /// URL for icon shown before each feature (Firebase Storage)
  final String? pointIcon;

  /// Price string (e.g. "299", "449")
  final String price;

  /// Short description (e.g. "Start chatting instantly")
  final String shortDescription;

  /// Show "Elite Experience" stacked tag when true (from Firestore eliteExp)
  final bool eliteExp;

  /// Show "Most Chosen" stacked tag when true (from Firestore mostChosen)
  final bool mostChosen;

  /// RevenueCat / Google Play product identifier to start purchase (e.g. deluxe_monthly, premium_monthly)
  final String? googlePlanKey;

  const SubscriptionPlanDisplay({
    required this.planKey,
    required this.planName,
    required this.cardBg,
    required this.features,
    this.pointIcon,
    required this.price,
    required this.shortDescription,
    this.eliteExp = false,
    this.mostChosen = false,
    this.googlePlanKey,
  });

  /// cardBg "1" = normal, "2" = highlight (3rd plan), "3" = elite (last card)
  bool get isNormalCard => cardBg == '1';
  bool get isHighlightCard => cardBg == '2';
  bool get isEliteCard => cardBg == '3';

  static String _capitalize(String key) {
    if (key.isEmpty) return key;
    return key[0].toUpperCase() + key.substring(1).toLowerCase();
  }

  static bool _parseBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  factory SubscriptionPlanDisplay.fromMap(String key, Map<String, dynamic>? data) {
    if (data == null) {
      return SubscriptionPlanDisplay(
        planKey: key,
        planName: _capitalize(key),
        cardBg: '1',
        features: const [],
        price: '',
        shortDescription: '',
        googlePlanKey: null,
      );
    }
    final planName = (data['planName'] as String?)?.trim();
    final list = data['features'];
    final featuresList = list is List
        ? list.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList()
        : <String>[];
    return SubscriptionPlanDisplay(
      planKey: key,
      planName: planName?.isNotEmpty == true ? planName! : _capitalize(key),
      cardBg: (data['cardBg'] as String?) ?? '1',
      features: featuresList,
      pointIcon: (data['pointIcon'] as String?)?.trim(),
      price: (data['price'] as String?) ?? '',
      shortDescription: (data['shortDescription'] as String?) ?? '',
      eliteExp: _parseBool(data['eliteExp']),
      mostChosen: _parseBool(data['mostChosen']),
      googlePlanKey: ((data['googlePlanKey'] ?? data['productId']) as String?)?.trim(),
    );
  }
}
