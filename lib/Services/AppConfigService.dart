import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Service to fetch app configuration from Firestore
///
/// Firestore Structure:
/// Collection: AppConfig
/// Document: FacePlusPlus
///   Fields:
///     - apiKey: String
///     - apiSecret: String
///     - isEnabled: bool (optional, defaults to true)
///
/// Document: General
///   Fields:
///     - maintenanceMode: bool
///     - minAppVersion: String
///
/// Document: RewardsMale
///   Fields:
///     - rewardType: String (enum: 'coins', 'gems', 'premium', etc. - WHAT to reward)
///     - rewardValue: int (QUANTITY: coins amount, gems amount, days of premium, etc.)
///     - messageWithReward: String (display message with {reward} placeholder)
///     - messageWithoutReward: String (fallback message if reward is 0)
///
/// Document: RewardsFemale
///   Fields:
///     - rewardType: String (enum: 'coins', 'gems', 'premium', etc. - WHAT to reward)
///     - rewardValue: int (QUANTITY: coins amount, gems amount, days of premium, etc.)
///     - messageWithReward: String (display message with {reward} placeholder)
///     - messageWithoutReward: String (fallback message if reward is 0)
///
/// Document: VerifyProfileDialog
///   Fields:
///     - benefitsMale: List<String> (benefits for male users, use {rewardType} and {rewardValue} placeholders)
///     - benefitsFemale: List<String> (benefits for female users, use {rewardType} and {rewardValue} placeholders)
///
/// Document: SafetyTipsDialog
///   Fields:
///     - titleNew: String (title for new users)
///     - titleExisting: String (title for existing users)
///     - tipsNew: List<String> (tips for new users)
///     - tipsExisting: List<String> (tips for existing users)
///
/// Document: SuccessVerificationDialog
///   Fields:
///     - subtitle: String (subtitle message)
///     - buttonText: String (button text)
///     - showBadge: bool (whether to show verified badge)
///
/// Document: ConnectionsScreenConfig
///   Fields:
///     - allTabEmptyTitle: String (title when no connections in All tab)
///     - allTabEmptyMessage: String (message when no connections in All tab)
///
/// Document: PlaceholderImages
///   Fields:
///     - maleImageUrl: String (URL for male placeholder image)
///     - femaleImageUrl: String (URL for female placeholder image)
///     - backgroundImages: List<String> (URLs for random background images)
///
/// Document: SubscriptionPolicies
///   Fields:
///     - data: List<String> (subscription policy list items)
///
/// Document: RestrictedRegex
///   Fields:
///     - emailRegex: String
///     - genericUrlRegex: String
///     - phoneRegex: String
///     - socialProfileRegex: String
///     - socialUrlRegex: String
///     - susPeciousEmailRegex: String
///

