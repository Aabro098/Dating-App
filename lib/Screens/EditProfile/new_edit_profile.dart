import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_picker/country_picker.dart' as cp;
import 'package:country_pickers/country.dart' as cps;
import 'package:country_pickers/country_pickers.dart' as cps;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:provider/provider.dart';
import 'package:viora/Screens/EditProfile/bottom_sheet.dart';
import 'package:viora/Screens/Home/homeScreen.dart';
import 'package:viora/Screens/Verification/LivenessVerificationScreen.dart';
import 'package:viora/Services/AppConfigService.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/Services/ImageUploadService.dart';
import 'package:viora/Services/SubscriptionService.dart';
import 'package:viora/Services/UserProvider.dart';
import 'package:viora/Services/auth_helper.dart';
import 'package:viora/Services/bio_service.dart';
import 'package:viora/Services/profile_business_logic.dart';
import 'package:viora/components/VerifyProfileDialog.dart';
import 'package:viora/components/custom_chips_choice.dart';
import 'package:viora/components/image_preview_dialog.dart';
import 'package:viora/components/reusable_dialog.dart';
import 'package:viora/components/verified_badge.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:viora/size_config.dart';
import 'package:viora/constants.dart';
import 'package:viora/utils/constatnts/colors.dart';
import 'package:viora/utils/constatnts/profile_constants.dart';
import 'package:viora/utils/helpers/image_helper.dart';
import '../../Services/Global.dart';

String getNationalNumberOnly(String phone) {
  if (phone.trim().isEmpty) return '';

  try {
    final parsed = PhoneNumber.parse(phone);

    // This returns the phone number without country code
    return parsed.nsn;
  } catch (_) {
    return phone.replaceAll(RegExp(r'^\+\d{1,3}'), '');
  }
}

/// UI Layer - Pure presentation component using Flutter Hooks
/// No business logic or backend calls - delegates to business logic layer
class NewEditProfile extends HookWidget {
  const NewEditProfile({super.key});

