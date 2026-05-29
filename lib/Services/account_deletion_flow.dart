// Shared account deletion: RevenueCat subscription warning + Firestore compliance + cleanup.

import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:viora/Screens/Home/homeScreen.dart';

import 'package:viora/Screens/Login_Signup/loginScreen.dart';
import 'package:viora/Services/AppConfigService.dart';
import 'package:viora/Services/FCMServie.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/Services/PhoneAuthService.dart';
import 'package:viora/Services/SubscriptionService.dart';
import 'package:viora/Services/session_service.dart';
import 'package:viora/components/delete_dialog.dart';
import 'package:viora/constants.dart';

class _PendingDeletionConfirmation {
  final bool hasActiveSubscription;
  final List<String> activeProductIds;
  final String deletionMethod;

  const _PendingDeletionConfirmation({
    required this.hasActiveSubscription,
    required this.activeProductIds,
    required this.deletionMethod,
  });
}

_PendingDeletionConfirmation? _pendingDeletionConfirmation;

/// Shows loading → checks RevenueCat → subscription warning sheet or simple confirm → [executeAccountDeletion].
Future<void> showAccountDeletionConfirmation(
  BuildContext context,
  ValueNotifier<bool> isDeletingAccount,
  Globals globals, {
  String deletionMethod = 'in_app_settings',
}) async {
  bool loadingShown = false;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        Center(child: CircularProgressIndicator(color: kPrimaryPurple)),
  );
  loadingShown = true;

  ({bool hasActiveSubscription, List<String> activeProductIds}) snapshot;
  final currentUser = FirebaseAuth.instance.currentUser;

  if (currentUser != null) {
    try {
      await SubscriptionService.refreshRevenueCatIdentity(
        currentUser.uid,
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint(
        '⚠️ Failed to refresh RevenueCat identity before deletion check: $e',
      );
    }
  }

  try {
    snapshot = await SubscriptionService.getSubscriptionSnapshotForAccountDeletion()
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            debugPrint(
              '⚠️ Subscription snapshot timed out; continuing with direct delete dialog.',
            );
            return (hasActiveSubscription: false, activeProductIds: <String>[]);
          },
        );

    if (!snapshot.hasActiveSubscription && currentUser != null) {
      try {
        final state =
            await SubscriptionService.getSubscriptionStateFromFirestore(
              currentUser.uid,
            ).timeout(const Duration(seconds: 4));

        final hasActiveFromFirestore =
            state != null &&
            SubscriptionService.subscriptionFirestoreOwnedBy(
              state,
              currentUser.uid,
            ) &&
            state.isActive;

        debugPrint(
          '🔍 Firestore Subscription Fallback: state=$state, owned=${state != null && SubscriptionService.subscriptionFirestoreOwnedBy(state, currentUser.uid)}, isActive=${state?.isActive}, hasActiveFromFirestore=$hasActiveFromFirestore',
        );

        if (hasActiveFromFirestore) {
          snapshot = (
            hasActiveSubscription: true,
            activeProductIds: state.productId == null
                ? <String>[]
                : <String>[state.productId!],
          );
          debugPrint(
            '✅ Account deletion: using Firestore fallback active subscription state.',
          );
        }
      } catch (e) {
        debugPrint('Error reading Firestore fallback subscription state: $e');
      }
    }
  } catch (e) {
    debugPrint('Error checking subscription before deletion: $e');
    snapshot = (hasActiveSubscription: false, activeProductIds: <String>[]);
  } finally {
    if (loadingShown && context.mounted) {
      final navigator = Navigator.of(context, rootNavigator: true);
      if (navigator.canPop()) {
        navigator.pop();
      }
    }
  }

  if (!context.mounted) return;

  // AppConfig is loaded in main() as non-blocking. If the user opens this
  // flow quickly, policies can still be empty. Force-refresh once here.
  if (AppConfigService.subscriptionPolicies.isEmpty) {
    try {
      await AppConfigService.reloadConfig().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('⚠️ Failed to refresh AppConfig before deletion dialog: $e');
    }
  }

  if (snapshot.hasActiveSubscription) {
    _showActiveSubscriptionDeleteDialog(
      context,
      isDeletingAccount,
      globals,
      snapshot.activeProductIds,
      deletionMethod: deletionMethod,
    );
  } else {
    // _showDirectDeleteDialog(
    //   context,
    //   isDeletingAccount,
    //   globals,
    //   deletionMethod: deletionMethod,
    // );
    DeleteDialog.show(context, deletionMethod);
  }
}

