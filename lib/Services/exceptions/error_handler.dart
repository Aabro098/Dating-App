import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:viora/Services/network_service.dart';

import 'app_exceptions.dart';

/// Centralized Error Handler for Viora Dating App
/// 
/// Responsibilities:
/// 1. Convert platform exceptions to AppExceptions
/// 2. Log errors (only in debug mode or to analytics)
/// 3. Show user-friendly notifications
/// 4. Map Firebase error codes to user messages
/// 
/// Usage:
/// ```dart
/// try {
///   await someOperation();
/// } catch (e, stackTrace) {
///   ErrorHandler.handle(context, e, stackTrace);
/// }
/// ```
class ErrorHandler {
  // Singleton instance
  static final ErrorHandler _instance = ErrorHandler._internal();
  factory ErrorHandler() => _instance;
  ErrorHandler._internal();

  // Toast debouncing
  static int _lastToastTime = 0;
  static const _toastDebounceMs = 2000; // 2 seconds between toasts
  static OverlaySupportEntry? _activeOverlay;

  /// Main handler - converts any exception to AppException and shows notification
  /// 
  /// [context] - BuildContext for showing notifications
  /// [error] - The caught exception
  /// [stackTrace] - Stack trace for logging
  /// [silent] - If true, logs but doesn't show notification
  /// 
  /// Returns the converted AppException for further handling if needed
  static AppException handle(
    BuildContext? context,
    dynamic error, [
    StackTrace? stackTrace,
    bool silent = false,
  ]) {
    final appException = convert(error, stackTrace);
    
    // Log the error (never in production builds)
    _logError(appException);
    
    // Show notification if context is available and not silent
    if (!silent && context != null && context.mounted) {
      showError(context, appException.userMessage);
    }
    
    return appException;
  }

  /// Converts any exception to the appropriate AppException type
  /// 
  /// This is the core mapping function that takes raw exceptions
  /// and converts them to our custom exception types
  static AppException convert(dynamic error, [StackTrace? stackTrace]) {
    // Already an AppException - return as is
    if (error is AppException) {
      return error;
    }

    // Firebase Auth exceptions
    if (error is FirebaseAuthException) {
      return _handleFirebaseAuthException(error, stackTrace);
    }

    // Firebase/Firestore exceptions
    if (error is FirebaseException) {
      return _handleFirebaseException(error, stackTrace);
    }

    // Timeout exceptions
    if (error is TimeoutException) {
      return TimeoutAppException(
        technicalMessage: error.toString(),
        stackTrace: stackTrace,
      );
    }

    // Socket/Network exceptions
    if (error is SocketException) {
      return NetworkException(
        technicalMessage: error.toString(),
        code: 'SOCKET_ERROR',
        stackTrace: stackTrace,
      );
    }

    // HTTP client exceptions (connectivity issues)
    if (error is HttpException) {
      return NetworkException(
        technicalMessage: error.toString(),
        code: 'HTTP_ERROR',
        stackTrace: stackTrace,
      );
    }

    // Platform exceptions (e.g., from native code, including RevenueCat)
    if (error is PlatformException) {
      final rc = _handleRevenueCatException(error, stackTrace);
      if (rc != null) return rc;
      return _handlePlatformException(error, stackTrace);
    }

    // Format exceptions (parsing errors)
    if (error is FormatException) {
      return ServerException(
        technicalMessage: 'Data format error: ${error.message}',
        code: 'FORMAT_ERROR',
        stackTrace: stackTrace,
      );
    }

    // Type errors (null safety, casting)
    if (error is TypeError) {
      return UnknownAppException(
        technicalMessage: 'Type error: ${error.toString()}',
        code: 'TYPE_ERROR',
        stackTrace: stackTrace,
      );
    }

    // State errors
    if (error is StateError) {
      return UnknownAppException(
        technicalMessage: 'State error: ${error.message}',
        code: 'STATE_ERROR',
        stackTrace: stackTrace,
      );
    }

    // String error messages
    if (error is String) {
      return UnknownAppException(
        technicalMessage: error,
        code: 'STRING_ERROR',
        stackTrace: stackTrace,
      );
    }

    // Unknown/fallback
    return UnknownAppException(
      technicalMessage: error?.toString() ?? 'Unknown error',
      code: 'UNKNOWN',
      stackTrace: stackTrace,
    );
  }

