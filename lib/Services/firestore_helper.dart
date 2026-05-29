import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'exceptions/exceptions.dart';

/// Firestore operation wrapper with centralized error handling
/// 
/// Usage:
/// ```dart
/// final result = await FirestoreHelper.get(
///   collection: 'Users',
///   docId: userId,
/// );
/// 
/// await FirestoreHelper.set(
///   collection: 'Users',
///   docId: userId,
///   data: userData,
/// );
/// ```
class FirestoreHelper {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Default timeout for Firestore operations
  static const Duration _defaultTimeout = Duration(seconds: 30);

  /// Get a single document
  static Future<DocumentSnapshot<Map<String, dynamic>>> get({
    required String collection,
    required String docId,
    Duration? timeout,
  }) async {
    try {
      _log('GET: $collection/$docId');
      return await _firestore
          .collection(collection)
          .doc(docId)
          .get()
          .timeout(timeout ?? _defaultTimeout, onTimeout: () {
            throw TimeoutAppException(
              technicalMessage: 'Firestore GET timed out: $collection/$docId',
              code: 'FIRESTORE_GET_TIMEOUT',
            );
          });
    } on TimeoutAppException {
      rethrow;
    } on FirebaseException catch (e, stackTrace) {
      throw ErrorHandler.convert(e, stackTrace);
    } catch (e, stackTrace) {
      throw ErrorHandler.convert(e, stackTrace);
    }
  }

  /// Set a document (creates or overwrites)
  static Future<void> set({
    required String collection,
    required String docId,
    required Map<String, dynamic> data,
    bool merge = false,
    Duration? timeout,
  }) async {
    try {
      _log('SET: $collection/$docId');
      await _firestore
          .collection(collection)
          .doc(docId)
          .set(data, SetOptions(merge: merge))
          .timeout(timeout ?? _defaultTimeout, onTimeout: () {
            throw TimeoutAppException(
              technicalMessage: 'Firestore SET timed out: $collection/$docId',
              code: 'FIRESTORE_SET_TIMEOUT',
            );
          });
    } on TimeoutAppException {
      rethrow;
    } on FirebaseException catch (e, stackTrace) {
      throw ErrorHandler.convert(e, stackTrace);
    } catch (e, stackTrace) {
      throw ErrorHandler.convert(e, stackTrace);
    }
  }

  /// Update a document (partial update)
  static Future<void> update({
    required String collection,
    required String docId,
    required Map<String, dynamic> data,
    Duration? timeout,
  }) async {
    try {
      _log('UPDATE: $collection/$docId');
      await _firestore
          .collection(collection)
          .doc(docId)
          .update(data)
          .timeout(timeout ?? _defaultTimeout, onTimeout: () {
            throw TimeoutAppException(
              technicalMessage: 'Firestore UPDATE timed out: $collection/$docId',
              code: 'FIRESTORE_UPDATE_TIMEOUT',
            );
          });
    } on TimeoutAppException {
      rethrow;
    } on FirebaseException catch (e, stackTrace) {
      throw ErrorHandler.convert(e, stackTrace);
    } catch (e, stackTrace) {
      throw ErrorHandler.convert(e, stackTrace);
    }
  }

  /// Delete a document
  static Future<void> delete({
    required String collection,
    required String docId,
    Duration? timeout,
  }) async {
    try {
      _log('DELETE: $collection/$docId');
      await _firestore
          .collection(collection)
          .doc(docId)
          .delete()
          .timeout(timeout ?? _defaultTimeout, onTimeout: () {
            throw TimeoutAppException(
              technicalMessage: 'Firestore DELETE timed out: $collection/$docId',
              code: 'FIRESTORE_DELETE_TIMEOUT',
            );
          });
    } on TimeoutAppException {
      rethrow;
    } on FirebaseException catch (e, stackTrace) {
      throw ErrorHandler.convert(e, stackTrace);
    } catch (e, stackTrace) {
      throw ErrorHandler.convert(e, stackTrace);
    }
  }

  /// Query documents with conditions
  static Future<QuerySnapshot<Map<String, dynamic>>> query({
    required String collection,
    List<QueryCondition>? conditions,
    String? orderBy,
    bool descending = false,
    int? limit,
    Duration? timeout,
  }) async {
    try {
      _log('QUERY: $collection');
      
      Query<Map<String, dynamic>> query = _firestore.collection(collection);
      
      // Apply conditions
      if (conditions != null) {
        for (final condition in conditions) {
          query = _applyCondition(query, condition);
        }
      }
      
      // Apply ordering
      if (orderBy != null) {
        query = query.orderBy(orderBy, descending: descending);
      }
      
      // Apply limit
      if (limit != null) {
        query = query.limit(limit);
      }
      
      return await query.get().timeout(
        timeout ?? _defaultTimeout,
        onTimeout: () {
          throw TimeoutAppException(
            technicalMessage: 'Firestore QUERY timed out: $collection',
            code: 'FIRESTORE_QUERY_TIMEOUT',
          );
        },
      );
    } on TimeoutAppException {
      rethrow;
    } on FirebaseException catch (e, stackTrace) {
      throw ErrorHandler.convert(e, stackTrace);
    } catch (e, stackTrace) {
      throw ErrorHandler.convert(e, stackTrace);
    }
  }

