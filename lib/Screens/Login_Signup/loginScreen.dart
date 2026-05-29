import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:country_pickers/country.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:country_pickers/country_pickers.dart';
import 'package:country_pickers/utils/utils.dart';
import 'package:viora/Screens/PrivacyPolicy/PrivacyPolicy.dart';
import 'package:viora/Screens/PrivacyPolicy/terms.dart';
import 'package:viora/Services/PhoneAuthService.dart';
import 'package:viora/components/custom_surfix_icon.dart';
import 'package:viora/constants.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'package:overlay_support/overlay_support.dart';

import '../../Services/AuthService.dart';
import '../../size_config.dart';
import '../../utils/phone_validation_util.dart';
import '../../utils/request_state_util.dart';
import '../../utils/notification_util.dart';

/// Login Screen - Main entry point for authentication
class LoginScreen extends HookWidget {
  const LoginScreen({super.key});

  static String routeName = "/login";

  @override
  Widget build(BuildContext context) {
    useEffect(() {
      // This removes the native splash screen as soon as this screen loads
      FlutterNativeSplash.remove();
      
      // Show system UI overlays for login screen
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      
      return null;
    }, []);
    return Scaffold(
      backgroundColor: kPrimaryPurple,
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
            ),
            child: Stack(
              children: [
                // Background image with gradient overlay
                _BackgroundSection(),
                // Main content
                _ContentSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Background image with gradient overlay
class _BackgroundSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: getProportionateScreenHeight(618),
        child: Stack(
          children: [
            // Background image
            Image.asset(
              "assets/backgrounds/login_signup.png",
              height: getProportionateScreenHeight(618),
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Color(0xFF401F69),
                child: const Icon(Icons.error, color: Colors.white),
              ),
            ),
            // Purple tint overlay
            Container(
              height: getProportionateScreenHeight(618),
              color: Color(0xFF401F69).withOpacity(0.2),
            ),
            // Gradient overlay
            Container(
              height: getProportionateScreenHeight(618),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.42, 0.70, 1.0],
                  colors: [
                    Colors.transparent,
                    kPrimaryPurple.withOpacity(0.0),
                    kPrimaryPurple.withOpacity(0.5),
                    kPrimaryPurple,
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

/// Main content section with all UI elements
class _ContentSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,

      children: [
        SizedBox(height: getProportionateScreenHeight(323)),
        // Tagline with hearts
        _TaglineSection(),
        SizedBox(height: getProportionateScreenHeight(30)),
        // Login options container
        _LoginOptionsContainer(),
        SizedBox(height: getProportionateScreenHeight(22)),
        // Sign up prompt
        //Comenting for now as per new design
        // _SignUpPrompt(),
        // SizedBox(height: getProportionateScreenHeight(15)),
        // Terms and privacy
        _TermsAndPrivacy(),
        SizedBox(height: getProportionateScreenHeight(20)),
      ],
    );
  }
}

/// Tagline section with decorative hearts
class _TaglineSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: getProportionateScreenWidth(353),
      height: getProportionateScreenHeight(104.32),
      child: Stack(
        children: [
          // Right heart SVG
          Positioned(
            right: 0,
            top: 0,
            child: SvgPicture.asset(
              'assets/svg/hearts_right.svg',
              width: getProportionateScreenWidth(30),
              height: getProportionateScreenHeight(30),
              fit: BoxFit.contain,
            ),
          ),
          // Left heart SVG
          Positioned(
            left: 0,
            bottom: 0,
            child: SvgPicture.asset(
              //Change the opacity as per your requirement
              color: kTertiaryPink.withOpacity(0.5),
              'assets/svg/hearts_left.svg',
              width: getProportionateScreenWidth(19.28),
              height: getProportionateScreenHeight(19.28),
              fit: BoxFit.contain,
            ),
          ),
          // Text content centered
          Positioned(
            left: 0,
            right: 0,
            top: getProportionateScreenHeight(39.79),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  "Talk. Feel. Live the Moment",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w700,
                    fontSize: getProportionateScreenWidth(26),
                    height: 35 / 26, // line-height / font-size
                    color: Colors.white,
                  ),
                ),
                Text(
                  "Find your twin soul and have fun",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w500,
                    fontSize: getProportionateScreenWidth(16),
                    height: 22 / 16, // line-height / font-size
                    color: Color(0xFFE2E2E2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Login options container with frosted glass effect
class _LoginOptionsContainer extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final isGoogleLoading = useState(false);

    Future<void> handleGoogleSignIn() async {
      if (isGoogleLoading.value) return;

      isGoogleLoading.value = true;

      try {
        final result = await GoogleAuth.signInWithGoogle(context);

        if (!result.success && context.mounted) {
          if (result.errorType != GoogleAuthErrorType.canceled) {
            GoogleAuth.showErrorSnackbar(context, result.errorMessage!);
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('An unexpected error occurred. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        isGoogleLoading.value = false;
      }
    }

    return Container(
      width: getProportionateScreenWidth(383),
      margin: EdgeInsets.symmetric(horizontal: getProportionateScreenWidth(14.5)),
      padding: EdgeInsets.all(getProportionateScreenWidth(17.5)),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.3),
        border: Border.all(color: Color(0xFFEEEEEE), width: 1.5),
        borderRadius: BorderRadius.circular(getProportionateScreenWidth(14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Phone login button
          _PhoneLoginButton(),
          SizedBox(height: getProportionateScreenHeight(18)),
          // OR divider
          _OrDivider(),
          SizedBox(height: getProportionateScreenHeight(17)),
          // Google login button
          _GoogleLoginButton(
            isLoading: isGoogleLoading.value,
            onTap: handleGoogleSignIn,
          ),
        ],
      ),
    );
  }
}

/// Phone login button
class _PhoneLoginButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    void showPhoneDialog() {
      showDialog(
        barrierDismissible: false,
        barrierColor: Color.fromRGBO(31, 31, 31, 0.25),
        context: context,
        builder: (_) => const _PhoneNumberDialog(),
      );
    }

    return GestureDetector(
      onTap: showPhoneDialog,
      child: Container(
        width: getProportionateScreenWidth(348),
        height: getProportionateScreenHeight(48),
        padding: EdgeInsets.symmetric(
          horizontal: getProportionateScreenWidth(22),
          vertical: getProportionateScreenHeight(12),
        ),
        decoration: BoxDecoration(
          color: Color(0xFFF3F3F3),
          border: Border.all(color: Color(0xFFD7D7D7)),
          borderRadius: BorderRadius.circular(getProportionateScreenWidth(40)),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              "assets/svg/phone_icon.svg",
              height: getProportionateScreenWidth(24),
              width: getProportionateScreenWidth(24),
                fit: BoxFit.contain,
            ),
            Expanded(
              child: Center(
                child: Text(
                  "Login with Phone number",
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w400,
                    fontSize: getProportionateScreenWidth(16),
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// OR divider
class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: getProportionateScreenWidth(348),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: Color(0xFFD9D9D9),
                borderRadius: BorderRadius.circular(getProportionateScreenWidth(71)),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: getProportionateScreenWidth(10)),
            child: Text(
              "OR",
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w500,
                fontSize: getProportionateScreenWidth(16),
                color: Color(0xFFB7B7B7),
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: Color(0xFFD9D9D9),
                borderRadius: BorderRadius.circular(getProportionateScreenWidth(71)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Google login button
class _GoogleLoginButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _GoogleLoginButton({
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Opacity(
        opacity: isLoading ? 0.6 : 1.0,
        child: Container(
          width: getProportionateScreenWidth(348),
          height: getProportionateScreenHeight(48),
          padding: EdgeInsets.symmetric(
            horizontal: getProportionateScreenWidth(22),
            vertical: getProportionateScreenHeight(12),
          ),
          decoration: BoxDecoration(
            color: Color(0xFFF3F3F3),
            border: Border.all(color: Color(0xFFD7D7D7)),
            borderRadius: BorderRadius.circular(getProportionateScreenWidth(40)),
          ),
          child: Row(
            children: [
              SvgPicture.asset(
                "assets/svg/google_icon.svg",
                height: getProportionateScreenWidth(24),
                width: getProportionateScreenWidth(24),
                  fit: BoxFit.contain,
              ),
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Login with Google",
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w400,
                          fontSize: getProportionateScreenWidth(16),
                          color: Colors.black,
                        ),
                      ),
                      if (isLoading)
                        Padding(
                          padding: EdgeInsets.only(left: getProportionateScreenWidth(12)),
                          child: SizedBox(
                            width: getProportionateScreenWidth(20),
                            height: getProportionateScreenWidth(20),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
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
    );
  }
}

/// Sign up prompt
class _SignUpPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: getProportionateScreenWidth(15)),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Don't have account yet? ",
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w600,
                fontSize: getProportionateScreenWidth(16),
                color: Colors.white,
              ),
            ),
            GestureDetector(
              onTap: () {
                // TODO: Navigate to sign up
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Sign up coming soon')),
                );
              },
              child: Text(
                "Sign up",
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w600,
                  fontSize: getProportionateScreenWidth(16),
                  color: kTertiaryPink,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Phone number input dialog with validation
class _PhoneNumberDialog extends HookWidget {
  const _PhoneNumberDialog();

  @override
  Widget build(BuildContext context) {
    final phoneController = useTextEditingController();
    final isLoading = useState(false);
    final phoneError = useState<String?>(null);
    final selectedCountry = useState<Country?>(CountryPickerUtils.getCountryByIsoCode('IN'));

    // --- Session Management ---
    final isRequestActive = useRef<bool>(false);
    final currentProcessingPhone = useRef<String?>(null); // Track which phone number is being processed
    
    // --- FIX: Track the active notification ---
    final activeOverlay = useRef<OverlaySupportEntry?>(null);
    
    // --- FIX: Track last toast time to prevent spam ---
    final lastToastTime = useRef<int>(0);
    const toastDebounceMs = 2000; // 2 seconds between toasts
    
    // --- Helper: Show Error Notification (Red) ---
    void showErrorNotification(String message) {
      NotificationUtil.showErrorNotification(
        context: context,
        message: message,
        getActiveOverlay: () => activeOverlay.value,
        setActiveOverlay: (overlay) => activeOverlay.value = overlay,
        getLastToastTime: () => lastToastTime.value,
        setLastToastTime: (time) => lastToastTime.value = time,
      );
    }

    // --- Helper: Show Warning Notification (Orange) ---
    void showWarningNotification(String message) {
      NotificationUtil.showWarningNotification(
        context: context,
        message: message,
        getActiveOverlay: () => activeOverlay.value,
        setActiveOverlay: (overlay) => activeOverlay.value = overlay,
        getLastToastTime: () => lastToastTime.value,
        setLastToastTime: (time) => lastToastTime.value = time,
      );
    }

    // --- Effect: Clear field errors on typing ---
    useEffect(() {
      void listener() {
        if (phoneError.value != null && phoneController.text.isNotEmpty) {
          phoneError.value = null;
        }
      }
      phoneController.addListener(listener);
      return () => phoneController.removeListener(listener);
    }, []);

    // --- Effect: Cancel active request if phone number changes ---
    useEffect(() {
      void listener() {
        final currentPhone = phoneController.text.trim();
        final processingPhone = currentProcessingPhone.value;
        
        // If phone number changed while a request is active, cancel it
        if (processingPhone != null && 
            currentPhone != processingPhone && 
            currentPhone.isNotEmpty &&
            isRequestActive.value) {
          // Reset states to allow new request
          isRequestActive.value = false;
          isLoading.value = false;
          currentProcessingPhone.value = null;
          // Clear any stale verification session
          PhoneAuth.clearVerificationSession();
        }
      }
      phoneController.addListener(listener);
      return () => phoneController.removeListener(listener);
    }, []);

    // --- Logic: Continue Button ---
    Future<void> continuePressed() async {
      // Clear any existing toasts immediately when button is pressed
      activeOverlay.value?.dismiss();
      
      // Prevent multiple simultaneous calls
      if (isLoading.value) {
        return;
      }
      
      // Get current phone number first
      final phone = phoneController.text.trim();
      
      // Check request state using utility
      final requestState = RequestStateUtil.checkRequestState(
        isLoading: isLoading.value,
        isRequestActive: isRequestActive.value,
        currentProcessingValue: currentProcessingPhone.value,
        newValue: phone,
      );

      if (requestState.shouldCancelPrevious) {
        RequestStateUtil.resetRequestState(
          setLoading: (value) => isLoading.value = value,
          setRequestActive: (value) => isRequestActive.value = value,
          setCurrentProcessingValue: (value) => currentProcessingPhone.value = value,
        );
        PhoneAuth.clearVerificationSession();
      }

      if (!requestState.isAllowed) {
        if (requestState.message != null) {
          showWarningNotification(requestState.message!);
        }
        return;
      }

      // Validate phone number using utility
      final validationError = PhoneValidationUtil.validatePhoneNumberWithMessage(phone);
      if (validationError != null) {
        showErrorNotification(validationError);
        return;
      }

      // Mark request as active using utility
      RequestStateUtil.setRequestActive(
        setLoading: (value) => isLoading.value = value,
        setRequestActive: (value) => isRequestActive.value = value,
        setCurrentProcessingValue: (value) => currentProcessingPhone.value = value,
        value: phone,
      );

      try {
        final countryCode = '+${selectedCountry.value?.phoneCode ?? '91'}';

        final result = await PhoneAuth.verifyPhoneNumber(
          context,
          phone,
          countryCode: countryCode,
        );
        
        // Check if phone number changed during the request
        final currentPhone = phoneController.text.trim();
        if (currentPhone != phone) {
          return;
        }
      } catch (e) {
        // Check if phone number changed during the request
        final currentPhone = phoneController.text.trim();
        if (currentPhone != phone) {
          return;
        }
        
        if (context.mounted) {
          showErrorNotification('Failed to send OTP. Please try again.');
        }
      } finally {
        // Only reset if this is still the current phone being processed
        final currentPhone = phoneController.text.trim();
        if (currentProcessingPhone.value == phone || currentPhone.isEmpty) {
          RequestStateUtil.resetRequestState(
            setLoading: (value) => isLoading.value = value,
            setRequestActive: (value) => isRequestActive.value = value,
            setCurrentProcessingValue: (value) => currentProcessingPhone.value = value,
          );
        }
      }
    }

    // --- Logic: Pick from SIM ---
    Future<void> pickPhoneNumber() async {
      // Clear any existing toasts immediately
      activeOverlay.value?.dismiss();

      // Prevent multiple simultaneous calls
      if (isLoading.value) {
        debugPrint('⚠️ Already processing, ignoring SIM picker request');
        return;
      }
      
      // Check request state using utility (no phone number yet for SIM picker)
      final requestState = RequestStateUtil.checkRequestState(
        isLoading: isLoading.value,
        isRequestActive: isRequestActive.value,
        currentProcessingValue: currentProcessingPhone.value,
        newValue: null, // No phone number yet
      );

      if (requestState.shouldCancelPrevious) {
        RequestStateUtil.resetRequestState(
          setLoading: (value) => isLoading.value = value,
          setRequestActive: (value) => isRequestActive.value = value,
          setCurrentProcessingValue: (value) => currentProcessingPhone.value = value,
        );
        PhoneAuth.clearVerificationSession();
      }

      if (!requestState.isAllowed) {
        if (requestState.message != null) {
          showWarningNotification(requestState.message!);
        }
        return;
      }

      // Mark request as active (phone will be set after SIM picker returns)
      isLoading.value = true;
      isRequestActive.value = true;

      try {
        // Add timeout to prevent indefinite waiting
        final hint = await SmsAutoFill().hint.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            return null;
          },
        );

        if (hint != null) {
          // Extract and format phone number using utility
          final digitsOnly = PhoneValidationUtil.extractLast10Digits(hint);
          final countryCode = '+${selectedCountry.value?.phoneCode ?? '91'}';
          
          // Track the phone number being processed
          currentProcessingPhone.value = digitsOnly;
          
          await PhoneAuth.verifyPhoneNumber(
            context,
            digitsOnly,
            countryCode: countryCode,
          );
        } else {
          if (context.mounted) {
            showWarningNotification('No number selected. Please type manually');
          }
        }
      } catch (e) {
        if (context.mounted) {
          // Don't show error for user cancellation
          if (!e.toString().contains('cancel')) {
            showErrorNotification('Unable to access SIM. Type manually');
          }
        }
      } finally {
        // ALWAYS reset loading and request state using utility
        RequestStateUtil.resetRequestState(
          setLoading: (value) => isLoading.value = value,
          setRequestActive: (value) => isRequestActive.value = value,
          setCurrentProcessingValue: (value) => currentProcessingPhone.value = value,
        );
      }
    }

    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 6.2, sigmaY: 6.2),
      child: Stack(
        children: [
          Dialog(
            backgroundColor: const Color.fromRGBO(230, 228, 228, 1),
            insetPadding: EdgeInsets.symmetric(
              horizontal: getProportionateScreenWidth(26),
              vertical: getProportionateScreenHeight(24),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(getProportionateScreenWidth(12)),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(getProportionateScreenWidth(30)),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(230, 228, 228, 1),
                  borderRadius: BorderRadius.circular(getProportionateScreenWidth(12)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title with icon
                    Row(
                      children: [
                        Icon(
                          Icons.phone,
                          color: kPrimaryPurple,
                          size: getProportionateScreenWidth(26),
                        ),
                        SizedBox(width: getProportionateScreenWidth(6)),
                        Text(
                          "Enter phone number",
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w600,
                            fontSize: getProportionateScreenWidth(22),
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: getProportionateScreenHeight(20)),
                    
                    // Phone input field with country picker
                    _PhoneInputField(
                      controller: phoneController,
                      isLoading: isLoading.value,
                      errorText: phoneError.value,
                      onSubmit: continuePressed,
                      selectedCountry: selectedCountry.value,
                      onCountryChanged: (country) {
                        selectedCountry.value = country;
                      },
                    ),
                    SizedBox(height: getProportionateScreenHeight(20)),
                    
                    // Continue button
                    _ContinueButton(
                      isLoading: isLoading.value,
                      onPressed: continuePressed,
                    ),
                    SizedBox(height: getProportionateScreenHeight(14)),
                    
                    // OR divider
                     _DialogOrDivider(),
                    SizedBox(height: getProportionateScreenHeight(14)),
                    
                    // Pick from phone buttons
                    _PickPhoneButton(
                      isLoading: isLoading.value,
                      onPressed: pickPhoneNumber,
                      simLabel: "Choose Number from Sim",
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Close button - positioned outside dialog in background at top right
          Positioned(
            top: getProportionateScreenHeight(20),
            right: getProportionateScreenWidth(20),
            child: GestureDetector(
              onTap: () {
                // Reset ALL session state when dialog closes to prevent stuck loaders
                isRequestActive.value = false;
                isLoading.value = false;
                Navigator.of(context).pop();
              },
              child: Container(
                width: getProportionateScreenWidth(45),
                height: getProportionateScreenWidth(45),
                decoration: BoxDecoration(
                  color: kSecondaryPurple,
                  borderRadius: BorderRadius.circular(getProportionateScreenWidth(22.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.close,
                    color: Colors.white,
                    size: getProportionateScreenWidth(24),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
/// Phone input field with country code picker
class _PhoneInputField extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final String? errorText;
  final VoidCallback onSubmit;
  final Country? selectedCountry;
  final Function(Country) onCountryChanged;

  const _PhoneInputField({
    required this.controller,
    required this.isLoading,
    required this.errorText,
    required this.onSubmit,
    required this.selectedCountry,
    required this.onCountryChanged,
  });

  void _openCountryPicker(BuildContext context) {
    showDialog(
      
      context: context,
      builder: (_) => Theme(
        
        data: Theme.of(context).copyWith(
          dialogBackgroundColor: Color.fromRGBO(230, 228, 228, 1),
        ),
        child: CountryPickerDialog(
          
          titlePadding: EdgeInsets.all(getProportionateScreenWidth(8)),
          searchCursorColor: kTertiaryPink,
          searchInputDecoration: InputDecoration(
            hintText: 'Search country...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(getProportionateScreenWidth(8)),
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
          onValuePicked: (Country country) {
            onCountryChanged(country);
          },
          itemBuilder: _buildCountryItem,
        ),
      ),
    );
  }

  Widget _buildCountryItem(Country country) => Container(
    padding: EdgeInsets.all(getProportionateScreenWidth(8)),
    child: Row(
      children: [
        CountryPickerUtils.getDefaultFlagImage(country),
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
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Input container
          Container(
            height: getProportionateScreenHeight(60),
            decoration: BoxDecoration(
              border: Border.all(color: Color(0xFF999999), width: 1),
              borderRadius: BorderRadius.circular(getProportionateScreenWidth(28)),
            ),
            child: Row(
              children: [
                SizedBox(width: getProportionateScreenWidth(18)),
                // Country code section - clickable
                GestureDetector(
                  onTap: () => _openCountryPicker(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Flag from country picker
                      if (selectedCountry != null)
                        SizedBox(
                          width: getProportionateScreenWidth(32),
                          height: getProportionateScreenHeight(22),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(getProportionateScreenWidth(6)),
                            child: CountryPickerUtils.getDefaultFlagImage(selectedCountry!),
                          ),
                        )
                      else
                        Container(
                          width: getProportionateScreenWidth(36),
                          height: getProportionateScreenHeight(26),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(getProportionateScreenWidth(6)),
                          ),
                          child: Center(
                            child: Text(
                              "🇮🇳",
                              style: TextStyle(fontSize: getProportionateScreenWidth(20)),
                            ),
                          ),
                        ),
                      SizedBox(width: getProportionateScreenWidth(4)),
                      Text(
                        "+${selectedCountry?.phoneCode ?? '91'}",
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w500,
                          fontSize: getProportionateScreenWidth(12),
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(width: getProportionateScreenWidth(2)),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: getProportionateScreenWidth(22),
                        color: Colors.black,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: getProportionateScreenWidth(3)),
                // Divider
                Container(
                  width: 1,
                  height: getProportionateScreenHeight(26),
                  color: Color(0xFF999999),
                ),
                SizedBox(width: getProportionateScreenWidth(10)),
                // Phone number input
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    enabled: !isLoading,
                    textAlignVertical: TextAlignVertical.center,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w700,
                      fontSize: getProportionateScreenWidth(15),
                      color: Colors.black,
                      height: 1.2,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      counterText: '',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: getProportionateScreenHeight(12)),
                      hintText: isLoading ? "Fetching..." : "9874957389",
                      hintStyle: TextStyle(
                        color: Color(0xFFCCCCCC),
                        fontWeight: FontWeight.w600,
                        fontSize: getProportionateScreenWidth(15),
                        fontFamily: 'Nunito',
                      ),
                    ),
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
                SizedBox(width: getProportionateScreenWidth(10)),
                SvgPicture.asset(
                  'assets/svg/empty_phone.svg',
                  width: getProportionateScreenWidth(20),
                  height: getProportionateScreenHeight(20),
                  fit: BoxFit.contain,
                ),
                SizedBox(width: getProportionateScreenWidth(18)),
              ],
            ),
          ),
          // Floating label - matches dialog background color exactly
          Positioned(
            top: -8,
            left: getProportionateScreenWidth(30),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: getProportionateScreenWidth(2)),
              color: Color.fromRGBO(230, 228, 228, 1),
              child: Text(
                "Mobile No.",
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w600,
                  fontSize: getProportionateScreenWidth(12),
                  color: Color(0xFF828282),
                ),
              ),
            ),
          ),
                  
                
              
            
          
        ],
      ),
    );
  }
}

/// Continue button with gradient
class _ContinueButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;

  const _ContinueButton({
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: Container(
        width: double.infinity,
        height: getProportionateScreenHeight(51),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kPrimaryPurple, kTertiaryPink],
            stops: [0.0312, 2.9414],
            transform: GradientRotation(93.81 * 3.14159265 / 180),
          ),
          borderRadius: BorderRadius.circular(getProportionateScreenWidth(14)),
        ),
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: getProportionateScreenWidth(24),
                  height: getProportionateScreenWidth(24),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Continue",
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w600,
                        fontSize: getProportionateScreenWidth(20),
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: getProportionateScreenWidth(4)),
                    Transform.flip(
                      flipX: true,
                      child: Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: getProportionateScreenWidth(24),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// OR divider for dialog
class _DialogOrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              color: Color(0xFF8D8D8D),
              borderRadius: BorderRadius.circular(getProportionateScreenWidth(71)),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: getProportionateScreenWidth(10)),
          child: Text(
            "OR",
            style: TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w500,
              fontSize: getProportionateScreenWidth(16),
              color: Color(0xFF8D8D8D),
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              color: Color(0xFF8D8D8D),
              borderRadius: BorderRadius.circular(getProportionateScreenWidth(71)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pick phone button
class _PickPhoneButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;
  final String simLabel;

  const _PickPhoneButton({
    required this.isLoading,
    required this.onPressed,
    required this.simLabel,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: Container(
        width: double.infinity,
        height: getProportionateScreenHeight(51),
        decoration: BoxDecoration(
          color: Color(0xFFF7E8FF).withOpacity(0.2),
          border: Border.all(
            color: kPrimaryPurple.withOpacity(0.8),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(getProportionateScreenWidth(14)),
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                simLabel,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w600,
                  fontSize: getProportionateScreenWidth(18),
                  color: Color(0xFF363538),
                ),
              ),
              SizedBox(width: getProportionateScreenWidth(4)),
              SvgPicture.asset(
                'assets/svg/phone_calling.svg',
                width: getProportionateScreenWidth(18),
                height: getProportionateScreenWidth(18),
                fit: BoxFit.contain,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Terms and privacy policy links
class _TermsAndPrivacy extends StatelessWidget {
  const _TermsAndPrivacy();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: getProportionateScreenWidth(20)),
      child: Column(
        children: [
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: getProportionateScreenWidth(14),
                fontWeight: FontWeight.w500,
                color: Colors.white,
                height: 1.36,
              ),
              children: [
                TextSpan(text: "By using app you agree our "),
                WidgetSpan(
                  child: GestureDetector(
                    onTap: () {
                      PersistentNavBarNavigator.pushNewScreen(
                        context,
                        screen: Terms(),
                        withNavBar: false,
                        pageTransitionAnimation: PageTransitionAnimation.cupertino,
                      );
                    },
                    child: Text(
                      "Terms & Conditions",
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: getProportionateScreenWidth(14),
                        color: Colors.yellow,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                TextSpan(text: " and "),
                WidgetSpan(
                  child: GestureDetector(
                    onTap: () {
                      PersistentNavBarNavigator.pushNewScreen(
                        context,
                        screen: PrivacyPolicy(),
                        withNavBar: false,
                        pageTransitionAnimation: PageTransitionAnimation.cupertino,
                      );
                    },
                    child: Text(
                      "Privacy Policy",
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: getProportionateScreenWidth(14),
                        color: Colors.yellow,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                TextSpan(text: "."),
              ],
            ),
          ),
        ],
      ),
    );
  }
}