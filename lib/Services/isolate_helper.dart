// FILE: utils/isolate_helper.dart
//created by Vinay Singhania on 11 october 2025
import 'dart:async';
import 'dart:isolate';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/foundation.dart';

import '../models/PlanTransaction.dart';
import '../models/UserDetails.dart';

class IsolateHelper {
  /// Parse JSON in background isolate
  static Future<T> parseJson<T>(
      Map<String, dynamic> json,
      T Function(Map<String, dynamic>) parser,
      ) async {
    // For web or small data, use compute
    return compute(_parseInIsolate, _ParseData(json, parser));
  }

  static T _parseInIsolate<T>(_ParseData<T> data) {
    return data.parser(data.json);
  }
}

class _ParseData<T> {
  final Map<String, dynamic> json;
  final T Function(Map<String, dynamic>) parser;

  _ParseData(this.json, this.parser);
}
// FILE: business_logic/isolates/package_processor.dart
// Isolate functions for heavy package processing operations
// Runs on separate threads to maintain 60+ FPS on UI thread



/// Package processor for heavy operations
/// All methods are static and run in isolates
class PackageProcessor {
  /// Extract and sort packages from offerings
  /// This operation can be heavy with large package lists
  /// Runs in isolate to avoid blocking UI
  static List<Package> extractAndSortPackages(List<Offering> offerings) {
    if (offerings.isEmpty) {
      return [];
    }

    // Extract all packages from offerings
    final packages = offerings
        .map((offer) => offer.availablePackages)
        .expand((pair) => pair)
        .toList();

    // Sort by price (can be CPU intensive for large lists)
    packages.sort((a, b) => a.storeProduct.price.compareTo(b.storeProduct.price));

    return packages;
  }

  /// Filter packages by specific criteria
  /// Runs in isolate for large datasets
  static List<Package> filterPackages({
    required List<Package> packages,
    double? minPrice,
    double? maxPrice,
    List<String>? allowedIds,
  }) {
    var filtered = packages;

    if (minPrice != null) {
      filtered = filtered.where((p) => p.storeProduct.price >= minPrice).toList();
    }

    if (maxPrice != null) {
      filtered = filtered.where((p) => p.storeProduct.price <= maxPrice).toList();
    }

    if (allowedIds != null && allowedIds.isNotEmpty) {
      filtered = filtered.where((p) => allowedIds.contains(p.identifier)).toList();
    }

    return filtered;
  }
}

// FILE: business_logic/isolates/transaction_processor.dart
// Heavy transaction processing in isolates


class TransactionProcessor {
  /// Serialize transaction to JSON in isolate
  /// Heavy operation for complex transaction data
  static Map<String, dynamic> serializeTransaction(PlanTransaction transaction) {
    // Convert transaction to JSON
    // This can be CPU-intensive with nested objects
    return transaction.toJson();
  }

  /// Batch serialize multiple transactions
  /// Used for bulk operations
  static List<Map<String, dynamic>> batchSerialize(
      List<PlanTransaction> transactions,
      ) {
    return transactions.map((t) => t.toJson()).toList();
  }

  /// Parse transaction from JSON in isolate
  /// Heavy operation for complex JSON parsing
  static PlanTransaction deserializeTransaction(Map<String, dynamic> json) {
    return PlanTransaction.fromJson(json);
  }

  /// Calculate total spending from transaction list
  /// Can be heavy with large datasets
  static TransactionSummary calculateSummary(
      List<PlanTransaction> transactions,
      ) {
    final totalSpending = transactions.fold<int>(
      0,
          (sum, t) => sum + t.price,
    );

    final totalCoins = transactions.fold<int>(
      0,
          (sum, t) => sum + t.coins,
    );

    final averageTransactionValue = transactions.isEmpty
        ? 0.0
        : totalSpending / transactions.length;

    return TransactionSummary(
      totalSpending: totalSpending,
      totalCoins: totalCoins,
      transactionCount: transactions.length,
      averageTransactionValue: averageTransactionValue,
    );
  }
}

class TransactionSummary {
  final int totalSpending;
  final int totalCoins;
  final int transactionCount;
  final double averageTransactionValue;

  TransactionSummary({
    required this.totalSpending,
    required this.totalCoins,
    required this.transactionCount,
    required this.averageTransactionValue,
  });
}

// FILE: business_logic/isolates/user_processor.dart
// Heavy user data processing in isolates



class UserProcessor {
  /// Process user data in isolate
  /// Heavy operation for complex user objects
  static Map<String, dynamic> serializeUser(UserDetails user) {
    return user.toJson();
  }

  /// Parse user from JSON in isolate
  static UserDetails deserializeUser(Map<String, dynamic> json) {
    return UserDetails.fromJson(json);
  }

