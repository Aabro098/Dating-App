import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

class SubscriptionPolicyScreen extends StatefulWidget {
  const SubscriptionPolicyScreen({Key? key}) : super(key: key);

  @override
  State<SubscriptionPolicyScreen> createState() =>
      _SubscriptionPolicyScreenState();
}

class _SubscriptionPolicyScreenState extends State<SubscriptionPolicyScreen> {
  @override
  void initState() {
    // TODO: implement initState
    isLoading = true;
    getSubscriptionPolicy();
    super.initState();
  }

  late bool isLoading;
  late String privacyString;

  getSubscriptionPolicy() async {
    await FirebaseFirestore.instance
        .collection("Admins")
        .doc('admins')
        .get()
        .then((value) {
          privacyString = value.data()!['subscriptionPolicy'];
          isLoading = false;
          setState(() {});
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Subscription Policy")),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(child: Html(data: privacyString)),
    );
  }
}
