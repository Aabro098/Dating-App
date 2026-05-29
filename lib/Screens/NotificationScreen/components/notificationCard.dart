import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:viora/Screens/ProfileScreen/new_profile_view.dart';
import 'package:viora/Screens/ProfileScreen/profileScreen.dart';
import 'package:viora/models/NotificationData.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:viora/size_config.dart';
import 'package:flutter/material.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';

import 'package:timeago/timeago.dart' as timeago;

import '../../../constants.dart';

class NotificationCard extends StatefulWidget {
  NotificationData notificationData;

  NotificationCard({required this.notificationData});

  @override
  _NotificationCardState createState() => _NotificationCardState();
}

class _NotificationCardState extends State<NotificationCard> {
  late bool isLoading;
  late UserDetails user;
  void initState() {
    // TODO: implement initState
    super.initState();
    isLoading = true;
    getUser();
  }

  @override
  void didUpdateWidget(NotificationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    getUser();
  }

  Future<void> getUser() async {
    CollectionReference collectionReference = FirebaseFirestore.instance
        .collection("Users");
    await collectionReference.doc(widget.notificationData.uid).get().then((
      value,
    ) {
      user = UserDetails.fromJson(value.data() as Map<String, dynamic>);
    });
    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return isLoading
        ? SizedBox()
        : user.isDisabled!
        ? SizedBox()
        : GestureDetector(
            onTap: () {
              PersistentNavBarNavigator.pushNewScreen(
                context,
                screen: NewProfileView(
                  uid: widget.notificationData.uid,
                  canPop: true,
                ),
                withNavBar: false, // OPTIONAL VALUE. True by default.
                pageTransitionAnimation: PageTransitionAnimation.cupertino,
              );
            },
            child: Card(
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.all(Radius.circular(30)),
                      child: CachedNetworkImage(
                        imageUrl: user.images!.isEmpty
                            ? user.gender == "Male"
                                  ? kMaleUrl
                                  : kFemaleUrl
                            : user.images![0],
                        height: 50,
                        width: 50,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.notificationData.type == "View"
                              ? "${user.name} just viewed your profile."
                              : widget.notificationData.type == "Fav"
                              ? "${user.name} just added you in there favorites."
                              : "${user.name} just had crush on you.",
                          style: TextStyle(
                            fontSize: getProportionateScreenWidth(15),
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          timeago.format(
                            DateTime.now().subtract(
                              DateTime.now().difference(
                                widget.notificationData.date,
                              ),
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

// class NotificationCard extends StatelessWidget {
//   NotificationData notificationData;
//
//   NotificationCard({this.notificationData});
//
//   @override
//   Widget build(BuildContext context) {
//     return GestureDetector(
//       onTap: () {
//         PersistentNavBarNavigator.pushNewScreen(
//           context,
//           screen: ProfileScreen(
//             uid: notificationData.uid,
//           ),
//           withNavBar: false, // OPTIONAL VALUE. True by default.
//           pageTransitionAnimation: PageTransitionAnimation.cupertino,
//         );
//       },
//       child: Card(
//         child: Row(
//           children: [
//             Padding(
//               padding: const EdgeInsets.all(8.0),
//               child: ClipRRect(
//                 borderRadius: BorderRadius.all(Radius.circular(30)),
//                 child: Image.network(
//                   notificationData.imgUrl,
//                   height: 50,
//                   width: 50,
//                   fit: BoxFit.cover,
//                 ),
//               ),
//             ),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     notificationData.type == "View"
//                         ? "${notificationData.name} just viewed your profile."
//                         : notificationData.type == "Fav"
//                             ? "${notificationData.name} just added you in there favorites."
//                             : "${notificationData.name} just had crush on you.",
//                     style: TextStyle(
//                         fontSize: getProportionateScreenWidth(15),
//                         fontWeight: FontWeight.bold,
//                         color: Colors.black),
//                   ),
//                   Text(timeago.format(DateTime.now().subtract(
//                       DateTime.now().difference(notificationData.date)))),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
