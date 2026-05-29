import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:viora/Screens/ProfileScreen/new_profile_view.dart';

import 'package:viora/components/customAppBar.dart';
import 'package:viora/constants.dart';
import 'package:viora/size_config.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:viora/models/ProfileAction.dart';
import 'package:viora/Screens/ProfileScreen/profileScreen.dart';
import 'package:viora/components/custom_tab_indicator.dart';

class CrushScreen extends HookWidget {
  final bool hideAppBar;
  final tabs = ["Your", "On You"];

  final userId = FirebaseAuth.instance.currentUser!.uid;

  CrushScreen({super.key, this.hideAppBar = false});

  List<Query<Map<String, dynamic>>> getQueries() => [
    FirebaseFirestore.instance
        .collection('Users')
        .doc(userId)
        .collection("MyCrush")
        .orderBy("date", descending: true),
    FirebaseFirestore.instance
        .collection('Users')
        .doc(userId)
        .collection("CrushOnMe")
        .orderBy("date", descending: true),
  ];

  @override
  Widget build(BuildContext context) {
    final queries = getQueries();
    return Scaffold(
      appBar: hideAppBar
          ? null
          : PreferredSize(
              preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),
              child: CustomAppBar(title: "Crush"),
            ),
      body: DefaultTabController(
        length: tabs.length,
        initialIndex: 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              labelPadding: EdgeInsets.symmetric(horizontal: 14.4),
              indicatorPadding: EdgeInsets.symmetric(horizontal: 14.4),
              isScrollable: true,
              labelColor: Color(0xFF000000),
              unselectedLabelColor: Color(0xFF8a8a8a),
              labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              unselectedLabelStyle: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              indicator: RoundedRectangleTabIndicator(
                color: Color(0xFF000000),
                weight: 2.4,
                width: 14.4,
              ),
              tabs: tabs.map((tab) => Tab(child: Text(tab))).toList(),
            ),
            Expanded(
              child: TabBarView(
                children: List.generate(
                  tabs.length,
                  (index) => FirestoreQueryBuilder<Map<String, dynamic>>(
                    query: queries[index],
                    pageSize: 20,
                    builder: (context, snapshot, _) {
                      if (snapshot.isFetching && snapshot.docs.isEmpty) {
                        return Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text("Error: ${snapshot.error}"));
                      }
                      if (snapshot.docs.isEmpty) {
                        return Center(child: Text("No Crush Added"));
                      }
                      return ListView.builder(
                        padding: EdgeInsets.all(
                          getProportionateScreenWidth(20),
                        ),
                        itemCount: snapshot.docs.length,
                        itemBuilder: (context, docIndex) {
                          final data = snapshot.docs[docIndex].data();
                          return ActionCard(
                            slidable: index == 0,
                            action: ProfileAction.fromJson(data),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ActionCard extends StatefulWidget {
  final ProfileAction action;
  final bool slidable;

  ActionCard({required this.action, required this.slidable});

  @override
  _ActionCardState createState() => _ActionCardState();
}

class _ActionCardState extends State<ActionCard> {
  late UserDetails user;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    getUser();
  }

  void getUser() async {
    final doc = await FirebaseFirestore.instance
        .collection("Users")
        .doc(widget.action.uid)
        .get();

    if (doc.exists) {
      user = UserDetails.fromJson(doc.data()!);
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return SizedBox();
    if (user.isDisabled!) return SizedBox();

    return GestureDetector(
      onTap: () {
        PersistentNavBarNavigator.pushNewScreen(
          context,
          screen: NewProfileView(uid: user.uid, canPop: true),
          withNavBar: false,
          pageTransitionAnimation: PageTransitionAnimation.cupertino,
        );
      },
      child: Card(
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(30)),
                    child: CachedNetworkImage(
                      imageUrl: user.images!.isEmpty
                          ? (user.gender == "Male" ? kMaleUrl : kFemaleUrl)
                          : user.images![0],
                      height: 50,
                      width: 50,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (user.isOnline!)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 16,
                        width: 16,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        user.name!,
                        style: TextStyle(
                          fontSize: getProportionateScreenWidth(15),
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        " ${user.age}",
                        style: TextStyle(
                          fontSize: getProportionateScreenWidth(15),
                          fontWeight: FontWeight.bold,
                          color: kSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                  Text("${user.city}, ${user.state}"),
                  Text(
                    user.isOnline!
                        ? "Online"
                        : "Active ${timeago.format(DateTime.now().subtract(DateTime.now().difference(user.lastOnline!)))}",
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.all(getProportionateScreenHeight(10)),
              child: SvgPicture.asset(
                user.gender == "Female"
                    ? "assets/svg/female.svg"
                    : "assets/svg/male.svg",
                height: getProportionateScreenHeight(24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
