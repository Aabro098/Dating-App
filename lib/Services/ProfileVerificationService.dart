import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:viora/Services/AppConfigService.dart';
import 'package:viora/Services/FacePlusPlusService.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/Services/exceptions/exceptions.dart';

// Helper for conditional logging
void _log(String message) {
  if (kDebugMode) {
    debugPrint('[ProfileVerification] $message');
  }
}

/// Service class for handling profile verification flow
///
/// Flow:
/// 1. Liveness Detection (blink detection)
/// 2. Capture selfie image
/// 3. Upload to Firebase Storage
/// 4. Call Face++ API for gender detection
/// 5. Validate gender matches profile
/// 6. On success: save image URL, set verified badge, add gender-specific rewards
///
/// Note: Verification rewards are gender-specific and fetched from Firestore:
///   - Males: AppConfig/RewardsMale (typically coins)
///   - Females: AppConfig/RewardsFemale (typically premium days, gems, etc.)
class ProfileVerificationService {
  /// Verification result states
  static const String resultSuccess = 'success';
  static const String resultNoFaceDetected = 'no_face';
  static const String resultGenderMismatch = 'gender_mismatch';
  static const String resultLowQuality = 'low_quality';
  static const String resultBlurry = 'blurry';
  static const String resultError = 'error';

