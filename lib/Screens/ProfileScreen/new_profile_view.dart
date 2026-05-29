import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:provider/provider.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:viora/Screens/Home/homeScreen.dart';
import 'package:viora/Screens/MessagesScreen/new_message_screen.dart';
import 'package:viora/Services/AppConfigService.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/Services/NotificationService.dart';
import 'package:viora/Services/UserProvider.dart';
import 'package:viora/components/reusable_dialog.dart';
import 'package:viora/components/verified_badge.dart';
import 'package:viora/models/ProfileAction.dart';
import 'package:viora/models/ReportedUser.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:viora/size_config.dart';
import 'package:viora/utils/constatnts/colors.dart';
import 'package:viora/utils/helpers/location_helper.dart';
import 'package:viora/utils/helpers/profile_view_helper.dart';

/// Custom Hook: useUserDetails
/// Fetches user details from Firestore for given uid and manages loading state.
/// Separates backend calls from UI, reusable and testable.
UserDetails? _parseUserDetails(DocumentSnapshot doc) {
  if (!doc.exists || doc.data() == null) return null;

  final user = UserDetails.fromJson(doc.data() as Map<String, dynamic>);
  if (user.relTypes?.contains("Purely sexual") ?? false) {
    user.relTypes!.remove("Purely sexual");
  }
  return user;
}

Future<UserDetails?> fetchUserDetails(String uid) async {
  final doc = await FirebaseFirestore.instance
      .collection("Users")
      .doc(uid)
      .get();
  return _parseUserDetails(doc);
}

final Set<String> _sentViewNotifications = {};

/// Check if a user (targetUid) has added the currentUid as a crush
Future<bool> hasUserLikedMyProfile(String targetUid, String currentUid) async {
  try {
    final doc = FirebaseFirestore.instance
        .collection("Users")
        .doc(targetUid)
        .collection('MyCrush');
    QuerySnapshot myCrush = await doc.get();
    for (var postDoc in myCrush.docs) {
      if (postDoc.data() != null && postDoc.get('uid') == currentUid) {
        return true;
      }
    }
    return false;
  } catch (e) {
    debugPrint("Error checking if user liked profile: $e");
    return false;
  }
}

void sendViewNotification(String uid, String? fcmToken, BuildContext context) {
  // Prevent self-views - don't add notification if viewing own profile
  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null || userId == uid) {
    return; // Don't send view notification for own profile
  }

  // Prevent duplicate view notifications in same session
  final key = '${userId}_$uid';
  // if (_sentViewNotifications.contains(key)) {
  //   debugPrint('🔔 View notification already sent to $uid in this session');
  //   return;
  // }

  if (fcmToken != null) {
    _sentViewNotifications.add(key);
    NotificationService.addNotification(uid, fcmToken, "View", context);
  }
}

/// Hook that manages the user details loading and notification side effect
UserDetails? useUserDetails(String uid, BuildContext context) {
  final userDetails = useState<UserDetails?>(null);
  final isLoading = useState<bool>(true);

  useEffect(() {
    bool isMounted = true;

    fetchUserDetails(uid).then((user) {
      if (isMounted && user != null) {
        userDetails.value = user;
        final viewerId = FirebaseAuth.instance.currentUser?.uid;
        if (viewerId != null) {
          // Use priority-based method: Crush/Fav > View
          DatabaseService.markIncomingProfileActionSeenWithPriority(
            viewerId,
            uid,
          );
        }
        sendViewNotification(uid, user.fcmToken, context);
        isLoading.value = false;
      }
    });

    return () => isMounted = false;
  }, [uid]);

  return userDetails.value;
}

class NewProfileView extends HookWidget {
  final String uid;
  final bool? canPop;

  const NewProfileView({super.key, required this.uid, this.canPop});

  static String routeName = "/profilescreen";

