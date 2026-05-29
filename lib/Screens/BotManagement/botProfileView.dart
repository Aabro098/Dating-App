import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:viora/Screens/PhotoView/photovioew.dart';
import 'package:viora/Services/NotificationService.dart';
import 'package:viora/components/icon_btn_with_counter.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:flutter/material.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/models/ProfileAction.dart';
import 'package:viora/utils/helpers/image_helper.dart';
import '../../constants.dart';
import '../../size_config.dart';
import 'botMessageScreen.dart';

class BotProfileView extends StatefulWidget {
  String uid;
  UserDetails bot;

  /// If true, skip sending notification (navigated from notification click)
  final bool fromNotification;

  BotProfileView({
    required this.uid,
    required this.bot,
    this.fromNotification = false,
  });

  @override
  _BotProfileViewState createState() => _BotProfileViewState();
}

class _BotProfileViewState extends State<BotProfileView> {
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    isLoading = true;
    getUser();
  }

  late bool isLoading;
  late UserDetails user;
  final _pageController = PageController();

  Future<void> getUser() async {
    CollectionReference collectionReference = FirebaseFirestore.instance
        .collection("Users");

    await collectionReference.doc(widget.uid).get().then((value) {
      user = UserDetails.fromJson(value.data() as Map<String, dynamic>);

      // Only send notification if not navigated from notification click
      if (!widget.fromNotification) {
        debugPrint(
          '🔔 [BOT] Sending view notification: ${widget.bot.name} viewing ${user.name}',
        );
        NotificationService.addBotNotification(
          widget.uid,
          user.fcmToken,
          "View",
          widget.bot,
        );
      } else {
        debugPrint(
          '🔔 [BOT] Skipping notification - navigated from notification click',
        );
      }
    });
    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                "Viewing as ${widget.bot.name}",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconBtnWithCounter(
                  svgSrc: "assets/svg/crush.svg",
                  press: () {
                    NotificationService.addBotNotification(
                      widget.uid,
                      user.fcmToken,
                      "Crush",
                      widget.bot,
                    );
                    ProfileAction action = ProfileAction(
                      date: DateTime.now(),
                      uid: widget.uid,
                    );
                    DatabaseService.addCrush(widget.bot.uid, action);
                  },
                  color: Colors.pink,
                ),
                IconBtnWithCounter(
                  svgSrc: "assets/svg/fav.svg",
                  press: () {
                    NotificationService.addBotNotification(
                      widget.uid,
                      user.fcmToken,
                      "Fav",
                      widget.bot,
                    );
                    ProfileAction action = ProfileAction(
                      date: DateTime.now(),
                      uid: widget.uid,
                    );
                    DatabaseService.addFav(widget.bot.uid, action);
                  },
                  color: Colors.red[400]!,
                ),
                IconBtnWithCounter(
                  svgSrc: "assets/svg/chat.svg",
                  press: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            BotMessagesScreen(bot: widget.bot, uId: user.uid),
                      ),
                    );
                  },
                  color: Colors.green,
                ),
              ],
            ),
          ],
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    //Image
                    Container(
                      height: getProportionateScreenHeight(450),
                      child: Stack(
                        children: [
                          user.images!.isNotEmpty
                              ? PageView(
                                  physics: BouncingScrollPhysics(),
                                  controller: _pageController,
                                  scrollDirection: Axis.horizontal,
                                  children: List.generate(
                                    user.images!.length,
                                    (int index) => GestureDetector(
                                      onTap: () {
                                        PersistentNavBarNavigator.pushNewScreen(
                                          context,
                                          screen: PhotoView(
                                            image: user.images![index],
                                          ),
                                          withNavBar: false,
                                          // OPTIONAL VALUE. True by default.
                                          pageTransitionAnimation:
                                              PageTransitionAnimation.cupertino,
                                        );
                                      },
                                      child: Container(
                                        width: double.infinity,
                                        height: double.infinity,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(10),
                                          ),
                                          child: ReactiveProfileImage(
                                            imagePath: user.images![index],
                                            gender: user.gender ?? 'male',
                                            width: double.infinity,
                                            height: double.infinity,
                                          ),
                                          // child: CachedNetworkImage(
                                          //   fit: BoxFit.cover,
                                          //   alignment: Alignment.topCenter,
                                          //   imageUrl: user.images![index],
                                          //   progressIndicatorBuilder:
                                          //       (
                                          //         context,
                                          //         url,
                                          //         downloadProgress,
                                          //       ) => Center(
                                          //         child:
                                          //             CircularProgressIndicator(
                                          //               value: downloadProgress
                                          //                   .progress,
                                          //             ),
                                          //       ),
                                          //   errorWidget:
                                          //       (context, url, error) => Center(
                                          //         child: Icon(Icons.error),
                                          //       ),
                                          // ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  width: double.infinity,
                                  height: double.infinity,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(10),
                                    ),
                                    child: ReactiveProfileImage(
                                      imagePath: '',
                                      gender: user.gender ?? 'male',
                                      width: double.infinity,
                                      height: double.infinity,
                                    ),
                                    // child: CachedNetworkImage(
                                    //   fit: BoxFit.cover,
                                    //   alignment: Alignment.topCenter,
                                    //   imageUrl: user.images!.isEmpty
                                    //       ? user.gender == "Male"
                                    //             ? kMaleUrl
                                    //             : kFemaleUrl
                                    //       : user.images![0],
                                    //   progressIndicatorBuilder:
                                    //       (
                                    //         context,
                                    //         url,
                                    //         downloadProgress,
                                    //       ) => Center(
                                    //         child: CircularProgressIndicator(
                                    //           value: downloadProgress.progress,
                                    //         ),
                                    //       ),
                                    //   errorWidget: (context, url, error) =>
                                    //       Center(child: Icon(Icons.error)),
                                    // ),
                                  ),
                                ),
                          //online Indicator
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Container(
                              margin: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.40),
                                borderRadius: BorderRadius.all(
                                  Radius.circular(10),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    user.isOnline!
                                        ? Text(
                                            "Online",
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            "Active ${timeago.format(DateTime.now().subtract(DateTime.now().difference(user.lastOnline!)))}",
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                    Icon(
                                      Icons.circle,
                                      color: user.isOnline!
                                          ? Colors.green
                                          : Colors.deepOrangeAccent,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          user.images!.length > 1
                              ? Align(
                                  alignment: Alignment.bottomLeft,
                                  child: Padding(
                                    padding: EdgeInsets.all(8.8),
                                    child: SmoothPageIndicator(
                                      controller: _pageController,
                                      count: user.images!.length,
                                      effect: ExpandingDotsEffect(
                                        activeDotColor: Colors.white,
                                        dotColor: Colors.white.withOpacity(0.5),
                                        dotHeight: 8.8,
                                        dotWidth: 12,
                                        spacing: 4.8,
                                      ),
                                    ),
                                  ),
                                )
                              : SizedBox(),

                          //Report User
                          SafeArea(
                            child: Align(
                              alignment: Alignment.topRight,
                              child: GestureDetector(
                                onTap: () {},
                                child: Container(
                                  margin: EdgeInsets.symmetric(
                                    vertical: 25,
                                    horizontal: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withOpacity(0.80),
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(10),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.report,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        Text(
                                          "Report User",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          //BackButton
                          SafeArea(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Padding(
                                padding: const EdgeInsets.all(25),
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context);
                                  },
                                  child: Icon(Icons.arrow_back_ios),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    //Details
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.person_pin,
                                size: getProportionateScreenWidth(26),
                              ),
                              Text(
                                user.name!,
                                style: TextStyle(
                                  fontSize: getProportionateScreenWidth(22),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "  ${user.age}",
                                style: TextStyle(
                                  fontSize: getProportionateScreenWidth(22),
                                  fontWeight: FontWeight.bold,
                                  color: kSecondaryColor,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: getProportionateScreenWidth(26),
                              ),
                              Text(
                                user.city!,
                                style: TextStyle(
                                  fontSize: getProportionateScreenWidth(18),
                                  color: kSecondaryColor,
                                ),
                              ),
                              Text(
                                ", ${user.state}",
                                style: TextStyle(
                                  fontSize: getProportionateScreenWidth(18),
                                  color: kSecondaryColor,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: getProportionateScreenHeight(20)),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Sexual Orientation"),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: (user.sexualOrientation ?? [])
                                    .map(
                                      (item) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                        ),
                                        child: Chip(label: Text(item)),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Marital Status"),
                              Wrap(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    child: Chip(
                                      label: Text(user.maritalStatus ?? ""),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              user.relTypes!.length > 0
                                  ? Text("Types of Relationship looking for")
                                  : SizedBox(),
                              Wrap(
                                direction: Axis.horizontal,

                                children: [
                                  for (var i in user.relTypes!)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                      ),
                                      child: Chip(label: Text(i)),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
