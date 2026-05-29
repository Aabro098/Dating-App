import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Service to monitor and check network connectivity
/// Helps detect slow internet, no internet, and network quality
class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  
  // Network state
  bool _isConnected = true;
  List<ConnectivityResult> _currentConnectivity = [];
  
  // Listeners
  final List<Function(bool)> _connectivityListeners = [];

  // Helper for conditional logging
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[NetworkService] $message');
    }
  }

  /// Initialize network monitoring
  Future<void> initialize() async {
    // Get initial connectivity status
    try {
      _currentConnectivity = await _connectivity.checkConnectivity();
      _isConnected = !_currentConnectivity.contains(ConnectivityResult.none);
      _log('Initial connectivity: $_currentConnectivity, Connected: $_isConnected');
    } catch (e) {
      _log('Error checking initial connectivity: $e');
      _isConnected = true; // Assume connected on error
    }

    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        _currentConnectivity = results;
        final wasConnected = _isConnected;
        _isConnected = !results.contains(ConnectivityResult.none);
        
        _log('Connectivity changed: $results, Connected: $_isConnected');
        
        // Notify listeners if status changed
        if (wasConnected != _isConnected) {
          _notifyListeners(_isConnected);
        }
      },
      onError: (error) {
        _log('Connectivity stream error: $error');
      },
    );
  }

  /// Dispose resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivityListeners.clear();
  }

  /// Check if device has internet connectivity
  bool get isConnected => _isConnected;

  /// Get current connectivity type
  List<ConnectivityResult> get currentConnectivity => _currentConnectivity;

  /// Check if on mobile data (potentially slower/metered)
  bool get isMobileData => _currentConnectivity.contains(ConnectivityResult.mobile);

  /// Check if on WiFi
  bool get isWiFi => _currentConnectivity.contains(ConnectivityResult.wifi);

  /// Add listener for connectivity changes
  void addConnectivityListener(Function(bool) listener) {
    if (!_connectivityListeners.contains(listener)) {
      _connectivityListeners.add(listener);
    }
  }

  /// Remove connectivity listener
  void removeConnectivityListener(Function(bool) listener) {
    _connectivityListeners.remove(listener);
  }

  /// Notify all listeners
  void _notifyListeners(bool isConnected) {
    for (var listener in _connectivityListeners) {
      try {
        listener(isConnected);
      } catch (e) {
        _log('Error notifying listener: $e');
      }
    }
  }

  /// Perform actual internet connectivity check (not just network availability)
  /// This attempts to reach a reliable server to verify actual internet access
  Future<bool> hasInternetAccess({Duration timeout = const Duration(seconds: 5)}) async {
    try {
      // Try to reach Google DNS (reliable and fast)
      final result = await InternetAddress.lookup('google.com').timeout(timeout);
      final hasAccess = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      _log('Internet access check: $hasAccess');
      return hasAccess;
    } on SocketException catch (e) {
      _log('No internet access (SocketException): $e');
      return false;
    } on TimeoutException catch (e) {
      _log('Internet check timeout (slow connection?): $e');
      return false;
    } catch (e) {
      _log('Internet check error: $e');
      return false;
    }
  }

  /// Check network quality by measuring ping time
  /// Returns null if no connection, otherwise ping time in milliseconds
  Future<int?> measureNetworkLatency({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final stopwatch = Stopwatch()..start();
      
      final result = await InternetAddress.lookup('google.com').timeout(timeout);
      
      stopwatch.stop();
      
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        final latency = stopwatch.elapsedMilliseconds;
        _log('Network latency: ${latency}ms');
        return latency;
      }
      return null;
    } catch (e) {
      _log('Latency measurement failed: $e');
      return null;
    }
  }

  /// Get network quality assessment
  Future<NetworkQuality> getNetworkQuality() async {
    if (!_isConnected) {
      return NetworkQuality.offline;
    }

    final latency = await measureNetworkLatency();
    
    if (latency == null) {
      return NetworkQuality.offline;
    } else if (latency < 100) {
      return NetworkQuality.excellent;
    } else if (latency < 300) {
      return NetworkQuality.good;
    } else if (latency < 1000) {
      return NetworkQuality.fair;
    } else {
      return NetworkQuality.poor;
    }
  }

  /// Get recommended timeout based on network quality
  Future<Duration> getRecommendedTimeout({Duration baseTimeout = const Duration(seconds: 30)}) async {
    final quality = await getNetworkQuality();
    
    switch (quality) {
      case NetworkQuality.offline:
        return const Duration(seconds: 5); // Fail fast if offline
      case NetworkQuality.poor:
        return Duration(seconds: baseTimeout.inSeconds * 2); // Double timeout for poor connection
      case NetworkQuality.fair:
        return Duration(seconds: (baseTimeout.inSeconds * 1.5).round()); // 1.5x for fair
      case NetworkQuality.good:
      case NetworkQuality.excellent:
        return baseTimeout;
    }
  }
}

/// Network quality levels
enum NetworkQuality {
  offline,
  poor,      // > 1000ms latency
  fair,      // 300-1000ms latency
  good,      // 100-300ms latency
  excellent, // < 100ms latency
}
