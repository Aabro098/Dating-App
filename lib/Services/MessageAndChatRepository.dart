// ============================================================================
// FILE: repository/message_repository.dart
// ============================================================================
// Repository: All message-related backend operations
// Centralizes Firebase/database access for messages

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:viora/models/Message.dart';
import 'package:viora/models/ChatRoom.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:viora/models/Spamer.dart';
import 'package:viora/models/ReportedUser.dart';
import 'package:viora/Services/ChatService.dart';
import 'package:viora/Services/DatabaseService.dart';

import 'MessageAndCoinValidator.dart';

/// Repository: Message operations
///
/// This class handles all backend operations related to messages:
/// - Sending messages
/// - Spam detection and reporting
/// - User reporting
/// - Notification dispatching
///
/// All Firebase/database logic is isolated here, making it:
/// - Testable (can mock this repository)
/// - Maintainable (all DB logic in one place)
/// - Reusable (can be used from multiple screens)
class MessageRepository {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Sends a message to a chat room
  ///
  /// Backend Operations:
  /// - Creates message document in Firestore
  /// - Updates chat room's last message
  /// - Increments receiver's unseen count
  /// - Decrements sender's coins (if male)
  /// - Sends push notification to receiver
  static Future<void> sendMessage({
    required BuildContext context,
    required ChatRoom chatRoom,
    required UserDetails receiver,
    required String messageText,
    required String currentUserName,
  }) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser!.uid;

      // Update receiver's unseen message count
      DatabaseService.updateUserField(receiver.uid, {
        "unseenCount": FieldValue.increment(1),
      });

      // Create message object
      final message = MessageModel(
        seen: false,
        date: DateTime.now(),
        uid: currentUserId,
        text: messageText,
        receiver: receiver.uid,
        roomId: chatRoom.roomId,
      );

      // Send message through chat service
      await ChatService.sendMessage(message, context);

      // Message push is sent by functions/notifications/onMessageCreated.js
      // when the new Messages document is created.
      // Do NOT send here from client, otherwise the receiver gets duplicate
      // notifications (one from this app call + one from Firestore trigger).
    } catch (e) {
      debugPrint('vinay Error sending message: $e');
      rethrow;
    }
  }

  /// Handles spam message reporting
  ///
  /// Backend Operations:
  /// - Records spam attempt in Firestore
  /// - Triggers help message to user
  /// - Logs spam details for admin review
  static Future<void> handleSpamMessage(
    String messageText,
    String reason,
  ) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser!.uid;

      // Create spammer record
      final spamer = Spamer(
        lastSpamDate: DateTime.now(),
        lastSpamMessage: messageText,
        spamerId: currentUserId,
      );

      // Add to spam collection
      await DatabaseService.addSpam(spamer);

      // Send automated help message
      // await ChatService.sendHelpMessage();

      debugPrint('Spam reported: $reason');
    } catch (e) {
      debugPrint('Error handling spam: $e');
      rethrow;
    }
  }

  /// Reports a user for misconduct
  ///
  /// Backend Operation:
  /// - Creates a report document in Firestore
  /// - Includes reporter ID, reported user ID, and timestamp
  static Future<void> reportUser(
    String reportedUserId,
    BuildContext context,
  ) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser!.uid;

      final reportedUser = ReportedUser(
        date: DateTime.now(),
        reportedByUid: currentUserId,
        reportedUid: reportedUserId,
      );

      await DatabaseService.reportUsers(reportedUser, context);

      debugPrint('User reported: $reportedUserId');
    } catch (e) {
      debugPrint('Error reporting user: $e');
      rethrow;
    }
  }

  /// Marks a message as seen
  ///
  /// Backend Operation:
  /// - Updates message document's 'seen' field
  static Future<void> markMessageAsSeen(String messageDocId) async {
    try {
      await _firestore.collection('Messages').doc(messageDocId).update({
        'seen': true,
      });
    } catch (e) {
      debugPrint('Error marking message as seen: $e');
      rethrow;
    }
  }

  /// Deletes a message
  ///
  /// Backend Operation:
  /// - Removes message document from Firestore
  static Future<void> deleteMessage(String messageDocId) async {
    try {
      await _firestore.collection('Messages').doc(messageDocId).delete();
    } catch (e) {
      debugPrint('Error deleting message: $e');
      rethrow;
    }
  }

  /// Gets message count for a chat room
  ///
  /// Backend Operation:
  /// - Queries message count from Firestore
  static Future<int> getMessageCount(String chatRoomId) async {
    try {
      final snapshot = await _firestore
          .collection('Messages')
          .where('roomId', isEqualTo: chatRoomId)
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('Error getting message count: $e');
      return 0;
    }
  }

  /// Gets unread message count for current user
  ///
  /// Backend Operation:
  /// - Queries unseen messages where user is receiver
  static Future<int> getUnreadCount(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('Messages')
          .where('receiver', isEqualTo: userId)
          .where('seen', isEqualTo: false)
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('Error getting unread count: $e');
      return 0;
    }
  }
}

