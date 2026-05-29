import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class UserService {
  UserService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> ensureUserDocument(User user) async {
    final docRef = _firestore.collection('Users').doc(user.uid);

    await docRef.set({
      'uid': user.uid,
      'email': user.email,
      'displayName': user.displayName,
      'photoURL': user.photoURL,
      'phoneNumber': user.phoneNumber,
      'providerIds': user.providerData.map((e) => e.providerId).toList(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Fetch the most recent deleted account for a user by uid
  /// Returns the deleted account document snapshot if found
  static Future<DocumentSnapshot?> getDeletedAccountForRestoration(
    String uid,
  ) async {
    try {
      // Query DeletedAccounts collection for this uid, ordered by deletedAt (most recent first)
      final query = await _firestore
          .collection('DeletedAccounts')
          .where('uid', isEqualTo: uid)
          .orderBy('deletedAt', descending: true)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        debugPrint(
          "❌ No deleted account found for uid: $uid in DeletedAccounts collection",
        );
        return null;
      }

      return query.docs.first;
    } catch (e) {
      debugPrint("❌ Error fetching deleted account for uid: $uid");
      debugPrint("Error: $e");
      return null;
    }
  }

  /// Restore Subscription subcollection from a deleted account to the new user
  /// Returns true if subscription was successfully restored
  static Future<bool> restoreSubscriptionFromDeletedAccount(
    String uid,
    DocumentSnapshot deletedAccountDoc,
  ) async {
    try {
      // Get the Subscription/current document from the deleted account
      final subscriptionRef = deletedAccountDoc.reference
          .collection('Subscription')
          .doc('current');

      debugPrint('📍 Reading from path: ${subscriptionRef.path}');

      final subscriptionSnap = await subscriptionRef.get();

      if (!subscriptionSnap.exists) {
        return false;
      }

      final subscriptionData = subscriptionSnap.data() ?? {};

      if (subscriptionData.isEmpty) {
        debugPrint("⚠️ [Subscription Restore] Subscription data is empty");
        return false;
      }

      // Restore it to the new user's Subscription/current
      final newUserSubscriptionRef = _firestore
          .collection('Users')
          .doc(uid)
          .collection('Subscription')
          .doc('current');

      debugPrint(
        '📝 [Subscription Restore] Writing to: ${newUserSubscriptionRef.path}',
      );

      await newUserSubscriptionRef.set({
        ...subscriptionData,
      }, SetOptions(merge: true));
      debugPrint(
        '✅ [Subscription Restore] Successfully restored for uid: $uid',
      );
      return true;
    } catch (e, stackTrace) {
      debugPrint("❌ [Subscription Restore] Error for uid: $uid");
      debugPrint("Error: $e");
      debugPrint("StackTrace: $stackTrace");
      return false;
    }
  }
}
