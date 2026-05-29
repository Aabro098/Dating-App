import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:intl/intl.dart';

import '../../constants.dart';
import '../../size_config.dart';
import 'AdminProfileView.dart';
import 'package:viora/models/Spamer.dart';

class Spamers extends HookWidget {
  static String routeName = "/spamers";

  @override
  Widget build(BuildContext context) {
    // State key to rebuild FirestoreQueryBuilder to trigger refresh
    final refreshKey = useState(DateTime.now());

    final query = FirebaseFirestore.instance
        .collection('Spams')
        .orderBy('lastSpamDate', descending: true);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(100.0),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: getProportionateScreenWidth(10),
              horizontal: getProportionateScreenWidth(20),
            ),
            child: Row(
              children: [
                SizedBox(
                  height: getProportionateScreenWidth(40),
                  width: getProportionateScreenWidth(40),
                  child: TextButton(
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(60),
                      ),
                      backgroundColor: kSecondaryColor.withOpacity(0.1),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Icon(Icons.arrow_back_ios_outlined),
                  ),
                ),
                Spacer(flex: 1),
                Text(
                  "Reported Users",
                  style: TextStyle(
                    fontSize: getProportionateScreenWidth(18),
                    fontWeight: FontWeight.w600,
                    color: kPrimaryColor,
                  ),
                ),
                Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          refreshKey.value = DateTime.now(); // trigger rebuild to refresh data
        },
        child: FirestoreQueryBuilder(
          key: ValueKey(refreshKey.value),
          query: query,
          pageSize: 10,
          builder: (context, snapshot, _) {
            if (snapshot.isFetching) {
              return Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (snapshot.docs.isEmpty) {
              return Center(child: Text("No Spam Users found"));
            }

            return ListView.builder(
              padding: EdgeInsets.all(getProportionateScreenWidth(5)),
              itemCount: snapshot.docs.length,
              itemBuilder: (context, index) {
                if (snapshot.hasMore && index + 1 == snapshot.docs.length) {
                  snapshot.fetchMore();
                }

                final data = snapshot.docs[index].data();
                final spamer = Spamer.fromJson(data);

                return SpamerCard(spamer: spamer);
              },
            );
          },
        ),
      ),
    );
  }
}

class SpamerCard extends StatelessWidget {
  final Spamer spamer;

  SpamerCard({required this.spamer});

  final subStyle = TextStyle(
    fontSize: getProportionateScreenWidth(16),
    fontWeight: FontWeight.bold,
    color: Colors.white,
    height: 1.5,
  );
  final DateFormat formatterdate = DateFormat('hh:mm a, dd MMMM y');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        width: getProportionateScreenWidth(SizeConfig.screenWidth),
        padding: EdgeInsets.symmetric(
          horizontal: getProportionateScreenWidth(20),
          vertical: getProportionateScreenWidth(15),
        ),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 1.45,
            colors: [kPrimaryColor, Color(0xFF4A3298)],
            center: Alignment(1.0, 1.0),
          ),
          color: Color(0xFF4A3298),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatterdate.format(spamer.lastSpamDate), style: subStyle),
            Row(
              children: [
                Icon(Icons.report_gmailerrorred_outlined, color: Colors.white),
                SizedBox(width: 4),
                Flexible(
                  child: Text(
                    spamer.spamerId,
                    style: subStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Spacer(),
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminProfileView(uid: spamer.spamerId),
                      ),
                    );
                  },
                  child: Icon(Icons.arrow_forward_ios, color: Colors.white70),
                ),
              ],
            ),
            Row(
              children: [
                Icon(Icons.message, color: Colors.white),
                SizedBox(width: 4),
                Flexible(
                  child: Text(
                    spamer.lastSpamMessage,
                    style: subStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
