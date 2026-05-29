// FILE: Screens/PaymentScreen/payment_screen.dart
// Subscriptions / Manage Your Dating Experience UI
// Fetches plans from Firestore: Subscriptions/billingPeriods.default + plans + displayData

import 'dart:async';
import 'dart:developer' as developer;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:viora/Screens/SupportScreen/supportScreen.dart';
import 'package:viora/models/SubscriptionPlanDisplay.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:viora/Services/SubscriptionDisplayService.dart';
import 'package:viora/Services/SubscriptionService.dart';
import 'package:viora/widgets/wrong_account_play_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants.dart';
import '../../size_config.dart';
import '../SubscriptionPolicy/subscription_policy.dart';
import '../../Services/Global.dart';

/// Hardcoded plan access (Firestore features + daily limit) for "What access you have" dialog.
//if isMale()
//Else
const Map<String, ({String name, List<String> features, String dailyLimit})>
_planAccess = {
  'starter_monthly': (
    name: 'Starter',
    features: ['Messaging'],
    dailyLimit: '10 messages + images per day',
  ),
  'deluxe_monthly': (
    name: 'Deluxe',
    features: ['Messaging', 'Only Online users'],
    dailyLimit: '40 messages + images per day',
  ),
  'premium_monthly': (
    name: 'Premium',
    features: [
      'Messaging',
      'Only Online users',
      'Image View',
      'AI Bio generation',
      'In Top Picks (10 days validity)',
      'Verified profiles (10 days validity)',
    ],
    dailyLimit: '100 messages + images per day',
  ),
  'elite_monthly': (
    name: 'Elite',
    features: [
      'Messaging',
      'Only Online users',
      'Image View',
      'AI Bio generation',
      'About Visible',
      'Minimum Photos Slider',
      'In Top Picks (UnLimited)',
      'Verified profiles (UnLimited)',
    ],
    dailyLimit: 'Unlimited messages + images',
  ),
};

/// Resolves [SubscriptionService.toProductIdForDisplay] ids for yearly plans to the
/// same tier as monthly in [_planAccess] (e.g. deluxe_yearly → deluxe_monthly).
({String name, List<String> features, String dailyLimit})?
_planAccessEntryForProductId(String planKey) {
  if (planKey.isEmpty) return null;
  final k = planKey.toLowerCase().trim();
  final direct = _planAccess[k];
  if (direct != null) return direct;
  final asMonthly = k.replaceAll('_yearly', '_monthly');
  if (asMonthly != k) {
    final m = _planAccess[asMonthly];
    if (m != null) return m;
  }
  final y = k.lastIndexOf('_yearly');
  if (y > 0) {
    final base = k.substring(0, y);
    final b = _planAccess[base];
    if (b != null) return b;
  }
  return null;
}

/// PaymentScreen - Subscriptions / Manage Your Dating Experience
/// Displays subscription plans for the default billing period from Firestore.
class PaymentScreen extends StatefulWidget {
  /// When used inside bottom navigation [IndexedStack], pass whether this tab is
  /// selected so we lazy-load once and refresh silently when re-selected.
  final bool isActiveTab;
  final bool showArrowBack;

  const PaymentScreen({
    super.key,
    this.isActiveTab = true,
    this.showArrowBack = false,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with WidgetsBindingObserver {
  List<SubscriptionPlanDisplay> _plans = [];
  bool _loading = true;
  bool _completedInitialLoad = false;
  bool _subscribingInProgress = false;
  String? _subscribingPlanKey;
  SubscriptionDisplayInfo? _subscriptionInfo;

  /// From [Subscriptions/entitlementFeatures] for current [entitlementId].
  List<String> _entitlementFeatureLabels = [];
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _subscriptionCurrentListener;

  Future<void> _loadEntitlementFeatureLabels(
    SubscriptionDisplayInfo? subInfo,
  ) async {
    if (subInfo == null || !subInfo.isActive) {
      if (mounted) setState(() => _entitlementFeatureLabels = []);
      return;
    }
    final labels =
        await SubscriptionDisplayService.fetchEnabledEntitlementFeatureLabels(
          entitlementId: subInfo.entitlementId,
          productId: subInfo.activeProductStoreId,
        );
    if (mounted) setState(() => _entitlementFeatureLabels = labels);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActiveTab) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        _subscriptionInfo = SubscriptionService.peekCachedSubscriptionDisplay(
          uid,
        );
      }
      _loadPlansAndSubscription();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscriptionCurrentListener?.cancel();
    _subscriptionCurrentListener = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _completedInitialLoad &&
        widget.isActiveTab) {
      _silentRefreshSubscriptionData();
    }
  }

