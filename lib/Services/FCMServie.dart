import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:viora/Screens/AdminScreens/Spamers.dart';
import 'package:viora/Screens/AdminScreens/adminChatRooms.dart';
import 'package:viora/Screens/BotManagement/botChatScreen.dart';
import 'package:viora/Screens/MessagesScreen/new_message_screen.dart';
import 'package:viora/Screens/ProfileScreen/new_profile_view.dart';
import 'package:viora/Screens/SupportScreen/supportScreen.dart';
import 'package:viora/main.dart';

class FCMService {
  static RemoteMessage? _pendingMessage;
  static bool _permissionRequested = false;

  /// Avoid duplicate onMessage / onMessageOpenedApp subscriptions after re-init.
  static bool _foregroundListenersAttached = false;
  static StreamSubscription<String>? _tokenRefreshSubscription;

  /// FCM registration tokens are long; short values are placeholders or corrupt.
  static const int _minValidFcmTokenLength = 100;

  /// Reset permission flag and clear state (called on logout)
  static Future<void> resetOnLogout() async {
    _permissionRequested = false;
    _pendingMessage = null;

    // 🔑 CRITICAL: Unsubscribe from Admin topic to prevent admin notifications
    // persisting after logout and being visible to next user
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic("Admin");
      debugPrint('🔔 FCM: Unsubscribed from Admin topic');
    } catch (e) {
      debugPrint('⚠️ FCM: Failed to unsubscribe from Admin topic: $e');
    }

