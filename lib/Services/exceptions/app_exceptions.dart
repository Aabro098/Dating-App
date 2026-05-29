/// Centralized Exception Model for Viora Dating App
/// 
/// This file contains all custom exceptions used throughout the app.
/// Each exception type has a user-friendly message and an error code for logging.
/// 
/// Usage:
/// ```dart
/// throw NetworkException();
/// throw TimeoutAppException();
/// throw ServerException(code: 'firestore-unavailable');
/// ```

/// Base class for all app exceptions
abstract class AppException implements Exception {
  final String userMessage;
  final String? technicalMessage;
  final String? code;
  final StackTrace? stackTrace;
  final DateTime timestamp;

  AppException({
    required this.userMessage,
    this.technicalMessage,
    this.code,
    this.stackTrace,
  }) : timestamp = DateTime.now();

  @override
  String toString() => userMessage;

  /// Returns a map for logging purposes
  Map<String, dynamic> toLogMap() => {
    'type': runtimeType.toString(),
    'code': code,
    'userMessage': userMessage,
    'technicalMessage': technicalMessage,
    'timestamp': timestamp.toIso8601String(),
    'stackTrace': stackTrace?.toString(),
  };
}

/// Network/Internet connection errors
/// 
/// Thrown when:
/// - No internet connection
/// - DNS resolution failed
/// - Socket connection failed
class NetworkException extends AppException {
  NetworkException({
    String? technicalMessage,
    String? code,
    StackTrace? stackTrace,
  }) : super(
    userMessage: 'No internet connection. Please check your network and try again.',
    technicalMessage: technicalMessage,
    code: code ?? 'NETWORK_ERROR',
    stackTrace: stackTrace,
  );
}

/// Timeout errors
/// 
/// Thrown when:
/// - Firebase operation times out
/// - API call takes too long
/// - Server doesn't respond within expected time
class TimeoutAppException extends AppException {
  TimeoutAppException({
    String? technicalMessage,
    String? code,
    StackTrace? stackTrace,
  }) : super(
    userMessage: 'Server is taking too long. Please try again later.',
    technicalMessage: technicalMessage,
    code: code ?? 'TIMEOUT_ERROR',
    stackTrace: stackTrace,
  );
}

/// Authentication/Authorization errors
/// 
/// Thrown when:
/// - Session expired
/// - Token invalid
/// - User not authenticated
/// - Permission denied
class UnauthorizedException extends AppException {
  UnauthorizedException({
    String? technicalMessage,
    String? code,
    StackTrace? stackTrace,
  }) : super(
    userMessage: 'Your session has expired. Please login again.',
    technicalMessage: technicalMessage,
    code: code ?? 'UNAUTHORIZED',
    stackTrace: stackTrace,
  );
}

/// Server-side errors
/// 
/// Thrown when:
/// - Firebase server error (5xx)
/// - Firestore unavailable
/// - Cloud Functions error
/// - Database operation failed
class ServerException extends AppException {
  ServerException({
    String? technicalMessage,
    String? code,
    StackTrace? stackTrace,
  }) : super(
    userMessage: 'Something went wrong on our end. Please try again.',
    technicalMessage: technicalMessage,
    code: code ?? 'SERVER_ERROR',
    stackTrace: stackTrace,
  );
}

/// Unknown/Unexpected errors
/// 
/// Thrown when:
/// - Unhandled exception type
/// - Unexpected error occurred
/// - Generic fallback
class UnknownAppException extends AppException {
  UnknownAppException({
    String? technicalMessage,
    String? code,
    StackTrace? stackTrace,
  }) : super(
    userMessage: 'An unexpected error occurred. Please restart the app.',
    technicalMessage: technicalMessage,
    code: code ?? 'UNKNOWN_ERROR',
    stackTrace: stackTrace,
  );
}

/// Validation errors
/// 
/// Thrown when:
/// - Invalid input data
/// - Form validation failed
/// - Data format incorrect
class ValidationException extends AppException {
  ValidationException({
    required String message,
    String? technicalMessage,
    String? code,
    StackTrace? stackTrace,
  }) : super(
    userMessage: message,
    technicalMessage: technicalMessage,
    code: code ?? 'VALIDATION_ERROR',
    stackTrace: stackTrace,
  );
}

/// Firebase Auth specific errors
/// 
/// Thrown when:
/// - Phone number invalid
/// - OTP incorrect
/// - Verification failed
/// - Account disabled
class AuthException extends AppException {
  AuthException({
    required String message,
    String? technicalMessage,
    String? code,
    StackTrace? stackTrace,
  }) : super(
    userMessage: message,
    technicalMessage: technicalMessage,
    code: code ?? 'AUTH_ERROR',
    stackTrace: stackTrace,
  );
}

/// Rate limiting errors
/// 
/// Thrown when:
/// - Too many requests
/// - Quota exceeded
/// - Firebase rate limit hit
class RateLimitException extends AppException {
  RateLimitException({
    String? technicalMessage,
    String? code,
    StackTrace? stackTrace,
  }) : super(
    userMessage: 'Too many attempts. Please wait a few minutes and try again.',
    technicalMessage: technicalMessage,
    code: code ?? 'RATE_LIMIT',
    stackTrace: stackTrace,
  );
}

/// Permission denied errors
/// 
/// Thrown when:
/// - Firestore security rules block access
/// - User doesn't have permission
/// - Resource access denied
class PermissionDeniedException extends AppException {
  PermissionDeniedException({
    String? technicalMessage,
    String? code,
    StackTrace? stackTrace,
  }) : super(
    userMessage: 'You don\'t have permission to perform this action.',
    technicalMessage: technicalMessage,
    code: code ?? 'PERMISSION_DENIED',
    stackTrace: stackTrace,
  );
}

/// Resource not found errors
/// 
/// Thrown when:
/// - Document doesn't exist
/// - User not found
/// - Data not found
class NotFoundException extends AppException {
  NotFoundException({
    String message = 'The requested information could not be found.',
    String? technicalMessage,
    String? code,
    StackTrace? stackTrace,
  }) : super(
    userMessage: message,
    technicalMessage: technicalMessage,
    code: code ?? 'NOT_FOUND',
    stackTrace: stackTrace,
  );
}

/// Storage/Upload errors
/// 
/// Thrown when:
/// - File upload failed
/// - Storage quota exceeded
/// - Invalid file type
class StorageException extends AppException {
  StorageException({
    required String message,
    String? technicalMessage,
    String? code,
    StackTrace? stackTrace,
  }) : super(
    userMessage: message,
    technicalMessage: technicalMessage,
    code: code ?? 'STORAGE_ERROR',
    stackTrace: stackTrace,
  );
}

/// Payment/Purchase errors
/// 
/// Thrown when:
/// - Payment failed
/// - Subscription error
/// - RevenueCat error
class PaymentException extends AppException {
  PaymentException({
    required String message,
    String? technicalMessage,
    String? code,
    StackTrace? stackTrace,
  }) : super(
    userMessage: message,
    technicalMessage: technicalMessage,
    code: code ?? 'PAYMENT_ERROR',
    stackTrace: stackTrace,
  );
}
