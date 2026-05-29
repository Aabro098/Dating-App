import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:viora/Services/UserProvider.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:provider/provider.dart';

import 'DatabaseService.dart';
import 'package:viora/constants.dart';
import 'package:viora/models/ChatRoom.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:viora/models/Message.dart';
import 'package:viora/models/SupportModels.dart';

// Helper for conditional logging
void _log(String message) {
  if (kDebugMode) {
    debugPrint('[ChatService] $message');
  }
}

class ChatService {
  static String checkUserID(String user1, String user2) {
    if (user1.compareTo(user2) == 1) {
      return user2 + "_" + user1;
    } else if (user2.compareTo(user1) == 1) {
      return user1 + "_" + user2;
    }
    return '';
  }

  static Future<void> addChatRoom(ChatRoom chatRoom) async {
    String uid = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance
        .runTransaction((Transaction tx) async {
          CollectionReference collectionReference = FirebaseFirestore.instance
              .collection("ChatRooms");

          var user1 = uid; // UID of user 1
          var user2 = chatRoom.users[0];
          chatRoom.users = user1.codeUnitAt(0) < user2.codeUnitAt(0)
              ? [user1, user2]
              : [user2, user1];
          var path = user1.codeUnitAt(0) == user2.codeUnitAt(0)
              ? checkUserID(user1, user2)
              : user1.codeUnitAt(0) < user2.codeUnitAt(0)
              ? user1 + "_" + user2
              : user2 + "_" + user1;

          chatRoom.roomId = path;

          await collectionReference
              .doc(path)
              .set(chatRoom.toJson())
              .whenComplete(() {
                _log("ChatRoom added successfully");
              });
        })
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('Failed to create chat room');
          },
        );
  }

  static Future<void> addBotChatRoom(ChatRoom chatRoom, context) async {
    await FirebaseFirestore.instance
        .runTransaction((Transaction tx) async {
          CollectionReference collectionReference = FirebaseFirestore.instance
              .collection("ChatRooms");

          var user1 = chatRoom.users[1]; // UID of user 1
          var user2 = chatRoom.users[0];
          chatRoom.users = user1.codeUnitAt(0) < user2.codeUnitAt(0)
              ? [user1, user2]
              : [user2, user1];
          var path = user1.codeUnitAt(0) == user2.codeUnitAt(0)
              ? checkUserID(user1, user2)
              : user1.codeUnitAt(0) < user2.codeUnitAt(0)
              ? user1 + "_" + user2
              : user2 + "_" + user1;

          chatRoom.roomId = path;

          await collectionReference
              .doc(path)
              .set(chatRoom.toJson())
              .whenComplete(() {
                _log("Bot ChatRoom added successfully");
              });
        })
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('Failed to create bot chat room');
          },
        );
  }

  static Future<void> addSupportChatRoom(ChatRoom chatRoom, context) async {
    String uid = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance
        .runTransaction((Transaction tx) async {
          CollectionReference collectionReference = FirebaseFirestore.instance
              .collection("SupportChatRooms");

          var user1 = uid;
          var user2 = chatRoom.users[0];
          chatRoom.users = user1.codeUnitAt(0) < user2.codeUnitAt(0)
              ? [user1, user2]
              : [user2, user1];
          var path = user1.codeUnitAt(0) < user2.codeUnitAt(0)
              ? user1 + "_" + user2
              : user2 + "_" + user1;

          chatRoom.roomId = path;

          await collectionReference
              .doc(path)
              .set(chatRoom.toJson())
              .whenComplete(() {
                _log("SupportChatRoom added successfully");
              });
        })
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('Failed to create support chat room');
          },
        );
  }

  static Future<void> sendMessage(MessageModel message, context) async {
    final Connectivity _connectivity = Connectivity();
    List<ConnectivityResult> result = ConnectivityResult.values;
    try {
      result = await _connectivity.checkConnectivity();
    } on PlatformException catch (e) {
      print(e.toString());
    }
    if (result.first == ConnectivityResult.none) {
      showSimpleNotification(
        Text("No Internet Connection"),
        subtitle: Text("Check you connection and retry"),
        // leading: NotificationBadge(totalNotifications: _totalNotifications),
        background: Colors.redAccent,
        duration: Duration(seconds: 4),
        position: NotificationPosition.top,
        slideDismiss: true,
        leading: Icon(Icons.close),
      );
    } else {
      final userDetails = Provider.of<UserProvider>(
        context,
        listen: false,
      ).userDetails;

      // if (userDetails.gender == "Male") {
      // Deduct coins based on number of images, or 1 coin for text-only message
      int coinsToDeduct = 1;
      if (message.imagePath != null && message.imagePath!.isNotEmpty) {
        coinsToDeduct = message.imagePath!.length;
      }

      // If coins is -1 (unlimited), do not deduct
      if (userDetails.coins != -1) {
        DatabaseService.updateField({
          "coins": FieldValue.increment(-coinsToDeduct),
        });
      } else {
        _log("User has unlimited coins (-1); skipping deduction");
      }
      // }

      CollectionReference collectionReference = FirebaseFirestore.instance
          .collection("Messages");
      CollectionReference collectionReferenceChatRoom = FirebaseFirestore
          .instance
          .collection("ChatRooms");

      collectionReference.add(message.toJson()).whenComplete(() {
        debugPrint("vinayChatBlocked Message Added");
      });
      collectionReferenceChatRoom.doc(message.roomId).update({
        "lastMessage": message.text,
        "lastMessageDate": DateTime.now(),
      });
    }

    // Trigger the authentication flow
  }

  static Future<void> sendBotMessage(MessageModel message) async {
    CollectionReference collectionReference = FirebaseFirestore.instance
        .collection("Messages");
    CollectionReference collectionReferenceChatRoom = FirebaseFirestore.instance
        .collection("ChatRooms");

    collectionReference.add(message.toJson()).whenComplete(() {
      print("Message Added");
    });
    collectionReferenceChatRoom.doc(message.roomId).update({
      "lastMessage": message.text,
      "lastMessageDate": DateTime.now(),
    });
    // Trigger the authentication flow
  }

  static Future<void> sendSupportMessage(MessageModel message, context) async {
    CollectionReference collectionReference = FirebaseFirestore.instance
        .collection("SupportMessages");
    CollectionReference collectionReferenceChatRoom = FirebaseFirestore.instance
        .collection("SupportChatRooms");

    collectionReference.add(message.toJson()).whenComplete(() {
      _log("SupportMessage added");
    });
    collectionReferenceChatRoom.doc(message.roomId).update({
      "lastMessage": message.text,
      "lastMessageDate": DateTime.now(),
    });
  }

  static Future<void> sendSupportMessageEnhanced(
    SupportMessageModel message,
    context,
  ) async {
    try {
      CollectionReference collectionReference = FirebaseFirestore.instance
          .collection("SupportMessages");

      await collectionReference.add(message.toJson()).whenComplete(() {
        _log("Enhanced SupportMessage added");
      });

      // Update last message in chat room (non-blocking)
      try {
        CollectionReference collectionReferenceChatRoom = FirebaseFirestore
            .instance
            .collection("SupportChatRooms");
        await collectionReferenceChatRoom.doc(message.roomId).update({
          "lastMessage": message.text,
          "lastMessageDate": DateTime.now(),
        });
      } catch (e) {
        _log("Failed to update SupportChatRoom lastMessage: $e");
      }
    } catch (e) {
      _log("Failed to send support message: $e");
      rethrow;
    }
  }

  static Future<void> updateSeen(
    String? docId,
    Map<String, dynamic> data,
  ) async {
    if (docId == null || docId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection("Messages")
          .doc(docId)
          .update(data);
    } catch (e) {
      _log("updateSeen failed (check Firestore rules): $e");
    }
  }

  static Future<void> updateSupportSeen(
    String? docId,
    Map<String, dynamic> data,
  ) async {
    if (docId == null || docId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection("SupportMessages")
          .doc(docId)
          .update(data);
    } catch (e) {
      _log("updateSupportSeen failed: $e");
    }
  }

  static Future<void> updateBlockChatRoom(
    String chatRoomId,
    bool isBlocked,
    String uid,
  ) async {
    FirebaseFirestore.instance.runTransaction((Transaction tx) async {
      CollectionReference collectionReference = FirebaseFirestore.instance
          .collection("ChatRooms");

      await collectionReference.doc(chatRoomId).update({
        "isBlocked": isBlocked,
        "blockedBy": uid,
      });
    });
    // Trigger the authentication flow
  }

  static Future<void> sendHelpMessage() async {
    String uid = FirebaseAuth.instance.currentUser!.uid;

    var user2 = uid; // UID of user 1
    var user1 = "Yl5RALFSJdOke2wgRDZp";

    var path = user1.codeUnitAt(0) < user2.codeUnitAt(0)
        ? user1 + "_" + user2
        : user2 + "_" + user1;

    CollectionReference collectionReference = FirebaseFirestore.instance
        .collection("ChatRooms");
    //.where("users",isEqualTo: usersArray)
    await collectionReference.doc(path).get().then((value) {
      if (value.exists) {
        ChatRoom chatRoom = ChatRoom.fromJson(
          value.data() as Map<String, dynamic>,
        );
        MessageModel message = MessageModel(
          seen: false,
          date: DateTime.now(),
          uid: "Yl5RALFSJdOke2wgRDZp",
          text: helpMessage,
          roomId: chatRoom.roomId,
          receiver: '',
        );
        ChatService.sendBotMessage(message);
      } else {
        ChatRoom chatRoom = new ChatRoom(
          lastMessage: "",
          lastMessageDate: DateTime.now(),
          users: ["Yl5RALFSJdOke2wgRDZp"],
          blockedBy: '',
          isBlocked: false,
        );
        ChatService.addChatRoom(chatRoom).then((value) {
          sendHelpMessage();
        });
      }
    });
  }
}
