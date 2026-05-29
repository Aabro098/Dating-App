import 'package:viora/constants.dart';
import 'package:flutter/material.dart';

import '../size_config.dart';

class CustomSurffixIcon extends StatelessWidget {
  const CustomSurffixIcon({required this.iconData});

  final IconData iconData;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        0,
        getProportionateScreenWidth(20),
        getProportionateScreenWidth(20),
        getProportionateScreenWidth(20),
      ),
      child: Icon(
        iconData,
        size: getProportionateScreenWidth(18),
        color: kPrimaryColor,
      ),
    );
  }
}