    debugPrint(
      '🔔 FCM: State reset for logout - will reinitialize on next login',
    );
  }

  /// Reset permission flag (for testing only)
  static void resetPermissionFlag() {
    _permissionRequested = false;
    print('🔔 FCM: Permission flag reset');
  }

  /// Setup FCM listeners without requesting permission
  static Future<void> setupListeners() async {
    // 🔹 KILLED STATE (safe to call every init)
    final message = await FirebaseMessaging.instance.getInitialMessage();
    if (message != null) {
      _pendingMessage = message;
    }

    if (_foregroundListenersAttached) return;
    _foregroundListenersAttached = true;

    // 🔹 BACKGROUND (tap)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _pendingMessage = message;
      _tryHandlePending();
    });

    // 🔹 FOREGROUND
    FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title ?? message.data['title'] ?? '';
      final body = message.notification?.body ?? message.data['body'] ?? '';
      if (title.isEmpty && body.isEmpty) return;
      showSimpleNotification(
        Text(title),
        subtitle: Text(body),
        background: Colors.cyan.shade700,
        duration: const Duration(seconds: 3),
        slideDismiss: true,
        trailing: GestureDetector(
          onTap: () {
            _pendingMessage = message;
            _tryHandlePending();
          },
          child: Icon(
            title.contains("Message from")
                ? Icons.reply
                : CupertinoIcons.profile_circled,
            color: Colors.white,
          ),
        ),
      );
    });

    _ensureTokenRefreshListener();
  }

  /// Keep Firestore in sync when FCM rotates the device token.
  static void _ensureTokenRefreshListener() {
    if (_tokenRefreshSubscription != null) return;
    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
        .listen(
          (newToken) async {
            await _saveFcmTokenToFirestore(newToken);
          },
          onError: (Object e) => debugPrint('🔔 FCM: onTokenRefresh error: $e'),
        );
  }

  /// Initialize FCM ONLY if permission is already granted
  /// DOES NOT request permission - that's HomeScreen's job!
  static Future<void> init() async {
    print('🔔 FCM: Checking if permission is already granted...');

    if (_permissionRequested) {
      print('🔔 FCM: Already initialized, skipping');
      return;
    }

    // Check if permission is granted WITHOUT requesting
    bool permissionGranted = false;

    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      permissionGranted = status.isGranted;
      print('🔔 FCM: Android notification permission status: $status');

      if (!permissionGranted) {
        print(
          '⚠️ FCM: Permission NOT granted yet - waiting for HomeScreen to request it',
        );
        print(
          '🚫 FCM: init() returning early - will be called again after permission granted',
        );
        return;
      }
    } else {
      // iOS: Check permission status without requesting
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      permissionGranted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      print(
        '🔔 FCM: iOS notification permission status: ${settings.authorizationStatus}',
      );

      if (!permissionGranted) {
        print(
          '⚠️ FCM: Permission NOT granted yet - waiting for HomeScreen to request it',
        );
        print(
          '🚫 FCM: init() returning early - will be called again after permission granted',
        );
        return;
      }
    }

    // Permission is granted - proceed with initialization
    _permissionRequested = true;
    print('✅ FCM: Permission granted! Proceeding with FCM initialization...');

    // Setup listeners if not already done
    await setupListeners();

    await _persistFcmTokenToFirestore();

    print('✅ FCM: Initialization complete');
  }

  /// Call this method AFTER HomeScreen grants notification permission
  /// This initializes FCM with the granted permission
  static Future<void> onPermissionGranted() async {
    print(
      '🎉 FCM: onPermissionGranted() called - permission was granted by HomeScreen',
    );

    await _persistFcmTokenToFirestore();

    // Initialize FCM listeners if not already done
    await init();

    // Check if user is admin and subscribe to Admin topic automatically
    await _checkAndSubscribeAdminTopic();
  }

  /// Check if current user is admin and subscribe to Admin topic
  /// This is called automatically when user signs in, no need to visit Admin menu
  static Future<void> _checkAndSubscribeAdminTopic() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) {
        debugPrint('🔔 FCM: No user logged in, skipping admin check');
        return;
      }

      debugPrint('🔔 FCM: Checking admin status for user: $currentUserId');

      // Fetch admin list from Firestore with timeout
      final doc = await FirebaseFirestore.instance
          .collection('Admins')
          .doc('admins')
          .get()
          .timeout(
            Duration(seconds: 5),
            onTimeout: () {
              debugPrint('⚠️ FCM: Admin check timed out');
              throw TimeoutException('Admin check timed out');
            },
          );

      final adminsRaw = doc.data()?['admins'];
      final admins = adminsRaw is List ? adminsRaw : <dynamic>[];
      debugPrint('🔔 FCM: Admin list: $admins');

      // Handle both string UIDs and other types (Firestore can return various formats)
      final isAdmin = admins.any((a) => a?.toString() == currentUserId);
      if (isAdmin) {
        // User is admin - subscribe to Admin topic
        await FirebaseMessaging.instance.subscribeToTopic('Admin');
        debugPrint('🔔 FCM: ✅ User IS ADMIN - subscribed to Admin topic');
      } else {
        debugPrint(
          '🔔 FCM: User is NOT admin, skipping Admin topic subscription',
        );
      }
    } catch (e) {
      debugPrint('⚠️ FCM: Error checking admin status: $e');
      // Don't rethrow - this is non-critical
    }
  }

  /// Public method to manually trigger admin topic subscription check
  /// Call this from home screen after user data is loaded
  static Future<void> checkAndSubscribeAdminTopic() async {
    await _checkAndSubscribeAdminTopic();
  }

  static Future<void> _saveFcmTokenToFirestore(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('⚠️ FCM: No user logged in, skipping token save');
      return;
    }
    if (token.length < _minValidFcmTokenLength) {
      debugPrint('⚠️ FCM: Token too short (${token.length}), not saving');
      return;
    }
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(uid)
          .get();

      final existingToken = userDoc.data()?['fcmToken'];
      if (existingToken == token) {
        debugPrint('🔔 FCM: Token already up to date');
        return;
      }

      await FirebaseFirestore.instance.collection('Users').doc(uid).update({
        'fcmToken': token,
      });
      debugPrint(
        '🔔 FCM: Token saved (${token.substring(0, 20)}… ${token.length} chars)',
      );
    } catch (e) {
      debugPrint('🔔 FCM: Error saving token: $e');
    }
  }

  /// Save device FCM token to `Users/{uid}.fcmToken` (Android + iOS).
  static Future<void> _persistFcmTokenToFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint('⚠️ FCM: No user logged in, skipping token add');
        return;
      }

      final fcm = FirebaseMessaging.instance;
      String? token;

      if (Platform.isIOS) {
        final settings = await fcm.getNotificationSettings();
        final ok =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
        if (!ok) {
          debugPrint('⚠️ FCM: iOS notifications not authorized');
          return;
        }
        // FCM on iOS needs APNs token first (can be briefly null right after grant).
        var apns = await fcm.getAPNSToken();
        if (apns == null) {
          await Future<void>.delayed(const Duration(seconds: 2));
          apns = await fcm.getAPNSToken();
        }
        if (apns == null) {
          debugPrint(
            '⚠️ FCM: APNs token not ready — will retry on next app open / refresh',
          );
          return;
        }
        token = await fcm.getToken();
      } else {
        final status = await Permission.notification.status;
        if (!status.isGranted) {
          debugPrint('⚠️ FCM: Android notification permission not granted');
          return;
        }
        token = await fcm.getToken();
      }

      if (token == null || token.length < _minValidFcmTokenLength) {
        debugPrint(
          '⚠️ FCM: Invalid token (${token?.length ?? 0} chars) — not saving',
        );
        return;
      }

      await _saveFcmTokenToFirestore(token);
    } catch (e) {
      debugPrint('🔔 FCM: Error persisting token: $e');
    }
  }

  /// Call this AFTER UI is ready (for handling pending notifications)
  /// This does NOT request permission - just checks if it's granted
  static Future<void> onAppReady() async {
    print('📢 FCM: onAppReady() called');

    // Check if permission is granted and initialize if needed
    bool permissionGranted = false;
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      permissionGranted = status.isGranted;
    } else {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      permissionGranted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    }

    if (permissionGranted) {
      await _persistFcmTokenToFirestore();

      if (!_permissionRequested) {
        print('✅ FCM: Permission already granted, initializing FCM...');
        await init();
      }

      // Ensure admin users are subscribed to Admin topic for bot notifications
      await _checkAndSubscribeAdminTopic();
    }

    // Try to handle any pending notifications
    _tryHandlePending();
  }

  static void _tryHandlePending() {
    if (_pendingMessage == null) return;

    final navigator = MyApp.navigatorKey.currentState;
    if (navigator == null) return;

    handlePushNotification(_pendingMessage!);
    _pendingMessage = null;
  }
}

