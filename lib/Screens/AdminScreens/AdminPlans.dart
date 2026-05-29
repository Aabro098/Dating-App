import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:viora/size_config.dart';
import 'package:viora/models/CoinPlan.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:viora/constants.dart';
import 'package:viora/Screens/AdminScreens/AddPlan.dart';
import 'package:viora/Screens/AdminScreens/EditPlan.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';

class AdminPlans extends StatefulWidget {
  static String routeName = "/adminplans";

  @override
  _AdminPlansState createState() => _AdminPlansState();
}

class _AdminPlansState extends State<AdminPlans> {
  @override
  Widget build(BuildContext context) {
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
                  "Coin Plans",
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
                      screen: AddPlan(),
                      withNavBar: false, // OPTIONAL VALUE. True by default.
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
      body: FirestoreQueryBuilder<Map<String, dynamic>>(
        query: FirebaseFirestore.instance
            .collection('CoinPlans')
            .orderBy('date', descending: true),
        pageSize: 10,
        builder: (context, snapshot, _) {
          if (snapshot.isFetching) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.docs.isEmpty) {
            return Center(child: Text('No Plans found'));
          }

          return GridView.builder(
            padding: EdgeInsets.all(getProportionateScreenWidth(20)),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 20.0,
              mainAxisSpacing: 20.0,
            ),
            itemCount: snapshot.docs.length,
            itemBuilder: (context, index) {
              if (snapshot.hasMore && index + 1 == snapshot.docs.length) {
                snapshot.fetchMore();
              }
              final docData = snapshot.docs[index].data();
              return CoinCard(coinPlan: CoinPlan.fromJson(docData));
            },
            shrinkWrap: true,
          );
        },
      ),
    );
  }
}

class CoinCard extends StatefulWidget {
  CoinPlan coinPlan;

  CoinCard({required this.coinPlan});

  @override
  _CoinCardState createState() => _CoinCardState();
}

class _CoinCardState extends State<CoinCard> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        PersistentNavBarNavigator.pushNewScreen(
          context,
          screen: EditPlan(coinPlan: widget.coinPlan),
          withNavBar: false, // OPTIONAL VALUE. True by default.
          pageTransitionAnimation: PageTransitionAnimation.cupertino,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            //focalRadius: 500,
            radius: 1.45,

            colors: [Color(0xFF4A3298), kPrimaryColor],
            center: Alignment(1.0, 1.0),
          ),
          color: Color(0xFF4A3298),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.coinPlan.coins.toString() + " ",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: getProportionateScreenWidth(20),
                  ),
                ),
                SvgPicture.asset(
                  "assets/svg/coins.svg",
                  color: widget.coinPlan.visibility
                      ? Colors.orangeAccent
                      : Colors.blueAccent,
                  width: getProportionateScreenWidth(20),
                ),
              ],
            ),
            Container(
              margin: EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white),
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36.0),
                child: Text(
                  "\u{20B9}" + widget.coinPlan.price.toString(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: getProportionateScreenWidth(16),
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
