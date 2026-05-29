// FILE: business_logic/profile_business_logic.dart
// Pure business logic layer - no UI dependencies, no direct backend calls
// All functions are static and testable independently

import 'package:viora/Services/profile_repository.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:flutter/material.dart';

/// Business Logic Layer for Profile Operations
/// Handles validation, transformations, and orchestrates repository calls
class ProfileBusinessLogic {
  /// Validate if more photos can be added
  /// Returns error message if validation fails, null if valid
  static String? validatePhotoUpload(int currentPhotoCount) {
    const maxPhotos = 5;
    if (currentPhotoCount >= maxPhotos) {
      return "You can't Upload more than $maxPhotos Photos";
    }
    return null;
  }

  /// Business logic to set a photo as profile picture
  /// Reorders images array to put selected image first
  static Future<void> setAsProfilePicture(
    String selectedImage,
    List<String> allImages,
  ) async {
    try {
      // Business rule: Profile picture must be first in array
      final reorderedImages = _reorderImagesForProfile(
        selectedImage,
        allImages,
      );

      // Delegate to repository for persistence
      await ProfileRepository.updateUserImages(reorderedImages);

      // Show success notification (could be moved to UI layer in future)
      showSimpleNotification(
        Text("Profile picture Updated"),
        leading: Icon(Icons.done),
        position: NotificationPosition.bottom,
        background: Colors.green,
        duration: Duration(seconds: 2),
        slideDismissDirection: DismissDirection.down,
      );
    } catch (e) {
      _showErrorNotification("Failed to update profile picture");
      rethrow;
    }
  }

  /// Business logic to delete a photo
  /// Handles storage deletion and database update
  static Future<void> deletePhoto(String imageUrl) async {
    try {
      // Delegate to repository for deletion
      await ProfileRepository.deleteUserPhoto(imageUrl);

      showSimpleNotification(
        Text("Photo Deleted Successfully"),
        leading: Icon(Icons.done),
        position: NotificationPosition.bottom,
        background: Colors.redAccent,
        duration: Duration(seconds: 2),
        slideDismiss: true,
      );
    } catch (e) {
      print("Error deleting photo: $e");
      _showErrorNotification("Failed to delete photo");
      rethrow;
    }
  }

  /// Pure function to reorder images array
  /// Makes selected image first, keeps others in original order
  static List<String> _reorderImagesForProfile(
    String profileImage,
    List<String> allImages,
  ) {
    final reordered = <String>[];
    reordered.add(profileImage);

    for (final image in allImages) {
      if (image != profileImage) {
        reordered.add(image);
      }
    }

    return reordered;
  }

  /// Extract filename from Firebase storage URL
  /// Used for deletion operations
  static String extractFilenameFromUrl(String url) {
    final decodedUrl = Uri.decodeFull(url);
    // Remove query parameters
    return decodedUrl.replaceAll(RegExp(r'(\?alt).*'), '');
  }

  /// Validate user profile completeness
  /// Returns list of missing required fields
  static List<String> validateProfileCompleteness({
    required String? name,
    required String? gender,
    required int? age,
    required String? city,
    required String? state,
    required List<String>? images,
  }) {
    final missingFields = <String>[];

    if (name == null || name.isEmpty) {
      missingFields.add('Name');
    }

    if (gender == null || gender.isEmpty) {
      missingFields.add('Gender');
    }

    if (age == null || age < 18 || age > 100) {
      missingFields.add('Valid Age (18-100)');
    }

    if (city == null || city.isEmpty) {
      missingFields.add('City');
    }

    if (state == null || state.isEmpty) {
      missingFields.add('State');
    }

    if (images == null || images.isEmpty) {
      missingFields.add('At least one photo');
    }

    return missingFields;
  }

  /// Calculate profile completion percentage
  /// Returns value between 0 and 100
  static int calculateProfileCompletion({
    required bool hasName,
    required bool hasGender,
    required bool hasAge,
    required bool hasLocation,
    required bool hasPhotos,
    required bool hasMaritalStatus,
    required bool hasSexualOrientation,
    required bool hasRelationshipTypes,
  }) {
    int totalFields = 8;
    int completedFields = 0;

    if (hasName) completedFields++;
    if (hasGender) completedFields++;
    if (hasAge) completedFields++;
    if (hasLocation) completedFields++;
    if (hasPhotos) completedFields++;
    if (hasMaritalStatus) completedFields++;
    if (hasSexualOrientation) completedFields++;
    if (hasRelationshipTypes) completedFields++;

    return ((completedFields / totalFields) * 100).round();
  }

  /// Show error notification helper
  static void _showErrorNotification(String message) {
    showSimpleNotification(
      Text(message),
      leading: Icon(Icons.error),
      position: NotificationPosition.bottom,
      background: Colors.redAccent,
      duration: Duration(seconds: 3),
      slideDismiss: true,
    );
  }
}

/// Heavy computation functions that should run in isolates
/// These are registered in isolate_helper.dart
class ProfileComputations {
  /// Process large batch of images (e.g., sorting, filtering)
  /// Should be called via isolate for lists > 50 items
  static List<String> sortImagesBySize(List<String> imageUrls) {
    // Heavy computation: sort by URL length as proxy for image size
    final sorted = List<String>.from(imageUrls);
    sorted.sort((a, b) => b.length.compareTo(a.length));
    return sorted;
  }

  /// Batch process user data transformations
  /// Used for heavy operations on user lists
  static Map<String, dynamic> computeUserStatistics({
    required int age,
    required int photoCount,
    required bool hasCompleteProfile,
    required DateTime joiningDate,
  }) {
    final daysSinceJoining = DateTime.now().difference(joiningDate).inDays;
    final profileScore = _calculateProfileScore(
      age: age,
      photoCount: photoCount,
      hasCompleteProfile: hasCompleteProfile,
      daysSinceJoining: daysSinceJoining,
    );

    return {
      'daysSinceJoining': daysSinceJoining,
      'profileScore': profileScore,
      'isNewUser': daysSinceJoining < 7,
      'isActiveUser': daysSinceJoining < 30,
    };
  }

  /// Calculate profile quality score (0-100)
  static int _calculateProfileScore({
    required int age,
    required int photoCount,
    required bool hasCompleteProfile,
    required int daysSinceJoining,
  }) {
    int score = 0;

    // Base score for complete profile
    if (hasCompleteProfile) score += 40;

    // Photo quality score (max 30 points)
    score += (photoCount * 6).clamp(0, 30);

    // Age appropriateness (max 15 points)
    if (age >= 18 && age <= 35) {
      score += 15;
    } else if (age > 35 && age <= 50) {
      score += 10;
    } else {
      score += 5;
    }

    // Activity score (max 15 points)
    if (daysSinceJoining < 7) {
      score += 15; // New users get bonus
    } else if (daysSinceJoining < 30) {
      score += 10;
    } else if (daysSinceJoining < 90) {
      score += 5;
    }

    return score.clamp(0, 100);
  }
}
