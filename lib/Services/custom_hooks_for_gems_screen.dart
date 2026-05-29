// FILE: business_logic/hooks/use_gems_data.dart
// Custom hook for managing gems data loading
// Integrates Firebase Firestore and RevenueCat with isolate processing

import 'dart:isolate';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:viora/Services/purchase_repository.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'ProgressBarHelper.dart';
import 'gems_business_logic.dart';
import 'isolate_helper.dart';

/// State class for gems data
class GemsState {
  final List<Package> packages;
  final bool isLoading;
  final bool hasError;
  final VoidCallback retry;

  GemsState({
    required this.packages,
    required this.isLoading,
    required this.hasError,
    required this.retry,
  });
}

/// Custom hook to fetch and process gems packages
/// Uses isolates for heavy JSON parsing operations
/// Returns GemsState with loading, error, and data states
GemsState useGemsData() {
  // State hooks for UI state management
  final packages = useState<List<Package>>([]);
  final isLoading = useState(true);
  final hasError = useState(false);
  
  // Track if widget is mounted to prevent disposed errors
  final isMounted = useRef(true);

  // Memoized repository instances (created once per widget lifecycle)
  final purchaseRepo = useMemoized(() => PurchaseRepository(), []);
  final firestoreRepo = useMemoized(() => FirestoreRepository(), []);

  // Callback for loading data
  final loadData = useCallback(() async {
    if (!isMounted.value) return;
    
    isLoading.value = true;
    hasError.value = false;

    try {
      // Step 1: Fetch package IDs from Firestore (Backend Layer)
      final packageIds = await firestoreRepo.fetchPackageIds();

      // Step 2: Fetch offerings from RevenueCat (Backend Layer)
      final offerings = await purchaseRepo.fetchOffersByIds(packageIds);

      // Step 3: Process packages in isolate (Performance Optimization)
      // This heavy operation runs on a separate thread
      final processedPackages = await _processPackagesInIsolate(offerings);

      // Check mounted before setting state
      if (isMounted.value) {
        packages.value = processedPackages;
        isLoading.value = false;
      }
    } catch (e) {
      print('Error loading gems data: $e');
      if (isMounted.value) {
        hasError.value = true;
        isLoading.value = false;
      }
    }
  }, []);

  // Effect hook - runs on mount (like initState)
  useEffect(() {
    isMounted.value = true;
    loadData();
    // Cleanup function (like dispose)
    return () {
      isMounted.value = false;
    };
  }, []);

  return GemsState(
    packages: packages.value,
    isLoading: isLoading.value,
    hasError: hasError.value,
    retry: loadData,
  );
}

/// Process packages in isolate to avoid blocking UI thread
/// This is a SHORT-LIVED isolate for one-time heavy computation
Future<List<Package>> _processPackagesInIsolate(
  List<Offering> offerings,
) async {
  // Use Isolate.run for simple one-time operations (Flutter 3.7+)
  return await Isolate.run(() {
    return PackageProcessor.extractAndSortPackages(offerings);
  });
}

// FILE: business_logic/hooks/use_purchase_handler.dart
// Custom hook for handling purchase operations

class PurchaseHandler {
  final Function(BuildContext, Package) handlePurchase;

  PurchaseHandler({required this.handlePurchase});
}

/// Custom hook for purchase handling logic
/// Separates UI from business logic and backend operations
PurchaseHandler usePurchaseHandler() {
  // Memoized repository instances
  final purchaseRepo = useMemoized(() => PurchaseRepository(), []);
  final transactionRepo = useMemoized(() => TransactionRepository(), []);

  // Callback for handling purchases
  // Uses useCallback to prevent recreation on every build
  final handlePurchase = useCallback((
    BuildContext context,
    Package package,
  ) async {
    // Show loading indicator (UI Layer)
    ProgressBarHelper.load(context);
    ProgressBarHelper.pr.show();

    try {
      // Step 1: Execute purchase (Backend Layer)
      final isSuccess = await purchaseRepo.purchasePackage(package);

      if (isSuccess) {
        // // Step 2: Create transaction model (Business Logic Layer)
        // final transaction = PurchaseBusinessLogic.createTransaction(package);
        //
        // // Step 3: Save transaction to Firestore (Backend Layer)
        // // This operation runs in isolate for heavy JSON serialization
        // await transactionRepo.addTransactionInIsolate(transaction);

        final coinAmount = int.parse(
          GemBusinessLogic.extractCoinAmount(package.storeProduct.identifier),
        );
        _showSuccessNotification(coinAmount);
        // Success UI feedback
        ProgressBarHelper.pr.hide();
      } else {
        ProgressBarHelper.pr.hide();
      }
    } catch (e) {
      print('Purchase error: $e');
      ProgressBarHelper.pr.hide();
      // Show error notification
      _showPurchaseError(context, e);
    }
  }, []);

  return PurchaseHandler(handlePurchase: handlePurchase);
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

void _showPurchaseError(BuildContext context, dynamic error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Purchase failed: ${error.toString()}'),
      backgroundColor: Colors.red,
    ),
  );
}

// FILE: business_logic/hooks/use_firestore_listener.dart
// Custom hook for real-time Firestore listeners

/// Custom hook for listening to Firestore document changes
/// Automatically manages subscription lifecycle
T? useFirestoreDocument<T>({
  required String collection,
  required String docId,
  required T Function(Map<String, dynamic>) parser,
}) {
  final data = useState<T?>(null);
  final isLoading = useState(true);

  useEffect(() {
    // Subscribe to Firestore document
    final subscription = FirebaseFirestore.instance
        .collection(collection)
        .doc(docId)
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.exists) {
              // Parse in isolate for heavy documents
              data.value = parser(snapshot.data()!);
            }
            isLoading.value = false;
          },
          onError: (error) {
            print('Firestore listener error: $error');
            isLoading.value = false;
          },
        );

    // Cleanup: Cancel subscription when widget unmounts
    return subscription.cancel;
  }, [collection, docId]);

  return data.value;
}

/// Custom hook for listening to Firestore collection changes
List<T> useFirestoreCollection<T>({
  required String collection,
  required T Function(Map<String, dynamic>) parser,
  Query Function(CollectionReference)? queryBuilder,
}) {
  final data = useState<List<T>>([]);

  useEffect(() {
    CollectionReference ref = FirebaseFirestore.instance.collection(collection);
    final query = queryBuilder?.call(ref) ?? ref;

    final subscription = query.snapshots().listen(
      (snapshot) {
        data.value = snapshot.docs
            .map((doc) => parser(doc.data() as Map<String, dynamic>))
            .toList();
      },
      onError: (error) {
        print('Firestore collection listener error: $error');
      },
    );

    return subscription.cancel;
  }, [collection]);

  return data.value;
}
