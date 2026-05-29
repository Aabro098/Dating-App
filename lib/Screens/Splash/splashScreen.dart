import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:viora/Screens/CompleteProfile/completeProfile.dart';
import 'package:viora/Screens/Home/home.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/Services/FCMServie.dart';
import 'package:viora/Services/SubscriptionService.dart';
import 'package:viora/Services/session_service.dart';
import 'package:viora/components/PermissionDialog.dart';
import 'package:viora/constants.dart';
import 'package:viora/size_config.dart';
import '../Login_Signup/loginScreen.dart';

/// Request notification permission during splash screen
/// This runs before any navigation happens
Future<void> _requestNotificationPermission(BuildContext context, Globals globals) async {
  // Check if notification permission was already requested this session
  if (PermissionSessionManager.isNotificationRequestedThisSession()) {
    debugPrint('🔒 [SPLASH] Notification already requested this session, skipping');
    return;
  }
  
  // Check if already denied this session - don't ask again
  if (PermissionSessionManager.isNotificationDeniedThisSession()) {
    debugPrint('🚫 [SPLASH] Notification already denied this session, skipping');
    return;
  }
  
  // Get current notification status
  var status = await Permission.notification.status;
  
  // If permission is granted, update preferences and return
  if (status.isGranted) {
    if (!globals.prefs.notificationPermissionGranted.value) {
      await globals.prefs.notificationPermissionGranted.set(true);
    }
    
    // Initialize FCM if not already initialized
    debugPrint('📞 [SPLASH] Permission already granted, ensuring FCM is initialized');
    await FCMService.onPermissionGranted();
    return;
  }
  
  // Check how many times user has denied
  final denialCount = globals.prefs.notificationDenialCount.value;
  
  // If permanently denied, skip splash dialog - will show custom dialog in home screen
  // DON'T mark as requested so home screen can handle it
  if (status.isPermanentlyDenied) {
    debugPrint('🚫 [SPLASH] Notification permanently denied - will show custom dialog in Home screen');
    return;
  }
  
  // Mark as requested for this session (only for non-permanently-denied cases)
  PermissionSessionManager.markNotificationRequestedThisSession();
  
  if (denialCount >= 2) {
    // After 2 denials, show custom dialog with settings
    if (context.mounted) {
      debugPrint('🔔 [SPLASH] Requesting notification (custom dialog)');
      final granted = await PermissionDialog.show(
        context,
        type: PermissionType.notification,
      );
      debugPrint('✅ [SPLASH] User responded: $granted');
      
      if (granted == true) {
        await globals.prefs.notificationPermissionGranted.set(true);
        await globals.prefs.notificationDenialCount.set(0);
        
        // Initialize FCM after permission is granted
        debugPrint('📞 [SPLASH] Initializing FCM after permission granted (custom dialog)');
        await FCMService.onPermissionGranted();
      } else {
        PermissionSessionManager.markNotificationDeniedThisSession();
      }
    }
  } else {
    // Less than 2 denials, use system dialog
    if (context.mounted) {
      debugPrint('🔔 [SPLASH] Requesting notification (system dialog)');
      status = await Permission.notification.request();
      debugPrint('✅ [SPLASH] User responded: $status');
      
      if (status.isGranted) {
        await globals.prefs.notificationPermissionGranted.set(true);
        await globals.prefs.notificationDenialCount.set(0);
        
        // Initialize FCM after permission is granted
        debugPrint('📞 [SPLASH] Initializing FCM after permission granted');
        await FCMService.onPermissionGranted();
      } else {
        // Increment denial count
        final newCount = denialCount + 1;
        await globals.prefs.notificationDenialCount.set(newCount);
        PermissionSessionManager.markNotificationDeniedThisSession();
        debugPrint('❌ [SPLASH] Notification denied. Count: $newCount');
      }
    }
  }
}

class SplashScreen extends HookWidget {
  static String routeName = "/splash";

  @override
  Widget build(BuildContext context) {
    final globals = Globals.of(context);

    useEffect(() {
      Future<void> initializeAndNavigate() async {
        try {
          debugPrint("⚡ START: Splash screen initialization");
          final splashStart = DateTime.now();
          
          // ⚡ OVERALL TIMEOUT: Maximum 15 seconds for entire splash flow
          await Future.any([
            _performInitialization(context, globals, splashStart),
            Future.delayed(Duration(seconds: 15)).then((_) {
              debugPrint("⚠️ CRITICAL: Splash timeout after 15s - forcing navigation");
              throw TimeoutException('Splash initialization timeout');
            }),
          ]);
        } catch (e, stackTrace) {
          debugPrint("❌ Error during initialization: $e\n$stackTrace");
          
          // Always remove native splash on error
          FlutterNativeSplash.remove();
          
          if (e is TimeoutException) {
            // On timeout, navigate to login as fallback
            if (context.mounted) {
              debugPrint("⚠️ Timeout occurred - navigating to login screen");
              Navigator.pushAndRemoveUntil(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => LoginScreen(),
                  transitionDuration: Duration.zero,
                ),
                (route) => false,
              );
            }
          } else {
            // Show error dialog for other errors
            if (context.mounted) {
              _showErrorDialog(context, e.toString());
            }
          }
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        initializeAndNavigate();
      });

      return null;
    }, []);

