import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:viora/Screens/AdminScreens/AdminHome.dart';
import 'package:viora/Screens/CrushScreen/CrushScreen.dart';
import 'package:viora/Screens/MyProfile/MyProfile.dart';
import 'package:viora/Screens/PrivacyPolicy/PrivacyPolicy.dart';
import 'package:viora/Screens/SupportScreen/supportScreen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:tuple/tuple.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:viora/components/delete_dialog.dart';
import 'package:viora/components/logout_dialog.dart';
import 'package:viora/utils/helpers/image_helper.dart';
import '../../Services/Global.dart';
import 'package:viora/Services/account_deletion_flow.dart';
import '../../constants.dart';
import '../../size_config.dart';
import '../PrivacyPolicy/disclaimer.dart';
import 'package:viora/Screens/FavScreen/FavScreen.dart';
import 'package:viora/Screens/PrivacyPolicy/terms.dart';

/// Custom Hook: useAdminStatus
/// Fetches admin list from Firestore and returns if current user is admin.
/// Handles loading state internally.
///
/// This hook encapsulates backend/database calls and hydration of UI state.
/// Returns a tuple: (isAdmin bool, isLoading bool).
Tuple2<bool, bool> useAdminStatus() {
  final isAdmin = useState<bool>(false);
  final isLoading = useState<bool>(true);

  useEffect(() {
    Future<void> fetchAdminData() async {
      try {
        final doc = await FirebaseFirestore.instance
            .collection("Admins")
            .doc('admins')
            .get();
        final admins = doc.data()?['admins'] as List<dynamic>? ?? [];
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        debugPrint("vinayAdmin $admins");
        if (admins.contains(currentUserId)) {
          isAdmin.value = true;
        }
      } catch (e) {
        // Handle error or log
        isAdmin.value = false;
      } finally {
        isLoading.value = false;
      }
    }

    fetchAdminData();
    return null; // No cleanup
  }, []);

  return Tuple2(isAdmin.value, isLoading.value);
}

/// Business Logic Function
/// Signs out the user and cleans up tokens and online status asynchronously.
/// This function is independent of UI and can be tested separately.
/// Returns bool to indicate if operation was successful
// Future<bool> signOutAndCleanup(BuildContext context) async {
//   try {
//     final globals = Globals.of(context);
//     debugPrint('🚪 [LOGOUT] Starting logout process...');
//     final uid = FirebaseAuth.instance.currentUser?.uid;

//     // 1. Set user offline
//     await DatabaseService.handleOnlineStatue(false);
//     debugPrint('🚪 [LOGOUT] User set to offline');

//     // 2. Delete FCM token from Firestore
//     await DatabaseService.deleteToken();
//     debugPrint('🚪 [LOGOUT] FCM token deleted from Firestore');

//     // 3. Reset FCM service state (including unsubscribe from Admin topic)
//     await FCMService.resetOnLogout();
//     debugPrint(
//       '🚪 [LOGOUT] FCM service state reset and Admin topic unsubscribed',
//     );

//     // Explicitly clear subscription cache/identity on logout.
//     await SubscriptionService.clearSubscriptionCacheOnLogout(uid: uid);

//     // Revoke this device session BEFORE Firebase sign-out, otherwise currentUser
//     // becomes null and the session doc may remain active.
//     await SessionService.revokeCurrentSession();

//     // 4. Add slight delay before sign out to ensure cleanup finishes
//     await Future.delayed(Duration(milliseconds: 500));

//     // 5. Sign out from Firebase Auth
//     await FirebaseAuth.instance.signOut();
//     debugPrint('🚪 [LOGOUT] Firebase Auth signed out');

//     // 6. Sign out from other providers
//     await PhoneAuth.logout(context);
//     await GoogleAuth.logoutApp(context);
//     debugPrint('🚪 [LOGOUT] Other auth providers signed out');

//     // 7. Clear app state
//     globals.prefs.clear();
//     globals.resetInitialization();
//     resetVerificationDialogFlag();
//     HomeFilterStore.reset();
//     debugPrint('🚪 [LOGOUT] App state cleared');
//     if (context.mounted) {
//       Navigator.pushNamedAndRemoveUntil(
//         context,
//         LoginScreen.routeName,
//         (route) => false,
//       );
//       showSimpleNotification(
//         Text("You have been logged out."),
//         background: Colors.green,
//         duration: Duration(seconds: 3),
//         position: NotificationPosition.bottom,
//       );
//     }
//     return true;
//   } catch (e) {
//     debugPrint('Error during logout: $e');
//     return false;
//   }
// }