// ============================================================================
// FILE: repository/chat_room_repository.dart
// ============================================================================
// Repository: All chat room-related backend operations
// Centralizes Firebase/database access for chat rooms

/// Repository: Chat room operations
///
/// Handles all backend operations for chat rooms:
/// - Creating chat rooms
/// - Blocking/unblocking
/// - Fetching chat room data
/// - Real-time updates
class ChatRoomRepository {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Creates a new chat room
  ///
  /// Backend Operations:
  /// - Generates room ID using business logic
  /// - Creates chat room document in Firestore
  /// - Initializes with empty message state
  static Future<ChatRoom?> createChatRoom(
    String otherUserId,
    String otherUserName,
  ) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser!.uid;

      // Validation using business logic
      if (!ChatRoomLogic.canCreateChatRoom(currentUserId, otherUserId)) {
        debugPrint('Cannot create chat room with invalid users');
        return null;
      }

      // Generate room ID using business logic
      final roomId = ChatRoomLogic.generateRoomId(currentUserId, otherUserId);
      final sortedUsers = ChatRoomLogic.getSortedUserIds(
        currentUserId,
        otherUserId,
      );

      final chatRoom = ChatRoom(
        lastMessage: "",
        blockedBy: '',
        isBlocked: false,
        lastMessageDate: DateTime.now(),
        users: sortedUsers,
      );
      chatRoom.roomId = roomId;

      // Create in Firestore
      await ChatService.addChatRoom(chatRoom);

