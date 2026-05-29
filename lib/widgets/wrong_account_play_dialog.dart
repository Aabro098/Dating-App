import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/components/logout_dialog.dart';
import 'package:viora/constants.dart';

/// Google Play subscription is tied to another Viora user (Scenario 4).
Future<void> showWrongAccountPlayDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Purchase unavailable'),
      content: const Text(
        'This Google Play account has an active subscription linked to another Viora account.',
      ),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            if (!context.mounted) return;
            // Do not await — showDialog's future completes only when popped.
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              useRootNavigator: true,
              builder: (loadingCtx) => PopScope(
                canPop: false,
                child: AlertDialog(
                  content: Row(
                    children: [
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: kPrimaryPurple,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Text(
                          'Signing out…',
                          style: TextStyle(
                            fontSize: 16,
                            color: kTextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            try {
              await LogoutFunction().signOutAndCleanup(
                context,
                Globals.of(context),
              );
            } finally {
              if (context.mounted) {
                final nav = Navigator.of(context, rootNavigator: true);
                if (nav.canPop()) {
                  nav.pop();
                }
              }
            }
          },
          child: const Text('Switch Account'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            final uri = Uri.parse(
              'https://play.google.com/store/account/subscriptions',
            );
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (e) {
              if (kDebugMode) {
                debugPrint('[wrong_account_play_dialog] launch Play: $e');
              }
            }
          },
          child: const Text('Open Google Play'),
        ),
      ],
    ),
  );
}