class AppConfigService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collectionName = 'AppConfig';

  static const String _defaultEmailRegexPattern =
      r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}';
  static const String _defaultGenericUrlRegexPattern =
      r'(https?:\/\/|www\.)[^\s]+';
  static const String _defaultPhoneRegexPattern =
      r'(?<!\d)(?:\+?\d{1,3}[\s.-]?)?(?:\(?\d{2,4}\)?[\s.-]?)?\d{3,4}[\s.-]?\d{4}(?!\d)';
  static const String _defaultSocialProfileRegexPattern =
      r'(^|[^a-zA-Z0-9])(ig|instagram|insta|facebook|fb|whatsapp|telegram|snapchat|snap|twitter|x|linkedin|youtube|tiktok|threads|discord|wechat|signal|viber|kik|messenger)([^a-zA-Z0-9]|$)';
  static const String _defaultSocialUrlRegexPattern =
      r'instagram\.com|facebook\.com|fb\.com|wa\.me|whatsapp\.com|t\.me|telegram\.me|snapchat\.com|twitter\.com|x\.com|linkedin\.com|youtube\.com|youtu\.be|tiktok\.com|threads\.net|discord\.gg';
  static const String _defaultSuspiciousEmailRegexPattern =
      r'(^|[^a-zA-Z0-9])(gmail|yahoo|hotmail|outlook|icloud|email|e-mail|mail)([^a-zA-Z0-9]|$)';

  // Cached values
  static String? _facePlusApiKey;
  static String? _facePlusApiSecret;
  static bool _isLoaded = false;

  // Gender-Specific Rewards Config
  // MALE: Typically coins
  static String _maleRewardType = 'coins';
  static int _maleRewardValue = 50;
  static String _maleMessageWithReward =
      'Congratulations! Your profile has been verified. You\'ve earned {reward} {rewardType} as a reward!';
  static String _maleMessageWithoutReward =
      'Congratulations! Your profile has been verified. You\'re now trusted and verified on the platform!';

  // FEMALE: Different reward (gems, premium features, etc.)
  static String _femaleRewardType = 'premium days';
  static int _femaleRewardValue = 7;
  static String _femaleMessageWithReward =
      'Congratulations! Your profile has been verified. You\'ve earned {reward} {rewardType} as a special reward!';
  static String _femaleMessageWithoutReward =
      'Congratulations! Your profile has been verified. You\'re now trusted and verified on the platform!';

  // Placeholder Images config
  static String _maleImageUrl = '';
  static String _femaleImageUrl = '';
  static List<String> _backgroundImages = [];

  // Verified Badge config
  // static String _verifiedBadgeUri = '';

  // Get the limit for sending the images and check the nsfw contents
  static int _imageSendLimit = 0;

  // Verify Profile Dialog config
  static List<String> _verifyBenefitsMale = [];
  static List<String> _verifyBenefitsFemale = [];

  // Safety Tips Dialog config
  static String _safetyTitleNew = 'Safety Tips';
  static String _safetyTitleExisting = 'Safety Reminder';
  static List<String> _safetyTipsNew = [];
  static List<String> _safetyTipsExisting = [];
  static int _safetyTipsVersion = 1; // Version for safety tips

  // Success Verification Dialog config
  static String _successSubtitle = 'Your verification is complete';
  static String _successButtonText = 'Continue';
  static bool _showBadge = true;

  // Connections Screen config
  static String _allTabEmptyTitle = 'RELAX a bit. You just joined !!';
  static String _allTabEmptyMessage =
      'Once you are Liked, Viewed or Match, people will be shown here.';

  // Device Limit config
  static int _maxActiveDevices = 2;

  // Base URL config
  static String _baseUrl = '';

  // Subscription Policies config
  static List<String> _subscriptionPolicies = [];

  // Restricted regex config
  static RegExp _emailRegex = RegExp(_defaultEmailRegexPattern);
  static RegExp _genericUrlRegex = RegExp(
    _defaultGenericUrlRegexPattern,
    caseSensitive: false,
  );
  static RegExp _phoneRegex = RegExp(_defaultPhoneRegexPattern);
  static RegExp _socialProfileRegex = RegExp(
    _defaultSocialProfileRegexPattern,
    caseSensitive: false,
  );
  static RegExp _socialUrlRegex = RegExp(
    _defaultSocialUrlRegexPattern,
    caseSensitive: false,
  );
  static RegExp _suspiciousEmailRegex = RegExp(
    _defaultSuspiciousEmailRegexPattern,
    caseSensitive: false,
  );

  // Interests config
  static List<String> _interests = [];

  // Profile weightage config
  static Map<String, dynamic> _profileWeightage = {};

  // Default benefits (used when Firebase config not available)
  // ⚠️ Note: Use {rewardType} and {rewardValue} placeholders
  static const List<String> _defaultBenefitsMale = [
    'Build trust with a verified badge on your profile',
    'Earn {rewardValue} {rewardType} instantly as a reward',
    'Stand out from other users with authentic verification',
    'Increase your profile visibility by 3x and get more matches',
  ];

  static const List<String> _defaultBenefitsFemale = [
    'Build trust with a verified badge on your profile',
    'Get {rewardValue} {rewardType} as a special reward',
    'Stand out from other users with authentic verification',
    'Unlock exclusive features and priority support',
  ];

  // Default safety tips
  static const List<String> _defaultSafetyTipsNew = [
    "Never share personal information like your home address, financial details, or workplace location with someone you've just met online.",
    "Always meet in public places for the first few dates. Inform a friend or family member about your plans and share your location with them.",
    "Trust your instincts. If something feels off or uncomfortable, don't hesitate to end the conversation or leave the date. Your safety comes first.",
  ];

  static const List<String> _defaultSafetyTipsExisting = [
    "Remember to keep your personal details private until you're comfortable.",
    "Always prioritize meeting in safe, public locations.",
    "Your safety matters - trust your instincts in every interaction.",
  ];

  /// Initialize and load config from Firestore
  static Future<void> loadConfig() async {
    if (_isLoaded) return;

    try {
      debugPrint('📱 Loading app config from Firestore...');

      // Load all configs in parallel for faster loading
      final results = await Future.wait([
        _firestore.collection(_collectionName).doc('FacePlusPlus').get(),
        _firestore.collection(_collectionName).doc('RewardsMale').get(),
        _firestore.collection(_collectionName).doc('RewardsFemale').get(),
        _firestore.collection(_collectionName).doc('VerifyProfileDialog').get(),
        _firestore.collection(_collectionName).doc('SafetyTipsDialog').get(),
        _firestore
            .collection(_collectionName)
            .doc('SuccessVerificationDialog')
            .get(),
        _firestore
            .collection(_collectionName)
            .doc('ConnectionsScreenConfig')
            .get(),
        _firestore.collection(_collectionName).doc('PlaceholderImages').get(),
        _firestore
            .collection(_collectionName)
            .doc('subscriptionPolicies')
            .get(),
        // _firestore.collection(_collectionName).doc('verifiedBadge').get(),
        _firestore.collection('AppConfig').doc('deviceLimit').get(),
        _firestore.collection('AppConfig').doc('profile').get(),
        _firestore.collection('AppConfig').doc('imageValidation').get(),
        _firestore.collection('AppConfig').doc('Storage').get(),
        _firestore.collection(_collectionName).doc('RestrictedRegex').get(),
      ]);

      final facePlusDoc = results[0];
      final rewardsMaleDoc = results[1];
      final rewardsFemaleDoc = results[2];
      final verifyDialogDoc = results[3];
      final safetyDialogDoc = results[4];
      final successDialogDoc = results[5];
      final connectionsConfigDoc = results[6];
      final placeholderImagesDoc = results[7];
      final subscriptionPoliciesDoc = results[8];
      // final verifiedBadgeDoc = results[9];
      final deviceLimitDoc = results[9];
      final profileConfigDoc = results[10];
      final imageValidationDoc = results[11];
      final baseUrlDoc = results[12];
      final restrictedRegexDoc = results[13];
      // Process Face++ config
      if (facePlusDoc.exists) {
        final data = facePlusDoc.data();
        _facePlusApiKey = data?['apiKey'] as String?;
        _facePlusApiSecret = data?['apiSecret'] as String?;
        debugPrint('✅ Face++ config loaded successfully');
      } else {
        debugPrint('⚠️ Face++ config not found in Firestore');
      }

      // Process Male Rewards config
      if (rewardsMaleDoc.exists) {
        final data = rewardsMaleDoc.data();
        _maleRewardType = data?['rewardType'] as String? ?? 'coins';
        _maleRewardValue = data?['rewardValue'] as int? ?? 50;
        _maleMessageWithReward =
            data?['messageWithReward'] as String? ??
            'Congratulations! Your profile has been verified. You\'ve earned {reward} {rewardType} as a reward!';
        _maleMessageWithoutReward =
            data?['messageWithoutReward'] as String? ??
            'Congratulations! Your profile has been verified. You\'re now trusted and verified on the platform!';
        debugPrint(
          '✅ Male Rewards config loaded: rewardType=$_maleRewardType, rewardValue=$_maleRewardValue',
        );
      } else {
        debugPrint(
          '⚠️ Male Rewards config not found, using defaults: $_maleRewardValue $_maleRewardType',
        );
      }

      // Process Female Rewards config
      if (rewardsFemaleDoc.exists) {
        final data = rewardsFemaleDoc.data();
        _femaleRewardType = data?['rewardType'] as String? ?? 'premium days';
        _femaleRewardValue = data?['rewardValue'] as int? ?? 7;
        _femaleMessageWithReward =
            data?['messageWithReward'] as String? ??
            'Congratulations! Your profile has been verified. You\'ve earned {reward} {rewardType} as a special reward!';
        _femaleMessageWithoutReward =
            data?['messageWithoutReward'] as String? ??
            'Congratulations! Your profile has been verified. You\'re now trusted and verified on the platform!';
        debugPrint(
          '✅ Female Rewards config loaded: rewardType=$_femaleRewardType, rewardValue=$_femaleRewardValue',
        );
      } else {
        debugPrint(
          '⚠️ Female Rewards config not found, using defaults: $_femaleRewardValue $_femaleRewardType',
        );
      }

      // Process Placeholder Images config
      if (placeholderImagesDoc.exists) {
        final data = placeholderImagesDoc.data();
        _maleImageUrl = data?['maleImageUrl'] as String? ?? _maleImageUrl;
        _femaleImageUrl = data?['femaleImageUrl'] as String? ?? _femaleImageUrl;
        _backgroundImages = _parseStringList(data?['backgroundImages']);
        debugPrint(
          '✅ PlaceholderImages config loaded: male=$_maleImageUrl..., female=$_femaleImageUrl..., backgrounds=${_backgroundImages.length}',
        );
      } else {
        debugPrint('⚠️ PlaceholderImages config not found, using defaults');
      }

      // Process Verify Profile Dialog config
      if (verifyDialogDoc.exists) {
        final data = verifyDialogDoc.data();
        _verifyBenefitsMale = _parseStringList(data?['benefitsMale']);
        _verifyBenefitsFemale = _parseStringList(data?['benefitsFemale']);
        debugPrint(
          '✅ VerifyProfileDialog config loaded: ${_verifyBenefitsMale.length} male benefits, ${_verifyBenefitsFemale.length} female benefits',
        );
      } else {
        debugPrint('⚠️ VerifyProfileDialog config not found, using defaults');
      }

      // Interests config
      if (profileConfigDoc.exists) {
        final data = profileConfigDoc.data();
        _interests = _parseStringList(data?['interests']);
        debugPrint('✅ Interests config loaded: ${_interests.length} interests');
      } else {
        debugPrint('⚠️ Interests config not found, using defaults');
      }

      // Profile Weightage config
      if (profileConfigDoc.exists) {
        final data = profileConfigDoc.data();
        _profileWeightage =
            data?['profileWeightage'] as Map<String, dynamic>? ?? {};
        debugPrint(
          '✅ Profile Weightage config loaded: ${_profileWeightage.length} weightage values',
        );
      } else {
        debugPrint('⚠️ Profile Weightage config not found, using defaults');
      }

      // Process Safety Tips Dialog config
      if (safetyDialogDoc.exists) {
        final data = safetyDialogDoc.data();
        _safetyTitleNew = data?['titleNew'] as String? ?? 'Safety Tips';
        _safetyTitleExisting =
            data?['titleExisting'] as String? ?? 'Safety Reminder';
        _safetyTipsNew = _parseStringList(data?['tipsNew']);
        _safetyTipsExisting = _parseStringList(data?['tipsExisting']);
        _safetyTipsVersion =
            data?['version'] as int? ?? 1; // Get version from Firebase
        debugPrint(
          '✅ SafetyTipsDialog config loaded: ${_safetyTipsNew.length} new tips, ${_safetyTipsExisting.length} existing tips, version: $_safetyTipsVersion',
        );
      } else {
        debugPrint('⚠️ SafetyTipsDialog config not found, using defaults');
      }

      // Process Success Verification Dialog config
      if (successDialogDoc.exists) {
        final data = successDialogDoc.data();
        _successSubtitle =
            data?['subtitle'] as String? ?? 'Your verification is complete';
        _successButtonText = data?['buttonText'] as String? ?? 'Continue';
        _showBadge = data?['showBadge'] as bool? ?? true;
        debugPrint('✅ SuccessVerificationDialog config loaded');
      } else {
        debugPrint(
          '⚠️ SuccessVerificationDialog config not found, using defaults',
        );
      }

      // Process Connections Screen config
      if (connectionsConfigDoc.exists) {
        final data = connectionsConfigDoc.data();
        _allTabEmptyTitle =
            data?['allTabEmptyTitle'] as String? ??
            'RELAX a bit. You just joined !!';
        _allTabEmptyMessage =
            data?['allTabEmptyMessage'] as String? ??
            'Once you are Liked, Viewed or Match, people will be shown here.';
        debugPrint('✅ ConnectionsScreenConfig loaded');
      } else {
        debugPrint('⚠️ ConnectionsScreenConfig not found, using defaults');
      }

      // Process Subscription Policies config
      if (subscriptionPoliciesDoc.exists) {
        final data = subscriptionPoliciesDoc.data();
        _subscriptionPolicies = _parseStringList(data?['data']);
        debugPrint(
          '✅ SubscriptionPolicies config loaded: ${_subscriptionPolicies.length} items',
        );
      } else {
        // Firestore document IDs are case-sensitive; support uppercase doc id too.
        try {
          final upperDoc = await _firestore
              .collection(_collectionName)
              .doc('SubscriptionPolicies')
              .get();
          if (upperDoc.exists) {
            final data = upperDoc.data();
            _subscriptionPolicies = _parseStringList(data?['data']);
            debugPrint(
              '✅ SubscriptionPolicies config loaded from uppercase doc id: ${_subscriptionPolicies.length} items',
            );
          } else {
            debugPrint(
              '⚠️ SubscriptionPolicies config not found (checked both doc id cases), using defaults',
            );
          }
        } catch (e) {
          debugPrint(
            '⚠️ SubscriptionPolicies config fallback read failed, using defaults: $e',
          );
        }
      }

      // Process Verified Badge config
      // if (verifiedBadgeDoc.exists) {
      //   final data = verifiedBadgeDoc.data();
      //   _verifiedBadgeUri = data?['uri'] as String? ?? '';
      //   debugPrint('✅ Verified Badge config loaded: $_verifiedBadgeUri...');
      // } else {
      //   debugPrint('⚠️ Verified Badge config not found');
      // }

      // Process Base URL config
      if (baseUrlDoc.exists) {
        final data = baseUrlDoc.data();
        _baseUrl = data?['baseUrl'] as String? ?? '';
        debugPrint('✅ Base URL config loaded: $_baseUrl...');
      } else {
        debugPrint('⚠️ Base URL config not found');
      }

      if (deviceLimitDoc.exists) {
        final data = deviceLimitDoc.data();
        _maxActiveDevices = data?['limit'] as int? ?? _maxActiveDevices;
        debugPrint('✅ Device Limit config loaded: $_maxActiveDevices');
      } else {
        debugPrint(
          '⚠️ Device Limit config not found, using default: $_maxActiveDevices',
        );
      }

      if (imageValidationDoc.exists) {
        final data = imageValidationDoc.data();
        _imageSendLimit = data?['limit'] as int? ?? 0;
        debugPrint('✅ Image Send Limit config loaded: $_imageSendLimit');
      } else {
        debugPrint('⚠️ Image Send Limit config not found, using default: 0');
      }

      if (restrictedRegexDoc.exists) {
        final data = restrictedRegexDoc.data();
        _emailRegex = _buildRegex(
          data?['emailRegex'] as String?,
          _defaultEmailRegexPattern,
        );
        _genericUrlRegex = _buildRegex(
          data?['genericUrlRegex'] as String?,
          _defaultGenericUrlRegexPattern,
          caseSensitive: false,
        );
        _phoneRegex = _buildRegex(
          data?['phoneRegex'] as String?,
          _defaultPhoneRegexPattern,
        );
        _socialProfileRegex = _buildRegex(
          data?['socialProfileRegex'] as String?,
          _defaultSocialProfileRegexPattern,
          caseSensitive: false,
        );
        _socialUrlRegex = _buildRegex(
          data?['socialUrlRegex'] as String?,
          _defaultSocialUrlRegexPattern,
          caseSensitive: false,
        );
        _suspiciousEmailRegex = _buildRegex(
          data?['susPeciousEmailRegex'] as String?,
          _defaultSuspiciousEmailRegexPattern,
          caseSensitive: false,
        );
        debugPrint('✅ RestrictedRegex config loaded successfully');
      } else {
        debugPrint('⚠️ RestrictedRegex config not found, using defaults');
      }

      _isLoaded = true;
    } catch (e) {
      debugPrint('❌ Error loading app config: $e');
    }
  }

  static RegExp _buildRegex(
    String? pattern,
    String fallbackPattern, {
    bool caseSensitive = true,
  }) {
    final resolvedPattern = pattern?.trim().isNotEmpty == true
        ? pattern!.trim()
        : fallbackPattern;

    try {
      return RegExp(resolvedPattern, caseSensitive: caseSensitive);
    } catch (e) {
      debugPrint('⚠️ Invalid regex pattern "$resolvedPattern": $e');
      return RegExp(fallbackPattern, caseSensitive: caseSensitive);
    }
  }

  /// Parse a dynamic list to List<String>
  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  /// Force reload config from Firestore
  static Future<void> reloadConfig() async {
    _isLoaded = false;
    await loadConfig();
  }

  /// Get Face++ API Key
  static String get facePlusApiKey {
    if (!_isLoaded) {
      debugPrint('⚠️ AppConfig not loaded yet. Call loadConfig() first.');
    }
    return _facePlusApiKey ?? '';
  }

  /// Get Face++ API Secret
  static String get facePlusApiSecret {
    if (!_isLoaded) {
      debugPrint('⚠️ AppConfig not loaded yet. Call loadConfig() first.');
    }
    return _facePlusApiSecret ?? '';
  }

  /// Check if Face++ is configured
  static bool get isFacePlusConfigured {
    return _facePlusApiKey?.isNotEmpty == true &&
        _facePlusApiSecret?.isNotEmpty == true;
  }

  // ========== GENDER-SPECIFIC REWARD GETTERS ==========

  /// Get reward configuration for a specific gender
  /// Returns: {rewardType, rewardValue, messageWithReward, messageWithoutReward}
  static Map<String, dynamic> getRewardConfig(String? gender) {
    final isMale = gender?.toLowerCase() == 'male';

    return {
      'rewardType': isMale ? _maleRewardType : _femaleRewardType,
      'rewardValue': isMale ? _maleRewardValue : _femaleRewardValue,
      'messageWithReward': isMale
          ? _maleMessageWithReward
          : _femaleMessageWithReward,
      'messageWithoutReward': isMale
          ? _maleMessageWithoutReward
          : _femaleMessageWithoutReward,
    };
  }

  /// Get reward type for a gender (e.g., "coins", "premium days", "gems")
  static String getRewardType(String? gender) {
    return gender?.toLowerCase() == 'male'
        ? _maleRewardType
        : _femaleRewardType;
  }

  /// Get reward value for a gender
  static int getRewardValue(String? gender) {
    return gender?.toLowerCase() == 'male'
        ? _maleRewardValue
        : _femaleRewardValue;
  }

  /// Get success message with gender-specific rewards
  /// Replaces {reward} with actual value and {rewardType} with reward type
  static String getSuccessMessage({
    required String? gender,
    required int rewardValue,
  }) {
    final config = getRewardConfig(gender);
    final actualRewardValue = rewardValue > 0
        ? rewardValue
        : config['rewardValue'] as int;
    final messageTemplate = rewardValue > 0
        ? config['messageWithReward'] as String
        : config['messageWithoutReward'] as String;

    return messageTemplate
        .replaceAll('{reward}', actualRewardValue.toString())
        .replaceAll('{rewardType}', config['rewardType'] as String);
  }

  /// Listen to Face++ config changes in real-time
  static Stream<Map<String, dynamic>?> get facePlusConfigStream {
    return _firestore
        .collection(_collectionName)
        .doc('FacePlusPlus')
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  /// Listen to Male Rewards config changes in real-time
  static Stream<Map<String, dynamic>?> get maleRewardsConfigStream {
    return _firestore
        .collection(_collectionName)
        .doc('RewardsMale')
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  /// Listen to Female Rewards config changes in real-time
  static Stream<Map<String, dynamic>?> get femaleRewardsConfigStream {
    return _firestore
        .collection(_collectionName)
        .doc('RewardsFemale')
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  /// Get verification benefits for a specific gender
  /// Replaces {rewardType} and {rewardValue} placeholders with actual values
  static List<String> getVerificationBenefits(String? gender) {
    List<String> benefits;

    if (gender?.toLowerCase() == 'male') {
      benefits = _verifyBenefitsMale.isNotEmpty
          ? _verifyBenefitsMale
          : _defaultBenefitsMale;
    } else {
      benefits = _verifyBenefitsFemale.isNotEmpty
          ? _verifyBenefitsFemale
          : _defaultBenefitsFemale;
    }

    // Get gender-specific reward config
    final config = getRewardConfig(gender);
    final rewardType = config['rewardType'] as String;
    final rewardValue = config['rewardValue'] as int;

    // Replace placeholders with actual values
    return benefits
        .map(
          (text) => text
              .replaceAll('{rewardType}', rewardType)
              .replaceAll('{rewardValue}', rewardValue.toString()),
        )
        .toList();
  }

  /// Get safety tips title based on user type
  static String getSafetyTitle({required bool isNewUser}) {
    return isNewUser ? _safetyTitleNew : _safetyTitleExisting;
  }

  /// Get safety tips based on user type
  static List<String> getSafetyTips({required bool isNewUser}) {
    if (isNewUser) {
      return _safetyTipsNew.isNotEmpty ? _safetyTipsNew : _defaultSafetyTipsNew;
    } else {
      return _safetyTipsExisting.isNotEmpty
          ? _safetyTipsExisting
          : _defaultSafetyTipsExisting;
    }
  }

  /// Get success verification subtitle
  static String get successSubtitle => _successSubtitle;

  /// Get success button text
  static String get successButtonText => _successButtonText;

  /// Whether to show verified badge
  static bool get shouldShowBadge => _showBadge;

  /// Get current safety tips version from Firebase
  static int get safetyTipsVersion => _safetyTipsVersion;

  /// Get Connections screen All tab empty state title
  static String get allTabEmptyTitle => _allTabEmptyTitle;

  /// Get Connections screen All tab empty state message
  static String get allTabEmptyMessage => _allTabEmptyMessage;

  /// Get male placeholder image URL
  static String get maleImageUrl => _maleImageUrl;

  /// Get female placeholder image URL
  static String get femaleImageUrl => _femaleImageUrl;

  /// Get list of background images
  static List<String> get backgroundImages => _backgroundImages;

  static String get baseUrl => _baseUrl;

  /// Get a random background image URL, or null if no backgrounds configured
  static String? getRandomBackgroundImage() {
    if (_backgroundImages.isEmpty) return null;
    final random =
        DateTime.now().millisecondsSinceEpoch % _backgroundImages.length;
    return _backgroundImages[random];
  }

  /// Get placeholder image URL for a specific gender
  static String getPlaceholderImageUrl(String? gender) {
    return gender?.toLowerCase() == 'male' ? _maleImageUrl : _femaleImageUrl;
  }

  /// Get subscription policies list
  static List<String> get subscriptionPolicies => _subscriptionPolicies;

  /// Restricted regexes loaded from AppConfig/RestrictedRegex
  static RegExp get emailRegex => _emailRegex;
  static RegExp get genericUrlRegex => _genericUrlRegex;
  static RegExp get phoneRegex => _phoneRegex;
  static RegExp get socialProfileRegex => _socialProfileRegex;
  static RegExp get socialUrlRegex => _socialUrlRegex;
  static RegExp get suspiciousEmailRegex => _suspiciousEmailRegex;

  /// Get Interests
  static List<String> get interests => _interests;

  /// Get Interests
  static Map<String, dynamic> get profileWeightage => _profileWeightage;

  /// Get max active devices limit from AppConfig
  static int get maxActiveDevices => _maxActiveDevices;

  static int get imageSendLimit => _imageSendLimit;

  static bool get isLoaded => _isLoaded;

  /// Listen to PlaceholderImages config changes in real-time
  static Stream<Map<String, dynamic>?> get placeholderImagesStream {
    return _firestore
        .collection(_collectionName)
        .doc('PlaceholderImages')
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  /// Get verified badge URI
  // static String get verifiedBadgeUri => _verifiedBadgeUri;

  /// Listen to Verified Badge config changes in real-time
  static Stream<Map<String, dynamic>?> get verifiedBadgeStream {
    return _firestore
        .collection(_collectionName)
        .doc('verifiedBadge')
        .snapshots()
        .map((snapshot) => snapshot.data());
  }
}