  /// Add a document with auto-generated ID
  static Future<DocumentReference<Map<String, dynamic>>> add({
    required String collection,
    required Map<String, dynamic> data,
    Duration? timeout,
  }) async {
    try {
      _log('ADD: $collection');
      return await _firestore
          .collection(collection)
          .add(data)
          .timeout(timeout ?? _defaultTimeout, onTimeout: () {
            throw TimeoutAppException(
              technicalMessage: 'Firestore ADD timed out: $collection',
              code: 'FIRESTORE_ADD_TIMEOUT',
            );
          });
    } on TimeoutAppException {
      rethrow;
    } on FirebaseException catch (e, stackTrace) {
      throw ErrorHandler.convert(e, stackTrace);
    } catch (e, stackTrace) {
      throw ErrorHandler.convert(e, stackTrace);
    }
  }

  /// Run a transaction
  static Future<T> runTransaction<T>({
    required Future<T> Function(Transaction transaction) transactionHandler,
    Duration? timeout,
    int maxAttempts = 5,
  }) async {
    try {
      _log('TRANSACTION START');
      return await _firestore
          .runTransaction(
            transactionHandler,
            maxAttempts: maxAttempts,
            timeout: timeout ?? const Duration(seconds: 60),
          );
    } on FirebaseException catch (e, stackTrace) {
      throw ErrorHandler.convert(e, stackTrace);
    } catch (e, stackTrace) {
      throw ErrorHandler.convert(e, stackTrace);
    }
  }

  /// Run a batch write
  static Future<void> runBatch({
    required void Function(WriteBatch batch) batchHandler,
    Duration? timeout,
  }) async {
    try {
      _log('BATCH START');
      final batch = _firestore.batch();
      batchHandler(batch);
      await batch.commit().timeout(
        timeout ?? _defaultTimeout,
        onTimeout: () {
          throw TimeoutAppException(
            technicalMessage: 'Firestore BATCH timed out',
            code: 'FIRESTORE_BATCH_TIMEOUT',
          );
        },
      );
    } on TimeoutAppException {
      rethrow;
    } on FirebaseException catch (e, stackTrace) {
      throw ErrorHandler.convert(e, stackTrace);
    } catch (e, stackTrace) {
      throw ErrorHandler.convert(e, stackTrace);
    }
  }

  /// Apply a condition to a query
  static Query<Map<String, dynamic>> _applyCondition(
    Query<Map<String, dynamic>> query,
    QueryCondition condition,
  ) {
    switch (condition.operator) {
      case QueryOperator.isEqualTo:
        return query.where(condition.field, isEqualTo: condition.value);
      case QueryOperator.isNotEqualTo:
        return query.where(condition.field, isNotEqualTo: condition.value);
      case QueryOperator.isLessThan:
        return query.where(condition.field, isLessThan: condition.value);
      case QueryOperator.isLessThanOrEqualTo:
        return query.where(condition.field, isLessThanOrEqualTo: condition.value);
      case QueryOperator.isGreaterThan:
        return query.where(condition.field, isGreaterThan: condition.value);
      case QueryOperator.isGreaterThanOrEqualTo:
        return query.where(condition.field, isGreaterThanOrEqualTo: condition.value);
      case QueryOperator.arrayContains:
        return query.where(condition.field, arrayContains: condition.value);
      case QueryOperator.arrayContainsAny:
        return query.where(condition.field, arrayContainsAny: condition.value);
      case QueryOperator.whereIn:
        return query.where(condition.field, whereIn: condition.value);
      case QueryOperator.whereNotIn:
        return query.where(condition.field, whereNotIn: condition.value);
      case QueryOperator.isNull:
        return query.where(condition.field, isNull: condition.value);
    }
  }

  /// Debug logging
  static void _log(String message) {
    if (kDebugMode) {
      debugPrint('[FirestoreHelper] $message');
    }
  }
}

/// Query condition helper
class QueryCondition {
  final String field;
  final QueryOperator operator;
  final dynamic value;

  QueryCondition({
    required this.field,
    required this.operator,
    required this.value,
  });

  /// Convenience constructors
  factory QueryCondition.equals(String field, dynamic value) =>
      QueryCondition(field: field, operator: QueryOperator.isEqualTo, value: value);
  
  factory QueryCondition.notEquals(String field, dynamic value) =>
      QueryCondition(field: field, operator: QueryOperator.isNotEqualTo, value: value);
  
  factory QueryCondition.lessThan(String field, dynamic value) =>
      QueryCondition(field: field, operator: QueryOperator.isLessThan, value: value);
  
  factory QueryCondition.greaterThan(String field, dynamic value) =>
      QueryCondition(field: field, operator: QueryOperator.isGreaterThan, value: value);
  
  factory QueryCondition.arrayContains(String field, dynamic value) =>
      QueryCondition(field: field, operator: QueryOperator.arrayContains, value: value);
  
  factory QueryCondition.whereIn(String field, List<dynamic> value) =>
      QueryCondition(field: field, operator: QueryOperator.whereIn, value: value);
}

/// Query operators
enum QueryOperator {
  isEqualTo,
  isNotEqualTo,
  isLessThan,
  isLessThanOrEqualTo,
  isGreaterThan,
  isGreaterThanOrEqualTo,
  arrayContains,
  arrayContainsAny,
  whereIn,
  whereNotIn,
  isNull,
}