void _showActiveSubscriptionDeleteDialog(
  BuildContext context,
  ValueNotifier<bool> isDeletingAccount,
  Globals globals,
  List<String> activeProductIds, {
  required String deletionMethod,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext modalContext) {
      return _ActiveSubscriptionDeleteSheet(
        outerContext: context,
        isDeletingAccount: isDeletingAccount,
        globals: globals,
        activeProductIds: activeProductIds,
        deletionMethod: deletionMethod,
        bottomInset: MediaQuery.of(modalContext).padding.bottom,
      );
    },
  );
}

class _ActiveSubscriptionDeleteSheet extends StatefulWidget {
  final BuildContext outerContext;
  final ValueNotifier<bool> isDeletingAccount;
  final Globals globals;
  final List<String> activeProductIds;
  final String deletionMethod;
  final double bottomInset;

  const _ActiveSubscriptionDeleteSheet({
    required this.outerContext,
    required this.isDeletingAccount,
    required this.globals,
    required this.activeProductIds,
    required this.deletionMethod,
    required this.bottomInset,
  });

  @override
  State<_ActiveSubscriptionDeleteSheet> createState() =>
      _ActiveSubscriptionDeleteSheetState();
}

class _ActiveSubscriptionDeleteSheetState
    extends State<_ActiveSubscriptionDeleteSheet> {
  late final ScrollController _scrollController;
  bool _showScrollMoreHint = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollHint();
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollHint());
    });
  }

  void _onScroll() => _updateScrollHint();

  void _updateScrollHint() {
    if (!mounted) return;
    if (!_scrollController.hasClients) {
      if (_showScrollMoreHint) setState(() => _showScrollMoreHint = false);
      return;
    }
    final p = _scrollController.position;
    final moreBelow = p.maxScrollExtent > 4 && p.pixels < 8;
    if (moreBelow != _showScrollMoreHint) {
      setState(() => _showScrollMoreHint = moreBelow);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.75;
    final bottomPad = widget.bottomInset + 16;
    final policies = AppConfigService.subscriptionPolicies.isNotEmpty
        ? AppConfigService.subscriptionPolicies
        : [];
    final screenWidth = MediaQuery.of(context).size.width;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              _updateScrollHint();
              return false;
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification n) {
                if (n is ScrollUpdateNotification ||
                    n is OverscrollNotification) {
                  _updateScrollHint();
                }
                return false;
              },
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPad),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange.shade700,
                            size: 26,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Active Subscription Found",
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      "The subscription continues unless you cancel it in your Google Play account.",
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 15,
                        height: 1.45,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 20),
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Subscription Policy — Account Deletion",
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Colors.orange.shade800,
                            ),
                          ),
                          SizedBox(height: 12),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: policies.length,
                            itemBuilder: (context, index) {
                              return _DeletionPolicyBullet(
                                text: policies[index],
                              );
                            },
                          ),
                          // _DeletionPolicyBullet(
                          //   text:
                          //       "Deleting your account will NOT automatically cancel your active subscription.",
                          // ),
                          // _DeletionPolicyBullet(
                          //   text:
                          //       "You will continue to be charged by Google Play until you manually cancel the subscription.",
                          // ),
                          // _DeletionPolicyBullet(
                          //   text:
                          //       "To avoid future charges, please cancel your subscription from the Google Play Store before deleting your account.",
                          // ),
                          // _DeletionPolicyBullet(
                          //   text:
                          //       "Viora is not responsible for any charges incurred after account deletion if the subscription was not cancelled by the user.",
                          // ),
                          // _DeletionPolicyBullet(
                          //   text:
                          //       "No refunds will be provided for the remaining subscription period after account deletion.",
                          // ),
                          // _DeletionPolicyBullet(
                          //   text:
                          //       "All premium features and benefits will be immediately revoked upon account deletion.",
                          // ),
                        ],
                      ),
                    ),
                    SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final uri = Uri.parse(
                            'https://play.google.com/store/account/subscriptions',
                          );
                          try {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          } catch (e) {
                            debugPrint('Could not launch Play Store: $e');
                            if (context.mounted) {
                              showSimpleNotification(
                                Text("Could not open Play Store"),
                                background: Colors.redAccent,
                                position: NotificationPosition.bottom,
                              );
                            }
                          }
                        },
                        icon: Icon(Icons.store, size: 20),
                        label: Text(
                          "Manage Subscription",
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          if (widget.isDeletingAccount.value) return;
                          Navigator.pop(context);
                          DeleteDialog.show(context, widget.deletionMethod);
                        },
                        icon: Icon(Icons.delete_forever, size: 20),
                        label: Text(
                          "Delete Account",
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(color: Colors.red, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          "Cancel",
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: kSecondaryColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_showScrollMoreHint)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 72 + widget.bottomInset,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withAlpha(0),
                        Colors.white.withAlpha(200),
                        Colors.white,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 30,
                        color: kSecondaryColor.withAlpha(217),
                      ),
                      SizedBox(height: 6 + widget.bottomInset),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> logDeletionConfirmation({
  required bool hasActiveSubscription,
  required List<String> activeProductIds,
  required String deletionMethod,
}) async {
  _pendingDeletionConfirmation = _PendingDeletionConfirmation(
    hasActiveSubscription: hasActiveSubscription,
    activeProductIds: activeProductIds,
    deletionMethod: deletionMethod,
  );
}

