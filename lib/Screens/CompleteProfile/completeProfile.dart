import 'package:country_pickers/country.dart';
import 'package:country_pickers/country_pickers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:viora/Services/AuthService.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/Services/PhoneAuthService.dart';
import 'package:viora/Services/exceptions/exceptions.dart';
import 'package:viora/constants.dart';
import 'package:viora/models/UserDetails.dart';

import '../../components/CustomDatePicker.dart';
import '../../components/CustomTextFormField.dart';
import '../../components/QuitAppDialog.dart';
import '../../components/QuitAppHandler.dart';
import '../../size_config.dart';
import '../../Services/PermissionManager.dart';

// Helper for conditional logging
void _log(String message) {
  if (kDebugMode) {
    debugPrint('[CompleteProfile] $message');
  }
}

class CompleteProfile extends HookWidget {
  static String routeName = "/completeProfile";

  const CompleteProfile({super.key});

  @override
  Widget build(BuildContext context) {
    // Determine login type - check if phone or email is available
    final isPhoneLogin = PhoneAuth.authenticatedPhone != null;
    final isGoogleLogin = GoogleAuth.authenticatedEmail != null;
    _log('Login Type - Phone: $isPhoneLogin, Google: $isGoogleLogin');

    // 1. Create a FocusNode for the phone field
    final phoneFocusNode = useFocusNode();

    // 2. Listen to the focus node so the widget rebuilds when focus changes
    // This is crucial for the InputDecorator to update its border state
    useListenable(phoneFocusNode);

    useEffect(() {
      FlutterNativeSplash.remove();
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      return null;
    }, []);

    // State management
    final gender = useState("Male");
    final formKey = useMemoized(() => GlobalKey<FormState>());

    // Country picker state
    final selectedCountry = useState<Country?>(
      isPhoneLogin && PhoneAuth.authenticatedCountryCode != null
          ? CountryPickerUtils.getCountryByPhoneCode(
              PhoneAuth.authenticatedCountryCode!.replaceAll('+', ''),
            )
          : CountryPickerUtils.getCountryByIsoCode('IN'),
    );

    // Form controllers
    final nameCtr = useTextEditingController();
    final emailCtr = useTextEditingController(
      text: isGoogleLogin ? GoogleAuth.authenticatedEmail : '',
    );
    final phoneCtr = useTextEditingController(
      text: isPhoneLogin ? PhoneAuth.authenticatedPhone : '',
    );
    final dobCtr = useTextEditingController();

    final selectedDate = useState<DateTime?>(null);
    final autoValidate = useState(AutovalidateMode.disabled);
    final isSubmitting = useState(false);

    // Request location
    Future<Map<String, dynamic>> requestLocationAndFetch() async {
      try {
        if (PermissionSessionManager.isLocationRequestedInCompleteProfile()) {
          _log('Location permission already requested this session, skipping');
          return {};
        }

        if (PermissionSessionManager.isLocationDeniedThisSession()) {
          _log('Location already denied this session, skipping');
          return {};
        }

        PermissionSessionManager.markLocationRequestedInCompleteProfile();

        final serviceEnabled = await Geolocator.isLocationServiceEnabled();

        if (!serviceEnabled) {
          _log('Location services are disabled');
          return {};
        }

        var status = await Permission.location.status;

        if (!status.isGranted) {
          _log('Location permission not granted, requesting...');
          await Future.delayed(const Duration(milliseconds: 800));

          try {
            status = await PermissionManager().requestPermission(
              Permission.location,
              delay: const Duration(milliseconds: 500),
            );
          } catch (e) {
            _log(
              'Permission request threw error (possibly telephony plugin conflict): $e',
            );

            // WORKAROUND: Re-check actual permission status after telephony plugin conflict
            // The another_telephony plugin intercepts ALL permission results, not just SMS
            // This causes "Reply already submitted" exception but permission may still be granted
            await Future.delayed(const Duration(milliseconds: 200));
            status = await Permission.location.status;
          }

          // Check final status after potential error recovery
          if (!status.isGranted) {
            _log('Location permission denied by user');
            PermissionSessionManager.markLocationDeniedThisSession();
            return {};
          }

          _log('Location permission granted - continuing...');
        }

        _log('Fetching current location...');
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        String city = '';
        String state = '';
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          state = place.administrativeArea ?? '';
          city = (place.subAdministrativeArea ?? '')
              .replaceAll("Division", "")
              .trim();
          if (city.isEmpty) {
            city = place.locality ?? '';
          }
        }

        _log('Location fetched: $city, $state');
        return {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'city': city,
          'state': state,
        };
      } catch (e, stackTrace) {
        _log('Location error: $e');
        final appException = ErrorHandler.convert(e, stackTrace);
        _log('Converted to: ${appException.runtimeType}');
        return {};
      }
    }

