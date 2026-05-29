/// Centralized Exception Handling for Viora Dating App
/// 
/// This barrel file exports all exception-related classes and utilities.
/// 
/// Usage:
/// ```dart
/// import 'package:viora/Services/exceptions/exceptions.dart';
/// 
/// // Throwing exceptions
/// throw NetworkException();
/// throw TimeoutAppException();
/// 
/// // Handling errors
/// ErrorHandler.handle(context, error, stackTrace);
/// 
/// // Showing notifications
/// ErrorHandler.showError(context, 'Something went wrong');
/// ```

export 'app_exceptions.dart';
export 'error_handler.dart';
