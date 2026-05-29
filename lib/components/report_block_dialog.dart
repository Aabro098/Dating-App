import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iconsax/iconsax.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/constants.dart';
import 'package:viora/models/ChatRoom.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:viora/size_config.dart';
import 'package:viora/utils/constatnts/colors.dart';

class ReportBlockDialog {
  static Future<bool> show(
    BuildContext context, {
    Future<void> Function()? onBlock,
    Future<void> Function()? onReport,
    required ChatRoom chatRoom,
    required UserDetails user,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha(100),
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(horizontal: 5),
            child: _ReportBlockDialogContent(
              onBlock: onBlock,
              onReport: onReport,
              chatRoom: chatRoom,
              user: user,
            ),
          ),
        );
      },
    );
    return result ?? false;
  }
}

class _ReportBlockDialogContent extends HookWidget {
  final Future<void> Function()? onBlock;
  final Future<void> Function()? onReport;
  final ChatRoom chatRoom;
  final UserDetails user;

  const _ReportBlockDialogContent({
    this.onBlock,
    this.onReport,
    required this.chatRoom,
    required this.user,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isPerformingOperation = useState(false);
    final globals = Globals.of(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Main dialog container with background image
        Container(
          width: screenWidth * 0.85,
          height: chatRoom.isBlocked
              ? getProportionateScreenHeight(82)
              : getProportionateScreenHeight(136),
          decoration: BoxDecoration(
            color: kBackgroundBG,
            borderRadius: BorderRadius.circular(12),
          ),
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
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: _buildButtons(
                  context,
                  isPerformingOperation,
                  globals,
                  'Report',
                  onReport,
                  onBlock,
                  chatRoom,
                  user,
                ),
              ),

              Positioned(
                right: 8,
                top: 8,
                child: GestureDetector(
                  onTap: () {
                    if (isPerformingOperation.value) return;
                    Navigator.of(context).pop(false);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppColors.purple,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.close, size: 24, color: Colors.white),
                  ),
                ),
              ),
              if (isPerformingOperation.value)
                Center(
                  child: SizedBox(
                    height: getProportionateScreenHeight(32),
                    width: getProportionateScreenWidth(32),
                    child: CircularProgressIndicator(strokeWidth: 4),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildButtons(
    BuildContext context,
    ValueNotifier<bool> isPerformingOperation,
    Globals globals,
    String buttonName,
    Future<void> Function()? onReport,
    Future<void> Function()? onBlock,
    ChatRoom chatRoom,
    UserDetails user,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: getProportionateScreenWidth(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Yes button (white background with border)
          GestureDetector(
            onTap: () async {
              if (isPerformingOperation.value) return;
              isPerformingOperation.value = true;

              try {
                if (onReport != null) {
                  await onReport();
                }
                if (context.mounted) {
                  Navigator.of(context).pop(true);
                }
              } catch (e) {
                isPerformingOperation.value = false;
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Report',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Color(0xFFEA2225),
                  ),
                ),
                SizedBox(width: getProportionateScreenWidth(6)),
                Icon(Iconsax.danger, color: Color(0xFFEA2225)),
              ],
            ),
          ),

          if (!chatRoom.isBlocked) ...[
            Divider(
              color: Color(0xFFDBDBDB),
              thickness: 2,
              height: getProportionateScreenHeight(32),
            ),
            GestureDetector(
              onTap: () async {
                if (isPerformingOperation.value) return;
                isPerformingOperation.value = true;

                try {
                  if (onBlock != null) {
                    await onBlock();
                  }
                  if (context.mounted) {
                    Navigator.of(context).pop(true);
                  }
                } catch (e) {
                  isPerformingOperation.value = false;
                }
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Block',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: Color(0xFF777777),
                    ),
                  ),
                  SizedBox(width: getProportionateScreenWidth(6)),
                  Icon(Icons.block, color: Color(0xFF777777)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