Future<void> _requestBackendAccountDeletion({
  required bool hasActiveSubscription,
  required List<String> activeProductIds,
  required String deletionMethod,
}) async {
  final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  final callable = functions.httpsCallable(
    'accountDeletionRequest',
    options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
  );
  try {
    await callable.call({
      'hasActiveSubscription': hasActiveSubscription,
      'activeProductIds': activeProductIds,
      'deletionMethod': deletionMethod,
      'deviceType': _currentDeviceTypeForAudit(),
    });
  } on FirebaseFunctionsException catch (e) {
    if (e.code == 'not-found') {
      debugPrint(
        '❌ accountDeletionRequest is not deployed in us-central1 for this project.',
      );
      throw Exception(
        'Account deletion service is unavailable. Please update backend deployment.',
      );
    }
    throw Exception(
      e.message ?? 'Account deletion request failed. Please try again.',
    );
  }
}

Future<void> _performPreDeletionLocalCleanup({required Globals globals}) async {
  globals.resetInitialization();
  try {
    await globals.prefs.clear();
  } catch (e) {
    debugPrint('Error clearing SharedPreferences: $e');
  }
  PermissionSessionManager.resetSafetyTipsSession();
  try {
    PhoneAuth.clearVerificationSession();
  } catch (e) {
    debugPrint('Error clearing PhoneAuth session: $e');
  }
  try {
    await SessionService.stopMonitoringDeviceLimitChanges();
  } catch (e) {
    debugPrint('Error stopping device limit monitoring: $e');
  }
}

Future<void> _performPostDeletionLocalCleanup({
  required String uid,
  required Globals globals,
}) async {
  try {
    await FCMService.resetOnLogout();
    debugPrint('✅ FCM reset complete');
  } catch (e) {
    debugPrint('Error resetting FCM: $e');
  }
  try {
    await SubscriptionService.clearSubscriptionCacheOnLogout(
      uid: uid,
    ).timeout(const Duration(seconds: 8));
    debugPrint('✅ Subscription cache cleared');
  } catch (e) {
    debugPrint('Error clearing subscription cache: $e');
  }
  try {
    await FirebaseFirestore.instance.disableNetwork();
    debugPrint('✅ Firestore network disabled');
  } catch (e) {
    debugPrint('Warning: Could not disable Firestore network: $e');
  }

  try {
    await FirebaseFirestore.instance.terminate();
    debugPrint('✅ Firestore terminated');
  } catch (e) {
    debugPrint('Warning: Could not terminate Firestore: $e');
  }

  try {
    await FirebaseFirestore.instance.clearPersistence();
    debugPrint('✅ Firestore persistence cleared');
  } catch (e) {
    debugPrint('Error clearing Firestore persistence: $e');
  }
}

String _currentDeviceTypeForAudit() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.fuchsia:
      return 'fuchsia';
  }
}