  void _ensureFirestoreSubscriptionListener(String uid) {
    _subscriptionCurrentListener?.cancel();
    _subscriptionCurrentListener = FirebaseFirestore.instance
        .collection('Users')
        .doc(uid)
        .collection('Subscription')
        .doc('current')
        .snapshots()
        .listen(
          (_) {
            if (!mounted || !_completedInitialLoad) return;
            _silentRefreshSubscriptionData();
          },
          onError: (error) {
            if (error is FirebaseException &&
                error.code == 'permission-denied') {
              // During logout/deletion, this listener can lose permission.
              return;
            }
            if (kDebugMode) {
              debugPrint('[PaymentScreen] Subscription listener error: $error');
            }
          },
        );
  }

  @override
  void didUpdateWidget(PaymentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActiveTab && !oldWidget.isActiveTab) {
      if (!_completedInitialLoad) {
        _loadPlansAndSubscription();
      } else {
        _silentRefreshSubscriptionData();
      }
    }
  }

  Future<void> _loadPlansAndSubscription({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _loading = true);
    final globals = Globals.of(context);
    final gender = globals.prefs.userDetails.value?.gender ?? 'Male';
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (kDebugMode) {
        debugPrint('FirebaseAuth.instance.currentUser =$gender');
        debugPrint('[PaymentScreen] _loadPlansAndSubscription uid=$uid');
      }

      // Firestore plans are fast (parallel reads in [fetchMonthlyPlans]). RevenueCat path is
      // slow — do not block the grid on it; show plans first, then banner / badges update.
      final plansFuture = SubscriptionDisplayService.fetchMonthlyPlans(gender);
      final Future<SubscriptionDisplayInfo?>? subFuture = uid != null
          ? SubscriptionService.getSubscriptionDisplayInfo(uid)
          : null;

      final plans = await plansFuture;

      if (uid != null) {
        _ensureFirestoreSubscriptionListener(uid);
      }
      if (mounted) {
        setState(() {
          _plans = plans;
          _loading = false;
          _completedInitialLoad = true;
        });
      }

      SubscriptionDisplayInfo? subInfo;
      if (subFuture != null) {
        subInfo = await subFuture;
      }
      developer.log(
        'subInfo loaded: present=${subInfo != null} isActive=${subInfo?.isActive} '
        'willRenew=${subInfo?.willRenew} product=${subInfo?.activeProductStoreId} '
        'exp=${subInfo?.expirationTime}',
        name: 'PaymentScreen.sub',
      );
      if (kDebugMode) {
        debugPrint(
          '[PaymentScreen] _loadPlansAndSubscription: plans=${plans.length} '
          'subInfo=${subInfo != null} isActive=${subInfo?.isActive} '
          'willRenew=${subInfo?.willRenew} '
          'activeProductStoreId=${subInfo?.activeProductStoreId} expirationTime=${subInfo?.expirationTime}',
        );
        for (final p in plans) {
          debugPrint(
            '[PaymentScreen]   plan: planKey=${p.planKey} googlePlanKey=${p.googlePlanKey}',
          );
        }
      }
      if (mounted) {
        setState(() {
          _subscriptionInfo = subInfo;
        });
        await _loadEntitlementFeatureLabels(subInfo);
      }
    } catch (e) {
      if (kDebugMode)
        debugPrint('[PaymentScreen] _loadPlansAndSubscription error: $e');
      if (mounted) {
        setState(() {
          _plans = SubscriptionDisplayService.getDefaultPlans();
          _subscriptionInfo = null;
          _entitlementFeatureLabels = [];
          _loading = false;
          _completedInitialLoad = true;
        });
      }
    }
  }

  /// Refresh subscription line only; no full-page loader. Updates UI if data changed.
  Future<void> _silentRefreshSubscriptionData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final subInfo = await SubscriptionService.getSubscriptionDisplayInfo(
        uid,
        forceRefresh: true,
      );
      if (!mounted) return;
      if (!_subscriptionDisplayEqual(_subscriptionInfo, subInfo)) {
        setState(() {
          _subscriptionInfo = subInfo;
        });
      }
      await _loadEntitlementFeatureLabels(subInfo);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PaymentScreen] _silentRefreshSubscriptionData: $e');
      }
    }
  }

  /// Badges: if plan is active show only active badge; else show Most Chosen / Elite from Firestore.
  List<String> _badgesForPlan(SubscriptionPlanDisplay plan, int index) {
    final isActive = SubscriptionService.isPlanActive(plan, _subscriptionInfo);
    if (kDebugMode) {
      debugPrint(
        '[PaymentScreen] _badgesForPlan: plan=${plan.planKey} googlePlanKey=${plan.googlePlanKey} '
        'subInfo=${_subscriptionInfo != null} isActive=${_subscriptionInfo?.isActive} '
        'activeProductStoreId=${_subscriptionInfo?.activeProductStoreId} => isPlanActive=$isActive '
        'badge=${isActive ? "ACTIVE_PACK" : "other"}',
      );
    }
    if (isActive) {
      return ["assets/subscriptions/active_pack.svg"];
    }
    final list = <String>[];
    if (plan.mostChosen) list.add("assets/subscriptions/most_chosen_tag.svg");
    if (plan.eliteExp)
      list.add("assets/subscriptions/elite_ecperience_tag.svg");
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background image (same pattern as ChatsScreen, CompleteProfile)
          Positioned(
            left: getProportionateScreenWidth(-97),
            top: getProportionateScreenHeight(-90),
            child: Transform(
              transform: Matrix4.identity()..scale(-1.0, 1.0),
              alignment: Alignment.center,
              child: Image.asset(
                "assets/icon/viora_transparent.png",
                width: getProportionateScreenWidth(270),
                height: getProportionateScreenHeight(210),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            right: getProportionateScreenWidth(-120),
            top: getProportionateScreenHeight(-97),
            child: Image.asset(
              "assets/icon/viora_transparent.png",
              width: getProportionateScreenWidth(360),
              height: getProportionateScreenHeight(270),
              fit: BoxFit.cover,
            ),
          ),
          // Content
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: getProportionateScreenWidth(kDefaultPadding),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: getProportionateScreenHeight(44)),
                // Title & Subtitle
                Row(
                  children: [
                    if (widget.showArrowBack) ...[
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).pop();
                        },
                        child: Icon(
                          Icons.arrow_back_ios,
                          size: 24,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(width: getProportionateScreenWidth(8)),
                    ],
                    Text(
                      "Subscriptions",
                      style: TextStyle(
                        fontSize: getProportionateScreenWidth(34),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  "Manage Your Dating Experience",
                  style: TextStyle(
                    fontSize: getProportionateScreenWidth(16),
                    color: kTextColor,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: getProportionateScreenHeight(16)),
                Expanded(
                  child: _loading
                      ? Center(
                          child: CircularProgressIndicator(
                            color: kPrimaryPurple,
                          ),
                        )
                      : SingleChildScrollView(
                          child: Column(
                            children: [
                              if (_subscriptionInfo != null &&
                                  (_subscriptionInfo!.isActive ||
                                      _subscriptionInfo!.expirationTime !=
                                          null)) ...[
                                _CurrentPlanExpiryBanner(
                                  expirationTime:
                                      _subscriptionInfo!.expirationTime,
                                  isActive: _subscriptionInfo!.isActive,
                                  willRenew: _subscriptionInfo!.willRenew,
                                  planName: _planNameFromProductId(
                                    _subscriptionInfo!.activeProductStoreId,
                                  ),
                                ),
                                SizedBox(
                                  height: getProportionateScreenHeight(24),
                                ),
                              ],
                              if (_plans.isEmpty)
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: getProportionateScreenHeight(24),
                                  ),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        Text(
                                          'No plans available.',
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: kTextColor,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        TextButton.icon(
                                          onPressed: _loadPlansAndSubscription,
                                          icon: Icon(Icons.refresh, size: 20),
                                          label: Text('Retry'),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                ...List.generate(_plans.length, (i) {
                                  final plan = _plans[i];
                                  final badgeSvgs = _badgesForPlan(plan, i);
                                  final isActivePlan =
                                      SubscriptionService.isPlanActive(
                                        plan,
                                        _subscriptionInfo,
                                      );
                                  final key =
                                      plan.googlePlanKey ?? plan.planKey;
                                  final isSubscribingThisPlan =
                                      _subscribingInProgress &&
                                      _subscribingPlanKey == key;
                                  return Padding(
                                    padding: EdgeInsets.only(
                                      bottom: getProportionateScreenHeight(16),
                                    ),
                                    child: _PlanCard(
                                      plan: plan,
                                      badgeSvgs: badgeSvgs,
                                      isActive: isActivePlan,
                                      isFirstCard: i < 2,
                                      isSubscribing: isSubscribingThisPlan,
                                      canSubscribe:
                                          !_subscribingInProgress &&
                                          plan.googlePlanKey != null &&
                                          plan.googlePlanKey!.isNotEmpty,
                                      onSubscribe:
                                          (plan.googlePlanKey == null ||
                                              plan.googlePlanKey!.isEmpty)
                                          ? null
                                          : () =>
                                                _onSubscribeTap(context, plan),
                                    ),
                                  );
                                }),
                              SizedBox(
                                height: getProportionateScreenHeight(24),
                              ),
                              if (_subscriptionInfo != null &&
                                  _subscriptionInfo!.isActive) ...[
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _showWhatAccessYouHave(context),
                                    icon: Icon(
                                      Icons.card_giftcard,
                                      size: 20,
                                      color: kPrimaryPurple,
                                    ),
                                    label: Text(
                                      'What access you have',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: kPrimaryPurple,
                                        fontSize: getProportionateScreenWidth(
                                          14,
                                        ),
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: kPrimaryPurple),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: getProportionateScreenHeight(16),
                                ),
                              ],
                              // Purchase History & Chat Support
                              Row(
                                children: [
                                  OutlinedButton(
                                    onPressed: () async {
                                      // Play: Payments & subscriptions → Budget & order history
                                      // (see https://support.google.com/googleplay/answer/2850369)
                                      final uri = Uri.parse(
                                        'https://play.google.com/store/account/orderhistory',
                                      );
                                      try {
                                        await launchUrl(
                                          uri,
                                          mode: LaunchMode.externalApplication,
                                        );
                                      } catch (e) {
                                        if (kDebugMode)
                                          debugPrint(
                                            'Could not launch Play Store: $e',
                                          );
                                        if (mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Could not open Play Store',
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: kTertiaryPink,
                                      backgroundColor: kTertiaryPink,
                                      side: BorderSide(color: kTertiaryPink),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: EdgeInsets.symmetric(
                                        vertical: 6,
                                        horizontal: 12,
                                      ),
                                    ),
                                    child: Text(
                                      "Purchase History",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Spacer(),
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: GestureDetector(
                                      onTap: () => _navigateToSupport(context),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.green,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        padding: const EdgeInsets.all(8.0),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.support_agent,
                                              color: Colors.white,
                                            ),
                                            Text(
                                              "  Chat Support",
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(
                                height: getProportionateScreenHeight(20),
                              ),
                              // Subscription Policy
                              Row(
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      GestureDetector(
                                        onTap: () {
                                          PersistentNavBarNavigator.pushNewScreen(
                                            context,
                                            screen: SubscriptionPolicyScreen(),
                                            withNavBar: false,
                                            pageTransitionAnimation:
                                                PageTransitionAnimation
                                                    .cupertino,
                                          );
                                        },
                                        child: Text(
                                          "Subscription Policy",
                                          style: TextStyle(
                                            color: kPrimaryPurple,
                                            fontSize:
                                                getProportionateScreenWidth(14),
                                            decoration:
                                                TextDecoration.underline,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        "Subscriptions are managed and billed via Google Play",
                                        style: TextStyle(
                                          fontSize: getProportionateScreenWidth(
                                            12,
                                          ),
                                          color: kPrimaryPurple,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (_subscriptionInfo != null &&
                                  _subscriptionInfo!.isActive &&
                                  _entitlementFeatureLabels.isNotEmpty) ...[
                                SizedBox(
                                  height: getProportionateScreenHeight(20),
                                ),
                                _EntitlementFeaturesBanner(
                                  labels: _entitlementFeatureLabels,
                                ),
                              ],
                              SizedBox(
                                height: getProportionateScreenHeight(32),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToSupport(BuildContext context) {
    PersistentNavBarNavigator.pushNewScreen(
      context,
      screen: SupportScreen(canPop: true),
      withNavBar: false,
      pageTransitionAnimation: PageTransitionAnimation.cupertino,
    );
  }

  Future<void> _onSubscribeTap(
    BuildContext context,
    SubscriptionPlanDisplay plan,
  ) async {
    // Wrong-account / shared Play: [SubscriptionService.shouldBlockPurchaseBeforePlay] runs
    // inside [purchaseSubscription] (strict: Play subscription + Firestore grace).
    await _onSubscribe(context, plan);
  }

  Future<void> _onSubscribe(
    BuildContext context,
    SubscriptionPlanDisplay plan,
  ) async {
    if (_subscribingInProgress) return;
    final baseline = _subscriptionInfo;
    if (mounted) {
      setState(() {
        _subscribingInProgress = true;
        _subscribingPlanKey = plan.googlePlanKey ?? plan.planKey;
      });
    }
    try {
      final success = await SubscriptionService.purchaseSubscription(
        context,
        plan,
        onWrongAccount: showWrongAccountPlayDialog,
      );
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (!mounted) return;
      // Stop subscribe loader as soon as purchase returns — webhook may still be pending.
      setState(() {
        _subscribingInProgress = false;
        _subscribingPlanKey = null;
      });

      if (success && uid != null) {
        final polled =
            await SubscriptionService.pollSubscriptionDisplayAfterPurchase(
              uid,
              plan,
              baseline,
              onPoll: (info) {
                if (!mounted) return;
                setState(() {
                  _subscriptionInfo = info ?? _subscriptionInfo;
                });
              },
            );
        if (mounted) {
          setState(() {
            _subscriptionInfo = polled ?? _subscriptionInfo;
          });
          await _loadEntitlementFeatureLabels(polled ?? _subscriptionInfo);
        }
        final globals = Globals.of(context);
        final gender = globals.prefs.userDetails.value?.gender ?? 'Male';
        final plans = await SubscriptionDisplayService.fetchMonthlyPlans(
          gender,
        );
        if (mounted && !_plansListEqual(_plans, plans)) {
          setState(() => _plans = plans);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _subscribingInProgress = false;
          _subscribingPlanKey = null;
        });
      }
    }
  }

  void _showWhatAccessYouHave(BuildContext context) {
    final planKey = (_subscriptionInfo?.activeProductStoreId ?? '')
        .toLowerCase()
        .replaceAll(' ', '_');
    final access = _planAccessEntryForProductId(planKey);
    if (access == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plan "$planKey" access details not found')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          24,
          20,
          MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Your plan: ${access.name}',
              style: TextStyle(
                fontSize: getProportionateScreenWidth(18),
                fontWeight: FontWeight.bold,
                color: kBlack,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Access you have:',
              style: TextStyle(
                fontSize: getProportionateScreenWidth(14),
                fontWeight: FontWeight.w600,
                color: kTextColor,
              ),
            ),
            SizedBox(height: 8),
            ...access.features.map(
              (f) => Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle, size: 20, color: Colors.green),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        f,
                        style: TextStyle(
                          fontSize: getProportionateScreenWidth(14),
                          color: kBlack,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kPrimaryPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.all_inclusive, color: kPrimaryPurple, size: 20),
                  SizedBox(width: 8),
                  Text(
                    access.dailyLimit,
                    style: TextStyle(
                      fontSize: getProportionateScreenWidth(13),
                      fontWeight: FontWeight.w500,
                      color: kPrimaryPurple,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _subscriptionDisplayEqual(
  SubscriptionDisplayInfo? a,
  SubscriptionDisplayInfo? b,
) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  if (a.isActive != b.isActive || a.willRenew != b.willRenew) return false;
  if (a.activeProductStoreId != b.activeProductStoreId) return false;
  if (a.entitlementId != b.entitlementId) return false;
  return _sameExpiryMinute(a.expirationTime, b.expirationTime);
}

bool _sameExpiryMinute(DateTime? a, DateTime? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  return (a.difference(b).inSeconds).abs() < 90;
}

bool _plansListEqual(
  List<SubscriptionPlanDisplay> a,
  List<SubscriptionPlanDisplay> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].planKey != b[i].planKey ||
        a[i].googlePlanKey != b[i].googlePlanKey ||
        a[i].price != b[i].price) {
      return false;
    }
  }
  return true;
}

/// Returns display name for a product id (e.g. deluxe_monthly -> Deluxe).
String _planNameFromProductId(String? productId) {
  if (productId == null || productId.isEmpty) return '';
  final key = productId.toLowerCase().trim();
  final name = _planAccessEntryForProductId(key)?.name;
  if (name != null && name.isNotEmpty) return name;
  return key
      .split('_')
      .map(
        (w) =>
            w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase(),
      )
      .join(' ');
}

/// Banner showing renew/expiry state for current subscription.
class _CurrentPlanExpiryBanner extends StatelessWidget {
  final DateTime? expirationTime;
  final bool isActive;
  final bool willRenew;
  final String? planName;

  const _CurrentPlanExpiryBanner({
    this.expirationTime,
    this.isActive = true,
    this.willRenew = true,
    this.planName,
  });

  @override
  Widget build(BuildContext context) {
    final formatted = expirationTime != null
        ? DateFormat('dd-MMM-yyyy').format(expirationTime!)
        : '—';
    final isExpired = !isActive;
    final String message;
    if (isExpired) {
      message = 'Subscription expired on: $formatted';
    } else if (!willRenew) {
      final pn = (planName ?? '').trim();
      message = pn.isEmpty
          ? 'Subscription expires on: $formatted'
          : '$pn Subscription expires on: $formatted';
    } else {
      message = 'Subscription renews on: $formatted';
    }

    developer.log(
      'banner: isExpired=$isExpired willRenew=$willRenew planName=$planName '
      '→ "$message"',
      name: 'PaymentScreen.sub',
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: getProportionateScreenWidth(16),
        vertical: getProportionateScreenHeight(12),
      ),
      decoration: BoxDecoration(
        color: isExpired
            ? Colors.grey.shade200
            : kQuaternaryPink.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExpired
              ? Colors.grey.shade400
              : kPrimaryPurple.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          // SvgPicture.asset(
          //   "assets/subscriptions/coinn_icon.svg",
          //   width: 22,
          //   height: 22,
          // ),
          // SizedBox(width: getProportionateScreenWidth(12)),
          Expanded(
            child: Text(
              message,
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: getProportionateScreenWidth(12),
                color: isExpired ? Colors.grey.shade700 : kBlack,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lists enabled features from Firestore [Subscriptions/entitlementFeatures].
class _EntitlementFeaturesBanner extends StatelessWidget {
  final List<String> labels;

  const _EntitlementFeaturesBanner({required this.labels});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: getProportionateScreenWidth(16),
        vertical: getProportionateScreenHeight(14),
      ),
      decoration: BoxDecoration(
        color: kPrimaryPurple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kPrimaryPurple.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, color: kPrimaryPurple, size: 20),
              SizedBox(width: 8),
              Text(
                'Your plan includes',
                style: TextStyle(
                  fontSize: getProportionateScreenWidth(14),
                  fontWeight: FontWeight.w700,
                  color: kBlack,
                ),
              ),
            ],
          ),
          SizedBox(height: getProportionateScreenHeight(10)),
          ...labels.map(
            (line) => Padding(
              padding: EdgeInsets.only(bottom: getProportionateScreenHeight(6)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(Icons.check, size: 16, color: kPrimaryPurple),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: getProportionateScreenWidth(13),
                        color: kTextColor,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge overlay: show SVG centered (ACTIVE PACK, MOST CHOSEN, Elite Experience)
class _PlanBadgeSvg extends StatelessWidget {
  final String svgAsset;

  const _PlanBadgeSvg({required this.svgAsset});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SvgPicture.asset(
        svgAsset,
        width: getProportionateScreenWidth(120),
        height: getProportionateScreenHeight(32),
        fit: BoxFit.contain,
      ),
    );
  }
}

/// Single subscription plan card (data from Firestore: planName, cardBg, features, pointIcon, price, shortDescription, eliteExp, mostChosen)
class _PlanCard extends StatelessWidget {
  final SubscriptionPlanDisplay plan;
  final List<String> badgeSvgs;
  final bool isActive;
  final bool isFirstCard;
  final bool isSubscribing;
  final bool canSubscribe;
  final VoidCallback? onSubscribe;

  static const Color _goldenBorder = Color(0xFFD4AF37);

  const _PlanCard({
    required this.plan,
    this.badgeSvgs = const [],
    required this.isActive,
    required this.isFirstCard,
    this.isSubscribing = false,
    this.canSubscribe = true,
    this.onSubscribe,
  });

  @override
  Widget build(BuildContext context) {
    final isHighlight = plan.isHighlightCard;
    final isElite = plan.isEliteCard;
    final bool useDarkCard = isHighlight || isElite;
    final Color textColor = useDarkCard ? kWhite : kBlack;
    final Color descColor = useDarkCard
        ? kWhite.withValues(alpha: 0.9)
        : kTertiaryPink;
    final Color borderColor = isFirstCard ? kBlack : _goldenBorder;
    final BoxDecoration decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderColor, width: 2),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    );
    // cardBg "1" = normal, "2" = 3rd plan style, "3" = elite/last card style
    final BoxDecoration resolvedDecoration = isElite
        ? decoration.copyWith(
            gradient: LinearGradient(
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
              stops: const [0.0, 0.31, 0.67, 1.0],
              colors: [
                const Color(0xFF0C0B0C),
                const Color(0xFF201822),
                const Color(0xFF685D3D),
                const Color(0xFFF5D7B0),
              ],
            ),
          )
        : isHighlight
        ? decoration.copyWith(
            gradient: LinearGradient(
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
              stops: const [0.0, 0.31, 0.93],
              colors: [Color(0xFF3E1E68), Color(0xFF825593), Color(0xFFFFACAC)],
            ),
          )
        : decoration.copyWith(color: kWhite);

    final priceDisplay = plan.price.isNotEmpty ? '₹${plan.price}' : '';
    final useBlueCheckmark = isFirstCard && !useDarkCard;

    final hasBadges = badgeSvgs.isNotEmpty;
    final topPadding = hasBadges ? 16.0 + (badgeSvgs.length * 36.0) : 16.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
          decoration: resolvedDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      plan.planName,
                      style: TextStyle(
                        fontSize: getProportionateScreenWidth(20),
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                  if (priceDisplay.isNotEmpty)
                    Text(
                      priceDisplay,
                      style: TextStyle(
                        fontSize: getProportionateScreenWidth(18),
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                ],
              ),
              Divider(),
              Text(
                plan.shortDescription,
                style: TextStyle(
                  fontSize: getProportionateScreenWidth(13),
                  color: descColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Divider(),
              SizedBox(height: 6),
              ...plan.features.map(
                (f) => _FeatureRow(
                  text: f,
                  color: textColor,
                  useBlueCheckmark: useBlueCheckmark,
                  pointIconUrl: plan.pointIcon,
                ),
              ),
              if (!isActive && onSubscribe != null) ...[
                SizedBox(height: 12),
                Align(
                  alignment: Alignment.bottomRight,
                  child: _SubscribeButton(
                    isGolden: isHighlight || isElite,
                    isLoading: isSubscribing,
                    enabled: canSubscribe,
                    onPressed: canSubscribe ? onSubscribe : null,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (hasBadges)
          Positioned(
            top: -8,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < badgeSvgs.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i < badgeSvgs.length - 1 ? 6 : 0,
                    ),
                    child: _PlanBadgeSvg(svgAsset: badgeSvgs[i]),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Feature row: icon from pointIcon URL (Firebase Storage) or fallback to checkmark SVG
class _FeatureRow extends StatelessWidget {
  final String text;
  final Color color;
  final bool useBlueCheckmark;
  final String? pointIconUrl;

  const _FeatureRow({
    required this.text,
    required this.color,
    required this.useBlueCheckmark,
    this.pointIconUrl,
  });

  @override
  Widget build(BuildContext context) {
    final checkAsset = useBlueCheckmark
        ? "assets/subscriptions/blue_checkmark.svg"
        : "assets/subscriptions/golden_checkmark.svg";
    final iconSize = 18.0;
    final iconWidget = pointIconUrl != null && pointIconUrl!.isNotEmpty
        ? ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CachedNetworkImage(
              imageUrl: pointIconUrl!,
              width: iconSize,
              height: iconSize,
              fit: BoxFit.contain,
              placeholder: (_, __) => SizedBox(
                width: iconSize,
                height: iconSize,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              ),
              errorWidget: (_, __, ___) => SvgPicture.asset(
                checkAsset,
                width: iconSize,
                height: iconSize,
                fit: BoxFit.contain,
              ),
            ),
          )
        : SvgPicture.asset(
            checkAsset,
            width: iconSize,
            height: iconSize,
            fit: BoxFit.contain,
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          iconWidget,
          SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: getProportionateScreenWidth(13),
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small subscribe button: primary gradient SVG for first two plans, golden SVG for remaining two; right-aligned
class _SubscribeButton extends StatefulWidget {
  final bool isGolden;
  final bool isLoading;
  final bool enabled;
  final VoidCallback? onPressed;

  const _SubscribeButton({
    required this.isGolden,
    required this.isLoading,
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<_SubscribeButton> createState() => _SubscribeButtonState();
}

class _SubscribeButtonState extends State<_SubscribeButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final asset = widget.isGolden
        ? "assets/subscriptions/golden_button.svg"
        : "assets/subscriptions/primary_gradient_button.svg";
    final canTap =
        widget.enabled && !widget.isLoading && widget.onPressed != null;
    return Material(
      color: Colors.transparent,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: canTap ? 1 : 0.8,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 90),
          scale: _pressed ? 0.97 : 1.0,
          child: InkWell(
            onTap: canTap ? widget.onPressed : null,
            onHighlightChanged: (v) {
              if (!mounted) return;
              setState(() => _pressed = v);
            },
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SvgPicture.asset(
                  asset,
                  height: getProportionateScreenHeight(28),
                  fit: BoxFit.fitHeight,
                ),
                if (widget.isLoading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.isGolden ? kBlack : kWhite,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
