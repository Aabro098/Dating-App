import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:viora/Screens/BotManagement/botChatScreen.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';

import 'package:viora/models/UserDetails.dart';
import 'package:viora/Screens/BotManagement/AddBot.dart';
import 'package:viora/Screens/BotManagement/BotProfile.dart';
import 'package:viora/Screens/BotManagement/BotUsersView.dart';
import 'package:viora/Screens/BotManagement/botNotifications.dart';
import 'package:viora/utils/helpers/image_helper.dart';

import '../../constants.dart';
import '../../size_config.dart';

class BotHome extends HookWidget {
  static String routeName = "/botHome";

  @override
  Widget build(BuildContext context) {
    final refreshKey = useState(DateTime.now());

    final query = FirebaseFirestore.instance
        .collection('Users')
        .where("fcmToken", isEqualTo: "Admin")
        .where("isDisabled", isEqualTo: false)
        .orderBy("joiningDate", descending: true);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),
        child: SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: kPrimaryColor,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(10),
                bottomRight: Radius.circular(10),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                  },
                  child: Container(
                    height: 57.6,
                    width: 57.6,
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9.6),
                    ),
                    child: Icon(
                      Icons.arrow_back_ios,
                      color: Colors.white,
                      size: getProportionateScreenWidth(28),
                    ),
                  ),
                ),
                Spacer(),
                Text(
                  "Bot Home",
                  style: TextStyle(
                    fontSize: getProportionateScreenWidth(20),
                    color: Colors.white,
                  ),
                ),
                Spacer(),
                GestureDetector(
                  onTap: () {
                    PersistentNavBarNavigator.pushNewScreen(
                      context,
                      screen: AddBot(),
                      withNavBar: false,
                      pageTransitionAnimation:
                          PageTransitionAnimation.cupertino,
                    );
                  },
                  child: Container(
                    height: 57.6,
                    width: 57.6,
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9.6),
                    ),
                    child: Icon(
                      Icons.add_circle,
                      color: Colors.white,
                      size: getProportionateScreenWidth(28),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          refreshKey.value =
              DateTime.now(); // triggers FirestoreQueryBuilder rebuild
        },
        child: FirestoreQueryBuilder(
          key: ValueKey(refreshKey.value),
          query: query,
          pageSize: 10,
          builder: (context, snapshot, _) {
            if (snapshot.isFetching) {
              return Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (snapshot.docs.isEmpty) {
              return Center(child: Text("No Users found"));
            }

            return GridView.builder(
              addAutomaticKeepAlives: true,
              padding: EdgeInsets.all(getProportionateScreenWidth(20)),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.75,
                crossAxisSpacing: 20.0,
                mainAxisSpacing: 20.0,
              ),
              itemCount: snapshot.docs.length,
              itemBuilder: (context, index) {
                if (snapshot.hasMore && index + 1 == snapshot.docs.length) {
                  snapshot.fetchMore();
                }
                final data = snapshot.docs[index].data();
                final user = UserDetails.fromJson(data);
                return BotCard(user: user);
              },
            );
          },
        ),
      ),
    );
  }
}

class BotCard extends StatefulWidget {
  final UserDetails user;

  BotCard({required this.user});

  @override
  _BotCardState createState() => _BotCardState();
}

