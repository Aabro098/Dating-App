/// Utility class for managing request state and preventing duplicate requests
class RequestStateUtil {
  RequestStateUtil._(); // Private constructor

  /// Checks if a new request should be allowed based on current state
  /// 
  /// [isLoading] - Current loading state
  /// [isRequestActive] - Whether a request is currently active
  /// [currentProcessingValue] - Value currently being processed (e.g., phone number)
  /// [newValue] - New value to process
  /// 
  /// Returns RequestStateResult with action to take
  static RequestStateResult checkRequestState({
    required bool isLoading,
    required bool isRequestActive,
    String? currentProcessingValue,
    String? newValue,
  }) {
    if (isLoading) {
      return RequestStateResult.blocked('Already processing, please wait');
    }

    if (isRequestActive && 
        currentProcessingValue != null && 
        newValue != null &&
        currentProcessingValue != newValue) {
      return RequestStateResult.cancelAndAllowNew(
        'Value changed from "$currentProcessingValue" to "$newValue"',
      );
    }

    if (isRequestActive) {
      return RequestStateResult.blocked('Previous request still processing');
    }

    return RequestStateResult.allowed();
  }

  /// Resets all request state variables
  /// 
  /// [isLoading] - Loading state setter
  /// [isRequestActive] - Request active state setter
  /// [currentProcessingValue] - Current processing value setter
  static void resetRequestState({
    required void Function(bool) setLoading,
    required void Function(bool) setRequestActive,
    required void Function(String?) setCurrentProcessingValue,
  }) {
    setLoading(false);
    setRequestActive(false);
    setCurrentProcessingValue(null);
  }

  /// Sets request as active
  /// 
  /// [isLoading] - Loading state setter
  /// [isRequestActive] - Request active state setter
  /// [currentProcessingValue] - Current processing value setter
  /// [value] - Value being processed
  static void setRequestActive({
    required void Function(bool) setLoading,
    required void Function(bool) setRequestActive,
    required void Function(String?) setCurrentProcessingValue,
    required String value,
  }) {
    setLoading(true);
    setRequestActive(true);
    setCurrentProcessingValue(value);
  }
}

class RequestStateResult {
  final bool isAllowed;
  final bool shouldCancelPrevious;
  final String? message;

  const RequestStateResult._({
    required this.isAllowed,
    required this.shouldCancelPrevious,
    this.message,
  });

  factory RequestStateResult.allowed() {
    return const RequestStateResult._(
      isAllowed: true,
      shouldCancelPrevious: false,
    );
  }


  factory RequestStateResult.blocked(String message) {
    return RequestStateResult._(
      isAllowed: false,
      shouldCancelPrevious: false,
      message: message,
    );
  }

  factory RequestStateResult.cancelAndAllowNew(String reason) {
    return RequestStateResult._(
      isAllowed: true,
      shouldCancelPrevious: true,
      message: reason,
    );
  }
}
