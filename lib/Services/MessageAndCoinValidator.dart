// ============================================================================
// FILE: logic/message_validator.dart
// ============================================================================
// Business Logic: Message validation and spam detection
// Pure functions with no dependencies on Flutter/Firebase
import 'package:viora/models/UserDetails.dart';

/// Result of message validation
class MessageValidationResult {
  final bool isValid;
  final String? reason;

  MessageValidationResult({required this.isValid, this.reason});

  MessageValidationResult.valid() : this(isValid: true);

  MessageValidationResult.invalid(String reason)
    : this(isValid: false, reason: reason);
}

/// Business Logic: Message validation
///
/// This class contains pure business logic for validating messages.
/// It has no dependencies on Firebase, Flutter, or UI components.
/// All methods are static and can be easily unit tested.
class MessageValidator {
  // Prohibited keywords that indicate contact sharing attempts
  static const List<String> _prohibitedKeywords = [
    'instagram',
    'insta',
    'phone',
    'call',
    'facebook',
    'contact',
    'whatsapp',
    'app',
    'fb',
    'snapchat',
    'whasapp',
    'hangouts',
    'no.',
    'telegram',
    'mobile',
    'number',
    '+91',
    'gmail',
    '@'
        '@gmail.com'
        '.com',
  ];

  /// Validates a message for spam and prohibited content
  ///
  /// Business Rules:
  /// - Cannot contain social media platform names
  /// - Cannot contain phone-related keywords
  /// - Cannot contain 10-digit phone numbers
  ///
  /// Returns: MessageValidationResult with validation status
  static MessageValidationResult validateMessage(String message) {
    if (message.isEmpty) {
      return MessageValidationResult.invalid('Message is empty');
    }

    final lowerCaseMessage = message.toLowerCase();

    // Check for prohibited keywords
    for (final keyword in _prohibitedKeywords) {
      if (lowerCaseMessage.contains(keyword)) {
        return MessageValidationResult.invalid(
          'Message contains prohibited keyword: $keyword',
        );
      }
    }

    // Check for 10-digit phone numbers
    if (_containsPhoneNumber(message)) {
      return MessageValidationResult.invalid('Message contains phone number');
    }

    return MessageValidationResult.valid();
  }

  /// Checks if message contains a 10-digit phone number
  ///
  /// Business Logic: Extracts only digits and checks length
  static bool _containsPhoneNumber(String message) {
    final digitsOnly = message.replaceAll(RegExp(r'[^0-9]'), '');
    return digitsOnly.length == 10;
  }

  /// Checks if message is valid for sending
  ///
  /// Quick validation for non-empty trimmed messages
  static bool isMessageValid(String message) {
    return message.trim().isNotEmpty;
  }
}

// ============================================================================
// FILE: logic/coin_validator.dart
// ============================================================================
// Business Logic: Coin and subscription validation
// Determines if users have necessary coins/subscriptions for actions

/// Business Logic: Coin and subscription validation
///
/// This class encapsulates business rules around:
/// - Coin requirements for male users
/// - Subscription benefits
/// - Image sending permissions
class CoinValidator {
  /// Checks if user can send images
  ///
  /// Business Rules:
  /// - Female users: Always allowed
  /// - Male users: Firestore-backed premium/elite (strict owner) + coins > 0
  ///
  /// [firestoreAllowsPremiumImages] comes from [SubscriptionService.canSendImagesForUser]
  /// — do not use RevenueCat [CustomerInfo] here (cross-account leakage on shared devices).
  static bool canSendImage(
    UserDetails userDetails,
    bool firestoreAllowsPremiumImages,
  ) {
    if (userDetails.gender == "Female") {
      return true;
    }

    final hasCoins = (userDetails.coins ?? 0) > 0;
    return firestoreAllowsPremiumImages && hasCoins;
  }

  /// Checks if user has sufficient coins
  static bool hasCoins(UserDetails userDetails) {
    return (userDetails.coins ?? 0) > 0;
  }

  /// Calculates coins required for action
  ///
  /// Business Rule: Male users spend 1 coin per message
  static int getMessageCost(String gender) {
    return gender == "Male" ? 1 : 0;
  }

  /// Validates if user can perform coin-based action
  static bool canPerformAction(UserDetails userDetails, int requiredCoins) {
    if (userDetails.gender == "Female") {
      return true; // Free for females
    }

    return (userDetails.coins ?? 0) >= requiredCoins;
  }
}

// ============================================================================
// FILE: logic/chat_room_logic.dart
// ============================================================================
// Business Logic: Chat room ID generation and user sorting
// Pure functions for chat room operations

/// Business Logic: Chat room operations
///
/// Contains business rules for:
/// - Generating consistent chat room IDs
/// - Sorting users alphabetically
/// - Handling edge cases in room creation
class ChatRoomLogic {
  /// Generates a consistent chat room ID for two users
  ///
  /// Business Rule: Chat room ID must be the same regardless of
  /// which user initiates the conversation. This is achieved by
  /// alphabetically sorting user IDs.
  static String generateRoomId(String userId1, String userId2) {
    final char1 = userId1.codeUnitAt(0);
    final char2 = userId2.codeUnitAt(0);

    // Handle equal first characters
    if (char1 == char2) {
      return _handleEqualFirstChar(userId1, userId2);
    }

    // Sort by first character
    return char1 < char2 ? "${userId1}_$userId2" : "${userId2}_$userId1";
  }

  /// Handles case where both user IDs start with same character
  static String _handleEqualFirstChar(String userId1, String userId2) {
    final comparison = userId1.compareTo(userId2);

    if (comparison > 0) {
      return "${userId2}_$userId1";
    } else if (comparison < 0) {
      return "${userId1}_$userId2";
    }

    return ''; // Same user (edge case)
  }

  /// Returns sorted array of user IDs for consistent ordering
  static List<String> getSortedUserIds(String userId1, String userId2) {
    final char1 = userId1.codeUnitAt(0);
    final char2 = userId2.codeUnitAt(0);

    return char1 < char2 ? [userId1, userId2] : [userId2, userId1];
  }

  /// Validates if chat room can be created between users
  static bool canCreateChatRoom(String userId1, String userId2) {
    // Cannot create room with self
    if (userId1 == userId2) return false;

    // Both IDs must be non-empty
    if (userId1.isEmpty || userId2.isEmpty) return false;

    return true;
  }
}

// ============================================================================
// FILE: logic/notification_logic.dart
// ============================================================================
// Business Logic: Notification message formatting and rules

/// Business Logic: Notification rules
///
/// Determines when and how to send notifications
class NotificationLogic {
  /// Checks if notification should be sent
  ///
  /// Business Rules:
  /// - Don't send to admin users
  /// - Don't send if user has disabled notifications
  /// - Don't send if user is currently active in chat
  static bool shouldSendNotification(
    String fcmToken,
    bool isUserOnline,
    String chatRoomId,
    String? userActiveRoom,
  ) {
    // Admin check
    if (fcmToken == 'Admin') return false;

    // Empty token check
    if (fcmToken.isEmpty) return false;

    // Don't send if user is in the same chat room
    if (userActiveRoom == chatRoomId && isUserOnline) return false;

    return true;
  }

  /// Formats notification title
  static String formatNotificationTitle(String senderName) {
    return "Message from $senderName";
  }

  /// Truncates long messages for notifications
  ///
  /// Business Rule: Notifications show max 100 characters
  static String formatNotificationBody(String message) {
    const maxLength = 100;

    if (message.length <= maxLength) {
      return message;
    }

    return "${message.substring(0, maxLength)}...";
  }
}