  /// Handle Firebase Auth specific exceptions
  static AppException _handleFirebaseAuthException(
    FirebaseAuthException e,
    StackTrace? stackTrace,
  ) {
    final technicalMsg = '${e.code}: ${e.message}';
    
    switch (e.code) {
      // Phone number errors
      case 'invalid-phone-number':
        return AuthException(
          message: 'Invalid phone number format. Please check and try again.',
          technicalMessage: technicalMsg,
          code: e.code,
          stackTrace: stackTrace,
        );
      
      // OTP errors
      case 'invalid-verification-code':
        return AuthException(
          message: 'Invalid OTP. Please check the code and try again.',
          technicalMessage: technicalMsg,
          code: e.code,
          stackTrace: stackTrace,
        );
      
      case 'invalid-verification-id':
      case 'session-expired':
        return AuthException(
          message: 'Verification session expired. Please request a new OTP.',
          technicalMessage: technicalMsg,
          code: e.code,
          stackTrace: stackTrace,
        );
      
      // Rate limiting
      case 'quota-exceeded':
      case 'too-many-requests':
        return RateLimitException(
          technicalMessage: technicalMsg,
          code: e.code,
          stackTrace: stackTrace,
        );
      
      // Network errors
      case 'network-request-failed':
        return NetworkException(
          technicalMessage: technicalMsg,
          code: e.code,
          stackTrace: stackTrace,
        );
      
      // Account errors
      case 'user-disabled':
        return AuthException(
          message: 'This account has been disabled. Please contact support.',
          technicalMessage: technicalMsg,
          code: e.code,
          stackTrace: stackTrace,
        );
      
      case 'user-not-found':
        return AuthException(
          message: 'Account not found. Please sign up first.',
          technicalMessage: technicalMsg,
          code: e.code,
          stackTrace: stackTrace,
        );
      
      case 'operation-not-allowed':
        return AuthException(
          message: 'This sign-in method is not enabled. Please contact support.',
          technicalMessage: technicalMsg,
          code: e.code,
          stackTrace: stackTrace,
        );
      
      case 'credential-already-in-use':
        return AuthException(
          message: 'This credential is already linked to another account.',
          technicalMessage: technicalMsg,
          code: e.code,
          stackTrace: stackTrace,
        );
      
      case 'requires-recent-login':
        return UnauthorizedException(
          technicalMessage: technicalMsg,
          code: e.code,
          stackTrace: stackTrace,
        );
      
      // Generic auth error
      default:
        return AuthException(
          message: 'Authentication failed. Please try again.',
          technicalMessage: technicalMsg,
          code: e.code,
          stackTrace: stackTrace,
        );
    }
  }

