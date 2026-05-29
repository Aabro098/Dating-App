import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:iconsax/iconsax.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tuple/tuple.dart';
import 'package:viora/Screens/AdminScreens/AdminHome.dart';
import 'package:viora/Screens/Home/homeScreen.dart';
import 'package:viora/Screens/MessagesScreen/new_message_screen.dart';
import 'package:viora/Screens/ProfileScreen/new_profile_view.dart';
import 'package:viora/components/verified_badge.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:viora/size_config.dart';
import 'package:viora/components/HomeFilterSheet.dart';
import 'package:viora/utils/helpers/image_helper.dart';
import '../../Services/Global.dart';
import '../../Services/HomeFilterStore.dart';
import '../../Services/AppConfigService.dart';
import '../../Services/ImageHelper.dart';
import 'package:viora/constants.dart';

// --- CONSTANTS ---
const kColorPinkActive = kTertiaryPink;
const kColorTextBlack = kBlack;

// --- TOP PICKS CONFIG ---
class TopPicksConfig {
  final Map<String, int> weights;
  final int scoreThreshold;

  // Default fallback weights if Firestore is empty or keys are missing
  static const Map<String, int> _defaultWeights = {
    'verified': 15,
    'photos': 15,
    'about': 10,
    'diet': 15,
    'zodiac': 5,
    'religion': 10,
    'smoker': 5,
    'drinking': 5,
    'interests': 20,
  };

  const TopPicksConfig({
    this.weights = _defaultWeights,
    this.scoreThreshold = 35,
  });

  factory TopPicksConfig.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return const TopPicksConfig();

    // Parse the 'weights' map from Firestore
    Map<String, int> parsedWeights = Map.from(_defaultWeights);

    if (data['weights'] != null && data['weights'] is Map) {
      final dataWeights = data['weights'] as Map<String, dynamic>;
      // Update defaults with values found in Firestore
      dataWeights.forEach((key, value) {
        if (value is int) {
          parsedWeights[key] = value;
        } else if (value is double) {
          parsedWeights[key] = value.toInt();
        }
      });
    }

    return TopPicksConfig(
      weights: parsedWeights,
      scoreThreshold: data['scoreThreshold'] ?? 35,
    );
  }
}

/// Calculate matching score for a user profile
double calculateTopPicksScore({
  required UserDetails targetUser,
  required UserDetails currentUser,
  required TopPicksConfig config,
}) {
  double totalScore = 0;

  // Helper to safely get weight
  int w(String key) => config.weights[key] ?? 0;

  // 1. Verified
  if (targetUser.isVerified == true) {
    totalScore += w('verified');
  }

  // 2. Photos (1 if min 1 photo)
  if ((targetUser.images?.length ?? 0) >= 1) {
    totalScore += w('photos');
  }

  // 3. About
  if (targetUser.about != null && targetUser.about!.isNotEmpty) {
    totalScore += w('about');
  }

  // 4. Diet
  if (targetUser.diet != null &&
      currentUser.diet != null &&
      targetUser.diet!.toLowerCase() == currentUser.diet!.toLowerCase()) {
    totalScore += w('diet');
  }

  // 5. Zodiac
  if (targetUser.zodiac != null &&
      currentUser.zodiac != null &&
      targetUser.zodiac!.toLowerCase() == currentUser.zodiac!.toLowerCase()) {
    totalScore += w('zodiac');
  }

  // 6. Religion
  if (targetUser.religion != null &&
      currentUser.religion != null &&
      targetUser.religion!.toLowerCase() ==
          currentUser.religion!.toLowerCase()) {
    totalScore += w('religion');
  }

  // 7. Smoker
  if (targetUser.smoker != null &&
      currentUser.smoker != null &&
      targetUser.smoker!.toLowerCase() == currentUser.smoker!.toLowerCase()) {
    totalScore += w('smoker');
  }

  // 8. Drinking
  if (targetUser.drinking != null &&
      currentUser.drinking != null &&
      targetUser.drinking!.toLowerCase() ==
          currentUser.drinking!.toLowerCase()) {
    totalScore += w('drinking');
  }

  // 9. Interests (1 if ≥2 matches)
  if (targetUser.interests != null && currentUser.interests != null) {
    final targetInterests = targetUser.interests!
        .map((e) => e.toLowerCase())
        .toSet();
    final currentInterests = currentUser.interests!
        .map((e) => e.toLowerCase())
        .toSet();
    final matchCount = targetInterests.intersection(currentInterests).length;
    if (matchCount >= 2) {
      totalScore += w('interests');
    }
  }

  return totalScore;
}

