import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:viora/Screens/PrivacyPolicy/PrivacyPolicy.dart';
import 'package:viora/Screens/PrivacyPolicy/disclaimer.dart';
import 'package:viora/Screens/PrivacyPolicy/terms.dart';
import 'package:viora/Screens/SettingsScreen/safeDatingTipsScreen.dart';
import 'package:viora/Screens/SettingsScreen/communityGuidelinesScreen.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/Services/account_deletion_flow.dart';
import 'package:viora/components/delete_dialog.dart';
import 'package:viora/components/logout_dialog.dart';
import 'package:viora/constants.dart';
import 'package:viora/size_config.dart';

class SettingsScreen extends HookWidget {
  static String routeName = "/settingsScreen";

  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isLoggingOut = useState(false);
    final isDeletingAccount = useState(false);
    final globals = Globals.of(context);

    final media = MediaQuery.of(context);
    final topInset = media.padding.top;
    print("Top Inset: $topInset");

    return Scaffold(
      backgroundColor: kBackgroundBG,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: kPrimaryPurple),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Settings",
          style: TextStyle(
            color: kPrimaryPurple,
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: getProportionateScreenWidth(16),
            vertical: getProportionateScreenHeight(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // NEW FEATURES Section
              _SectionHeader(title: "New Features"),
              SizedBox(height: 8),
              _SettingsCard(
                children: [
                  _SettingsTile(
                    icon: Icons.shield_outlined,
                    iconColor: Colors.teal,
                    title: "Safe Dating Tips",
                    subtitle: "Stay safe while meeting new people",
                    onTap: () {
                      PersistentNavBarNavigator.pushNewScreen(
                        context,
                        screen: SafeDatingTipsScreen(),
                        withNavBar: false,
                        pageTransitionAnimation:
                            PageTransitionAnimation.cupertino,
                      );
                    },
                  ),
                  _SettingsDivider(),
                  _SettingsTile(
                    icon: Icons.people_outline,
                    iconColor: Colors.indigo,
                    title: "Community Guidelines",
                    subtitle: "Our community standards & rules",
                    onTap: () {
                      PersistentNavBarNavigator.pushNewScreen(
                        context,
                        screen: CommunityGuidelinesScreen(),
                        withNavBar: false,
                        pageTransitionAnimation:
                            PageTransitionAnimation.cupertino,
                      );
                    },
                  ),
                ],
              ),

              SizedBox(height: 24),

              // LEGAL Section
              _SectionHeader(title: "Legal"),
              SizedBox(height: 8),
              _SettingsCard(
                children: [
                  _SettingsTile(
                    icon: Icons.privacy_tip_outlined,
                    iconColor: Colors.blue,
                    title: "Privacy Policy",
                    subtitle: "How we handle your data",
                    onTap: () {
                      PersistentNavBarNavigator.pushNewScreen(
                        context,
                        screen: PrivacyPolicy(),
                        withNavBar: false,
                        pageTransitionAnimation:
                            PageTransitionAnimation.cupertino,
                      );
                    },
                  ),
                  _SettingsDivider(),
                  _SettingsTile(
                    icon: Icons.description_outlined,
                    iconColor: Colors.orange,
                    title: "Terms & Conditions",
                    subtitle: "Terms of use for Viora",
                    onTap: () {
                      PersistentNavBarNavigator.pushNewScreen(
                        context,
                        screen: Terms(),
                        withNavBar: false,
                        pageTransitionAnimation:
                            PageTransitionAnimation.cupertino,
                      );
                    },
                  ),
                  _SettingsDivider(),
                  _SettingsTile(
                    icon: Icons.info_outline,
                    iconColor: Colors.purple,
                    title: "Disclaimer",
                    subtitle: "Important disclaimers",
                    onTap: () {
                      PersistentNavBarNavigator.pushNewScreen(
                        context,
                        screen: Disclaimer(),
                        withNavBar: false,
                        pageTransitionAnimation:
                            PageTransitionAnimation.cupertino,
                      );
                    },
                  ),
                ],
              ),

              SizedBox(height: 24),

              // ACCOUNT SETTINGS Section
              _SectionHeader(title: "Account Settings"),
              SizedBox(height: 8),
              _SettingsCard(
                children: [
                  _SettingsTile(
                    icon: Icons.logout,
                    iconColor: Colors.deepOrange,
                    title: "Logout",
                    subtitle: "Sign out of your account",
                    onTap: () {
                      if (isLoggingOut.value) return;
                      // _showLogoutConfirmation(
                      //   context,
                      //   isLoggingOut,
                      //   globals,
                      // );
                      LogoutDialog.show(context);
                    },
                  ),
                  _SettingsDivider(),
                  _SettingsTile(
                    icon: Icons.delete_outline,
                    iconColor: Colors.red,
                    title: "Delete Account",
                    subtitle: "Permanently delete your account",
                    titleColor: Colors.red,
                    onTap: () {
                      if (isDeletingAccount.value) return;
                      showAccountDeletionConfirmation(
                        context,
                        isDeletingAccount,
                        globals,
                      );
                    },
                  ),
                ],
              ),

              SizedBox(height: 32),

              // App Version
              Center(
                child: Text(
                  "Viora v1.0",
                  style: TextStyle(
                    color: kSecondaryColor,
                    fontSize: 13,
                    fontFamily: 'Nunito',
                  ),
                ),
              ),
              SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Logout ──────────────────────────────────────────────────────────────────

  // void _showLogoutConfirmation(
  //   BuildContext context,
  //   ValueNotifier<bool> isLoggingOut,
  //   Globals globals,
  // ) {
  //   showCupertinoModalPopup<void>(
  //     context: context,
  //     builder: (BuildContext modalContext) => CupertinoActionSheet(
  //       title: Text(
  //         "Logout",
  //         style: TextStyle(
  //           fontFamily: 'Nunito',
  //           fontWeight: FontWeight.w700,
  //           fontSize: 18,
  //         ),
  //       ),
  //       message: Text(
  //         "Are you sure you want to logout?",
  //         style: TextStyle(fontFamily: 'Nunito', fontSize: 14),
  //       ),
  //       actions: <CupertinoActionSheetAction>[
  //         CupertinoActionSheetAction(
  //           onPressed: () async {
  //             if (isLoggingOut.value) return;
  //             isLoggingOut.value = true;
  //             Navigator.pop(modalContext);

  //             showSimpleNotification(
  //               Text("Logging Out"),
  //               background: Colors.red,
  //               duration: Duration(seconds: 3),
  //               position: NotificationPosition.bottom,
  //             );

  //             // final success = await _signOutAndCleanup(context, globals);
  //             if (!success) {
  //               isLoggingOut.value = false;
  //             }
  //           },
  //           isDestructiveAction: true,
  //           child: Text("Logout"),
  //         ),
  //       ],
  //       cancelButton: CupertinoActionSheetAction(
  //         onPressed: () => Navigator.pop(modalContext),
  //         child: Text("Cancel"),
  //       ),
  //     ),
  //   );
  // }

  // ─── Delete Account ──────────────────────────────────────────────────────────

  // void _showDeleteAccountConfirmation(
  //   BuildContext context,
  //   ValueNotifier<bool> isDeletingAccount,
  //   Globals globals,
  // ) {
  //   showAccountDeletionConfirmation(
  //     context,
  //     isDeletingAccount,
  //     globals,
  //     deletionMethod: 'in_app_settings',
  //   );
  // }
}

// ─── Reusable Widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: kSecondaryColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color? titleColor;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: titleColor ?? Colors.black87,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 12,
                      color: kSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: kSecondaryColor, size: 22),
          ],
        ),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, color: Colors.grey.shade200),
    );
  }
}
