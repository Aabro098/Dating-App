import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:viora/Screens/Login_Signup/loginScreen.dart';
import 'package:viora/Services/SubscriptionService.dart';
import 'package:viora/Screens/Home/homeScreen.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/Services/FCMServie.dart';
import 'package:viora/Services/PermissionManager.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:viora/Services/session_service.dart';
import '../../Services/Global.dart';
import '../../constants.dart';

/// ============================================================================
/// APP FLOW AFTER SIGN-UP (First Launch):
/// ============================================================================
/// 1. ✅ OTP Verification (OtpScreen)
/// 2. ✅ Phone Notification Permission (Home -> FCMService.init) - First Launch
/// 3. ✅ Location Permission Request (CompleteProfile -> requestLocationAndFetch)
/// 4. ✅ Complete Profile Form (CompleteProfile)
/// 5. ✅ Navigate to Home (DatabaseService.addUser)
/// 6. ✅ Verify Profile Dialog (HomeScreen) - If not verified (can be skipped)
/// 7. ✅ Safety Tips Dialog (HomeScreen) - After Verify Profile, Non-Dismissible
/// 8. ✅ Home Screen Content Loads
/// 9. ✅ General Notifications (FCM) - Active in background
/// ============================================================================

// ---------- Custom Hook for handling lifecycle and online status ----------
void useOnlineStatus(BuildContext context) {
  final globals = Globals.of(context);

  useEffect(() {
    final observer = _HooksBindingObserver(context);

    WidgetsBinding.instance.addObserver(observer);
    DatabaseService.handleOnlineStatue(true);

    try {
      final userDetails = globals.prefs.userDetails;
      final currentUser = userDetails.value;

      if ((currentUser?.uid ?? '').isNotEmpty) {
        SubscriptionService.refreshRevenueCatIdentity(
          currentUser!.uid,
        ).catchError((Object e) => debugPrint('RevenueCat refresh error: $e'));
      }
    } catch (e) {
      debugPrint('RevenueCat sync error: $e');
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 500));
      // await _updateLastDateIfNeeded();
      await FCMService.checkAndSubscribeAdminTopic();

      SessionService.startMonitoringDeviceLimitChanges();
    });

    return () {
      WidgetsBinding.instance.removeObserver(observer);
      SessionService.stopMonitoringDeviceLimitChanges();
    };
  }, []);
}

// Newly Added : May 25, 2026
void useWhoCanMessageSync(BuildContext context) {
  final globals = Globals.of(context);

  useEffect(() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return null;

    final uid = currentUser.uid;
    final userRef = FirebaseFirestore.instance.collection('Users').doc(uid);
    final subscriptionRef = userRef.collection('Subscription').doc('current');
    final freeFeaturesRef = FirebaseFirestore.instance
        .collection('Subscriptions')
        .doc('freeFeatures');

    Future<void> setWhoCanMessageAll() async {
      DatabaseService.updateField({'who_can_message': 'All'});

      final localUser = globals.prefs.userDetails.value;
      if (localUser != null && localUser.uid == uid) {
        localUser.messagePermission = 'All';
        await globals.prefs.userDetails.set(localUser);
      }
    }

    Future<void> evaluatePolicy({Map<String, dynamic>? userData}) async {
      final latestUserData = userData ?? (await userRef.get()).data();
      if (latestUserData == null) return;

      final currentPermission =
          latestUserData['who_can_message']?.toString().trim() ?? 'All';
      if (currentPermission == 'All') return;

      final subscriptionState =
          await SubscriptionService.getSubscriptionStateFromFirestore(uid);
      final subscriptionEnabled =
          subscriptionState?.isActive == true &&
          subscriptionState?.entitlementFeatures?.isFeatureEnabled(
                'who_can_message',
              ) ==
              true;
      if (subscriptionEnabled) {
        return;
      }

      final freeSnapshot = await freeFeaturesRef.get();
      final data = freeSnapshot.data();
      if (data == null) {
        await setWhoCanMessageAll();
        return;
      }

      final genderKey =
          latestUserData['gender']?.toString().toLowerCase() == 'female'
          ? 'female'
          : 'male';

      final genderData = data[genderKey] as Map<String, dynamic>?;
      final isEnabled = genderData?['isEnable'] as bool? ?? false;
      if (!isEnabled) {
        await setWhoCanMessageAll();
        return;
      }

      final features = genderData?['features'] as Map<String, dynamic>?;
      final messaging = features?['who_can_message'] as Map<String, dynamic>?;
      final messagingEnabled = messaging?['enabled'] as bool? ?? false;

      if (messagingEnabled) {
        return;
      }

      await setWhoCanMessageAll();
    }

    final userSubscription = userRef.snapshots().listen((snapshot) {
      final data = snapshot.data();
      if (data == null) return;
      unawaited(evaluatePolicy(userData: data));
    });

    final subscriptionSubscription = subscriptionRef.snapshots().listen((_) {
      unawaited(evaluatePolicy());
    });

    final freeFeaturesSubscription = freeFeaturesRef.snapshots().listen((_) {
      unawaited(evaluatePolicy());
    });

    unawaited(evaluatePolicy());

    return () {
      userSubscription.cancel();
      subscriptionSubscription.cancel();
      freeFeaturesSubscription.cancel();
    };
  }, [globals]);
}

