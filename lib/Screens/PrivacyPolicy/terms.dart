import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

class Terms extends StatefulWidget {
  @override
  _TermsState createState() => _TermsState();
}

class _TermsState extends State<Terms> {

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


      privacyString = value.data()!['terms'];
      isLoading=false;
      setState(() {});
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Terms & Conditions"),
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