    Future<void> selectDate() async {
      final DateTime? picked = await CustomDatePicker.show(
        context,
        initialDate:
            selectedDate.value ??
            DateTime.now().subtract(const Duration(days: 6570)),
        firstDate: DateTime(1950),
        lastDate: DateTime.now().subtract(const Duration(days: 6570)),
      );

      if (picked != null) {
        selectedDate.value = picked;
        dobCtr.text = DateFormat('dd-MM-yyyy').format(picked);
      }
    }

    Future<void> handleSubmit() async {
      if (!formKey.currentState!.validate()) {
        autoValidate.value = AutovalidateMode.onUserInteraction;
        return;
      }

      // if (isGoogleLogin && phoneCtr.text.trim().isEmpty) {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     const SnackBar(
      //       content: Text('Please enter a phone number'),
      //       backgroundColor: Colors.red,
      //     ),
      //   );
      //   return;
      // }

      if (selectedDate.value == null) {
        autoValidate.value = AutovalidateMode.onUserInteraction;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select your date of birth'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      isSubmitting.value = true;

      try {
        _log('Fetching location data for profile...');
        final locData = await requestLocationAndFetch();

        final now = DateTime.now();
        int age = now.year - selectedDate.value!.year;
        if (now.month < selectedDate.value!.month ||
            (now.month == selectedDate.value!.month &&
                now.day < selectedDate.value!.day)) {
          age--;
        }

        if (age < 18) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You must be at least 18 years old'),
                backgroundColor: Colors.red,
              ),
            );
          }
          isSubmitting.value = false;
          return;
        }

        String? phoneNumber;
        if (isPhoneLogin) {
          phoneNumber =
              '+${selectedCountry.value?.phoneCode ?? '91'}${PhoneAuth.authenticatedPhone}';
        } else if (phoneCtr.text.trim().isNotEmpty) {
          phoneNumber =
              '+${selectedCountry.value?.phoneCode ?? '91'}${phoneCtr.text.trim()}';
        }

        String? email;
        if (isGoogleLogin) {
          email = GoogleAuth.authenticatedEmail;
        } else {
          email = emailCtr.text.trim();
        }

        final user = UserDetails(
          isDisabled: false,
          isTyping: '',
          gender: gender.value,
          name: nameCtr.text.trim(),
          email: email,
          phone: phoneNumber,
          joiningDate: DateTime.now(),
          dateOfBirth: selectedDate.value,
          age: age,
          city: locData['city'] ?? '',
          state: locData['state'] ?? '',
          latitude: locData['latitude'],
          longitude: locData['longitude'],
          isVerified: false,
        );

        if (!context.mounted) return;
        await DatabaseService.addUser(user, context);

        // Reset authentication variables after successful profile creation
        PhoneAuth.clearAuthenticatedPhone();
        GoogleAuth.clearAuthenticatedEmail();
      } catch (e, stackTrace) {
        _log('Profile creation error: $e');
        final appException = ErrorHandler.convert(e, stackTrace);
        isSubmitting.value = false;
        if (context.mounted) {
          ErrorHandler.showError(context, appException.userMessage);
        }
      }
    }

    return QuitAppHandler(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            _buildBackground(),
            SafeArea(
              child: Column(
                children: [
                  _buildCloseButton(context),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          SizedBox(height: getProportionateScreenHeight(240)),
                          _buildProfileCard(
                            context: context,
                            formKey: formKey,
                            gender: gender,
                            autoValidate: autoValidate.value,
                            nameCtr: nameCtr,
                            emailCtr: emailCtr,
                            phoneCtr: phoneCtr,
                            dobCtr: dobCtr,
                            selectedDate: selectedDate.value,
                            selectDate: selectDate,
                            onSubmit: handleSubmit,
                            isSubmitting: isSubmitting.value,
                            isPhoneLogin: isPhoneLogin,
                            isGoogleLogin: isGoogleLogin,
                            selectedCountry: selectedCountry,
                            // Pass the focus node down
                            phoneFocusNode: phoneFocusNode,
                          ),
                          // Extra padding for scrolling
                          SizedBox(height: getProportionateScreenHeight(30)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isSubmitting.value)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child: CircularProgressIndicator(color: kPrimaryPurple),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/backgrounds/complete_profile.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                Container(color: Colors.white),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.16, 0.37, 0.49, 0.73],
                colors: [
                  Color(0x00FFFFFF),
                  Color(0x003E1E68),
                  Color(0x333E1E68),
                  Color(0x803E1E68),
                  kPrimaryPurple,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: -90,
          top: 296,
          child: Container(
            width: 290,
            height: 284,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: kTertiaryPink.withOpacity(0.16),
                width: 2,
              ),
            ),
          ),
        ),
        Positioned(
          right: -46,
          top: 338,
          child: Container(
            width: 203,
            height: 199,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kTertiaryPink.withOpacity(0.15),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCloseButton(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 24, top: 24),
        child: GestureDetector(
          onTap: () => QuitAppDialog.show(context),
          child: Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: kSecondaryPurple,
              borderRadius: BorderRadius.circular(17.5),
            ),
            child: const Icon(Icons.close, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard({
    required BuildContext context,
    required GlobalKey<FormState> formKey,
    required ValueNotifier<String> gender,
    required TextEditingController nameCtr,
    required AutovalidateMode autoValidate,
    required TextEditingController emailCtr,
    required TextEditingController phoneCtr,
    required TextEditingController dobCtr,
    required DateTime? selectedDate,
    required VoidCallback selectDate,
    required VoidCallback onSubmit,
    required bool isSubmitting,
    required bool isPhoneLogin,
    required bool isGoogleLogin,
    required ValueNotifier<Country?> selectedCountry,
    required FocusNode phoneFocusNode, // Accept the FocusNode
  }) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: getProportionateScreenWidth(14)),
      padding: EdgeInsets.all(getProportionateScreenWidth(21)),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Form(
        key: formKey,
        autovalidateMode: autoValidate,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Complete Profile',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),

            _buildGenderSelection(gender),
            const SizedBox(height: 12),

            _buildNameField(nameCtr),
            const SizedBox(height: 12),

            _buildDOBField(dobCtr, selectDate, selectedDate),
            const SizedBox(height: 12),

            if (isGoogleLogin) ...[
              // Pass the focus node to the editable field
              _buildPhoneField(
                context,
                phoneCtr,
                selectedCountry,
                phoneFocusNode,
              ),
              const SizedBox(height: 12),
            ],

            if (isPhoneLogin) ...[
              _buildEmailField(emailCtr),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 8),
            _buildSubmitButton(onSubmit, isSubmitting),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderSelection(ValueNotifier<String> gender) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => gender.value = "Male",
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: gender.value == "Male"
                    ? kQuaternaryPink.withOpacity(0.8)
                    : Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text(
                  'I am a Man',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: GestureDetector(
            onTap: () => gender.value = "Female",
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: gender.value == "Female"
                    ? kQuaternaryPink.withOpacity(0.8)
                    : Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text(
                  'I am a Woman',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNameField(TextEditingController controller) {
    return CustomTextFormField(
      controller: controller,
      label: 'Enter your name',
      hint: 'Your name',
      icon: Icons.edit_outlined,
      validator: (value) {
        if (value == null || value.trim().isEmpty) return 'Name is required';
        if (value.trim().length < 3) {
          return 'Name must be at least 3 characters';
        }
        if (value.trim().length > 20) {
          return 'Name must be less than 20 characters';
        }
        if (!RegExp(
              r'^(?=.{1,}$)[A-Za-z][A-Za-z0-9 ]*$',
            ).hasMatch(value.trim()) ||
            RegExp(r'\d').allMatches(value.trim()).length > 3) {
          return 'Starts with a letter. Max 3 numbers. No special characters.';
        }
        return null;
      },
    );
  }

  Widget _buildDOBField(
    TextEditingController controller,
    VoidCallback onTap,
    DateTime? selectedDate,
  ) {
    return CustomTextFormField(
      controller: controller,
      label: 'Date of Birth',
      hint: 'DD-MM-YYYY',
      icon: Icons.calendar_today,
      readOnly: true,
      onTap: onTap,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Date of birth is required';
        }
        if (selectedDate != null) {
          final now = DateTime.now();
          int age = now.year - selectedDate.year;
          if (now.month < selectedDate.month ||
              (now.month == selectedDate.month && now.day < selectedDate.day)) {
            age--;
          }
          if (age < 18) return 'You must be at least 18 years old';
        }
        return null;
      },
    );
  }

  Widget _buildEmailField(
    TextEditingController controller, {
    bool readOnly = false,
    bool showOptional = true,
  }) {
    return CustomTextFormField(
      controller: controller,
      label: showOptional ? 'Email' : 'Email',
      hint: 'abc@gmail.com',
      icon: Icons.mail_outline,
      readOnly: readOnly,
      keyboardType: TextInputType.emailAddress,
      validator: (value) {
        if (value == null || value.trim().isEmpty) return null;
        final emailRegex = RegExp(r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+');
        if (!emailRegex.hasMatch(value)) return 'Please enter a valid email';
        return null;
      },
    );
  }

  /// Flag display field (Read-only) using InputDecorator for consistent label style

  /// Phone input field using InputDecorator combined with FocusNode
  /// This ensures the border thickens when the inner TextField is tapped.
  Widget _buildPhoneField(
    BuildContext context,
    TextEditingController controller,
    ValueNotifier<Country?> selectedCountry,
    FocusNode focusNode, // <--- FocusNode passed here
  ) {
    return InputDecorator(
      // This property tells the Decorator to draw the 'focusedBorder'
      isFocused: focusNode.hasFocus,
      decoration: InputDecoration(
        labelText: 'Mobile No.',
        labelStyle: TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w600,
          fontSize: getProportionateScreenWidth(16),
          color: const Color(0xFFE2E2E2),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: EdgeInsets.symmetric(
          horizontal: getProportionateScreenWidth(14),
          vertical: getProportionateScreenHeight(18),
        ),
        // Normal state: white border, width 1
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white, width: 1),
        ),
        // Focused state: white border, width 3
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white, width: 2),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white, width: 1),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _openCountryPicker(context, selectedCountry),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selectedCountry.value != null)
                  SizedBox(
                    width: getProportionateScreenWidth(28),
                    height: getProportionateScreenHeight(20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CountryPickerUtils.getDefaultFlagImage(
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
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w500,
                    fontSize: getProportionateScreenWidth(12),
                    color: Colors.white,
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
            color: Colors.white.withOpacity(0.5),
          ),
          SizedBox(width: getProportionateScreenWidth(10)),
          Expanded(
            child: TextField(
              focusNode: focusNode, // <--- Bind focus node to text field
              controller: controller,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Colors.white,
              ),
              // Decoration removed here because InputDecorator handles the border
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
                counterText: '',
                hintText: "9999999999",
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Nunito',
                ),
              ),
            ),
          ),
          Icon(
            Icons.phone_outlined,
            color: kPrimaryPurple,
            size: getProportionateScreenWidth(20),
          ),
        ],
      ),
    );
  }

  void _openCountryPicker(
    BuildContext context,
    ValueNotifier<Country?> selectedCountry,
  ) {
    showDialog(
      context: context,
      builder: (_) => Theme(
        data: Theme.of(context).copyWith(
          dialogBackgroundColor: const Color.fromRGBO(230, 228, 228, 1),
        ),
        child: CountryPickerDialog(
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
          onValuePicked: (Country country) => selectedCountry.value = country,
          itemBuilder: (Country country) => Container(
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
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton(VoidCallback onSubmit, bool isSubmitting) {
    return GestureDetector(
      onTap: isSubmitting ? null : onSubmit,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [kPrimaryPurple, kTertiaryPink],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: const Text(
            'Save Profile',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w600,
              fontSize: 20,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
