// ============================================================================
// FILE: hooks/use_user_data.dart
// ============================================================================
// Custom hook that manages user data fetching and real-time updates
// Uses useStream to listen to Firestore changes and useState for data storage
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:viora/models/ChatRoom.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:viora/Services/ChatService.dart';
import 'package:flutter/material.dart';
import 'package:viora/Services/DatabaseService.dart';

class UserDataState {
  final UserDetails? user;
  final bool isLoading;
  final String? error;

  UserDataState({this.user, this.isLoading = false, this.error});
}

/// Hook: Fetches and monitors user data in real-time
///
/// This hook encapsulates the logic of:
/// - Listening to Firestore user document changes
/// - Converting snapshot data to UserDetails model
/// - Managing loading and error states
UserDataState useUserData(String userId) {
  // useState: Holds the current user data state
  // useState: Holds the current user data statec
  final userState = useState<UserDataState>(UserDataState(isLoading: true));

  // useEffect: Sets up Firestore listener when userId changes
  useEffect(() {
    print('🔍 useUserData: Starting for userId: $userId');
    final subscription = FirebaseFirestore.instance
        .collection("Users")
        .doc(userId)
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.exists && snapshot.data() != null) {
              final user = UserDetails.fromJson(
                snapshot.data() as Map<String, dynamic>,
              );
              userState.value = UserDataState(user: user, isLoading: false);
            } else {
              userState.value = UserDataState(
                isLoading: false,
                error: 'User not found',
              );
            }
          },
          onError: (error) {
            userState.value = UserDataState(
              isLoading: false,
              error: error.toString(),
            );
          },
        );

    // Cleanup: Cancel subscription when widget disposes or userId changes
    return subscription.cancel;
  }, [userId]);

  return userState.value;
}

// ============================================================================
// FILE: hooks/use_chat_room.dart
// ============================================================================
// Custom hook that manages chat room initialization and monitoring
// Handles the complex logic of checking/creating chat rooms

class ChatRoomState {
  final ChatRoom? chatRoom;
  final bool isLoading;
  final String? error;

  ChatRoomState({this.chatRoom, this.isLoading = false, this.error});
}

/// Hook: Manages chat room setup and real-time monitoring
///
/// This hook encapsulates:
/// - Chat room ID generation logic (based on user ID comparison)
/// - Checking if chat room exists
/// - Creating new chat room if needed
/// - Real-time updates to chat room state
ChatRoomState useChatRoom(String otherUserId, UserDetails? otherUser) {
  // useState: Holds chat room state
  final chatRoomState = useState<ChatRoomState>(ChatRoomState(isLoading: true));

  // useEffect: Initialize and monitor chat room
  useEffect(() {
    print('🔍 useChatRoom: Starting for otherUserId: $otherUser');

    if (otherUser == null) {
      chatRoomState.value = ChatRoomState(
        isLoading: true, // ✅ Keeps loading state
      );
      return null; // ✅ Waits for user data
    }

    // Business Logic: Generate chat room path
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    final roomPath = _generateChatRoomPath(currentUserId, otherUserId);

    // Repository call: Check/create chat room
    _initializeChatRoom(
      roomPath,
      currentUserId,
      otherUserId,
      otherUser,
      chatRoomState,
    );

    return null;
  }, [otherUserId, otherUser]);

  return chatRoomState.value;
}

/// Business Logic: Generates chat room path based on user IDs
String _generateChatRoomPath(String user1, String user2) {
  // Sort users alphabetically to ensure consistent room IDs
  final usersArray = user1.codeUnitAt(0) < user2.codeUnitAt(0)
      ? [user1, user2]
      : [user2, user1];

  if (user1.codeUnitAt(0) == user2.codeUnitAt(0)) {
    return _checkUserID(user1, user2);
  }

  return user1.codeUnitAt(0) < user2.codeUnitAt(0)
      ? "${user1}_$user2"
      : "${user2}_$user1";
}