  @override
  Widget build(BuildContext context) {
    // Get user details from prefs (initialized in Global.dart)
    final globals = Globals.of(context);

    final formKey = useRef(GlobalKey<FormState>());

    final aboutFieldKey = useMemoized(
      () => GlobalKey<FormFieldState<String>>(),
    );
    final emailFieldKey = useMemoized(
      () => GlobalKey<FormFieldState<String>>(),
    );

    final emailScrollKey = useMemoized(() => GlobalKey());
    final aboutScrollKey = useMemoized(() => GlobalKey());
    // Listen to user details changes using hook
    final userDetails = useListenable(globals.prefs.userDetails);
    final currentUser = userDetails.value;

    final phoneFocusNode = useFocusNode();
    useListenable(phoneFocusNode);

    // Handle loading state
    if (currentUser == null) {
      return Material(
        child: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    // Local UI state management with hooks
    final isLoadingImage = useState(false);
    final isSavingChanges = useState(false);
    final isFetchingLocation = useState(false);
    final isAIBioEnabled = useState<bool>(false);
    final whoCanMessageMe = useState<bool>(false);
    final isGeneratingBio = useState<bool>(false);
    final isAboutExpanded = useState<bool>(false);
    final handleAddPhoto = useCallback(() async {
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

    final emailController = useTextEditingController(
      text: currentUser.email ?? '',
    );
    final ageController = useTextEditingController(
      text: currentUser.dateOfBirth != null
          ? DateFormat('dd-MM-yyyy').format(currentUser.dateOfBirth!)
          : '',
    );
    final workController = useTextEditingController(
      text: currentUser.work ?? '',
    );

    final educationController = useTextEditingController(
      text: currentUser.education ?? '',
    );

    final aboutController = useTextEditingController(
      text: currentUser.about ?? '',
    );
    final initialPhone = currentUser.phone ?? '';
    final phoneController = useTextEditingController(
      text: getNationalNumberOnly(initialPhone),
    );

    final drinking = useState(currentUser.drinking ?? "");
    final diet = useState(currentUser.diet ?? "");
    final religion = useState(currentUser.religion ?? "");
    final maritalStatus = useState(currentUser.maritalStatus ?? "");
    final smoker = useState(currentUser.smoker ?? "");
    final messagePermission = useState(currentUser.messagePermission ?? "");
    final selectedZodiac = useState<String?>(currentUser.zodiac);
    final initialHeight = currentUser.height != null ? currentUser.height! : 40;
    final height = useState(initialHeight);
    final nationality = useState(currentUser.nationality);
    final bool isPhoneSignedIn = AuthHelper.isPhoneSignIn();

    final interests = useState<Set<int>>(
      currentUser.interests != null
          ? currentUser.interests!
                .map(
                  (interest) =>
                      ProfileConstants.interestStrings.indexOf(interest),
                )
                .where((index) => index != -1)
                .toSet()
          : <int>{},
    );

    final relationType = useState<Set<int>>(
      currentUser.relTypes != null
          ? currentUser.relTypes!
                .map(
                  (type) => ProfileConstants.relationTypeStrings.indexOf(type),
                )
                .where((index) => index != -1)
                .toSet()
          : <int>{},
    );

    final sexualOrientation = useState<Set<int>>(
      currentUser.sexualOrientation != null
          ? currentUser.sexualOrientation!
                .map(
                  (orientation) =>
                      ProfileConstants.orientationStrings.indexOf(orientation),
                )
                .where((index) => index != -1)
                .toSet()
          : <int>{},
    );

    final selectedCountry = useState<cps.Country?>(
      AuthHelper.isPhoneSignIn()
          ? cps.CountryPickerUtils.getCountryByPhoneCode(
              PhoneNumber.parse(initialPhone).countryCode,
            )
          : cps.CountryPickerUtils.getCountryByIsoCode('IN'),
    );

    final hasChanges = useState(false);

    bool setsEqual(Set<int> a, Set<int> b) {
      return a.length == b.length && a.containsAll(b);
    }

    String normalize(String? value) => value?.trim() ?? '';

    bool checkHasChanges() {
      final initialInterests = currentUser.interests != null
          ? currentUser.interests!
                .map(
                  (interest) =>
                      ProfileConstants.interestStrings.indexOf(interest),
                )
                .where((index) => index != -1)
                .toSet()
          : <int>{};

      final initialRelationType = currentUser.relTypes != null
          ? currentUser.relTypes!
                .map(
                  (type) => ProfileConstants.relationTypeStrings.indexOf(type),
                )
                .where((index) => index != -1)
                .toSet()
          : <int>{};

      final initialSexualOrientation = currentUser.sexualOrientation != null
          ? currentUser.sexualOrientation!
                .map(
                  (orientation) =>
                      ProfileConstants.orientationStrings.indexOf(orientation),
                )
                .where((index) => index != -1)
                .toSet()
          : <int>{};

      final initialDobText = currentUser.dateOfBirth != null
          ? DateFormat('dd-MM-yyyy').format(currentUser.dateOfBirth!)
          : '';

      final initialPhoneText = getNationalNumberOnly(currentUser.phone ?? '');

      return normalize(emailController.text) != normalize(currentUser.email) ||
          normalize(phoneController.text) != normalize(initialPhoneText) ||
          normalize(ageController.text) != normalize(initialDobText) ||
          normalize(workController.text) != normalize(currentUser.work) ||
          normalize(educationController.text) !=
              normalize(currentUser.education) ||
          normalize(aboutController.text) != normalize(currentUser.about) ||
          drinking.value != (currentUser.drinking ?? "") ||
          diet.value != (currentUser.diet ?? "") ||
          religion.value != (currentUser.religion ?? "") ||
          maritalStatus.value != (currentUser.maritalStatus ?? "") ||
          smoker.value != (currentUser.smoker ?? "") ||
          messagePermission.value != (currentUser.messagePermission ?? "") ||
          selectedZodiac.value != currentUser.zodiac ||
          height.value != initialHeight ||
          nationality.value != currentUser.nationality ||
          !setsEqual(interests.value, initialInterests) ||
          !setsEqual(relationType.value, initialRelationType) ||
          !setsEqual(sexualOrientation.value, initialSexualOrientation);
    }

    Future<void> pickDate() async {
      final now = DateTime.now();
      final eighteenYearsAgo = DateTime(now.year - 18, now.month, now.day);

      final picked = await showDatePicker(
        context: context,
        initialDate: eighteenYearsAgo,
        firstDate: DateTime(1970),
        lastDate: eighteenYearsAgo,
        confirmText: "Select",
        helpText: "Select Your Date of Birth",
      );

      if (picked != null && context.mounted) {
        ageController.text = DateFormat('dd-MM-yyyy').format(picked);
      }
    }

    void openCountryPicker(
      BuildContext context,
      ValueNotifier<cps.Country?> selectedCountry,
    ) {
      showDialog(
        context: context,
        builder: (_) => Theme(
          data: Theme.of(context).copyWith(
            dialogTheme: DialogThemeData(
              backgroundColor: const Color.fromRGBO(230, 228, 228, 1),
            ),
          ),
          child: cps.CountryPickerDialog(
            titlePadding: EdgeInsets.all(getProportionateScreenWidth(8)),
            searchCursorColor: kTertiaryPink,
            searchInputDecoration: InputDecoration(
              hintText: 'Search country...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  getProportionateScreenWidth(8),
                ),
              ),
            ),
            isSearchable: true,
            title: Text(
              'Select your country',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w600,
                fontSize: getProportionateScreenWidth(18),
              ),
            ),
            onValuePicked: (cps.Country country) {
              selectedCountry.value = country;
            },
            itemBuilder: (cps.Country country) => Container(
              padding: EdgeInsets.all(getProportionateScreenWidth(8)),
              child: Row(
                children: [
                  cps.CountryPickerUtils.getDefaultFlagImage(country),
                  SizedBox(width: getProportionateScreenWidth(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          country.name,
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w600,
                            fontSize: getProportionateScreenWidth(14),
                          ),
                        ),
                        Text(
                          '+${country.phoneCode}',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w400,
                            fontSize: getProportionateScreenWidth(12),
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    void pickCountry(BuildContext context) {
      cp.showCountryPicker(
        context: context,
        countryListTheme: cp.CountryListThemeData(
          bottomSheetHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        showPhoneCode: true,
        onSelect: (cp.Country country) {
          nationality.value = country.name;
        },
      );
    }

    useEffect(() {
      void listener() {
        hasChanges.value = checkHasChanges();
      }

      emailController.addListener(listener);
      phoneController.addListener(listener);
      ageController.addListener(listener);
      workController.addListener(listener);
      educationController.addListener(listener);
      aboutController.addListener(listener);

      return () {
        emailController.removeListener(listener);
        phoneController.removeListener(listener);
        ageController.removeListener(listener);
        workController.removeListener(listener);
        educationController.removeListener(listener);
        aboutController.removeListener(listener);
      };
    }, [currentUser]);

    useEffect(
      () {
        hasChanges.value = checkHasChanges();
        return null;
      },
      [
        drinking.value,
        diet.value,
        religion.value,
        maritalStatus.value,
        smoker.value,
        messagePermission.value,
        selectedZodiac.value,
        height.value,
        nationality.value,
        interests.value,
        relationType.value,
        sexualOrientation.value,
      ],
    );

    void scrollTo(GlobalKey key) {
      final context = key.currentContext;

      if (context == null) return;

      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
    }

    final handleApplyChanges = useCallback(() async {
      if (!hasChanges.value || isSavingChanges.value) {
        return;
      }
      try {
        String? fullPhoneNumber;
        if (phoneController.text.trim().isNotEmpty) {
          final nationalNumber = phoneController.text.trim();
          final countryCode = selectedCountry.value?.phoneCode ?? '91';
          fullPhoneNumber = '+$countryCode$nationalNumber';
          // try {
          //   final parsed = PhoneNumber.parse(fullPhoneNumber);
          //   if (!parsed.isValid()) {
          //     WidgetsBinding.instance.addPostFrameCallback((_) {
          //       scrollTo(emailScrollKey);
          //     });
          //     hasPhoneError.value = true;
          //     // showSimpleNotification(
          //     //   Text("Please enter a valid phone number"),
          //     //   background: Colors.redAccent,
          //     //   position: NotificationPosition.top,
          //     // );
          //     return;
          //   }
          // } catch (_) {
          //   WidgetsBinding.instance.addPostFrameCallback((_) {
          //     scrollTo(emailScrollKey);
          //   });
          //   hasPhoneError.value = true;
          //   return;
          //   // showSimpleNotification(
          //   //   Text("Please enter a valid phone number"),
          //   //   background: Colors.redAccent,
          //   //   position: NotificationPosition.top,
          //   // );
          // }
        }
        UserDetails updatedUser = currentUser;
        updatedUser.email = emailController.text;
        updatedUser.phone = fullPhoneNumber?.isNotEmpty == true
            ? fullPhoneNumber
            : null;
        // Parse dateOfBirth and calculate age
        if (ageController.text.isNotEmpty) {
          try {
            updatedUser.dateOfBirth = DateFormat(
              'dd-MM-yyyy',
            ).parse(ageController.text);

            // Calculate age from dateOfBirth
            final today = DateTime.now();
            int calculatedAge = today.year - updatedUser.dateOfBirth!.year;
            if (today.month < updatedUser.dateOfBirth!.month ||
                (today.month == updatedUser.dateOfBirth!.month &&
                    today.day < updatedUser.dateOfBirth!.day)) {
              calculatedAge--;
            }
            updatedUser.age = calculatedAge;
          } catch (e) {
            debugPrint('Error parsing date: $e');
          }
        }

        updatedUser.maritalStatus = maritalStatus.value;
        updatedUser.relTypes = relationType.value
            .map((index) => ProfileConstants.relationTypeStrings[index])
            .toList();
        updatedUser.about = aboutController.text;
        updatedUser.diet = diet.value;
        updatedUser.zodiac = selectedZodiac.value;
        updatedUser.religion = religion.value;
        updatedUser.smoker = smoker.value;
        updatedUser.drinking = drinking.value;
        updatedUser.interests = interests.value
            .map((index) => ProfileConstants.interestStrings[index])
            .toList();
        updatedUser.sexualOrientation = sexualOrientation.value
            .map((index) => ProfileConstants.orientationStrings[index])
            .toList();
        if (height.value != initialHeight) {
          updatedUser.height = height.value;
        }
        updatedUser.messagePermission = messagePermission.value;
        updatedUser.work = workController.text;
        updatedUser.education = educationController.text;
        updatedUser.nationality = nationality.value ?? "";

        // Save to local prefs
        globals.prefs.userDetails.set(updatedUser);

        // Build update data map
        final updateData = {
          "name": updatedUser.name,
          "email": updatedUser.email,
          "phone": updatedUser.phone,
          "age": updatedUser.age,
          "dateOfBirth": updatedUser.dateOfBirth,
          "state": updatedUser.state,
          "city": updatedUser.city,
          "work": workController.text,
          "education": educationController.text,
          "maritalStatus": updatedUser.maritalStatus,
          "relTypes": updatedUser.relTypes,
          "about": updatedUser.about,
          "diet": updatedUser.diet,
          "zodiac": updatedUser.zodiac,
          "religion": updatedUser.religion,
          "smoker": updatedUser.smoker,
          "drinking": updatedUser.drinking,
          "interests": updatedUser.interests,
          "sexualOrientation": updatedUser.sexualOrientation,
          "who_can_message": updatedUser.messagePermission,
          "nationality": updatedUser.nationality,
        };

        // Only add height if it changed
        if (height.value != initialHeight) {
          updateData["height"] = updatedUser.height;
        }

        // Save to Firestore
        DatabaseService.updateField(updateData);

        hasChanges.value = false;

        showSimpleNotification(
          Text("Profile updated Successfully"),
          leading: Icon(Icons.done),
          position: NotificationPosition.bottom,
          background: Colors.green,
          duration: Duration(seconds: 2),
          slideDismissDirection: DismissDirection.horizontal,
        );
        showEditProfileScreen.value = false;
      } finally {
        isSavingChanges.value = false;
      }
    });

    final weightage = useState<Map<String, dynamic>>({});

    /// 🔄 Fetch Remote Config (Hook #2)
    useEffect(() {
      Future.microtask(() async {
        try {
          weightage.value = AppConfigService.profileWeightage;
        } catch (e) {
          debugPrint("❌ Remote config error: $e");
        }
      });

      return null;
    }, []);

    final u = userDetails.value;
    final w = weightage.value;

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

    Future<void> isAIFeatureEnabled() async {
      final doc = await FirebaseFirestore.instance
          .collection('Subscriptions')
          .doc('freeFeatures')
          .get();
      final data = doc.data();

      final genderKey = currentUser.gender?.toLowerCase() == "female"
          ? "female"
          : "male";
      final gender = data?[genderKey] as Map<String, dynamic>?;
      final isEnabled = gender?['isEnable'] as bool? ?? false;

      if (isEnabled) {
        final features = gender?['features'] as Map<String, dynamic>?;
        final aiBio = features?['ai_bio'] as Map<String, dynamic>?;
        final whoCanMessageUser =
            features?['who_can_message'] as Map<String, dynamic>?;
        isAIBioEnabled.value = aiBio?['enabled'] == true;
        whoCanMessageMe.value = whoCanMessageUser?['enabled'] == true;
      }

      if (isAIBioEnabled.value == true && whoCanMessageMe.value == true) {
        return;
      }

      // Check if active and use details
      final String uid = FirebaseAuth.instance.currentUser!.uid;
      // Single fetch that gives you everything
      final SubscriptionDisplayInfo? subInfo =
          await SubscriptionService.getSubscriptionDisplayInfo(uid);

      if (subInfo?.isActive ?? false) {
        final entitlementFeatures = subInfo?.entitlementFeatures;
        if (isAIBioEnabled.value == false) {
          final aiBioEnabled =
              entitlementFeatures?.isFeatureEnabled("ai_bio") ?? false;
          isAIBioEnabled.value = aiBioEnabled;
        }
        if (whoCanMessageMe.value == false) {
          final isWhoCanMessageMe =
              entitlementFeatures?.isFeatureEnabled("who_can_message") ?? false;
          whoCanMessageMe.value = isWhoCanMessageMe;
        }
      }
    }

    useEffect(() {
      Future.microtask(() async {
        try {
          await isAIFeatureEnabled();
        } catch (e) {
          debugPrint("❌ Error checking AI feature: $e");
        }
      });

      return null;
    }, []);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        showEditProfileScreen.value = false;
      },
      child: Scaffold(
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
              child: Form(
                key: formKey.value,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fixed top section
                    SizedBox(height: getProportionateScreenHeight(28)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Edit My Profile",
                          style: TextStyle(
                            fontSize: getProportionateScreenHeight(34),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        GestureDetector(
                          onTap: (!hasChanges.value || isSavingChanges.value)
                              ? null
                              : () async {
                                  final isValid =
                                      formKey.value.currentState?.validate() ??
                                      false;

                                  if (!isValid) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (aboutFieldKey
                                                  .currentState
                                                  ?.hasError ==
                                              true) {
                                            scrollTo(aboutScrollKey);
                                            return;
                                          }

                                          if (emailFieldKey
                                                  .currentState
                                                  ?.hasError ==
                                              true) {
                                            scrollTo(emailScrollKey);
                                            return;
                                          }
                                        });

                                    return;
                                  }

                                  await handleApplyChanges();
                                },
                          child: Icon(
                            Icons.save,
                            color: (!hasChanges.value || isSavingChanges.value)
                                ? Colors.grey
                                : kPrimaryColor,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      "Your love life starts here :)",
                      style: TextStyle(fontSize: 16, color: AppColors.purple),
                    ),
                    SizedBox(height: getProportionateScreenHeight(16)),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: getProportionateScreenWidth(72),
                                  height: getProportionateScreenWidth(72),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: const Color(
                                        0xFFE45A92,
                                      ).withAlpha(100),
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
                                SizedBox(
                                  width: getProportionateScreenWidth(16),
                                ),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                            ),
                                          ),
                                          if (currentUser.isVerified ?? false)
                                            Padding(
                                              padding: EdgeInsets.only(
                                                left:
                                                    getProportionateScreenWidth(
                                                      8,
                                                    ),
                                              ),
                                              child: VerifiedBadge(),
                                              // child: ReactiveBadgeImage(
                                              //   badgePath: AppConfigService
                                              //       .verifiedBadgeUri,
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
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: getProportionateScreenHeight(16)),
                            SizedBox(
                              height: getProportionateScreenWidth(60),
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: (currentUser.images?.length ?? 0) < 5
                                    ? (currentUser.images?.length ?? 0) + 1
                                    : (currentUser.images?.length ?? 0),
                                separatorBuilder: (_, _) => SizedBox(
                                  width: getProportionateScreenWidth(8),
                                ),
                                itemBuilder: (context, index) {
                                  final imageCount =
                                      currentUser.images?.length ?? 0;
                                  final isAddButton = index >= imageCount;

                                  if (isAddButton) {
                                    return GestureDetector(
                                      onTap: () async {
                                        await handleAddPhoto();
                                      },
                                      child: Container(
                                        width: getProportionateScreenWidth(56),
                                        height: getProportionateScreenWidth(59),
                                        decoration: BoxDecoration(
                                          color: AppColors.purple.withAlpha(12),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: const Color(
                                              0xFF3E1E68,
                                            ).withAlpha(100),
                                            width: 1,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.add,
                                          color: AppColors.purple,
                                          size: 28,
                                        ),
                                      ),
                                    );
                                  }
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
                                      width: getProportionateScreenWidth(58),
                                      height: getProportionateScreenWidth(60),
                                      child: Stack(
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: ReactiveProfileImage(
                                              imagePath: imageUrl,
                                              gender:
                                                  currentUser.gender ?? "male",
                                              width:
                                                  getProportionateScreenWidth(
                                                    58,
                                                  ),
                                              height:
                                                  getProportionateScreenWidth(
                                                    60,
                                                  ),
                                            ),
                                          ),
                                          Positioned(
                                            right: 2,
                                            top: 2,
                                            child: GestureDetector(
                                              onTap: () async {
                                                await ProfileBusinessLogic.deletePhoto(
                                                  imageUrl,
                                                );
                                              },
                                              child: Container(
                                                height: 20,
                                                width: 20,
                                                decoration: BoxDecoration(
                                                  color: AppColors.purple,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        4.r,
                                                      ),
                                                ),
                                                child: Icon(
                                                  Icons.close,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            SizedBox(height: getProportionateScreenHeight(16)),
                            profileScoreAndVerify(
                              completion,
                              currentUser,
                              context,
                            ),
                            SizedBox(height: getProportionateScreenHeight(16)),
                            Container(
                              key: aboutScrollKey,
                              child: aboutField(
                                aboutController,
                                isAboutExpanded,
                                aboutFieldKey,
                              ),
                            ),
                            // if (isAIBioEnabled.value) ...[
                            SizedBox(height: getProportionateScreenHeight(6)),
                            GestureDetector(
                              onTap: isAIBioEnabled.value
                                  ? () async {
                                      if (isGeneratingBio.value) return;
                                      isGeneratingBio.value = true;
                                      final response = await BioService().generateBio(
                                        prompt: aboutController.text,
                                        age: currentUser.age,
                                        work: workController.text,
                                        diet: diet.value,
                                        smoker: smoker.value,
                                        drinker: drinking.value,
                                        zodiac: selectedZodiac.value,
                                        nationality:
                                            selectedCountry.value?.name,
                                        interests: interests.value.isNotEmpty
                                            ? interests.value
                                                  .map(
                                                    (index) => ProfileConstants
                                                        .interestStrings[index],
                                                  )
                                                  .toList()
                                            : (currentUser.interests ?? []),
                                        relationshipType:
                                            relationType.value.isNotEmpty
                                            ? relationType.value
                                                  .map(
                                                    (index) => ProfileConstants
                                                        .relationTypeStrings[index],
                                                  )
                                                  .toList()
                                            : (currentUser.relTypes ?? []),
                                      );
                                      aboutController.text =
                                          response ?? aboutController.text;
                                      isGeneratingBio.value = false;
                                    }
                                  : () {
                                      ReusableDialog.show(
                                        context,
                                        "Invalid subscription !",
                                        "Subscribe to access this feature.",
                                        "Subscribe",
                                        onConfirm: () async {
                                          currentNavigationIndex.value = 3;
                                        },
                                      );
                                    },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (isGeneratingBio.value) ...[
                                    Center(
                                      child: SizedBox(
                                        width: getProportionateScreenWidth(12),
                                        height: getProportionateScreenWidth(12),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  ] else ...[
                                    Icon(Iconsax.cpu, color: AppColors.purple),
                                  ],
                                  SizedBox(
                                    width: getProportionateScreenWidth(6),
                                  ),
                                  Text(
                                    'Auto Generate',
                                    style: TextStyle(
                                      color: AppColors.purple,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // ],
                            CustomChipsChoice(
                              title: "Who can message me directly?",
                              options:
                                  ProfileConstants.messagePermissionStrings,
                              selectedValue: messagePermission.value.isEmpty
                                  ? -1
                                  : ProfileConstants.messagePermissionStrings
                                        .indexOf(messagePermission.value),
                              onChanged: (val) {
                                whoCanMessageMe.value
                                    ? messagePermission.value = val >= 0
                                          ? ProfileConstants
                                                .messagePermissionStrings[val]
                                          : ""
                                    : ReusableDialog.show(
                                        context,
                                        "Invalid subscription !",
                                        "Subscribe to access this feature.",
                                        "Subscribe",
                                        onConfirm: () async {
                                          currentNavigationIndex.value = 3;
                                        },
                                      );
                              },
                            ),
                            SizedBox(height: getProportionateScreenHeight(20)),
                            AppFormField(
                              nameController: ageController,
                              isSavingChanges: isSavingChanges,
                              label: "Date of Birth",
                              readOnly: true,
                              onTap: () async {
                                await pickDate();
                              },
                              suffixIcon: Icons.calendar_month,
                            ),
                            SizedBox(height: getProportionateScreenHeight(20)),
                            AppFormField(
                              nameController: workController,
                              isSavingChanges: isSavingChanges,
                              label: "Work",
                              readOnly: true,
                              onTap: () async {
                                final result =
                                    await showModalBottomSheet<String>(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.white,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(20),
                                        ),
                                      ),
                                      builder: (_) =>
                                          AppBottomSheet(isWork: true),
                                    );
                                if (result != null) {
                                  workController.text = result;
                                }
                              },
                            ),
                            SizedBox(height: getProportionateScreenHeight(20)),
                            AppFormField(
                              nameController: educationController,
                              isSavingChanges: isSavingChanges,
                              readOnly: true,
                              label: "Education",
                              onTap: () async {
                                final result =
                                    await showModalBottomSheet<String>(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.white,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(20),
                                        ),
                                      ),
                                      builder: (_) =>
                                          AppBottomSheet(isWork: false),
                                    );
                                if (result != null) {
                                  educationController.text = result;
                                }
                              },
                            ),
                            SizedBox(height: getProportionateScreenHeight(20)),
                            Text(
                              'Location',
                              style: TextStyle(
                                color: AppColors.purple,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: getProportionateScreenHeight(4)),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
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
                                ),
                                SizedBox(
                                  width: getProportionateScreenWidth(12),
                                ),
                                GestureDetector(
                                  onTap: isFetchingLocation.value == true
                                      ? null
                                      : () async {
                                          isFetchingLocation.value = true;
                                          try {
                                            showSimpleNotification(
                                              Text("Fetching Location"),
                                              background: Colors.green,
                                              duration: Duration(seconds: 5),
                                              position:
                                                  NotificationPosition.top,
                                            );
                                            await Provider.of<UserProvider>(
                                              context,
                                              listen: false,
                                            ).getIpandLoc(context);
                                          } catch (e) {
                                            showSimpleNotification(
                                              Text(
                                                "Error Fetching Location, Try Again",
                                              ),
                                              background: Colors.red,
                                              duration: Duration(seconds: 5),
                                              position:
                                                  NotificationPosition.top,
                                            );
                                          } finally {
                                            showSimpleNotification(
                                              Text("Location Fetched"),
                                              background: Colors.green,
                                              duration: Duration(seconds: 5),
                                              position:
                                                  NotificationPosition.top,
                                            );
                                            isFetchingLocation.value = false;
                                          }
                                        },
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Color(0xFFFFBDBD).withAlpha(125),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          'My Location',
                                          style: TextStyle(
                                            color: AppColors.purple,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        SizedBox(
                                          width: getProportionateScreenWidth(4),
                                        ),
                                        Icon(
                                          Icons.location_on_outlined,
                                          color: AppColors.purple,
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: getProportionateScreenHeight(20)),
                            Text(
                              'Nationality',
                              style: TextStyle(
                                color: AppColors.purple,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => pickCountry(context),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Color(0xFFE2E2E2),
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      nationality.value != "" &&
                                              nationality.value != null
                                          ? nationality.value!
                                          : "Select Nationality",
                                    ),
                                    Spacer(),
                                    Icon(
                                      Iconsax.arrow_down_1,
                                      color: AppColors.greyShade,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            CustomChipsChoice(
                              title: "Marital Status",
                              options: ProfileConstants.maritalStrings,
                              selectedValue: maritalStatus.value.isEmpty
                                  ? -1
                                  : ProfileConstants.maritalStrings.indexOf(
                                      maritalStatus.value,
                                    ),
                              onChanged: (val) {
                                maritalStatus.value = val >= 0
                                    ? ProfileConstants.maritalStrings[val]
                                    : "";
                              },
                            ),
                            MultiChipsChoice(
                              title: "Sexual Orientation",
                              options: ProfileConstants.orientationStrings,
                              selectedValues: sexualOrientation.value,
                              onChanged: (val) {
                                sexualOrientation.value = val;
                              },
                            ),
                            SizedBox(height: getProportionateScreenHeight(16)),
                            Text(
                              isPhoneSignedIn ? 'Phone number' : 'Email',
                              style: TextStyle(
                                color: AppColors.purple,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: getProportionateScreenHeight(8)),
                            SizedBox(
                              width: double.infinity,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    isPhoneSignedIn
                                        ? Icons.phone_outlined
                                        : Icons.email_outlined,
                                    color: AppColors.purple,
                                    size: 16,
                                  ),
                                  SizedBox(
                                    width: getProportionateScreenWidth(8),
                                  ),
                                  Text(
                                    isPhoneSignedIn
                                        ? currentUser.phone ?? "Not added"
                                        : currentUser.email ?? "Not added",
                                    style: TextStyle(
                                      color: AppColors.purple,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: getProportionateScreenHeight(16)),
                            Text(
                              "Height",
                              style: TextStyle(
                                color: AppColors.purple,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      height.value > 0
                                          ? () {
                                              final totalInches =
                                                  (height.value.round() *
                                                          0.393701)
                                                      .round();
                                              final feet = totalInches ~/ 12;
                                              final inches = totalInches % 12;
                                              return "${height.value.round()}cm ($feet'$inches\")";
                                            }()
                                          : "Not specified",
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    height: getProportionateScreenHeight(4),
                                  ),
                                  Slider(
                                    padding: EdgeInsets.zero,
                                    activeColor: AppColors.purple,
                                    value: height.value.toDouble(),
                                    min: 40,
                                    max: 260,
                                    divisions: 220,
                                    label: '${height.value.round()} cm',
                                    onChanged: (double value) {
                                      height.value = value.toInt();
                                    },
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: getProportionateScreenHeight(20)),
                            Text(
                              "Zodiac Sign",
                              style: TextStyle(
                                color: AppColors.purple,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            DropdownButtonFormField<String?>(
                              initialValue: selectedZodiac.value,
                              decoration: InputDecoration(
                                hintText: "Select Zodiac",
                                border: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFFE2E2E2),
                                  ),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFFE2E2E2),
                                  ),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFFE2E2E2),
                                    width: 2,
                                  ),
                                ),
                              ),
                              dropdownColor: Color(0xFFF5F5F5),
                              menuMaxHeight:
                                  MediaQuery.of(context).size.height * 0.6,
                              items: ProfileConstants.zodiacStrings
                                  .map(
                                    (zodiac) => DropdownMenuItem(
                                      value: zodiac,
                                      child: Text(zodiac),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                selectedZodiac.value = value;
                              },
                            ),
                            SizedBox(height: getProportionateScreenHeight(20)),
                            if (!AuthHelper.isPhoneSignIn()) ...[
                              Text(
                                "Phone Number",
                                style: TextStyle(
                                  color: AppColors.purple,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: getProportionateScreenHeight(6)),
                              Container(
                                key: emailScrollKey,
                                child: phoneField(
                                  openCountryPicker,
                                  context,
                                  selectedCountry,
                                  phoneController,
                                  phoneFocusNode,
                                  emailFieldKey,
                                ),
                              ),
                            ] else ...[
                              Container(
                                key: emailScrollKey,
                                child: AppFormField(
                                  formKey: emailFieldKey,
                                  nameController: emailController,
                                  isSavingChanges: isSavingChanges,
                                  label: "Email",
                                  validator: (value) {
                                    final email = value?.trim();
                                    if (email == null || email.isEmpty) {
                                      return null;
                                    }
                                    if (!RegExp(
                                      r'^[\w-]+(\.[\w-]+)*@([\w-]+\.)+[a-zA-Z]{2,7}$',
                                    ).hasMatch(email)) {
                                      return "Please enter a valid email";
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                            CustomChipsChoice(
                              title: "Diet",
                              options: ProfileConstants.dietStrings,
                              selectedValue: diet.value.isEmpty
                                  ? -1
                                  : ProfileConstants.dietStrings.indexOf(
                                      diet.value,
                                    ),
                              onChanged: (val) {
                                diet.value = val >= 0
                                    ? ProfileConstants.dietStrings[val]
                                    : "";
                              },
                            ),
                            CustomChipsChoice(
                              title: "Religion",
                              options: ProfileConstants.religionStrings,
                              selectedValue: religion.value.isEmpty
                                  ? -1
                                  : ProfileConstants.religionStrings.indexOf(
                                      religion.value,
                                    ),
                              onChanged: (val) {
                                religion.value = val >= 0
                                    ? ProfileConstants.religionStrings[val]
                                    : "";
                              },
                            ),
                            MultiChipsChoice(
                              title: "Looking for relationship type",
                              options: ProfileConstants.relationTypeStrings,
                              selectedValues: relationType.value,
                              onChanged: (val) {
                                relationType.value = val;
                              },
                            ),
                            CustomChipsChoice(
                              title: "Smoker",
                              options: ProfileConstants.smokerStrings,
                              selectedValue: smoker.value.isEmpty
                                  ? -1
                                  : ProfileConstants.smokerStrings.indexOf(
                                      smoker.value,
                                    ),
                              onChanged: (val) {
                                smoker.value = val >= 0
                                    ? ProfileConstants.smokerStrings[val]
                                    : "";
                              },
                            ),
                            CustomChipsChoice(
                              title: "Drinking",
                              options: ProfileConstants.drinkingStrings,
                              selectedValue: drinking.value.isEmpty
                                  ? -1
                                  : ProfileConstants.drinkingStrings.indexOf(
                                      drinking.value,
                                    ),
                              onChanged: (val) {
                                drinking.value = val >= 0
                                    ? ProfileConstants.drinkingStrings[val]
                                    : "";
                              },
                            ),
                            MultiChipsChoice(
                              title: "Interests",
                              options: ProfileConstants.interestStrings,
                              selectedValues: interests.value,
                              onChanged: (val) {
                                interests.value = val;
                              },
                            ),
                            SizedBox(height: getProportionateScreenHeight(24)),
                            GestureDetector(
                              onTap:
                                  (!hasChanges.value || isSavingChanges.value)
                                  ? null
                                  : () async {
                                      final isValid =
                                          formKey.value.currentState
                                              ?.validate() ??
                                          false;

                                      if (!isValid) {
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                              if (aboutFieldKey
                                                      .currentState
                                                      ?.hasError ==
                                                  true) {
                                                scrollTo(aboutScrollKey);
                                                return;
                                              }

                                              if (emailFieldKey
                                                      .currentState
                                                      ?.hasError ==
                                                  true) {
                                                scrollTo(emailScrollKey);
                                                return;
                                              }
                                            });

                                        return;
                                      }
                                      await handleApplyChanges();
                                    },
                              child: Container(
                                height: getProportionateScreenHeight(60),
                                decoration: BoxDecoration(
                                  color:
                                      (!hasChanges.value ||
                                          isSavingChanges.value)
                                      ? Colors.grey
                                      : null,
                                  gradient:
                                      (!hasChanges.value ||
                                          isSavingChanges.value)
                                      ? null
                                      : LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: isSavingChanges.value
                                              ? [
                                                  kPrimaryPurple.withAlpha(216),
                                                  Color(
                                                    0xFF8B3A7B,
                                                  ).withAlpha(216),
                                                  // Color(0xFFA14281).withAlpha(216),
                                                  // kTertiaryPink,
                                                ]
                                              : [
                                                  kPrimaryPurple,
                                                  Color(0xFF8B3A7B),
                                                  // Color(0xFFA14281),
                                                  // kTertiaryPink,
                                                ],
                                          stops: [0.0, 0.80],
                                        ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Stack(
                                  children: [
                                    Center(
                                      child: Text(
                                        'Save Updates',
                                        style: TextStyle(
                                          fontFamily: 'Nunito',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 20,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    if (isSavingChanges.value == true)
                                      const Center(
                                        child: SizedBox(
                                          height: 16,
                                          width: 16,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: getProportionateScreenHeight(24)),
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

  Widget aboutField(
    TextEditingController aboutController,
    ValueNotifier<bool> isAboutExpanded,
    GlobalKey<FormFieldState<String>> aboutFieldKey,
  ) {
    return FormField<String>(
      key: aboutFieldKey,
      initialValue: aboutController.text,
      autovalidateMode: AutovalidateMode.always,
      validator: (value) {
        final text = value?.trim();

        if (text == null || text.isEmpty) {
          return null;
        }

        final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
        final lowerText = normalized.toLowerCase();

        if (normalized.isEmpty) return null;

        final emailRegex = AppConfigService.emailRegex;
        final phoneRegex = AppConfigService.phoneRegex;
        final socialProfileRegex = AppConfigService.socialProfileRegex;
        final suspiciousEmailTextRegex = AppConfigService.suspiciousEmailRegex;
        final socialUrlRegex = AppConfigService.socialUrlRegex;
        final genericUrlRegex = AppConfigService.genericUrlRegex;
        if (normalized.length < 50) {
          return 'Text is too short';
        }
        final handleRegex = RegExp(r'(?<!\w)@[a-zA-Z0-9._]{3,}(?!\w)');
        final contactIntentRegex = RegExp(
          r'\b(call|contact|phone|mobile|number|whatsapp|message me|text me|dm me|reach me|email me|mail me)\b',
          caseSensitive: false,
        );

        final hasEmail = emailRegex.hasMatch(normalized);
        final hasPhone = phoneRegex.hasMatch(normalized);
        final hasSocialProfile = socialProfileRegex.hasMatch(lowerText);
        final hasSocialUrl = socialUrlRegex.hasMatch(lowerText);
        final hasGenericUrl = genericUrlRegex.hasMatch(lowerText);
        final hasHandle = handleRegex.hasMatch(normalized);
        final hasContactIntent = contactIntentRegex.hasMatch(lowerText);
        final hasSuspiciousEmailText = suspiciousEmailTextRegex.hasMatch(
          lowerText,
        );

        if (hasEmail) {
          return 'Text contains an email address';
        }

        if (hasPhone) {
          return 'Text contains a phone number';
        }

        if (hasSocialUrl || hasSocialProfile || hasHandle) {
          return 'Text contains social media or profile information';
        }

        if (hasGenericUrl) {
          return 'Text contains a website link';
        }

        if (hasContactIntent || hasSuspiciousEmailText) {
          return 'Text contains contact-related text';
        }

        return null;
      },
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.colorPink.withAlpha(42),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'About',
                    style: TextStyle(
                      color: AppColors.purple,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextFormField(
                    controller: aboutController,
                    autofocus: false,
                    onChanged: field.didChange,
                    maxLines: isAboutExpanded.value ? null : 3,
                    maxLength: 1000,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(
                      color: Color(0xFF767676),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: const InputDecoration(
                      hintText: "Write something about yourself...",
                      hintStyle: TextStyle(
                        color: Color(0xFF767676),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      counterText: "",
                      errorText: null,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (aboutController.text.length > 150)
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () {
                          isAboutExpanded.value = !isAboutExpanded.value;
                        },
                        child: Text(
                          isAboutExpanded.value ? 'Read less' : 'Read more',
                          style: TextStyle(
                            color: AppColors.purple,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.purple,
                          ),
                        ),
                      ),
                    ),

                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Max 1000 characters',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: AppColors.colorGrey,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 6),
                child: Text(
                  field.errorText!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget phoneField(
    void Function(
      BuildContext context,
      ValueNotifier<cps.Country?> selectedCountry,
    )
    openCountryPicker,
    BuildContext context,
    ValueNotifier<cps.Country?> selectedCountry,
    TextEditingController phoneController,
    FocusNode focusNode,
    emailFormKey,
  ) {
    return FormField<String>(
      initialValue: phoneController.text,
      autovalidateMode: AutovalidateMode.always,
      key: emailFormKey,
      validator: (_) {
        final phone = phoneController.text.trim();

        if (phone.isEmpty) {
          return null;
        }

        if (phone.length != 10) {
          return "Phone number should be of 10 digits";
        }

        if (!RegExp(r'^[2-9]\d{9}$').hasMatch(phone)) {
          return "Please enter a valid phone number";
        }

        return null;
      },
      builder: (field) {
        return InputDecorator(
          isFocused: focusNode.hasFocus,
          decoration: InputDecoration(
            errorText: field.errorText, // error shows outside/below the box

            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.borderColor,
                width: 1,
              ),
            ),

            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.purple, width: 1),
            ),

            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.red, width: 1),
            ),

            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.red, width: 1),
            ),

            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.borderColor,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => openCountryPicker(context, selectedCountry),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selectedCountry.value != null)
                      SizedBox(
                        width: getProportionateScreenWidth(28),
                        height: getProportionateScreenHeight(20),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: cps.CountryPickerUtils.getDefaultFlagImage(
                            selectedCountry.value!,
                          ),
                        ),
                      )
                    else
                      Container(
                        width: getProportionateScreenWidth(28),
                        height: getProportionateScreenHeight(20),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: Text(
                            "🇮🇳",
                            style: TextStyle(
                              fontSize: getProportionateScreenWidth(14),
                            ),
                          ),
                        ),
                      ),

                    SizedBox(width: getProportionateScreenWidth(4)),

                    Text(
                      "+${selectedCountry.value?.phoneCode ?? '91'}",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),

                    SizedBox(width: getProportionateScreenWidth(2)),

                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: getProportionateScreenWidth(18),
                      color: Colors.black,
                    ),
                  ],
                ),
              ),

              SizedBox(width: getProportionateScreenWidth(8)),

              Container(
                width: 1,
                height: getProportionateScreenHeight(24),
                color: Colors.grey,
              ),

              SizedBox(width: getProportionateScreenWidth(10)),

              Expanded(
                child: TextField(
                  focusNode: focusNode,
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                    counterText: '',
                    hintText: "9999999999",
                    hintStyle: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.colorGrey,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Row profileScoreAndVerify(
    int completion,
    UserDetails currentUser,
    BuildContext context,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: getProportionateScreenWidth(32),
                height: getProportionateScreenWidth(32),
                child: CircularProgressIndicator(
                  backgroundColor: AppColors.colorPink.withAlpha(25),
                  value: completion / 100,
                  strokeWidth: 6,
                  strokeCap: StrokeCap.round,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.purple),
                ),
              ),
              SizedBox(width: getProportionateScreenWidth(8)),
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
        SizedBox(width: getProportionateScreenWidth(16)),
        if (currentUser.isVerified == false) ...[
          VerifyProfile(gender: currentUser.gender ?? 'male'),
        ] else ...[
          SizedBox.shrink(),
        ],
      ],
    );
  }
}

class VerifyProfile extends StatelessWidget {
  const VerifyProfile({required this.gender, this.height, super.key});

  final String gender;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await VerifyProfileDialog.show(
          context,
          userGender: gender,
          onStartVerification: () {
            // Navigate to liveness verification screen
            Navigator.of(
              context,
            ).pushNamed(LivenessVerificationScreen.routeName);
          },
          onSkip: () async {},
        );
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: height != null ? height ?? 6 : 8,
        ),
        decoration: BoxDecoration(
          // color: AppColors.colorPink.withAlpha(38),
          gradient: LinearGradient(colors: [kPrimaryPurple, Color(0xFF8B3A7B)]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      color: Colors.white,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      "Verify Profile",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Text(
                  "Show users you’re real",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            SizedBox(width: getProportionateScreenWidth(8)),
            Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}

class AppFormField extends StatefulWidget {
  const AppFormField({
    super.key,
    required this.nameController,
    required this.isSavingChanges,
    required this.label,
    this.focusNode,
    this.readOnly = false,
    this.onTap,
    this.suffixIcon,
    this.validate = true,
    this.validator,
    this.formKey,
  });

  final TextEditingController nameController;
  final ValueNotifier<bool> isSavingChanges;
  final String label;
  final FocusNode? focusNode;
  final bool? readOnly;
  final VoidCallback? onTap;
  final IconData? suffixIcon;
  final bool? validate;
  final String? Function(String?)? validator;
  final GlobalKey<FormFieldState<String>>? formKey;

  @override
  State<AppFormField> createState() => _AppFormFieldState();
}

class _AppFormFieldState extends State<AppFormField> {
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: widget.formKey,
      controller: widget.nameController,
      autofocus: false,
      maxLines: 1,
      focusNode: widget.focusNode,
      readOnly: widget.readOnly ?? false,
      enabled: !widget.isSavingChanges.value,
      onTap: widget.onTap,
      textInputAction: TextInputAction.done,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Colors.black,
      ),
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.purple,
        ),
        hintText: widget.label,
        hintStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.colorGrey,
        ),
        suffixIcon: widget.suffixIcon != null
            ? Icon(widget.suffixIcon, color: AppColors.purple, size: 24)
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderColor, width: 1),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderColor, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.purple, width: 1),
        ),
      ),
    );
  }
}
