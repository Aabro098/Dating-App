import 'package:flutter/material.dart';
import 'package:viora/size_config.dart';
import 'package:viora/utils/constatnts/colors.dart';

class TitleMessageList extends StatelessWidget {
  const TitleMessageList({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: getProportionateScreenWidth(12),
        vertical: getProportionateScreenHeight(8),
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: getProportionateScreenWidth(8),
          vertical: getProportionateScreenHeight(6),
        ),
        decoration: BoxDecoration(
          color: AppColors.lavendar.withAlpha(30),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: getProportionateScreenWidth(12),
            fontWeight: FontWeight.w600,
            color: AppColors.purple,
          ),
        ),
      ),
    );
  }
}