// --- HOOKS ---
class UserTabState {
  final int tabIndex;
  final Function(int) setTabIndex;
  final List<Query<Map<String, dynamic>>> queries;

  /// Opposite gender shown in the feed (matches Firestore query).
  final String genderToShow;
  final HomeFilterState filters;
  final Function(HomeFilterState) setFilters;
  final bool isTopPicksActive;
  final Function(bool) setTopPicksActive;
  final TopPicksConfig topPicksConfig;
  final bool isConfigLoading;

  UserTabState({
    required this.tabIndex,
    required this.setTabIndex,
    required this.queries,
    required this.genderToShow,
    required this.filters,
    required this.setFilters,
    required this.isTopPicksActive,
    required this.setTopPicksActive,
    required this.topPicksConfig,
    required this.isConfigLoading,
  });
}

// Custom Hook: Handles tab index state and prepares Firestore queries
UserTabState useUserTabs(BuildContext context, List<String> tabs) {
  final tabIndex = useState(0);
  // Persist filters and Top Picks across navigation - use HomeFilterStore
  final filters = useState(HomeFilterStore.filters);
  final isTopPicksActive = useState(HomeFilterStore.isTopPicksActive);
  final topPicksConfig = useState(const TopPicksConfig());
  final isConfigLoading = useState(true);
  final globals = Globals.of(context);
  final userGender = globals.prefs.userDetails.value?.gender;
  // Show opposite gender; if viewer hasn't set gender, default to Female (show Male users)
  final genderToShow = (userGender == null || userGender.isEmpty)
      ? "Female"
      : (userGender == "Female" ? "Male" : "Female");

  // Fetch Top Picks config from Firestore on mount
  useEffect(() {
    FirebaseFirestore.instance
        .collection('Config')
        .doc('topPicks')
        .get()
        .then((doc) {
          if (doc.exists) {
            topPicksConfig.value = TopPicksConfig.fromFirestore(doc.data());
            print(
              '✅ Top Picks config loaded. Weights: ${topPicksConfig.value.weights}',
            );
          } else {
            print('⚠️ No Top Picks config in Firestore, using defaults');
          }
          isConfigLoading.value = false;
        })
        .catchError((e) {
          print('❌ Error loading Top Picks config: $e');
          isConfigLoading.value = false;
        });
    return null;
  }, []);

  // useMemoized ensures queries are not rebuilt on every render
  final queries = useMemoized(
    () => [
      // Index 0: "All" — all marital statuses (incl. null/other); index: gender+isDisabled+lastOnline
      FirebaseFirestore.instance
          .collection('Users')
          .where("gender", isEqualTo: genderToShow)
          .where("isDisabled", isEqualTo: false)
          .orderBy("lastOnline", descending: true),

      // Index 1: "Single"
      FirebaseFirestore.instance
          .collection('Users')
          .where("gender", isEqualTo: genderToShow)
          .where('maritalStatus', isEqualTo: "Single")
          .where("isDisabled", isEqualTo: false)
          .orderBy("lastOnline", descending: true),

      // Index 2: "Married"
      FirebaseFirestore.instance
          .collection('Users')
          .where("gender", isEqualTo: genderToShow)
          .where('maritalStatus', isEqualTo: "Married")
          .where("isDisabled", isEqualTo: false)
          .orderBy("lastOnline", descending: true),

      // Index 3: "Divorced"
      FirebaseFirestore.instance
          .collection('Users')
          .where("gender", isEqualTo: genderToShow)
          .where('maritalStatus', isEqualTo: "Divorced")
          .where("isDisabled", isEqualTo: false)
          .orderBy("lastOnline", descending: true),
    ],
    [genderToShow],
  );

  return UserTabState(
    tabIndex: tabIndex.value,
    setTabIndex: (newIndex) => tabIndex.value = newIndex,
    queries: queries,
    genderToShow: genderToShow,
    filters: filters.value,
    setFilters: (newFilters) {
      HomeFilterStore.filters = newFilters;
      filters.value = newFilters;
    },
    isTopPicksActive: isTopPicksActive.value,
    setTopPicksActive: (active) {
      HomeFilterStore.isTopPicksActive = active;
      isTopPicksActive.value = active;
    },
    topPicksConfig: topPicksConfig.value,
    isConfigLoading: isConfigLoading.value,
  );
}

