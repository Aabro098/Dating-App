import 'package:flutter/material.dart';

import '../constants.dart';
import '../size_config.dart';


class SearchField extends StatelessWidget {
   SearchField();
   final TextEditingController tc= new TextEditingController();
  @override
  Widget build(BuildContext context) {


    return Container(
      width: SizeConfig.screenWidth ,
      decoration: BoxDecoration(
        color: kSecondaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
      ),
      child: TextField(
        autofocus: false,
      controller: tc,
        onSubmitted: (value){


        },
        decoration: InputDecoration(
            contentPadding: EdgeInsets.symmetric(
                horizontal: getProportionateScreenWidth(20),
                vertical: getProportionateScreenWidth(9)),
            border: InputBorder.none,

            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            hintText: "Search Order",

            prefixIcon: Icon(Icons.search)),
      ),
    );
  }
}
