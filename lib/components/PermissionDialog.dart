import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../constants.dart';
import '../size_config.dart';

enum PermissionType {
  location,
  camera,
  notification,
}

/// A beautiful, unified permission dialog component
/// Matches the design in the app's UI guidelines
class PermissionDialog extends StatelessWidget {
  final PermissionType type;
  final VoidCallback? onSkip;
  final VoidCallback? onAction;
  final String? customTitle;
  final String? customMessage;
  final String? customActionText;

  const PermissionDialog({
    Key? key,
    required this.type,
    this.onSkip,
    this.onAction,
    this.customTitle,
    this.customMessage,
    this.customActionText,
  }) : super(key: key);

  /// Show the permission dialog with smart fallback logic
  static Future<bool?> show(
    BuildContext context, {
    required PermissionType type,
    VoidCallback? onSkip,
    VoidCallback? onAction,
    String? customTitle,
    String? customMessage,
    String? customActionText,
    bool barrierDismissible = false,
  }) async {
    // For notification permission, try system dialog first on Android
    if (type == PermissionType.notification) {
      final permission = Permission.notification;
      final status = await permission.status;
      
      // If not denied permanently and can show request rationale, use system dialog
      if (!status.isDenied && !status.isPermanentlyDenied) {
        // Show system dialog - await blocks until user responds
        final result = await permission.request();
        return result.isGranted;
      }
      
      // If not yet permanently denied, still allow one more system attempt
      if (status.isDenied && await Permission.notification.shouldShowRequestRationale) {
        final result = await permission.request();
        return result.isGranted;
      }
      
      // Only show custom dialog if permission is permanently denied or system dialog not applicable
      if (status.isPermanentlyDenied) {
        final result = await showDialog<bool>(
          context: context,
          barrierDismissible: barrierDismissible,
          builder: (ctx) => PermissionDialog(
            type: type,
            onSkip: onSkip ?? () => Navigator.pop(ctx, false),
            onAction: onAction ?? () {
              openAppSettings();
              Navigator.pop(ctx, true);
            },
            customTitle: customTitle,
            customMessage: customMessage,
            customActionText: customActionText,
          ),
        );
        return result;
      }
      
      // One more attempt with custom dialog
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (ctx) => PermissionDialog(
          type: type,
          onSkip: onSkip ?? () => Navigator.pop(ctx, false),
          onAction: onAction ?? () async {
            final result = await permission.request();
            Navigator.pop(ctx, result.isGranted);
          },
          customTitle: customTitle,
          customMessage: customMessage,
          customActionText: customActionText,
        ),
      );
      return result;
    }
    
    // For other permissions, show custom dialog directly
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => PermissionDialog(
        type: type,
        onSkip: onSkip ?? () => Navigator.pop(ctx, false),
        onAction: onAction,
        customTitle: customTitle,
        customMessage: customMessage,
        customActionText: customActionText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(getProportionateScreenWidth(20)),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: getProportionateScreenWidth(32),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: getProportionateScreenWidth(24),
          vertical: getProportionateScreenHeight(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            _buildIcon(),
            SizedBox(height: getProportionateScreenHeight(20)),
            
            // Title
            Text(
              customTitle ?? _getTitle(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w700,
                fontSize: getProportionateScreenWidth(22),
                color: kPrimaryPurple,
                height: 1.2,
              ),
            ),
            SizedBox(height: getProportionateScreenHeight(12)),
            
            // Message
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: getProportionateScreenWidth(8),
              ),
              child: Text(
                customMessage ?? _getMessage(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w500,
                  fontSize: getProportionateScreenWidth(14),
                  color: const Color(0xFF666666),
                  height: 1.4,
                ),
              ),
            ),
            SizedBox(height: getProportionateScreenHeight(24)),
            