// Business Logic: Create user card info
class UserCardInfo {
  final String displayName;
  final String cityAndState;
  final String imageUrl;
  final bool isOnline;
  final String uid;
  final String gender;
  final List<String> images;
  final String? backgroundImageUrl;
  final bool isVerified;
  final String? messagePermission;

  UserCardInfo.fromUser(UserDetails user)
    : displayName = "${user.name}, ${user.age}",
      cityAndState = "${user.city}, ${user.state}",
      imageUrl = (user.images?.isEmpty ?? true)
          ? AppConfigService.getPlaceholderImageUrl(user.gender)
          : user.images![0],
      isOnline = user.isOnline ?? false,
      uid = user.uid,
      gender = user.gender ?? "",
      images = user.images ?? [],
      backgroundImageUrl = (user.images?.isEmpty ?? true)
          ? ImageHelper.getConsistentBackgroundForUser(user.uid)
          : null,
      isVerified = user.isVerified ?? false,
      messagePermission = user.messagePermission ?? "All";
}

String? _cachedAdminStatusUid;
bool? _cachedIsAdmin;
Future<bool>? _adminStatusInFlight;

Tuple2<bool, bool> useAdminStatus(BuildContext context) {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final hasCachedValue =
      _cachedAdminStatusUid == currentUserId && _cachedIsAdmin != null;
  final isAdmin = useState<bool>(hasCachedValue ? _cachedIsAdmin! : false);
  final isLoading = useState<bool>(!hasCachedValue);

  useEffect(() {
    Future<void> fetchAdminData() async {
      if (currentUserId == null) {
        _cachedAdminStatusUid = null;
        _cachedIsAdmin = false;
        if (context.mounted) {
          isAdmin.value = false;
          isLoading.value = false;
        }
        return;
      }

      if (_cachedAdminStatusUid == currentUserId && _cachedIsAdmin != null) {
        if (context.mounted) {
          isAdmin.value = _cachedIsAdmin!;
          isLoading.value = false;
        }
        return;
      }

      final pendingFetch = _adminStatusInFlight ??= FirebaseFirestore.instance
          .collection("Admins")
          .doc('admins')
          .get()
          .then((doc) {
            final admins = doc.data()?['admins'] as List<dynamic>? ?? [];
            return admins.contains(currentUserId);
          })
          .whenComplete(() {
            _adminStatusInFlight = null;
          });

      try {
        final adminValue = await pendingFetch;
        _cachedAdminStatusUid = currentUserId;
        _cachedIsAdmin = adminValue;
        if (context.mounted) {
          isAdmin.value = adminValue;
        }
      } catch (e) {
        _cachedAdminStatusUid = currentUserId;
        _cachedIsAdmin = false;
        if (context.mounted) {
          isAdmin.value = false;
        }
      } finally {
        if (context.mounted) {
          isLoading.value = false;
        }
      }
    }

    fetchAdminData();
    return null; // No cleanup
  }, []);

  return Tuple2(isAdmin.value, isLoading.value);
}

// --- MAIN WIDGET ---

class HomeContent extends HookWidget {
  final filterOptions = const ["All", "Single", "Married", "Divorced"];

  const HomeContent({super.key});