class _BotCardState extends State<BotCard> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int count = 0;
  var listener;

  @override
  void initState() {
    super.initState();
    getMessageCount();
  }

  @override
  void didUpdateWidget(covariant BotCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    listener?.cancel();
    getMessageCount();
  }

  void getMessageCount() {
    listener = FirebaseFirestore.instance
        .collection("Messages")
        .where(
          "date",
          isGreaterThanOrEqualTo: DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
            0,
            0,
            0,
          ),
        )
        .where("receiver", isEqualTo: widget.user.uid)
        .where("seen", isEqualTo: false)
        .snapshots()
        .listen((event) {
          setState(() {
            count = event.size;
          });
        });
  }

  @override
  void dispose() {
    listener?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return GestureDetector(
      onTap: () {
        PersistentNavBarNavigator.pushNewScreen(
          context,
          screen: BotUsersView(bot: widget.user),
          withNavBar: false,
          pageTransitionAnimation: PageTransitionAnimation.cupertino,
        );
      },
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              child: ReactiveProfileImage(
                imagePath: widget.user.images?.isNotEmpty == true
                    ? widget.user.images![0]
                    : '',
                gender: widget.user.gender ?? 'male',
                width: double.infinity,
                height: double.infinity,
              ),
              // child: CachedNetworkImage(
              //   fit: BoxFit.cover,
              //   alignment: Alignment.topCenter,
              //   imageUrl: widget.user.images!.isEmpty
              //       ? (widget.user.gender == "Male" ? kMaleUrl : kFemaleUrl)
              //       : widget.user.images![0],
              //   progressIndicatorBuilder: (context, url, downloadProgress) =>
              //       Center(
              //         child: CircularProgressIndicator(
              //           value: downloadProgress.progress,
              //         ),
              //       ),
              //   errorWidget: (context, url, error) =>
              //       Center(child: Icon(Icons.error)),
              // ),
            ),
          ),
          Align(
            alignment: Alignment.topLeft,
            child: Container(
              margin: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.40),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.user.isOnline! ? "Online" : "Offline",
                      style: TextStyle(color: Colors.white),
                    ),
                    Icon(
                      Icons.circle,
                      color: widget.user.isOnline!
                          ? Colors.green
                          : Colors.deepOrangeAccent,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              width: double.infinity,
              color: Colors.white.withOpacity(0.90),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "${widget.user.name},${widget.user.age}",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "${widget.user.city},${widget.user.state}",
                    style: TextStyle(color: kSecondaryColor, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 5,
            bottom: 50,
            child: GestureDetector(
              onTap: () {
                PersistentNavBarNavigator.pushNewScreen(
                  context,
                  screen: BotChatsScreen(botId: widget.user.uid),
                  withNavBar: false,
                  pageTransitionAnimation: PageTransitionAnimation.cupertino,
                );
              },
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SvgPicture.asset(
                        "assets/svg/chat.svg",
                        height: 20,
                      ),
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        height: getProportionateScreenWidth(16),
                        width: getProportionateScreenWidth(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFFF4848),
                          shape: BoxShape.circle,
                          border: Border.all(width: 1.5, color: Colors.white),
                        ),
                        child: Center(
                          child: Text(
                            count > 9 ? "9+" : "$count",
                            style: TextStyle(
                              fontSize: getProportionateScreenWidth(10),
                              height: 1,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 5,
            top: 50,
            child: GestureDetector(
              onTap: () {
                PersistentNavBarNavigator.pushNewScreen(
                  context,
                  screen: BotNotificationScreen(botId: widget.user.uid),
                  withNavBar: false,
                  pageTransitionAnimation: PageTransitionAnimation.cupertino,
                );
              },
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blueAccent,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SvgPicture.asset(
                        "assets/svg/notifications.svg",
                        height: 20,
                      ),
                    ),
                  ),
                  if (widget.user.notiCount! > 0)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        height: getProportionateScreenWidth(16),
                        width: getProportionateScreenWidth(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFFF4848),
                          shape: BoxShape.circle,
                          border: Border.all(width: 1.5, color: Colors.white),
                        ),
                        child: Center(
                          child: Text(
                            widget.user.notiCount! > 9
                                ? "9+"
                                : "${widget.user.notiCount}",
                            style: TextStyle(
                              fontSize: getProportionateScreenWidth(10),
                              height: 1,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 5,
            bottom: 50,
            child: GestureDetector(
              onTap: () {
                PersistentNavBarNavigator.pushNewScreen(
                  context,
                  screen: BotProfile(botId: widget.user.uid),
                  withNavBar: false,
                  pageTransitionAnimation: PageTransitionAnimation.cupertino,
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: kPrimaryColor,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Icon(
                    CupertinoIcons.profile_circled,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
