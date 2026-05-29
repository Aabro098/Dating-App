// import 'package:cached_network_image/cached_network_image.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter_svg/svg.dart';
// import 'package:viora/Screens/MessagesScreen/message_screen.dart';
// import 'package:viora/Services/AppConfigService.dart';
// import 'package:viora/Services/NotificationService.dart';
// import 'package:viora/components/icon_btn_with_counter.dart';
// import 'package:viora/models/ReportedUser.dart';
// import 'package:viora/models/UserDetails.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_hooks/flutter_hooks.dart';
// import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
// import 'package:smooth_page_indicator/smooth_page_indicator.dart';
// import 'package:timeago/timeago.dart' as timeago;
// import 'package:viora/utils/helpers/badge_helper.dart';
// import '../../constants.dart';
// import 'package:viora/Screens/PhotoView/photovioew.dart';
// import '../../size_config.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:viora/Services/DatabaseService.dart';
// import 'package:overlay_support/overlay_support.dart';
// import 'package:viora/models/ProfileAction.dart';

// /// Custom Hook: useUserDetails
// /// Fetches user details from Firestore for given uid and manages loading state.
// /// Separates backend calls from UI, reusable and testable.
// UserDetails? _parseUserDetails(DocumentSnapshot doc) {
//   if (!doc.exists || doc.data() == null) return null;

//   final user = UserDetails.fromJson(doc.data() as Map<String, dynamic>);
//   if (user.relTypes?.contains("Purely sexual") ?? false) {
//     user.relTypes!.remove("Purely sexual");
//   }
//   return user;
// }

// // bool isAlreadyAddedAsCrush(String otherProfileUid)  {
// //   fetchMyCrushList().then(myCrush){
// //     for (var postDoc in myCrush.docs) {
// //       if(postDoc.data()!=null) {
// //
// //         if (postDoc.get('uid') == otherProfileUid) {
// //           debugPrint("VinayCrush ${postDoc.data()}");
// //           return true;
// //         }
// //       }
// //     }
// //     return false;
// //   };
// //
// // }
// ValueNotifier<bool> useCrushOrNot(String uid) {
//   final isAlreadyCrush = useState<bool>(false);
//   useEffect(() {
//     Future<void> fetchMyCrushList() async {
//       final doc = FirebaseFirestore.instance
//           .collection("Users")
//           .doc(FirebaseAuth.instance.currentUser?.uid)
//           .collection('MyCrush');
//       QuerySnapshot myCrush = await doc.get();
//       for (var postDoc in myCrush.docs) {
//         if (postDoc.data() != null) {
//           if (postDoc.get('uid') == uid) {
//             debugPrint("VinayCrush ${postDoc.data()}");
//             isAlreadyCrush.value = true;
//           }
//         }
//       }
//     }

//     fetchMyCrushList();
//     return null;
//   }, []);
//   return isAlreadyCrush;
// }

// /// Hook to check if user is already in favorites
// ValueNotifier<bool> useFavOrNot(String uid) {
//   final isAlreadyFav = useState<bool>(false);
//   useEffect(() {
//     Future<void> fetchMyFavList() async {
//       final doc = FirebaseFirestore.instance
//           .collection("Users")
//           .doc(FirebaseAuth.instance.currentUser?.uid)
//           .collection('MyFav');
//       QuerySnapshot myFav = await doc.get();
//       for (var postDoc in myFav.docs) {
//         if (postDoc.data() != null) {
//           if (postDoc.get('uid') == uid) {
//             debugPrint("VinayFav ${postDoc.data()}");
//             isAlreadyFav.value = true;
//           }
//         }
//       }
//     }

//     fetchMyFavList();
//     return null;
//   }, []);
//   return isAlreadyFav;
// }

// Future<UserDetails?> fetchUserDetails(String uid) async {
//   final doc = await FirebaseFirestore.instance
//       .collection("Users")
//       .doc(uid)
//       .get();
//   return _parseUserDetails(doc);
// }

// // Track sent view notifications to prevent duplicates within session
// final Set<String> _sentViewNotifications = {};

// void sendViewNotification(String uid, String? fcmToken, BuildContext context) {
//   // Prevent self-views - don't add notification if viewing own profile
//   final currentUserId = FirebaseAuth.instance.currentUser?.uid;
//   if (currentUserId == null || currentUserId == uid) {
//     return; // Don't send view notification for own profile
//   }

//   // Prevent duplicate view notifications in same session
//   final key = '${currentUserId}_$uid';
//   if (_sentViewNotifications.contains(key)) {
//     debugPrint('🔔 View notification already sent to $uid in this session');
//     return;
//   }

