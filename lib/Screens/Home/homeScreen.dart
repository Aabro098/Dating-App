import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:viora/Screens/AdminScreens/Spamers.dart';
import 'package:viora/Screens/AdminScreens/adminChatRooms.dart';
import 'package:viora/Screens/BotManagement/botChatScreen.dart';
import 'package:viora/Screens/BotManagement/botNotifications.dart';
import 'package:viora/Screens/ChatScreen/chats_screen.dart';
import 'package:viora/Screens/ConnectionsScreen/ConnectionsScreen.dart';
import 'package:viora/Screens/MessagesScreen/new_message_screen.dart';
import 'package:viora/Screens/MyProfile/my_profile_new.dart';
// import 'package:viora/Screens/GemsScreen/gemsScreen.dart'; // Commented: replaced by PaymentScreen
import 'package:viora/Screens/EditProfile/new_edit_profile.dart';
import 'package:viora/Screens/PaymentScreen/payment_screen.dart';
import 'package:viora/Screens/Home/HomeContent.dart';
import 'package:viora/Screens/ProfileScreen/new_profile_view.dart';
import 'package:viora/Screens/SupportScreen/supportScreen.dart';
import 'package:viora/Screens/Verification/LivenessVerificationScreen.dart';
import 'package:viora/Services/connection_count_service.dart';
import 'package:viora/components/VerifyProfileDialog.dart';
import 'package:viora/components/SafetyTipsDialog.dart';
import 'package:viora/components/PermissionDialog.dart';
import 'package:viora/Services/FCMServie.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:viora/Services/DatabaseService.dart';
import '../../Services/Global.dart';
import '../../Services/auth_helper.dart';
import '../../constants.dart';
import '../../size_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:viora/Services/AppConfigService.dart';
import 'package:viora/Services/SubscriptionService.dart';

// Static flag to track if verification dialog was shown this session
bool _verificationDialogShownThisSession = false;

// Global variable to control profile screen display
final ValueNotifier<bool> showEditProfileScreen = ValueNotifier(false);

final ValueNotifier<String?> showViewProfileScreen = ValueNotifier(null);
final ValueNotifier<bool?> showSupportScreenValue = ValueNotifier(false);

// Global variable to control bottom navigation index
final ValueNotifier<int> currentNavigationIndex = ValueNotifier(0);

// Function to reset the verification dialog flag (call on logout)
void resetVerificationDialogFlag() {
  _verificationDialogShownThisSession = false;
}

/// RevenueCat [EntitlementInfo.billingIssueDetectedAt] — same UI shell as Safety Tips.
Future<void> _showPaymentIssueIfNeeded(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || !context.mounted) return;
  try {
    final issue = await SubscriptionService.hasActiveSubscriptionBillingIssue(
      uid,
    );
    if (!issue || !context.mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!context.mounted) return;
    await SafetyTipsDialog.showPaymentIssue(context);
    debugPrint('✅ [HOME] Payment issue dialog dismissed');
  } catch (e) {
    debugPrint('⚠️ [HOME] Payment issue check failed: $e');
  }
}

class _PaymentIssueLifecycleObserver extends WidgetsBindingObserver {
  final void Function() onResumed;
  _PaymentIssueLifecycleObserver(this.onResumed);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}

