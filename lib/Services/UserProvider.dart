import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../Screens/Login_Signup/loginScreen.dart';
import '../constants.dart';
import '../size_config.dart';
import 'DatabaseService.dart';
import 'package:http/http.dart' as http;

import 'Global.dart';
import 'PermissionManager.dart';
import 'SubscriptionService.dart';

class UserProvider extends ChangeNotifier {
  late UserDetails userDetails;

  late CustomerInfo userInfo;
  bool _userInfoInitialized = false;
  bool get isUserInfoInitialized => _userInfoInitialized;

  // Loading states
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  StreamSubscription? _userSubscription;

  /// Public method to update user details and notify listeners
  /// This should be called when user data is updated externally
  void updateUserDetails(UserDetails newDetails) {
    userDetails = newDetails;
    notifyListeners();
  }

  /// Cancel user subscription and reset state (call on logout/account deletion)
  /// This prevents data mixing between accounts
  void resetUserState() {
    debugPrint('🔄 Resetting UserProvider state');
    _userSubscription?.cancel();
    _userSubscription = null;
    _isLoading = false;
    _error = null;
    _userInfoInitialized = false;
    // Note: Don't call notifyListeners here as we're logging out
  }

  static Future<String> getUserIPAddress() async {
    final response = await http.get(Uri.parse('https://api.ipify.org'));
    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception('Failed to get IP address');
    }
  }

  static Future<Position> getUserLocation() async {
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    return position;
  }

  static Future<bool> checkLocationPermission() async {
    PermissionStatus status = await Permission.location.status;
    if (status.isGranted) {
      return true;
    } else {
      // Use centralized permission manager to prevent conflicts
      PermissionStatus permissionStatus = await PermissionManager()
          .requestPermission(
            Permission.location,
            delay: const Duration(milliseconds: 800),
          );
      if (permissionStatus.isGranted) {
        return true;
      } else {
        return false;
      }
    }
  }

  Future<bool> getIpandLoc(context) async {
    bool isLoading = true;
    try {
      isLoading = true;
      // Check location permission
      final bool hasPermission = await checkLocationPermission();
      if (!hasPermission) {
        debugPrint('Location permission denied');
        isLoading = await locationPermissionDialog(context);
      }

      // Retrieve the user's location
      Position position = await getUserLocation();
      double latitude = position.latitude;
      double longitude = position.longitude;

      // Store the location in Firestore
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .update({'latitude': latitude, 'longitude': longitude});

      final List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );

      debugPrint('Placemarks: $placemarks');
      DatabaseService.updateField({
        "city": (placemarks[0].subAdministrativeArea)!.replaceAll(
          "Division",
          "",
        ),
        "state": placemarks[0].administrativeArea,
      });

      debugPrint('User location stored successfully');
    } catch (e) {
      debugPrint('Error storing user location: $e');
      isLoading = false;
    }

    try {
      isLoading = true;
      // Retrieve the user's IP address
      final ipAddress = await getUserIPAddress();

      // Store the IP address in Firestore
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .update({'ipAddress': ipAddress});

      debugPrint('User IP address stored successfully');
    } catch (e) {
      debugPrint('Error storing user IP address: $e');
      isLoading = false;
    }
    return isLoading;
  }

  Future<Map<String, double>> getLatLng(context, {bool? skip}) async {
    bool isLoading = true;
    double latitude = 0.0;
    double longitude = 0.0;
    try {
      isLoading = true;
      // Check location permission
      final bool hasPermission = await checkLocationPermission();
      if (!hasPermission) {
        debugPrint('Location permission denied');
        isLoading = await locationPermissionDialog(context, skip: skip);
      }

      // Retrieve the user's location
      Position position = await getUserLocation();
      latitude = position.latitude;
      longitude = position.longitude;

      // Store the location in Firestore
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .update({'latitude': latitude, 'longitude': longitude});

      final List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );

      debugPrint('Placemarks: $placemarks');
      DatabaseService.updateField({
        "city": (placemarks[0].subAdministrativeArea)!.replaceAll(
          "Division",
          "",
        ),
        "state": placemarks[0].administrativeArea,
      });

      debugPrint('User location stored successfully');
    } catch (e) {
      debugPrint('Error storing user location: $e');
      isLoading = false;
    }

    try {
      isLoading = true;
      // Retrieve the user's IP address
      final ipAddress = await getUserIPAddress();

      // Store the IP address in Firestore
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .update({'ipAddress': ipAddress});

      debugPrint('User IP address stored successfully');
    } catch (e) {
      debugPrint('Error storing user IP address: $e');
      isLoading = false;
    }
    return {"latitude": latitude, "longitude": longitude};
  }

  /// NEW METHOD: Initialize user details with proper async handling
  /// Returns true if user profile exists, false if needs completion
  Future<bool> initializeUserDetails(BuildContext context) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final globals = Globals.of(context);
      final uid = FirebaseAuth.instance.currentUser?.uid;

      if (uid == null) {
        throw Exception('No authenticated user');
      }

      debugPrint("⚡ START: User initialization for UID: $uid");
      final startTime = DateTime.now();

      // ⚡ OPTIMIZATION 1: Try cached data first for INSTANT loading
      // BUT validate the cached user matches the current authenticated user
      try {
        final cachedUser = globals.prefs.userDetails.value;
        // CRITICAL: Validate cached user matches current authenticated user to prevent profile mixing
        if (cachedUser != null &&
            cachedUser.uid == uid &&
            _isProfileComplete(cachedUser)) {
          debugPrint("⚡ CACHE HIT! Loading from cache - instant!");
          userDetails = cachedUser;

          // Setup listener and refresh in background (non-blocking)
          _refreshUserDataInBackground(context, uid);

          _isLoading = false;
          notifyListeners();

          final elapsed = DateTime.now().difference(startTime).inMilliseconds;
          debugPrint("⚡ DONE: Cached load in ${elapsed}ms");
          return true;
        } else {
          // Clear invalid/stale cache from different user
          if (cachedUser != null && cachedUser.uid != uid) {
            debugPrint(
              "⚠️ Cache belongs to different user (${cachedUser.uid} vs $uid) - clearing",
            );
            await globals.prefs.userDetails.remove();
          }
          debugPrint("⚡ Cache miss or incomplete - fetching from Firestore");
        }
      } catch (e) {
        debugPrint("Cache read error: $e");
      }

      // Setup RevenueCat listener (non-blocking)
      Purchases.addCustomerInfoUpdateListener((purchaserInfo) {
        userInfo = purchaserInfo;
        _userInfoInitialized = true;
        notifyListeners();
      });

      final collectionReference = FirebaseFirestore.instance.collection(
        "Users",
      );

      // ⚡ OPTIMIZATION 2: Fetch user document (this is the main bottleneck)
      debugPrint("⚡ Fetching from Firestore...");
      final fetchStart = DateTime.now();
      final docSnapshot = await collectionReference.doc(uid).get();
      final fetchTime = DateTime.now().difference(fetchStart).inMilliseconds;
      debugPrint("⚡ Firestore fetch took ${fetchTime}ms");

      if (!docSnapshot.exists) {
        debugPrint("User document not found");
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Parse user data
      userDetails = UserDetails.fromJson(
        docSnapshot.data() as Map<String, dynamic>,
      );
      debugPrint("✅ User data parsed: ${userDetails.name}");

      // Check if profile is complete
      if (!_isProfileComplete(userDetails)) {
        debugPrint("⚠️ Profile incomplete");
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Clean up legacy data
      if (userDetails.relTypes?.contains("Purely sexual") ?? false) {
        userDetails.relTypes!.remove("Purely sexual");
      }

      // ⚡ OPTIMIZATION 3: Run NON-CRITICAL operations in parallel (don't wait!)
      Future.wait<void>([
        globals.prefs.userDetails.set(userDetails).catchError((e) => null),
        DatabaseService.addToken().catchError((e) => null),
      ]).then((_) => debugPrint("⚡ Background tasks done"));

      // Check if account is disabled
      if (userDetails.isDisabled ?? false) {
        await _handleDisabledAccount(context);
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // ⚡ OPTIMIZATION 4: Setup listener (non-blocking)
      _setupRealtimeListener(context, uid, collectionReference, globals);

      _isLoading = false;
      _error = null;
      notifyListeners();

      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint("⚡ DONE: Full initialization in ${elapsed}ms");

      return true;
    } catch (e, stackTrace) {
      debugPrint("Error initializing user details: $e\n$stackTrace");
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Background refresh after serving cached data
  void _refreshUserDataInBackground(BuildContext context, String uid) {
    final globals = Globals.of(context);
    final collectionReference = FirebaseFirestore.instance.collection("Users");

    debugPrint("⚡ Background refresh started");
    collectionReference
        .doc(uid)
        .get()
        .then((docSnapshot) {
          if (!docSnapshot.exists) return;

          userDetails = UserDetails.fromJson(
            docSnapshot.data() as Map<String, dynamic>,
          );
          globals.prefs.userDetails.set(userDetails).catchError((e) => null);
          _setupRealtimeListener(context, uid, collectionReference, globals);

          notifyListeners();
          debugPrint("⚡ Background refresh complete");
        })
        .catchError((e) {
          debugPrint("Background refresh error: $e");
        });
  }

  /// Setup real-time Firestore listener
  void _setupRealtimeListener(
    BuildContext context,
    String uid,
    CollectionReference collectionReference,
    Globals globals,
  ) {
    _userSubscription = collectionReference
        .doc(uid)
        .snapshots()
        .listen(
          (event) async {
            if (!event.exists) return;

            userDetails = UserDetails.fromJson(
              event.data() as Map<String, dynamic>,
            );
            globals.prefs.userDetails.set(userDetails).catchError((e) => null);

            if (userDetails.relTypes?.contains("Purely sexual") ?? false) {
              userDetails.relTypes!.remove("Purely sexual");
            }

            if (userDetails.isDisabled ?? false) {
              await _handleDisabledAccount(context);
            }

            notifyListeners();
          },
          onError: (error) {
            _error = error.toString();
            notifyListeners();
          },
        );
  }

  /// Handle disabled account scenario
  Future<void> _handleDisabledAccount(BuildContext context) async {
    showSimpleNotification(
      Text("Your Account is Disabled"),
      background: Colors.redAccent,
      duration: Duration(seconds: 10),
      position: NotificationPosition.top,
      slideDismissDirection: DismissDirection.down,
      leading: Icon(Icons.close),
    );

    await DatabaseService.handleOnlineStatue(false);
    await DatabaseService.deleteToken();
    await SubscriptionService.logOutRevenueCat();
    await FirebaseAuth.instance.signOut();

    Future.delayed(Duration(seconds: 4), () {
      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          LoginScreen.routeName,
          (Route<dynamic> route) => false,
        );
      }
      SystemNavigator.pop();
    });
  }

  /// DEPRECATED: Keep for backward compatibility but should not be used
  @Deprecated('Use initializeUserDetails instead')
  Future<void> getUserDetails(context) async {
    // Just call the new method
    await initializeUserDetails(context);
  }

  Future<bool> locationPermissionDialog(
    BuildContext context, {
    bool? skip,
  }) async {
    final globals = Globals.of(context);

    // Check if already denied this session - don't ask again
    if (skip == false || skip == null) {
      if (PermissionSessionManager.isLocationDeniedThisSession()) {
        debugPrint(
          '🚫 [DIALOG] Location already denied this session, skipping dialog',
        );
        return false;
      }

      // Check if already requested in home - coordinate with home.dart
      if (PermissionSessionManager.isLocationRequestedInHome()) {
        debugPrint(
          '🚫 [DIALOG] Location already requested in home this session, skipping dialog',
        );
        return false;
      }
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(getProportionateScreenWidth(20)),
        ),
        insetPadding: EdgeInsets.symmetric(
          horizontal: getProportionateScreenWidth(32),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: getProportionateScreenWidth(24),
            vertical: getProportionateScreenHeight(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Location Icon
              Container(
                width: getProportionateScreenWidth(72),
                height: getProportionateScreenWidth(72),
                decoration: BoxDecoration(
                  color: kQuaternaryPink.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.location_on,
                    color: kPrimaryPurple,
                    size: getProportionateScreenWidth(32),
                  ),
                ),
              ),
              SizedBox(height: getProportionateScreenHeight(20)),

              // Title
              Text(
                'Location Access\nRequired',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w700,
                  fontSize: getProportionateScreenWidth(22),
                  color: kPrimaryPurple,
                  height: 1.2,
                ),
              ),
              SizedBox(height: getProportionateScreenHeight(12)),

              // Message
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: getProportionateScreenWidth(8),
                ),
                child: Text(
                  'We need your location to show you matches nearby. Please enable location access in your settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w500,
                    fontSize: getProportionateScreenWidth(14),
                    color: const Color(0xFF666666),
                    height: 1.4,
                  ),
                ),
              ),
              SizedBox(height: getProportionateScreenHeight(24)),

              // Buttons
              Row(
                children: [
                  // Skip Button
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        await globals.prefs.locationPermissionDenied.set(true);
                        PermissionSessionManager.markLocationDeniedThisSession();
                        Navigator.pop(dialogContext, false);
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          vertical: getProportionateScreenHeight(14),
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kPrimaryPurple, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontWeight: FontWeight.w600,
                              fontSize: getProportionateScreenWidth(15),
                              color: kPrimaryPurple,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: getProportionateScreenWidth(12)),

                  // Settings Button
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Geolocator.openAppSettings();
                        Navigator.pop(dialogContext, true);
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          vertical: getProportionateScreenHeight(14),
                        ),
                        decoration: BoxDecoration(
                          color: kPrimaryPurple,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            'Settings',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontWeight: FontWeight.w600,
                              fontSize: getProportionateScreenWidth(15),
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

    return result ?? false;
  }

  /// Helper method to check if user profile is complete
  /// A complete profile must have all essential fields filled
  bool _isProfileComplete(UserDetails user) {
    // Check if essential profile fields exist
    if (user.name == null || user.name!.trim().isEmpty) {
      return false;
    }
    if (user.gender == null || user.gender!.isEmpty) {
      return false;
    }
    if (user.age == null || user.age! < 18) {
      return false;
    }
    if (user.dateOfBirth == null) {
      return false;
    }

    // Profile is complete
    return true;
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }
}
