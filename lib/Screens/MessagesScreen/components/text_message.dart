import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:viora/Screens/PaymentScreen/payment_screen.dart';
import 'package:viora/Screens/PhotoView/photovioew.dart';
import 'package:viora/Services/SubscriptionService.dart';
import 'package:viora/components/reusable_dialog.dart';
import 'package:viora/size_config.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:viora/utils/constatnts/colors.dart';
import 'package:viora/utils/helpers/image_helper.dart';
import '../../../constants.dart';

class TextMessage extends StatefulWidget {
  const TextMessage({
    super.key,
    required this.message,
    required this.isSender,
    required this.time,
    this.isSeen = false,
    this.imagePath,
    this.isSupportMessage = false,
    this.gender,
  });

  final String message;
  final bool isSender;
  final DateTime time;
  final bool? isSeen;
  final List<String>? imagePath;
  final bool isSupportMessage;
  final String? gender;

  @override
  TextMessageState createState() => TextMessageState();
}

class TextMessageState extends State<TextMessage> {
  bool? _isFreeImageFeatureEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkCanViewImages();
    });
    // Listen to Firestore subscription/current doc for realtime updates.
    _subscribeToSubscriptionChanges();
  }

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _subscriptionListener;

  final DateFormat formatterdate = DateFormat('hh:mm a');
  bool canViewImages = false;

  Future<bool> _resolveFreeImageFeatureEnabled() async {
    if (widget.isSupportMessage) return true;

    final doc = await FirebaseFirestore.instance
        .collection('Subscriptions')
        .doc('freeFeatures')
        .get();
    final data = doc.data();

    final genderKey = widget.gender?.toLowerCase() == "female"
        ? "female"
        : "male";
    final gender = data?[genderKey] as Map<String, dynamic>?;
    final isEnabled = gender?['isEnable'] as bool? ?? false;

    if (!isEnabled) return false;

    final features = gender?['features'] as Map<String, dynamic>?;
    final viewImage = features?['image_view'] as Map<String, dynamic>?;
    return viewImage?['enabled'] == true;
  }

  Future<bool> _resolveCanViewImages() async {
    final freeImageFeatureEnabled =
        _isFreeImageFeatureEnabled ?? await _resolveFreeImageFeatureEnabled();
    _isFreeImageFeatureEnabled = freeImageFeatureEnabled;

    if (freeImageFeatureEnabled) return true;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final subInfo = await SubscriptionService.getSubscriptionDisplayInfo(
      uid,
      forceRefresh: true,
    );
    if (subInfo?.isActive != true) return false;

    return subInfo?.entitlementFeatures?.isFeatureEnabled('image_view') ??
        false;
  }

  /// Helper method to safely check if user has premium subscription
  /// Returns false if userInfo not initialized
  Future<void> checkCanViewImages() async {
    final allowed = await _resolveCanViewImages();
    if (mounted) {
      setState(() {
        canViewImages = allowed;
      });
    }
  }

  void _subscribeToSubscriptionChanges() {
    if (widget.isSupportMessage) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final ref = FirebaseFirestore.instance
          .collection('Users')
          .doc(uid)
          .collection('Subscription')
          .doc('current');
      _subscriptionListener = ref.snapshots().listen(
        (snap) async {
          _isFreeImageFeatureEnabled ??=
              await _resolveFreeImageFeatureEnabled();
          if (_isFreeImageFeatureEnabled == true) return;

          if (!mounted) return;
          final bool allowed = await _resolveCanViewImages();
          if (allowed != canViewImages) {
            setState(() {
              canViewImages = allowed;
            });
          }
        },
        onError: (e) {
          // ignore listener errors; fallback already handled by checkCanViewImages
          if (mounted) {
            // no-op
          }
        },
      );
    } catch (e) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Column(
        crossAxisAlignment: widget.isSender
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          (widget.message.contains("vioraa.firebasestorage.app") &&
                  widget.imagePath != null)
              ? SizedBox(
                  // height: getProportionateScreenHeight(196),
                  width: getProportionateScreenWidth(196),
                  child: BuildImages(
                    images: widget.imagePath!,
                    canViewImages: canViewImages,
                    isSender: widget.isSender,
                  ),
                )
              : Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: kDefaultPadding * 0.75,
                    vertical: kDefaultPadding / 2,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isSender
                        ? AppColors.purple
                        : Color(0xFFE45A92).withAlpha(232),
                    borderRadius: widget.isSender
                        ? BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                            topLeft: Radius.circular(16),
                            bottomRight: Radius.circular(6),
                          )
                        : BorderRadius.only(
                            bottomRight: Radius.circular(16),
                            topRight: Radius.circular(16),
                            bottomLeft: Radius.circular(16),
                            topLeft: Radius.circular(6),
                          ),
                  ),
                  child: SelectableText(
                    widget.message,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
          SizedBox(height: getProportionateScreenHeight(4)),
          Row(
            children: [
              widget.isSender ? Spacer() : SizedBox(),
              Text(
                formatterdate.format(widget.time),
                style: TextStyle(fontSize: getProportionateScreenWidth(10)),
              ),
              !widget.isSender ? Spacer() : SizedBox(),
              if (widget.isSender) ...[
                SizedBox(width: getProportionateScreenWidth(4)),
                MessageStatusDot(seen: widget.isSeen ?? false),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _subscriptionListener?.cancel();
    super.dispose();
  }
}

class BuildImages extends HookWidget {
  final List<String> images;
  final bool canViewImages;
  final bool isSender;

  const BuildImages({
    super.key,
    required this.images,
    required this.canViewImages,
    required this.isSender,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return SizedBox.shrink();
    final expanded = useState<bool>(false);
    final displayImages = expanded.value ? images : images.take(4).toList();
    final remainingCount = expanded.value ? 0 : images.length - 4;

    return images.length > 1
        ? SizedBox(
            width: getProportionateScreenWidth(196),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1.0,
              children: List.generate(displayImages.length, (index) {
                final imagePath = displayImages[index];
                final isLastVisible = index == 3 && remainingCount > 0;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    GestureDetector(
                      onTap: isLastVisible
                          ? null
                          : () {
                              // Navigate to gallery with all images
                              // final userProvider = Provider.of<UserProvider>(
                              //   context,
                              //   listen: false,
                              // );
                              // final hasCoins =
                              //     userProvider.userDetails.coins! > 0;

                              if (isSender || canViewImages) {
                                PersistentNavBarNavigator.pushNewScreen(
                                  context,
                                  screen: PhotoView(image: imagePath),
                                  withNavBar: false,
                                  pageTransitionAnimation:
                                      PageTransitionAnimation.cupertino,
                                );
                              }
                              // else if (!hasCoins) {
                              //   CustomDialog.outOfCoinsDialog(context);
                              // }
                              else {
                                // ❌ No coins + inactive subscription
                                ReusableDialog.show(
                                  context,
                                  "Invalid subscription !",
                                  "Subscribe to access this feature.",
                                  "Subscribe",
                                  onConfirm: () async {
                                    await PersistentNavBarNavigator.pushNewScreen(
                                      context,
                                      screen: PaymentScreen(
                                        showArrowBack: true,
                                      ),
                                      withNavBar: false,
                                      pageTransitionAnimation:
                                          PageTransitionAnimation.cupertino,
                                    );
                                  },
                                );
                              }
                            },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ImageFiltered(
                          imageFilter: (isSender || canViewImages)
                              ? ImageFilter.blur(sigmaX: 0, sigmaY: 0)
                              : ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: ReactiveProfileImage(
                            imagePath: imagePath,
                            gender: "male",
                            height: getProportionateScreenHeight(90),
                            width: getProportionateScreenWidth(90),
                          ),
                          // child: CachedNetworkImage(
                          //   imageUrl: imagePath,
                          //   fit: BoxFit.cover,
                          //   height: getProportionateScreenHeight(90),
                          //   width: getProportionateScreenWidth(90),
                          // ),
                        ),
                      ),
                    ),
                    if (isLastVisible)
                      GestureDetector(
                        onTap: () {
                          expanded.value = !expanded.value;
                        },
                        child: Container(
                          height: getProportionateScreenHeight(24),
                          width: getProportionateScreenWidth(72),
                          decoration: BoxDecoration(
                            color: Color(0xFF686868).withAlpha(60),
                            border: Border.all(
                              color: Colors.white.withAlpha(100),
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          clipBehavior: Clip.antiAlias,
                          child: Text(
                            '+$remainingCount Images',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              }),
            ),
          )
        : GestureDetector(
            onTap: () {
              // Navigate to gallery with all images
              // final userProvider = Provider.of<UserProvider>(
              //   context,
              //   listen: false,
              // );
              // final hasCoins = userProvider.userDetails.coins! > 0;

              if (isSender || canViewImages) {
                PersistentNavBarNavigator.pushNewScreen(
                  context,
                  screen: PhotoView(image: images[0]),
                  withNavBar: false,
                  pageTransitionAnimation: PageTransitionAnimation.cupertino,
                );
              }
              //  else if (!hasCoins) {
              //   CustomDialog.outOfCoinsDialog(context);
              // }
              else {
                ReusableDialog.show(
                  context,
                  "Invalid subscription !",
                  "Subscribe to access this feature.",
                  "Subscribe",
                  onConfirm: () async {
                    await PersistentNavBarNavigator.pushNewScreen(
                      context,
                      screen: PaymentScreen(showArrowBack: true),
                      withNavBar: false,
                      pageTransitionAnimation:
                          PageTransitionAnimation.cupertino,
                    );
                  },
                );
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ImageFiltered(
                imageFilter: (isSender || canViewImages)
                    ? ImageFilter.blur(sigmaX: 0, sigmaY: 0)
                    : ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: ReactiveProfileImage(
                  imagePath: images[0],
                  width: getProportionateScreenHeight(184),
                  height: getProportionateScreenHeight(184),
                  gender: "male",
                ),
                // child: CachedNetworkImage(
                //   imageUrl: images[0],
                //   width: getProportionateScreenHeight(184),
                //   height: getProportionateScreenHeight(184),
                //   fit: BoxFit.cover,
                //   placeholder: (context, url) => Container(
                //     width: getProportionateScreenHeight(184),
                //     height: getProportionateScreenHeight(184),
                //     color: Colors.grey[300],
                //     child: Center(child: CircularProgressIndicator()),
                //   ),
                //   errorWidget: (context, url, error) => Container(
                //     width: getProportionateScreenHeight(184),
                //     height: getProportionateScreenHeight(184),
                //     color: Colors.grey[300],
                //     child: Icon(Icons.image_not_supported),
                //   ),
                // ),
              ),
            ),
          );
  }
}

class MessageStatusDot extends StatelessWidget {
  final bool seen;

  const MessageStatusDot({super.key, required this.seen});
  @override
  Widget build(BuildContext context) {
    return Icon(
      seen ? Icons.done_all : Icons.check,
      size: 18,
      color: seen ? Color(0xFF3487B9) : kSecondaryColor,
    );
  }
}
