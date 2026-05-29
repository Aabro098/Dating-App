import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:viora/Services/SubscriptionService.dart';

class MessagingRewardConfig {
  final int limit;
  final int period;
  final String source;

  const MessagingRewardConfig({
    required this.limit,
    required this.period,
    required this.source,
  });
}

class MessageHelper {
  MessageHelper._();

  static Future<void> updateLastDateIfNeeded() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final userRef = FirebaseFirestore.instance
          .collection('Users')
          .doc(currentUser.uid);

      final userDoc = await userRef.get();

      if (!userDoc.exists) return;

      final userData = userDoc.data();
      if (userData == null) return;

      final today = DateUtils.dateOnly(DateTime.now());

      final rawLastDate = userData['lastDate'];
      DateTime? storedLastDate;

      if (rawLastDate is Timestamp) {
        storedLastDate = rawLastDate.toDate();
      } else if (rawLastDate is DateTime) {
        storedLastDate = rawLastDate;
      } else if (rawLastDate is String) {
        storedLastDate = DateTime.tryParse(rawLastDate);
      }

      final DateTime? storedDateOnly = storedLastDate == null
          ? null
          : DateUtils.dateOnly(storedLastDate);

      if (storedDateOnly != null &&
          DateUtils.isSameDay(storedDateOnly, today)) {
        return;
      }

      final rewardConfig = await getMessagingRewardConfig(
        uid: currentUser.uid,
        userData: userData,
      );

      if (rewardConfig == null) {
        return;
      }

      final limit = rewardConfig.limit;
      final period = rewardConfig.period;

      // 0 means do not update.
      // -1 is allowed as unlimited/free-pass value.
      // if (limit == 0) {
      //   debugPrint('ℹ️ [HOME] reward limit is 0, skipping coin update');
      //   return;
      // }

      if (period <= 0) {
        return;
      }

      if (storedDateOnly == null) {
        await userRef.update({
          'lastDate': Timestamp.fromDate(today),
          'coins': limit,
        });
        return;
      }

      final dayDifference = today.difference(storedDateOnly).inDays;

      // Only update when the elapsed days are strictly greater than or equal to the period.
      // i.e. require dayDifference >= period (period <= dayDifference) to proceed.
      if (dayDifference < period) {
        return;
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        transaction.update(userRef, {
          'coins': limit,
          'lastDate': Timestamp.fromDate(today),
        });
      });
    } catch (e) {
      debugPrint('❌ [HOME] lastDate update error: $e');
    }
  }

  static Future<MessagingRewardConfig?> getMessagingRewardConfig({
    required String uid,
    required Map<String, dynamic> userData,
  }) async {
    final subState =
        await SubscriptionService.getSubscriptionStateFromFirestore(uid);

    if (subState?.isActive == true) {
      final subLimit = subState?.entitlementFeatures?.getFeatureLimit(
        'messaging',
      );

      final subPeriod = subState?.entitlementFeatures
          ?.getFeature('messaging')
          ?.period;

      if (subLimit != null && subPeriod != null) {
        return MessagingRewardConfig(
          limit: subLimit,
          period: subPeriod,
          source: 'subscription',
        );
      }
    }
    return _getFreeMessagingRewardConfig(userData);
  }

  static Future<MessagingRewardConfig?> _getFreeMessagingRewardConfig(
    Map<String, dynamic> userData,
  ) async {
    final doc = await FirebaseFirestore.instance
        .collection('Subscriptions')
        .doc('freeFeatures')
        .get();

    final data = doc.data();
    if (data == null) return null;

    final genderKey = userData['gender']?.toString().toLowerCase() == 'female'
        ? 'female'
        : 'male';

    final genderData = data[genderKey] as Map<String, dynamic>?;

    final isEnabled = genderData?['isEnable'] as bool? ?? false;
    if (!isEnabled) {
      return null;
    }

    final features = genderData?['features'] as Map<String, dynamic>?;
    final messaging = features?['messaging'] as Map<String, dynamic>?;

    if (messaging == null) return null;

    final limit = _parseInt(messaging['limit']);
    final period = _parseInt(messaging['period']);

    if (limit == null || period == null) {
      debugPrint('ℹ️ [HOME] freeFeatures messaging limit/period missing');
      return null;
    }

    return MessagingRewardConfig(
      limit: limit,
      period: period,
      source: 'freeFeatures',
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;

    if (value is int) return value;

    if (value is num) return value.toInt();

    return int.tryParse(value.toString());
  }
}
