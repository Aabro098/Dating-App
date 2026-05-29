import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:viora/Screens/EditProfile/new_edit_profile.dart';
import 'package:viora/Screens/Home/homeScreen.dart';
import 'package:viora/Screens/SettingsScreen/settingsScreen.dart';
import 'package:viora/Services/AppConfigService.dart';
import 'package:viora/Services/auth_helper.dart';
import 'package:viora/components/image_preview_dialog.dart';
import 'package:viora/components/verified_badge.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:viora/size_config.dart';
import 'package:viora/constants.dart';
import 'package:viora/utils/constatnts/colors.dart';
import 'package:viora/utils/helpers/image_helper.dart';
import '../../Services/Global.dart';

/// UI Layer - Pure presentation component using Flutter Hooks
/// No business logic or backend calls - delegates to business logic layer
class NewMyProfile extends HookWidget {
  const NewMyProfile({this.hideAppBar = true, super.key});

  final bool hideAppBar;

  @override
  Widget build(BuildContext context) {
    // Get user details from prefs (initialized in Global.dart)
    final globals = Globals.of(context);

    // Listen to user details changes using hook
    final userDetails = useListenable(globals.prefs.userDetails);
    final currentUser = userDetails.value;

    // Handle loading state
    if (currentUser == null) {
      return Material(
        child: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    final questionValuesFirst = [
      QuestionValues(
        question: "Who can message me directly?",
        value: currentUser.messagePermission ?? "All",
      ),
      QuestionValues(question: "Work", value: currentUser.work),
      QuestionValues(question: "Education", value: currentUser.education),
      QuestionValues(question: "Nationality", value: currentUser.nationality),
      QuestionValues(
        question: "Marital Status",
        value: currentUser.maritalStatus,
      ),
      QuestionValues(
        question: "Sexual Orientation",
        options: currentUser.sexualOrientation,
      ),
      QuestionValues(
        question: "Height",
        value: currentUser.height != null ? "${currentUser.height} cm" : null,
      ),
      QuestionValues(question: "Phone number", value: currentUser.phone),
      QuestionValues(question: "Email", value: currentUser.email),
    ];

    final questionValuesSecond = [
      QuestionValues(question: "Zodiac Sign", value: currentUser.zodiac),
      QuestionValues(question: "Diet", value: currentUser.diet),
      QuestionValues(question: "Religion", value: currentUser.religion),
    ];

    final questionValuesThird = [
      QuestionValues(question: "Smoker", value: currentUser.smoker),
      QuestionValues(question: "Drinking", value: currentUser.drinking),
    ];
    final u = userDetails.value;
    final w = AppConfigService.profileWeightage;
    final isWeightageReady = w.isNotEmpty;

    if (!isWeightageReady) {
      return const Material(
        child: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    int completion = 0;

    if (u != null && w.isNotEmpty) {
      int completed = 0;

      final fieldCheckers = <String, bool>{
        'education': (u.education ?? '').isNotEmpty,
        'drinking': (u.drinking ?? '').isNotEmpty,
        'relationshipType': (u.relTypes ?? []).isNotEmpty,
        'work': (u.work ?? '').isNotEmpty,
        'about': (u.about ?? '').isNotEmpty,
        'photos': (u.images ?? []).isNotEmpty,
        'Interests': (u.interests ?? []).isNotEmpty,
        'religion': (u.religion ?? '').isNotEmpty,
        'sexualOrientation': (u.sexualOrientation ?? []).isNotEmpty,
        'smoker': (u.smoker ?? '').isNotEmpty,
        'nationality': (u.nationality ?? '').isNotEmpty,
        'verifyProfile': u.isVerified == true,
        'height': u.height != null,
      };

      fieldCheckers.forEach((key, isFilled) {
        if (isFilled) {
          completed += (w[key] as int?) ?? 0;
        }
      });

      final total = w.values.fold<int>(0, (s, v) => s + (v as int));

      if (total != 0) {
        completion = ((completed / total) * 100).round();
      }
    }

    final isAboutExpanded = useState<bool>(false);

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: Image.asset(
              'assets/backgrounds/left.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              width: getProportionateScreenWidth(210),
              height: getProportionateScreenHeight(135),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Image.asset(
              'assets/backgrounds/right.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              width: getProportionateScreenWidth(169),
              height: getProportionateScreenHeight(112),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: getProportionateScreenHeight(28)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "My Profile",
                      style: TextStyle(
                        fontSize: getProportionateScreenHeight(34),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        await PersistentNavBarNavigator.pushNewScreen(
                          context,
                          screen: SettingsScreen(),
                          withNavBar: false,
                          pageTransitionAnimation:
                              PageTransitionAnimation.cupertino,
                        );
                      },
                      child: Icon(
                        Icons.settings,
                        color: kPrimaryColor,
                        size: 32,
                      ),
                    ),
                  ],
                ),
                Text(
                  "Your love life starts here :)",
                  style: TextStyle(fontSize: 16, color: AppColors.colorGrey),
                ),
                SizedBox(height: getProportionateScreenHeight(16)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: getProportionateScreenWidth(72),
                      height: getProportionateScreenWidth(72),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFFE45A92).withAlpha(100),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ReactiveProfileImage(
                          imagePath:
                              currentUser.images != null &&
                                  currentUser.images!.isNotEmpty
                              ? currentUser.images!.first
                              : '',
                          gender: currentUser.gender ?? 'male',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    SizedBox(width: getProportionateScreenWidth(16)),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  "${currentUser.name}, ${currentUser.age}",
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                  overflow: TextOverflow.visible,
                                ),
                              ),
                              if (currentUser.isVerified ?? false)
                                Padding(
                                  padding: EdgeInsets.only(
                                    left: getProportionateScreenWidth(8),
                                  ),
                                  child: VerifiedBadge(),
                                  // child: ReactiveBadgeImage(
                                  //   badgePath:
                                  //       AppConfigService.verifiedBadgeUri,
                                  //   width: 22,
                                  //   height: 22,
                                  // ),
                                ),
                            ],
                          ),
                          // SizedBox(height: getProportionateScreenHeight(2)),
                          Text(
                            (currentUser.city != null &&
                                        currentUser.city != '') &&
                                    (currentUser.state != null &&
                                        currentUser.state != '')
                                ? "${currentUser.city}, ${currentUser.state}"
                                : "No location added",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.colorGrey,
                            ),
                          ),
                          SizedBox(height: 2),
                          GestureDetector(
                            onTap: () async {
                              showEditProfileScreen.value = true;
                            },
                            child: Row(
                              children: [
                                Text(
                                  "Edit Profile",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: kPrimaryColor,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  Icons.edit,
                                  color: kPrimaryColor,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: getProportionateScreenHeight(16)),
                if (currentUser.images != null &&
                    currentUser.images!.isNotEmpty)
                  SizedBox(
                    height: getProportionateScreenWidth(59),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      scrollDirection: Axis.horizontal,
                      physics: NeverScrollableScrollPhysics(),
                      itemCount: currentUser.images?.length ?? 0,
                      separatorBuilder: (_, _) =>
                          SizedBox(width: getProportionateScreenWidth(12)),
                      itemBuilder: (context, index) {
                        final imageUrl = currentUser.images![index];

                        return GestureDetector(
                          onTap: () {
                            ImagePreviewDialog.show(
                              context,
                              imageUrl: imageUrl,
                              userImages: currentUser.images,
                            );
                          },
                          child: SizedBox(
                            width: getProportionateScreenWidth(56),
                            height: getProportionateScreenWidth(59),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: ReactiveProfileImage(
                                imagePath: imageUrl,
                                gender: currentUser.gender ?? 'male',
                                width: getProportionateScreenWidth(56),
                                height: getProportionateScreenWidth(59),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                SizedBox(height: getProportionateScreenHeight(16)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20.w,
                        vertical: 10.h,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.colorPink.withAlpha(38),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: getProportionateScreenWidth(32),
                            height: getProportionateScreenWidth(32),
                            child: CircularProgressIndicator(
                              backgroundColor: AppColors.colorPink.withAlpha(
                                25,
                              ),
                              value: completion / 100,
                              strokeWidth: 6,
                              strokeCap: StrokeCap.round,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.purple,
                              ),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "$completion%",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.purple,
                                ),
                              ),
                              Text(
                                "Profile Score",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.colorGrey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: getProportionateScreenWidth(12)),
                    if (!(currentUser.isVerified ?? false)) ...[
                      VerifyProfile(
                        gender: currentUser.gender ?? 'male',
                        height: 14,
                      ),
                    ] else ...[
                      SizedBox.shrink(),
                    ],
                  ],
                ),
                SizedBox(height: getProportionateScreenHeight(16)),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Builder(
                          builder: (context) {
                            // final hasAbout =
                            //     currentUser.about != null &&
                            //     currentUser.about != "";
                            // if (!hasAbout) {
                            //   return SizedBox.shrink();
                            // }
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        currentUser.about == '' ||
                                                currentUser.about == null
                                            ? "No about added yet."
                                            : currentUser.about ?? '',

                                        maxLines: isAboutExpanded.value
                                            ? null
                                            : 4,
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
                                        child:
                                            (currentUser.about?.length ?? 0) >
                                                140
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
                                                    decoration: TextDecoration
                                                        .underline,
                                                    decorationColor: Color(
                                                      0xFFE45A92,
                                                    ),
                                                  ),
                                                ),
                                              )
                                            : SizedBox.shrink(),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  height: getProportionateScreenHeight(12),
                                ),
                              ],
                            );
                          },
                        ),
                        Builder(
                          builder: (context) {
                            final allQuestions =
                                [
                                      ...questionValuesFirst,
                                      ...questionValuesSecond,
                                      QuestionValues(
                                        question:
                                            "Looking for relationship type",
                                        options: currentUser.relTypes,
                                      ),
                                      ...questionValuesThird,
                                      QuestionValues(
                                        question: "Interests",
                                        options: currentUser.interests,
                                      ),
                                    ]
                                    .where(
                                      (q) =>
                                          (q.options?.isNotEmpty ?? false) ||
                                          (q.value?.isNotEmpty ?? false),
                                    )
                                    .toList();
                            return allQuestions.isEmpty
                                ? const SizedBox.shrink()
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: List.generate(
                                      allQuestions.length,
                                      (index) {
                                        final question = allQuestions[index];

                                        final isSecondOrThirdGroup =
                                            index >=
                                                questionValuesFirst.length +
                                                    questionValuesSecond
                                                        .length +
                                                    1 ||
                                            index ==
                                                questionValuesFirst.length +
                                                    questionValuesSecond.length;

                                        return Padding(
                                          padding: EdgeInsets.only(
                                            bottom:
                                                index == allQuestions.length - 1
                                                ? 0
                                                : getProportionateScreenHeight(
                                                    12,
                                                  ),
                                          ),
                                          child: questionValues(
                                            questionValue: question,
                                            requiresContainer:
                                                !isSecondOrThirdGroup,
                                          ),
                                        );
                                      },
                                    ),
                                  );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget questionValues({
    required QuestionValues questionValue,
    bool? requiresContainer = true,
  }) {
    // If value is null or options are null, return shrink
    if (!((questionValue.options?.isNotEmpty ?? false) ||
        (questionValue.value?.isNotEmpty ?? false))) {
      return SizedBox.shrink();
    }

    return Column(
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
        ] else ...[
          Container(
            padding: requiresContainer == true
                ? EdgeInsets.symmetric(vertical: 8, horizontal: 10)
                : null,
            decoration: requiresContainer == true
                ? BoxDecoration(
                    color: AppColors.lavendar.withAlpha(50),
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            child: Text(
              questionValue.value ?? "",
              style: TextStyle(
                color: AppColors.purple,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