//   if (fcmToken != null) {
//     _sentViewNotifications.add(key);
//     debugPrint('🔔 Sending view notification to $uid');
//     NotificationService.addNotification(uid, fcmToken, "View", context);
//   }
// }

// ProfileAction createProfileAction(String uid) {
//   return ProfileAction(date: DateTime.now(), uid: uid);
// }

// /// Hook that manages the user details loading and notification side effect
// UserDetails? useUserDetails(String uid, BuildContext context) {
//   final userDetails = useState<UserDetails?>(null);
//   final isLoading = useState<bool>(true);

//   useEffect(() {
//     bool isMounted = true;

//     fetchUserDetails(uid).then((user) {
//       if (isMounted && user != null) {
//         userDetails.value = user;
//         sendViewNotification(uid, user.fcmToken, context);
//         isLoading.value = false;
//       }
//     });

//     return () => isMounted = false;
//   }, [uid]);

//   return userDetails.value;
// }

// class ProfileScreen extends HookWidget {
//   final String uid;

//   ProfileScreen({required this.uid});

//   static String routeName = "/profilescreen";

//   @override
//   Widget build(BuildContext context) {
//     // Use the custom hook to fetch user details and loading state
//     final user = useUserDetails(uid, context);

//     final pageController = usePageController();

//     if (user == null) {
//       return Scaffold(body: Center(child: CircularProgressIndicator()));
//     }

//     final isAlreadyACrush = useCrushOrNot(uid);
//     final isAlreadyAFav = useFavOrNot(uid);

//     return SafeArea(
//       child: Scaffold(
//         bottomNavigationBar: Padding(
//           padding: const EdgeInsets.all(8.0),
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.spaceAround,
//             children: [
//               IconBtnWithCounter(
//                 svgSrc: isAlreadyACrush.value
//                     ? "assets/svg/crushFilled.svg"
//                     : "assets/svg/crush.svg",
//                 press: () async {
//                   // Prevent duplicate crush - check if already added
//                   if (isAlreadyACrush.value) {
//                     showSimpleNotification(
//                       Text("Already added as your Crush"),
//                       background: Colors.orange,
//                       duration: Duration(seconds: 2),
//                       position: NotificationPosition.top,
//                       slideDismiss: true,
//                       leading: Icon(Icons.info),
//                     );
//                     return;
//                   }

//                   isAlreadyACrush.value = true;
//                   showSimpleNotification(
//                     Text("Added as your Crush"),
//                     background: Colors.green,
//                     duration: Duration(seconds: 4),
//                     position: NotificationPosition.top,
//                     slideDismiss: true,
//                     leading: Icon(Icons.verified),
//                   );
//                   final action = createProfileAction(uid);
//                   DatabaseService.addCrush(
//                     FirebaseAuth.instance.currentUser!.uid,
//                     action,
//                   );
//                   NotificationService.addNotification(
//                     uid,
//                     user.fcmToken,
//                     "Crush",
//                     context,
//                   );
//                 },
//                 color: Colors.pink,
//               ),
//               IconBtnWithCounter(
//                 svgSrc: "assets/svg/fav.svg",
//                 press: () async {
//                   // Prevent duplicate favorite - check if already added
//                   if (isAlreadyAFav.value) {
//                     showSimpleNotification(
//                       Text("Already added to favorites"),
//                       background: Colors.orange,
//                       duration: Duration(seconds: 2),
//                       position: NotificationPosition.top,
//                       slideDismiss: true,
//                       leading: Icon(Icons.info),
//                     );
//                     return;
//                   }