/// Triggers backend account deletion job and waits for completion before sign-out.
Future<void> executeAccountDeletion(
  BuildContext context,
  ValueNotifier<bool> isDeletingAccount,
  Globals globals,
  bool dialogDisplay,
) async {
  isDeletingAccount.value = true;

  try {
    // Show loading dialog that blocks all interactions
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      isDeletingAccount.value = false;
      if (context.mounted) Navigator.pop(context);
      return;
    }
    final uid = currentUser.uid;
    final pending =
        _pendingDeletionConfirmation ??
        const _PendingDeletionConfirmation(
          hasActiveSubscription: false,
          activeProductIds: <String>[],
          deletionMethod: 'in_app_settings',
        );
    await _performPreDeletionLocalCleanup(globals: globals);
    await _requestBackendAccountDeletion(
      hasActiveSubscription: pending.hasActiveSubscription,
      activeProductIds: pending.activeProductIds,
      deletionMethod: pending.deletionMethod,
    );
    _pendingDeletionConfirmation = null;
    await FirebaseAuth.instance.signOut().timeout(const Duration(seconds: 8));
    await _performPostDeletionLocalCleanup(uid: uid, globals: globals);
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        LoginScreen.routeName,
        (Route<dynamic> route) => false,
      );
      showSimpleNotification(
        Text("Your account has been deleted successfully."),
        background: Colors.red,
        duration: Duration(seconds: 3),
        position: NotificationPosition.bottom,
        slideDismissDirection: DismissDirection.down,
        leading: Icon(Icons.check_circle),
      );
    }
    currentNavigationIndex.value = 0;
  } catch (e) {
    debugPrint('Error deleting account: $e');
    isDeletingAccount.value = false;
    // Close the loading dialog on error
    if (context.mounted) {
      Navigator.pop(context);
      showSimpleNotification(
        Text(e.toString().replaceFirst('Exception: ', '')),
        background: Colors.redAccent,
        duration: Duration(seconds: 4),
        position: NotificationPosition.bottom,
      );
    }
  }
}

class _DeletionPolicyBullet extends StatelessWidget {
  final String text;

  const _DeletionPolicyBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black87,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                height: 1.4,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// if (context.mounted) {
//                             showDialog<void>(
//                               context: context,
//                               barrierDismissible: false,
//                               barrierColor: Colors.black.withAlpha(100),
//                               builder: (dialogContext) => PopScope(
//                                 canPop: false, // Prevent back button
//                                 child: BackdropFilter(
//                                   filter: ImageFilter.blur(
//                                     sigmaX: 5,
//                                     sigmaY: 5,
//                                   ),
//                                   child: Dialog(
//                                     backgroundColor: Colors.transparent,
//                                     elevation: 0,
//                                     insetPadding: const EdgeInsets.symmetric(
//                                       horizontal: 5,
//                                     ),
//                                     shape: RoundedRectangleBorder(
//                                       borderRadius: BorderRadius.circular(16),
//                                     ),
//                                     child: Container(
//                                       width: screenWidth * 0.87,
//                                       height: getProportionateScreenHeight(200),
//                                       decoration: BoxDecoration(
//                                         color: kBackgroundBG,
//                                         borderRadius: BorderRadius.circular(12),
//                                       ),
//                                       child: Stack(
//                                         children: [
//                                           Positioned(
//                                             left: -170,
//                                             top: -95,
//                                             child: Image.asset(
//                                               'assets/icon/viora_transparent.png',
//                                               width: 370,
//                                               height: 370,
//                                               fit: BoxFit.contain,
//                                             ),
//                                           ),
//                                           Positioned(
//                                             right: -100,
//                                             top: -145,
//                                             child: Transform.scale(
//                                               scaleX: -1,
//                                               child: Image.asset(
//                                                 'assets/icon/viora_transparent.png',
//                                                 width: 310,
//                                                 height: 310,
//                                                 fit: BoxFit.contain,
//                                               ),
//                                             ),
//                                           ),
//                                           Column(
//                                             mainAxisSize: MainAxisSize.min,
//                                             children: [
//                                               CircularProgressIndicator(
//                                                 color: AppColors.purple,
//                                                 strokeWidth: 4,
//                                               ),
//                                               SizedBox(height: 20),
//                                               Text(
//                                                 "Deleting Account...",
//                                                 style: TextStyle(
//                                                   fontFamily: 'Nunito',
//                                                   fontWeight: FontWeight.w700,
//                                                   fontSize: 16,
//                                                   color: AppColors.purple,
//                                                 ),
//                                               ),
//                                               SizedBox(height: 8),
//                                               Text(
//                                                 "Please wait till the time Deletion is happening",
//                                                 style: TextStyle(
//                                                   fontFamily: 'Nunito',
//                                                   fontSize: 13,
//                                                   color: AppColors.purple,
//                                                 ),
//                                                 textAlign: TextAlign.center,
//                                               ),
//                                             ],
//                                           ),
//                                         ],
//                                       ),
//                                     ),
//                                   ),
//                                 ),
//                               ),
//                             );
//                           }


// final waitResult = await _waitForDeletionCompletion(
    //   uid: uid,
    //   timeout: const Duration(minutes: 2),
    // );

