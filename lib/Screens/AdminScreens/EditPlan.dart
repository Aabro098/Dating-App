import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:viora/size_config.dart';
import 'package:viora/constants.dart';
import 'package:viora/components/custom_surfix_icon.dart';
import 'package:viora/components/form_error.dart';
import 'package:viora/components/default_button.dart';
import 'package:viora/models/CoinPlan.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:overlay_support/overlay_support.dart';

class EditPlan extends StatefulWidget {
  CoinPlan coinPlan;

  EditPlan({required this.coinPlan});

  @override
  _EditPlanState createState() => _EditPlanState();
}

class _EditPlanState extends State<EditPlan> {
  final _formKey = GlobalKey<FormState>();
  bool visibility = true;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    visibility = widget.coinPlan.visibility;
    priceCtr.text = widget.coinPlan.price.toString();
    coinCtr.text = widget.coinPlan.coins.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),
        child:
            /// Custom Navigation Drawer and Search Button
            SafeArea(
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
                      "Edit Plan",
                      style: TextStyle(
                        fontSize: getProportionateScreenWidth(20),
                        color: Colors.white,
                      ),
                    ),
                    Spacer(),
                    GestureDetector(
                      onTap: () {
                        showCupertinoModalPopup<void>(
                          context: context,
                          builder: (BuildContext context) =>
                              CupertinoActionSheet(
                                title: Text("Delete Plan"),
                                message: Text("This is not reversible process"),
                                actions: <CupertinoActionSheetAction>[
                                  CupertinoActionSheetAction(
                                    onPressed: () async {
                                      FirebaseFirestore.instance
                                          .collection("CoinPlans")
                                          .doc(widget.coinPlan.planId)
                                          .delete();

                                      Navigator.pop(context);
                                      Navigator.pop(context);
                                      showSimpleNotification(
                                        Text("Plan Deleted"),
                                        background: Colors.redAccent,
                                        duration: Duration(seconds: 10),
                                        position: NotificationPosition.top,
                                        slideDismiss: true,
                                        leading: Icon(Icons.close),
                                      );
                                    },
                                    isDestructiveAction: true,
                                    child: Text("Delete Plan"),
                                  ),
                                ],
                                cancelButton: CupertinoActionSheetAction(
                                  onPressed: () async {
                                    Navigator.pop(context);
                                  },
                                  child: Text("Cancel"),
                                ),
                              ),
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
                          Icons.delete,
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
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildCoinFormField(),
              SizedBox(height: getProportionateScreenHeight(10)),
              buildPriceFormField(),
              SizedBox(height: getProportionateScreenHeight(10)),
              Row(
                children: [
                  Text("Visibility"),
                  Switch(
                    value: visibility,
                    activeThumbColor: Colors.green,
                    onChanged: (value) {
                      setState(() {
                        visibility = value;
                      });
                    },
                  ),
                ],
              ),
              FormError(errors: errors),
              SizedBox(height: getProportionateScreenHeight(20)),
              DefaultButton(
                text: "UPDATE",
                press: () {
                  FocusScope.of(context).requestFocus(FocusNode());

                  if (_formKey.currentState!.validate()) {
                    CoinPlan coinPlan = CoinPlan(
                      date: widget.coinPlan.date,
                      coins: int.parse(coinCtr.text),
                      price: int.parse(priceCtr.text),
                      visibility: visibility,
                    );
                    coinPlan.planId = widget.coinPlan.planId;

                    DatabaseService.updatePlan(coinPlan);
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextEditingController priceCtr = new TextEditingController();

  TextFormField buildPriceFormField() {
    return TextFormField(
      controller: priceCtr,
      keyboardType: TextInputType.number,
      onChanged: (value) {
        if (value.isNotEmpty) {
          removeError(kReqError);
        }
        return null;
      },
      validator: (value) {
        if (value!.isEmpty) {
          addError(kReqError);
          return "";
        }
        return null;
      },
      decoration: InputDecoration(
        helperText: ' ',
        labelText: "Price",
        hintText: "Enter price",
        // If  you are using latest version of flutter then lable text and hint text shown like this
        // if you r using flutter less then 1.20.* then maybe this is not working properly
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixIcon: CustomSurffixIcon(iconData: Icons.monetization_on_outlined),
      ),
    );
  }

  TextEditingController coinCtr = new TextEditingController();

  TextFormField buildCoinFormField() {
    return TextFormField(
      controller: coinCtr,
      keyboardType: TextInputType.number,
      onChanged: (value) {
        if (value.isNotEmpty) {
          removeError(kReqError);
        }
        return null;
      },
      validator: (value) {
        if (value!.isEmpty) {
          addError(kReqError);
          return "";
        }
        return null;
      },
      decoration: InputDecoration(
        helperText: ' ',
        labelText: "Coins",
        hintText: "Enter coins",
        // If  you are using latest version of flutter then lable text and hint text shown like this
        // if you r using flutter less then 1.20.* then maybe this is not working properly
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixIcon: CustomSurffixIcon(iconData: Icons.attach_money_outlined),
      ),
    );
  }

  final List<String> errors = [];

  void addError(String error) {
    if (!errors.contains(error))
      setState(() {
        errors.add(error);
      });
  }

  void removeError(String error) {
    if (errors.contains(error))
      setState(() {
        errors.remove(error);
      });
  }
}
