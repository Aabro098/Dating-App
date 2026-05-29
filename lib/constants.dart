import 'package:flutter/material.dart';

import 'size_config.dart';

// ═══════════════════════════════════════════════════════════════════════════
// VIORA COLOR PALETTE
// ═══════════════════════════════════════════════════════════════════════════

/// Primary Purple - Main brand color
const Color kPrimaryPurple = Color(0xFF3E1E68);

/// Secondary Purple - Slightly lighter purple
const Color kSecondaryPurple = Color(0xFF5D2F77);

/// Tertiary Pink - Accent pink color
const Color kTertiaryPink = Color(0xFFE45A92);

/// Quaternary Pink - Light pink for backgrounds/overlays
const Color kQuaternaryPink = Color(0xFFFFACAC);

/// Background Color - Very light pink/white background
const Color kBackgroundBG = Color(0xFFFFF9F9);

/// Light Purple - For subtle backgrounds
const Color kLightPurple = Color(0xFFF5EBFF);

/// Pure White
const Color kWhite = Color(0xFFFFFFFF);

/// Pure Black
const Color kBlack = Color(0xFF000000);

/// Primary Gradient - Purple to Pink
const LinearGradient kPrimaryGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [kPrimaryPurple, kTertiaryPink],
);

// ═══════════════════════════════════════════════════════════════════════════
// LEGACY COLORS & IMAGES (for backward compatibility)
// ═══════════════════════════════════════════════════════════════════════════

// DEPRECATED: Use AppConfigService.maleImageUrl and AppConfigService.femaleImageUrl instead
// These are now configurable in Firestore at AppConfig/PlaceholderImages
const kMaleUrl =
    "https://1.bp.blogspot.com/--Ag41rfepUk/YRYesJ_f6AI/AAAAAAAAASk/fWkzd5_IyvokzQdZrrK_t6hs2D6LasztACLcBGAsYHQ/s16000/male.png";
const kFemaleUrl =
    "https://1.bp.blogspot.com/-ncU-Ju8RCsQ/YRYesNIIMGI/AAAAAAAAASo/nYV2uRbMx5odxOOtfJErQR4LfKhHicVKQCLcBGAsYHQ/s16000/female.png";
const notificationApi =
    "	AAAAuDKqLig:APA91bH_XifJfp4IZKhqL3HWROMtLrDTilQDM8Eh9ifzqBSy0_2Sk_IaNx3cgUDZR6e3MwjPe-WJnjTGTfJ2FktQGG1qhFQoxu1DLMFjscFUUOM3sj225MxNqi0TqWVsXv-8nYYg8SJ_";

const helpMessage = """
Hi there,
Please don't share your contact details to anyone, otherwise your account might be disabled.

Regards,
Viora Team.
""";

const kPrimaryColor = kPrimaryPurple; // Updated to use new palette
const kPrimaryLightColor = Color(0xFFFFECDF);
const kPrimaryGradientColor = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF491844), Color(0xFF84264C)],
);
const kSecondaryColor = Color(0xFF979797);
const kTextColor = Color(0xFF757575);

const kAnimationDuration = Duration(milliseconds: 200);
const double kDefaultPadding = 20.0;
final headingStyle = TextStyle(
  fontSize: getProportionateScreenWidth(28),
  fontWeight: FontWeight.bold,
  color: Colors.black,
  height: 1.5,
);
final sHeadingStyle = TextStyle(
  fontSize: getProportionateScreenWidth(18),
  fontWeight: FontWeight.bold,
  color: Colors.black,
  height: 1.5,
);

const defaultDuration = Duration(milliseconds: 250);

// Form Error
final RegExp emailValidatorRegExp = RegExp(
  r"^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
);
const String kEmailNullError = "Please Enter your email";
const String kInvalidEmailError = "Please Enter Valid Email";
const String kPassNullError = "Please Enter your password";
const String kShortPassError =
    "Password is too short must be greater than 8 characters";
const String kMatchPassError = "Passwords don't match";
const String kNamelNullError = "Please Enter your name";
const String kPhoneNumberNullError = "Please Enter your phone number";
const String kAddressNullError = "Please Enter your address";
const String kReqError = "Please Enter Required Field";
const String kAgeError = "Age must be 18 Years";
const String kValidPinError = "Please Enter Valid PinCode";
const String kShareData =
    "MEET THE CHOSEN ONE"
    "Get Free 10 Coins on Downloading Viora\n"
    "Find your twin soul near you and have fun"
    "Download Now\n"
    "At  \n"
    "https://play.google.com/store/apps/details?id=com.epochtechlabs.viora&hl=en_IN";

const String appName = "Viora";
const String kAppCover =
    "https://1.bp.blogspot.com/-pO_NCEyVm4E/YP6oGEhcVcI/AAAAAAAAASE/XEVNXRGkR3EwvwI5M1ylDN7M8fCh5mHEACLcBGAsYHQ/s16000/e48fb3cc11a0d4508a6fa0ab066c82c7.jpg";
const kAppUrl =
    "https://play.google.com/store/apps/details?id=com.epochtechlabs.viora&hl=en_IN";
const kInstaUrl = "https://www.instagram.com/oneword.in/?hl=en";
const kPrivacyUrl =
    "https://meetisy.blogspot.com/2021/07/meetisy-privacy-policy.html";
const kRupee = "\u{20B9}";

final otpInputDecoration = InputDecoration(
  contentPadding: EdgeInsets.symmetric(
    vertical: getProportionateScreenWidth(15),
  ),
  border: outlineInputBorder(),
  focusedBorder: outlineInputBorder(),
  enabledBorder: outlineInputBorder(),
);

OutlineInputBorder outlineInputBorder() {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(getProportionateScreenWidth(15)),
    borderSide: BorderSide(color: kTextColor),
  );
}
