// FILE: data/repositories/purchase_repository.dart
// Backend layer for RevenueCat purchase operations
// Isolated from UI and business logic

import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/PlanTransaction.dart';
import '../models/UserDetails.dart';
import 'NotificationService.dart';
import 'isolate_helper.dart';
import 'dart:io' show Platform;

class PurchaseRepository {
  // static const _apiKey = "zIjkQxKxiPEiVQwTESyczyJvdTNTEGVi";
  static const _apiKey = "goog_fJbYxKAfTbyycozJpXjBZiPsWPD";

  // static const _apiKey = "test_fQfeMuUPMOiDhkQDliNOWdXDEpt";

  /// Initialize RevenueCat SDK
  /// Should be called once during app startup
  Future<void> initialize() async {
    await Purchases.setLogLevel(LogLevel.debug);
    PurchasesConfiguration configuration;
    if (Platform.isAndroid) {
      configuration = PurchasesConfiguration(_apiKey);
      final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
      configuration.appUserID = userId;
      await Purchases.configure(configuration);
    }
    // await Purchases.setup(_apiKey, appUserId: userId);
  }

  /// Fetch all available offerings from RevenueCat
  /// Returns empty list on failure
  Future<List<Offering>> fetchOffers() async {
    try {
      final offerings = await Purchases.getOfferings();
      debugPrint("Offerings: ${offerings.current?.availablePackages.length}");
      return offerings.all.values.toList();
    } on PlatformException catch (e) {
      debugPrint('vinay Error fetching offers: $e');
      return [];
    }
  }

  /// Fetch offerings filtered by specific IDs
  /// Uses isolate for heavy filtering operations
  Future<List<Offering>> fetchOffersByIds(List<String> ids) async {
    final allOffers = await fetchOffers();

    // Filter in isolate if list is large (>10 items)
    if (allOffers.length > 10) {
      return await Isolate.run(() {
        return allOffers
            .where((offer) => ids.contains(offer.identifier))
            .toList();
      });
    }

    // Small lists can run on main thread
    return allOffers.where((offer) => ids.contains(offer.identifier)).toList();
  }

  /// Execute package purchase
  /// Returns true on success, false on failure/cancellation
  Future<bool> purchasePackage(Package package) async {
    try {
      await Purchases.purchasePackage(package);
      return true;
    } catch (e) {
      debugPrint('vinay Purchase error: $e');

      // Handle specific error cases
      if (e is PlatformException) {
        final errorCode = PurchasesErrorHelper.getErrorCode(e);

        // if (errorCode == PurchasesErrorCode.paymentPendingError) {
        //   _showPaymentPendingNotification();
        // } else

        if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
          debugPrint('vinay Purchase cancelled by user');
        } else if (errorCode == PurchasesErrorCode.networkError) {
          _showPurchaseError(
            "No / unstable internet",
            "No internet connection. Please check and try again.",
            Colors.redAccent,
          );
        } else if (errorCode ==
            PurchasesErrorCode.productNotAvailableForPurchaseError) {
          _showPurchaseError(
            "Product inactive / not synced",
            "This product is not available right now.",
            Colors.redAccent,
          );
        } else if (errorCode == PurchasesErrorCode.purchaseNotAllowedError) {
          _showPurchaseError(
            "Parental / policy restriction",
            "Purchases are not allowed on this device.",
            Colors.redAccent,
          );
        } else if (errorCode == PurchasesErrorCode.paymentPendingError) {
          _showPaymentPendingNotification();
          // _showPurchaseError(
          //   "Payment pending",
          //   "Your payment is pending. We'll update once confirmed.",
          //   Colors.orange,
          // );
        } else if (errorCode == PurchasesErrorCode.purchaseInvalidError) {
          _showPurchaseError(
            "Purchase verification failed",
            "We couldn’t verify the purchase. Please try again.",
            Colors.redAccent,
          );
        } else if (errorCode == PurchasesErrorCode.configurationError) {
          _showPurchaseError(
            "RevenueCat / Play setup issue",
            "Something went wrong. Please contact support.",
            Colors.redAccent,
          );
        } else if (errorCode == PurchasesErrorCode.unknownError) {
          _showPurchaseError(
            "Fallback",
            "Purchase failed. Please try again.",
            Colors.redAccent,
          );
        } else {
          _showPurchaseError(
            "Purchase failed",
            "Please try again.",
            Colors.redAccent,
          );
        }
      }

      return false;
    }
  }

  /// Restore previous purchases
  Future<CustomerInfo?> restorePurchases() async {
    try {
      return await Purchases.restorePurchases();
    } catch (e) {
      debugPrint('vinay Error restoring purchases: $e');
      return null;
    }
  }

  /// Get customer information
  Future<CustomerInfo?> getCustomerInfo() async {
    try {
      return await Purchases.getCustomerInfo();
    } catch (e) {
      debugPrint('vinay Error getting customer info: $e');
      return null;
    }
  }

  void _showPaymentPendingNotification() {
    showSimpleNotification(
      Text("Payment pending"),
      leading: CircularProgressIndicator(backgroundColor: Colors.black),
      background: Colors.orange,
      position: NotificationPosition.bottom,
      slideDismiss: true,
      duration: Duration(seconds: 5),
      subtitle: Text(
        "Your payment is pending. We'll update once confirmed.",
      ),
    );
  }

  void _showPurchaseError(String title, String message, Color bgColor) {
    showSimpleNotification(
      Text(title),
      subtitle: Text(message),
      background: bgColor,
      position: NotificationPosition.bottom,
      slideDismiss: true,
      duration: Duration(seconds: 5),
    );
  }
}

