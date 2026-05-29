import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/constants.dart';

class ReusableDialog {
  static Future<bool> show(
    BuildContext context,
    String title,
    String subtitle,
    String buttonName, {
    Future<void> Function()? onConfirm,
    Future<void> Function()? onCancel,
    bool showCancelButton = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha(100),
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: SafeArea(
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(horizontal: 5),
              child: _ReusableDialogContent(
                title: title,
                subtitle: subtitle,
                button: buttonName,
                onConfirm: onConfirm,
                onCancel: onCancel,
                showCancelButton: showCancelButton,
              ),
            ),
          ),
        );
      },
    );
    return result ?? false;
  }
}

class _ReusableDialogContent extends HookWidget {
  final String title;
  final String subtitle;
  final String button;
  final Future<void> Function()? onConfirm;
  final Future<void> Function()? onCancel;
  final bool showCancelButton;
  const _ReusableDialogContent({
    required this.title,
    required this.subtitle,
    required this.button,
    this.onConfirm,
    this.onCancel,
    this.showCancelButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final isPerformingOperation = useState(false);
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
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
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
                    subtitle,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w600,
                      fontSize: 14.sp,
                      height: 1.35,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  // Buttons
                  _buildButtons(
                    context,
                    isPerformingOperation,
                    globals,
                    button,
                    onConfirm,
                    onCancel,
                    showCancelButton,
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
    ValueNotifier<bool> isPerformingOperation,
    Globals globals,
    String buttonName,
    Future<void> Function()? onConfirm,
    Future<void> Function()? onCancel,
    bool showCancelButton,
  ) {
    return Row(
      children: [
        // Yes button (white background with border)
        showCancelButton
            ? Expanded(
                child: GestureDetector(
                  onTap: () async {
                    if (onCancel != null) {
                      await onCancel();
                    }
                    Navigator.of(context).pop(false);
                  },
                  child: Container(
                    height: 42.h,
                    decoration: BoxDecoration(
                      color: isPerformingOperation.value == true
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
                          color: isPerformingOperation.value == true
                              ? Colors.white
                              : Color(0xFF727272),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : SizedBox.shrink(),
        SizedBox(width: 12.w),
        Expanded(
          child: GestureDetector(
            onTap: isPerformingOperation.value == true
                ? null
                : () async {
                    if (isPerformingOperation.value) return;
                    isPerformingOperation.value = true;

                    try {
                      if (onConfirm != null) {
                        await onConfirm();
                      }
                      if (context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    } catch (e) {
                      isPerformingOperation.value = false;
                    }
                  },
            child: Container(
              height: 42.h,
              decoration: BoxDecoration(
                color: isPerformingOperation.value == true ? Colors.grey : null,
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: isPerformingOperation.value
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
                      buttonName,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w600,
                        fontSize: 18.sp,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (isPerformingOperation.value == true)
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
        ),
      ],
    );
  }
}