    // if (waitResult.failed) {
    //   throw Exception(
    //     waitResult.message ??
    //         'Account deletion failed on the server. Please try again.',
    //   );
    // }

    // if (!waitResult.completed) {
    //   throw Exception(
    //     waitResult.message ??
    //         'Account deletion is still in progress. Please try again shortly.',
    //   );
    // }



// class _DeletionWaitResult {
//   final bool completed;
//   final bool failed;
//   final String? message;

//   const _DeletionWaitResult({
//     required this.completed,
//     required this.failed,
//     this.message,
//   });
// }

// Future<bool> _isAuthUserDeleted() async {
//   final user = FirebaseAuth.instance.currentUser;
//   if (user == null) {
//     return true;
//   }

//   try {
//     await user.reload().timeout(const Duration(seconds: 8));
//     return FirebaseAuth.instance.currentUser == null;
//   } on FirebaseAuthException catch (e) {
//     if (e.code == 'user-not-found' ||
//         e.code == 'invalid-user-token' ||
//         e.code == 'user-token-expired') {
//       return true;
//     }
//     debugPrint('Error while checking auth deletion: ${e.code}');
//     return false;
//   } catch (e) {
//     debugPrint('Unexpected error while checking auth deletion: $e');
//     return false;
//   }
// }

// String? _extractDeletionJobErrorMessage(Object? rawError) {
//   if (rawError is String && rawError.trim().isNotEmpty) {
//     return rawError.trim();
//   }

//   if (rawError is Map) {
//     final code = rawError['code']?.toString();
//     final message = rawError['message']?.toString();
//     if (message != null && message.trim().isNotEmpty) {
//       if (code != null && code.trim().isNotEmpty) {
//         return '${code.trim()}: ${message.trim()}';
//       }
//       return message.trim();
//     }
//   }

//   return null;
// }

// Future<_DeletionWaitResult> _waitForDeletionCompletion({
//   required String uid,
//   required Duration timeout,
//   Duration pollInterval = const Duration(seconds: 4),
// }) async {
//   final start = DateTime.now();
//   bool canReadJobStatus = true;

//   while (DateTime.now().difference(start) < timeout) {
//     await Future.delayed(pollInterval);

//     if (canReadJobStatus) {
//       try {
//         final jobDoc = await FirebaseFirestore.instance
//             .collection('AccountDeletionJobs')
//             .doc(uid)
//             .get()
//             .timeout(const Duration(seconds: 8));

//         if (jobDoc.exists) {
//           final data = jobDoc.data() ?? <String, dynamic>{};
//           final status = (data['status'] ?? '').toString().trim();

//           if (status == 'completed') {
//             return const _DeletionWaitResult(completed: true, failed: false);
//           }

//           if (status == 'failed') {
//             return _DeletionWaitResult(
//               completed: false,
//               failed: true,
//               message: _extractDeletionJobErrorMessage(data['error']),
//             );
//           }
//         }
//       } on FirebaseException catch (e) {
//         if (e.code == 'permission-denied') {
//           canReadJobStatus = false;
//           debugPrint(
//             'AccountDeletionJobs status read denied by Firestore rules; falling back to auth polling only.',
//           );
//         } else {
//           debugPrint('Error while polling AccountDeletionJobs: ${e.code}');
//         }
//       } catch (e) {
//         debugPrint('Unexpected error while polling deletion job status: $e');
//       }
//     }

//     final authDeleted = await _isAuthUserDeleted();
//     if (authDeleted) {
//       return const _DeletionWaitResult(completed: true, failed: false);
//     }
//   }

//   return const _DeletionWaitResult(
//     completed: false,
//     failed: false,
//     message: 'Account deletion is still running on the server.',
//   );
// }
