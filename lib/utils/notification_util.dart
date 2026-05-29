import 'package:flutter/material.dart';
import 'package:overlay_support/overlay_support.dart';

/// Utility class for showing notifications with debouncing
class NotificationUtil {
  NotificationUtil._(); // Private constructor

  /// Shows an error notification (red)
  /// 
  /// [context] - BuildContext
  /// [message] - Error message to display
  /// [activeOverlay] - Reference to current overlay (for dismissing previous)
  /// [lastToastTime] - Reference to last toast time (for debouncing)
  /// [toastDebounceMs] - Minimum milliseconds between toasts
  static void showErrorNotification({
    required BuildContext context,
    required String message,
    required OverlaySupportEntry? Function() getActiveOverlay,
    required void Function(OverlaySupportEntry?) setActiveOverlay,
    required int Function() getLastToastTime,
    required void Function(int) setLastToastTime,
    int toastDebounceMs = 2000,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - getLastToastTime() < toastDebounceMs) {
      return; 
    }

    setLastToastTime(now);
    getActiveOverlay()?.dismiss();

    setActiveOverlay(
      showOverlayNotification(
        (notificationContext) => _buildNotification(
          context: notificationContext,
          message: message,
          color: Colors.red,
        ),
        duration: const Duration(seconds: 4),
        position: NotificationPosition.top,
      ),
    );
  }

  /// Shows a warning notification (orange)
  /// 
  /// [context] - BuildContext
  /// [message] - Warning message to display
  /// [activeOverlay] - Reference to current overlay (for dismissing previous)
  /// [lastToastTime] - Reference to last toast time (for debouncing)
  /// [toastDebounceMs] - Minimum milliseconds between toasts
  static void showWarningNotification({
    required BuildContext context,
    required String message,
    required OverlaySupportEntry? Function() getActiveOverlay,
    required void Function(OverlaySupportEntry?) setActiveOverlay,
    required int Function() getLastToastTime,
    required void Function(int) setLastToastTime,
    int toastDebounceMs = 2000,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - getLastToastTime() < toastDebounceMs) {
      return; 
    }

    setLastToastTime(now);
    getActiveOverlay()?.dismiss();

    setActiveOverlay(
      showOverlayNotification(
        (notificationContext) => _buildNotification(
          context: notificationContext,
          message: message,
          color: Colors.orange,
        ),
        duration: const Duration(seconds: 4),
        position: NotificationPosition.top,
      ),
    );
  }

  static Widget _buildNotification({
    required BuildContext context,
    required String message,
    required Color color,
  }) {
    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => OverlaySupportEntry.of(context)?.dismiss(),
                child: const Text(
                  'Dismiss',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