  /// Upload selfie image to Firebase Storage
  ///
  /// [imageBytes] - The captured image bytes
  /// Returns both download URL and storage path of the uploaded image
  static Future<VerificationImageUpload> uploadVerificationImage(
    Uint8List imageBytes,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('User not authenticated');

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'verification_images/$uid/selfie_$timestamp.jpg';

    final ref = FirebaseStorage.instance.ref().child(path);

    _log('Uploading verification image to: $path');

    final uploadTask = await ref
        .putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'))
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            throw TimeoutException('Image upload timed out after 60 seconds');
          },
        );

    final downloadUrl = await uploadTask.ref.getDownloadURL().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw TimeoutException('Failed to get download URL');
      },
    );
    _log('Image uploaded successfully: $downloadUrl');

    return VerificationImageUpload(downloadUrl: downloadUrl, storagePath: path);
  }

  /// Main verification method
  ///
  /// [imageBytes] - The captured selfie bytes from liveness detection
  /// [profileGender] - The gender from user's profile
  /// [context] - BuildContext for accessing Globals
  ///
  /// Returns [VerificationResult] with status and details
  static Future<VerificationResult> verifyProfile({
    required Uint8List imageBytes,
    required String profileGender,
    required BuildContext context,
  }) async {
    try {
      _log('Starting profile verification...');
      _log('Profile Gender: $profileGender');

      // Step 1: Upload image to Firebase Storage
      _log('Step 1: Uploading image...');
      final imageUpload = await uploadVerificationImage(imageBytes);
      final imageUrl = imageUpload.downloadUrl;
      final imagePath = imageUpload.storagePath;

      // Step 2: Call Face++ API
      _log('Step 2: Analyzing image with Face++...');
      final faceResult = await FacePlusPlusService.analyzeImage(imageBytes);

      // Step 3: Validate face detection
      _log('Step 3: Validating face detection...');
      if (!faceResult.hasFace) {
        _log('No face detected in image');
        return VerificationResult(
          status: resultNoFaceDetected,
          message:
              'No face detected in the image. Please try again with a clear photo of your face.',
          imageUrl: imageUrl,
        );
      }

      // Step 4: Check image quality
      _log('Step 4: Checking image quality...');
      if (faceResult.isBlurry) {
        _log('Image is too blurry');
        return VerificationResult(
          status: resultBlurry,
          message:
              'Image is too blurry. Please try again with better lighting.',
          imageUrl: imageUrl,
        );
      }

      // Step 5: Validate gender
      _log('Step 5: Validating gender...');
      final detectedGender = faceResult.detectedGender;
      _log('Detected Gender: $detectedGender');
      _log('Profile Gender: $profileGender');

      final genderMatches = FacePlusPlusService.validateGender(
        detectedGender,
        profileGender,
      );

      if (!genderMatches) {
        _log('Gender mismatch detected');
        return VerificationResult(
          status: resultGenderMismatch,
          message:
              'The detected gender does not match your profile. Please ensure your photo matches your profile gender.',
          imageUrl: imageUrl,
          detectedGender: detectedGender,
        );
      }

      // Step 6: All checks passed - Update Firestore
      _log('Step 6: All checks passed! Updating profile...');
      final coinsAwarded = await _updateVerifiedProfile(
        imageUrl,
        imagePath,
        context,
      );

      _log('Profile verification successful!');
      return VerificationResult(
        status: resultSuccess,
        message:
            'Profile verified successfully! You\'ve earned $coinsAwarded coins.',
        imageUrl: imageUrl,
        coinsAwarded: coinsAwarded,
        detectedGender: detectedGender,
      );
    } catch (e, stackTrace) {
      _log('Verification error: $e');
      final appException = ErrorHandler.convert(e, stackTrace);
      return VerificationResult(
        status: resultError,
        message: appException.userMessage,
      );
    }
  }

  /// Updates the user profile with verification data
  /// Returns the reward value awarded (coins, premium days, etc. based on gender)
  static Future<int> _updateVerifiedProfile(
    String imageUrl,
    String imagePath,
    BuildContext context,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('User not authenticated');

    // Get user gender to determine reward type
    final globals = Globals.of(context);
    final userGender = globals.prefs.userDetails.value?.gender ?? 'Male';

    // Get gender-specific reward value from AppConfig
    final rewardValue = AppConfigService.getRewardValue(userGender);
    final rewardType = AppConfigService.getRewardType(userGender);

    final userRef = FirebaseFirestore.instance.collection('Users').doc(uid);

    // Get current coins (cast to int to avoid type errors)
    final userDoc = await userRef.get().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw TimeoutException('Failed to fetch user data');
      },
    );
    final currentCoins = (userDoc.data()?['coins'] ?? 0).toInt();

    // Update profile with verification data
    // Note: For now we still use 'coins' field. In future, may add 'premiumDays' field for females
    await userRef.update({
      'isVerified': true,
      'verifiedImageUrl': imageUrl,
      'verifiedImagePath': imagePath,
      'verifiedAt': FieldValue.serverTimestamp(),
      'coins': currentCoins + rewardValue, // Universal field for now
      'lastRewardType': rewardType, // Track what type of reward was given
      'lastRewardValue': rewardValue,
    });

    // Update local prefs AND UserProvider
    final userDetails = globals.prefs.userDetails.value;
    if (userDetails != null) {
      userDetails.isVerified = true;
      userDetails.verifiedImageUrl = imageUrl;
      userDetails.verifiedImagePath = imagePath;
      userDetails.coins = ((userDetails.coins ?? 0).toInt() + rewardValue);
      await globals.prefs.userDetails.set(userDetails);

      // Also update UserProvider to trigger UI updates immediately
      globals.userProvider.updateUserDetails(userDetails);
    }

    print('✅ Profile updated in Firestore');
    print('   isVerified: true');
    print('   verifiedImageUrl: $imageUrl');
    print('   Reward: $rewardValue $rewardType');
    print(
      '   Coins: $currentCoins + $rewardValue = ${currentCoins + rewardValue}',
    );

    return rewardValue;
  }

  /// Awards bonus coins to verified users
  static Future<void> awardCoins(int amount, BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final userRef = FirebaseFirestore.instance.collection('Users').doc(uid);

    await userRef.update({'coins': FieldValue.increment(amount)});

    final globals = Globals.of(context);
    final userDetails = globals.prefs.userDetails.value;
    if (userDetails != null) {
      userDetails.coins = (userDetails.coins ?? 0) + amount;
      await globals.prefs.userDetails.set(userDetails);

      // Also update UserProvider to trigger UI updates immediately
      globals.userProvider.updateUserDetails(userDetails);
    }
  }

  /// Check if user is already verified
  static Future<bool> isUserVerified() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final userDoc = await FirebaseFirestore.instance
        .collection('Users')
        .doc(uid)
        .get();

    return userDoc.data()?['isVerified'] ?? false;
  }
}

/// Result class for verification process
class VerificationResult {
  final String status;
  final String message;
  final String? imageUrl;
  final int? coinsAwarded;
  final String? detectedGender;

  VerificationResult({
    required this.status,
    required this.message,
    this.imageUrl,
    this.coinsAwarded,
    this.detectedGender,
  });

  bool get isSuccess => status == ProfileVerificationService.resultSuccess;
  bool get isGenderMismatch =>
      status == ProfileVerificationService.resultGenderMismatch;
  bool get isNoFace =>
      status == ProfileVerificationService.resultNoFaceDetected;
  bool get isBlurry => status == ProfileVerificationService.resultBlurry;
  bool get isError => status == ProfileVerificationService.resultError;
}

class VerificationImageUpload {
  final String downloadUrl;
  final String storagePath;

  VerificationImageUpload({
    required this.downloadUrl,
    required this.storagePath,
  });
}
