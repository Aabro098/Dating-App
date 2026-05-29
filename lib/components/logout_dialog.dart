import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:viora/Screens/Home/homeScreen.dart';
import 'package:viora/Screens/Login_Signup/loginScreen.dart';
import 'package:viora/Services/AuthService.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/Services/FCMServie.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/Services/PhoneAuthService.dart';
import 'package:viora/Services/session_service.dart';
import 'package:viora/Services/SubscriptionService.dart';
import 'package:viora/constants.dart';

class LogoutDialog {
  static Future<bool> show(BuildContext context) async {
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
              child: LogoutDialogContent(),
            ),
          ),
        );
      },
    );
    return result ?? false;
  }
}

class LogoutDialogContent extends HookWidget {
  const LogoutDialogContent({super.key});

  @override
  Widget build(BuildContext context) {
    final isLoggingOut = useState(false);
    final globals = Globals.of(context);

    return Container(
      width: 320.w,
      decoration: BoxDecoration(
        color: kBackgroundBG,
        borderRadius: BorderRadius.circular(12),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.r),
        child: Stack(
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
            // Content on top
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Logout',
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.bold,
                      fontSize: 20.sp,
                      height: 1.35,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    isLoggingOut.value == true
                        ? 'Please wait till Logout is happening'
                        : 'Are you sure you want to logout?',
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
                  _buildButtons(context, isLoggingOut, globals),
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
    ValueNotifier<bool> isLoggingOut,
    Globals globals,
  ) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: isLoggingOut.value
                ? null
                : () {
                    Navigator.of(context).pop(false);
                  },
            child: Container(
              height: 42.h,
              decoration: BoxDecoration(
                color: isLoggingOut.value == true
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
                    color: isLoggingOut.value == true
                        ? Colors.white
                        : Color(0xFF727272),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: GestureDetector(
            onTap: isLoggingOut.value == true
                ? null
                : () async {
                    if (isLoggingOut.value) return;
                    isLoggingOut.value = true;

                    final success = await LogoutFunction().signOutAndCleanup(
                      context,
                      globals,
                    );
                    if (!success) {
                      isLoggingOut.value = false;
                    }
                  },
            child: Container(
              height: 42.h,
              decoration: BoxDecoration(
                color: isLoggingOut.value == true ? Colors.grey : null,
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: isLoggingOut.value
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
                      'Logout',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w600,
                        fontSize: 18.sp,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (isLoggingOut.value == true)
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

class LogoutFunction {
  Future<bool> signOutAndCleanup(BuildContext context, Globals globals) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;

      if (uid == null) {
        await SessionService.clearSavedSessionId();

        if (context.mounted) {
          Navigator.of(
            context,
            rootNavigator: true,
          ).pushNamedAndRemoveUntil(LoginScreen.routeName, (route) => false);
        }

        return true;
      }
      // Stop monitoring device limit changes
      await SessionService.stopMonitoringDeviceLimitChanges();
      await DatabaseService.handleOnlineStatue(false);
      await DatabaseService.deleteToken();
      await FCMService.resetOnLogout();
      await SubscriptionService.clearSubscriptionCacheOnLogout(uid: uid);

      // Must happen before Firebase signOut
      await SessionService.deleteCurrentSession();

      await GoogleAuth.logoutOnly();
      await PhoneAuth.logoutOnly();

      await FirebaseAuth.instance.signOut();

      await SessionService.clearSavedSessionId();

      globals.resetInitialization();
      resetVerificationDialogFlag();

      if (context.mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pushNamedAndRemoveUntil(LoginScreen.routeName, (route) => false);
      }
      currentNavigationIndex.value = 0;
      return true;
    } catch (e) {
      debugPrint('❌ Error during logout: $e');
      return false;
    }
  }
}