  /// Batch process multiple users
  /// Used for filtering, sorting large user lists
  static List<UserDetails> batchProcessUsers({
    required List<Map<String, dynamic>> usersJson,
    String? stateFilter,
    String? cityFilter,
    int? minAge,
    int? maxAge,
  }) {
    // Parse all users
    var users = usersJson.map((json) => UserDetails.fromJson(json)).toList();

    // Apply filters
    if (stateFilter != null && stateFilter.isNotEmpty) {
      users = users.where((u) => u.state == stateFilter).toList();
    }

    if (cityFilter != null && cityFilter.isNotEmpty) {
      users = users.where((u) => u.city == cityFilter).toList();
    }

    if (minAge != null) {
      users = users.where((u) => (u.age ?? 0) >= minAge).toList();
    }

    if (maxAge != null) {
      users = users.where((u) => (u.age ?? 0) <= maxAge).toList();
    }

    return users;
  }

  /// Sort users by multiple criteria
  /// CPU-intensive for large lists
  static List<UserDetails> sortUsers({
    required List<UserDetails> users,
    required UserSortCriteria criteria,
  }) {
    switch (criteria) {
      case UserSortCriteria.ageAsc:
        users.sort((a, b) => (a.age ?? 0).compareTo(b.age ?? 0));
        break;
      case UserSortCriteria.ageDesc:
        users.sort((a, b) => (b.age ?? 0).compareTo(a.age ?? 0));
        break;
      case UserSortCriteria.recentJoining:
        users.sort((a, b) {
          final aDate = a.joiningDate ?? DateTime(2000);
          final bDate = b.joiningDate ?? DateTime(2000);
          return bDate.compareTo(aDate);
        });
        break;
      case UserSortCriteria.coinsDesc:
        users.sort((a, b) => (b.coins ?? 0).compareTo(a.coins ?? 0));
        break;
    }

    return users;
  }
}

enum UserSortCriteria { ageAsc, ageDesc, recentJoining, coinsDesc }

// FILE: business_logic/isolates/isolate_manager.dart
// Manager for long-lived isolates (persistent background workers)


/// Manager for persistent isolate workers
/// Use for recurring heavy operations
class IsolateManager {
  static final IsolateManager _instance = IsolateManager._internal();
  factory IsolateManager() => _instance;
  IsolateManager._internal();

  Isolate? _workerIsolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  final _responseController = StreamController<dynamic>.broadcast();

  /// Initialize long-lived worker isolate
  Future<void> initializeWorker() async {
    if (_workerIsolate != null) return; // Already initialized

    _receivePort = ReceivePort();

    _workerIsolate = await Isolate.spawn(
      _isolateWorker,
      _receivePort!.sendPort,
    );

    // Listen for messages from isolate
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
      } else {
        _responseController.add(message);
      }
    });

    // Wait for isolate to be ready
    await Future.delayed(Duration(milliseconds: 100));
  }

  /// Send work to isolate and get response
  Future<T> executeInWorker<T>(WorkerTask task) async {
    if (_sendPort == null) {
      await initializeWorker();
    }

    final completer = Completer<T>();
    final responseSubscription = _responseController.stream.listen((response) {
      if (response is WorkerResponse && response.taskId == task.id) {
        if (response.error != null) {
          completer.completeError(response.error!);
        } else {
          completer.complete(response.result as T);
        }
      }
    });

    _sendPort!.send(task);

    final result = await completer.future;
    await responseSubscription.cancel();
    return result;
  }

  /// Dispose isolate worker
  Future<void> dispose() async {
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _sendPort = null;
    _receivePort?.close();
    await _responseController.close();
  }

  /// Isolate worker entry point
  static void _isolateWorker(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message is WorkerTask) {
        try {
          final result = _processTask(message);
          sendPort.send(WorkerResponse(
            taskId: message.id,
            result: result,
          ));
        } catch (e) {
          sendPort.send(WorkerResponse(
            taskId: message.id,
            error: e.toString(),
          ));
        }
      }
    });
  }

  /// Process task in isolate
  static dynamic _processTask(WorkerTask task) {
    switch (task.type) {
      case WorkerTaskType.jsonParsing:
        return _parseJsonTask(task.data);
      case WorkerTaskType.dataTransformation:
        return _transformDataTask(task.data);
      case WorkerTaskType.heavyComputation:
        return _computeTask(task.data);
      default:
        throw Exception('Unknown task type: ${task.type}');
    }
  }

  static dynamic _parseJsonTask(dynamic data) {
    // Heavy JSON parsing logic
    return data; // Placeholder
  }

  static dynamic _transformDataTask(dynamic data) {
    // Heavy data transformation logic
    return data; // Placeholder
  }

  static dynamic _computeTask(dynamic data) {
    // Heavy computation logic
    return data; // Placeholder
  }
}

/// Task to be executed in worker isolate
class WorkerTask {
  final String id;
  final WorkerTaskType type;
  final dynamic data;

  WorkerTask({
    required this.id,
    required this.type,
    required this.data,
  });
}

/// Response from worker isolate
class WorkerResponse {
  final String taskId;
  final dynamic result;
  final String? error;

  WorkerResponse({
    required this.taskId,
    this.result,
    this.error,
  });
}

enum WorkerTaskType {
  jsonParsing,
  dataTransformation,
  heavyComputation,
}