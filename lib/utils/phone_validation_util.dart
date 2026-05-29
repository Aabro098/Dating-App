/// Utility class for phone number validation and formatting
class PhoneValidationUtil {
  PhoneValidationUtil._(); // Private constructor

  /// Validates if phone number is a valid 10-digit number
  /// 
  /// [phoneNumber] - Phone number to validate (without country code)
  /// Returns true if valid, false otherwise
  static bool isValidPhoneNumber(String phoneNumber) {
    final cleaned = phoneNumber.trim().replaceAll(RegExp(r'\s+'), '');
    return RegExp(r'^\d{10}$').hasMatch(cleaned);
  }

  /// Validates phone number and returns error message if invalid
  /// 
  /// [phoneNumber] - Phone number to validate
  /// Returns null if valid, error message if invalid
  static String? validatePhoneNumberWithMessage(String phoneNumber) {
    final trimmed = phoneNumber.trim();
    
    if (trimmed.isEmpty) {
      return 'Please enter a phone number';
    }
    
    if (!isValidPhoneNumber(trimmed)) {
      return 'Please enter a valid 10-digit phone number';
    }
    
    return null;
  }

  /// Formats phone number by removing non-digit characters
  /// 
  /// [phoneNumber] - Phone number to format
  /// Returns formatted phone number (digits only)
  static String formatPhoneNumber(String phoneNumber) {
    return phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Extracts last 10 digits from a phone number (handles country codes)
  /// 
  /// [phoneNumber] - Phone number that may include country code
  /// Returns last 10 digits
  static String extractLast10Digits(String phoneNumber) {
    final digitsOnly = formatPhoneNumber(phoneNumber);
    if (digitsOnly.length > 10) {
      return digitsOnly.substring(digitsOnly.length - 10);
    }
    return digitsOnly;
  }

  /// Builds full phone number with country code
  /// 
  /// [phoneNumber] - Phone number without country code
  /// [countryCode] - Country code (e.g., '+91')
  /// Returns full phone number
  static String buildFullPhoneNumber(String phoneNumber, String countryCode) {
    return '$countryCode$phoneNumber';
  }
}