void handlePushNotification(RemoteMessage message) {
  try {
    final navigator = MyApp.navigatorKey.currentState;

    if (navigator == null) return;
    final title = message.notification?.title ?? "";
    final uid = message.data["uid"]?.toString();

    debugPrint('🔔 [FCM] Handling notification - Title: "$title", UID: $uid');

    if (title.contains("Spam message Detected")) {
      navigator.push(MaterialPageRoute(builder: (_) => Spamers()));
    } else if (title.contains("Support Message Response")) {
      navigator.push(
        MaterialPageRoute(builder: (_) => SupportScreen(canPop: true)),
      );
    } else if (title.contains("Support Message from")) {
      navigator.push(MaterialPageRoute(builder: (_) => AdminChatRooms()));
    } else if (title == "BOTs") {
      // Bot notification - uid is viewer's or bot's uid
      if (uid != null && uid.isNotEmpty) {
        debugPrint('🔔 [FCM] Opening profile: $uid');
        navigator.push(
          MaterialPageRoute(
            builder: (_) => NewProfileView(uid: uid, canPop: true),
          ),
        );
      } else {
        debugPrint(
          '⚠️ [FCM] BOTs notification missing uid, skipping navigation',
        );
      }
    } else if (title.contains("BOTs")) {
      // Bot chat notification
      if (uid != null && uid.isNotEmpty) {
        navigator.push(
          MaterialPageRoute(builder: (_) => BotChatsScreen(botId: uid)),
        );
      }
    } else if (title.contains("Message from")) {
      if (uid != null && uid.isNotEmpty) {
        navigator.push(
          MaterialPageRoute(builder: (_) => NewMessagesScreen(uId: uid)),
        );
      }
    } else if (uid != null && uid.isNotEmpty) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => NewProfileView(uid: uid, canPop: true),
        ),
      );
    }
  } catch (e) {
    print(e.toString());
  }
}
