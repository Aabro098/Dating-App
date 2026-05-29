import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:viora/Screens/ProfileScreen/new_profile_view.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/models/NotificationData.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:flutter/material.dart';
import 'package:viora/constants.dart';
import 'package:viora/size_config.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:viora/utils/helpers/image_helper.dart';

class BotNotificationScreen extends StatefulWidget {
  final String botId;
  const BotNotificationScreen({required this.botId});

  static String routeName = "/botNotificationScreen";

  @override
  _BotNotificationScreenState createState() => _BotNotificationScreenState();
}

class _BotNotificationScreenState extends State<BotNotificationScreen> {
  late bool isLoading;
  late UserDetails bot;

  @override
  void initState() {
    super.initState();
    isLoading = true;
    getBot();
    DatabaseService.updateUserField(widget.botId, {"notiCount": 0});
  }

  getBot() {
    FirebaseFirestore.instance
        .collection("Users")
        .doc(widget.botId)
        .snapshots()
        .listen((event) {
          bot = UserDetails.fromJson(event.data() as Map<String, dynamic>);
          if (mounted) {
            setState(() {
              isLoading = false;
            });
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : FirestoreListView<Map<String, dynamic>>(
              query: FirebaseFirestore.instance
                  .collection('Users')
                  .doc(widget.botId)
                  .collection("Notifications")
                  .orderBy('date', descending: true),
              itemBuilder: (context, snapshot) {
                final notificationData = snapshot.data();
                return BotNotificationCard(
                  notificationData: NotificationData.fromJson(notificationData),
                  press: () {
                    // Navigate to viewer's profile (uid is the viewer who interacted with bot)
                    PersistentNavBarNavigator.pushNewScreen(
                      context,
                      screen: NewProfileView(
                        uid: notificationData["uid"],
                        canPop: true,
                      ),
                      withNavBar: false,
                      pageTransitionAnimation:
                          PageTransitionAnimation.cupertino,
                    );
                  },
                );
              },
              loadingBuilder: (context) =>
                  const Center(child: CircularProgressIndicator()),
              emptyBuilder: (context) =>
                  const Center(child: Text("No Notifications")),
            ),
    );
  }

  AppBar buildAppBar() {
    return isLoading
        ? AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: kPrimaryColor,
          )
        : AppBar(
            iconTheme: const IconThemeData(color: Colors.white),
            automaticallyImplyLeading: false,
            backgroundColor: kPrimaryColor,
            title: Row(
              children: [
                const BackButton(),
                ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(30)),
                  child: ReactiveProfileImage(
                    imagePath: bot.images!.isEmpty ? '' : bot.images![0],
                    gender: bot.gender ?? 'male',
                    width: 45,
                    height: 45,
                  ),
                  // child: CachedNetworkImage(
                  //   imageUrl: bot.images!.isEmpty
                  //       ? bot.gender == "Male"
                  //             ? kMaleUrl
                  //             : kFemaleUrl
                  //       : bot.images![0],
                  //   height: 45,
                  //   width: 45,
                  //   fit: BoxFit.cover,
                  // ),
                ),
                SizedBox(width: kDefaultPadding * 0.75),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${bot.name} Notifications',
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                    Text(
                      bot.isOnline!
                          ? "Online"
                          : "Active ${timeago.format(DateTime.now().subtract(DateTime.now().difference(bot.lastOnline!)))}",
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          );
  }
}

class BotNotificationCard extends StatelessWidget {
  final NotificationData notificationData;
  final VoidCallback press;

  const BotNotificationCard({
    required this.notificationData,
    required this.press,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: press,
      child: Card(
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(30)),
                child: ReactiveProfileImage(
                  imagePath: notificationData.imgUrl,
                  gender: 'male',
                  width: 50,
                  height: 50,
                ),
                // child: Image.network(
                //   notificationData.imgUrl,
                //   height: 50,
                //   width: 50,
                //   fit: BoxFit.cover,
                // ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notificationData.type == "View"
                        ? "${notificationData.name} just viewed your profile."
                        : notificationData.type == "Fav"
                        ? "${notificationData.name} just added you in their favorites."
                        : "${notificationData.name} just had a crush on you.",
                    style: TextStyle(
                      fontSize: getProportionateScreenWidth(15),
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    timeago.format(
                      DateTime.now().subtract(
                        DateTime.now().difference(notificationData.date),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
