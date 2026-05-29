import 'package:flutter/material.dart';
import 'package:viora/utils/constatnts/colors.dart';

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(Icons.verified, color: AppColors.purple, size: 24),
        Icon(Icons.check, color: Colors.white, size: 16),
      ],
    );
  }
}