  /// Handle Firebase/Firestore exceptions
  static AppException _handleFirebaseException(
    FirebaseException e,
    StackTrace? stackTrace,
  ) {
    final technicalMsg = '${e.plugin}/${e.code}: ${e.message}';
    
    switch (e.code) {
      // Network/Connectivity
      case 'unavailable':
        return NetworkException(
          technicalMessage: technicalMsg,
          code: 'FIRESTORE_UNAVAILABLE',
          stackTrace: stackTrace,
        );
      
      // Permission errors
      case 'permission-denied':
        return PermissionDeniedException(
          technicalMessage: technicalMsg,
          code: 'FIRESTORE_PERMISSION_DENIED',
          stackTrace: stackTrace,
        );
      
      // Not found
      case 'not-found':
        return NotFoundException(
          technicalMessage: technicalMsg,
          code: 'FIRESTORE_NOT_FOUND',
          stackTrace: stackTrace,
        );
      
      // Already exists
      case 'already-exists':
        return ServerException(
          technicalMessage: technicalMsg,
          code: 'FIRESTORE_ALREADY_EXISTS',
          stackTrace: stackTrace,
        );
      
      // Resource exhausted (rate limiting)
      case 'resource-exhausted':
        return RateLimitException(
          technicalMessage: technicalMsg,
          code: 'FIRESTORE_RATE_LIMIT',
          stackTrace: stackTrace,
        );
      
      // Cancelled
      case 'cancelled':
        return UnknownAppException(
          technicalMessage: technicalMsg,
          code: 'FIRESTORE_CANCELLED',
          stackTrace: stackTrace,
        );
      
      // Deadline exceeded (timeout)
      case 'deadline-exceeded':
        return TimeoutAppException(
          technicalMessage: technicalMsg,
          code: 'FIRESTORE_TIMEOUT',
          stackTrace: stackTrace,
        );
      
      // Unauthenticated
      case 'unauthenticated':
        return UnauthorizedException(
          technicalMessage: technicalMsg,
          code: 'FIRESTORE_UNAUTHENTICATED',
          stackTrace: stackTrace,
        );
      
      // Invalid argument
      case 'invalid-argument':
        return ValidationException(
          message: 'Invalid data provided. Please check your input.',
          technicalMessage: technicalMsg,
          code: 'FIRESTORE_INVALID_ARGUMENT',
          stackTrace: stackTrace,
        );
      
      // Data loss
      case 'data-loss':
        return ServerException(
          technicalMessage: technicalMsg,
          code: 'FIRESTORE_DATA_LOSS',
          stackTrace: stackTrace,
        );
      
      // Internal error
      case 'internal':
        return ServerException(
          technicalMessage: technicalMsg,
          code: 'FIRESTORE_INTERNAL',
          stackTrace: stackTrace,
        );
      
      // Storage errors
      case 'object-not-found':
        return NotFoundException(
          message: 'The file could not be found.',
          technicalMessage: technicalMsg,
          code: 'STORAGE_NOT_FOUND',
          stackTrace: stackTrace,
        );
      
      case 'unauthorized':
        return UnauthorizedException(
          technicalMessage: technicalMsg,
          code: 'STORAGE_UNAUTHORIZED',
          stackTrace: stackTrace,
        );
      
      case 'retry-limit-exceeded':
        return NetworkException(
          technicalMessage: technicalMsg,
          code: 'STORAGE_RETRY_LIMIT',
          stackTrace: stackTrace,
        );
      
      case 'invalid-checksum':
        return StorageException(
          message: 'File upload failed. Please try again.',
          technicalMessage: technicalMsg,
          code: 'STORAGE_CHECKSUM',
          stackTrace: stackTrace,
        );
      
      case 'canceled':
        return StorageException(
          message: 'Upload was cancelled.',
          technicalMessage: technicalMsg,
          code: 'STORAGE_CANCELLED',
          stackTrace: stackTrace,
        );
      
      // Default server error
      default:
        return ServerException(
          technicalMessage: technicalMsg,
          code: 'FIREBASE_${e.code.toUpperCase()}',
          stackTrace: stackTrace,
        );
    }
  }

