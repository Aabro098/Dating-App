import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

class Disclaimer  extends StatefulWidget {
  @override
  _DisclaimerState createState() => _DisclaimerState();
}

class _DisclaimerState extends State<Disclaimer > {

  @override
  void initState() {
    // TODO: implement initState
    isLoading=true;
    getPrivacydata();
    super.initState();
  }
  late bool isLoading;
  late String privacyString;

  getPrivacydata() async {
    await FirebaseFirestore.instance
        .collection("Admins")
        .doc('admins')
        .get()
        .then((value) {


      privacyString = value.data()!['disclaimer'];
      isLoading=false;
      setState(() {});
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Disclaimer"),
      ),
      body: isLoading?Center(
        child: CircularProgressIndicator(),
      ):SingleChildScrollView(
        child: Html(
          data: privacyString,
        ),
      ),
    );
  }
}
