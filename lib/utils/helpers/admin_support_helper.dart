import 'package:flutter/material.dart';
import 'package:viora/utils/constatnts/colors.dart';

class AdminSupportHelper {
  Color color(String status) {
    switch (status) {
      case "new":
        return AppColors.lavendar;
      case "auto-replied":
        return Colors.blue;
      case "resolved":
        return Colors.green;
      case "in-progress":
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String status(String status) {
    switch (status) {
      case "new":
        return "New";
      case "auto-replied":
        return "Auto-Replied";
      case "resolved":
        return "Resolved";
      case "in-progress":
        return "In Progress";
      default:
        return "No Status";
    }
  }
}
