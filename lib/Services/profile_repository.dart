// FILE: data/repositories/profile_repository.dart
// Backend/Database Layer - Handles all external data operations
// No business logic, no UI dependencies

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/Services/StoragePathService.dart';

/// Repository Pattern for Profile Data Operations
/// Handles all Firebase interactions for profile management
class ProfileRepository {
  // Private constructor to prevent instantiation
  ProfileRepository._();

  /// Update user's images array in Firestore
  /// Used for reordering, adding, or updating images
  static Future<void> updateUserImages(List<String> images) async {
    try {
      DatabaseService.updateField({"imagePaths": images});
    } catch (e) {
      debugPrint("ProfileRepository: Error updating images: $e");
      throw ProfileRepositoryException(
        "Failed to update images",
        originalError: e,
      );
    }
  }

  /// Delete a photo from Firebase Storage and Firestore
  /// Performs both storage deletion and database update
  static Future<void> deleteUserPhoto(String imageRef) async {
    try {
      final storagePath = StoragePathService.extractPath(imageRef);
      if (storagePath == null || storagePath.isEmpty) {
        throw ProfileRepositoryException(
          'Invalid image reference for deletion',
        );
      }

      // Delete from Firebase Storage
      final storageRef = FirebaseStorage.instance.ref().child(storagePath);

      try {
        await storageRef.delete();
      } catch (storageError) {
        // Log but continue to update Firestore
        if (storageError.toString().contains('object-not-found')) {
        } else {
          rethrow;
        }
      }

      // Remove from Firestore array
      DatabaseService.updateField({
        "images": FieldValue.arrayRemove([imageRef]),
        "imagePaths": FieldValue.arrayRemove([storagePath]),
      });
    } catch (e) {
      throw ProfileRepositoryException(
        "Failed to delete photo",
        originalError: e,
      );
    }
  }

  /// Add a new photo to user's images array
  /// Only updates Firestore (assumes upload already done)
  static Future<void> addUserPhoto(String imageUrl) async {
    try {
      DatabaseService.updateField({
        "images": FieldValue.arrayUnion([imageUrl]),
      });
    } catch (e) {
      print("ProfileRepository: Error adding photo: $e");
      throw ProfileRepositoryException("Failed to add photo", originalError: e);
    }
  }

  /// Update user's profile picture (first image in array)
  /// This is a specific use case of updateUserImages
  static Future<void> setProfilePicture(
    String imageUrl,
    List<String> allImages,
  ) async {
    try {
      // Reorder images to put selected image first
      final reordered = [imageUrl];
      for (final img in allImages) {
        if (img != imageUrl) {
          reordered.add(img);
        }
      }

      await updateUserImages(reordered);
    } catch (e) {
      print("ProfileRepository: Error setting profile picture: $e");
      throw ProfileRepositoryException(
        "Failed to set profile picture",
        originalError: e,
      );
    }
  }

  /// Get current user's UID
  /// Helper method for other repository methods
  static String? getCurrentUserId() {
    return FirebaseAuth.instance.currentUser?.uid;
  }

  /// Update any field in user document
  /// Generic method for single field updates
  static Future<void> updateUserField(String field, dynamic value) async {
    try {
      DatabaseService.updateField({field: value});
    } catch (e) {
      print("ProfileRepository: Error updating field $field: $e");
      throw ProfileRepositoryException(
        "Failed to update $field",
        originalError: e,
      );
    }
  }

  /// Update multiple fields in user document
  /// Batch update for efficiency
  static Future<void> updateUserFields(Map<String, dynamic> fields) async {
    try {
      DatabaseService.updateField(fields);
    } catch (e) {
      print("ProfileRepository: Error updating fields: $e");
      throw ProfileRepositoryException(
        "Failed to update profile fields",
        originalError: e,
      );
    }
  }

  /// Get user document from Firestore
  /// Returns null if not found
  static Future<DocumentSnapshot?> getUserDocument(String uid) async {
    try {
      return await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
    } catch (e) {
      print("ProfileRepository: Error fetching user document: $e");
      throw ProfileRepositoryException(
        "Failed to fetch user data",
        originalError: e,
      );
    }
  }

  /// Check if user document exists
  static Future<bool> userExists(String uid) async {
    try {
      final doc = await getUserDocument(uid);
      return doc?.exists ?? false;
    } catch (e) {
      print("ProfileRepository: Error checking user existence: $e");
      return false;
    }
  }

  /// Upload image to Firebase Storage
  /// Returns the download URL
  static Future<String> uploadImage({
    required String localPath,
    required String fileName,
    required String uid,
  }) async {
    try {
      final storageRef = FirebaseStorage.instance.ref().child(
        'user_images/$uid/$fileName',
      );

      final uploadTask = await storageRef.putFile(localPath as dynamic);
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      print("ProfileRepository: Error uploading image: $e");
      throw ProfileRepositoryException(
        "Failed to upload image",
        originalError: e,
      );
    }
  }

  /// Delete multiple images in batch
  /// More efficient than deleting one by one
  static Future<void> deleteMultiplePhotos(List<String> imageRefs) async {
    try {
      final storagePaths = <String>[];

      // Delete from storage
      for (final imageRef in imageRefs) {
        final storagePath = StoragePathService.extractPath(imageRef);
        if (storagePath == null || storagePath.isEmpty) {
          continue;
        }
        storagePaths.add(storagePath);
        final storageRef = FirebaseStorage.instance.ref().child(storagePath);
        await storageRef.delete();
      }

      // Update Firestore in single operation
      DatabaseService.updateField({
        "images": FieldValue.arrayRemove(imageRefs),
        "imagePaths": FieldValue.arrayRemove(storagePaths),
      });
    } catch (e) {
      print("ProfileRepository: Error deleting multiple photos: $e");
      throw ProfileRepositoryException(
        "Failed to delete photos",
        originalError: e,
      );
    }
  }

  /// Get storage size used by user's images
  /// Useful for quota management
  static Future<int> getUserStorageSize(String uid) async {
    try {
      final storageRef = FirebaseStorage.instance.ref().child(
        'user_images/$uid',
      );
      final listResult = await storageRef.listAll();

      int totalSize = 0;
      for (final item in listResult.items) {
        final metadata = await item.getMetadata();
        totalSize += metadata.size ?? 0;
      }

      return totalSize;
    } catch (e) {
      print("ProfileRepository: Error getting storage size: $e");
      return 0;
    }
  }
}

/// Custom exception for repository errors
/// Provides better error handling and debugging
class ProfileRepositoryException implements Exception {
  final String message;
  final dynamic originalError;

  ProfileRepositoryException(this.message, {this.originalError});

  @override
  String toString() {
    if (originalError != null) {
      return 'ProfileRepositoryException: $message\nOriginal error: $originalError';
    }
    return 'ProfileRepositoryException: $message';
  }
}