// FILE: data/repositories/firestore_repository.dart
// Backend layer for Firestore operations

class FirestoreRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fetch package IDs from Firestore configuration
  Future<List<String>> fetchPackageIds() async {
    try {
      final snapshot = await _firestore
          .collection("InAppPurchase")
          .doc('ids')
          .get();

      if (!snapshot.exists) {
        return [];
      }

      final data = snapshot.data();
      final idArray = data?['idArray'] as List<dynamic>?;

      return idArray?.map((e) => e.toString()).toList() ?? [];
    } catch (e) {
      print('Error fetching package IDs: $e');
      return [];
    }
  }

  /// Fetch user by ID
  /// Uses isolate for JSON parsing if user data is heavy
  Future<UserDetails?> fetchUser(String uid) async {
    try {
      final doc = await _firestore.collection("Users").doc(uid).get();

      if (!doc.exists) return null;

      final data = doc.data();
      if (data == null) return null;

      // Parse in isolate for heavy user objects
      return await Isolate.run(() => UserDetails.fromJson(data));
    } catch (e) {
      print('Error fetching user: $e');
      return null;
    }
  }

  /// Update user field
  Future<void> updateUserField(String userId, Map<String, dynamic> data) async {
    try {
      await _firestore.collection("Users").doc(userId).update(data);
    } catch (e) {
      print('Error updating user field: $e');
      rethrow;
    }
  }

  /// Update current user fields
  Future<void> updateCurrentUser(Map<String, dynamic> data) async {
    try {
      final uid = _getCurrentUserId();
      await _firestore.collection("Users").doc(uid).update(data);
    } catch (e) {
      print('Error updating current user: $e');
      rethrow;
    }
  }

  /// Update online status
  Future<void> updateOnlineStatus(bool isOnline) async {
    try {
      final uid = _getCurrentUserId();

      final updateData = isOnline
          ? {'isOnline': true}
          : {'isOnline': false, 'lastOnline': FieldValue.serverTimestamp()};

      await _firestore.collection("Users").doc(uid).update(updateData);
    } catch (e) {
      print('Error updating online status: $e');
    }
  }

  /// Batch fetch users with filters
  /// Uses isolate for heavy processing
  Future<List<UserDetails>> fetchUsersWithFilters({
    String? state,
    String? city,
    int? minAge,
    int? maxAge,
    int limit = 50,
  }) async {
    try {
      Query query = _firestore.collection("Users").limit(limit);

      if (state != null) {
        query = query.where('state', isEqualTo: state);
      }

      if (city != null) {
        query = query.where('city', isEqualTo: city);
      }

      final snapshot = await query.get();
      final usersJson = snapshot.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();

      // Process in isolate
      return await Isolate.run(() {
        return UserProcessor.batchProcessUsers(
          usersJson: usersJson,
          stateFilter: state,
          cityFilter: city,
          minAge: minAge,
          maxAge: maxAge,
        );
      });
    } catch (e) {
      print('Error fetching users with filters: $e');
      return [];
    }
  }

  /// Listen to document changes
  Stream<DocumentSnapshot<Map<String, dynamic>>> listenToDocument(
    String collection,
    String docId,
  ) {
    return _firestore.collection(collection).doc(docId).snapshots();
  }

  /// Listen to collection changes
  Stream<QuerySnapshot<Map<String, dynamic>>> listenToCollection(
    String collection, {
    Query Function(Query)? queryBuilder,
  }) {
    Query<Map<String, dynamic>> query = _firestore.collection(collection);

    if (queryBuilder != null) {
      query = queryBuilder(query) as Query<Map<String, dynamic>>;
    }

    return query.snapshots();
  }

  String _getCurrentUserId() {
    // This would normally come from FirebaseAuth
    // Kept here for repository isolation
    return "current_user_id"; // Placeholder
  }
}

