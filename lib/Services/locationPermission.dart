// location_helper.dart

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import 'PermissionManager.dart';

enum LocationState { initial, loading, success, denied, error }

/// Handles location permission, retrieves coordinates, and updates state and city controllers.
/// [onState] is called to update UI state.
/// [onCoordinates] receives the Position object on success.
/// [stateController] and [cityController] will be updated with state/city names.
/// [showPermissionDialog] is called if permission is denied.
Future<void> requestLocationWithPermission({
  required BuildContext context,
  required ValueChanged<LocationState> onState,
  required ValueChanged<Position?> onCoordinates,
  required TextEditingController stateController,
  required TextEditingController cityController,
  required Future<void> Function() showPermissionDialog,
}) async {
  onState(LocationState.loading);

  try {
    final status = await Permission.location.status;

    if (status.isGranted) {
      await _fetchAndAssignLocation(
        onState: onState,
        onCoordinates: onCoordinates,
        stateController: stateController,
        cityController: cityController,
      );
    } else {
      // Use centralized permission manager to prevent conflicts
      final result = await PermissionManager().requestPermission(
        Permission.location,
        delay: const Duration(milliseconds: 800),
      );

      if (result.isGranted) {
        await _fetchAndAssignLocation(
          onState: onState,
          onCoordinates: onCoordinates,
          stateController: stateController,
          cityController: cityController,
        );
      } else {
        onState(LocationState.denied);
        await showPermissionDialog();
      }
    }
  } catch (e) {
    onState(LocationState.error);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to get location: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// Helper method: get device location, assign state/city, update callbacks.
Future<void> _fetchAndAssignLocation({
  required ValueChanged<LocationState> onState,
  required ValueChanged<Position?> onCoordinates,
  required TextEditingController stateController,
  required TextEditingController cityController,
}) async {
  try {
    final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    onCoordinates(position);

    final placemarks =
    await placemarkFromCoordinates(position.latitude, position.longitude);
    if (placemarks.isNotEmpty) {
      final place = placemarks.first;
      stateController.text = place.administrativeArea ?? '';
      cityController.text =
          (place.subAdministrativeArea ?? '').replaceAll("Division", "").trim();
    }

    onState(LocationState.success);
  } catch (e) {
    onState(LocationState.error);
    rethrow;
  }
}
