import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
// import 'package:viora/Screens/GemsScreen/gemsScreen.dart'; // Commented: replaced by PaymentScreen
import 'package:viora/Screens/PaymentScreen/payment_screen.dart';
import 'package:viora/components/default_button.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../size_config.dart';
import 'UserProvider.dart';

class CustomDialog {
  static outOfCoinsDialog(context) {
    showDialog(
      context: context,
      builder: (BuildContext context) => Consumer<UserProvider>(
        builder: (context, userProvider, child) => WillPopScope(
          onWillPop: () {
            Navigator.pop(context);

            return Future.value(false);
          },
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Container(
              width: getProportionateScreenWidth(80),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: getProportionateScreenHeight(20)),
                  Text(
                    "OUT OF COINS?",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: getProportionateScreenWidth(24),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: getProportionateScreenHeight(20)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "1",
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: getProportionateScreenWidth(32),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: SvgPicture.asset(
                          "assets/svg/coins.svg",
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: getProportionateScreenHeight(20)),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      "To send a message/Image 1 Coin is required.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      //  color: kPrimaryColor,
                      borderRadius: BorderRadius.all(Radius.circular(25)),
                      border: Border.all(color: kPrimaryColor, width: 3),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          Text("You have "),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                Provider.of<UserProvider>(
                                  context,
                                  listen: false,
                                ).userDetails.coins.toString(),
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: getProportionateScreenWidth(24),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: SvgPicture.asset(
                                  "assets/svg/coins.svg",
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: getProportionateScreenHeight(20)),
                  Padding(
                    padding: const EdgeInsets.all(kDefaultPadding),
                    child: DefaultButton(
                      text: "Buy Now",
                      press: () {
                        Navigator.pop(context);
                        PersistentNavBarNavigator.pushNewScreen(
                          context,
                          // screen: GemsScreen(), // Commented: use PaymentScreen
                          screen: PaymentScreen(),
                          withNavBar: false, // OPTIONAL VALUE. True by default.
                          pageTransitionAnimation:
                              PageTransitionAnimation.cupertino,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void buyImagePackDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (BuildContext context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Consumer<UserProvider>(
          builder: (context, userProvider, child) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: SizedBox(
              width: getProportionateScreenWidth(80),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: getProportionateScreenHeight(20)),
                  Text(
                    "You don’t have a valid subscription !",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: getProportionateScreenWidth(24),
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  SizedBox(height: getProportionateScreenHeight(20)),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      "For sending Images Buy Coin Pack of Rs 1000 or higher.",
                      textAlign: TextAlign.center,
                    ),
                  ),

                  SizedBox(height: getProportionateScreenHeight(20)),
                  Padding(
                    padding: const EdgeInsets.all(kDefaultPadding),
                    child: DefaultButton(
                      text: "Buy Now",
                      press: () {
                        Navigator.pop(context);
                        PersistentNavBarNavigator.pushNewScreen(
                          context,
                          // screen: GemsScreen(), // Commented: use PaymentScreen
                          screen: PaymentScreen(),
                          withNavBar: false, // OPTIONAL VALUE. True by default.
                          pageTransitionAnimation:
                              PageTransitionAnimation.cupertino,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