    // This UI is now only seen if you navigate BACK to Splash manually
    // or if an error dialog pops up.
    return Scaffold(
      backgroundColor: kPrimaryPurple, 
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Image.asset(
              "assets/icon/icon.png",
              width: getProportionateScreenHeight(300),
              height: getProportionateScreenHeight(300),
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            bottom: 40, 
            left: 0,
            right: 0,
            child: Column(
              children: [
                Image.asset(
                  "assets/splash/branding.png",
                  fit: BoxFit.contain,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performInitialization(
    BuildContext context,
    Globals globals,
    DateTime splashStart,
  ) async {
    // ⚡ OPTIMIZATION: Reduced timeout from 10s to 7s
    final initLogic = Future<bool>(() async {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      // Enforce per-device session limit: if this device's session is invalid,
      // sign out locally and treat the user as logged out.
      final isSessionValid = await SessionService.isCurrentSessionValid();
      if (!isSessionValid) {
        debugPrint(
            "⚠️ Session for this device is invalid or revoked - signing out");
        await FirebaseAuth.instance.signOut();
        return false;
      }

      debugPrint("✅ User authenticated: ${currentUser.uid}");
      return await globals.initializeUserData(context, true);
    }).timeout(
      Duration(seconds: 7),
      onTimeout: () {
        debugPrint("⚠️ User data initialization timed out after 7s");
        return false;
      },
    );

    final bool? hasProfileOrLoggedIn = await initLogic;
    final currentUser = FirebaseAuth.instance.currentUser;

    final splashElapsed = DateTime.now().difference(splashStart).inMilliseconds;
    debugPrint("⚡ Splash initialization took ${splashElapsed}ms");

    // -----------------------------------------------------------
    // STEP 1: Request notification permission BEFORE navigation
    // This ensures FCM is set up early in the app lifecycle
    // Add timeout to prevent hanging
    // -----------------------------------------------------------
    if (context.mounted) {
      debugPrint('🔔 [SPLASH] Requesting notification permission...');
      try {
        await _requestNotificationPermission(context, globals).timeout(
          Duration(seconds: 10),
          onTimeout: () {
            debugPrint('⚠️ [SPLASH] Notification permission request timed out after 10s');
          },
        );
        debugPrint('✅ [SPLASH] Notification permission flow complete');
      } catch (e) {
        debugPrint('⚠️ [SPLASH] Notification permission error: $e');
        // Continue anyway - notification is optional
      }
    }

    // ⚠️ KEY: Remove native splash BEFORE navigation to prevent stuck state
    debugPrint("🎬 Removing native splash before navigation");
    try {
      FlutterNativeSplash.remove();
    } catch (e) {
      debugPrint("⚠️ Error removing native splash: $e");
    }

    // Small delay to ensure splash removal completes
    await Future.delayed(Duration(milliseconds: 100));

    if (!context.mounted) return;

    void navigateWithoutAnimation(String routeName) {
      Navigator.pushAndRemoveUntil(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) {
            // Return the actual Widget for the route
            if (routeName == Home.routeName) return Home();
            if (routeName == LoginScreen.routeName) return LoginScreen();
            if (routeName == CompleteProfile.routeName) return CompleteProfile();
            return LoginScreen();
          },
          transitionDuration: Duration.zero, // ⚡ NO ANIMATION
          reverseTransitionDuration: Duration.zero,
        ),
        (route) => false,
      );
    }

    if (currentUser == null) {
      debugPrint("⚡ Navigating to Login");
      navigateWithoutAnimation(LoginScreen.routeName);
    } else {
      final hasProfile = hasProfileOrLoggedIn ?? false;

      if (hasProfile) {
        try {
          await SubscriptionService.refreshRevenueCatIdentity(currentUser.uid);
          debugPrint("✅ [SPLASH] RevenueCat identity refreshed for ${currentUser.uid}");
        } catch (e) {
          debugPrint("⚠️ [SPLASH] RevenueCat sync error: $e");
        }
        debugPrint("⚡ Navigating to Home (profile complete)");
        navigateWithoutAnimation(Home.routeName);
      } else {
        // If profile is incomplete, navigate to Login screen instead of CompleteProfile
        debugPrint("⚡ Profile incomplete, navigating to Login");
        navigateWithoutAnimation(LoginScreen.routeName);
      }
    }
  }

  void _showErrorDialog(BuildContext context, String error) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: Text("Initialization Error"),
        content: Text(error),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              final globals = Globals.of(context);
              globals.resetInitialization();
              Navigator.pushReplacementNamed(context, SplashScreen.routeName);
            },
            child: Text("RETRY"),
          ),
          TextButton(
            onPressed: () async {
               Navigator.of(context).pop();
               await SubscriptionService.logOutRevenueCat();
               await FirebaseAuth.instance.signOut();
               Navigator.pushReplacementNamed(context, LoginScreen.routeName);
            },
            child: Text("LOGOUT"),
          )
        ],
      ),
    );
  }
}