// ---------- Business Logic function ----------
Future<void> handleLifecycleState(AppLifecycleState state) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    if (state == AppLifecycleState.resumed) {
      // Set user online in Firestore (backend function)
      await DatabaseService.handleOnlineStatue(true);
      // await _updateLastDateIfNeeded();
    } else {
      // Set user offline in Firestore (backend function)
      await DatabaseService.handleOnlineStatue(false);
    }
  }
}

// ---------- Custom Hook for app lifecycle ----------
class _HooksBindingObserver extends WidgetsBindingObserver {
  final BuildContext context;
  _HooksBindingObserver(this.context);

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    await handleLifecycleState(state); // Call separated business logic function
  }
}

// ---------- Location Update Helper ----------
// ignore: unused_element
Future<void> _updateLocationIfNeeded(BuildContext context) async {
  try {
    final globals = Globals.of(context);

    // Check if location permission was already requested in this session
    if (PermissionSessionManager.isLocationRequestedInHome()) {
      debugPrint(
        '🔒 [HOME] Location permission already requested this session, skipping',
      );
      return;
    }

    // Check if already denied this session - don't ask again
    if (PermissionSessionManager.isLocationDeniedThisSession()) {
      debugPrint('🚫 [HOME] Location already denied this session, skipping');
      return;
    }

    // Mark as requested for this session
    PermissionSessionManager.markLocationRequestedInHome();

    // Check if user has PERMANENTLY denied location permission (not just regular denial)
    // Regular denials are handled by session tracking, this is only for permanent denials
    var status = await Permission.location.status;
    if (status.isPermanentlyDenied &&
        globals.prefs.locationPermissionDenied.value) {
      debugPrint(
        '🚫 [HOME] Location permission permanently denied by user, showing settings dialog',
      );
      // Show custom dialog to allow user to open settings
      if (context.mounted) {
        final shouldOpenSettings = await _showLocationPermissionDialog(context);
        if (shouldOpenSettings == true) {
          await openAppSettings();
        }
      }
      return;
    }

    // Check if location services are enabled first
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('⚠️ [HOME] Location services disabled');
      return;
    }

    // Check if location permission is granted
    debugPrint('📍 [HOME] Current location permission status: $status');

    if (!status.isGranted) {
      // Permission not granted - check if we should request or show custom dialog
      debugPrint(
        '⚠️ [HOME] Location permission not granted. isDenied=${status.isDenied}, isPermanentlyDenied=${status.isPermanentlyDenied}',
      );

      if (!status.isPermanentlyDenied) {
        // Not permanently denied - request permission
        debugPrint('⚠️ [HOME] Requesting location permission...');
        status = await PermissionManager().requestPermission(
          Permission.location,
          delay: const Duration(milliseconds: 500),
        );

        if (status.isGranted) {
          debugPrint('✅ [HOME] Location permission granted');
          // Continue below to fetch location
        } else {
          debugPrint('❌ [HOME] Location permission denied');
          PermissionSessionManager.markLocationDeniedThisSession();
          if (status.isPermanentlyDenied) {
            await globals.prefs.locationPermissionDenied.set(true);
          }
          return;
        }
      } else {
        // Permission permanently denied - show custom dialog
        debugPrint(
          '⚠️ [HOME] Location permission permanently denied, showing custom dialog...',
        );

        final shouldOpenSettings = await _showLocationPermissionDialog(context);

        if (shouldOpenSettings == true) {
          // User wants to open settings
          await openAppSettings();
          // Don't continue - user will come back and we'll re-check
          return;
        } else {
          // User declined - only mark session, don't set persistent flag
          // On hot restart, they'll be asked again
          debugPrint('❌ [HOME] Location permission denied by user');
          PermissionSessionManager.markLocationDeniedThisSession();
          // Only set persistent flag if it becomes permanently denied
          if (await Permission.location.isPermanentlyDenied) {
            await globals.prefs.locationPermissionDenied.set(true);
          }
          return;
        }
      }
    }

    debugPrint('✅ [HOME] Location permission granted');

    // Get current position
    debugPrint('📍 [HOME] Fetching current location...');
    final position = await Geolocator.getCurrentPosition(
      // desiredAccuracy: LocationAccuracy.high, Previously deprecated - now set via LocationSettings
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    // Reverse geocode to get city and state
    final placemarks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );

    if (placemarks.isNotEmpty) {
      final place = placemarks.first;
      final state = place.administrativeArea ?? '';
      var city = (place.subAdministrativeArea ?? '')
          .replaceAll("Division", "")
          .trim();
      if (city.isEmpty) {
        city = place.locality ?? '';
      }

      debugPrint('✅ [HOME] Location updated: $city, $state');

      // Update location in database
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DatabaseService.updateUserField(user.uid, {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'city': city,
          'state': state,
        });
      }
    }
  } catch (e) {
    debugPrint('❌ [HOME] Location update error: $e');
  }
}

