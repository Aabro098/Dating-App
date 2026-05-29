import 'package:firebase_auth/firebase_auth.dart';

/// Helper class to determine the sign-in method used by the current user
class AuthHelper {
  static final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  /// Get the sign-in method for the current user
  ///
  /// Returns:
  /// - 'phone': if user signed in via phone number
  /// - 'google': if user signed in via Google
  /// - 'email': if user signed in via email/password
  /// - null: if no user is signed in
  static String? getSignInMethod() {
    User? user = _firebaseAuth.currentUser;

    if (user == null) return null;

    // Check provider data for authentication methods
    for (var provider in user.providerData) {
      if (provider.providerId == 'phone') {
        return 'phone';
      } else if (provider.providerId == 'google.com') {
        return 'google';
      } else if (provider.providerId == 'password') {
        return 'email';
      }
    }

    // Fallback: if only email exists and no providers
    return user.email != null ? 'email' : null;
  }

  /// Check if user signed in with phone number
  static bool isPhoneSignIn() => getSignInMethod() == 'phone';

  /// Check if user signed in with Google
  static bool isGoogleSignIn() => getSignInMethod() == 'google';

  /// Check if user signed in with email/password
  static bool isEmailSignIn() => getSignInMethod() == 'email';

  /// Get user's phone number if they signed in with phone
  static String? getPhoneNumber() {
    if (isPhoneSignIn()) {
      return _firebaseAuth.currentUser?.phoneNumber;
    }
    return null;
  }

  /// Get user's email if they signed in with Google or email
  static String? getEmail() {
    if (isGoogleSignIn() || isEmailSignIn()) {
      return _firebaseAuth.currentUser?.email;
    }
    return null;
  }

  /// Get all provider IDs linked to the account
  static List<String> getLinkedProviders() {
    User? user = _firebaseAuth.currentUser;
    if (user == null) return [];

    return user.providerData.map((provider) => provider.providerId).toList();
  }
}