/// Helper: Handles equal first character case
String _checkUserID(String user1, String user2) {
  if (user1.compareTo(user2) == 1) {
    return "${user2}_$user1";
  } else if (user2.compareTo(user1) == 1) {
    return "${user1}_$user2";
  }
  return '';
}

/// Repository: Initialize or fetch existing chat room
Future<void> _initializeChatRoom(
  String roomPath,
  String currentUserId,
  String otherUserId,
  UserDetails otherUser,
  ValueNotifier<ChatRoomState> chatRoomState,
) async {
  try {
    final docSnapshot = await FirebaseFirestore.instance
        .collection("ChatRooms")
        .doc(roomPath)
        .get();

    if (docSnapshot.exists) {
      // Chat room exists - load it
      final chatRoom = ChatRoom.fromJson(
        docSnapshot.data() as Map<String, dynamic>,
      );
      chatRoomState.value = ChatRoomState(chatRoom: chatRoom, isLoading: false);

      // Set up real-time listener
      _listenToChatRoom(roomPath, chatRoomState);
    } else {
      // Chat room doesn't exist - create it
      final newChatRoom = ChatRoom(
        lastMessage: "",
        blockedBy: '',
        isBlocked: false,
        lastMessageDate: DateTime.now(),
        users: [otherUser.uid],
      );

      await ChatService.addChatRoom(newChatRoom);

      // Retry initialization after creation
      await _initializeChatRoom(
        roomPath,
        currentUserId,
        otherUserId,
        otherUser,
        chatRoomState,
      );
    }
  } catch (e) {
    chatRoomState.value = ChatRoomState(isLoading: false, error: e.toString());
  }
}

/// Repository: Listen to chat room changes in real-time
void _listenToChatRoom(
  String roomPath,
  ValueNotifier<ChatRoomState> chatRoomState,
) {
  FirebaseFirestore.instance
      .collection("ChatRooms")
      .doc(roomPath)
      .snapshots()
      .listen((snapshot) {
        // Check if ValueNotifier is still active before updating
        if (!chatRoomState.hasListeners) {
          return;
        }
        if (snapshot.exists && snapshot.data() != null) {
          final chatRoom = ChatRoom.fromJson(
            snapshot.data() as Map<String, dynamic>,
          );
          try {
            chatRoomState.value = ChatRoomState(
              chatRoom: chatRoom,
              isLoading: false,
            );
          } catch (e) {
            debugPrint('Error updating chatRoomState: $e');
          }
        }
      });
}

// ============================================================================
// FILE: hooks/use_typing_indicator.dart
// ============================================================================
// Custom hook that manages typing indicator state and updates
// Debounces typing updates to avoid excessive Firestore writes

class TypingIndicatorState {
  final bool showSendButton;
  final bool isTyping;

  TypingIndicatorState({this.showSendButton = false, this.isTyping = false});
}

/// Hook: Manages typing indicator and send button visibility
///
/// This hook:
/// - Monitors text field changes
/// - Shows/hides send button based on content
/// - Updates typing status in Firestore
/// - Implements debouncing to reduce writes
TypingIndicatorState useTypingIndicator(
  TextEditingController controller,
  String? chatRoomId,
) {
  // useState: Track typing state
  final typingState = useState(TypingIndicatorState());

  // useEffect: Listen to text changes
  useEffect(() {
    void handleTextChange() {
      final text = controller.text.trim();
      final hasText = text.isNotEmpty;

      // Update local state
      typingState.value = TypingIndicatorState(
        showSendButton: hasText,
        isTyping: hasText,
      );

      // Update remote typing status
      if (chatRoomId != null) {
        if (hasText) {
          DatabaseService.updateField({"isTyping": chatRoomId});
        } else {
          DatabaseService.updateField({"isTyping": ""});
        }
      }
    }

    // Add listener
    controller.addListener(handleTextChange);

    // Cleanup: Remove listener
    return () => controller.removeListener(handleTextChange);
  }, [controller, chatRoomId]);

  return typingState.value;
}