// Beautiful location permission dialog for home screen
Future<bool?> _showLocationPermissionDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Location Icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: kQuaternaryPink.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.location_on, color: kPrimaryPurple, size: 32),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            const Text(
              'Location Access\nRequired',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w700,
                fontSize: 22,
                color: kPrimaryPurple,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 12),

            // Message
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'We need your location to show you matches nearby. Please enable location access in your settings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: Color(0xFF666666),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                // Skip Button
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(dialogContext, false);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kPrimaryPurple, width: 1.5),
                      ),
                      child: const Center(
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: kPrimaryPurple,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Settings Button
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(dialogContext, true);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: kPrimaryPurple,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'Settings',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void useSessionWatcher(BuildContext context) {
  final didInit = useRef(false);
  final isHandlingLogout = useRef(false);

  useEffect(() {
    if (didInit.value) return null;
    didInit.value = true;

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? sub;

    Future<void> startWatcher() async {
      final stream = SessionService.watchCurrentSession();
      if (stream == null) return;

      sub = stream.listen(
        (snapshot) async {
          final data = snapshot.data();
          if (data == null) return;

          final revoked = data['revoked'] == true;

          if (revoked && !isHandlingLogout.value) {
            isHandlingLogout.value = true;

            debugPrint('⚠️ [SESSION] Current session revoked. Forcing logout.');

            if (context.mounted) {
              // Determine message based on revocation reason
              final revokedReason = data['revokedReason'] as String?;
              final message = revokedReason == 'device_limit_decreased'
                  ? 'Your session was ended because the device limit was reduced.'
                  : 'Your session was ended because this account was logged in on another device.';

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.redAccent,
                  content: Text(message),
                ),
              );
            }

            await SessionService.forceLogoutLocally(Globals.of(context));

            if (context.mounted) {
              Navigator.pushNamedAndRemoveUntil(
                context,
                LoginScreen.routeName,
                (route) => false,
              );
            }
          }
        },
        onError: (error) {
          if (error is FirebaseException && error.code == 'permission-denied') {
            // Happens when logout/account deletion is in progress.
            return;
          }
          debugPrint('❌ [SESSION] watchCurrentSession error: $error');
        },
      );
    }

    startWatcher();

    return () {
      sub?.cancel();
    };
  }, []);
}

// ---------- Refactored Home widget as a HookWidget ----------
class Home extends HookWidget {
  static String routeName = "/home";

  @override
  Widget build(BuildContext context) {
    // Local UI state for zoom drawer controller using useState
    // final drawerController = useState(ZoomDrawerController());

    // Custom hook for side effects (lifecycle, online status)
    useOnlineStatus(context);
    // Neewly Added : May 25, 2026
    useWhoCanMessageSync(context);
    useSessionWatcher(context);

    // The widget glue: leverages hooks for UI and calls business/backend functions
    // return ZoomDrawer(
    //   controller: drawerController.value,
    //   style: DrawerStyle.style1,
    //   menuScreen: MenuScreen(),
    //   mainScreen: HomeScreen(),
    //   borderRadius: 20.0,
    //   showShadow: true,
    //   angle: -8.0,
    //   drawerShadowsBackgroundColor: Colors.grey[300]!,
    //   slideWidth: MediaQuery.of(context).size.width * .75,
    //   openCurve: Curves.fastOutSlowIn,
    //   closeCurve: Curves.bounceIn,
    // );
    return HomeScreen();
  }
}