            // Buttons
            Row(
              children: [
                // Skip Button
                Expanded(
                  child: GestureDetector(
                    onTap: onSkip,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        vertical: getProportionateScreenHeight(14),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: kPrimaryPurple,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w600,
                            fontSize: getProportionateScreenWidth(15),
                            color: kPrimaryPurple,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: getProportionateScreenWidth(12)),
                
                // Action Button
                Expanded(
                  child: GestureDetector(
                    onTap: onAction,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        vertical: getProportionateScreenHeight(14),
                      ),
                      decoration: BoxDecoration(
                        color: kPrimaryPurple,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          customActionText ?? _getActionText(),
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w600,
                            fontSize: getProportionateScreenWidth(15),
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
      width: getProportionateScreenWidth(72),
      height: getProportionateScreenWidth(72),
      decoration: BoxDecoration(
        color: _getIconBackgroundColor(),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          _getIcon(),
          color: kPrimaryPurple,
          size: getProportionateScreenWidth(32),
        ),
      ),
    );
  }

  Color _getIconBackgroundColor() {
    return kQuaternaryPink.withOpacity(0.5);
  }

  IconData _getIcon() {
    switch (type) {
      case PermissionType.location:
        return Icons.location_on;
      case PermissionType.camera:
        return Icons.camera_alt;
      case PermissionType.notification:
        return Icons.notifications_active;
    }
  }

  String _getTitle() {
    switch (type) {
      case PermissionType.location:
        return 'Location Access\nRequired';
      case PermissionType.camera:
        return 'Camera Access\nRequired';
      case PermissionType.notification:
        return 'Enable Notifications';
    }
  }

  String _getMessage() {
    switch (type) {
      case PermissionType.location:
        return 'We need your location to show you matches nearby. Please enable location access in your settings.';
      case PermissionType.camera:
        return 'We need camera access to verify your profile. Please enable it in your settings.';
      case PermissionType.notification:
        return 'Stay updated with messages, matches, and important alerts. Enable notifications to never miss a moment.';
    }
  }

  String _getActionText() {
    switch (type) {
      case PermissionType.location:
        return 'Settings';
      case PermissionType.camera:
        return 'Settings';
      case PermissionType.notification:
        return 'Enable';
    }
  }
}

/// Verification Success Dialog
class VerificationRewardDialog extends StatelessWidget {
  final int coinsAwarded;
  final VoidCallback? onContinue;

  const VerificationRewardDialog({
    Key? key,
    required this.coinsAwarded,
    this.onContinue,
  }) : super(key: key);

  /// Show the verification reward dialog
  static Future<void> show(
    BuildContext context, {
    required int coinsAwarded,
    VoidCallback? onContinue,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => VerificationRewardDialog(
        coinsAwarded: coinsAwarded,
        onContinue: onContinue ?? () => Navigator.pop(ctx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(getProportionateScreenWidth(20)),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: getProportionateScreenWidth(32),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: getProportionateScreenWidth(24),
          vertical: getProportionateScreenHeight(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Success Icon with checkmark
            Container(
              width: getProportionateScreenWidth(80),
              height: getProportionateScreenWidth(80),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.verified,
                  color: Colors.green,
                  size: getProportionateScreenWidth(48),
                ),
              ),
            ),
            SizedBox(height: getProportionateScreenHeight(20)),
            
            // Title
            Text(
              'Verification Successful!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w700,
                fontSize: getProportionateScreenWidth(22),
                color: kPrimaryPurple,
              ),
            ),
            SizedBox(height: getProportionateScreenHeight(12)),
            
            // Message
            Text(
              'Congratulations! Your profile is now verified.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w500,
                fontSize: getProportionateScreenWidth(14),
                color: const Color(0xFF666666),
                height: 1.4,
              ),
            ),
            SizedBox(height: getProportionateScreenHeight(16)),
            
            // Coins Reward
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: getProportionateScreenWidth(20),
                vertical: getProportionateScreenHeight(12),
              ),
              decoration: BoxDecoration(
                color: kQuaternaryPink.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.monetization_on,
                    color: Colors.amber,
                    size: getProportionateScreenWidth(28),
                  ),
                  SizedBox(width: getProportionateScreenWidth(8)),
                  Text(
                    '+$coinsAwarded Coins',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w700,
                      fontSize: getProportionateScreenWidth(18),
                      color: kPrimaryPurple,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: getProportionateScreenHeight(24)),
            
            // Continue Button
            GestureDetector(
              onTap: onContinue,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  vertical: getProportionateScreenHeight(14),
                ),
                decoration: BoxDecoration(
                  gradient: kPrimaryGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    'Continue',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w600,
                      fontSize: getProportionateScreenWidth(16),
                      color: Colors.white,
                    ),
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
