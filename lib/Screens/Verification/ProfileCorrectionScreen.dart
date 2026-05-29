import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_pickers/country.dart';
import 'package:country_pickers/country_pickers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:intl/intl.dart';
import 'package:viora/Screens/Verification/LivenessVerificationScreen.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/Services/exceptions/exceptions.dart';
import 'package:viora/constants.dart';

import '../../components/CustomDatePicker.dart';
import '../../components/CustomTextFormField.dart';
import '../../size_config.dart';

// Helper for conditional logging
void _log(String message) {
  if (kDebugMode) {
    debugPrint('[ProfileCorrection] $message');
  }
}

class ProfileCorrectionScreen extends HookWidget {
  static String routeName = "/profileCorrection";

  const ProfileCorrectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final globals = Globals.of(context);
    final userDetails = globals.prefs.userDetails.value;

    // 1. Create and listen to FocusNode for phone field
    final phoneFocusNode = useFocusNode();
    useListenable(phoneFocusNode);

    // Get detected gender from navigation arguments (if provided)
    final detectedGender =
        ModalRoute.of(context)?.settings.arguments as String?;

    // State management
    final autoValidate = useState(AutovalidateMode.disabled);

    final gender = useState(userDetails?.gender ?? "Male");
    final formKey = useMemoized(() => GlobalKey<FormState>());

    // Parse phone number if it exists
    String? phoneNumberOnly;
    Country? initialCountry;
    
    if (userDetails?.phone != null && userDetails!.phone!.isNotEmpty) {
      final phone = userDetails.phone!;
      _log('Parsing phone: $phone');
      
      if (phone.startsWith('+')) {
        // Try to match phone format: +<code><number>
        // Try common country codes first (1-3 digits)
        for (int codeLength = 3; codeLength >= 1; codeLength--) {
          if (phone.length > codeLength + 1) {
            final potentialCode = phone.substring(1, codeLength + 1);
            try {
              final country = CountryPickerUtils.getCountryByPhoneCode(potentialCode);
              // Verify this is a valid country
              if (country.phoneCode == potentialCode) {
                initialCountry = country;
                phoneNumberOnly = phone.substring(codeLength + 1);
                _log('Found country: ${country.name} (+${country.phoneCode})');
                _log('Phone number: $phoneNumberOnly');
                break;
              }
            } catch (e) {
              // Not a valid country code, try shorter code
              continue;
            }
          }
        }
      }
      
      // If parsing failed, use the whole number and default country
      if (initialCountry == null) {
        _log('Could not parse country code, using default');
        phoneNumberOnly = phone.replaceAll('+', '').replaceAll(' ', '');
        initialCountry = CountryPickerUtils.getCountryByIsoCode('IN');
      }
    } else {
      // No phone number, use default country
      initialCountry = CountryPickerUtils.getCountryByIsoCode('IN');
    }
    
    // Form controllers - initialize with user data
    final nameCtr = useTextEditingController(text: userDetails?.name ?? '');
    final emailCtr = useTextEditingController(text: userDetails?.email ?? '');
    final phoneCtr = useTextEditingController(text: phoneNumberOnly ?? '');
    final dobCtr = useTextEditingController(
      text: userDetails?.dateOfBirth != null
          ? DateFormat('dd-MM-yyyy').format(userDetails!.dateOfBirth!)
          : '',
    );
    
    // Country picker state
    final selectedCountry = useState<Country?>(initialCountry);

    final selectedDate = useState<DateTime?>(userDetails?.dateOfBirth);
    final isSubmitting = useState(false);

    // Date picker
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

    // Form submission
    Future<void> handleSubmit() async {
      FocusScope.of(context).requestFocus(FocusNode());

      if (!formKey.currentState!.validate()) {
        autoValidate.value = AutovalidateMode.onUserInteraction;
        return;
      }

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
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null || userDetails == null) {
          throw Exception('User not authenticated');
        }

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

        final genderChanged = gender.value != userDetails.gender;

        final updates = <String, dynamic>{
          'gender': gender.value,
          'name': nameCtr.text.trim(),
          'email': emailCtr.text.trim(),
          'dateOfBirth': Timestamp.fromDate(selectedDate.value!),
          'age': age,
        };
        
        if (phoneCtr.text.trim().isNotEmpty) {
          updates['phone'] = '+${selectedCountry.value?.phoneCode ?? '91'}${phoneCtr.text.trim()}';
        }

        if (genderChanged) {
          updates['verificationRetries'] = 0;
        }

        await FirebaseFirestore.instance
            .collection('Users')
            .doc(uid)
            .update(updates);

        userDetails.gender = gender.value;
        userDetails.name = nameCtr.text.trim();
        userDetails.email = emailCtr.text.trim();
        if (phoneCtr.text.trim().isNotEmpty) {
          userDetails.phone = '+${selectedCountry.value?.phoneCode ?? '91'}${phoneCtr.text.trim()}';
        }
        userDetails.dateOfBirth = selectedDate.value;
        userDetails.age = age;
        if (genderChanged) {
          userDetails.verificationRetries = 0;
        }
        await globals.prefs.userDetails.set(userDetails);

