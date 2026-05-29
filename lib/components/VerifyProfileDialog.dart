import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:viora/constants.dart';
import 'package:viora/Services/AppConfigService.dart';
import '../size_config.dart';

class VerifyProfileDialog extends HookWidget {
  final VoidCallback onStartVerification;
  final VoidCallback onSkip;
  final String? userGender;

  const VerifyProfileDialog({
    super.key,
    required this.onStartVerification,
    required this.onSkip,
    this.userGender,
  });

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onStartVerification,
    required VoidCallback onSkip,
    String? userGender,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.25),
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(
              horizontal: getProportionateScreenWidth(10),
              vertical: getProportionateScreenHeight(50),
            ),
            child: VerifyProfileDialog(
              onStartVerification: onStartVerification,
              onSkip: onSkip,
              userGender: userGender,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to benefits changes from AppConfigService
    final benefitsSnapshot = useState<List<String>>([]);
    final isLoading = useState(true);
    useEffect(() {
      // Load initial benefits
      // final benefits = AppConfigService.getVerificationBenefits(userGender);
      // benefitsSnapshot.value = benefits;
      // isLoading.value = false;
      final benefits = AppConfigService.getVerificationBenefits(userGender);

      if (context.mounted) {
        benefitsSnapshot.value = benefits;
        isLoading.value = false;
      }
      debugPrint(
        '🎯 [VERIFY_DIALOG] Loaded benefits for ${userGender ?? "unknown"} gender: ${benefits.length} items',
      );
      debugPrint(
        '📋 [VERIFY_DIALOG] Reward: ${AppConfigService.getRewardValue(userGender)} ${AppConfigService.getRewardType(userGender)}',
      );

      // Listen to gender-specific rewards config changes in real-time
      final isMale = userGender?.toLowerCase() == 'male';
      final rewardsStream = isMale
          ? AppConfigService.maleRewardsConfigStream
          : AppConfigService.femaleRewardsConfigStream;

      final subscription = rewardsStream.listen((data) async {
        if (data != null) {
          await AppConfigService.reloadConfig();

          if (!context.mounted) return;

          final updatedBenefits = AppConfigService.getVerificationBenefits(
            userGender,
          );

          benefitsSnapshot.value = updatedBenefits;
          if (kDebugMode) {
            debugPrint(
              '[VERIFY_DIALOG] Benefits refreshed. New reward: ${AppConfigService.getRewardValue(userGender)} ${AppConfigService.getRewardType(userGender)}',
            );
            debugPrint(
              '[VERIFY_DIALOG] Updated benefits: ${updatedBenefits.join(", ")}',
            );
          }
        }
      });

      return () => subscription.cancel();
    }, [userGender]);

    if (isLoading.value) {
      return Container(
        decoration: BoxDecoration(
          color: kBackgroundBG,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: EdgeInsets.all(getProportionateScreenWidth(40)),
        child: const Center(
          child: CircularProgressIndicator(color: kTertiaryPink),
        ),
      );
    }

    return _buildDialog(context, benefitsSnapshot.value);
  }

  Widget _buildDialog(BuildContext context, List<String> benefits) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.80,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF9F9).withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFAFAFAF), width: 1.6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with purple background
            _buildHeader(),

            // White content area with scroll
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Column(
                  children: [
                    SizedBox(height: getProportionateScreenHeight(14)),
                    // Benefits of Verification section
                    _buildBenefitsSection(benefits),

                    //  SizedBox(height: getProportionateScreenHeight(4)),

                    // How It Works section
                    _buildHowItWorksSection(),

                    SizedBox(height: getProportionateScreenHeight(8)),

                    // Buttons
                    _buildButtons(context),

                    SizedBox(height: getProportionateScreenHeight(4)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: kPrimaryPurple,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Left decorative viora logo (rotated)
          Positioned(
            left: -130,
            top: -55,
            child: Image.asset(
              'assets/icon/viora_transparent.png',
              width: 300,
              height: 300,
              fit: BoxFit.contain,
            ),
          ),
          // Right decorative viora logo (rotated opposite direction)
          Positioned(
            right: -60,
            top: -122,
            child: Transform.scale(
              scaleX: -1,
              child: Image.asset(
                'assets/icon/viora_transparent.png',
                width: 250,
                height: 250,
                fit: BoxFit.contain,
              ),
            ),
          ),
          // Header content
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: getProportionateScreenWidth(20),
              vertical: getProportionateScreenHeight(18),
            ),
            child: Column(
              children: [
                // Shield icon
                Center(
                  child: Container(
                    width: getProportionateScreenWidth(40),
                    height: getProportionateScreenHeight(40),
                    decoration: const BoxDecoration(color: Colors.transparent),
                    child: SvgPicture.asset(
                      'assets/svg/verify_profile.svg',
                      width: getProportionateScreenWidth(40),
                      height: getProportionateScreenHeight(40),
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                      placeholderBuilder: (context) => Icon(
                        Icons.verified_user_outlined,
                        color: Colors.white,
                        size: getProportionateScreenWidth(40),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: getProportionateScreenHeight(8)),
                // Title
                Text(
                  'Verify Your Profile',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w700,
                    fontSize: getProportionateScreenWidth(22),
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: getProportionateScreenHeight(4)),
                // Subtitle
                Text(
                  'Get verified in seconds with AI',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w600,
                    fontSize: getProportionateScreenWidth(14),
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitsSection(List<String> benefits) {
    // If no benefits configured, don't show the section
    if (benefits.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: getProportionateScreenWidth(17),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              SvgPicture.asset(
                'assets/svg/benefits_star.svg',
                width: getProportionateScreenWidth(24),
                height: getProportionateScreenHeight(24),
                colorFilter: const ColorFilter.mode(
                  kTertiaryPink,
                  BlendMode.srcIn,
                ),
                placeholderBuilder: (context) => Icon(
                  Icons.auto_awesome,
                  color: kTertiaryPink,
                  size: getProportionateScreenWidth(24),
                ),
              ),
              SizedBox(width: getProportionateScreenWidth(12)),
              Text(
                'Benefits of Verification',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w700,
                  fontSize: getProportionateScreenWidth(15),
                  color: Colors.black,
                ),
              ),
            ],
          ),
          SizedBox(height: getProportionateScreenHeight(12)),
          // Benefits list - dynamically generated from config
          ...benefits.map((benefit) => _buildBenefitItem(benefit)).toList(),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: getProportionateScreenHeight(6)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '✓ ',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w600,
              fontSize: getProportionateScreenWidth(14),
              color: Colors.black,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w300,
                fontSize: getProportionateScreenWidth(14),
                height: 1.35,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksSection() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: getProportionateScreenWidth(22),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: kLightPurple,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: EdgeInsets.all(getProportionateScreenWidth(8)),
              child: Row(
                children: [
                  SvgPicture.asset(
                    'assets/svg/camera_verification.svg',
                    width: getProportionateScreenWidth(24),
                    height: getProportionateScreenHeight(24),
                    colorFilter: ColorFilter.mode(
                      kTertiaryPink,
                      BlendMode.srcIn,
                    ),
                    placeholderBuilder: (context) => Icon(
                      Icons.camera_alt_outlined,
                      color: kTertiaryPink,
                      size: getProportionateScreenWidth(24),
                    ),
                  ),
                  SizedBox(width: getProportionateScreenWidth(12)),
                  Text(
                    'How It Works',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w700,
                      fontSize: getProportionateScreenWidth(15),
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
            // Steps
            Padding(
              padding: EdgeInsets.fromLTRB(
                getProportionateScreenWidth(16),
                0,
                getProportionateScreenWidth(16),
                getProportionateScreenHeight(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStep(
                    '1. Take a live selfie (you\'ll be asked to blink)',
                  ),
                  _buildStep(
                    '2. AI verifies it\'s a real person and matches your gender',
                  ),
                  _buildStep('3. Get your verified badge and bonus coins!'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: getProportionateScreenHeight(6)),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w300,
          fontSize: getProportionateScreenWidth(14),
          height: 1.35,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _buildButtons(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: getProportionateScreenWidth(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Start Verification button
          GestureDetector(
            onTap: () {
              //   Navigator.of(context).pop();
              onStartVerification();
            },
            child: Container(
              width: getProportionateScreenWidth(200),
              padding: EdgeInsets.symmetric(
                vertical: getProportionateScreenHeight(12),
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [kPrimaryPurple, kTertiaryPink],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'assets/svg/camera_verification.svg',
                    width: getProportionateScreenWidth(20),
                    height: getProportionateScreenHeight(20),
                    colorFilter: const ColorFilter.mode(
                      kTertiaryPink,
                      BlendMode.srcIn,
                    ),
                    placeholderBuilder: (context) => Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.white,
                      size: getProportionateScreenWidth(20),
                    ),
                  ),
                  SizedBox(width: getProportionateScreenWidth(8)),
                  Text(
                    'Start Verification',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w600,
                      fontSize: getProportionateScreenWidth(16),
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: getProportionateScreenHeight(8)),
          // Skip for Now button
          GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
              onSkip();
            },
            child: Container(
              width: getProportionateScreenWidth(200),

              padding: EdgeInsets.symmetric(
                vertical: getProportionateScreenHeight(12),
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF7E8FF).withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kPrimaryPurple, width: 1.5),
              ),
              child: Center(
                child: Text(
                  'Skip for Now',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w600,
                    fontSize: getProportionateScreenWidth(16),
                    color: const Color(0xFF363538),
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
