import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:viora/Services/SubscriptionService.dart';
import 'package:viora/Services/UserProvider.dart';
import 'package:viora/Services/prefs.dart';
import 'package:viora/Services/purchase_repository.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:math';

final deviceInfoPlugin = DeviceInfoPlugin();

class Globals {
  Globals._(
    this.prefs, {
    required this.iosDeviceInfo,
    required this.androidDeviceInfo,
    required this.userProvider,
  });

  static Globals of(BuildContext context) =>
      Provider.of<Globals>(context, listen: false);

  final Prefs prefs;
  final IosDeviceInfo? iosDeviceInfo;
  final AndroidDeviceInfo? androidDeviceInfo;
  final UserProvider userProvider;

  // Track initialization state
  bool _isUserInitialized = false;
  bool get isUserInitialized => _isUserInitialized;

  static Future<Globals> init() async {
    debugPrint("⚡ START: Globals initialization");
    final startTime = DateTime.now();
    
    // ⚡ OPTIMIZATION: Run Firebase init and SharedPreferences in parallel with device info
    final results = await Future.wait([
      Firebase.apps.isEmpty ? Firebase.initializeApp() : Future.value(null),
      SharedPreferences.getInstance(),
      _getDeviceInfo(),
    ]);

    final prefs = Prefs(results[1] as SharedPreferences);
    final deviceInfo = results[2] as Map<String, dynamic>;
    final userProvider = UserProvider();
    
    // Initialize permission session tracking (resets on hot restart/app restart)
    PermissionSessionManager.initializeSession(prefs);
    
    // Initialize PurchaseRepository in background (don't wait)
    PurchaseRepository().initialize().catchError((e) {
      debugPrint("Purchase initialization error: $e");
    });

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    debugPrint("⚡ DONE: Globals init in ${elapsed}ms");

    return Globals._(
      prefs,
      iosDeviceInfo: deviceInfo['ios'] as IosDeviceInfo?,
      androidDeviceInfo: deviceInfo['android'] as AndroidDeviceInfo?,
      userProvider: userProvider,
    );
  }

  /// Get device info in a non-blocking way
  static Future<Map<String, dynamic>> _getDeviceInfo() async {
    IosDeviceInfo? iosInfo;
    AndroidDeviceInfo? androidInfo;
    
    try {
      iosInfo = await deviceInfoPlugin.iosInfo;
    } catch (_) {}

    try {
      androidInfo = await deviceInfoPlugin.androidInfo;
    } catch (_) {}
    
    return {'ios': iosInfo, 'android': androidInfo};
  }

  /// Initialize user data - MUST be called before navigating to Home
  /// Returns true if user document exists, false if needs profile completion
  Future<bool> initializeUserData(BuildContext context,bool fromSplash) async {
    // if (_isUserInitialized && !fromSplash) {
    //   debugPrint("Vinay User already initialized, skipping...");
    //   return true;
    // }

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('No authenticated user');
      }

      print("Initializing user data for UID: ${currentUser.uid}");

      // This will load user data and return whether profile exists
      final hasProfile = await userProvider.initializeUserDetails(context);

      _isUserInitialized = true;

      // Warm subscription UI (Firestore + RevenueCat) in background so Payment tab is faster.
      SubscriptionService.preloadSubscriptionDisplayForUser(currentUser.uid);

      return hasProfile;
    } catch (e, stackTrace) {
      print("Error initializing user data: $e\n$stackTrace");
      _isUserInitialized = false;
      rethrow;
    }
  }

  /// Reset initialization state (useful for logout/login flows)
  /// CRITICAL: Must be called on logout/account deletion to prevent data mixing
  void resetInitialization() {
    _isUserInitialized = false;
    SubscriptionService.invalidateSubscriptionDisplayCache();
    // Detach RevenueCat from previous Firebase user (strict ownership / shared device)
    unawaited(
      SubscriptionService.logOutRevenueCat().catchError((Object e) {
        debugPrint('⚠️ RevenueCat logOut during session reset: $e');
      }),
    );
    // Cancel Firestore subscription and reset user state
    userProvider.resetUserState();
    // Reset permission session flags when user logs out/switches account
    PermissionSessionManager.resetAllSessions(prefs);
    debugPrint('🔄 Globals initialization reset complete');
  }
}

/// Manages permission request session flags to ensure permissions are only requested once per session
/// 
/// A "session" is defined as the lifetime of the app from launch to close.
/// On hot restart (development) or app restart, the session is reset.
class PermissionSessionManager {
  // Session ID to detect app restarts/hot restarts
  // Uses timestamp + random value to ensure uniqueness even on rapid hot restarts
  static final int _currentSessionId = DateTime.now().millisecondsSinceEpoch + Random().nextInt(1000000);
  
  // Location permission session flags
  static bool _locationPermissionRequestedInCompleteProfileSession = false;
  static bool _locationPermissionRequestedInHomeSession = false;
  
  // Permission denial tracking (per session)
  static bool _locationDeniedThisSession = false;
  static bool _notificationDeniedThisSession = false;
  static bool _smsDeniedThisSession = false;
  
  // Track notification permission request for session
  static bool _notificationPermissionRequestedThisSession = false;
  
  // Track safety tips shown in this session
  static bool _safetyTipsShownThisSession = false;
  