        isSubmitting.value = false;

        if (!context.mounted) return;

        Navigator.of(context).pushReplacementNamed(LivenessVerificationScreen.routeName);
      } catch (e, stackTrace) {
        _log('Profile update error: $e');
        final appException = ErrorHandler.convert(e, stackTrace);
        isSubmitting.value = false;
        if (context.mounted) {
          ErrorHandler.showError(context, appException.userMessage);
        }
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildBackButton(context),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(height: getProportionateScreenHeight(240)),
                        if (detectedGender != null)
                          _buildInfoMessage(detectedGender),

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
                          selectedCountry: selectedCountry,
                          // 2. Pass the focus node
                          phoneFocusNode: phoneFocusNode,
                        ),
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

  Widget _buildBackButton(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 24, top: 24),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: kSecondaryPurple,
              borderRadius: BorderRadius.circular(17.5),
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoMessage(String detectedGender) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: getProportionateScreenWidth(14),
        vertical: getProportionateScreenHeight(12),
      ),
      padding: EdgeInsets.all(getProportionateScreenWidth(16)),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.15),
        border: Border.all(color: Colors.orange.withOpacity(0.3), width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.orange, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'We detected a "$detectedGender" face. Please update your profile if needed.',
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.white,
                height: 1.4,
              ),
            ),
          ),
        ],
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
    required ValueNotifier<Country?> selectedCountry,
    required FocusNode phoneFocusNode, // 3. Receive FocusNode
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
              'Update Profile',
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

            // 4. Pass FocusNode to field
            _buildPhoneField(context, phoneCtr, selectedCountry, phoneFocusNode),
            const SizedBox(height: 12),

            _buildEmailField(emailCtr),
            const SizedBox(height: 20),

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
        if (value.trim().length < 3) return 'Name must be at least 3 characters';
        if (value.trim().length > 20) return 'Name must be less than 20 characters';
        if (!RegExp(r'^[a-zA-Z ]+$').hasMatch(value.trim())) return 'Name can only contain letters';
        return null;
      },
    );
  }

  Widget _buildDOBField(TextEditingController controller, VoidCallback onTap, DateTime? selectedDate) {
    return CustomTextFormField(
      controller: controller,
      label: 'Date of Birth',
      hint: 'DD-MM-YYYY',
      icon: Icons.calendar_today,
      readOnly: true,
      onTap: onTap,
      validator: (value) {
        if (value == null || value.trim().isEmpty) return 'Date of birth is required';
        if (selectedDate != null) {
          final now = DateTime.now();
          int age = now.year - selectedDate.year;
          if (now.month < selectedDate.month || (now.month == selectedDate.month && now.day < selectedDate.day)) age--;
          if (age < 18) return 'You must be at least 18 years old';
        }
        return null;
      },
    );
  }

  Widget _buildEmailField(TextEditingController controller) {
    return CustomTextFormField(
      controller: controller,
      label: 'Email',
      hint: 'abc@gmail.com',
      icon: Icons.mail_outline,
      keyboardType: TextInputType.emailAddress,
      validator: (value) {
        if (value == null || value.trim().isEmpty) return null;
        final emailRegex = RegExp(r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+');
        if (!emailRegex.hasMatch(value)) return 'Please enter a valid email';
        return null;
      },
    );
  }

  /// Phone input field with country code picker
  /// Updated to use InputDecorator + FocusNode for correct label/border behavior
  Widget _buildPhoneField(
    BuildContext context,
    TextEditingController controller,
    ValueNotifier<Country?> selectedCountry,
    FocusNode focusNode, // 5. Use FocusNode
  ) {
    return InputDecorator(
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
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white, width: 3),
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
                      child: CountryPickerUtils.getDefaultFlagImage(selectedCountry.value!),
                    ),
                  )
                else
                  Container(
                    width: getProportionateScreenWidth(28),
                    height: getProportionateScreenHeight(20),
                    decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                    child: Center(child: Text("🇮🇳", style: TextStyle(fontSize: getProportionateScreenWidth(14)))),
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
                // Changed to white to be visible on purple background
                Icon(Icons.keyboard_arrow_down_rounded, size: getProportionateScreenWidth(18), color: Colors.white),
              ],
            ),
          ),
          SizedBox(width: getProportionateScreenWidth(8)),
          Container(width: 1, height: getProportionateScreenHeight(24), color: Colors.white.withOpacity(0.5)),
          SizedBox(width: getProportionateScreenWidth(10)),
          Expanded(
            child: TextField(
              focusNode: focusNode, // 6. Bind to TextField
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
          // Changed to white opacity to be visible on purple background
          Icon(Icons.phone_outlined, color: Colors.white.withOpacity(0.7), size: getProportionateScreenWidth(20)),
        ],
      ),
    );
  }

  void _openCountryPicker(BuildContext context, ValueNotifier<Country?> selectedCountry) {
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
            selectedCountry.value = country;
          },
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
                  'Save & Continue',
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