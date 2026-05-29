import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:viora/Screens/Splash/splashScreen.dart';
import 'package:viora/Services/user_service.dart';
import 'package:viora/components/reusable_dialog.dart';

import '../Screens/CompleteProfile/completeProfile.dart';
import '../Screens/Home/home.dart';
import '../Screens/Login_Signup/loginScreen.dart';
import '../Screens/otp/otp_screen.dart';
import 'Global.dart';
import 'session_service.dart';
import 'AuthService.dart';
import 'exceptions/exceptions.dart';
import '../utils/phone_validation_util.dart';

class PhoneAuth {
  PhoneAuth._();

  static String? _verificationId;
  static int? _resendToken;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static String? _lastPhoneNumber;
  static DateTime? _lastVerificationTime;
  static const _verificationSessionTimeout = Duration(seconds: 60);
  static String? _authenticatedPhone;
  static String? _authenticatedCountryCode;
  static String? get authenticatedPhone => _authenticatedPhone;
  static String? get authenticatedCountryCode => _authenticatedCountryCode;

  static void clearAuthenticatedPhone() {
    _authenticatedPhone = null;
    _authenticatedCountryCode = null;
  }

  static String? get verificationId => _verificationId;

  /// Verifies phone number and handles OTP flow
  ///
  /// [context] - BuildContext for navigation
  /// []
  /// [phoneNumber] - Phone number without country code
  /// [countryCode] - Country code with '+' prefix (e.g., '+91')
  /// [resend] - Whether this is a resend request
  ///
  /// Returns Future<bool> indicating success/failure
  static Future<bool> verifyPhoneNumber(
    BuildContext context,
    String phoneNumber, {
    String countryCode = '+91',
    bool resend = false,
  }) async {
    if (phoneNumber.isEmpty) {
      ErrorHandler.showError(context, 'Phone number cannot be empty');
      return false;
    }

    if (!PhoneValidationUtil.isValidPhoneNumber(phoneNumber)) {
      ErrorHandler.showError(
        context,
        'Please enter a valid 10-digit phone number',
      );
      return false;
    }

    final fullPhoneNumber = '$countryCode$phoneNumber';

    if (!resend &&
        _verificationId != null &&
        _lastPhoneNumber == fullPhoneNumber &&
        _lastVerificationTime != null) {
      final timeSinceVerification = DateTime.now().difference(
        _lastVerificationTime!,
      );

      if (timeSinceVerification < _verificationSessionTimeout) {
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => OtpScreen(phone: phoneNumber)),
          );
        }
        return true;
      } else {
        clearVerificationSession();
      }
    }

    if (_lastPhoneNumber != fullPhoneNumber) {
      clearVerificationSession();
    }

    try {
      final completer = Completer<bool>();
      bool codeSentCalled = false;
      bool isCanceled = false;
      await _auth.verifyPhoneNumber(
        phoneNumber: '$countryCode $phoneNumber',
        timeout: const Duration(seconds: 120),
        forceResendingToken: resend ? _resendToken : null,

        verificationCompleted: (PhoneAuthCredential credential) async {
          if (isCanceled) {
            return;
          }

          try {
            await _signInWithCredential(context, credential);
            if (!completer.isCompleted) {
              completer.complete(true);
            }
          } catch (e, stackTrace) {
            if (!isCanceled) {
              ErrorHandler.handle(context, e, stackTrace, true);
            }
            if (!completer.isCompleted) {
              completer.complete(false);
            }
          }
        },

        verificationFailed: (FirebaseAuthException e) {
          if (isCanceled) {
            if (!completer.isCompleted) {
              completer.complete(false);
            }
            return;
          }

          final appException = ErrorHandler.convert(e);
          ErrorHandler.showError(context, appException.userMessage);
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        },

        codeSent: (String verificationId, int? resendToken) {
          codeSentCalled = true;
          _verificationId = verificationId;
          _resendToken = resendToken;
          _lastPhoneNumber = fullPhoneNumber;
          _lastVerificationTime = DateTime.now();
          _authenticatedPhone = phoneNumber;
          _authenticatedCountryCode = countryCode;
          GoogleAuth.clearAuthenticatedEmail();

          // Always navigate/show success when OTP was actually sent (e.g. after user
          // returns from reCAPTCHA), even if our timeout already fired (isCanceled).
          if (!resend) {
            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OtpScreen(phone: phoneNumber),
                ),
              );
            }
          } else {
            if (context.mounted) {
              ErrorHandler.showSuccess(context, 'OTP resent successfully');
            }
          }
          if (!completer.isCompleted) {
            completer.complete(true);
          }
        },

        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          if (!codeSentCalled && !completer.isCompleted && !isCanceled) {
            ErrorHandler.showError(
              context,
              'Too many requests. Please wait a minute before trying again.',
            );
            completer.complete(false);
          }
        },
      );

      try {
        // Use 90s timeout so user can complete reCAPTCHA and return; Firebase may call
        // codeSent only after CAPTCHA. 18s was too short and showed error even when OTP was sent.
        final result = await completer.future.timeout(
          const Duration(seconds: 90),
          onTimeout: () {
            isCanceled = true;
            clearVerificationSession();
            if (!completer.isCompleted) {
              completer.complete(false);
            }
            throw TimeoutAppException(
              technicalMessage:
                  'verifyPhoneNumber timed out after 90s - Firebase did not respond',
              code: 'PHONE_VERIFY_TIMEOUT',
            );
          },
        );

        return result;
      } on TimeoutAppException {
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        if (context.mounted) {
          ErrorHandler.showError(
            context,
            'Verification is taking longer than usual. If you received an OTP, try opening the OTP screen again or retry in a minute.',
          );
        }
        return false;
      }
    } on FirebaseAuthException catch (e, stackTrace) {
      ErrorHandler.handle(context, e, stackTrace);
      return false;
    } catch (e, stackTrace) {
      ErrorHandler.handle(context, e, stackTrace);
      return false;
    }
  }

  /// Submits OTP for verification
  ///
  /// [context] - BuildContext for navigation
  /// [otp] - 6-digit OTP code
  ///
  /// Returns Future<bool> indicating success/failure
  static Future<bool> submitOtp(BuildContext context, String otp) async {
    if (otp.isEmpty || otp.length != 6) {
      ErrorHandler.showError(context, 'Please enter a valid 6-digit OTP');
      return false;
    }

    if (_verificationId == null) {
      ErrorHandler.showError(
        context,
        'Verification session expired. Please request a new OTP.',
      );
      return false;
    }

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );

      await _signInWithCredential(context, credential);
      return true;
    } on FirebaseAuthException catch (e, stackTrace) {
      if (e.code == 'invalid-verification-id' || e.code == 'session-expired') {
        _verificationId = null;
        _resendToken = null;
      }

      ErrorHandler.handle(context, e, stackTrace);
      return false;
    } catch (e, stackTrace) {
      ErrorHandler.handle(context, e, stackTrace);
      return false;
    }
  }

  /// Signs in with phone credential and navigates to appropriate screen
  static Future<void> _signInWithCredential(
    BuildContext context,
    PhoneAuthCredential credential,
  ) async {
    try {
      final userCredential = await _auth
          .signInWithCredential(credential)
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              throw TimeoutAppException(
                technicalMessage: 'signInWithCredential timed out',
                code: 'SIGN_IN_TIMEOUT',
              );
            },
          );

      final user = userCredential.user;
      if (user == null) {
        throw AuthException(
          message: 'Authentication failed. Please try again.',
          technicalMessage: 'User is null after sign-in',
          code: 'USER_NULL',
        );
      }

      GoogleAuth.clearAuthenticatedEmail();

      await UserService.ensureUserDocument(user);

      clearVerificationSession();

      if (!context.mounted) return;

      try {
        final globals = Globals.of(context);

        final sessionResult =
            await SessionService.prepareSessionForCurrentUser();

        if (!context.mounted) return;

        if (sessionResult.maxZero) {
          final result = await ReusableDialog.show(
            context,
            'Login disabled',
            'Login is currently disabled. Please try again later.',
            "Go Back",
            onConfirm: () async {
              await SessionService.clearSavedSessionId();
              await _auth.signOut();
            },
            showCancelButton: false,
          );

          if (result && context.mounted) {
            Navigator.pushNamedAndRemoveUntil(
              context,
              LoginScreen.routeName,
              (Route<dynamic> route) => false,
            );
          }
          return;
        }

        if (sessionResult.needsUserConfirmation) {
          final confirmed = await ReusableDialog.show(
            context,
            'Session already active',
            'This account is already active on another device. Do you want to continue on this device and log out the other device?',
            "Login",
            onConfirm: () async {
              // Dialog handles closing itself
            },
            onCancel: () async {
              // Dialog handles closing itself
            },
          );

          if (confirmed != true) {
            await SessionService.clearSavedSessionId();
            await _auth.signOut();
            if (context.mounted) {
              Navigator.pushNamedAndRemoveUntil(
                context,
                LoginScreen.routeName,
                (Route<dynamic> route) => false,
              );
            }
            return;
          }

          await SessionService.confirmSessionReplacementForCurrentUser();
        }

        PermissionSessionManager.resetAllSessions(globals.prefs);
        final hasProfile = await globals.initializeUserData(context, false);

        if (!context.mounted) return;

        if (hasProfile) {
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
      } on FirebaseException catch (e, stackTrace) {
        _log('Firestore/init failure: ${e.code} ${e.message}');
        ErrorHandler.handle(context, e, stackTrace, true);

        if (context.mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            SplashScreen.routeName,
            (Route<dynamic> route) => false,
          );
        }
      } catch (e, stackTrace) {
        ErrorHandler.handle(context, e, stackTrace, true);

        if (context.mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            SplashScreen.routeName,
            (Route<dynamic> route) => false,
          );
        }
      }
    } on TimeoutAppException {
      rethrow;
    } on AuthException {
      rethrow;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  /// Logs out the current user
  static Future<void> logoutOnly() async {
    _verificationId = null;
    _resendToken = null;
    PermissionSessionManager.resetSafetyTipsSession();
  }

  /// Clears all stored authentication data
  static void clearVerificationSession() {
    _verificationId = null;
    _resendToken = null;
    _lastPhoneNumber = null;
    _lastVerificationTime = null;
  }

  /// Checks if there's an active verification session
  static bool hasActiveSession(String phoneNumber, String countryCode) {
    final fullPhoneNumber = '$countryCode$phoneNumber';

    if (_verificationId == null ||
        _lastPhoneNumber != fullPhoneNumber ||
        _lastVerificationTime == null) {
      return false;
    }

    final timeSinceVerification = DateTime.now().difference(
      _lastVerificationTime!,
    );
    return timeSinceVerification < _verificationSessionTimeout;
  }

  /// Debug logging - only in debug mode
  static void _log(String message) {
    if (kDebugMode) {
      debugPrint('[PhoneAuth] $message');
    }
  }
}
