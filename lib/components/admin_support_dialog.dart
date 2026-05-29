import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/constants.dart';

class AdminSupportDialog {
  static Future<bool> show(
    BuildContext context,
    String title, {
    Future<void> Function()? onNew,
    Future<void> Function()? onInProgress,
    Future<void> Function()? onResolved,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha(100),
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: SafeArea(
              child: Dialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                insetPadding: const EdgeInsets.symmetric(horizontal: 5),
                child: _AdminSupportDialogContent(
                  title: title,
                  onNew: onNew,
                  onInProgress: onInProgress,
                  onResolved: onResolved,
                ),
              ),
            ),
          ),
        );
      },
    );
    return result ?? false;
  }
}

class _AdminSupportDialogContent extends HookWidget {
  final String title;
  final Future<void> Function()? onNew;
  final Future<void> Function()? onInProgress;
  final Future<void> Function()? onResolved;
  const _AdminSupportDialogContent({
    required this.title,
    this.onNew,
    this.onInProgress,
    this.onResolved,
  });

  @override
  Widget build(BuildContext context) {
    final globals = Globals.of(context);
    final isPerformingNewOperation = useState(false);
    final isPerformingInProgressOperation = useState(false);
    final isPerformingResolvedOperation = useState(false);

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
                  // Buttons
                  _buildButtons(
                    context,
                    globals,
                    onNew,
                    onInProgress,
                    onResolved,
                    isPerformingNewOperation,
                    isPerformingInProgressOperation,
                    isPerformingResolvedOperation,
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
    Globals globals,
    Future<void> Function()? onNew,
    Future<void> Function()? onInProgress,
    Future<void> Function()? onResolved,
    ValueNotifier<bool> isPerformingNewOperation,
    ValueNotifier<bool> isPerformingInProgressOperation,
    ValueNotifier<bool> isPerformingResolvedOperation,
  ) {
    return Wrap(
      runAlignment: WrapAlignment.center,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12.w,
      runSpacing: 12.h,
      children: [
        button(
          context,
          "New",
          onNew,
          isPerformingNewOperation,
          isPerformingInProgressOperation,
          isPerformingResolvedOperation,
        ),
        button(
          context,
          "In Progress",
          onInProgress,
          isPerformingNewOperation,
          isPerformingInProgressOperation,
          isPerformingResolvedOperation,
        ),
        button(
          context,
          "Resolved",
          onResolved,
          isPerformingNewOperation,
          isPerformingInProgressOperation,
          isPerformingResolvedOperation,
        ),
        button(
          context,
          "Cancel",
          () async {},
          isPerformingNewOperation,
          isPerformingInProgressOperation,
          isPerformingResolvedOperation,
        ),
      ],
    );
  }

  Widget button(
    BuildContext context,
    String buttonName,
    Future<void> Function()? onFunctionCall,
    ValueNotifier<bool> isPerformingNewOperation,
    ValueNotifier<bool> isPerformingInProgressOperation,
    ValueNotifier<bool> isPerformingResolvedOperation,
  ) {
    final isPerformingThisOperation = switch (buttonName) {
      'New' => isPerformingNewOperation.value,
      'In Progress' => isPerformingInProgressOperation.value,
      'Resolved' => isPerformingResolvedOperation.value,
      _ => false,
    };
    final isAnyOperationRunning =
        isPerformingNewOperation.value ||
        isPerformingInProgressOperation.value ||
        isPerformingResolvedOperation.value;

    return GestureDetector(
      onTap: isAnyOperationRunning
          ? null
          : () async {
              if (buttonName == "New") {
                isPerformingNewOperation.value = true;
              } else if (buttonName == "In Progress") {
                isPerformingInProgressOperation.value = true;
              } else if (buttonName == "Resolved") {
                isPerformingResolvedOperation.value = true;
              }

              try {
                if (onFunctionCall != null) {
                  await onFunctionCall();
                }
                if (context.mounted) {
                  Navigator.of(context).pop(true);
                }
              } catch (e) {
                isPerformingNewOperation.value = false;
                isPerformingInProgressOperation.value = false;
                isPerformingResolvedOperation.value = false;
              }
            },
      child: Container(
        height: 42.h,
        width: 136.w,
        decoration: BoxDecoration(
          color: isAnyOperationRunning ? Colors.grey : null,
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: isAnyOperationRunning
                ? [
                    kPrimaryPurple.withAlpha(216),
                    Color(0xFF8B3A7B).withAlpha(216),
                    Color(0xFFA14281).withAlpha(216),
                  ]
                : [kPrimaryPurple, Color(0xFF8B3A7B), Color(0xFFA14281)],
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
            if (isPerformingThisOperation)
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
    );
  }
}