/// Helper function to show safety tips based on version
/// NOT session-based - shows only when needed:
/// - New users (storedVersion == 0): Show "Safety Tips" ONE TIME ONLY
/// - Existing users: Show "Safety Reminder" ONLY when Firebase version is updated
/// Version is stored in Firestore per-user (not device-specific)
Future<void> _showSafetyTipsIfNeeded(
  BuildContext context,
  Globals globals,
  bool isFirstLaunch,
) async {
  // Prevent duplicate shows within same session (hot restart protection only)
  if (PermissionSessionManager.isSafetyTipsShownThisSession()) {
    debugPrint('✅ [HOME] Safety tips already shown this session, skipping');
    return;
  }

  // Get current version from Firebase (admin-controlled)
  final currentVersion = AppConfigService.safetyTipsVersion;

  // Get user's stored version from Firestore (what they've already seen)
  final userDetails = globals.prefs.userDetails.value;
  final storedVersion = userDetails?.safetyTipsVersion ?? 0;

  // Determine if user is new (never seen any version) or existing (has seen versions)
  bool isNewUser = storedVersion == 0;

  // Check if we should show safety tips:
  // - New user (storedVersion == 0): Show ONE TIME only
  // - Existing user: Show ONLY if currentVersion > storedVersion (version was updated)
  bool shouldShow = isNewUser || (currentVersion > storedVersion);

  if (!shouldShow) {
    debugPrint(
      '✅ [HOME] Safety tips not needed (user version: $storedVersion, current: $currentVersion)',
    );
    return;
  }

  if (isNewUser) {
    debugPrint(
      '🛡️ [HOME] New user detected - showing Safety Tips ONE TIME (onboarding)',
    );
  } else {
    debugPrint(
      '🛡️ [HOME] Version updated ($storedVersion → $currentVersion) - showing Safety Reminder ONE TIME',
    );
  }

  if (context.mounted) {
    await Future.delayed(const Duration(milliseconds: 300));
    debugPrint(
      '🛡️ [HOME] Displaying safety tips dialog (isNewUser: $isNewUser)',
    );

    await SafetyTipsDialog.show(context, isNewUser: isNewUser);

    // Mark as shown for this session (prevent duplicate in same session/hot restart)
    PermissionSessionManager.markSafetyTipsShownThisSession();

    // ALWAYS update to currentVersion after showing (prevents showing again)
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && userDetails != null) {
      // Update Firestore - persists across sessions and devices
      await FirebaseFirestore.instance.collection('Users').doc(uid).update({
        'safetyTipsVersion': currentVersion,
      });

      // Update local cache
      userDetails.safetyTipsVersion = currentVersion;
      await globals.prefs.userDetails.set(userDetails);
      globals.userProvider.updateUserDetails(userDetails);

      debugPrint(
        '✅ [HOME] Updated safetyTipsVersion to $currentVersion in Firestore',
      );
    }

    debugPrint('✅ [HOME] Safety Tips completed');
  }
}

// Note: Notification permission is now handled in SplashScreen
// However, if permanently denied, we show custom dialog here
Future<void> _checkNotificationPermissionIfDenied(BuildContext context) async {
  final globals = Globals.of(context);

  // Check if notification permission was already requested this session
  if (PermissionSessionManager.isNotificationRequestedThisSession()) {
    return;
  }

  // Check if already denied this session - don't ask again
  if (PermissionSessionManager.isNotificationDeniedThisSession()) {
    return;
  }

  // Get current notification status
  var status = await Permission.notification.status;

  // Only show custom dialog if permanently denied
  if (status.isPermanentlyDenied) {
    debugPrint(
      '🔔 [HOME] Notification permanently denied - showing custom dialog',
    );

    // Mark as requested for this session
    PermissionSessionManager.markNotificationRequestedThisSession();

    if (context.mounted) {
      final granted = await PermissionDialog.show(
        context,
        type: PermissionType.notification,
      );
      debugPrint('✅ [HOME] User responded: $granted');

      if (granted == true) {
        await globals.prefs.notificationPermissionGranted.set(true);
        await globals.prefs.notificationDenialCount.set(0);

        // Initialize FCM after permission is granted
        debugPrint('📞 [HOME] Initializing FCM after permission granted');
        await FCMService.onPermissionGranted();
      } else {
        PermissionSessionManager.markNotificationDeniedThisSession();
      }
    }
  }
}

// Location permission function below handles location requests

// Custom hook for connectivity
StreamSubscription<ConnectivityResult>? useConnectivityHook(
  void Function(ConnectivityResult) onStatusChange,
) {
  final connectivity = Connectivity();
  useEffect(() {
    final sub = connectivity.onConnectivityChanged.listen((result) {
      onStatusChange(result[0]);
    });
    return sub.cancel;
  }, []);
  return null;
}

// Custom hook for notification count
class NotificationCounts {
  final int notiCount;
  final int unseenCount;

