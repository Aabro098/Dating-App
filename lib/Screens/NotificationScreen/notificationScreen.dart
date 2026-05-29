import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:viora/models/NotificationData.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:viora/Services/DatabaseService.dart';
import '../../constants.dart';
import '../../size_config.dart';
import 'components/notificationCard.dart';

class NotificationScreen extends StatefulWidget {
  @override
  _NotificationScreenState createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    DatabaseService.updateField({"notiCount": 0});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),
        child:
            /// Custom Navigation Drawer and Search Button
            Container(
              decoration: BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
              ),
              padding: EdgeInsets.only(top: 28.8),
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
                  Spacer(flex: 1),
                  Text(
                    "Notifications",
                    style: TextStyle(
                      fontSize: getProportionateScreenWidth(20),
                      color: Colors.white,
                    ),
                  ),
                  Spacer(flex: 2),
                ],
              ),
            ),
      ),
      body: FirestoreListView(
        query: FirebaseFirestore.instance
            .collection('Users')
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .collection("Notifications")
            .orderBy('date', descending: true),
        //item builder type is compulsory.
        itemBuilder: (context, documentSnapshots) {
          final data = documentSnapshots.data() as Map<String, dynamic>;
          return NotificationCard(
            notificationData: NotificationData.fromJson(data),
          );
        },
        // orderBy is compulsory to enable pagination

        //Change types accordingly
        padding: EdgeInsets.all(getProportionateScreenWidth(5)),
        emptyBuilder: (context) {
          return Center(child: Text("No Notifications"));
        },

        loadingBuilder: (context) {
          return Center(child: CircularProgressIndicator());
        },

        // to fetch real-time data
      ),
    );
  }
}
