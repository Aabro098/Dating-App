import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:viora/Screens/Home/homeScreen.dart';
import 'package:viora/Services/AppConfigService.dart';
import 'package:viora/Services/AuthService.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/Services/FCMServie.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/Services/PhoneAuthService.dart';
import 'package:viora/Services/SubscriptionService.dart';

enum SessionRegisterStatus {
  reusedExisting,
  createdNew,
  requiresReplacement,
  maxZero, // Added: When device limit is 0
}

class SessionRegisterResult {
  final SessionRegisterStatus status;
  final String? message;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> activeSessions;

  const SessionRegisterResult({
    required this.status,
    this.message,
    this.activeSessions = const [],
  });

  bool get needsUserConfirmation =>
      status == SessionRegisterStatus.requiresReplacement;

  bool get maxZero => status == SessionRegisterStatus.maxZero;
}

class SessionService {
  SessionService._();

  static const String _deviceIdKey = 'device_id_v2';
  static const String _sessionIdKey = 'session_id_v2';

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  // Real-time device limit monitoring
  static StreamSubscription<int>? _limitWatchSubscription;

  static bool _isPermissionDeniedError(Object error) {
    return error is FirebaseException && error.code == 'permission-denied';
  }

  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();

    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    String newId;
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      newId = androidInfo.id;
    } else if (Platform.isIOS) {
      final deviceInfo = DeviceInfoPlugin();
      final iosInfo = await deviceInfo.iosInfo;
      newId = iosInfo.identifierForVendor ?? const Uuid().v4();
    } else {
      newId = const Uuid().v4();
    }
    // final newId = const Uuid().v4();
    await prefs.setString(_deviceIdKey, newId);
    return newId;
  }

  static Future<String?> _getSavedSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionIdKey);
  }

  static Future<void> _saveSessionId(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionIdKey, sessionId);
  }

  static Future<void> clearSavedSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionIdKey);
  }

  // static Future<int> _getMaxActiveDevicesFromConfig() async {
  //   return AppConfigService.maxActiveDevices;
  // }

  /// Fetch the current max active devices limit directly from Firestore
  /// This ensures we always get the latest limit, not a cached value
  static Future<int> _getMaxActiveDevicesFromFirestore() async {
    try {
      final doc = await _firestore
          .collection('AppConfig')
          .doc('deviceLimit')
          .get(const GetOptions(source: Source.server));

      if (doc.exists) {
        final limit = doc.data()?['limit'] as int? ?? 2;
        _log('Fetched device limit from Firestore: $limit');
        return limit;
      }
    } catch (e) {
      _log('Error fetching device limit from Firestore: $e');
    }

    // Fallback to cached value if Firestore fetch fails
    return AppConfigService.maxActiveDevices;
  }

  /// Watch the max active devices limit in real-time
  /// This stream emits the limit whenever it changes in Firestore
  static Stream<int> watchMaxActiveDeviceLimit() {
    return _firestore
        .collection('AppConfig')
        .doc('deviceLimit')
        .snapshots()
        .map((snapshot) {
          if (snapshot.exists) {
            final limit = snapshot.data()?['limit'] as int? ?? 2;
            _log('Device limit updated: $limit');
            return limit;
          }
          return 2; // fallback
        });
  }

  /// Enforces the device limit by removing excess sessions in FIFO order
  /// This is called when the limit decreases
  static Future<void> enforceDeviceLimitForCurrentUser(int newLimit) async {
    try {
      final sessionsRef = await _sessionsRef();
      final activeSessions = await _getActiveSessions(sessionsRef);

      if (activeSessions.length <= newLimit) {
        _log(
          'No sessions to remove. Current: ${activeSessions.length}, Limit: $newLimit',
        );
        return;
      }

      final sessionsToRemoveCount = activeSessions.length - newLimit;
      _log(
        'Removing $sessionsToRemoveCount sessions to enforce limit $newLimit',
      );

      final batch = _firestore.batch();

      // Remove oldest sessions first (FIFO)
      for (int i = 0; i < sessionsToRemoveCount; i++) {
        final doc = activeSessions[i];
        batch.update(doc.reference, {
          'revoked': true,
          'revokedAt': FieldValue.serverTimestamp(),
          'revokedReason': 'device_limit_decreased',
        });
        _log('Marked session ${doc.id} for revocation (FIFO order)');
      }

      await batch.commit();
      _log(
        '$sessionsToRemoveCount sessions revoked due to device limit reduction',
      );
    } catch (e) {
      _log('Failed to enforce device limit: $e');
      rethrow;
    }
  }

  /// Initialize real-time monitoring of device limit changes
  /// This automatically enforces the new limit for the current user when it decreases
  static StreamSubscription<int> startMonitoringDeviceLimitChanges() {
    _limitWatchSubscription?.cancel();

    int? previousLimit;

    _limitWatchSubscription = watchMaxActiveDeviceLimit().listen(
      (newLimit) async {
        if (previousLimit == null) {
          previousLimit = newLimit;
          return;
        }

        if (newLimit < previousLimit!) {
          _log(
            'Device limit decreased from $previousLimit to $newLimit. Enforcing new limit...',
          );
          try {
            await enforceDeviceLimitForCurrentUser(newLimit);
          } catch (e) {
            _log('Error enforcing device limit: $e');
          }
        }

        previousLimit = newLimit;
      },
      onError: (e) {
        _log('Error monitoring device limit: $e');
      },
    );

    return _limitWatchSubscription!;
  }

  /// Stop monitoring device limit changes
  static Future<void> stopMonitoringDeviceLimitChanges() async {
    await _limitWatchSubscription?.cancel();
    _limitWatchSubscription = null;
    _log('Stopped monitoring device limit changes');
  }

  static Future<Map<String, dynamic>> _getDeviceDetailMap() async {
    final map = <String, dynamic>{
      'platform': Platform.isAndroid
          ? 'android'
          : Platform.isIOS
          ? 'ios'
          : 'other',
    };

    try {
      if (Platform.isAndroid) {
        final android = await _deviceInfo.androidInfo;

        map.addAll({
          'deviceName': android.model.isNotEmpty
              ? android.model
              : android.device,
          'model': android.model,
          'brand': android.brand,
          'manufacturer': android.manufacturer,
          'osVersion': android.version.release,
          'sdkInt': android.version.sdkInt,
          'device': android.device,
          'display': android.display,
          'hardware': android.hardware,
          'product': android.product,
        });
      } else if (Platform.isIOS) {
        final ios = await _deviceInfo.iosInfo;

        map.addAll({
          'deviceName': ios.name,
          'model': ios.model,
          'osVersion': ios.systemVersion,
          'systemName': ios.systemName,
          'utsname': ios.utsname.machine,
        });

        if (ios.identifierForVendor != null) {
          map['identifierForVendor'] = ios.identifierForVendor;
        }
      }
    } catch (e) {
      map['deviceInfoError'] = e.toString();
    }

    try {
      final pkg = await PackageInfo.fromPlatform();

      map.addAll({
        'appVersion': pkg.version,
        'appBuildNumber': pkg.buildNumber,
        'appName': pkg.appName,
        'packageName': pkg.packageName,
      });
    } catch (e) {
      map['appInfoError'] = e.toString();
    }

    return map;
  }

  static Future<User> _requireCurrentUser() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-authenticated-user',
        message: 'No authenticated user found.',
      );
    }

    await user.getIdToken(true);
    return user;
  }

  static Future<CollectionReference<Map<String, dynamic>>>
  _sessionsRef() async {
    final user = await _requireCurrentUser();
    return _firestore.collection('Users').doc(user.uid).collection('Sessions');
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _getActiveSessions(
    CollectionReference<Map<String, dynamic>> sessionsRef,
  ) async {
    final snapshot = await sessionsRef
        .where('revoked', isEqualTo: false)
        .orderBy('createdAt', descending: false) // oldest first = FIFO
        .get(const GetOptions(source: Source.server));

    return snapshot.docs;
  }

  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?>
  _findSessionForDevice(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> activeSessions,
    String deviceId,
  ) async {
    for (final doc in activeSessions) {
      final data = doc.data();
      if (data['deviceId'] == deviceId) {
        return doc;
      }
    }
    return null;
  }

  static Future<DocumentReference<Map<String, dynamic>>> _createSessionDoc(
    CollectionReference<Map<String, dynamic>> sessionsRef,
    String deviceId,
  ) async {
    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isIOS
        ? 'ios'
        : 'other';

    final deviceDetail = await _getDeviceDetailMap();

    return sessionsRef.add({
      'deviceId': deviceId,
      'createdAt': FieldValue.serverTimestamp(),
      'lastActive': FieldValue.serverTimestamp(),
      'revoked': false,
      'platform': platform,
      'deviceDetail': deviceDetail,
    });
  }

  /// Call this right after auth sign-in.
  /// This does NOT replace another session automatically.
  /// It returns a result so the UI can decide.
  static Future<SessionRegisterResult> prepareSessionForCurrentUser() async {
    final deviceId = await getOrCreateDeviceId();
    final sessionsRef = await _sessionsRef();
    // Use fresh limit from Firestore to ensure we respect the current limit
    final maxActiveDevices = await _getMaxActiveDevicesFromFirestore();

    // Check if device limit is 0 (no devices allowed)
    if (maxActiveDevices == 0) {
      _log('Device limit is 0. Login not allowed.');
      return SessionRegisterResult(
        status: SessionRegisterStatus.maxZero,
        message: 'Login is currently disabled. Please try again later.',
      );
    }

    final activeSessions = await _getActiveSessions(sessionsRef);

    final existingForThisDevice = await _findSessionForDevice(
      activeSessions,
      deviceId,
    );

    if (existingForThisDevice != null) {
      await _saveSessionId(existingForThisDevice.id);
      await existingForThisDevice.reference.update({
        'lastActive': FieldValue.serverTimestamp(),
      });

      _log('Existing session reused for this device');

      return SessionRegisterResult(
        status: SessionRegisterStatus.reusedExisting,
      );
    }

    if (activeSessions.length < maxActiveDevices) {
      final newDoc = await _createSessionDoc(sessionsRef, deviceId);
      await _saveSessionId(newDoc.id);

      _log('New session created: ${newDoc.id}');

      return SessionRegisterResult(status: SessionRegisterStatus.createdNew);
    }

    return SessionRegisterResult(
      status: SessionRegisterStatus.requiresReplacement,
      message: 'Another device is already logged in to this account.',
      activeSessions: activeSessions,
    );
  }

  /// Call this ONLY after the user confirms replacement in a dialog.
  static Future<void> confirmSessionReplacementForCurrentUser() async {
    final deviceId = await getOrCreateDeviceId();
    final sessionsRef = await _sessionsRef();
    // Use fresh limit from Firestore to ensure we respect the current limit
    final maxActiveDevices = await _getMaxActiveDevicesFromFirestore();

    final activeSessions = await _getActiveSessions(sessionsRef);

    final existingForThisDevice = await _findSessionForDevice(
      activeSessions,
      deviceId,
    );

    if (existingForThisDevice != null) {
      await _saveSessionId(existingForThisDevice.id);
      await existingForThisDevice.reference.update({
        'lastActive': FieldValue.serverTimestamp(),
      });
      return;
    }

    final sessionsToRemoveCount =
        (activeSessions.length - maxActiveDevices) + 1;

    if (sessionsToRemoveCount > 0) {
      final batch = _firestore.batch();

      for (int i = 0; i < sessionsToRemoveCount; i++) {
        final doc = activeSessions[i]; // oldest first
        batch.update(doc.reference, {
          'revoked': true,
          'revokedAt': FieldValue.serverTimestamp(),
          'revokedReason': 'replaced_by_new_login',
        });
      }

      await batch.commit();
    }

    final newDoc = await _createSessionDoc(sessionsRef, deviceId);
    await _saveSessionId(newDoc.id);

    _log('Replacement session created: ${newDoc.id}');
  }

  static Future<bool> isCurrentSessionValid() async {
    final user = _auth.currentUser;

    if (user == null) {
      await clearSavedSessionId();
      return false;
    }

    final uid = user.uid;
    final deviceId = await getOrCreateDeviceId();
    final sessionId = await _getSavedSessionId();

    if (sessionId == null || sessionId.isEmpty) {
      return false;
    }

    final docRef = _firestore
        .collection('Users')
        .doc(uid)
        .collection('Sessions')
        .doc(sessionId);

    try {
      final snapshot = await docRef.get(
        const GetOptions(source: Source.server),
      );

      if (!snapshot.exists) {
        await clearSavedSessionId();
        return false;
      }

      final data = snapshot.data();

      if (data == null) {
        await clearSavedSessionId();
        return false;
      }

      final revoked = data['revoked'] == true;
      final docDeviceId = data['deviceId'] as String?;

      if (revoked || docDeviceId != deviceId) {
        await clearSavedSessionId();
        return false;
      }

      await docRef.update({'lastActive': FieldValue.serverTimestamp()});
      return true;
    } catch (e) {
      _log('Session validation failed: $e');
      await clearSavedSessionId();
      return false;
    }
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>>? watchCurrentSession() {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }

    return Stream.fromFuture(_getSavedSessionId()).asyncExpand((sessionId) {
      if (sessionId == null || sessionId.isEmpty) {
        return const Stream.empty();
      }

      return _firestore
          .collection('Users')
          .doc(user.uid)
          .collection('Sessions')
          .doc(sessionId)
          .snapshots()
          .handleError((error) {
            if (_isPermissionDeniedError(error)) {
              _log(
                'Session watch permission denied (likely sign-out/deletion in progress).',
              );
              return;
            }
            throw error;
          });
    });
  }

  static Future<void> revokeCurrentSession() async {
    final user = _auth.currentUser;

    if (user == null) {
      await clearSavedSessionId();
      return;
    }

    final sessionId = await _getSavedSessionId();

    if (sessionId == null || sessionId.isEmpty) {
      await clearSavedSessionId();
      return;
    }

    final docRef = _firestore
        .collection('Users')
        .doc(user.uid)
        .collection('Sessions')
        .doc(sessionId);

    try {
      await docRef.update({
        'revoked': true,
        'revokedAt': FieldValue.serverTimestamp(),
        'revokedReason': 'user_logout',
      });
    } catch (e) {
      _log('Failed to revoke session: $e');
    } finally {
      await clearSavedSessionId();
    }
  }

  static Future<void> deleteCurrentSession() async {
    final user = _auth.currentUser;

    if (user == null) {
      await clearSavedSessionId();
      return;
    }

    final sessionId = await _getSavedSessionId();

    if (sessionId == null || sessionId.isEmpty) {
      await clearSavedSessionId();
      return;
    }

    try {
      await _firestore
          .collection('Users')
          .doc(user.uid)
          .collection('Sessions')
          .doc(sessionId)
          .delete();
    } catch (e) {
      _log('Failed to delete current session: $e');
    } finally {
      await clearSavedSessionId();
    }
  }

  static Future<void> forceLogoutLocally(Globals globals) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;

      // Stop monitoring device limit changes
      await stopMonitoringDeviceLimitChanges();

      await DatabaseService.handleOnlineStatue(false);
      await DatabaseService.deleteToken();
      await FCMService.resetOnLogout();

      if (uid != null) {
        await SubscriptionService.clearSubscriptionCacheOnLogout(uid: uid);
      }

      await GoogleAuth.logoutOnly();
      await PhoneAuth.logoutOnly();
      await clearSavedSessionId();
      await FirebaseAuth.instance.signOut();

      globals.resetInitialization();
      resetVerificationDialogFlag();
    } catch (e) {
      debugPrint('❌ [SESSION] Local logout cleanup failed: $e');

      // fallback cleanup
      try {
        await clearSavedSessionId();
      } catch (_) {}

      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
    }
  }

  static void _log(String message) {
    if (kDebugMode) {
      debugPrint('[SessionService] $message');
    }
  }
}