  NotificationCounts(this.notiCount, this.unseenCount);
}

NotificationCounts useNotificationCounts() {
  final notiCount = useState(0);
  final unseenCount = useState(0);
  final uid = FirebaseAuth.instance.currentUser?.uid;

  useEffect(() {
    if (uid == null) return null;

    // Backend call: Get notification counts
    final userListener = FirebaseFirestore.instance
        .collection("Users")
        .doc(uid)
        .snapshots()
        .listen(
          (value) {
            // Check if document exists before accessing fields
            if (value.exists && value.data() != null) {
              final data = value.data()!;
              if (data["notiCount"] != null) {
                notiCount.value = data["notiCount"];
              }
            }
          },
          onError: (error) {
            if (error is FirebaseException &&
                error.code == 'permission-denied') {
              notiCount.value = 0;
              return;
            }
          },
        );

    final messagesListener = FirebaseFirestore.instance
        .collection("Messages")
        .where("receiver", isEqualTo: uid)
        .where("seen", isEqualTo: false)
        .snapshots()
        .listen(
          (event) {
            unseenCount.value = event.size;
          },
          onError: (error) {
            if (error is FirebaseException &&
                error.code == 'permission-denied') {
              unseenCount.value = 0;
              return;
            }
          },
        );

    return () {
      userListener.cancel();
      messagesListener.cancel();
    };
  }, [uid]);

  return NotificationCounts(notiCount.value, unseenCount.value);
}

// Business logic: connection status message mapping
SnackBarInfo getConnectionSnackBarInfo(ConnectivityResult result) {
  switch (result) {
    case ConnectivityResult.wifi:
    case ConnectivityResult.mobile:
      return SnackBarInfo(
        text: "We are Online",
        color: Colors.green,
        icon: Icons.wifi,
        duration: Duration(seconds: 2),
      );
    case ConnectivityResult.none:
      return SnackBarInfo(
        text: "No Internet Connection",
        color: Colors.redAccent,
        icon: Icons.wifi_off,
        duration: Duration(seconds: 4),
      );
    default:
      return SnackBarInfo(
        text: "Please Check Your Connection",
        color: Colors.redAccent,
        icon: Icons.error,
        duration: Duration(seconds: 4),
      );
  }
}

class SnackBarInfo {
  final String text;
  final Color color;
  final IconData icon;
  final Duration duration;

  SnackBarInfo({
    required this.text,
    required this.color,
    required this.icon,
    required this.duration,
  });
}

// Backend API for handling push notifications
void handlePushNotification(BuildContext ctx, RemoteMessage message) {
  try {
    final title = message.notification?.title ?? "";
    final uid = message.data["uid"];
    Widget nextScreen;
    if (title.contains("Spam message Detected")) {
      nextScreen = Spamers();
    } else if (title.contains("Support Message Response")) {
      nextScreen = SupportScreen(canPop: true);
    } else if (title.contains("Support Message from")) {
      nextScreen = AdminChatRooms();
    } else if (title.contains("BOTs Profile Notification")) {
      nextScreen = BotNotificationScreen(botId: uid);
    } else if (title.contains("BOTs")) {
      nextScreen = BotChatsScreen(botId: uid);
    } else if (title.contains("Message from")) {
      nextScreen = NewMessagesScreen(uId: uid);
    } else {
      nextScreen = NewProfileView(uid: uid, canPop: true);
    }
    Navigator.push(ctx, MaterialPageRoute(builder: (context) => nextScreen));
  } catch (e) {
    print(e.toString());
  }
}