/// Main Widget: MenuScreen using HookWidget to leverage Flutter Hooks.
/// UI state use isAdmin and isLoading managed by useState and useEffect inside custom hook.
/// Business logic and backend/database calls separated and reusable.
class MenuScreen extends HookWidget {
  @override
  Widget build(BuildContext context) {
    // Custom hook to get admin status and loading state
    final adminStatus = useAdminStatus();
    final bool isAdmin = adminStatus.item1;
    final bool isLoading = adminStatus.item2;
    final globals = Globals.of(context);
    final userDetails = useValueListenable(globals.prefs.userDetails);

    // State to prevent multiple clicks on logout/delete
    final isLoggingOut = useState(false);
    final isDeletingAccount = useState(false);

    // Helper function for URL launching abstracted for reuse
    Future<void> _launchURL(String url) async {
      if (await canLaunch(url)) {
        await launch(url);
      } else {
        throw 'Could not launch $url';
      }
    }

    // Check if userDetails is null (user might be logged out)
    if (userDetails == null) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Container(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: getProportionateScreenHeight(100)),
                    GestureDetector(
                      onTap: () {
                        PersistentNavBarNavigator.pushNewScreen(
                          context,
                          screen: MyProfile(),
                          withNavBar: false,
                          pageTransitionAnimation:
                              PageTransitionAnimation.cupertino,
                        );
                      },
                      child: Row(
                        children: [
                          Spacer(flex: 1),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: ClipRRect(
                                    // borderRadius: BorderRadius.all(
                                    //   Radius.circular(30),
                                    // ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: ReactiveProfileImage(
                                        imagePath:
                                            userDetails.images?.isNotEmpty ==
                                                true
                                            ? userDetails.images![0]
                                            : '',
                                        gender: userDetails.gender ?? 'male',
                                        height: 80,
                                        width: 80,
                                      ),
                                      // child: CircleAvatar(
                                      //   backgroundImage: NetworkImage(
                                      //     (userDetails.images == null ||
                                      //             userDetails.images!.isEmpty)
                                      //         ? userDetails.gender == "Male"
                                      //               ? kMaleUrl
                                      //               : kFemaleUrl
                                      //         : userDetails.images![0],
                                      //   ),
                                      //   radius: 40,
                                    ),
                                  ),
                                ),
                                Text(
                                  userDetails.name ?? 'User',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                Text(
                                  "${userDetails.age ?? ''} Yrs",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    "${userDetails.city ?? ''},${userDetails.state ?? ''}",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Spacer(flex: 5),
                        ],
                      ),
                    ),
                    // Admin section shown if user is admin
                    if (isAdmin)
                      CustomListTile(Icons.dashboard_outlined, 'Admin', () {
                        PersistentNavBarNavigator.pushNewScreen(
                          context,
                          screen: AdminHome(),
                          withNavBar: false,
                          pageTransitionAnimation:
                              PageTransitionAnimation.cupertino,
                        );
                      }),
                    CustomListTile(
                      CupertinoIcons.heart_circle_fill,
                      'Your Crush',
                      () {
                        PersistentNavBarNavigator.pushNewScreen(
                          context,
                          screen: CrushScreen(),
                          withNavBar: false,
                          pageTransitionAnimation:
                              PageTransitionAnimation.cupertino,
                        );
                      },
                    ),
                    CustomListTile(
                      CupertinoIcons.star_circle_fill,
                      'Your Favorite',
                      () {
                        PersistentNavBarNavigator.pushNewScreen(
                          context,
                          screen: FavScreen(),
                          withNavBar: false,
                          pageTransitionAnimation:
                              PageTransitionAnimation.cupertino,
                        );
                      },
                    ),
                    CustomListTile(CupertinoIcons.chat_bubble_2, 'Support', () {
                      PersistentNavBarNavigator.pushNewScreen(
                        context,
                        screen: SupportScreen(canPop: true),
                        withNavBar: false,
                        pageTransitionAnimation:
                            PageTransitionAnimation.cupertino,
                      );
                    }),
                    CustomListTile(Icons.delete, 'Delete Account', () {
                      if (isDeletingAccount.value) return;
                      showAccountDeletionConfirmation(
                        context,
                        isDeletingAccount,
                        globals,
                        deletionMethod: 'menu',
                      );
                    }),
                    CustomListTile(
                      Icons.privacy_tip_outlined,
                      'Privacy Policy',
                      () {
                        PersistentNavBarNavigator.pushNewScreen(
                          context,
                          screen: PrivacyPolicy(),
                          withNavBar: false,
                          pageTransitionAnimation:
                              PageTransitionAnimation.cupertino,
                        );
                      },
                    ),
                    CustomListTile(Icons.info, 'Disclaimer', () {
                      PersistentNavBarNavigator.pushNewScreen(
                        context,
                        screen: Disclaimer(),
                        withNavBar: false,
                        pageTransitionAnimation:
                            PageTransitionAnimation.cupertino,
                      );
                    }),
                    CustomListTile(Icons.info, 'Terms & \nConditions', () {
                      _launchURL(kPrivacyUrl);
                      PersistentNavBarNavigator.pushNewScreen(
                        context,
                        screen: Terms(),
                        withNavBar: false,
                        pageTransitionAnimation:
                            PageTransitionAnimation.cupertino,
                      );
                    }),
                    CustomListTile(Icons.logout, 'Logout', () async {
                      // Prevent multiple clicks
                      // if (isLoggingOut.value) return;
                      // isLoggingOut.value = true;

                      // showSimpleNotification(
                      //   Text("Logging Out"),
                      //   background: Colors.red,
                      //   duration: Duration(seconds: 3),
                      //   position: NotificationPosition.bottom,
                      // );

                      // final success = await signOutAndCleanup(context);
                      // if (!success) {
                      //   isLoggingOut.value = false;
                      // }

                      if (isLoggingOut.value) return;
                      LogoutDialog.show(context);
                    }),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Custom List Tile widget with proper onTap callback (no immediate invocation)
class CustomListTile extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  CustomListTile(this.icon, this.text, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: getProportionateScreenWidth(20),
      ),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 5),
        child: InkWell(
          splashColor: kPrimaryColor,
          onTap:
              onTap, // Correct: pass the callback reference, not invoke immediately
          child: Container(
            height: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(icon, size: 30, color: kPrimaryColor),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(text, style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
