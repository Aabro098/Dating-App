import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:viora/Services/AppConfigService.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/Services/exceptions/exceptions.dart';
import 'package:viora/models/NotificationData.dart';
import 'package:viora/models/UserDetails.dart';
import '../constants.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'Global.dart';

// Helper for conditional logging
void _log(String message) {
  if (kDebugMode) {
    debugPrint('[NotificationService] $message');
  }
}

class NotificationService {
  static Future<void> addNotification(
    receiverId,
    receiverToken,
    action,
    context,
  ) async {
    final globals = Globals.of(context);
    UserDetails curruntUser = globals.userProvider.userDetails;
    DatabaseService.updateUserField(receiverId, {
      "notiCount": FieldValue.increment(1),
    });
    NotificationData notification = NotificationData(
      uid: curruntUser.uid,
      name: curruntUser.name!,
      date: DateTime.now(),
      imgUrl: curruntUser.images!.isEmpty
          ? curruntUser.gender == "Male"
                ? AppConfigService.maleImageUrl
                : AppConfigService.femaleImageUrl
          : curruntUser.images![0],
      type: action,
    );

    CollectionReference collectionReference = FirebaseFirestore.instance
        .collection("Users");

    await collectionReference
        .doc(receiverId)
        .collection("Notifications")
        .doc(curruntUser.uid + action)
        .set(notification.toJson())
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Failed to save notification');
          },
        )
        .whenComplete(() {
          _log("Notification added");
        });

    // ✅ Validate FCM token before sending notification
    final tokenStr = receiverToken?.toString() ?? '';

    // Skip if token is empty or is the string "null" (legacy bug)
    if (tokenStr.isEmpty || tokenStr == 'null') {
      debugPrint('ℹ️ Skipping notification - receiver has no FCM token');
      return;
    }

    // Check if this is a BOT profile (bots have fcmToken = "Admin")
    final isBotProfile = tokenStr == 'Admin';

    // For regular FCM tokens: must be 100+ characters (valid FCM tokens are ~152 chars)
    // Skip if token looks invalid (too short and not a bot)
    if (!isBotProfile && tokenStr.length < 100) {
      debugPrint(
        'ℹ️ Skipping notification - invalid FCM token (${tokenStr.length} chars)',
      );
      return;
    }

    // Send notification (non-blocking)
    try {
      if (isBotProfile) {
        // BOT PROFILE: Send notification to Admin topic with viewer's info
        // Fetch bot's name for the message
        String botName = "Bot";
        try {
          final botDoc = await FirebaseFirestore.instance
              .collection("Users")
              .doc(receiverId)
              .get()
              .timeout(
                const Duration(seconds: 5),
                onTimeout: () {
                  throw TimeoutException('Failed to fetch bot name');
                },
              );
          if (botDoc.exists) {
            botName = botDoc.data()?['name'] ?? 'Bot';
          }
        } catch (e, stackTrace) {
          _log('Error fetching bot name: $e');
          final appException = ErrorHandler.convert(e, stackTrace);
          _log('Converted to: ${appException.runtimeType}');
        }

        debugPrint(
          '🔔 [BOT] ${curruntUser.name} $action $botName - sending to Admin topic',
        );

        await sendNotification(
          "Admin", // Send to Admin topic
          "BOTs", // Title must be "BOTs" for FCM handler to recognize
          action == "View"
              ? "${curruntUser.name} just viewed $botName's Profile"
              : action == "Fav"
              ? "${curruntUser.name} added $botName in favorites"
              : action == "Crush"
              ? "${curruntUser.name} had crush on $botName"
              : "",
          curruntUser.uid, // Pass VIEWER's uid so clicking opens their profile
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('⚠️ Notification timeout - continuing anyway');
          },
        );
      } else {
        // REGULAR USER PROFILE: Send notification to the user
        await sendNotification(
          receiverToken,
          "Profile Notification",
          action == "View"
              ? "Someone just viewed your Profile"
              : action == "Fav"
              ? "Someone just added you in there favorites"
              : action == "Crush"
              ? "Someone just had crush on you"
              : "",
          curruntUser.uid,
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('⚠️ Notification timeout - continuing anyway');
          },
        );
      }
    } catch (e) {
      // Log but don't throw - notification is optional
      debugPrint('⚠️ Profile notification failed (non-critical): $e');
    }
  }

  static Future<auth.AccessCredentials> _getAccessToken() async {
    final serviceAccountPath = "SECRETS/fcm_key.json";

    String serviceAccountJson = await rootBundle.loadString(serviceAccountPath);

    print("vinayNotification json: $serviceAccountJson");
    final serviceAccount = auth.ServiceAccountCredentials.fromJson(
      serviceAccountJson,
    );

    final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

    final client = await clientViaServiceAccount(serviceAccount, scopes);
    return client.credentials;
  }

  static Future<void> sendNotification(token, title, body, uId) async {
    final user = FirebaseAuth.instance.currentUser;
    Map<String, String> data = {
      "click_action": "FLUTTER_NOTIFICATION_CLICK",
      "id": "1",
      "status": "done",
      "uid": uId,
    };

    if (user == null) {
      throw Exception('User not authenticated');
    }
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');

    final callable = functions.httpsCallable('notifications-sendPush');
    if (token == "Admin") {
      try {
        final response = await callable.call({
          'topic': token,
          'title': title,
          'body': body,
          "data": data,
        });

        print(" ✅ Notification success: ${response.data}");
      } catch (e, st) {
        _logCallableFailure('topic/Admin', e, st);
      }
    } else {
      try {
        final response = await callable.call({
          'token': token,
          'title': title,
          'body': body,
          "data": data,
        });
        print(" ✅ Notification success: ${response.data}");
      } catch (e, st) {
        _logCallableFailure('token', e, st);
      }
    }
  }

  /// Logs why `notifications-sendPush` failed (often App Check, auth, or IAM).
  static void _logCallableFailure(String mode, Object e, StackTrace st) {
    debugPrint('⚠️ Notification callable failed ($mode): $e');
    if (e is FirebaseException) {
      debugPrint('   FirebaseException code=${e.code} message=${e.message}');
      if (e.code == 'failed-precondition' ||
          (e.message ?? '').toLowerCase().contains('app check')) {
        debugPrint(
          '   → Likely App Check: add debug token in Firebase Console, or ensure '
          'Play Integrity / App Attest is registered for this app.',
        );
      }
    }
    if (kDebugMode) debugPrint('$st');
  }

  static Future<void> sendNotificationHTTP({
    required String fcmToken,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("⚠️ User not logged in, skipping notification");
      return;
    }

    final idToken = await user.getIdToken(true);

    final uri = Uri.parse(
      "https://us-central1-vioraa.cloudfunctions.net/notifications-sendPush",
    );

    try {
      final response = await http.post(
        uri,
        headers: {
          "Authorization": "Bearer $idToken",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "token": fcmToken,
          "title": title,
          "body": body,
          "data": data ?? {},
        }),
      );

      if (response.statusCode != 200) {
        print("⚠️ Notification failed: ${response.body}");
      } else {
        print(" ✅ Notification success: ${response.body}");
      }
    } catch (e) {
      print("❌ Notification error: $e");
    }
  }

  static Future<void> sendNotificationOld(token, title, body, uId) async {
    final credentials = await _getAccessToken();
    final accessToken = credentials.accessToken.data;
    final projectId = 'vioraa';
    print("vinayNotification accessToken: $accessToken");

    if (token == "Admin") {
      sendAdminNotification("BOTs " + title, body, uId);
    } else {
      // ✅ FIXED: Correct FCM v1 API structure
      final data = {
        "message": {
          "token": "$token",
          "notification": {"body": body, "title": title},
          // ✅ Data payload inside message
          "data": {
            "click_action": "FLUTTER_NOTIFICATION_CLICK",
            "id": "1",
            "status": "done",
            "uid": uId,
          },
          // ✅ Platform-specific configuration
          "android": {
            "priority": "high",
            "notification": {
              "sound": "default",
              "click_action": "FLUTTER_NOTIFICATION_CLICK",
            },
          },
          "apns": {
            "headers": {"apns-priority": "10"},
            "payload": {
              "aps": {"sound": "default"},
            },
          },
        },
      };

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

      BaseOptions options = BaseOptions(
        connectTimeout: Duration(milliseconds: 5000),
        receiveTimeout: Duration(milliseconds: 3000),
        headers: headers,
      );

      print("vinayNotification $data");

      try {
        final response = await Dio(options).post(
          "https://fcm.googleapis.com/v1/projects/$projectId/messages:send",
          data: data,
        );

        if (response.statusCode == 200) {
          print('vinayNotification notification sent successfully');
        } else {
          print(
            'vinayNotification notification sending failed: ${response.statusCode}',
          );
        }
      } catch (e) {
        print('vinay notification exception $e');
        if (e is DioException && e.response != null) {
          print('vinay notification error response: ${e.response?.data}');
        }
      }
    }
  }

  // ✅ OPTION 1: Update to use FCM v1 API (Recommended)
  static Future<void> sendSupportResponseNotification(
    token,
    title,
    body,
  ) async {
    final credentials = await _getAccessToken();
    final accessToken = credentials.accessToken.data;
    final projectId = 'vioraa';

    final data = {
      "message": {
        "token": "$token",
        "notification": {"body": body, "title": title},
        "data": {
          "click_action": "FLUTTER_NOTIFICATION_CLICK",
          "id": "1",
          "status": "done",
        },
        "android": {
          "priority": "high",
          "notification": {"sound": "default"},
        },
      },
    };

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
    };

    BaseOptions options = BaseOptions(
      connectTimeout: Duration(milliseconds: 5000),
      receiveTimeout: Duration(milliseconds: 3000),
      headers: headers,
    );

    try {
      final response = await Dio(options).post(
        "https://fcm.googleapis.com/v1/projects/$projectId/messages:send",
        data: data,
      );

      if (response.statusCode == 200) {
        print('vinayNotification notification sent');
      } else {
        print('vinayNotification notification sending failed');
      }
    } catch (e) {
      print('vinayNotification exception $e');
      if (e is DioException && e.response != null) {
        print('vinayNotification error response: ${e.response?.data}');
      }
    }
  }

  static Future<void> sendAdminNotification(title, body, uId) async {
    await sendNotification("Admin", title, body, uId);
  }

  // ✅ OPTION 2: Update to use FCM v1 API with topic
  static Future<void> sendAdminNotificationOld(title, body, uId) async {
    final credentials = await _getAccessToken();
    final accessToken = credentials.accessToken.data;
    final projectId = 'vioraa';

    final data = {
      "message": {
        "topic": "Admin", // ✅ Use topic instead of "to"
        "notification": {"body": body, "title": title},
        "data": {
          "click_action": "FLUTTER_NOTIFICATION_CLICK",
          "id": "1",
          "status": "done",
          "uid": uId,
        },
        "android": {
          "priority": "high",
          "notification": {"sound": "default"},
        },
      },
    };

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
    };

    BaseOptions options = BaseOptions(
      connectTimeout: Duration(milliseconds: 5000),
      receiveTimeout: Duration(milliseconds: 3000),
      headers: headers,
    );

    try {
      final response = await Dio(options).post(
        "https://fcm.googleapis.com/v1/projects/$projectId/messages:send",
        data: data,
      );

      if (response.statusCode == 200) {
        print('Notification sent');
      } else {
        print('Notification sending failed');
      }
    } catch (e) {
      print('Notification exception $e');
      if (e is DioException && e.response != null) {
        print('Notification error response: ${e.response?.data}');
      }
    }
  }

  static Future<void> addBotNotification(
    receiverId,
    receiverToken,
    action,
    UserDetails bot,
  ) async {
    // Skip if bot is viewing themselves (shouldn't happen but safety check)
    if (bot.uid == receiverId) {
      debugPrint('[BOT] Skipping self-notification');
      return;
    }

    // This function handles: Bot views a user profile
    // - bot = the bot doing the viewing (e.g., Rinki)
    // - receiverId = the user being viewed (e.g., "Bot male")
    // Notification is stored in the VIEWED USER's collection
    // The notification stores the BOT's info (who viewed them)

    NotificationData notification = NotificationData(
      uid: bot.uid, // Store bot's uid (the viewer)
      name: bot.name!, // Bot's name (the viewer)
      date: DateTime.now(),
      imgUrl: bot.images!.isEmpty
          ? bot.gender == "Male"
                ? AppConfigService.maleImageUrl
                : AppConfigService.femaleImageUrl
          : bot.images![0],
      type: action,
    );

    // Fetch viewed user's name for the notification message
    String viewedUserName = "User";
    try {
      final viewedUserDoc = await FirebaseFirestore.instance
          .collection("Users")
          .doc(receiverId)
          .get();
      if (viewedUserDoc.exists) {
        viewedUserName = viewedUserDoc.data()?['name'] ?? 'User';
      }
    } catch (e) {
      debugPrint('[BOT] Error fetching viewed user info: $e');
    }

    // Save notification to VIEWED USER's notifications collection
    // So the viewed user can see who viewed them
    await FirebaseFirestore.instance
        .collection("Users")
        .doc(receiverId) // Save to viewed user's collection
        .collection("Notifications")
        .doc(bot.uid + action) // Use bot's uid as doc id
        .set(notification.toJson());

    // Update viewed user's notification count
    DatabaseService.updateUserField(receiverId, {
      "notiCount": FieldValue.increment(1),
    });

    debugPrint('[BOT] Notification saved: ${bot.name} $action $viewedUserName');

    // Push must go to the **viewed user’s** device, not the Admin topic (Admin was only
    // receiving these; the real user got nothing). Same routing as [addNotification] for
    // normal profiles: title "Profile Notification" + uid = bot for tap → open bot profile.
    final tokenStr = receiverToken?.toString() ?? '';
    if (tokenStr.isEmpty ||
        tokenStr == 'null' ||
        tokenStr == 'Admin' ||
        tokenStr.length < 100) {
      debugPrint(
        '[BOT] Skipping FCM — viewed user has no valid token (len=${tokenStr.length})',
      );
      return;
    }
    try {
      await sendNotification(
        tokenStr,
        'Profile Notification',
        action == 'View'
            ? '${bot.name} just viewed your profile.'
            : action == 'Fav'
            ? '${bot.name} added you to their favorites'
            : action == 'Crush'
            ? '${bot.name} just had a crush on you.'
            : '',
        bot.uid,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⚠️ [BOT] FCM timeout - continuing anyway');
        },
      );
    } catch (e) {
      debugPrint('⚠️ [BOT] Push failed (non-critical): $e');
    }
  }
}
