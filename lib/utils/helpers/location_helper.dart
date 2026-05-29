import 'package:geolocator/geolocator.dart';

/// Calculate distance with rounded result
String getDistanceInKmFormatted(
  double sourceLat,
  double sourceLng,
  double destLat,
  double destLng,
) {
  final distanceInMeters = Geolocator.distanceBetween(
    sourceLat,
    sourceLng,
    destLat,
    destLng,
  );

  final distanceInKm = distanceInMeters / 1000;

  // Round to 1 decimal place
  if (distanceInKm < 1) {
    return "${(distanceInMeters).toStringAsFixed(0)} m";
  } else if (distanceInKm < 100) {
    return "${distanceInKm.toStringAsFixed(1)} km";
  } else {
    return "${distanceInKm.toStringAsFixed(0)} km";
  }
}
