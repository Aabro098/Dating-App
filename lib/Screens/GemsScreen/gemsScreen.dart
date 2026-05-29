// FILE: screens/gems_screen.dart
// Refactored with Flutter Hooks and Isolates
// Author: AI Assistant | Date: Oct 2025
// COMMENTED: Subscription/coins screen replaced by PaymentScreen (Screens/PaymentScreen/payment_screen.dart). Uncomment to restore.

/*
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:provider/provider.dart';
import 'package:viora/Services/SubscriptionService.dart';
import 'package:viora/Services/Global.dart';

import '../../Services/UserProvider.dart';
import '../../Services/custom_hooks_for_gems_screen.dart';
import '../../Services/gems_business_logic.dart';
import '../../constants.dart';
import '../../size_config.dart';
import '../SupportScreen/supportScreen.dart';

/// GemsScreen - UI Layer
/// Responsibility: Display gems/coins purchase interface
/// Uses custom hooks for state management and isolates for heavy operations
class GemsScreen extends HookWidget {
  const GemsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Custom hook to manage gems data loading (Firebase + RevenueCat)
    // Runs isolate operations for JSON parsing of large package lists
    final gemsState = useGemsData();

    // Hook to handle purchase interactions
    final purchaseHandler = usePurchaseHandler();

    // Memoized user coins to prevent unnecessary rebuilds
    final userCoins =
        Provider.of<UserProvider>(context, listen: true).userDetails.coins ?? 0;
    // final userCoins = useMemoized(
    //       () => Provider.of<UserProvider>(context, listen: false)
    //       .userDetails
    //       .coins ?? 0,
    //   [],
    // );

    // Loading state UI
    if (gemsState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Error state UI
    if (gemsState.hasError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text('Failed to load packages'),
              SizedBox(height: 16),
              ElevatedButton(onPressed: gemsState.retry, child: Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Balance Display
                _BalanceHeader(coins: userCoins),

                // Gems Grid
                _GemsGrid(
                  packages: gemsState.packages,
                  onPurchase: (package) async {
                    try {
                      final uid = FirebaseAuth.instance.currentUser!.uid;
                      await SubscriptionService.refreshRevenueCatIdentity(uid);
                      purchaseHandler.handlePurchase(context, package);
                    } catch (e) {
                      print(e);
                    }
                  },
                ),

                // Support Section
                const _SupportSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Balance Header Widget
/// Pure UI component - no business logic
class _BalanceHeader extends StatelessWidget {
  final int coins;

  const _BalanceHeader({required this.coins});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text("Balance:", style: headingStyle),
        Text(" $coins ", style: headingStyle),
        SvgPicture.asset("assets/svg/coins.svg", color: Colors.orangeAccent),
      ],
    );
  }
}

/// Gems Grid Widget
/// Displays purchase packages in a grid
class _GemsGrid extends StatelessWidget {
  final List<Package> packages;
  final Function(Package) onPurchase;

  const _GemsGrid({required this.packages, required this.onPurchase});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
      ),
      itemCount: packages.length,
      itemBuilder: (ctx, index) => PurchaseCard(
        package: packages[index],
        onTap: () => onPurchase(packages[index]),
      ),
    );
  }
}

/// Support Section Widget
class _SupportSection extends StatelessWidget {
  const _SupportSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "For Payment Issues & any other Query Tap Support and contact Us",
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: GestureDetector(
            onTap: () => _navigateToSupport(context),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(8.0),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.support_agent, color: Colors.white),
                  Text("  Chat Support", style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _navigateToSupport(BuildContext context) {
    PersistentNavBarNavigator.pushNewScreen(
      context,
      screen: SupportScreen(),
      withNavBar: false,
      pageTransitionAnimation: PageTransitionAnimation.cupertino,
    );
  }
}

/// Purchase Card Widget
/// Displays individual package purchase option
class PurchaseCard extends StatelessWidget {
  final Package package;
  final VoidCallback onTap;

  const PurchaseCard({Key? key, required this.package, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Extract coin amount from package identifier using business logic
    final coinAmount = GemBusinessLogic.extractCoinAmount(
      package.storeProduct.identifier,
    );
    final isValuePack = GemBusinessLogic.isValueForMoneyPack(
      package.storeProduct.identifier,
    );
    final hasImagePack = package.storeProduct.price >= 1000;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: kPrimaryGradientColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Coin Amount Display
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "$coinAmount ",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: getProportionateScreenWidth(20),
                      ),
                    ),
                    SvgPicture.asset(
                      "assets/svg/coins.svg",
                      color: Colors.orangeAccent,
                      width: getProportionateScreenWidth(20),
                    ),
                  ],
                ),

                // Price Display
                Container(
                  margin: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Text(
                    package.storeProduct.priceString,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: getProportionateScreenWidth(16),
                    ),
                  ),
                ),

                // Image Pack Badge
                if (hasImagePack)
                  const Row(
                    children: [
                      Icon(Icons.image, color: Colors.white),
                      Flexible(
                        child: Text(
                          "Image Sending Pack",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Value for Money Badge
          if (isValuePack)
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  color: Colors.green,
                ),
                width: double.infinity,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Text("Value for Money")],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
*/