  @override
  Widget build(BuildContext context) {
    final configFuture = useMemoized(() async {
      if (!AppConfigService.isLoaded) {
        await AppConfigService.loadConfig();
      }
    }, []);

    final configSnapshot = useFuture(configFuture);
    if (configSnapshot.connectionState != ConnectionState.done) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final adminStatus = useAdminStatus(context);
    final bool isAdmin = adminStatus.item1;
    // final bool isLoading = adminStatus.item2;
    final userTabs = useUserTabs(context, filterOptions);
    final globals = Globals.of(context);
    final currentUser = globals.prefs.userDetails.value;
    final currentUserLat = currentUser?.latitude;
    final currentUserLon = currentUser?.longitude;
    final currentUserPhotoCount = currentUser?.images?.length ?? 0;

    // Filter users client-side based on filter state
    bool passesFilter(UserDetails user) {
      final filters = userTabs.filters;

      // Exclude current user from feed
      if (currentUser != null && user.uid == currentUser.uid) return false;

      // Age filter
      final userAge = user.age ?? 18;
      if (userAge < filters.ageRange.start || userAge > filters.ageRange.end) {
        return false;
      }

      // Distance filter
      if (!filters.showAllPeople) {
        if (user.latitude == null || user.longitude == null) {
          return false;
        }

        if (currentUserLat != null && currentUserLon != null) {
          final distance =
              Geolocator.distanceBetween(
                currentUserLat,
                currentUserLon,
                user.latitude!,
                user.longitude!,
              ) /
              1000; // Convert to km

          if (distance > filters.maxDistance) {
            return false;
          }
        }
      }

      // Relation type filter (sheet): if user picked types, require overlap; missing relTypes = no match
      if (filters.relationTypes.isNotEmpty) {
        if (user.relTypes == null || user.relTypes!.isEmpty) {
          return false;
        }
        final userRelTypes = user.relTypes!.map((e) => e.toLowerCase()).toSet();
        final filterRelTypes = filters.relationTypes
            .map((e) => e.toLowerCase())
            .toSet();
        if (userRelTypes.intersection(filterRelTypes).isEmpty) {
          return false;
        }
      }

      // Premium filters
      if (filters.onlyVerifiedProfiles && !(user.isVerified ?? false)) {
        return false;
      }
      if (filters.onlyOnlineUsers && !(user.isOnline ?? false)) return false;

      if (filters.minPhotos > 1) {
        final photoCount = user.images?.length ?? 0;
        if (photoCount < filters.minPhotos) return false;
      }

      return true;
    }

    // final HomeController controller = Get.find<HomeController>();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 1. Custom Header
          _buildCustomHeader(context, userTabs, currentUserPhotoCount, isAdmin),

          // 2. The Content Grid
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                // The query builder handles the actual data fetch
              },
              child: FirestoreQueryBuilder<Map<String, dynamic>>(
                // Only tab + gender affect the Firestore query. Filters & Top Picks are
                // client-side; including them in the key was recreating this widget, resetting
                // the snapshot listener and pagination so new users often failed to appear live.
                key: ValueKey(
                  'home_users_${userTabs.genderToShow}_${userTabs.tabIndex}',
                ),
                query: userTabs.queries[userTabs.tabIndex],
                pageSize: 100,
                builder: (context, snapshot, _) {
                  if (snapshot.isFetching && snapshot.docs.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    final error = snapshot.error;
                    final isAuthTearDown =
                        FirebaseAuth.instance.currentUser == null;
                    final isPermissionDenied =
                        error is FirebaseException &&
                        error.code == 'permission-denied';

                    // During logout/account deletion, auth can be torn down before this
                    // stream widget disposes; suppress transient permission-denied UI.
                    if (isAuthTearDown && isPermissionDenied) {
                      return const SizedBox.shrink();
                    }
                    return Center(child: Text("Error: ${snapshot.error}"));
                  }

                  var filteredDocs = snapshot.docs.where((doc) {
                    final user = UserDetails.fromJson(doc.data());
                    return passesFilter(user);
                  }).toList();

                  // Apply Top Picks filtering and scoring if active
                  if (userTabs.isTopPicksActive && currentUser != null) {
                    final scoredDocs =
                        <
                          ({
                            QueryDocumentSnapshot<Map<String, dynamic>> doc,
                            double score,
                            bool isOnline,
                          })
                        >[];

                    for (final doc in filteredDocs) {
                      final user = UserDetails.fromJson(doc.data());
                      final userPhotoCount = user.images?.length ?? 0;

                      // Photo Segregation Logic
                      if (currentUserPhotoCount >= 1 && userPhotoCount < 1) {
                        continue;
                      }
                      if (currentUserPhotoCount == 0 && userPhotoCount >= 1) {
                        continue;
                      }

                      final score = calculateTopPicksScore(
                        targetUser: user,
                        currentUser: currentUser,
                        config: userTabs.topPicksConfig,
                      );

                      if (score >= userTabs.topPicksConfig.scoreThreshold) {
                        scoredDocs.add((
                          doc: doc,
                          score: score,
                          isOnline: user.isOnline ?? false,
                        ));
                      }
                    }

                    // Sort: Group by online (online first), then by score descending
                    scoredDocs.sort((a, b) {
                      if (a.isOnline != b.isOnline) {
                        return a.isOnline ? -1 : 1;
                      }
                      return b.score.compareTo(a.score);
                    });

                    filteredDocs = scoredDocs.map((e) => e.doc).toList();
                  } else {
                    // Default sorting: Sort by online status (online users first)
                    filteredDocs.sort((a, b) {
                      final userA = UserDetails.fromJson(a.data());
                      final userB = UserDetails.fromJson(b.data());
                      final isOnlineA = userA.isOnline ?? false;
                      final isOnlineB = userB.isOnline ?? false;

                      if (isOnlineA == isOnlineB) return 0;
                      return isOnlineA ? -1 : 1;
                    });
                  }

                  if (filteredDocs.isEmpty && !snapshot.hasMore) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            userTabs.isTopPicksActive
                                ? Icons.star_outline
                                : Icons.filter_list_off,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            userTabs.isTopPicksActive
                                ? "No Top Picks found"
                                : "No Users found",
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                          if (userTabs.filters.hasActiveFilters ||
                              userTabs.isTopPicksActive) ...[
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () {
                                userTabs.setFilters(const HomeFilterState());
                                userTabs.setTopPicksActive(false);
                              },
                              child: Text(
                                userTabs.isTopPicksActive
                                    ? 'Disable Top Picks'
                                    : 'Clear filters',
                                style: TextStyle(
                                  color: kSecondaryPurple,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  // Fetch more when client-side filters / Top Picks thin out visible rows.
                  final thinFeed =
                      userTabs.filters.hasActiveFilters ||
                      userTabs.isTopPicksActive;
                  final minVisibleTarget = thinFeed ? 12 : 6;
                  if (filteredDocs.length < minVisibleTarget &&
                      snapshot.hasMore &&
                      !snapshot.isFetchingMore) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      snapshot.fetchMore();
                    });
                  }

                  return GridView.builder(
                    key: const PageStorageKey('home_user_list'),
                    addAutomaticKeepAlives: true,
                    padding: EdgeInsets.only(
                      top: getProportionateScreenHeight(10),
                      left: getProportionateScreenWidth(16),
                      right: getProportionateScreenWidth(16),
                      bottom: getProportionateScreenHeight(10),
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 177 / 195, // Made taller cards
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 6, // Reduced row spacing
                        ),
                    itemCount: filteredDocs.length + (snapshot.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (snapshot.hasMore && index == filteredDocs.length) {
                        snapshot.fetchMore();
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (index >= filteredDocs.length) {
                        return const SizedBox.shrink();
                      }

                      final data = filteredDocs[index].data();
                      final cardInfo = UserCardInfo.fromUser(
                        UserDetails.fromJson(data),
                      );
                      return UserCard(info: cardInfo);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomHeader(
    BuildContext context,
    UserTabState userTabs,
    int currentUserPhotoCount,
    bool isAdmin,
  ) {
    return Container(
      width: double.infinity,
      height: 140,
      decoration: const BoxDecoration(
        color: Color(0xFFFFF9F9),
        border: Border(
          bottom: BorderSide(color: Color(0xFFFFACAC), width: 1.5),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -97,
            top: -90,
            child: Transform(
              transform: Matrix4.identity()..scale(-1.0, 1.0),
              alignment: Alignment.center,
              child: Image.asset(
                "assets/icon/viora_transparent.png",
                width: 270,
                height: 210,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            right: -120,
            top: -97,
            child: Image.asset(
              "assets/icon/viora_transparent.png",
              width: 360,
              height: 270,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            left: 23,
            top: 32 + MediaQuery.of(context).padding.top * 0.5,
            child: GestureDetector(
              // onTap: () => Navigator.pushNamed(context, '/supportScreen'),
              onTap: () {
                showSupportScreenValue.value = true;
              },
              child: Container(
                width: getProportionateScreenWidth(41),
                height: getProportionateScreenHeight(41),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9D9D9).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SvgPicture.asset(
                  "assets/svg/chat_ai.svg",
                  width: 24,
                  height: 24,
                ),
              ),
            ),
          ),
          if (isAdmin) ...[
            Positioned(
              left: 82,
              top: 32 + MediaQuery.of(context).padding.top * 0.5,
              child: GestureDetector(
                onTap: () async {
                  PersistentNavBarNavigator.pushNewScreen(
                    context,
                    screen: AdminHome(),
                    withNavBar: false,
                    pageTransitionAnimation: PageTransitionAnimation.cupertino,
                  );
                },
                child: Container(
                  width: getProportionateScreenWidth(41),
                  height: getProportionateScreenHeight(41),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9D9D9).withAlpha(80),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Iconsax.security_user,
                    size: 24,
                    color: kSecondaryPurple,
                  ),
                ),
              ),
            ),
          ],
          Positioned(
            right: 75,
            top: 32 + MediaQuery.of(context).padding.top * 0.5,
            child: GestureDetector(
              onTap: () {
                // If activating Top Picks and filters are applied, reset filters first
                if (!userTabs.isTopPicksActive &&
                    userTabs.filters.hasActiveFilters) {
                  userTabs.setFilters(const HomeFilterState());
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Filters reset for Top Picks'),
                      duration: Duration(seconds: 2),
                      backgroundColor: kSecondaryPurple,
                    ),
                  );
                }
                userTabs.setTopPicksActive(!userTabs.isTopPicksActive);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 41,
                        height: 41,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: userTabs.isTopPicksActive
                              ? kPrimaryPurple.withOpacity(0.2)
                              : const Color(0xFFD9D9D9).withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SvgPicture.asset(
                          "assets/svg/benefits_star.svg",
                          color: userTabs.isTopPicksActive
                              ? kTertiaryPink
                              : kPrimaryPurple,
                          width: 22,
                          height: 22,
                        ),
                      ),
                      if (userTabs.isTopPicksActive)
                        Positioned(
                          right: 2,
                          top: 16.5,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: kTertiaryPink,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  // if (userTabs.isTopPicksActive) ...[const SizedBox(height: 4),
                  //   Text(
                  //     'Top Picks',
                  //     style: const TextStyle(
                  //       fontFamily: 'Nunito',
                  //       fontSize: 10,
                  //       fontWeight: FontWeight.w600,
                  //       color: kTertiaryPink,
                  //     ),
                  //   ),
                  // ],
                ],
              ),
            ),
          ),
          Positioned(
            right: 23,
            top: 32 + MediaQuery.of(context).padding.top * 0.5,
            child: GestureDetector(
              onTap: () async {
                final result = await showHomeFilterSheet(
                  context: context,
                  currentFilters: userTabs.filters,
                  currentUserPhotoCount: currentUserPhotoCount,
                  isTopPicksActive: userTabs.isTopPicksActive,
                );
                if (result != null) userTabs.setFilters(result);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 41,
                        height: 41,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9D9D9).withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SvgPicture.asset(
                          "assets/svg/filter_home.svg",
                          width: 22,
                          height: 22,
                        ),
                      ),
                      if (userTabs.filters.hasActiveFilters)
                        Positioned(
                          right: 2,
                          top: 16.5,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: kTertiaryPink,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  // if (userTabs.filters.hasActiveFilters) ...[const SizedBox(height: 4),
                  //   Text(
                  //     'Filters',
                  //     style: const TextStyle(
                  //       fontFamily: 'Nunito',
                  //       fontSize: 10,
                  //       fontWeight: FontWeight.w600,
                  //       color: kTertiaryPink,
                  //     ),
                  //   ),
                  // ],
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 17,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(filterOptions.length, (index) {
                final isSelected = userTabs.tabIndex == index;
                return GestureDetector(
                  onTap: () => userTabs.setTabIndex(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      filterOptions[index],
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? kColorPinkActive : kColorTextBlack,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// --- USER CARD ---
class UserCard extends StatefulWidget {
  final UserCardInfo info;

  const UserCard({super.key, required this.info});

  @override
  State<UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<UserCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final profileImage = widget.info.imageUrl;
    return GestureDetector(
      onTap: () {
        showViewProfileScreen.value = widget.info.uid;
      },
      child: SizedBox(
        width: getProportionateScreenWidth(177),
        height: getProportionateScreenHeight(212),
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  imageUrl: widget.info.backgroundImageUrl ?? '',
                  placeholder: (context, url) =>
                      Container(color: Colors.grey[300]),
                  placeholderFadeInDuration: Duration.zero,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  errorWidget: (context, url, error) {
                    return Container(color: Colors.grey[300]);
                  },
                ),
              ),
            ),
            // Foreground Image (Profile or Placeholder)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ReactiveProfileImage(
                  imagePath: profileImage,
                  gender: widget.info.gender,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
            // Active Status Badge
            Positioned(
              left: 6,
              top: 6,
              child: widget.info.isOnline
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFBFFFBF),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Text(
                        "Active",
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 11,
                          color: Color(0xFF16AC16),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // Verified Badge (if user is verified)
            Positioned(
              right: 6,
              top: 6,
              child: widget.info.isVerified
                  ? VerifiedBadge()
                  : const SizedBox.shrink(),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 53,
                // 1. Define the shape here
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  ),
                ),
                // 2. Force content (including blur) to stay inside the shape
                clipBehavior: Clip.hardEdge,
                child: Stack(
                  children: [
                    // Layer 1: The Blur
                    Positioned.fill(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10.05, sigmaY: 10.05),
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                    // Layer 2: The Content & Overlay Color
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF3E1E68).withOpacity(0.18),
                        border: Border(
                          top: BorderSide(
                            color: const Color(0xFFFEFEFE).withOpacity(0.5),
                            width: 0.8,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    widget.info.displayName,
                                    style: const TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  Text(
                                    widget.info.cityAndState,
                                    style: const TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFFDFDFDF),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                final currentUserId =
                                    FirebaseAuth.instance.currentUser?.uid;
                                if (currentUserId == null) {
                                  showSimpleNotification(
                                    Text("Error: User not authenticated"),
                                    background: Colors.red,
                                    duration: Duration(seconds: 2),
                                  );
                                  return;
                                }

                                final hasLiked = await hasUserLikedMyProfile(
                                  widget.info.uid,
                                  currentUserId,
                                );
                                final permission = widget.info.messagePermission
                                    ?.toLowerCase();

                                final canMessage =
                                    hasLiked ||
                                    permission == null ||
                                    permission == "all";

                                if (!canMessage) {
                                  showSimpleNotification(
                                    const Text(
                                      "This profile allows chats only with matched or liked profiles",
                                    ),
                                    background: Colors.orange,
                                    duration: const Duration(seconds: 3),
                                    position: NotificationPosition.top,
                                    slideDismissDirection:
                                        DismissDirection.down,
                                    leading: const Icon(Icons.info),
                                  );
                                  return;
                                }
                                PersistentNavBarNavigator.pushNewScreen(
                                  context,
                                  screen: NewMessagesScreen(
                                    uId: widget.info.uid,
                                  ),
                                  withNavBar: false,
                                  pageTransitionAnimation:
                                      PageTransitionAnimation.cupertino,
                                );
                              },
                              child: SizedBox(
                                width: getProportionateScreenWidth(19.98),
                                height: getProportionateScreenHeight(17.95),
                                child: SvgPicture.asset(
                                  'assets/svg/user_chat.svg',
                                  colorFilter: const ColorFilter.mode(
                                    Colors.white,
                                    BlendMode.srcIn,
                                  ),
                                  width: 18,
                                  height: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/*
---------------------------------------------------
How the architecture fits together and its benefits:
---------------------------------------------------
- UI state (selected tab) is handled with a custom Hook (`useUserTabs`) using HookWidget.
- All Firestore queries are built in custom hooks, not in the widget tree.
- Business logic such as user card mapping is fully stateless and testable in `UserCardInfo`.
- The HomeContent widget itself only "glues" hooks, business logic, and backend data to UI widgets.
- Testability is greatly improved: queries, business mapping, and UI each testable independently.
- UI components (UserCard) are stateless and parameterized.
- Clean separation of UI, business logic, and backend access per best practices[web:1][web:2][web:3][web:4][web:5][web:6][web:8].
*/
