import 'package:flutter/material.dart';
import 'package:viora/components/customAppBar.dart';
import 'package:viora/size_config.dart';
import 'package:viora/constants.dart';
import 'package:viora/components/custom_surfix_icon.dart';
import 'package:viora/components/form_error.dart';
import 'package:viora/components/default_button.dart';
import 'package:viora/models/CoinPlan.dart';
import 'package:viora/Services/DatabaseService.dart';

class AddPlan extends StatefulWidget {
  @override
  _AddPlanState createState() => _AddPlanState();
}

class _AddPlanState extends State<AddPlan> {
  final _formKey = GlobalKey<FormState>();
  bool visibility = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),
        child: CustomAppBar(title: "Add Plan"),
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
                text: "ADD",
                press: () {
                  FocusScope.of(context).requestFocus(FocusNode());

                  if (_formKey.currentState!.validate()) {
                    CoinPlan coinPlan = CoinPlan(
                      date: DateTime.now(),
                      coins: int.parse(coinCtr.text),
                      price: int.parse(priceCtr.text),
                      visibility: visibility,
                    );

                    DatabaseService.addPlan(coinPlan);
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

  TextEditingController priceCtr = TextEditingController();

  TextFormField buildPriceFormField() {
    return TextFormField(
      controller: priceCtr,
      keyboardType: TextInputType.number,
      onChanged: (value) {
        if (value.isNotEmpty) {
          removeError(kReqError);
        }
        return;
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

  TextEditingController coinCtr = TextEditingController();

  TextFormField buildCoinFormField() {
    return TextFormField(
      controller: coinCtr,
      keyboardType: TextInputType.number,
      onChanged: (value) {
        if (value.isNotEmpty) {
          removeError(kReqError);
        }
        return;
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
    if (!errors.contains(error)) {
      setState(() {
        errors.add(error);
      });
    }
  }

  void removeError(String error) {
    if (errors.contains(error)) {
      setState(() {
        errors.remove(error);
      });
    }
  }
}
