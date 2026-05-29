import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:viora/Screens/PrivacyPolicy/terms.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/Services/account_deletion_flow.dart';
import 'package:viora/constants.dart';
import 'package:viora/size_config.dart';

class DeleteDialog {
  static Future<bool> show(BuildContext context, String deletionMethod) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha(100),
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(horizontal: 5),
              child: _DeleteDialogContent(deletionMethod),
            ),
          ),
        );
      },
    );
    return result ?? false;
  }
}

class _DeleteDialogContent extends HookWidget {
  const _DeleteDialogContent(this.deletionMethod);

  final String deletionMethod;

  @override
  Widget build(BuildContext context) {
    final isDeletingAccount = useState(false);
    final globals = Globals.of(context);

    return Container(
      width: 320.w,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: kBackgroundBG,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.r),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Background image
            Positioned(
              left: -170,
              top: -95,
              child: Image.asset(
                'assets/icon/viora_transparent.png',
                width: 370,
                height: 370,
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              right: -100,
              top: -145,
              child: Transform.scale(
                scaleX: -1,
                child: Image.asset(
                  'assets/icon/viora_transparent.png',
                  width: 310,
                  height: 310,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isDeletingAccount.value == true
                        ? 'Deleting Account...'
                        : 'Delete Account',
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.bold,
                      fontSize: 18.sp,
                      height: 1.35,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    isDeletingAccount.value == true
                        ? 'Please wait till the time Deletion\nis happening'
                        : 'Are you sure you want to delete\nthe account?',
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.bold,
                      fontSize: 14.sp,
                      height: 1.35,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    'This is an irreversible activity and the account profile cannot be reinstated once you confirm.',
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w300,
                      fontSize: 14.sp,
                      height: 1.35,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'For details, refer ',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w300,
                            fontSize: 14.sp,
                            height: 1.35,
                            color: Colors.black,
                          ),
                        ),
                        TextSpan(
                          text: 'Terms & Conditions',
                          style: const TextStyle(
                            color: Color(0xFF0000FF),
                            fontWeight: FontWeight.w500,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = isDeletingAccount.value
                                ? null
                                : () {
                                    PersistentNavBarNavigator.pushNewScreen(
                                      context,
                                      screen: Terms(),
                                      withNavBar: false,
                                      pageTransitionAnimation:
                                          PageTransitionAnimation.cupertino,
                                    );
                                  },
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12.h),
                  // Buttons
                  _buildButtons(
                    context,
                    isDeletingAccount,
                    globals,
                    deletionMethod,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButtons(
    BuildContext context,
    ValueNotifier<bool> isDeletingAccount,
    Globals globals,
    String deletionMethod,
  ) {
    return Row(
      children: [
        // Yes button (white background with border)
        Expanded(
          child: GestureDetector(
            onTap: isDeletingAccount.value
                ? null
                : () {
                    Navigator.of(context).pop(false);
                  },
            child: Container(
              height: 42.h,
              decoration: BoxDecoration(
                color: isDeletingAccount.value == true
                    ? Colors.grey
                    : Color(0xFFD9D9D9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w600,
                    fontSize: 18.sp,
                    color: isDeletingAccount.value == true
                        ? Colors.white
                        : Color(0xFF727272),
                  ),
                ),
              ),
            ),
          ),
        ),

        SizedBox(width: getProportionateScreenWidth(12)),
        Expanded(
          child: GestureDetector(
            onTap: isDeletingAccount.value == true
                ? null
                : () async {
                    if (isDeletingAccount.value) return;
                    isDeletingAccount.value = true;

                    await logDeletionConfirmation(
                      hasActiveSubscription: false,
                      activeProductIds: [],
                      deletionMethod: deletionMethod,
                    );

                    await executeAccountDeletion(
                      context,
                      isDeletingAccount,
                      globals,
                      false,
                    );
                  },
            child: Container(
              height: 42.h,
              decoration: BoxDecoration(
                color: isDeletingAccount.value == true ? Colors.grey : null,
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: isDeletingAccount.value
                      ? [
                          kPrimaryPurple.withAlpha(216),
                          Color(0xFF8B3A7B).withAlpha(216),
                          Color(0xFFA14281).withAlpha(216),
                          // kTertiaryPink,
                        ]
                      : [
                          kPrimaryPurple,
                          Color(0xFF8B3A7B),
                          Color(0xFFA14281),
                          // kTertiaryPink,
                        ],
                  stops: [0.0, 0.80, 0.94],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Text(
                      'Delete',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w600,
                        fontSize: 18.sp,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (isDeletingAccount.value == true)
                    const Center(
                      child: SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
