import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:viora/constants.dart';
import 'package:viora/size_config.dart';
import 'package:viora/Services/AppConfigService.dart';

class SafetyTipsDialog {
  static const String paymentIssueTitle = 'Payment issue';
  static const String paymentIssueMessage =
      'We couldn\'t process your last payment. Please update your payment method in Google Play to keep Premium access.';

  /// Same chrome as [show], for subscription billing / Google Play payment issues.
  static Future<void> showPaymentIssue(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: _PaymentIssueDialogContent(),
            ),
          ),
        );
      },
    );
  }

  /// Show safety tips dialog
  /// [isNewUser] - true for first launch users, false for existing users
  static Future<void> show(BuildContext context, {bool isNewUser = true}) async {
    await showDialog(
      context: context,
      barrierDismissible: false, // Non-closable when touching outside
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return PopScope(
          canPop: false, // Prevent back button from closing
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: _SafetyTipsDialogContent(isNewUser: isNewUser),
            ),
          ),
        );
      },
    );
  }
}

class _PaymentIssueDialogContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    const lines = [SafetyTipsDialog.paymentIssueMessage];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: screenWidth * 0.9,
          constraints: BoxConstraints(
            maxWidth: 346,
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          decoration: BoxDecoration(
            color: kBackgroundBG,
            border: Border.all(color: Color(0xFFAFAFAF), width: 1.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              Positioned(
                left: -192,
                top: -89,
                child: Image.asset(
                  'assets/icon/viora_transparent.png',
                  width: 400,
                  height: 400,
                  fit: BoxFit.contain,
                ),
              ),
              Positioned(
                right: -88,
                top: -149,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
                  child: Image.asset(
                    'assets/icon/viora_transparent.png',
                    width: 310,
                    height: 310,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      SafetyTipsDialog.paymentIssueTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                        height: 30 / 22,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 31),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ...List.generate(
                              lines.length,
                              (index) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${index + 1}. ',
                                      style: const TextStyle(
                                        fontFamily: 'Nunito',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        height: 19 / 14,
                                        color: Colors.black,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        lines[index],
                                        style: const TextStyle(
                                          fontFamily: 'Nunito',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          height: 19 / 14,
                                          color: Colors.black,
                                        ),
                                        overflow: TextOverflow.visible,
                                        softWrap: true,
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
                    const SizedBox(height: 18),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        height: getProportionateScreenHeight(60),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment(0.0312, 0),
                            end: Alignment(0.9414, 0),
                            colors: [kPrimaryPurple, kTertiaryPink],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'OK',
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 20,
                                  height: 27 / 20,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Icon(
                                Icons.keyboard_double_arrow_right,
                                color: Colors.white,
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SafetyTipsDialogContent extends StatelessWidget {
  final bool isNewUser;
  
  const _SafetyTipsDialogContent({required this.isNewUser});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Get configurable title and tips
    final title = AppConfigService.getSafetyTitle(isNewUser: isNewUser);
    final safetyTips = AppConfigService.getSafetyTips(isNewUser: isNewUser);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Main dialog container with background
        Container(
          width: screenWidth * 0.9,
          constraints: BoxConstraints(
            maxWidth: 346,
            maxHeight: MediaQuery.of(context).size.height * 0.75, // Limit height
          ),
          decoration: BoxDecoration(
            color: kBackgroundBG,
            border: Border.all(color: Color(0xFFAFAFAF), width: 1.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              // Background image - Left side
              Positioned(
                left: -192,
                top: -89,
                child: Image.asset(
                  'assets/icon/viora_transparent.png',
                  width: 400,
                  height: 400,
                  fit: BoxFit.contain,
                ),
              ),

              // Background image - Right side (flipped)
              Positioned(
                right: -88,
                top: -149,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..scale(-1.0, 1.0, 1.0), // Flip horizontally
                  child: Image.asset(
                    'assets/icon/viora_transparent.png',
                    width: 310,
                    height: 310,
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Configurable Title
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                        height: 30 / 22,
                        color: Colors.black,
                      ),
                    ),

                    const SizedBox(height: 31),

                    // Scrollable safety tips list (handles many items)
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ...List.generate(
                              safetyTips.length,
                              (index) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${index + 1}. ',
                                      style: const TextStyle(
                                        fontFamily: 'Nunito',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        height: 19 / 14,
                                        color: Colors.black,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        safetyTips[index],
                                        style: const TextStyle(
                                          fontFamily: 'Nunito',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          height: 19 / 14,
                                          color: Colors.black,
                                        ),
                                        // Handle long text with ellipsis if needed
                                        overflow: TextOverflow.visible,
                                        softWrap: true,
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

                    const SizedBox(height: 18),

                    // Accept button
                    _buildAcceptButton(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAcceptButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
      },
      child: Container(
        height: getProportionateScreenHeight(60),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment(0.0312, 0), // 93.81 degrees converted
            end: Alignment(0.9414, 0),
            colors: [kPrimaryPurple, kTertiaryPink],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'OK',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                  height: 27 / 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 5),
              // Double arrow icon
              Icon(
                Icons.keyboard_double_arrow_right,
                color: Colors.white,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
