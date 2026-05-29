// FILE: business_logic/gems_business_logic.dart
// Pure business logic functions for gems/coins operations
// No UI dependencies, fully testable

import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/PlanTransaction.dart';
import '../models/UserDetails.dart';

/// Business logic for gems screen
/// Contains pure, stateless functions that can be tested independently
class GemBusinessLogic {
  /// Extract coin amount from package identifier
  // viora_starter - 40 coin - 299 price
  // viora_deluxe - 100 coin - 450 price
  // viora_premium - 500 coin - 999 price
  // viora_elite_2500 - 5000 coin - 2500 price
  static String extractCoinAmount(String identifier) {
    // final regex = RegExp(r'(?<=_)(.*)(?=_)');
    // final match = regex.firstMatch(identifier);
    // return match?.group(0) ?? '0';
    const Map<String, String> coinMap = {
      'viora_starter': '40',
      'viora_deluxe': '100',
      'viora_premium': '500',
      'viora_elite_2500': '5000',
    };
    return coinMap[identifier] ?? '0';
  }

  /// Check if package is marked as "Value for Money"
  static bool isValueForMoneyPack(String identifier) {
    const valuePackIds = ["viora_deluxe", "viora_premium", "viora_elite_2500"];
    return valuePackIds.contains(identifier);
  }

  /// Calculate if package includes image sending feature
  static bool hasImageSendingFeature(double price) {
    return price >= 1000;
  }

  /// Validate package data before purchase
  static ValidationResult validatePackage(Package package) {
    if (package.storeProduct.price <= 0) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Invalid package price',
      );
    }

    final coinAmount = extractCoinAmount(package.storeProduct.identifier);
    if (coinAmount == '0') {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Invalid coin amount',
      );
    }

    return ValidationResult(isValid: true);
  }
}

class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  ValidationResult({required this.isValid, this.errorMessage});
}

// FILE: business_logic/purchase_business_logic.dart
// Business logic for purchase operations

class PurchaseBusinessLogic {
  /// Create a transaction model from a package purchase
  /// Pure function - no side effects
  static PlanTransaction createTransaction(Package package) {
    final coinAmount = int.parse(
      GemBusinessLogic.extractCoinAmount(package.storeProduct.identifier),
    );

    final transactionId = _generateTransactionId();

    return PlanTransaction(
      date: DateTime.now(),
      price: package.storeProduct.price.toInt(),
      coins: coinAmount,
      planId: package.storeProduct.identifier,
      transactionId: transactionId,
      uId: FirebaseAuth.instance.currentUser!.uid,
    );
  }

  /// Generate unique transaction ID
  static String _generateTransactionId() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${uid}_$timestamp';
  }

  /// Calculate discount percentage for a package
  static double calculateDiscountPercentage({
    required double originalPrice,
    required double discountedPrice,
  }) {
    if (originalPrice <= 0) return 0;
    return ((originalPrice - discountedPrice) / originalPrice) * 100;
  }

  /// Determine package tier (Bronze, Silver, Gold, Platinum)
  static PackageTier determinePackageTier(int coins) {
    if (coins >= 500) return PackageTier.platinum;
    if (coins >= 200) return PackageTier.gold;
    if (coins >= 100) return PackageTier.silver;
    return PackageTier.bronze;
  }
}

enum PackageTier { bronze, silver, gold, platinum }

// FILE: business_logic/user_business_logic.dart
// Business logic for user operations

class UserBusinessLogic {
  /// Calculate if user should receive welcome bonus
  static bool shouldReceiveWelcomeBonus(UserDetails user) {
    // Check if user was created in last 24 hours
    final daysSinceJoining = DateTime.now()
        .difference(user.joiningDate ?? DateTime.now())
        .inDays;

    return daysSinceJoining == 0 && user.coins == 0;
  }

  /// Calculate user's total spending
  static int calculateTotalSpending(List<PlanTransaction> transactions) {
    return transactions.fold(0, (sum, transaction) => sum + transaction.price);
  }

  /// Determine if user is premium (based on spending)
  static bool isPremiumUser(int totalSpending) {
    return totalSpending >= 1000;
  }

  /// Calculate coins needed for next reward tier
  static int coinsUntilNextReward(int currentCoins) {
    const rewardTiers = [100, 500, 1000, 5000];

    for (final tier in rewardTiers) {
      if (currentCoins < tier) {
        return tier - currentCoins;
      }
    }

    return 0; // Already at max tier
  }

  /// Validate user profile completion
  static ProfileCompletionStatus checkProfileCompletion(UserDetails user) {
    int completedFields = 0;
    const totalFields = 7;

    if (user.name?.isNotEmpty ?? false) completedFields++;
    if (user.images?.isNotEmpty ?? false) completedFields++;
    if (user.age != null && user.age! > 0) completedFields++;
    if (user.city?.isNotEmpty ?? false) completedFields++;
    if (user.state?.isNotEmpty ?? false) completedFields++;
    if (user.maritalStatus?.isNotEmpty ?? false) completedFields++;
    if (user.sexualOrientation?.isNotEmpty ?? false) completedFields++;

    final percentage = (completedFields / totalFields * 100).round();

    return ProfileCompletionStatus(
      percentage: percentage,
      isComplete: percentage == 100,
      missingFields: totalFields - completedFields,
    );
  }
}

class ProfileCompletionStatus {
  final int percentage;
  final bool isComplete;
  final int missingFields;

  ProfileCompletionStatus({
    required this.percentage,
    required this.isComplete,
    required this.missingFields,
  });
}

// Import statement for models