// FILE: data/repositories/transaction_repository.dart
// Backend layer for transaction operations

class TransactionRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Add transaction and update user coins
  /// Uses Firestore batch for atomic operations
  Future<void> addTransaction(PlanTransaction transaction) async {
    try {
      final batch = _firestore.batch();

      // Add transaction document
      final transactionRef = _firestore
          .collection("Transactions")
          .doc(transaction.transactionId);
      batch.set(transactionRef, transaction.toJson());

      // Update user coins
      final userRef = _firestore
          .collection("Users")
          .doc(FirebaseAuth.instance.currentUser!.uid);
      batch.update(userRef, {"coins": FieldValue.increment(transaction.coins)});

      await batch.commit();

      _showSuccessNotification(transaction.coins);
      _notifyAdmin(transaction);
    } catch (e) {
      print('Error adding transaction: $e');
      rethrow;
    }
  }

  /// Add transaction with isolate for JSON serialization
  /// Use for heavy transaction objects
  Future<void> addTransactionInIsolate(PlanTransaction transaction) async {
    try {
      // Serialize in isolate
      final transactionJson = await Isolate.run(() {
        return TransactionProcessor.serializeTransaction(transaction);
      });

      final batch = _firestore.batch();

      final transactionRef = _firestore
          .collection("Transactions")
          .doc(transaction.transactionId);
      batch.set(transactionRef, transactionJson);

      final userRef = _firestore
          .collection("Users")
          .doc(FirebaseAuth.instance.currentUser!.uid);
      batch.update(userRef, {"coins": FieldValue.increment(transaction.coins)});

      await batch.commit();

      _showSuccessNotification(transaction.coins);
      _notifyAdmin(transaction);
    } catch (e) {
      print('Error adding transaction in isolate: $e');
      rethrow;
    }
  }

  /// Fetch user transaction history
  Future<List<PlanTransaction>> fetchUserTransactions(String userId) async {
    try {
      final snapshot = await _firestore
          .collection("Transactions")
          .where('uId', isEqualTo: userId)
          .orderBy('date', descending: true)
          .get();

      final transactionsJson = snapshot.docs.map((doc) => doc.data()).toList();

      // Parse in isolate for large lists
      if (transactionsJson.length > 20) {
        return await Isolate.run(() {
          return transactionsJson
              .map((json) => PlanTransaction.fromJson(json))
              .toList();
        });
      }

      return transactionsJson
          .map((json) => PlanTransaction.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching transactions: $e');
      return [];
    }
  }

  /// Calculate transaction summary in isolate
  Future<TransactionSummary> calculateTransactionSummary(String userId) async {
    final transactions = await fetchUserTransactions(userId);

    // Calculate summary in isolate
    return await Isolate.run(() {
      return TransactionProcessor.calculateSummary(transactions);
    });
  }

  void _showSuccessNotification(int coins) {
    showSimpleNotification(
      Text("Coins Added Successfully"),
      subtitle: Text("+$coins coins"),
      background: Colors.green,
      duration: Duration(seconds: 4),
      position: NotificationPosition.bottom,
      slideDismiss: true,
      leading: Icon(Icons.verified_outlined),
    );
  }

  void _notifyAdmin(PlanTransaction transaction) {
    NotificationService.sendAdminNotification(
      "Someone just Purchased Coins",
      "${transaction.coins} for ${transaction.price}",
      transaction.uId,
    );
  }
}
