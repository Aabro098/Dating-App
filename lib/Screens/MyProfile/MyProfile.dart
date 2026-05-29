import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:viora/Screens/EditProfile/editProfile.dart';
import 'package:viora/Screens/SettingsScreen/settingsScreen.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/Services/ImageUploadService.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:viora/size_config.dart';
import 'package:viora/constants.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import '../../Services/Global.dart';
import '../../Services/profile_business_logic.dart';

/// UI Layer - Pure presentation component using Flutter Hooks
/// No business logic or backend calls - delegates to business logic layer
class MyProfile extends HookWidget {
  const MyProfile({super.key});

  @override
  Widget build(BuildContext context) {
    // Get user details from prefs (initialized in Global.dart)
    final globals = Globals.of(context);

    // Listen to user details changes using hook
    final userDetails = useListenable(globals.prefs.userDetails);
    final currentUser = userDetails.value;

    if (currentUser?.images != null) {
      print("currentUser ${currentUser?.images?.length}");
    } else {
      print("currentUser null");
    }

    // Local UI state management with hooks
    final isLoadingImage = useState(false);

    // Memoized expensive computations
    final profileImageUrl = useMemoized(
      () => _getProfileImageUrl(currentUser),
      [currentUser?.images],
    );

    final textStyle = useMemoized(
      () => TextStyle(
        fontSize: getProportionateScreenWidth(14),
        fontWeight: FontWeight.bold,
        color: Colors.black,
      ),
      [],
    );

    // Memoized callbacks to prevent unnecessary rebuilds
    final handleEditProfile = useCallback(() {
      PersistentNavBarNavigator.pushNewScreen(
        context,
        screen: EditProfile(),
        withNavBar: false,
        pageTransitionAnimation: PageTransitionAnimation.cupertino,
      );
    }, []);

    final handleAddPhoto = useCallback(() async {
      if (currentUser == null) return;

      if (currentUser.images != null) {
        if (currentUser.images!.length >= 5) {
          showSimpleNotification(
            Text("You can't Upload more than 5 Photos"),
            background: Colors.redAccent,
            position: NotificationPosition.bottom,
          );
          return;
        }
      }

      isLoadingImage.value = true;
      try {
        await ImageUploadService.getImageForMyProfile(context);
      } finally {
        isLoadingImage.value = false;
      }
    }, [currentUser]);

    // Handle loading state
    if (currentUser == null) {
      return Material(
        child: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    return Material(
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Settings Icon - Top Right
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () {
                      PersistentNavBarNavigator.pushNewScreen(
                        context,
                        screen: SettingsScreen(),
                        withNavBar: false,
                        pageTransitionAnimation:
                            PageTransitionAnimation.cupertino,
                      );
                    },
                    child: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kPrimaryPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.settings,
                        color: kPrimaryPurple,
                        size: 24,
                      ),
                    ),
                  ),
                ),

                // Profile Header Section
                _ProfileHeader(
                  userDetails: currentUser,
                  profileImageUrl: profileImageUrl,
                  onEditPressed: handleEditProfile,
                ),

                SizedBox(height: 16),

                // User Information Section
                _UserInfoSection(
                  userDetails: currentUser,
                  textStyle: textStyle,
                ),

                SizedBox(height: 16),

                // Photos Section
                _PhotosSection(
                  userDetails: currentUser,
                  textStyle: textStyle,
                  onAddPhoto: handleAddPhoto,
                  isLoading: isLoadingImage.value,
                ),

                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getProfileImageUrl(UserDetails? user) {
    if (user == null) return kMaleUrl;
    if (user.images == null || user.images!.isEmpty) {
      return user.gender == "Male" ? kMaleUrl : kFemaleUrl;
    }
    return user.images![0];
  }
}

/// Profile Header Component - Optimized with hooks
class _ProfileHeader extends HookWidget {
  final UserDetails userDetails;
  final String profileImageUrl;
  final VoidCallback onEditPressed;

