import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:viora/constants.dart';
import 'package:viora/size_config.dart';

class QuitAppDialog {
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(horizontal: 5),
            child: _QuitAppDialogContent(),
          ),
        );
      },
    );
    return result ?? false;
  }
}

class _QuitAppDialogContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Stack(
      clipBehavior: Clip.none,
      children: [
      
        // Main dialog container with background image
        Container(
          width: screenWidth * 0.87,
        
          height: getProportionateScreenHeight(240),
          decoration: BoxDecoration(
            color: kBackgroundBG,
            borderRadius: BorderRadius.circular(12)),
          child: Stack(
            children: [
              // Background image
                Positioned(
        left: -170,
        top: -95,
        child: Image.asset(
          'assets/icon/viora_transparent.png',
          width: 370,
          height: 370,
          fit: BoxFit.contain,
        ),
      ),
      Positioned(
        right: -100,
        top: -145,
        child: Transform.scale(
          scaleX: -1,
          child: Image.asset(
            'assets/icon/viora_transparent.png',
            width: 310,
            height: 310,
            fit: BoxFit.contain,
          ),
        ),
      ),

              // Content on top
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),

                  // Dialog text
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Click Yes to exit app.\nNo to continue using app.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w600,
                        fontSize: 20,
                        height: 1.35,
                        color: Colors.black,
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Buttons
                  _buildButtons(context),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildButtons(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: getProportionateScreenWidth(30),
      ),
      child: Row(
        children: [
          // Yes button (white background with border)
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pop(true);
                SystemNavigator.pop(); // Exit the app
              },
              child: Container(
                height: getProportionateScreenHeight(60),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: kPrimaryPurple, width: 1.4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text(
                    'Yes',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                      color: Color(0xFF323232),
                    ),
                  ),
                ),
              ),
            ),
          ),

          SizedBox(width: getProportionateScreenWidth(11)),

          // No button (gradient background)
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pop(false);
              },
              child: Container(
                height: getProportionateScreenHeight(60),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [kPrimaryPurple, kTertiaryPink],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text(
                    'No',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
