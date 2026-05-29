import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';

import '../../constants.dart';
import '../../size_config.dart';
import 'botHome.dart';
import 'package:viora/models/UserDetails.dart';

class DisabledBots extends HookWidget {
  static String routeName = "/disabledBots";

  @override
  Widget build(BuildContext context) {
    final refreshKey = useState(GlobalKey<RefreshIndicatorState>());

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
                  onTap: () => Navigator.pop(context),
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
                  "Disabled Bots",
                  style: TextStyle(
                    fontSize: getProportionateScreenWidth(20),
                    color: Colors.white,
                  ),
                ),
                Spacer(),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        key: refreshKey.value,
        onRefresh: () async {
          // Manually refresh FirestoreQueryBuilder by rebuilding Widget
          refreshKey.value = GlobalKey<RefreshIndicatorState>();
        },
        child: FirestoreQueryBuilder<Map<String, dynamic>>(
          pageSize: 20,
          query: FirebaseFirestore.instance
              .collection('Users')
              .where("fcmToken", isEqualTo: "Admin")
              .where("isDisabled", isEqualTo: true)
              .orderBy("joiningDate", descending: true),
          builder: (context, snapshot, _) {
            if (snapshot.isFetching && snapshot.docs.isEmpty) {
              return Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text("Error: ${snapshot.error}"));
            }
            if (snapshot.docs.isEmpty) {
              return Center(child: Text("No Users found"));
            }
            return GridView.builder(
              padding: EdgeInsets.all(getProportionateScreenWidth(20)),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.75,
                crossAxisSpacing: 20.0,
                mainAxisSpacing: 20.0,
              ),
              itemCount: snapshot.docs.length,
              itemBuilder: (context, index) {
                final userData = snapshot.docs[index].data();
                final user = UserDetails.fromJson(userData);
                return BotCard(user: user);
              },
            );
          },
        ),
      ),
    );
  }
}