  /// Map RevenueCat purchase PlatformException to AppException (user-friendly, no raw messages).
  static AppException? _handleRevenueCatException(
    PlatformException e,
    StackTrace? stackTrace,
  ) {
    try {
      final code = PurchasesErrorHelper.getErrorCode(e);
      final technicalMsg = '${e.code}: ${e.message}';
      switch (code) {
        case PurchasesErrorCode.purchaseCancelledError:
          return PaymentException(
            message: 'Purchase was cancelled.',
            technicalMessage: technicalMsg,
            code: 'PURCHASE_CANCELLED',
            stackTrace: stackTrace,
          );
        case PurchasesErrorCode.networkError:
          return NetworkException(
            technicalMessage: technicalMsg,
            code: 'RC_NETWORK',
            stackTrace: stackTrace,
          );
        case PurchasesErrorCode.productNotAvailableForPurchaseError:
          return PaymentException(
            message: 'This plan is not available right now. Please try again later.',
            technicalMessage: technicalMsg,
            code: 'PRODUCT_UNAVAILABLE',
            stackTrace: stackTrace,
          );
        case PurchasesErrorCode.purchaseNotAllowedError:
          return PaymentException(
            message: 'Purchases are not allowed on this device.',
            technicalMessage: technicalMsg,
            code: 'PURCHASE_NOT_ALLOWED',
            stackTrace: stackTrace,
          );
        case PurchasesErrorCode.paymentPendingError:
          return PaymentException(
            message: 'Your payment is pending. We\'ll update once it\'s confirmed.',
            technicalMessage: technicalMsg,
            code: 'PAYMENT_PENDING',
            stackTrace: stackTrace,
          );
        case PurchasesErrorCode.purchaseInvalidError:
          return PaymentException(
            message: 'We couldn\'t verify the purchase. Please try again.',
            technicalMessage: technicalMsg,
            code: 'PURCHASE_INVALID',
            stackTrace: stackTrace,
          );
        case PurchasesErrorCode.configurationError:
          return ServerException(
            technicalMessage: technicalMsg,
            code: 'RC_CONFIG',
            stackTrace: stackTrace,
          );
        case PurchasesErrorCode.storeProblemError:
          return ServerException(
            technicalMessage: technicalMsg,
            code: 'STORE_PROBLEM',
            stackTrace: stackTrace,
          );
        case PurchasesErrorCode.unknownError:
        default:
          return PaymentException(
            message: 'Purchase failed. Please try again.',
            technicalMessage: technicalMsg,
            code: 'RC_UNKNOWN',
            stackTrace: stackTrace,
          );
      }
    } catch (_) {
      return null;
    }
  }

  /// Handle Platform exceptions
  static AppException _handlePlatformException(
    PlatformException e,
    StackTrace? stackTrace,
  ) {
    final technicalMsg = '${e.code}: ${e.message}';
    
    switch (e.code) {
      case 'network_error':
      case 'NETWORK_ERROR':
        return NetworkException(
          technicalMessage: technicalMsg,
          code: 'PLATFORM_NETWORK_ERROR',
          stackTrace: stackTrace,
        );
      
      case 'sign_in_failed':
        return AuthException(
          message: 'Sign in failed. Please try again.',
          technicalMessage: technicalMsg,
          code: 'PLATFORM_SIGN_IN_FAILED',
          stackTrace: stackTrace,
        );
      
      case 'sign_in_canceled':
        return AuthException(
          message: 'Sign in was cancelled.',
          technicalMessage: technicalMsg,
          code: 'PLATFORM_SIGN_IN_CANCELED',
          stackTrace: stackTrace,
        );
      
      default:
        return UnknownAppException(
          technicalMessage: technicalMsg,
          code: 'PLATFORM_${e.code.toUpperCase()}',
          stackTrace: stackTrace,
        );
    }
  }

  /// Log error - only in debug mode, never expose in production
  static void _logError(AppException exception) {
    // Only log in debug mode
    if (kDebugMode) {
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('❌ ERROR: ${exception.runtimeType}');
      debugPrint('   Code: ${exception.code}');
      debugPrint('   User Message: ${exception.userMessage}');
      debugPrint('   Technical: ${exception.technicalMessage}');
      debugPrint('   Time: ${exception.timestamp.toIso8601String()}');
      if (exception.stackTrace != null) {
        debugPrint('   Stack Trace:\n${exception.stackTrace}');
      }
      debugPrint('═══════════════════════════════════════════════════════════');
    }
    
    // TODO: In production, send to analytics/crashlytics
    // if (kReleaseMode) {
    //   FirebaseCrashlytics.instance.recordError(
    //     exception,
    //     exception.stackTrace,
    //     reason: exception.code,
    //   );
    // }
  }