// Location permission update function
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
      // Check if permission is not permanently denied
      if (!status.isPermanentlyDenied) {
        // First time or regular denial - request permission with system dialog
        debugPrint('📍 [HOME] Requesting location permission (system dialog)');

        // Simple await - blocks until user responds!
        status = await Permission.location.request();
        debugPrint('✅ [HOME] User responded: $status');

        if (status.isGranted) {
          debugPrint('✅ [HOME] Location permission granted');
          // Continue to get location below
        } else if (status.isDenied) {
          // User denied - only mark session, don't set persistent flag
          debugPrint('❌ [HOME] Location permission denied by user');
          PermissionSessionManager.markLocationDeniedThisSession();
          return;
        } else if (status.isPermanentlyDenied) {
          // User permanently denied - set persistent flag
          debugPrint('❌ [HOME] Location permission permanently denied');
          PermissionSessionManager.markLocationDeniedThisSession();
          await globals.prefs.locationPermissionDenied.set(true);
          return;
        }
      } else if (status.isPermanentlyDenied) {
        // Previously denied - show custom dialog to go to settings
        debugPrint(
          '📍 [HOME] Location permanently denied, showing custom dialog',
        );

        final shouldOpenSettings = await _showLocationPermissionDialog(context);
        debugPrint('✅ [HOME] User responded: $shouldOpenSettings');

        if (shouldOpenSettings == true) {
          await openAppSettings();
        }
        return;
      } else {
        // Restricted or other status
        debugPrint('⚠️ [HOME] Location permission restricted or unavailable');
        return;
      }
    }

    // Only reach here if permission is granted
    if (!status.isGranted) {
      debugPrint('⚠️ [HOME] Location permission not granted, returning');
      return;
    }

    debugPrint('✅ [HOME] Location permission granted');

    // Get current position
    debugPrint('📍 [HOME] Fetching current location...');
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
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

class HomeScreen extends HookWidget {
  static String routeName = "/homeScreen";

