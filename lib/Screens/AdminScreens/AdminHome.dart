import 'package:viora/Screens/AdminScreens/MaleUsers.dart';
import 'package:viora/Screens/AdminScreens/Spamers.dart';
import 'package:viora/Screens/AdminScreens/adminChatRooms.dart';
import 'package:viora/Screens/BotManagement/DiabledBots.dart';
import 'package:viora/Screens/BotManagement/botHome.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../constants.dart';
import '../../size_config.dart';
import 'TransactionsScreen.dart';
import 'reportScreen.dart';
import 'FemaleUsers.dart';
import 'SearchUsers.dart';

class AdminHome extends StatefulWidget {
  @override
  _AdminHomeState createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  @override
  void initState() {
    super.initState();
    // Admin topic subscription is now handled automatically by FCMService
    // when user signs in and is identified as admin - no need to visit this screen
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),

        child: buildAppBar(context),
      ),

      body: GridView.count(
        padding: EdgeInsets.all(kDefaultPadding),
        crossAxisCount: 2,
        mainAxisSpacing: 20,
        childAspectRatio: 1.75,
        crossAxisSpacing: 20,
        physics: NeverScrollableScrollPhysics(),
        scrollDirection: Axis.vertical,
        shrinkWrap: true,
        children: [
          CustomContainer(
            title: "Support",
            icon: CupertinoIcons.chat_bubble_2,
            routeName: AdminChatRooms.routeName,
          ),
          CustomContainer(
            title: "Bots",
            icon: CupertinoIcons.person_alt_circle,
            routeName: BotHome.routeName,
          ),
          CustomContainer(
            title: "Disabled",
            icon: CupertinoIcons.person_alt_circle,
            routeName: DisabledBots.routeName,
          ),
          CustomContainer(
            title: "Transactions",
            icon: CupertinoIcons.money_dollar_circle,
            routeName: TransactionsScreen.routeName,
          ),
          CustomContainer(
            title: "Reports",
            icon: Icons.error_outline,
            routeName: ReportScreen.routeName,
          ),
          CustomContainer(
            title: "Spamers",
            icon: Icons.not_interested_sharp,
            routeName: Spamers.routeName,
          ),
          CustomContainer(
            title: "Male",
            icon: CupertinoIcons.person,
            routeName: MaleUsers.routeName,
          ),
          CustomContainer(
            title: "Female",
            icon: CupertinoIcons.person,
            routeName: FemaleUsers.routeName,
          ),
        ],
      ),
    );
  }

  Widget buildAppBar(context) {
    return SafeArea(
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
              "Admin Home",
              style: TextStyle(
                fontSize: getProportionateScreenWidth(20),
                color: Colors.white,
              ),
            ),
            Spacer(),
            GestureDetector(
              onTap: () {
                Navigator.pushNamed(context, SearchUser.routeName);
              },
              child: Container(
                height: 57.6,
                width: 57.6,
                padding: EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9.6),
                ),
                child: Icon(
                  Icons.search,
                  color: Colors.white,
                  size: getProportionateScreenWidth(28),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomContainer extends StatelessWidget {
  String title, routeName;
  IconData icon;

  CustomContainer({
    required this.icon,
    required this.title,
    required this.routeName,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, routeName);
      },
      child: Container(
        // height: 90,
        width: getProportionateScreenWidth(SizeConfig.screenWidth / 2),
        padding: EdgeInsets.symmetric(
          horizontal: getProportionateScreenWidth(20),
          vertical: getProportionateScreenWidth(15),
        ),
        decoration: BoxDecoration(
          gradient: kPrimaryGradientColor,
          color: Color(0xFF4A3298),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: getProportionateScreenWidth(18),
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
