import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:viora/Services/SubscriptionService.dart';
import 'package:viora/Screens/CompleteProfile/completeProfile.dart';
import 'package:viora/Screens/Home/home.dart';
import 'package:viora/Screens/Splash/splashScreen.dart';
import 'package:viora/Services/user_service.dart';
import 'package:viora/components/reusable_dialog.dart';
import 'Global.dart';
import 'PhoneAuthService.dart';
import 'session_service.dart';
import 'exceptions/exceptions.dart';

class GoogleAuthResult {
  final bool success;
  final String? errorMessage;
  final GoogleAuthErrorType? errorType;

  GoogleAuthResult({required this.success, this.errorMessage, this.errorType});
}

enum GoogleAuthErrorType {
  canceled,
  interrupted,
  networkError,
  accountExists,
  invalidCredential,
  userDisabled,
  operationNotAllowed,
  clientConfigurationError,
  providerConfigurationError,
  uiUnavailable,
  userMismatch,
  unknown,
}

class GoogleAuth {
  static final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  static bool _isInitialized = false;
  static GoogleSignInAccount? _currentUser;

  // Store authenticated Google email for CompleteProfile screen
  static String? _authenticatedEmail;

  /// Get the authenticated Google email
  static String? get authenticatedEmail => _authenticatedEmail;

  static void setAuthenticatedEmail(String? email) {
    _authenticatedEmail = email;
  }

  static void setAuthenticatedEmailNull() {
    _authenticatedEmail = null;
  }

  /// Clear the authenticated email (call on logout)
  static void clearAuthenticatedEmail() {
    _authenticatedEmail = null;
  }

  /// Web Client ID (OAuth 2.0 client type "Web") from Firebase/Google Cloud.
  /// Required on Android for "Developer console is not set up correctly" to be resolved.
  static const String _serverClientId =
      '877294522958-cdq4j63un6h8muvk8vojui0dpb70596p.apps.googleusercontent.com';