  Future<void> _bootstrapApp(Globals globals) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    int attempts = 0;
    while (!AppConfigService.isLoaded && attempts < 50) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    attempts = 0;
    while (globals.prefs.userDetails.value == null && attempts < 50) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }
  }

  @override
  Widget build(BuildContext context) {
    useEffect(() {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );

      Timer? autoHideTimer;

      void handleSystemUIChange() {
        autoHideTimer?.cancel();
        autoHideTimer = Timer(const Duration(seconds: 3), () {
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
            overlays: [],
          );
        });
      }

      return () {
        autoHideTimer?.cancel();
      };
    }, []);

    useEffect(() {
      Future.delayed(const Duration(milliseconds: 500), () async {
        if (!context.mounted) return;

        await _checkNotificationPermissionIfDenied(context);

        if (context.mounted) {
          await _updateLocationIfNeeded(context);
        }
      });
      return null;
    }, []);

    final globals = Globals.of(context);

    final bootstrapFuture = useMemoized(() => _bootstrapApp(globals), [
      globals,
    ]);
    final bootstrapSnapshot = useFuture(bootstrapFuture);

    final currentIndex = useListenable(currentNavigationIndex);
    final notificationCounts = useNotificationCounts();
    final snackbarVisible = useState(false);

    // Listen to global edit profile screen toggle
    final showEditProfile = useListenable(showEditProfileScreen);
    final showProfileScreen = useListenable(showViewProfileScreen);
    final showSupportScreen = useListenable(showSupportScreenValue);

    final authUser = FirebaseAuth.instance.currentUser;
    final userId = authUser?.uid ?? '';

    final connectionCountSnapshot = useStream<int>(
      userId.isNotEmpty
          ? ConnectionCountService.watchUnseenConnectionsCount(userId)
          : const Stream<int>.empty(),
      initialData: 0,
    );
    final connectionCount = connectionCountSnapshot.data ?? 0;

    final skipFirstResume = useRef(true);

    useEffect(() {
      if (bootstrapSnapshot.connectionState == ConnectionState.done) {
        FlutterNativeSplash.remove();
      }
      return null;
    }, [bootstrapSnapshot.connectionState]);

    useConnectivityHook((result) {
      final info = getConnectionSnackBarInfo(result);
      if (snackbarVisible.value) {
        showSimpleNotification(
          Text(info.text),
          background: info.color,
          duration: info.duration,
          position: NotificationPosition.top,
          slideDismiss: true,
          leading: Icon(info.icon),
        );
      }
      snackbarVisible.value = true;
    });

    useEffect(() {
      final userDetails = globals.prefs.userDetails.value;
      final isVerified = userDetails?.isVerified ?? false;
      final isFirstLaunch = globals.prefs.isFirstLaunch.value;
      final userGender = userDetails?.gender;

      final shouldShowVerificationDialog = !isVerified;

      if (shouldShowVerificationDialog ||
          (!_verificationDialogShownThisSession && isFirstLaunch)) {
        _verificationDialogShownThisSession = true;

        Future.delayed(const Duration(milliseconds: 800), () async {
          if (!context.mounted) return;

          if (shouldShowVerificationDialog) {
            await VerifyProfileDialog.show(
              context,
              userGender: userGender,
              onStartVerification: () {
                Navigator.of(
                  context,
                ).pushNamed(LivenessVerificationScreen.routeName);
              },
              onSkip: () async {
                if (context.mounted) {
                  await _showSafetyTipsIfNeeded(
                    context,
                    globals,
                    isFirstLaunch,
                  );
                }
              },
            );
          } else {
            if (context.mounted) {
              await _showSafetyTipsIfNeeded(context, globals, isFirstLaunch);
            }
          }

          FCMService.onAppReady();
        });
      }

      return null;
    }, []);

    useEffect(() {
      final timer = Timer(const Duration(milliseconds: 3800), () {
        if (context.mounted) {
          _showPaymentIssueIfNeeded(context);
        }
      });

      void onResumed() {
        if (skipFirstResume.value) {
          skipFirstResume.value = false;
          return;
        }

        Future<void>.delayed(const Duration(milliseconds: 450), () {
          if (context.mounted) {
            _showPaymentIssueIfNeeded(context);
          }
        });
      }

      final obs = _PaymentIssueLifecycleObserver(onResumed);
      WidgetsBinding.instance.addObserver(obs);

      return () {
        timer.cancel();
        WidgetsBinding.instance.removeObserver(obs);
      };
    }, []);

    if (bootstrapSnapshot.connectionState != ConnectionState.done) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    /// Subscriptions tab (IndexedStack index). Keep in sync with [buildScreens] order.
    const paymentTabIndex = 3;
    // Build screens list — IndexedStack keeps tab state (no full reload on switch).
    List<Widget> buildScreens() {
      return [
        showSupportScreen.value == true
            ? SupportScreen(canPop: false)
            : showProfileScreen.value != null
            ? NewProfileView(uid: showProfileScreen.value!)
            : HomeContent(),
        ChatsScreen(hideAppBar: true, isActiveTab: currentIndex.value == 1),
        showProfileScreen.value != null
            ? NewProfileView(uid: showProfileScreen.value!)
            : ConnectionsScreen(hideAppBar: true),
        PaymentScreen(isActiveTab: currentIndex.value == paymentTabIndex),
        showEditProfile.value == true
            ? NewEditProfile()
            : NewMyProfile(hideAppBar: true),
      ];
    }

    // Get navigation bar destinations
    List<NavigationDestination> buildNavBarItems(
      NotificationCounts counts,
      int connectionCount,
    ) {
      // final isMale = globals.prefs.userDetails.value?.gender == "Male";

      return [
        NavigationDestination(
          icon: SvgPicture.asset(
            "assets/svg/navbar_home.svg",
            height: getProportionateScreenHeight(35),
            width: getProportionateScreenWidth(35),
            colorFilter: ColorFilter.mode(kWhite, BlendMode.srcIn),
          ),
          selectedIcon: SvgPicture.asset(
            "assets/svg/navbar_home.svg",
            height: getProportionateScreenHeight(35),
            width: getProportionateScreenWidth(35),
            colorFilter: ColorFilter.mode(kTertiaryPink, BlendMode.srcIn),
          ),
          label: "Home",
        ),
        NavigationDestination(
          icon: Badge(
            isLabelVisible: counts.unseenCount > 0,
            label: Text("${counts.unseenCount}"),
            child: SvgPicture.asset(
              "assets/svg/navbar_interactions.svg",
              height: getProportionateScreenHeight(34),
              width: getProportionateScreenWidth(34),
              colorFilter: ColorFilter.mode(kWhite, BlendMode.srcIn),
            ),
          ),
          selectedIcon: Badge(
            isLabelVisible: counts.unseenCount > 0,
            label: Text("${counts.unseenCount}"),
            child: SvgPicture.asset(
              "assets/svg/navbar_interactions.svg",
              height: getProportionateScreenHeight(34),
              width: getProportionateScreenWidth(34),
              colorFilter: ColorFilter.mode(kTertiaryPink, BlendMode.srcIn),
            ),
          ),
          label: "Messages",
        ),
        NavigationDestination(
          icon: Badge(
            isLabelVisible: connectionCount > 0,
            label: Text("$connectionCount"),
            child: SvgPicture.asset(
              "assets/svg/navbar_connections.svg",
              height: getProportionateScreenHeight(34),
              width: getProportionateScreenWidth(34),
              colorFilter: ColorFilter.mode(kWhite, BlendMode.srcIn),
            ),
          ),
          selectedIcon: Badge(
            isLabelVisible: connectionCount > 0,
            label: Text("$connectionCount"),
            child: SvgPicture.asset(
              "assets/svg/navbar_connections.svg",
              height: getProportionateScreenHeight(34),
              width: getProportionateScreenWidth(34),
              colorFilter: ColorFilter.mode(kTertiaryPink, BlendMode.srcIn),
            ),
          ),
          label: "Connections",
        ),
        // if (isMale)
        NavigationDestination(
          icon: SvgPicture.asset(
            "assets/svg/navbar_coins.svg",
            height: getProportionateScreenHeight(34),
            width: getProportionateScreenWidth(34),
            colorFilter: ColorFilter.mode(kWhite, BlendMode.srcIn),
          ),
          selectedIcon: SvgPicture.asset(
            "assets/svg/navbar_coins.svg",
            height: getProportionateScreenHeight(34),
            width: getProportionateScreenWidth(34),
            colorFilter: ColorFilter.mode(kTertiaryPink, BlendMode.srcIn),
          ),
          label: "Subscriptions",
        ),
        NavigationDestination(
          icon: SvgPicture.asset(
            "assets/svg/navbar_profile.svg",
            height: getProportionateScreenHeight(34),
            width: getProportionateScreenWidth(34),
            colorFilter: ColorFilter.mode(kWhite, BlendMode.srcIn),
          ),
          selectedIcon: SvgPicture.asset(
            "assets/svg/navbar_profile.svg",
            height: getProportionateScreenHeight(34),
            width: getProportionateScreenWidth(34),
            colorFilter: ColorFilter.mode(kTertiaryPink, BlendMode.srcIn),
          ),
          label: "Profile",
        ),
      ];
    }

    final screens = buildScreens();
    final navBarItems = buildNavBarItems(notificationCounts, connectionCount);

    // Calculate profile tab index (last tab)
    // final isMale = globals.prefs.userDetails.value?.gender == "Male";
    // final profileTabIndex = isMale ? 4 : 3; // Profile is last tab

    // Ensure currentIndex is within bounds
    if (currentIndex.value >= screens.length) {
      currentIndex.value =
          screens.length - 1; // Set to last valid index (Profile)
    }

    // final isProfileTab = currentIndex.value == profileTabIndex;

    // -- UI Section Below --
    return Scaffold(
      // appBar: isProfileTab
      //     ? PreferredSize(
      //         preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),
      //         child: SafeArea(
      //           child: Container(
      //             decoration: BoxDecoration(
      //               color: kPrimaryColor,
      //               borderRadius: BorderRadius.only(
      //                 bottomLeft: Radius.circular(10),
      //                 bottomRight: Radius.circular(10),
      //               ),
      //             ),
      //             child: Row(
      //               mainAxisAlignment: MainAxisAlignment.spaceBetween,
      //               children: <Widget>[
      //                 IconBtnWithCounter(
      //                   svgSrc: "assets/svg/icon_drawer.svg",
      //                   press: () {
      //                     if (ZoomDrawer.of(context)!.isOpen()) {
      //                       ZoomDrawer.of(context)!.close();
      //                     } else {
      //                       ZoomDrawer.of(context)!.open();
      //                     }
      //                   },
      //                   numOfitem: 0,
      //                 ),
      //                 Spacer(),
      //                 Text(
      //                   appName,
      //                   style: TextStyle(
      //                     fontSize: getProportionateScreenHeight(26),
      //                     color: Colors.white,
      //                   ),
      //                 ),
      //                 Spacer(),
      //                 IconBtnWithCounter(
      //                   svgSrc: "assets/svg/meetisy_help.svg",
      //                   press: () => Navigator.push(
      //                     context,
      //                     MaterialPageRoute(
      //                       builder: (context) =>
      //                           MessagesScreen(uId: 'Yl5RALFSJdOke2wgRDZp'),
      //                     ),
      //                   ),
      //                   isMeetisyHelpBtn: true,
      //                 ),
      //                 IconBtnWithCounter(
      //                   svgSrc: "assets/svg/notifications.svg",
      //                   press: () => Navigator.push(
      //                     context,
      //                     MaterialPageRoute(
      //                       builder: (context) => NotificationScreen(),
      //                     ),
      //                   ),
      //                   numOfitem: notificationCounts.notiCount,
      //                 ),
      //                 IconBtnWithCounter(
      //                   svgSrc: "assets/svg/chat.svg",
      //                   press: () => Navigator.push(
      //                     context,
      //                     MaterialPageRoute(
      //                       builder: (context) => ChatsScreen(),
      //                     ),
      //                   ),
      //                   numOfitem: notificationCounts.unseenCount,
      //                 ),
      //               ],
      //             ),
      //           ),
      //         ),
      //       )
      //     : null,
      body: IndexedStack(index: currentIndex.value, children: screens),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: kWhite.withOpacity(0.8), width: 1.5),
              ),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                navigationBarTheme: NavigationBarThemeData(
                  elevation: 0,
                  backgroundColor: kPrimaryPurple,
                  indicatorColor: Colors.transparent,
                  overlayColor: MaterialStateProperty.all(Colors.transparent),
                  height: getProportionateScreenHeight(62),
                  labelBehavior:
                      NavigationDestinationLabelBehavior.onlyShowSelected,
                  labelTextStyle: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        color: kTertiaryPink,
                      );
                    }
                    return TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: kWhite,
                    );
                  }),
                ),
              ),
              child: NavigationBar(
                selectedIndex: currentIndex.value,
                onDestinationSelected: (index) {
                  showEditProfileScreen.value = false;
                  showSupportScreenValue.value = false;
                  showViewProfileScreen.value = null;
                  currentNavigationIndex.value = index;
                },
                destinations: navBarItems,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            color: kPrimaryPurple,
            padding: EdgeInsets.only(bottom: getProportionateScreenHeight(2)),
            child: Center(
              child: Text(
                'Signed In through ${AuthHelper.isPhoneSignIn() ? AuthHelper.getPhoneNumber() ?? "Unknown" : AuthHelper.getEmail() ?? "Unknown"}',
                style: TextStyle(fontSize: 10, color: kWhite),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------
// Comments and Explanations
// -------------------------

/*
  How hooks manage UI:
  - All local state (tabController, notificationCounts, snackbarVisible) is handled using useState/useMemoized for better separation of UI state from business and backend logic.
  - Side effects are managed with useEffect, ensuring all initialization, cleanup, and event listeners are lifecycle-aware and do not leak resources.

  Custom Hooks:
  - useNotificationCounts: Encapsulates subscriptions to user and message Firestore changes. Provides testable state updates for notification counts.
  - useConnectivityHook: Listens to connectivity changes and calls the supplied callback. Keeps widget UI focused on glue logic, not actual state management or backend logic.

  Separation of Concerns:
  - Backend/database code (Firestore/FCM listeners) is handled in custom hooks or standalone business logic functions outside the build method.
  - Business logic (snackbar message selection, tab selection) is encapsulated in stateless mappers and utility classes outside Widget code.
  - The Widget itself merely glues together hooks for state, functions for backend or business logic, and composes screens/UI.

  This architecture keeps the HomeScreen modular, maintainable, and testable. All business and backend concerns can be individually unit-tested or replaced. UI logic is minimal and easy to understand.
*/