//                   isAlreadyAFav.value = true;
//                   showSimpleNotification(
//                     Text("Added as Your favorite"),
//                     background: Colors.green,
//                     duration: Duration(seconds: 4),
//                     position: NotificationPosition.top,
//                     slideDismiss: true,
//                     leading: Icon(Icons.verified),
//                   );
//                   final action = createProfileAction(uid);
//                   DatabaseService.addFav(
//                     FirebaseAuth.instance.currentUser!.uid,
//                     action,
//                   );
//                   NotificationService.addNotification(
//                     uid,
//                     user.fcmToken,
//                     "Fav",
//                     context,
//                   );
//                 },
//                 color: Colors.red[400]!,
//               ),
//               IconBtnWithCounter(
//                 svgSrc: "assets/svg/chat.svg",
//                 press: () {
//                   PersistentNavBarNavigator.pushNewScreen(
//                     context,
//                     screen: MessagesScreen(uId: user.uid),
//                     withNavBar: false,
//                     pageTransitionAnimation: PageTransitionAnimation.cupertino,
//                   );
//                 },
//                 color: Colors.green,
//               ),
//             ],
//           ),
//         ),
//         body: SafeArea(
//           child: SingleChildScrollView(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 // Image slider with page indicator
//                 Container(
//                   height: getProportionateScreenHeight(450),
//                   child: Stack(
//                     children: [
//                       user.images!.isNotEmpty
//                           ? PageView.builder(
//                               physics: BouncingScrollPhysics(),
//                               controller: pageController,
//                               scrollDirection: Axis.horizontal,
//                               itemCount: user.images!.length,
//                               itemBuilder: (context, index) => GestureDetector(
//                                 onTap: () {
//                                   PersistentNavBarNavigator.pushNewScreen(
//                                     context,
//                                     screen: PhotoView(
//                                       image: user.images![index],
//                                     ),
//                                     withNavBar: false,
//                                     pageTransitionAnimation:
//                                         PageTransitionAnimation.cupertino,
//                                   );
//                                 },
//                                 child: ClipRRect(
//                                   borderRadius: BorderRadius.all(
//                                     Radius.circular(10),
//                                   ),
//                                   child: CachedNetworkImage(
//                                     imageUrl: user.images![index],
//                                     fit: BoxFit.cover,
//                                     alignment: Alignment.topCenter,
//                                     progressIndicatorBuilder:
//                                         (context, url, progress) => Center(
//                                           child: CircularProgressIndicator(
//                                             value: progress.progress,
//                                           ),
//                                         ),
//                                     errorWidget: (context, url, error) =>
//                                         Icon(Icons.error),
//                                   ),
//                                 ),
//                               ),
//                             )
//                           : ClipRRect(
//                               borderRadius: BorderRadius.all(
//                                 Radius.circular(10),
//                               ),
//                               child: CachedNetworkImage(
//                                 imageUrl: user.images!.isEmpty
//                                     ? (user.gender == "Male"
//                                           ? kMaleUrl
//                                           : kFemaleUrl)
//                                     : user.images![0],
//                                 fit: BoxFit.cover,
//                                 alignment: Alignment.topCenter,
//                                 progressIndicatorBuilder:
//                                     (context, url, progress) => Center(
//                                       child: CircularProgressIndicator(
//                                         value: progress.progress,
//                                       ),
//                                     ),
//                                 errorWidget: (context, url, error) =>
//                                     Icon(Icons.error),
//                               ),
//                             ),
//                       Align(
//                         alignment: Alignment.bottomRight,
//                         child: Container(
//                           margin: EdgeInsets.all(8),
//                           decoration: BoxDecoration(
//                             color: Colors.black.withOpacity(0.4),
//                             borderRadius: BorderRadius.all(Radius.circular(10)),
//                           ),
//                           child: Padding(
//                             padding: const EdgeInsets.symmetric(horizontal: 2),
//                             child: Row(
//                               mainAxisSize: MainAxisSize.min,
//                               children: [
//                                 user.isOnline!
//                                     ? Text(
//                                         "Online",
//                                         style: TextStyle(color: Colors.white),
//                                       )
//                                     : Text(
//                                         "Active ${timeago.format(DateTime.now().subtract(DateTime.now().difference(user.lastOnline!)))}",
//                                         style: TextStyle(color: Colors.white),
//                                       ),
//                                 Icon(
//                                   Icons.circle,
//                                   color: user.isOnline!
//                                       ? Colors.green
//                                       : Colors.deepOrangeAccent,
//                                   size: 16,
//                                 ),
//                               ],
//                             ),
//                           ),
//                         ),
//                       ),
//                       if (user.images!.length > 1)
//                         Align(
//                           alignment: Alignment.bottomLeft,
//                           child: Padding(
//                             padding: EdgeInsets.all(8.8),
//                             child: SmoothPageIndicator(
//                               controller: pageController,
//                               count: user.images!.length,
//                               effect: ExpandingDotsEffect(
//                                 activeDotColor: Colors.white,
//                                 dotColor: Colors.white.withOpacity(0.5),
//                                 dotHeight: 8.8,
//                                 dotWidth: 12,
//                                 spacing: 4.8,
//                               ),
//                             ),
//                           ),
//                         ),
//                       // Report User Button
//                       SafeArea(
//                         child: Align(
//                           alignment: Alignment.topRight,
//                           child: GestureDetector(
//                             onTap: () {
//                               ReportedUser report = ReportedUser(
//                                 date: DateTime.now(),
//                                 reportedByUid:
//                                     FirebaseAuth.instance.currentUser!.uid,
//                                 reportedUid: uid,
//                               );
//                               DatabaseService.reportUsers(report);
//                             },
//                             child: Container(
//                               margin: EdgeInsets.symmetric(
//                                 vertical: 25,
//                                 horizontal: 8,
//                               ),
//                               decoration: BoxDecoration(
//                                 color: Colors.redAccent.withOpacity(0.8),
//                                 borderRadius: BorderRadius.all(
//                                   Radius.circular(10),
//                                 ),
//                               ),
//                               child: Padding(
//                                 padding: const EdgeInsets.symmetric(
//                                   horizontal: 2,
//                                 ),
//                                 child: Row(
//                                   mainAxisSize: MainAxisSize.min,
//                                   children: [
//                                     Icon(
//                                       Icons.report,
//                                       color: Colors.white,
//                                       size: 18,
//                                     ),
//                                     Text(
//                                       "Report User",
//                                       style: TextStyle(color: Colors.white),
//                                     ),
//                                   ],
//                                 ),
//                               ),
//                             ),
//                           ),
//                         ),
//                       ),
//                       // Back Button
//                       SafeArea(
//                         child: Align(
//                           alignment: Alignment.topLeft,
//                           child: Padding(
//                             padding: const EdgeInsets.all(25),
//                             child: GestureDetector(
//                               onTap: () => Navigator.pop(context),
//                               child: Icon(Icons.arrow_back_ios),
//                             ),
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//                 // User Details Section
//                 Padding(
//                   padding: const EdgeInsets.all(8.0),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Row(
//                         children: [
//                           Icon(
//                             Icons.person_pin,
//                             size: getProportionateScreenWidth(26),
//                           ),
//                           Text(
//                             user.name!,
//                             style: TextStyle(
//                               fontSize: getProportionateScreenWidth(22),
//                               fontWeight: FontWeight.bold,
//                             ),
//                           ),
//                           if (user.isVerified ?? false) ...[
//                             SizedBox(width: getProportionateScreenWidth(6)),
//                             SvgPicture.network(
//                               BadgeHelper().getBadgeUrl(),
//                               width: 18,
//                               height: 18,
//                               fit: BoxFit.contain,
//                             ),

