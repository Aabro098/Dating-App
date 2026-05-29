import 'package:flutter/material.dart';

import '../constants.dart';
import '../size_config.dart';

class CustomAppBar extends StatelessWidget {
  String title;
  CustomAppBar({required this.title});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
        child: Container(
    decoration: BoxDecoration(
      color: kPrimaryColor,
      borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(10),
          bottomRight: Radius.circular(10)),
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
        Spacer(
          flex: 1,
        ),
        Text(title,
            style: TextStyle(
                fontSize: getProportionateScreenWidth(20),
                color: Colors.white)),
        Spacer(
          flex: 2,
        ),
      ],
    ),
        ),
      );
  }
}