  /// Initialize Google Sign-In (required in v7)
  static Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      try {
        await _googleSignIn.initialize(serverClientId: _serverClientId);
        _isInitialized = true;
        _log('Google Sign-In initialized successfully (with serverClientId)');
      } catch (e, stackTrace) {
        _log('Failed to initialize Google Sign-In');
        throw ServerException(
          technicalMessage: 'Google Sign-In initialization failed: $e',
          code: 'GOOGLE_INIT_FAILED',
          stackTrace: stackTrace,
        );
      }
    }
  }

  /// Sign in with Google using v7 authenticate() method
  static Future<GoogleAuthResult> signInWithGoogle(BuildContext context) async {
    try {
      _log('🔵 signInWithGoogle: start');

      await _ensureInitialized();
      _log('🔵 Google Sign-In initialized');

      if (!_googleSignIn.supportsAuthenticate()) {
        _log('❌ supportsAuthenticate() = false');
        return GoogleAuthResult(
          success: false,
          errorMessage: 'Google Sign-In is not supported on this platform',
          errorType: GoogleAuthErrorType.operationNotAllowed,
        );
      }

      _log('🔵 Calling _googleSignIn.authenticate()...');
      final GoogleSignInAccount googleUser = await _googleSignIn
          .authenticate(scopeHint: ['email'])
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw TimeoutAppException(
                technicalMessage:
                    'Google Sign-In authentication timed out after 30 seconds',
                code: 'GOOGLE_AUTHENTICATE_TIMEOUT',
              );
            },
          );

      _log('🔵 authenticate() OK, email: ${googleUser.email}');

      final authClient = _googleSignIn.authorizationClient;
      final authorization = await authClient
          .authorizationForScopes(['email'])
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              throw TimeoutAppException(
                technicalMessage:
                    'Google authorization timed out after 20 seconds',
                code: 'GOOGLE_AUTHORIZATION_TIMEOUT',
              );
            },
          );

      if (authorization == null) {
        _log('❌ authorizationForScopes returned null');
        return GoogleAuthResult(
          success: false,
          errorMessage: 'Failed to obtain authorization',
          errorType: GoogleAuthErrorType.invalidCredential,
        );
      }

      _log('🔵 authorization OK');

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      if (googleAuth.idToken == null) {
        _log('❌ idToken is null');
        return GoogleAuthResult(
          success: false,
          errorMessage: 'Failed to obtain authentication tokens',
          errorType: GoogleAuthErrorType.invalidCredential,
        );
      }

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: authorization.accessToken,
        idToken: googleAuth.idToken,
      );

      _log('🔵 Signing in to Firebase...');

      final UserCredential userCredential = await _firebaseAuth
          .signInWithCredential(credential)
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () {
              throw TimeoutAppException(
                technicalMessage: 'Firebase sign-in timed out after 25 seconds',
                code: 'GOOGLE_FIREBASE_TIMEOUT',
              );
            },
          );

      final user = userCredential.user;
      if (user == null) {
        _log('❌ userCredential.user == null');
        return GoogleAuthResult(
          success: false,
          errorMessage: 'Authentication failed. Please try again.',
          errorType: GoogleAuthErrorType.unknown,
        );
      }

      _log('🔵 Firebase signInWithCredential OK, uid: ${user.uid}');

      _currentUser = googleUser;
      _authenticatedEmail = googleUser.email;
      PhoneAuth.clearAuthenticatedPhone();

      _log("Google Login successful - Email: ${googleUser.email}");
      _log("🔑 Phone auth cleared (switched to Google login)");

      await UserService.ensureUserDocument(user);
      _log('✅ User document ensured for uid: ${user.uid}');

      if (!context.mounted) {
        return GoogleAuthResult(success: true);
      }

      try {
        final globals = Globals.of(context);

        final sessionResult =
            await SessionService.prepareSessionForCurrentUser();

        if (!context.mounted) {
          return GoogleAuthResult(success: true);
        }

        if (sessionResult.maxZero) {
          final confirmed = await ReusableDialog.show(
            context,
            'Login disabled',
            'Login is currently disabled. Please try again later.',
            "Go Back",
            onConfirm: () async {},
            showCancelButton: false,
          );

          if (confirmed) {
            await SessionService.clearSavedSessionId();
            await _firebaseAuth.signOut();
            await _googleSignIn.signOut();

            return GoogleAuthResult(
              success: false,
              errorMessage: 'Login cancelled.',
              errorType: GoogleAuthErrorType.canceled,
            );
          }
        }

        if (sessionResult.needsUserConfirmation) {
          final confirmed = await ReusableDialog.show(
            context,
            'Session already active',
            'This account is already active on another device. Do you want to continue on this device and log out the other device?',
            "Login",
            onConfirm: () async {},
          );

          if (confirmed != true) {
            await SessionService.clearSavedSessionId();
            await _firebaseAuth.signOut();
            await _googleSignIn.signOut();

            return GoogleAuthResult(
              success: false,
              errorMessage: 'Login cancelled.',
              errorType: GoogleAuthErrorType.canceled,
            );
          }

          await SessionService.confirmSessionReplacementForCurrentUser();
        }

        PermissionSessionManager.resetAllSessions(globals.prefs);
        final hasProfile = await globals.initializeUserData(context, false);
        _log("Initialization complete. Has profile: $hasProfile");

        if (!context.mounted) {
          return GoogleAuthResult(success: true);
        }

        if (hasProfile) {
          try {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid != null) {
              await SubscriptionService.refreshRevenueCatIdentity(uid);
              _log('✅ RevenueCat identity + Play sync for $uid');
            }
          } catch (e) {
            _log('⚠️ RevenueCat sync error: $e');
          }

          Navigator.pushNamedAndRemoveUntil(
            context,
            Home.routeName,
            (Route<dynamic> route) => false,
          );
        } else {
          Navigator.pushNamedAndRemoveUntil(
            context,
            CompleteProfile.routeName,
            (Route<dynamic> route) => false,
          );
        }

        _log('✅ signInWithGoogle: success');
        return GoogleAuthResult(success: true);
      } on FirebaseException catch (e, stackTrace) {
        _log('❌ Firestore/init error: ${e.code} ${e.message}');
        ErrorHandler.handle(context, e, stackTrace, true);

        if (context.mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            SplashScreen.routeName,
            (Route<dynamic> route) => false,
          );
        }

        return GoogleAuthResult(
          success: false,
          errorMessage:
              'Signed in, but account setup failed. Please try again.',
          errorType: GoogleAuthErrorType.unknown,
        );
      } catch (e, stackTrace) {
        _log('❌ Error during user initialization');
        ErrorHandler.handle(context, e, stackTrace, true);

        if (context.mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            SplashScreen.routeName,
            (Route<dynamic> route) => false,
          );
        }

        return GoogleAuthResult(
          success: false,
          errorMessage: 'Signed in, but app initialization failed.',
          errorType: GoogleAuthErrorType.unknown,
        );
      }
    } on TimeoutAppException catch (e) {
      _log('⏱️ ${e.technicalMessage}');
      return GoogleAuthResult(
        success: false,
        errorMessage:
            'Sign-in is taking too long. Please check your internet and try again.',
        errorType: GoogleAuthErrorType.networkError,
      );
    } on GoogleSignInException catch (e) {
      _log(
        '❌ GoogleSignInException: code=${e.code.name}, description=${e.description}',
      );
      return _handleGoogleSignInException(e);
    } on FirebaseAuthException catch (e) {
      _log('❌ FirebaseAuthException: code=${e.code}, message=${e.message}');
      return _handleFirebaseAuthException(e);
    } on PlatformException catch (e) {
      _log('❌ PlatformException: code=${e.code}, message=${e.message}');
      return _handlePlatformException(e);
    } catch (e, st) {
      debugPrint('[GoogleAuth] ❌ Unexpected error: $e');
      debugPrint('[GoogleAuth] stackTrace: $st');
      return GoogleAuthResult(
        success: false,
        errorMessage: 'An unexpected error occurred. Please try again.',
        errorType: GoogleAuthErrorType.unknown,
      );
    }
  }

  /// Handle GoogleSignInException (new in v7)
  static GoogleAuthResult _handleGoogleSignInException(
    GoogleSignInException e,
  ) {
    switch (e.code.name) {
      case 'canceled':
        return GoogleAuthResult(
          success: false,
          errorMessage:
              'Sign-in was cancelled. Please try again if you want to continue.',
          errorType: GoogleAuthErrorType.canceled,
        );
      case 'interrupted':
        return GoogleAuthResult(
          success: false,
          errorMessage: 'Sign-in was interrupted. Please try again.',
          errorType: GoogleAuthErrorType.interrupted,
        );
      case 'clientConfigurationError':
        return GoogleAuthResult(
          success: false,
          errorMessage:
              'There is a configuration issue with Google Sign-In. Please contact support.',
          errorType: GoogleAuthErrorType.clientConfigurationError,
        );
      case 'providerConfigurationError':
        return GoogleAuthResult(
          success: false,
          errorMessage:
              'Google Sign-In is currently unavailable. Please try again later or contact support.',
          errorType: GoogleAuthErrorType.providerConfigurationError,
        );
      case 'uiUnavailable':
        return GoogleAuthResult(
          success: false,
          errorMessage:
              'Google Sign-In UI is currently unavailable. Please try again later.',
          errorType: GoogleAuthErrorType.uiUnavailable,
        );
      case 'userMismatch':
        return GoogleAuthResult(
          success: false,
          errorMessage:
              'There was an issue with your account. Please sign out and try again.',
          errorType: GoogleAuthErrorType.userMismatch,
        );
      case 'unknownError':
      default:
        final desc = (e.description ?? '').toLowerCase();
        final isDeveloperError =
            desc.contains('developer') ||
            desc.contains('apiException: 10') ||
            desc.contains('10:');
        return GoogleAuthResult(
          success: false,
          errorMessage: isDeveloperError
              ? 'Google Sign-In is not configured for this app. Add your app\'s SHA-1 in Firebase Console (Project settings → Your apps → Android) and ensure the package name is com.epochtechlabs.viora.'
              : (e.description ??
                    'An unexpected error occurred during Google Sign-In. Please try again.'),
          errorType: GoogleAuthErrorType.unknown,
        );
    }
  }

  /// Handle FirebaseAuthException errors
  static GoogleAuthResult _handleFirebaseAuthException(
    FirebaseAuthException e,
  ) {
    _log('FirebaseAuthException: ${e.code}');

    switch (e.code) {
      case 'account-exists-with-different-credential':
        return GoogleAuthResult(
          success: false,
          errorMessage:
              'An account already exists with this email using a different sign-in method.',
          errorType: GoogleAuthErrorType.accountExists,
        );
      case 'invalid-credential':
        return GoogleAuthResult(
          success: false,
          errorMessage: 'Invalid credentials. Please try again.',
          errorType: GoogleAuthErrorType.invalidCredential,
        );
      case 'operation-not-allowed':
        return GoogleAuthResult(
          success: false,
          errorMessage:
              'Google sign-in is not enabled. Please contact support.',
          errorType: GoogleAuthErrorType.operationNotAllowed,
        );
      case 'user-disabled':
        return GoogleAuthResult(
          success: false,
          errorMessage:
              'This account has been disabled. Please contact support.',
          errorType: GoogleAuthErrorType.userDisabled,
        );
      case 'user-not-found':
        return GoogleAuthResult(
          success: false,
          errorMessage: 'No account found. Please sign up first.',
          errorType: GoogleAuthErrorType.unknown,
        );
      case 'wrong-password':
        return GoogleAuthResult(
          success: false,
          errorMessage: 'Invalid credentials. Please try again.',
          errorType: GoogleAuthErrorType.invalidCredential,
        );
      case 'network-request-failed':
        return GoogleAuthResult(
          success: false,
          errorMessage: 'Network error. Please check your internet connection.',
          errorType: GoogleAuthErrorType.networkError,
        );
      case 'too-many-requests':
        return GoogleAuthResult(
          success: false,
          errorMessage: 'Too many attempts. Please try again later.',
          errorType: GoogleAuthErrorType.unknown,
        );
      default:
        return GoogleAuthResult(
          success: false,
          errorMessage: e.message ?? 'Authentication failed. Please try again.',
          errorType: GoogleAuthErrorType.unknown,
        );
    }
  }

  /// Handle PlatformException errors
  static GoogleAuthResult _handlePlatformException(PlatformException e) {
    _log('PlatformException: code=${e.code}, message=${e.message}');

    switch (e.code) {
      case 'sign_in_canceled':
        return GoogleAuthResult(
          success: false,
          errorMessage: 'Sign-in canceled',
          errorType: GoogleAuthErrorType.canceled,
        );
      case 'sign_in_failed':
        {
          final msg = (e.message ?? '').toLowerCase();
          final isDeveloperError =
              msg.contains('developer') ||
              msg.contains('apiException: 10') ||
              msg.contains('10:');
          return GoogleAuthResult(
            success: false,
            errorMessage: isDeveloperError
                ? 'Google Sign-In is not configured for this app. Add your app\'s SHA-1 in Firebase Console (Project settings → Your apps → Android) and ensure the package name is com.epochtechlabs.viora.'
                : 'Sign-in failed. Please try again.',
            errorType: GoogleAuthErrorType.unknown,
          );
        }
      case 'network_error':
        return GoogleAuthResult(
          success: false,
          errorMessage: 'Network error. Please check your internet connection.',
          errorType: GoogleAuthErrorType.networkError,
        );
      default:
        return GoogleAuthResult(
          success: false,
          errorMessage: e.message ?? 'An error occurred. Please try again.',
          errorType: GoogleAuthErrorType.unknown,
        );
    }
  }

  /// Attempt silent sign-in (v7 method: attemptLightweightAuthentication)
  static Future<GoogleAuthResult> signInSilently(BuildContext context) async {
    try {
      await _ensureInitialized();

      // v7 method can return Future or immediate result
      final result = _googleSignIn.attemptLightweightAuthentication();

      GoogleSignInAccount? googleUser;
      if (result is Future<GoogleSignInAccount?>) {
        googleUser = await result;
      } else {
        googleUser = result as GoogleSignInAccount?;
      }

      if (googleUser == null) {
        return GoogleAuthResult(
          success: false,
          errorMessage: 'No previous sign-in found',
          errorType: GoogleAuthErrorType.canceled,
        );
      }

      // Get authorization
      final authClient = _googleSignIn.authorizationClient;
      final authorization = await authClient.authorizationForScopes(['email']);

      if (authorization == null) {
        return GoogleAuthResult(
          success: false,
          errorMessage: 'Failed to obtain authorization',
          errorType: GoogleAuthErrorType.invalidCredential,
        );
      }

      // Get authentication - synchronous in v7
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      if (authorization.accessToken == null || googleAuth.idToken == null) {
        return GoogleAuthResult(
          success: false,
          errorMessage: 'Failed to obtain authentication tokens',
          errorType: GoogleAuthErrorType.invalidCredential,
        );
      }

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: authorization.accessToken,
        idToken: googleAuth.idToken,
      );

      await _firebaseAuth.signInWithCredential(credential);
      _currentUser = googleUser;

      return GoogleAuthResult(success: true);
    } on GoogleSignInException catch (e) {
      return _handleGoogleSignInException(e);
    } on FirebaseAuthException catch (e) {
      return _handleFirebaseAuthException(e);
    } on PlatformException catch (e) {
      return _handlePlatformException(e);
    } catch (e) {
      _log('Error during silent sign-in');
      return GoogleAuthResult(
        success: false,
        errorMessage: 'Silent sign-in failed',
        errorType: GoogleAuthErrorType.unknown,
      );
    }
  }

  /// Sign out from both Google and Firebase
  static Future<GoogleAuthResult> logoutOnly() async {
    try {
      await _ensureInitialized();

      await SubscriptionService.logOutRevenueCat();

      await _googleSignIn.signOut().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutAppException(
            technicalMessage: 'Google logout timed out',
            code: 'GOOGLE_LOGOUT_TIMEOUT',
          );
        },
      );

      _currentUser = null;
      PermissionSessionManager.resetSafetyTipsSession();

      return GoogleAuthResult(success: true);
    } catch (e) {
      _log('Google logout failed: $e');

      return GoogleAuthResult(
        success: false,
        errorMessage: 'Failed to sign out from Google.',
        errorType: GoogleAuthErrorType.unknown,
      );
    }
  }

  /// Disconnect Google account (revoke access)
  static Future<GoogleAuthResult> disconnect() async {
    try {
      await _ensureInitialized();

      await _googleSignIn.disconnect();
      await _firebaseAuth.signOut();

      _currentUser = null;

      return GoogleAuthResult(success: true);
    } on PlatformException catch (e) {
      _log('PlatformException during disconnect: ${e.code}');
      return GoogleAuthResult(
        success: false,
        errorMessage: 'Failed to disconnect Google account',
        errorType: GoogleAuthErrorType.unknown,
      );
    } catch (e) {
      _log('Error disconnecting Google account');
      return GoogleAuthResult(
        success: false,
        errorMessage: 'An unexpected error occurred',
        errorType: GoogleAuthErrorType.unknown,
      );
    }
  }

  /// Check if user is currently signed in (manual state management in v7)
  static bool isSignedIn() {
    return _currentUser != null || _firebaseAuth.currentUser != null;
  }

  /// Get current Google user (manual state management in v7)
  static GoogleSignInAccount? getCurrentGoogleUser() {
    return _currentUser;
  }

  /// Get current Firebase user
  static User? getCurrentFirebaseUser() {
    return _firebaseAuth.currentUser;
  }

  /// Show error dialog with appropriate message
  static void showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Authentication Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show error snackbar with appropriate message
  static void showErrorSnackbar(BuildContext context, String message) {
    ErrorHandler.showError(context, message);
  }

  /// Debug logging - only in debug mode
  static void _log(String message) {
    if (kDebugMode) {
      debugPrint('[GoogleAuth] $message');
    }
  }
}