  @override
  Widget build(BuildContext context) {
    final globals = Globals.of(context);
    final user = useUserDetails(uid, context);
    final pageController = usePageController();
    final scrollController = useScrollController();
    final imageHeight = useState(getProportionateScreenHeight(492.0));
    final isImageTapped = useState<bool>(false);
    final isAboutExpanded = useState<bool>(false);
    final showLikedBadge = useState<bool>(false);
    final cachedBackgroundImage = useState<String?>(null);
    final resetGallery = useState<bool>(false);

    final imageExpandProgress = useState<double>(0.0);
    final currentPageIndex = useState<int>(0);

    // Cache the background image once on first build
    useEffect(() {
      cachedBackgroundImage.value ??=
          AppConfigService.getRandomBackgroundImage();
      return null;
    }, []);

    useEffect(() {
      // Listen to page changes
      void handlePageChange() {
        currentPageIndex.value = pageController.page?.round() ?? 0;
      }

      pageController.addListener(handlePageChange);
      return () => pageController.removeListener(handlePageChange);
    }, [pageController]);

    final userDetails = useListenable(globals.prefs.userDetails);

    final currentUserLocation = useState<bool>(
      userDetails.value?.latitude != null &&
          userDetails.value?.longitude != null,
    );
    // Newly Added: Listen to changes in userDetails to update location availability
    // Update currentUserLocation when userDetails changes (e.g., after enabling location)
    useEffect(() {
      currentUserLocation.value =
          userDetails.value?.latitude != null &&
          userDetails.value?.longitude != null;
      return null;
    }, [userDetails.value?.latitude, userDetails.value?.longitude]);

    // Listen to scroll events but keep image height at 492
    useEffect(() {
      void handleScroll() {
        // Keep image height at 492, do not change during scroll
        imageHeight.value = getProportionateScreenHeight(492.0);
      }

      scrollController.addListener(handleScroll);
      return () => scrollController.removeListener(handleScroll);
    }, [scrollController, imageHeight]);

    // Auto-hide liked badge after 2 seconds
    useEffect(() {
      if (showLikedBadge.value) {
        Future.delayed(Duration(seconds: 2), () {
          showLikedBadge.value = false;
        });
      }
      return null;
    }, [showLikedBadge.value]);

    if (user == null) {
      return PopScope(
        canPop: canPop ?? false,
        onPopInvokedWithResult: (didPop, result) {
          if (canPop == true) {
            Navigator.of(context).pop();
          }
          showViewProfileScreen.value = null;
        },
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: getProportionateScreenWidth(24),
              height: getProportionateScreenHeight(24),
              child: CircularProgressIndicator(
                color: AppColors.purple,
                strokeWidth: 4,
              ),
            ),
          ),
        ),
      );
    }

    ValueNotifier<bool> userCrushOrNot(String uid) {
      final isAlreadyCrush = useState<bool>(false);
      useEffect(() {
        Future<void> fetchMyCrushList() async {
          final doc = FirebaseFirestore.instance
              .collection("Users")
              .doc(FirebaseAuth.instance.currentUser?.uid)
              .collection('MyCrush');
          QuerySnapshot myCrush = await doc.get();
          for (var postDoc in myCrush.docs) {
            if (postDoc.data() != null) {
              if (postDoc.get('uid') == uid) {
                debugPrint("VinayCrush ${postDoc.data()}");
                isAlreadyCrush.value = true;
              }
            }
          }
        }

        fetchMyCrushList();
        return null;
      }, []);
      return isAlreadyCrush;
    }

    final images =
        user.images ??
        [
          user.gender?.toLowerCase() == "male"
              ? AppConfigService.maleImageUrl
              : AppConfigService.femaleImageUrl,
        ];

    final questionValuesFirst = [
      QuestionValues(question: "Work", value: user.work),
      QuestionValues(question: "Education", value: user.education),
      QuestionValues(
        question: "Looking for relationship type",
        options: user.relTypes,
      ),
      QuestionValues(question: "Marital Status", value: user.maritalStatus),
      QuestionValues(
        question: "Sexual Orientation",
        options: user.sexualOrientation,
      ),

      QuestionValues(question: "Nationality", value: user.nationality),
      QuestionValues(
        question: "Height",
        value: user.height != null ? "${user.height} cm" : null,
      ),
      QuestionValues(question: "Zodiac Sign", value: user.zodiac),
      QuestionValues(question: "Diet", value: user.diet),
      QuestionValues(question: "Religion", value: user.religion),
    ];

    final isAlreadyACrush = userCrushOrNot(uid);

    return PopScope(
      canPop: canPop ?? false,
      onPopInvokedWithResult: (didPop, result) {
        showViewProfileScreen.value = null;
      },
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final media = MediaQuery.of(context);
            final topInset = media.padding.top;

            final h = constraints.maxHeight;
            final t = imageExpandProgress.value.clamp(0.0, 1.0);

            final minImageHeight = h * 0.60;
            final maxImageHeight = h * 0.74;
            final maxOverlap = h * 0.10;
            final buttonOffset = h * 0.05;

            final currentImageHeight = lerpDouble(
              minImageHeight,
              maxImageHeight,
              t,
            )!;

            final overlap = (1 - t) * maxOverlap;

            final bottomSheetTop = (currentImageHeight - overlap).clamp(
              0.0,
              double.infinity,
            );

            final buttonsTop = (currentImageHeight - buttonOffset - overlap)
                .clamp(0.0, double.infinity);

            return SingleChildScrollView(
              controller: scrollController,
              physics: isImageTapped.value
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GestureDetector(
                        onTap: () {
                          isImageTapped.value = true;
                          imageExpandProgress.value = 1.0;
                        },
                        child: SizedBox(
                          height: currentImageHeight,
                          width: double.infinity,
                          child: buildImage(
                            context,
                            images,
                            user.gender ?? "Male",
                            pageController,
                            cachedBackgroundImage.value,
                            currentPageIndex.value,
                            isImageTapped,
                            resetGallery,
                            currentPageIndex,
                          ),
                        ),
                      ),
                      Container(
                        margin: EdgeInsets.only(
                          top:
                              bottomSheetTop -
                              (isImageTapped.value ? topInset : 0),
                        ),
                        child: bottomSheet(
                          context,
                          user,
                          questionValuesFirst,
                          isImageTapped,
                          isAboutExpanded,
                          currentUserLocation,
                          userDetails.value?.latitude,
                          userDetails.value?.longitude,
                          isImageTapped,
                          imageExpandProgress,
                          resetGallery,
                        ),
                      ),

                      Positioned(
                        top: buttonsTop + (isImageTapped.value ? 0 : topInset),
                        left: 0,
                        right: 0,
                        child: actionButtons(
                          context,
                          user,
                          isAlreadyACrush,
                          showLikedBadge,
                        ),
                      ),

                      if (showLikedBadge.value)
                        Positioned(
                          top: h * 0.25,
                          left: (constraints.maxWidth / 2) - 102,
                          child: Transform.rotate(
                            angle: -0.2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(100),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.purple,
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Text(
                                    "LIKED",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 30,
                                    ),
                                  ),
                                  SizedBox(width: constraints.maxWidth * 0.02),
                                  Image.asset(
                                    "assets/icon/love_filled.png",
                                    height: h * 0.037,
                                    width: constraints.maxWidth * 0.08,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget actionButtons(
    BuildContext context,
    UserDetails user,
    ValueNotifier<bool> isAlreadyACrush,
    ValueNotifier<bool> showLikedBadge,
  ) {
    ProfileAction createProfileAction(String uid) {
      return ProfileAction(date: DateTime.now(), uid: uid);
    }

    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () {
              showViewProfileScreen.value = null;
              if (canPop == true) {
                Navigator.of(context).pop();
              }
            },
            child: Container(
              width: getProportionateScreenWidth(60),
              height: getProportionateScreenHeight(60),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Color(0xFFDADADA), width: 2),
              ),
              child: Icon(
                Icons.arrow_back,
                color: AppColors.purple,
                size: getProportionateScreenWidth(32),
              ),
            ),
          ),
          SizedBox(width: getProportionateScreenWidth(12)),
          GestureDetector(
            onTap: () {
              // Prevent duplicate crush - check if already added
              if (isAlreadyACrush.value) {
                showSimpleNotification(
                  Text("Already added as your Crush"),
                  background: Colors.orange,
                  duration: Duration(seconds: 2),
                  position: NotificationPosition.top,
                  slideDismiss: true,
                  leading: Icon(Icons.info),
                );
                return;
              }

              isAlreadyACrush.value = true;
              showLikedBadge.value = true;
              showSimpleNotification(
                Text("Added as your Crush"),
                background: Colors.green,
                duration: Duration(seconds: 4),
                position: NotificationPosition.top,
                slideDismiss: true,
                leading: Icon(Icons.verified),
              );
              final action = createProfileAction(uid);
              DatabaseService.addCrush(
                FirebaseAuth.instance.currentUser!.uid,
                action,
              );
              NotificationService.addNotification(
                uid,
                user.fcmToken,
                "Crush",
                context,
              );
            },
            child: Container(
              width: getProportionateScreenWidth(78),
              height: getProportionateScreenHeight(78),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Color(0xFFDADADA), width: 2),
              ),
              child: Image.asset(
                isAlreadyACrush.value
                    ? "assets/icon/love_filled.png"
                    : "assets/icon/love_icon.png",
                height: getProportionateScreenHeight(52),
                width: getProportionateScreenWidth(52),
              ),
            ),
          ),
          SizedBox(width: getProportionateScreenWidth(12)),
          GestureDetector(
            onTap: () async {
              final currentUserId = FirebaseAuth.instance.currentUser?.uid;
              if (currentUserId == null) {
                showSimpleNotification(
                  Text("Error: User not authenticated"),
                  background: Colors.red,
                  duration: Duration(seconds: 2),
                );
                return;
              }

              final hasLiked = await hasUserLikedMyProfile(uid, currentUserId);
              final permission = user.messagePermission?.toLowerCase();

              final canMessage =
                  hasLiked || permission == null || permission == "all";

              if (!canMessage) {
                showSimpleNotification(
                  const Text(
                    "This profile allows chats only with matched or liked profiles",
                  ),
                  background: Colors.orange,
                  duration: const Duration(seconds: 3),
                  position: NotificationPosition.top,
                  slideDismissDirection: DismissDirection.down,
                  leading: const Icon(Icons.info),
                );
                return;
              }

              await PersistentNavBarNavigator.pushNewScreen(
                context,
                screen: NewMessagesScreen(uId: user.uid),
                withNavBar: false,
                pageTransitionAnimation: PageTransitionAnimation.cupertino,
              );
            },
            child: Container(
              width: getProportionateScreenWidth(60),
              height: getProportionateScreenHeight(60),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Color(0xFFDADADA), width: 2),
              ),
              child: Image.asset(
                "assets/icon/message.png",
                height: getProportionateScreenHeight(24),
                width: getProportionateScreenWidth(26),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildImage(
    BuildContext context,
    List<String> images,
    String gender,
    PageController controller,
    String? cachedBgImage,
    int currentPage,
    ValueNotifier<bool> isImageTapped,
    ValueNotifier<bool> resetGallery,
    ValueNotifier<int> currentPageIndex,
  ) {
    final pt = getProportionateScreenWidth(12);
    return Padding(
      padding: EdgeInsets.fromLTRB(0, pt, 0, 0),
      child: Stack(
        children: [
          Positioned.fill(
            child: cachedBgImage != null && cachedBgImage.isNotEmpty
                ? Padding(
                    padding: EdgeInsets.symmetric(horizontal: pt),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CachedNetworkImage(
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        imageUrl: cachedBgImage,
                        placeholder: (context, url) =>
                            Container(color: Colors.grey[300]),
                      ),
                    ),
                  )
                : Container(color: Colors.grey[300]),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pt),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: CachedNetworkImage(
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      imageUrl: cachedBgImage ?? '',
                      placeholder: (context, url) =>
                          Container(color: Colors.grey[300]),
                      errorWidget: (context, url, error) {
                        return Container(color: Colors.grey[300]);
                      },
                    ),
                  ),
                ),
                ReactiveProfileGallery(
                  images: images,
                  gender: gender,
                  controller: controller,
                  borderRadius: BorderRadius.circular(
                    getProportionateScreenWidth(12),
                  ),
                  resetTrigger: resetGallery,
                  isImageTapped: isImageTapped.value,
                  currentPageIndex: currentPageIndex.value,
                  onPageChanged: (index) {
                    currentPageIndex.value = index;
                  },
                ),
              ],
            ),
          ),
          if (images.length > 1)
            Positioned(
              top: 20,
              left: pt,
              right: pt,
              child: Center(
                child: SmoothPageIndicator(
                  controller: controller,
                  count: images.length,
                  effect: WormEffect(
                    dotWidth:
                        (SizeConfig.screenWidth -
                            getProportionateScreenWidth(72)) /
                        images.length,
                    dotHeight: getProportionateScreenHeight(6),
                    activeDotColor: Colors.white,
                    dotColor: Colors.black54,
                  ),
                ),
              ),
            ),
          Positioned(
            top: 36,
            right: 30,
            child: GestureDetector(
              onTap: () async {
                ReusableDialog.show(
                  context,
                  "Report User",
                  "Are you sure you want to report\nthis user?",
                  "Report User",
                  onConfirm: () async {
                    ReportedUser report = ReportedUser(
                      date: DateTime.now(),
                      reportedByUid: FirebaseAuth.instance.currentUser!.uid,
                      reportedUid: uid,
                    );
                    await DatabaseService.reportUsers(report, context);
                    showViewProfileScreen.value = null;
                  },
                );
              },
              child: Icon(
                Icons.more_horiz,
                color: AppColors.purple,
                size: getProportionateScreenHeight(30),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget bottomSheet(
    BuildContext context,
    UserDetails user,
    List<QuestionValues> questionValuesFirst,
    ValueNotifier<bool> isExpand,
    // ValueNotifier<double> imageHeight,
    ValueNotifier<bool> isAboutExpanded,
    ValueNotifier<bool> currentUserLocation,
    double? latitude,
    double? longitude,
    ValueNotifier<bool> isImageTapped,
    ValueNotifier<double> imageExpandProgress,
    ValueNotifier<bool> resetGallery,
  ) {
    final isDistanceAvailable =
        (user.latitude != null && user.longitude != null);

    return SafeArea(
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(getProportionateScreenWidth(38)),
        ),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            getProportionateScreenWidth(16),
            getProportionateScreenHeight(52),
            getProportionateScreenWidth(16),
            getProportionateScreenWidth(16),
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(getProportionateScreenWidth(20)),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.lavendar,
                blurRadius: 18,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start, // important
                  children: [
                    /// LEFT SIDE (TEXT - flexible)
                    Flexible(
                      child: Row(
                        children: [
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        "${user.name}, ${user.age}",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                        maxLines:
                                            2, // don't allow unlimited chaos
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(
                                      width: getProportionateScreenWidth(12),
                                    ),
                                    if (user.isVerified == true)
                                      VerifiedBadge(),
                                    // ReactiveBadgeImage(
                                    //   badgePath:
                                    //       AppConfigService.verifiedBadgeUri,
                                    //   width: 24,
                                    //   height: 24,
                                    // ),
                                  ],
                                ),

                                if (user.city != null || user.state != null)
                                  Text(
                                    "${user.city ?? ""}, ${user.state ?? ""}",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.colorGrey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: getProportionateScreenWidth(16)),

                    /// RIGHT SIDE (FIXED)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: isDistanceAvailable
                              ? (!currentUserLocation.value &&
                                        latitude == null &&
                                        longitude == null)
                                    ? () async {
                                        await Provider.of<UserProvider>(
                                          context,
                                          listen: false,
                                        ).getLatLng(context, skip: true);
                                      }
                                    : null
                              : null,
                          child: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.colorPink.withAlpha(38),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.location_pin,
                                  color: AppColors.purple,
                                  size: 16,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  isDistanceAvailable
                                      ? !currentUserLocation.value
                                            ? "Enable Location"
                                            : latitude != null &&
                                                  longitude != null
                                            ? getDistanceInKmFormatted(
                                                latitude,
                                                longitude,
                                                user.latitude ?? 0.0,
                                                user.longitude ?? 0.0,
                                              )
                                            : "Loading..."
                                      : "Location Not Available",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.purple,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: getProportionateScreenHeight(4)),
                if (user.isOnline == true) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
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
                        fontSize: 14,
                        color: Color(0xFF16AC16),
                      ),
                    ),
                  ),
                ] else ...[
                  Text(
                    "Active ${timeago.format(DateTime.now().subtract(DateTime.now().difference(user.lastOnline ?? DateTime.now())))}",
                    style: TextStyle(fontSize: 12, color: AppColors.greyShade),
                  ),
                ],

                if (!isExpand.value) ...[
                  SizedBox(height: getProportionateScreenHeight(16)),
                  if (user.about != null && user.about!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.purple,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'About',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            (user.about?.isEmpty ?? true)
                                ? "No about added yet."
                                : user.about!,
                            maxLines: isAboutExpanded.value ? null : 3,
                            overflow: isAboutExpanded.value
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: (user.about?.length ?? 0) > 140
                                ? GestureDetector(
                                    onTap: () {
                                      isAboutExpanded.value =
                                          !isAboutExpanded.value;
                                    },
                                    child: Text(
                                      isAboutExpanded.value
                                          ? 'Read less'
                                          : 'Read more',
                                      style: TextStyle(
                                        color: Color(0xFFE45A92),
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.underline,
                                        decorationColor: Color(0xFFE45A92),
                                      ),
                                    ),
                                  )
                                : SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    itemCount: questionValuesFirst.length,
                    itemBuilder: (context, index) {
                      final questionValue = questionValuesFirst[index];
                      return questionValues(questionValue: questionValue);
                    },
                  ),
                  SizedBox(height: getProportionateScreenHeight(16)),
                  Row(
                    children: [
                      smokeDrinkSection(
                        "Smoker",
                        user.smoker,
                        Icons.smoke_free_sharp,
                      ),
                      SizedBox(width: getProportionateScreenWidth(52)),
                      smokeDrinkSection(
                        "Drinker",
                        (user.drinking != '' && user.drinking != null)
                            ? user.drinking ?? ""
                            : null,
                        Icons.local_bar_sharp,
                      ),
                    ],
                  ),
                  questionValues(
                    questionValue: QuestionValues(
                      question: "Interests",
                      options: user.interests,
                    ),
                  ),
                ] else ...[
                  SizedBox(height: getProportionateScreenHeight(8)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () {
                        isImageTapped.value = false;
                        imageExpandProgress.value = 0.0;
                        resetGallery.value = true;
                      },
                      child: Icon(
                        Icons.arrow_upward,
                        size: 32,
                        color: AppColors.purple,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget smokeDrinkSection(String title, String? value, IconData icon) {
    if (value == null || value.isEmpty) {
      return SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.purple, size: 16),
            SizedBox(width: 4),
            Text(
              title,
              style: TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        SizedBox(height: getProportionateScreenHeight(2)),
        Container(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.lavendar.withAlpha(50),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: AppColors.purple,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget questionValues({
    required QuestionValues questionValue,
    bool? requiresContainer = true,
  }) {
    if ((questionValue.options?.isNotEmpty ?? false) ||
        (questionValue.value?.isNotEmpty ?? false)) {
    } else {
      return SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(top: getProportionateScreenHeight(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            questionValue.question,
            style: TextStyle(
              color: Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: getProportionateScreenHeight(2)),
          if (questionValue.options != null &&
              questionValue.options!.isNotEmpty) ...[
            Wrap(
              spacing: getProportionateScreenWidth(8),
              runSpacing: getProportionateScreenHeight(8),
              children: questionValue.options!.map((option) {
                return Container(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                  decoration: BoxDecoration(
                    color: AppColors.lavendar.withAlpha(50),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    option,
                    style: TextStyle(
                      color: AppColors.purple,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }).toList(),
            ),
          ] else
            Container(
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.lavendar.withAlpha(50),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                questionValue.value!,
                style: TextStyle(
                  color: AppColors.purple,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
