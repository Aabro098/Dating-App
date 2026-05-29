import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Centralized Permission Manager to prevent "Reply already submitted" errors
/// 
/// This class ensures that only ONE permission request happens at a time,
/// preventing conflicts between multiple plugins (permission_handler, telephony, geolocator)
class PermissionManager {
  static final PermissionManager _instance = PermissionManager._internal();
  factory PermissionManager() => _instance;
  PermissionManager._internal();

  // Track ongoing permission requests
  bool _isRequestingPermission = false;
  final Map<Permission, Completer<PermissionStatus>> _pendingRequests = {};
  
  /// Check if any permission request is currently active
  /// Returns true if the permission system is busy
  bool get isPermissionRequestActive => _isRequestingPermission;

  /// Request a permission with queue management to prevent conflicts
  /// 
  /// This method ensures that:
  /// 1. Only one permission is requested at a time
  /// 2. Multiple requests for the same permission are deduplicated
  /// 3. Proper delays are added between different permission types
  Future<PermissionStatus> requestPermission(
    Permission permission, {
    Duration delay = const Duration(milliseconds: 500),
  }) async {
    debugPrint('🔐 [PermissionManager] Requesting ${permission.toString()}');

    // Check if there's already a pending request for this permission
    if (_pendingRequests.containsKey(permission)) {
      debugPrint('⏳ [PermissionManager] Waiting for existing request for ${permission.toString()}');
      return _pendingRequests[permission]!.future;
    }

    // Create a new completer for this request
    final completer = Completer<PermissionStatus>();
    _pendingRequests[permission] = completer;

    try {
      // Wait if another permission is being requested
      while (_isRequestingPermission) {
        debugPrint('⏳ [PermissionManager] Waiting for other permission request to complete...');
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Mark as requesting
      _isRequestingPermission = true;

      // Add delay before requesting to avoid conflicts
      if (delay.inMilliseconds > 0) {
        await Future.delayed(delay);
      }

      // Check current status first
      final currentStatus = await permission.status;
      
      if (currentStatus.isGranted) {
        debugPrint('✅ [PermissionManager] ${permission.toString()} already granted');
        completer.complete(currentStatus);
        return currentStatus;
      }

      // Request the permission
      debugPrint('📱 [PermissionManager] Requesting ${permission.toString()}...');
      final status = await permission.request();
      
      debugPrint('✅ [PermissionManager] ${permission.toString()} result: $status');
      completer.complete(status);
      return status;

    } catch (e, stackTrace) {
      debugPrint('❌ [PermissionManager] Error requesting ${permission.toString()}: $e');
      debugPrint('Stack trace: $stackTrace');
      
      // On error, check current status as fallback
      try {
        final fallbackStatus = await permission.status;
        completer.complete(fallbackStatus);
        return fallbackStatus;
      } catch (fallbackError) {
        // If even status check fails, return denied
        completer.complete(PermissionStatus.denied);
        return PermissionStatus.denied;
      }
    } finally {
      // Clean up
      _isRequestingPermission = false;
      _pendingRequests.remove(permission);
      
      // Add delay after request completes to prevent rapid successive requests
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  /// Check permission status without requesting
  Future<PermissionStatus> checkPermission(Permission permission) async {
    try {
      return await permission.status;
    } catch (e) {
      debugPrint('❌ [PermissionManager] Error checking ${permission.toString()}: $e');
      return PermissionStatus.denied;
    }
  }

  /// Request multiple permissions sequentially with delays
  /// 
  /// This is safer than requesting multiple permissions at once
  Future<Map<Permission, PermissionStatus>> requestMultiplePermissions(
    List<Permission> permissions, {
    Duration delayBetweenRequests = const Duration(milliseconds: 800),
  }) async {
    final Map<Permission, PermissionStatus> results = {};

    for (final permission in permissions) {
      final status = await requestPermission(
        permission,
        delay: delayBetweenRequests,
      );
      results[permission] = status;
    }

    return results;
  }

  /// Check if any permission request is currently in progress
  bool get isRequestingPermission => _isRequestingPermission;

  /// Clear all pending requests (use with caution, typically only on app restart)
  void clearPendingRequests() {
    debugPrint('🧹 [PermissionManager] Clearing all pending requests');
    _pendingRequests.clear();
    _isRequestingPermission = false;
  }
}

/// Extension to make it easier to use PermissionManager
extension PermissionExtension on Permission {
  /// Request this permission using the centralized manager
  Future<PermissionStatus> requestManaged({
    Duration delay = const Duration(milliseconds: 500),
  }) {
    return PermissionManager().requestPermission(this, delay: delay);
  }

  /// Check status using the centralized manager
  Future<PermissionStatus> checkManaged() {
    return PermissionManager().checkPermission(this);
  }
}