  const _ProfileHeader({
    super.key,
    required this.userDetails,
    required this.profileImageUrl,
    required this.onEditPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.all(Radius.circular(50)),
                      child: CachedNetworkImage(
                        imageUrl: profileImageUrl,
                        height: getProportionateScreenWidth(100),
                        width: getProportionateScreenWidth(100),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Text(userDetails.name ?? '', style: sHeadingStyle),
                  Container(
                    padding: EdgeInsets.all(getProportionateScreenHeight(10)),
                    child: SvgPicture.asset(
                      userDetails.gender == "Female"
                          ? "assets/svg/female.svg"
                          : "assets/svg/male.svg",
                      height: getProportionateScreenHeight(24),
                    ),
                  ),
                  Text("${userDetails.age} Yrs"),
                  Text("${userDetails.city}/ ${userDetails.state}"),
                ],
              ),
            ),
          ],
        ),
        Row(
          children: [
            Spacer(),
            GestureDetector(
              onTap: onEditPressed,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: kPrimaryColor,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Text(
                      "Edit",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: getProportionateScreenWidth(16),
                      ),
                    ),
                    Icon(Icons.edit, color: Colors.white),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// User Information Section Component
class _UserInfoSection extends StatelessWidget {
  final UserDetails userDetails;
  final TextStyle textStyle;

  const _UserInfoSection({
    super.key,
    required this.userDetails,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (userDetails.sexualOrientation != null)
          // _InfoChipSection(
          //   title: "Sexual Orientation",
          //   items: [userDetails.sexualOrientation!],
          //   textStyle: textStyle,
          // ),
          if (userDetails.maritalStatus != null)
            _InfoChipSection(
              title: "Marital Status",
              items: [userDetails.maritalStatus!],
              textStyle: textStyle,
            ),

        if (userDetails.relTypes != null && userDetails.relTypes!.isNotEmpty)
          _InfoChipSection(
            title: "Types of Relationship looking for",
            items: userDetails.relTypes!,
            textStyle: textStyle,
          ),
      ],
    );
  }
}

/// Reusable Info Chip Section Component
class _InfoChipSection extends StatelessWidget {
  final String title;
  final List<String> items;
  final TextStyle textStyle;

  const _InfoChipSection({
    super.key,
    required this.title,
    required this.items,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textStyle),
        Wrap(
          children: items
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Chip(label: Text(item)),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

/// Photos Section Component with Hooks
class _PhotosSection extends HookWidget {
  final UserDetails userDetails;
  final TextStyle textStyle;
  final VoidCallback onAddPhoto;
  final bool isLoading;

  const _PhotosSection({
    super.key,
    required this.userDetails,
    required this.textStyle,
    required this.onAddPhoto,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    // Callback for photo actions
    final handlePhotoAction = useCallback((String image, BuildContext context) {
      showCupertinoModalPopup<void>(
        context: context,
        builder: (BuildContext context) => CupertinoActionSheet(
          title: Text("Choose action"),
          actions: <CupertinoActionSheetAction>[
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(context);
                // Delegate to business logic
                await ProfileBusinessLogic.setAsProfilePicture(
                  image,
                  userDetails.images!,
                );
              },
              isDestructiveAction: false,
              child: Text("Make Profile Picture"),
            ),
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(context);
                // Delegate to business logic
                await ProfileBusinessLogic.deletePhoto(image);
              },
              isDestructiveAction: true,
              child: Text("Delete Picture"),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text("Cancel"),
          ),
        ),
      );
    }, [userDetails.images]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Text("Photos", style: textStyle),
              Spacer(),
              GestureDetector(
                onTap: isLoading ? null : onAddPhoto,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isLoading ? Colors.grey : kPrimaryColor,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        isLoading ? "Uploading..." : "Add Photo",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: getProportionateScreenWidth(16),
                        ),
                      ),
                      SizedBox(width: 4),
                      if (isLoading)
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      else
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          color: Colors.white,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 20,
            mainAxisSpacing: 20,
          ),
          physics: NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: userDetails.images?.length ?? 0,
          itemBuilder: (context, index) {
            final image = userDetails.images![index];
            return GestureDetector(
              onTap: () => handlePhotoAction(image, context),
              child: PhotoCard(image: image),
            );
          },
        ),
      ],
    );
  }
}

/// Photo Card Component - Kept as StatelessWidget (already optimized)
class PhotoCard extends StatelessWidget {
  final String image;

  const PhotoCard({super.key, required this.image});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        child: CachedNetworkImage(
          imageUrl: image,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      ),
    );
  }
}