//                             // Container(
//                             //   padding: EdgeInsets.all(2),
//                             //   decoration: BoxDecoration(
//                             //     gradient: kPrimaryGradient,
//                             //     shape: BoxShape.circle,
//                             //   ),
//                             //   child: Icon(
//                             //     Icons.verified,
//                             //     color: kWhite,
//                             //     size: getProportionateScreenWidth(20),
//                             //   ),
//                             // ),
//                           ],
//                           Text(
//                             "  ${user.age}",
//                             style: TextStyle(
//                               fontSize: getProportionateScreenWidth(22),
//                               fontWeight: FontWeight.bold,
//                               color: kSecondaryColor,
//                             ),
//                           ),
//                         ],
//                       ),
//                       Row(
//                         children: [
//                           Icon(
//                             Icons.location_on,
//                             size: getProportionateScreenWidth(26),
//                           ),
//                           Text(
//                             user.city!,
//                             style: TextStyle(
//                               fontSize: getProportionateScreenWidth(18),
//                               color: kSecondaryColor,
//                             ),
//                           ),
//                           Text(
//                             ", ${user.state}",
//                             style: TextStyle(
//                               fontSize: getProportionateScreenWidth(18),
//                               color: kSecondaryColor,
//                             ),
//                           ),
//                         ],
//                       ),
//                       SizedBox(height: getProportionateScreenHeight(20)),
//                       if ((user.sexualOrientation ?? "") != [])
//                         Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Text("Sexual Orientation"),
//                             Wrap(
//                               spacing: 6,
//                               runSpacing: 6,
//                               children: (user.sexualOrientation ?? [])
//                                   .map(
//                                     (item) => Padding(
//                                       padding: const EdgeInsets.symmetric(
//                                         horizontal: 5,
//                                       ),
//                                       child: Chip(label: Text(item)),
//                                     ),
//                                   )
//                                   .toList(),
//                             ),
//                           ],
//                         ),
//                       if ((user.maritalStatus ?? "").isNotEmpty)
//                         Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Text("Marital Status"),
//                             Wrap(
//                               children: [
//                                 Padding(
//                                   padding: const EdgeInsets.symmetric(
//                                     horizontal: 5,
//                                   ),
//                                   child: Chip(label: Text(user.maritalStatus!)),
//                                 ),
//                               ],
//                             ),
//                           ],
//                         ),
//                       if ((user.relTypes?.isNotEmpty ?? false))
//                         Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Text("Types of Relationship looking for"),
//                             Wrap(
//                               direction: Axis.horizontal,
//                               children: user.relTypes!.map((rel) {
//                                 return Padding(
//                                   padding: const EdgeInsets.symmetric(
//                                     horizontal: 5,
//                                   ),
//                                   child: Chip(label: Text(rel)),
//                                 );
//                               }).toList(),
//                             ),
//                           ],
//                         ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
