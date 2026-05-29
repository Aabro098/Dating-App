import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:viora/Services/NotificationService.dart';
import 'package:viora/Services/user_service.dart';
import 'package:viora/models/ReportedUser.dart';
import 'package:viora/models/PlanTransaction.dart';
import 'package:viora/models/Spamer.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:viora/models/CoinPlan.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:viora/models/ProfileAction.dart';

import '../Screens/Home/home.dart';
import 'Global.dart';
import 'exceptions/exceptions.dart';

class DatabaseService {
  // static Future<void> handleUser(String uid, context) async {
  //   PurchaseApi.init();
  //   CollectionReference collectionReference =
  //       FirebaseFirestore.instance.collection("Users");
  //
  //   collectionReference.doc(uid).get().then((value) {
  //     if (value.exists) {
  //       addToken();
  //       DatabaseService.getUser().then((value) async {
  //         if(userDetails.isDisabled){
  //           await handleOnlineStatue(false);
  //           await FirebaseAuth.instance.signOut();
  //           GoogleSignIn().signOut();
  //(
  //           Navigator.pushNamedAndRemoveUntil(context, LoginScreen.routeName,
  //                   (Route<dynamic> route) => false);
  //           showSimpleNotification(
  //             Text("Your Account is Disabled/Deleted"),
  //             background: Colors.redAccent,
  //             duration: Duration(seconds: 10),
  //             position: NotificationPosition.top,
  //             slideDismiss: true,
  //             leading: Icon(Icons.close),
  //           );
  //         }
  //
  //       else  {
  //           Navigator.pushNamedAndRemoveUntil(
  //               context, Home.routeName, (Route<dynamic> route) => false);
  //         }
  //       });
  //     } else
  //       Navigator.pushNamedAndRemoveUntil(context, CompleteProfile.routeName,
  //           (Route<dynamic> route) => false);
  //   });
  //   // Trigger the authentication flow
  // }

  // Only showing the modified addUser method - rest of the file remains the same

  static Future<void> addUser(UserDetails user, BuildContext context) async {
    try {
      final globals = Globals.of(context);
      late String deviceId;
      if (globals.androidDeviceInfo != null) {
        deviceId = globals.androidDeviceInfo!.id;
      } else if (globals.iosDeviceInfo != null) {
        deviceId = globals.iosDeviceInfo!.identifierForVendor!;
      }

      CollectionReference collectionReferenceDevices = FirebaseFirestore
          .instance
          .collection("Devices");

      // Check device and set coins (don't block profile create if Devices write fails)
      try {
        final deviceDoc = await collectionReferenceDevices.doc(deviceId).get();
        if (deviceDoc.exists) {
          user.coins = 0;
        } else {
          user.coins = 10;
          await collectionReferenceDevices.doc(deviceId).set({
            "uid": FirebaseAuth.instance.currentUser!.uid,
            "date": DateTime.now(),
          });
        }
      } catch (e) {
        debugPrint('DatabaseService.addUser: Devices write skipped: $e');
        user.coins = user.coins ?? 10;
      }

      // Set user data
      String uid = FirebaseAuth.instance.currentUser!.uid;
      user.uid = uid;
      user.isOnline = true;
      user.lastOnline = DateTime.now();
      user.relTypes = [];
      user.images = [];
      user.safetyTipsVersion = 0; // Initialize safety tips version for new user

      CollectionReference collectionReference = FirebaseFirestore.instance
          .collection("Users");

      // 🔥 Create user document (ensure uid is in payload for consistency)
      final userData = user.toJson();
      userData['uid'] = uid;
      await collectionReference.doc(uid).set(userData);
      debugPrint("vinay i called prefs set from adduser->DatabaseService");
      globals.userProvider.userDetails = user;
      globals.prefs.userDetails.set(user);

      print("User document created successfully");

      // 🔥 Now initialize user data through Globals
      final hasProfile = await globals.initializeUserData(context, false);

      if (hasProfile) {
        print("User initialization complete - navigating to home");

        // Check for and restore deleted account subscription
        try {
          final deletedAccountDoc =
              await UserService.getDeletedAccountForRestoration(user.uid);
          if (deletedAccountDoc != null) {
            _log('🔄 Deleted account found for uid: ${user.uid}');
            final restored =
                await UserService.restoreSubscriptionFromDeletedAccount(
                  user.uid,
                  deletedAccountDoc,
                );
            if (restored) {
              _log('✅ Subscription restored from deleted account');
            }
          }
        } catch (e) {
          _log('⚠️ Error restoring deleted account subscription: $e');
        }
        // Navigation will be handled by the calling screen
        // or you can navigate here if needed
        Navigator.pushNamedAndRemoveUntil(
          context,
          Home.routeName,
          (Route<dynamic> route) => false,
        );
      }
    } catch (e, stackTrace) {
      _log("Error adding user");
      ErrorHandler.handle(context, e, stackTrace);
      rethrow;
    }
  }