  /// Initialize session - call this on app start to reset session-based flags
  /// This ensures that hot restart or app restart resets all session tracking
  static void initializeSession(Prefs prefs) {
    // Check if this is a new session by comparing stored session ID
    final storedSessionId = prefs.currentSessionId.value;
    
    debugPrint('🔄 [SESSION] Checking session: stored=$storedSessionId, current=$_currentSessionId');
    
    if (storedSessionId != _currentSessionId) {
      // New session detected - reset all session flags (hot restart, app restart, or login)
      debugPrint('🔄 [SESSION] ⚡ NEW SESSION DETECTED! (hot restart, app restart, or login)');
      
      _locationPermissionRequestedInCompleteProfileSession = false;
      _locationPermissionRequestedInHomeSession = false;
      _locationDeniedThisSession = false;
      _notificationDeniedThisSession = false;
      _smsDeniedThisSession = false;
      _notificationPermissionRequestedThisSession = false;
      _safetyTipsShownThisSession = false;
      
      // Store the new session ID
      prefs.currentSessionId.set(_currentSessionId);
      
      debugPrint('✅ [SESSION] Session initialized successfully');
    } else {
      debugPrint('ℹ️ [SESSION] Continuing existing session (ID: $_currentSessionId)');
    }
  }
  
  /// Reset location permission session flag for CompleteProfile
  static void resetCompleteProfileSession() {
    _locationPermissionRequestedInCompleteProfileSession = false;
    debugPrint('🔄 [SESSION] CompleteProfile location session reset');
  }
  
  /// Reset location permission session flag for Home
  static void resetHomeSession() {
    _locationPermissionRequestedInHomeSession = false;
    debugPrint('🔄 [SESSION] Home location session reset');
  }
  
  /// Reset all permission session flags (called on logout/login)
  /// Also clears the persistent locationPermissionDenied preference for new user
  static void resetAllSessions(Prefs prefs) {
    _locationPermissionRequestedInCompleteProfileSession = false;
    _locationPermissionRequestedInHomeSession = false;
    _locationDeniedThisSession = false;
    _notificationDeniedThisSession = false;
    _safetyTipsShownThisSession = false; // ← Reset safety tips on logout
    // Clear the persistent denial state so new user gets fresh permission prompts
    prefs.locationPermissionDenied.set(false);
    debugPrint('🔄 [SESSION] All permission sessions reset + location denial cleared');
    debugPrint('🛡️ [SESSION] Safety tips session cleared for logout/login');
  }
  
  /// Reset safety tips session specifically (for logout/account deletion)
  /// This ensures user sees safety tips again on next login
  static void resetSafetyTipsSession() {
    _safetyTipsShownThisSession = false;
    debugPrint('🛡️ [SESSION] Safety tips session cleared (logout/account deletion) - will show on next login');
  }
  
  /// Check if location permission was already requested in CompleteProfile session
  static bool isLocationRequestedInCompleteProfile() {
    return _locationPermissionRequestedInCompleteProfileSession;
  }
  
  /// Mark location permission as requested in CompleteProfile session
  static void markLocationRequestedInCompleteProfile() {
    _locationPermissionRequestedInCompleteProfileSession = true;
  }
  
  /// Check if location permission was already requested in Home session
  static bool isLocationRequestedInHome() {
    return _locationPermissionRequestedInHomeSession;
  }
  
  /// Mark location permission as requested in Home session
  static void markLocationRequestedInHome() {
    _locationPermissionRequestedInHomeSession = true;
  }
  
  // --- Permission Denial Tracking ---
  
  /// Check if location permission was denied in this session
  static bool isLocationDeniedThisSession() => _locationDeniedThisSession;
  
  /// Mark location permission as denied for this session
  static void markLocationDeniedThisSession() {
    _locationDeniedThisSession = true;
    debugPrint('🚫 [SESSION] Location permission denied for this session');
  }
  
  /// Check if notification permission was denied in this session  
  static bool isNotificationDeniedThisSession() => _notificationDeniedThisSession;
  
  /// Mark notification permission as denied for this session
  static void markNotificationDeniedThisSession() {
    _notificationDeniedThisSession = true;
    debugPrint('🚫 [SESSION] Notification permission denied for this session');
  }
  
  /// Check if SMS permission was denied in this session
  static bool isSmsDeniedThisSession() => _smsDeniedThisSession;
  
  /// Mark SMS permission as denied for this session
  static void markSmsDeniedThisSession() {
    _smsDeniedThisSession = true;
    debugPrint('🚫 [SESSION] SMS permission denied for this session');
  }
  
  /// Check if notification permission was requested in this session
  static bool isNotificationRequestedThisSession() => _notificationPermissionRequestedThisSession;
  
  /// Mark notification permission as requested for this session
  static void markNotificationRequestedThisSession() {
    _notificationPermissionRequestedThisSession = true;
    debugPrint('📍 [SESSION] Notification permission marked as requested for this session');
  }
  
  /// Check if safety tips were shown in this session
  static bool isSafetyTipsShownThisSession() => _safetyTipsShownThisSession;
  
  /// Mark safety tips as shown for this session
  static void markSafetyTipsShownThisSession() {
    _safetyTipsShownThisSession = true;
    debugPrint('🛡️ [SESSION] Safety tips marked as shown for this session');
  }
}