  /// Show error notification to user
  static void showError(BuildContext context, String message) {
    // Debounce toast notifications
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastToastTime < _toastDebounceMs) {
      return;
    }
    _lastToastTime = now;
    
    // Dismiss previous notification
    _activeOverlay?.dismiss();
    
    // Check keyboard visibility
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    
    _activeOverlay = showOverlayNotification(
      (context) => SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.red.shade600,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => OverlaySupportEntry.of(context)?.dismiss(),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      duration: const Duration(seconds: 4),
      position: keyboardVisible ? NotificationPosition.top : NotificationPosition.bottom,
    );
  }

  /// Show success notification to user
  static void showSuccess(BuildContext context, String message) {
    // Debounce toast notifications
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastToastTime < _toastDebounceMs) {
      return;
    }
    _lastToastTime = now;
    
    // Dismiss previous notification
    _activeOverlay?.dismiss();
    
    _activeOverlay = showOverlayNotification(
      (context) => SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.green.shade600,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      duration: const Duration(seconds: 3),
      position: NotificationPosition.bottom,
    );
  }

  /// Show warning notification to user
  static void showWarning(BuildContext context, String message) {
    // Debounce toast notifications
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastToastTime < _toastDebounceMs) {
      return;
    }
    _lastToastTime = now;
    
    // Dismiss previous notification
    _activeOverlay?.dismiss();
    
    _activeOverlay = showOverlayNotification(
      (context) => SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.orange.shade600,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      duration: const Duration(seconds: 4),
      position: NotificationPosition.top,
    );
  }

  /// Dismiss any active notification
  static void dismissNotification() {
    _activeOverlay?.dismiss();
    _activeOverlay = null;
  }

  // --- NETWORK CONNECTIVITY HELPERS ---

  /// Check if device has internet connection before attempting an operation
  /// Returns true if connected, shows error and returns false if not
  static Future<bool> checkNetworkBeforeOperation(BuildContext? context) async {
    final networkService = NetworkService();
    
    if (!networkService.isConnected) {
      if (context != null && context.mounted) {
        showError(context, 'No internet connection. Please check your network and try again.');
      }
      return false;
    }

    // Verify actual internet access (not just network availability)
    final hasInternet = await networkService.hasInternetAccess();
    if (!hasInternet) {
      if (context != null && context.mounted) {
        showError(context, 'Cannot reach server. Please check your internet connection.');
      }
      return false;
    }

    return true;
  }

  /// Check network quality and warn user if slow
  /// Returns true to proceed, false to cancel
  static Future<bool> checkNetworkQuality(BuildContext? context, {bool showWarningOnly = true}) async {
    final networkService = NetworkService();
    final quality = await networkService.getNetworkQuality();

    if (quality == NetworkQuality.offline) {
      if (context != null && context.mounted) {
        showError(context, 'No internet connection. Please check your network and try again.');
      }
      return false;
    }

    if (quality == NetworkQuality.poor && context != null && context.mounted) {
      if (showWarningOnly) {
        showWarning(context, 'Slow connection detected. This may take longer than usual.');
        return true;
      } else {
        // Show dialog asking user to proceed
        return await _showSlowConnectionDialog(context);
      }
    }

    return true;
  }

  /// Show dialog for slow connection
  static Future<bool> _showSlowConnectionDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slow Connection'),
        content: const Text(
          'Your internet connection is slow. Operations may take longer than usual. Do you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Extension for easier error handling in async operations
extension ErrorHandlerExtension on Future {
  /// Wrap any Future with centralized error handling
  /// 
  /// Usage:
  /// ```dart
  /// await someAsyncOperation().handleError(context);
  /// ```
  Future<T?> handleError<T>(BuildContext? context, [bool silent = false]) async {
    try {
      return await this as T;
    } catch (e, stackTrace) {
      ErrorHandler.handle(context, e, stackTrace, silent);
      return null;
    }
  }
}