      return chatRoom;
    } catch (e) {
      debugPrint('Error creating chat room: $e');
      rethrow;
    }
  }

  /// Fetches a chat room by ID
  ///
  /// Backend Operation:
  /// - Retrieves chat room document from Firestore
  static Future<ChatRoom?> getChatRoom(String roomId) async {
    try {
      final doc = await _firestore.collection('ChatRooms').doc(roomId).get();

      if (doc.exists && doc.data() != null) {
        return ChatRoom.fromJson(doc.data()!);
      }

      return null;
    } catch (e) {
      debugPrint('Error fetching chat room: $e');
      return null;
    }
  }

  /// Blocks a chat room
  ///
  /// Backend Operations:
  /// - Updates chat room's isBlocked flag
  /// - Records who blocked the room
  static Future<void> blockChatRoom(String chatRoomId, String uId) async {
    try {
      final currentUserId = uId.isEmpty
          ? FirebaseAuth.instance.currentUser!.uid
          : uId;

      await ChatService.updateBlockChatRoom(chatRoomId, true, currentUserId);

      debugPrint('Chat room blocked: $chatRoomId');
    } catch (e) {
      debugPrint('Error blocking chat room: $e');
      rethrow;
    }
  }

  /// Unblocks a chat room
  ///
  /// Backend Operations:
  /// - Updates chat room's isBlocked flag to false
  /// - Clears blockedBy field
  static Future<void> unblockChatRoom(String chatRoomId, String uId) async {
    try {
      final currentUserId = uId.isEmpty
          ? FirebaseAuth.instance.currentUser!.uid
          : uId;

      await ChatService.updateBlockChatRoom(chatRoomId, false, currentUserId);

      debugPrint('Chat room unblocked: $chatRoomId');
    } catch (e) {
      debugPrint('Error unblocking chat room: $e');
      rethrow;
    }
  }

  /// Gets all chat rooms for current user
  ///
  /// Backend Operation:
  /// - Queries chat rooms where user is a participant
  static Stream<QuerySnapshot> getUserChatRooms(String userId) {
    return _firestore
        .collection('ChatRooms')
        .where('users', arrayContains: userId)
        .orderBy('lastMessageDate', descending: true)
        .snapshots();
  }

  /// Checks if a chat room is blocked
  ///
  /// Backend Operation:
  /// - Fetches chat room and checks isBlocked flag
  static Future<bool> isChatRoomBlocked(String chatRoomId) async {
    try {
      final chatRoom = await getChatRoom(chatRoomId);
      return chatRoom?.isBlocked ?? false;
    } catch (e) {
      debugPrint('Error checking blocked status: $e');
      return false;
    }
  }

  /// Updates typing status in chat room
  ///
  /// Backend Operation:
  /// - Updates user's typing field in Firestore
  static Future<void> updateTypingStatus(
    String userId,
    String? chatRoomId,
  ) async {
    try {
      DatabaseService.updateField({"isTyping": chatRoomId ?? ""});
    } catch (e) {
      debugPrint('Error updating typing status: $e');
      rethrow;
    }
  }
}

// ============================================================================
// FILE: repository/user_repository.dart
// ============================================================================
// Repository: User-related backend operations

/// Repository: User operations
///
/// Handles all backend operations for users:
/// - Fetching user data
/// - Updating user fields
/// - Coin management
class UserRepository {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fetches user details by ID
  ///
  /// Backend Operation:
  /// - Retrieves user document from Firestore
  static Future<UserDetails?> getUserById(String userId) async {
    try {
      final doc = await _firestore.collection('Users').doc(userId).get();

      if (doc.exists && doc.data() != null) {
        return UserDetails.fromJson(doc.data()!);
      }

      return null;
    } catch (e) {
      debugPrint('Error fetching user: $e');
      return null;
    }
  }

  /// Gets real-time user updates
  ///
  /// Backend Operation:
  /// - Returns a stream of user document changes
  static Stream<DocumentSnapshot> getUserStream(String userId) {
    return _firestore.collection('Users').doc(userId).snapshots();
  }

  /// Updates user coins
  ///
  /// Backend Operation:
  /// - Increments or decrements user's coin count
  static Future<void> updateCoins(String userId, int amount) async {
    try {
      await _firestore.collection('Users').doc(userId).update({
        'coins': FieldValue.increment(amount),
      });
    } catch (e) {
      debugPrint('Error updating coins: $e');
      rethrow;
    }
  }

  /// Updates user's online status
  ///
  /// Backend Operation:
  /// - Updates isOnline flag and lastOnline timestamp
  static Future<void> updateOnlineStatus(String userId, bool isOnline) async {
    try {
      await _firestore.collection('Users').doc(userId).update({
        'isOnline': isOnline,
        'lastOnline': DateTime.now(),
      });
    } catch (e) {
      debugPrint('Error updating online status: $e');
      rethrow;
    }
  }

  /// Resets user's unseen message count
  ///
  /// Backend Operation:
  /// - Sets unseenCount to 0
  static Future<void> resetUnseenCount(String userId) async {
    try {
      await _firestore.collection('Users').doc(userId).update({
        'unseenCount': 0,
      });
    } catch (e) {
      debugPrint('Error resetting unseen count: $e');
      rethrow;
    }
  }
}
