import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:viora/models/PlanTransaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../constants.dart';
import '../../size_config.dart';

import 'AdminProfileView.dart';

class TransactionsScreen extends StatefulWidget {
  static String routeName = "/transactions";

  const TransactionsScreen({super.key});

  @override
  _TransactionsScreenState createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  DateTime startDate = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
        00,
        00,
        00,
      ),
      endDate = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
        23,
        59,
        59,
      );

  late DateTimeRange selectedDateRange;
  Future<void> pickDate() async {
    // final List<DateTime> picked = await DateRagePicker.showDatePicker(
    //     initialDatePickerMode: DateRagePicker.DatePickerMode.day,
    //     context: context,
    //     initialFirstDate: new DateTime.now().subtract(new Duration(days: 7)),
    //     initialLastDate: (new DateTime.now()),
    //     firstDate: new DateTime(2015),
    //     lastDate: new DateTime(3000));

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now().add(Duration(days: 365)),
      initialDateRange: selectedDateRange,

      // builder: (BuildContext context, Widget child) {
      //   return Theme(
      //     data: ThemeData.light().copyWith(
      //       primaryColor: kPrimaryColor, // Set the primary color
      //       hintColor: kPrimaryColor, // Set the accent color
      //       colorScheme: ColorScheme.light(primary: kPrimaryColor), // Set the color scheme
      //     ),
      //     child: child,
      //   );}
    );

    if (picked != null) {
      if (mounted) {
        setState(() {
          selectedDateRange = picked;
        });
      }
    }

    if (picked != null) {
      startDate = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
        00,
        00,
        00,
      );
      endDate = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
      );
      getTransactions();
    }
  }

  Future<void> getTransactions() async {
    try {
      CollectionReference collectionReference = FirebaseFirestore.instance
          .collection('Subscription_logs');
      collectionReference
          .where('serverReceivedAt', isLessThan: endDate)
          .where('serverReceivedAt', isGreaterThanOrEqualTo: startDate)
          .orderBy('serverReceivedAt', descending: true)
          .snapshots()
          .listen((snapshot) async {
            List documents;

            documents = snapshot.docs;
            transactions.clear();
            total = 0;

            for (int i = 0; i < documents.length; i++) {
              TransactionScreenModel transaction =
                  TransactionScreenModel.fromJson(documents[i].data());
              transactions.add(transaction);
              total = total + transaction.price;
            }

            setState(() {
              isLoading = false;
            });
          });
    } catch (e) {
      debugPrint("Error fetching transactions: $e");
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    selectedDateRange = DateTimeRange(start: startDate, end: endDate);
    isLoading = true;
    getTransactions();
  }

  List<TransactionScreenModel> transactions = [];
  late bool isLoading;
  double total = 0;

  @override
  Widget build(BuildContext context) {
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
                  child: InkWell(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(60),
                        color: kSecondaryColor.withOpacity(0.1),
                      ),
                      padding: EdgeInsets.zero,
                      child: Icon(Icons.arrow_back_ios_outlined),
                    ),
                  ),
                ),
                Spacer(flex: 1),
                Text(
                  "Transactions",
                  style: TextStyle(
                    fontSize: getProportionateScreenWidth(18),
                    fontWeight: FontWeight.w600,
                    color: kPrimaryColor,
                  ),
                ),
                Spacer(flex: 3),
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
                    onPressed: () => pickDate(),
                    child: Icon(Icons.date_range, color: kPrimaryColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            "Total $kRupee${total.toStringAsFixed(4)}",
            style: TextStyle(fontSize: 22),
          ),
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  for (var trans in transactions) TransCard(transaction: trans),
                ],
              ),
            ),
    );
  }
}

class TransCard extends StatelessWidget {
  TransactionScreenModel transaction;

  TransCard({required this.transaction});

  final mailStyle = TextStyle(
    fontSize: getProportionateScreenWidth(18),
    fontWeight: FontWeight.bold,
    color: Colors.black,
    height: 1.5,
  );
  final subStyle = TextStyle(
    fontSize: getProportionateScreenWidth(16),
    fontWeight: FontWeight.bold,
    color: Colors.black,
    height: 1.5,
  );
  final DateFormat formatter = DateFormat('jm');
  final DateFormat formatterdate = DateFormat('hh:mm a, dd MMMM y');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdminProfileView(uid: transaction.uId),
            ),
          );
        },
        child: Container(
          width: getProportionateScreenWidth(SizeConfig.screenWidth),
          padding: EdgeInsets.symmetric(
            horizontal: getProportionateScreenWidth(20),
            vertical: getProportionateScreenWidth(15),
          ),
          decoration: BoxDecoration(
            // gradient: transaction.status.toLowerCase() == "active"
            //     ? null
            //     : RadialGradient(
            //         //focalRadius: 500,
            //         radius: 1.45,

            //         colors: [kPrimaryColor, Color(0xFF4A3298)],
            //         center: Alignment(1.0, 1.0),
            //       ),
            color: transaction.status.toLowerCase() == "active"
                ? Colors.green.withAlpha(180)
                : Colors.red.withAlpha(180),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(formatterdate.format(transaction.date), style: subStyle),
              Text(transaction.transactionId, style: subStyle),
              Row(
                children: [
                  // Icon(Icons.monetization_on, color: Colors.white),
                  // SizedBox(width: 4),
                  Text('$kRupee ${transaction.price}', style: mailStyle),
                  Spacer(),
                  Icon(Icons.arrow_forward_ios, color: Colors.white70),
                ],
              ),
              Row(
                children: [
                  // SvgPicture.asset(
                  //   "assets/svg/coins.svg",
                  //   color: Colors.orangeAccent,
                  //   width: getProportionateScreenWidth(20),
                  // ),
                  // SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      transaction.productId.toString(),
                      style: subStyle,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: getProportionateScreenWidth(8),
                  vertical: getProportionateScreenHeight(6),
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(100),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(transaction.eventType, style: subStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