  // static UserDetails userDetails;
  late List<UserDetails> fetchedUsers;
  late List<DocumentSnapshot> documents;

  //Fetch User Menu Screen
  //   static Future<void> getUser() async {
  //     String uid = FirebaseAuth.instance.currentUser.uid;
  //
  //     CollectionReference collectionReference =
  //         FirebaseFirestore.instance.collection("Users");
  //
  //     await collectionReference.doc(uid).get().then((value) {
  //       userDetails = UserDetails.fromJson(value.data());
  //     });
  //
  //
  //
  //   }

  static Future<void> getMessageCount(uid) async {
    try {
      final value = await FirebaseFirestore.instance
          .collection("Messages")
          .where("uid", isEqualTo: uid)
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Failed to get message count');
            },
          );

      _log("${value.size} messages");
      showSimpleNotification(
        Text("${value.size.toString()} Messages"),
        background: Colors.green,
        duration: Duration(seconds: 2),
        position: NotificationPosition.bottom,
        slideDismiss: true,
        leading: Icon(Icons.verified),
      );
    } catch (e, stackTrace) {
      _log('Error getting message count: $e');
      final appException = ErrorHandler.convert(e, stackTrace);
      _log('Converted to: ${appException.runtimeType}');
    }
  }

  //online offline feature
  static Future<void> handleOnlineStatue(bool status) async {
    try {
      if (FirebaseAuth.instance.currentUser != null) {
        String uid = FirebaseAuth.instance.currentUser!.uid;

        var user = await FirebaseFirestore.instance
            .collection("Users")
            .doc(uid)
            .get()
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                throw TimeoutException('Failed to check user document');
              },
            );
        if (user.exists) {
          CollectionReference collectionReference = FirebaseFirestore.instance
              .collection("Users");
          DateTime now = DateTime.now();
          Map<String, dynamic> online = {'isOnline': status};
          Map<String, dynamic> offline = {
            'isOnline': status,
            'lastOnline': now,
          };
          await collectionReference
              .doc(uid)
              .update(status ? online : offline)
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () {
                  throw TimeoutException('Failed to update online status');
                },
              )
              .whenComplete(() {
                _log("Status updated");
              });
        } else {
          _log('User document not found, skipping online status update');
        }
      }
    } catch (e, stackTrace) {
      _log('Error in handleOnlineStatue: $e');
      final appException = ErrorHandler.convert(e, stackTrace);
      _log('Converted to: ${appException.runtimeType}');
      // Don't rethrow - this is cleanup, not critical
    }
  }

  static void updateField(Map<String, dynamic> data) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _log('Cannot update field - user not authenticated');
        return;
      }

      await FirebaseFirestore.instance
          .runTransaction((transaction) async {
            String uid = currentUser.uid;
            CollectionReference collectionReference = FirebaseFirestore.instance
                .collection("Users");

            await collectionReference.doc(uid).update(data).whenComplete(() {
              _log("Field update done");
            });
          })
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Failed to update field');
            },
          );
    } catch (e, stackTrace) {
      _log('Error in updateField: $e');
      final appException = ErrorHandler.convert(e, stackTrace);
      _log('Converted to: ${appException.runtimeType}');
      // Don't rethrow - this might be called during cleanup
    }
  }

  static void updateUserField(userId, Map<String, dynamic> data) async {
    try {
      await FirebaseFirestore.instance
          .runTransaction((transaction) async {
            CollectionReference collectionReference = FirebaseFirestore.instance
                .collection("Users");

            await collectionReference.doc(userId).update(data).whenComplete(() {
              _log("User field update done");
            });
          })
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Failed to update user field');
            },
          );
    } catch (e, stackTrace) {
      _log('Error in updateUserField: $e');
      final appException = ErrorHandler.convert(e, stackTrace);
      _log('Converted to: ${appException.runtimeType}');
      // Don't rethrow - this might be called during cleanup
    }
  }

  static Future<void> markIncomingProfileActionSeen(
    String viewerId,
    String profileId,
  ) async {
    if (viewerId.isEmpty || profileId.isEmpty || viewerId == profileId) {
      return;
    }

    final firestore = FirebaseFirestore.instance;
    final refs = <DocumentReference<Map<String, dynamic>>>[
      firestore
          .collection('Users')
          .doc(viewerId)
          .collection('MyCrush')
          .doc(profileId),
      firestore
          .collection('Users')
          .doc(viewerId)
          .collection('MyFav')
          .doc(profileId),
      firestore
          .collection('Users')
          .doc(viewerId)
          .collection('CrushOnMe')
          .doc(profileId),
      firestore
          .collection('Users')
          .doc(viewerId)
          .collection('FavOnMe')
          .doc(profileId),
      firestore
          .collection('Users')
          .doc(viewerId)
          .collection('Notifications')
          .doc('${profileId}View'),
    ];

    for (final ref in refs) {
      final snapshot = await ref.get();
      if (snapshot.exists && snapshot.data()?['seen'] != true) {
        await ref.update({'seen': true});
      }
    }
  }

  /// Marks profile actions as seen with priority:
  /// Priority is used only for COUNTING (unseen count), not for marking
  ///
  /// When a user views someone's profile:
  /// 1. Mark ALL incoming actions as seen (crush, fav, view)
  /// 2. This acknowledges that the user has now seen this person
  /// 3. Priority logic is only for counting to avoid duplicates
  static Future<void> markIncomingProfileActionSeenWithPriority(
    String viewerId,
    String profileId,
  ) async {
    if (viewerId.isEmpty || profileId.isEmpty || viewerId == profileId) {
      return;
    }

    final firestore = FirebaseFirestore.instance;

    // Mark ALL incoming actions as seen (crush, fav, view)
    // This ensures complete acknowledgment of the profile visit
    try {
      final crushDoc = await firestore
          .collection('Users')
          .doc(viewerId)
          .collection('CrushOnMe')
          .doc(profileId)
          .get();

      if (crushDoc.exists && crushDoc.data()?['seen'] != true) {
        await crushDoc.reference.update({'seen': true});
      }
    } catch (e) {
      debugPrint('Error marking crush as seen: $e');
    }

    try {
      final favDoc = await firestore
          .collection('Users')
          .doc(viewerId)
          .collection('FavOnMe')
          .doc(profileId)
          .get();

      if (favDoc.exists && favDoc.data()?['seen'] != true) {
        await favDoc.reference.update({'seen': true});
      }
    } catch (e) {
      debugPrint('Error marking fav as seen: $e');
    }

    try {
      // ALWAYS mark view notifications as seen when visiting profile
      // Don't skip just because there's a crush/fav
      // This ensures all acknowledgments are marked
      final viewNotifDoc = await firestore
          .collection('Users')
          .doc(viewerId)
          .collection('Notifications')
          .doc('${profileId}View')
          .get();

      if (viewNotifDoc.exists && viewNotifDoc.data()?['seen'] != true) {
        await viewNotifDoc.reference.update({'seen': true});
      }
    } catch (e) {
      debugPrint('Error marking view as seen: $e');
    }
  }

  //FCM Tokens Handling
  static addToken() async {
    try {
      FirebaseMessaging fcm = FirebaseMessaging.instance;
      String? token;

      if (Platform.isIOS) {
        // iOS specific handling
        try {
          // Request notification permissions first
          await fcm.requestPermission(alert: true, badge: true, sound: true);

          // Try to get APNS token
          String? apnsToken = await fcm.getAPNSToken();
          if (apnsToken != null) {
            token = await fcm.getToken();
          } else {
            print("vinay APNS token not available - skipping FCM token");
            return; // Exit gracefully for simulators
          }
        } catch (e) {
          print("vinay iOS FCM setup failed: $e");
          return; // Exit gracefully
        }
      } else {
        // Android handling - check if permission is granted and add token directly
        final status = await Permission.notification.status;
        if (status.isGranted) {
          token = await fcm.getToken();
          if (token == null || token.length < 100) {
            print("🔔 FCM: Invalid token from DatabaseService.addToken()");
            return;
          }
          print(
            "🔔 FCM: Got token from DatabaseService.addToken(): ${token.substring(0, 20)}... (${token.length} chars)",
          );
        } else {
          // Permission not granted - FCMService will handle this later
          print(
            "🔔 FCM: Permission not granted yet - FCMService will handle token",
          );
          return;
        }
      }

      if (token != null) {
        String uid = FirebaseAuth.instance.currentUser!.uid;

        CollectionReference collectionReference = FirebaseFirestore.instance
            .collection("Users");

        FirebaseFirestore.instance.runTransaction((Transaction tx) async {
          await collectionReference
              .doc(uid)
              .update({"fcmToken": token})
              .whenComplete(() {
                print("Vinay FCM Token Added Successfully");
              });
        });
      }
    } catch (e) {
      print("vinay Error in addToken: $e");
      // Don't rethrow - let initialization continue
    }
  }

  static deleteToken() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        debugPrint('⚠️ No current user, skipping token deletion');
        return;
      }

      CollectionReference collectionReference = FirebaseFirestore.instance
          .collection("Users");

      await FirebaseFirestore.instance.runTransaction((Transaction tx) async {
        // Check if document exists before updating
        final docSnapshot = await tx.get(
          collectionReference.doc(currentUser.uid),
        );
        if (docSnapshot.exists) {
          await tx.update(
            collectionReference.doc(currentUser.uid),
            {"fcmToken": null}, // Use actual null, not string "null"
          );
        } else {
          debugPrint('⚠️ User document not found, skipping token deletion');
        }
      });
    } catch (e) {
      debugPrint('Error in deleteToken: $e');
      // Don't rethrow - this is cleanup, not critical
    }
  }

  static addTransaction(PlanTransaction pt) async {
    var db = FirebaseFirestore.instance;

    var batch = db.batch();
    batch.set(db.collection("Transactions").doc(pt.transactionId), pt.toJson());
    batch.update(
      db.collection("Users").doc(FirebaseAuth.instance.currentUser!.uid),
      {"coins": FieldValue.increment(pt.coins)},
    );
    batch.commit();

    showSimpleNotification(
      Text("Coins Added Successfully"),
      // leading: NotificationBadge(totalNotifications: _totalNotifications),
      background: Colors.green,
      duration: Duration(seconds: 4),
      position: NotificationPosition.bottom,
      slideDismiss: true,
      leading: Icon(Icons.verified_outlined),
    );

    NotificationService.sendAdminNotification(
      "Someone just Purchased Coins",
      "${pt.coins} for ${pt.price}",
      pt.uId,
    );
  }

  static reportUsers(ReportedUser user, BuildContext context) async {
    var user1 = user.reportedByUid; // UID of user 1
    var user2 = user.reportedUid;
    var path = user1.codeUnitAt(0) < user2.codeUnitAt(0)
        ? user1 + "_" + user2
        : user2 + "_" + user1;

    var db = FirebaseFirestore.instance;

    var batch = db.batch();
    batch.set(db.collection("ReportedUsers").doc(path), user.toJson());
    batch.commit();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(left: 16, right: 16, bottom: 24),
        backgroundColor: Color(0xFF39B432),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14.r),
          side: BorderSide(color: Colors.white, width: 1),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified, color: Colors.white),
                SizedBox(width: 8.w),
                Text(
                  "Profile Reported Successfully!",
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            Text(
              "We will investigate the profile soon.",
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
    // showSimpleNotification(
    //   Text("Profile Reported Successfully"),
    //   subtitle: Text("We will Investigate the profile Soon"),
    //   // leading: NotificationBadge(totalNotifications: _totalNotifications),
    //   background: Colors.green,
    //   duration: Duration(seconds: 4),
    //   position: NotificationPosition.bottom,
    //   slideDismiss: true,
    //   leading: Icon(Icons.verified_outlined),
    // );

    NotificationService.sendAdminNotification(
      "Report ",
      "Someone just reported a profile",
      user.reportedUid,
    );
  }

  //Bots Addition
  static addBot(context, UserDetails bot) async {
    FirebaseFirestore.instance.runTransaction((Transaction tx) async {
      CollectionReference collectionReference = FirebaseFirestore.instance
          .collection("Users");
      String path = collectionReference.doc().id;
      bot.uid = path;

      await collectionReference.doc(path).set(bot.toJson()).whenComplete(() {
        showSimpleNotification(
          Text("Bot Added Successfully"),

          // leading: NotificationBadge(totalNotifications: _totalNotifications),
          background: Colors.green,
          duration: Duration(seconds: 2),
          position: NotificationPosition.bottom,
          slideDismiss: true,
          leading: Icon(Icons.verified),
        );
      });
    });
  }

  static addBots() async {
    users.forEach((element) {
      FirebaseFirestore.instance.runTransaction((Transaction tx) async {
        CollectionReference collectionReference = FirebaseFirestore.instance
            .collection("Users");
        String path = collectionReference.doc().id;
        element.uid = path;

        await collectionReference.doc(path).set(element.toJson()).whenComplete(
          () {
            print("Done");
          },
        );
      });
    });
  }

  //Bots
  static List<UserDetails> users = [
    UserDetails(
      coins: 0,
      isDisabled: false,
      state: "MP",
      city: "Guna",
      age: 18,
      joiningDate: DateTime.now().subtract(Duration(days: 10)),
      images: [
        "https://c6oxm85c.cloudimg.io/cdno/n/q85/https://az617363.vo.msecnd.net/imgmodels/models/MD10003122/anastasia7af6bab9cba575d3f3fdac9ca9f94ee3_thumb.jpg",
      ],
      name: "Jiya",
      fcmToken: "Admin",
      gender: "Female",
      isOnline: false,
      lastOnline: DateTime.now().subtract(Duration(days: 10)),
      maritalStatus: '',
      sexualOrientation: [],
      relTypes: [],
      isTyping: '',
      notiCount: 0,
      unseenCount: 0,
      // maritalStatusline: '',
    ),
    UserDetails(
      coins: 0,
      isDisabled: false,
      state: "UP",
      city: "Bihar",
      age: 22,
      joiningDate: DateTime.now().subtract(Duration(days: 5)),
      images: [
        "https://mediaslide-europe.storage.googleapis.com/immmodels/pictures/1503/3307/profile-1621352876-8f925c4c723cfd714f6630e0df70fea4.jpg",
      ],
      name: "Siya Kumari",
      fcmToken: "Admin",
      gender: "Female",
      isOnline: true,
      lastOnline: DateTime.now().subtract(Duration(days: 2)),
      // maritalStatusline: '',
      sexualOrientation: [],
      relTypes: [],
      isTyping: '',
      notiCount: 0,
      unseenCount: 0,
      maritalStatus: '',
    ),
    UserDetails(
      coins: 0,
      isDisabled: false,
      state: "Himachal Pradesh",
      city: "Manali",
      age: 19,
      joiningDate: DateTime.now().subtract(Duration(days: 8)),
      images: [
        "https://upload.wikimedia.org/wikipedia/commons/thumb/8/8e/Adriana_Lima_2019_by_Glenn_Francis.jpg/1200px-Adriana_Lima_2019_by_Glenn_Francis.jpg",
      ],
      name: "Preeti Singh",
      fcmToken: "Admin",
      gender: "Female",
      isOnline: true,
      lastOnline: DateTime.now().subtract(Duration(days: 7)),
      maritalStatus: '',
      sexualOrientation: [],
      relTypes: [],
      isTyping: '',
      notiCount: 0,
      unseenCount: 0,
      // maritalStatusline: ''
    ),
    UserDetails(
      coins: 0,
      isDisabled: false,
      state: "Rajasthan",
      city: "Jaipur",
      age: 23,
      joiningDate: DateTime.now().subtract(Duration(days: 6)),
      images: [
        "https://imgix.ranker.com/user_node_img/80/1595588/original/miranda-kerr-photo-u289?auto=format&q=60&fit=crop&fm=pjpg&w=375",
      ],
      name: "Reeta Kumari",
      fcmToken: "Admin",
      gender: "Female",
      isOnline: true,
      lastOnline: DateTime.now().subtract(Duration(days: 5)),
      maritalStatus: '',
      sexualOrientation: [],
      relTypes: [],
      isTyping: '',
      notiCount: 0,
      unseenCount: 0,
      // maritalStatusline: ''
    ),
    UserDetails(
      coins: 0,
      isDisabled: false,
      state: "MP",
      city: "Guna",
      age: 18,
      joiningDate: DateTime.now().subtract(Duration(days: 10)),
      images: [
        "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcScUuYnFczUXKpo8SDh1m0jp2-hAkeOO3BlQw&usqp=CAU",
      ],
      name: "Arpit Singh",
      fcmToken: "Admin",
      gender: "Male",
      isOnline: false,
      lastOnline: DateTime.now().subtract(Duration(days: 10)),
      maritalStatus: '',
      sexualOrientation: [],
      relTypes: [],
      isTyping: '',
      notiCount: 0,
      unseenCount: 0,
      // maritalStatusline: ''
    ),
    UserDetails(
      coins: 0,
      isDisabled: false,
      state: "Gujrat",
      city: "kach",
      age: 18,
      joiningDate: DateTime.now().subtract(Duration(days: 12)),
      images: [
        "https://www.modelmanagement.com/blog/wp-content/uploads/2020/09/mario-rodriguez.png",
      ],
      name: "Ajeet Kumar",
      fcmToken: "Admin",
      gender: "Male",
      isOnline: true,
      lastOnline: DateTime.now().subtract(Duration(days: 5)),
      maritalStatus: '',
      sexualOrientation: [],
      relTypes: [],
      isTyping: '',
      notiCount: 0,
      unseenCount: 0,
      // maritalStatusline: ''
    ),
    UserDetails(
      coins: 0,
      isDisabled: false,
      state: "Delhi",
      city: "delhi",
      age: 18,
      joiningDate: DateTime.now().subtract(Duration(days: 7)),
      images: [
        "https://media.gq.com/photos/56d75ae39acdcf20275f0f4e/master/w_400%2Cc_limit/1-courtesy%2520of%2520Gucci.jpg",
      ],
      name: "Shiva Chouhan",
      fcmToken: "Admin",
      gender: "Male",
      isOnline: false,
      lastOnline: DateTime.now().subtract(Duration(days: 5)),
      maritalStatus: '',
      sexualOrientation: [],
      relTypes: [],
      isTyping: '',
      notiCount: 0,
      unseenCount: 0,
      // maritalStatusline: ''
    ),
    UserDetails(
      coins: 0,
      isDisabled: false,
      state: "Mumbai",
      city: "Maharashtra",
      age: 25,
      joiningDate: DateTime.now().subtract(Duration(days: 10)),
      images: [
        "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcT00rejWha1fvpXc8Njcbd4oSt27V8EDKosCA&usqp=CAU",
      ],
      name: "Rithik Roshan",
      fcmToken: "Admin",
      gender: "Male",
      isOnline: true,
      lastOnline: DateTime.now().subtract(Duration(days: 10)),
      maritalStatus: '',
      sexualOrientation: [],
      relTypes: [],
      isTyping: '',
      notiCount: 0,
      unseenCount: 0,
      // maritalStatusline: ''
    ),
    UserDetails(
      coins: 0,
      isDisabled: false,
      state: "MP",
      city: "Indore",
      age: 18,
      joiningDate: DateTime.now().subtract(Duration(days: 8)),
      images: [
        "https://assets.rebelmouse.io/eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpbWFnZSI6Imh0dHBzOi8vYXNzZXRzLnJibC5tcy8yNTg5NTE5L29yaWdpbi5qcGciLCJleHBpcmVzX2F0IjoxNjc1NzEzNzgzfQ.t2eraTGQyZppDADkH1mosRIrmjCPdMGEb92byRk03Y4/img.jpg?quality=80&width=824",
      ],
      name: "Neha Sharma",
      fcmToken: "Admin",
      gender: "Female",
      isOnline: false,
      lastOnline: DateTime.now().subtract(Duration(days: 3)),
      maritalStatus: '',
      sexualOrientation: [],
      relTypes: [],
      isTyping: '',
      notiCount: 0,
      unseenCount: 0,
      // maritalStatusline: ''
    ),
    UserDetails(
      coins: 0,
      isDisabled: false,
      state: "MP",
      city: "Mhow",
      age: 18,
      joiningDate: DateTime.now().subtract(Duration(days: 10)),
      images: [
        "https://c6oxm85c.cloudimg.io/cdno/n/q85/https://az617363.vo.msecnd.net/imgmodels/models/MD30001425/final_2-144_cropff8df223d05b6dd25310360576a15322_thumb.jpg",
      ],
      name: "Priya Singh",
      fcmToken: "Admin",
      gender: "Female",
      isOnline: true,
      lastOnline: DateTime.now().subtract(Duration(days: 10)),
      maritalStatus: '',
      sexualOrientation: [],
      relTypes: [],
      isTyping: '',
      notiCount: 0,
      unseenCount: 0,
      // maritalStatusline: ''
    ),
  ];

  static void addCrush(MyuserId, ProfileAction action) async {
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      CollectionReference collectionReference = FirebaseFirestore.instance
          .collection("Users")
          .doc(MyuserId)
          .collection("MyCrush");

      collectionReference.doc(action.uid).set(action.toJson());

      CollectionReference collectionReference1 = FirebaseFirestore.instance
          .collection("Users")
          .doc(action.uid)
          .collection("CrushOnMe");
      action.uid = MyuserId;
      collectionReference1.doc(action.uid).set(action.toJson());
    });

    // Trigger the authentication flow
  }

  static void addFav(MyuserId, ProfileAction action) async {
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      CollectionReference collectionReference = FirebaseFirestore.instance
          .collection("Users")
          .doc(MyuserId)
          .collection("MyFav");

      collectionReference.doc(action.uid).set(action.toJson());

      CollectionReference collectionReference1 = FirebaseFirestore.instance
          .collection("Users")
          .doc(action.uid)
          .collection("FavOnMe");
      action.uid = MyuserId;
      collectionReference1.doc(action.uid).set(action.toJson());
    });

    // Trigger the authentication flow
  }

  static void deleteFav(favUid) async {
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      CollectionReference collectionReference = FirebaseFirestore.instance
          .collection("Users")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection("MyFav");

      collectionReference.doc(favUid).delete();

      CollectionReference collectionReference1 = FirebaseFirestore.instance
          .collection("Users")
          .doc(favUid)
          .collection("FavOnMe");

      collectionReference1.doc(FirebaseAuth.instance.currentUser!.uid).delete();
    });

    // Trigger the authentication flow
  }

  static void deleteCrush(crushUid) async {
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      CollectionReference collectionReference = FirebaseFirestore.instance
          .collection("Users")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection("MyCrush");

      collectionReference.doc(crushUid).delete();

      CollectionReference collectionReference1 = FirebaseFirestore.instance
          .collection("Users")
          .doc(crushUid)
          .collection("CrushOnMe");

      collectionReference1.doc(FirebaseAuth.instance.currentUser!.uid).delete();
    });

    // Trigger the authentication flow
  }

  static addPlan(CoinPlan plan) async {
    FirebaseFirestore.instance.runTransaction((Transaction tx) async {
      CollectionReference collectionReference = FirebaseFirestore.instance
          .collection("CoinPlans");
      String path = collectionReference.doc().id;
      plan.planId = path;

      await collectionReference.doc(path).set(plan.toJson()).whenComplete(() {
        showSimpleNotification(
          Text("Plan Added Successfully"),

          // leading: NotificationBadge(totalNotifications: _totalNotifications),
          background: Colors.green,
          duration: Duration(seconds: 2),
          position: NotificationPosition.bottom,
          slideDismiss: true,
          leading: Icon(Icons.verified),
        );
      });
    });
  }

  static updatePlan(CoinPlan plan) async {
    FirebaseFirestore.instance.runTransaction((Transaction tx) async {
      CollectionReference collectionReference = FirebaseFirestore.instance
          .collection("CoinPlans");

      await collectionReference
          .doc(plan.planId)
          .update(plan.toJson())
          .whenComplete(() {
            showSimpleNotification(
              Text("Plan Updated Successfully"),

              // leading: NotificationBadge(totalNotifications: _totalNotifications),
              background: Colors.green,
              duration: Duration(seconds: 2),
              position: NotificationPosition.bottom,
              slideDismiss: true,
              leading: Icon(Icons.verified),
            );
          });
    });
  }

  static addSpam(Spamer spamer) async {
    FirebaseFirestore.instance.runTransaction((Transaction tx) async {
      CollectionReference collectionReference = FirebaseFirestore.instance
          .collection("Spams");

      await collectionReference.doc(spamer.spamerId).set(spamer.toJson());
      NotificationService.sendAdminNotification(
        "Spam message Detected",
        spamer.lastSpamMessage,
        spamer.spamerId,
      );
    });
  }

  // Backup user data before deletion for compliance
  static Future<void> backupUserDataBeforeDeletion(String uid) async {
    try {
      // Get user data
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(uid)
          .get();

      if (!userDoc.exists) {
        debugPrint('⚠️ User document not found, skipping backup');
        return;
      }

      final userData = userDoc.data();
      if (userData == null) return;

      // Add deletion timestamp and reason
      final backupData = {
        ...userData,
        'deletedAt': DateTime.now(),
        'deletionReason': 'User requested account deletion',
        'originalUid': uid,
      };

      // Store in DeletedUsers collection for compliance
      await FirebaseFirestore.instance
          .collection('DeletedUsers')
          .doc(uid)
          .set(backupData);

      debugPrint('✅ User data backed up for compliance');
    } catch (e) {
      _log('Error backing up user data');
      // Log but don't throw - continue with deletion even if backup fails
      if (kDebugMode) {
        debugPrint('Backup error: $e');
      }
    }
  }

  /// Debug logging - only in debug mode
  static void _log(String message) {
    if (kDebugMode) {
      debugPrint('[DatabaseService] $message');
    }
  }
}
