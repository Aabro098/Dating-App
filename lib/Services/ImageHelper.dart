import 'dart:math';
import 'package:viora/Services/AppConfigService.dart';

/// Helper class for image-related operations
class ImageHelper {
  static final Random _random = Random();
  
  /// Cache for consistent background images per user UID during session
  static final Map<String, String> _backgroundCache = {};
  
  /// Get a random background image URL from Firestore configuration
  /// Returns null if no background images are configured
  static String? getRandomBackgroundImage() {
    final backgrounds = AppConfigService.backgroundImages;
    if (backgrounds.isEmpty) return null;
    return backgrounds[_random.nextInt(backgrounds.length)];
  }
  
  /// Get a consistent background image for a user based on their UID
  /// Same user will always get the same background during the session
  static String? getConsistentBackgroundForUser(String uid) {
    // Check cache first
    if (_backgroundCache.containsKey(uid)) {
      return _backgroundCache[uid];
    }
    
    final backgrounds = AppConfigService.backgroundImages;
    if (backgrounds.isEmpty) return null;
    
    // Use hash of UID to deterministically select background
    final hash = uid.hashCode.abs();
    final selectedBg = backgrounds[hash % backgrounds.length];
    
    // Cache for session consistency
    _backgroundCache[uid] = selectedBg;
    return selectedBg;
  }
  
  /// Get placeholder image URL based on gender
  /// Falls back to Firestore-configured placeholder images
  static String getPlaceholderImage(String? gender) {
    return AppConfigService.getPlaceholderImageUrl(gender);
  }
  
  /// Get user's display image with fallback to placeholder
  /// Also returns a random background image if available
  static UserImageResult getUserImageWithBackground({
    required List<String>? userImages,
    required String? gender,
  }) {
    String imageUrl;
    
    if (userImages != null && userImages.isNotEmpty) {
      imageUrl = userImages[0];
    } else {
      imageUrl = getPlaceholderImage(gender);
    }
    
    return UserImageResult(
      imageUrl: imageUrl,
      backgroundImageUrl: getRandomBackgroundImage(),
    );
  }
  
  /// BACKWARD COMPATIBILITY METHOD
  /// Replace usage of: `(user.gender == "Male" ? kMaleUrl : kFemaleUrl)`
  /// With: `ImageHelper.getPlaceholderForGender(user.gender)`
  /// 
  /// This method provides the same functionality but uses Firestore configuration
  static String getPlaceholderForGender(String? gender) {
    return getPlaceholderImage(gender);
  }
  
  /// BACKWARD COMPATIBILITY METHOD
  /// For simple image display without background
  /// Replace: `user.images?.isEmpty ?? true ? kMaleUrl : user.images![0]`
  /// With: `ImageHelper.getUserImage(user.images, user.gender)`
  static String getUserImage(List<String>? images, String? gender) {
    if (images != null && images.isNotEmpty) {
      return images[0];
    }
    return getPlaceholderImage(gender);
  }
}

/// Result class for user image operations
class UserImageResult {
  final String imageUrl;
  final String? backgroundImageUrl;
  
  UserImageResult({
    required this.imageUrl,
    this.backgroundImageUrl,
  });
}
