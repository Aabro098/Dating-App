import 'dart:convert';

import 'package:firebase_storage/firebase_storage.dart';

class StoragePathService {
  static bool isHttpUrl(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    return trimmed.startsWith('http://') || trimmed.startsWith('https://');
  }

  static bool isGsUrl(String? value) {
    if (value == null) return false;
    return value.trim().startsWith('gs://');
  }

  static String? extractPath(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final raw = value.trim();
    if (!isHttpUrl(raw) && !isGsUrl(raw)) {
      return raw;
    }

    if (isGsUrl(raw)) {
      final uri = Uri.parse(raw);
      if (uri.pathSegments.isEmpty) return null;
      return uri.pathSegments.join('/');
    }

    final uri = Uri.tryParse(raw);
    if (uri == null) return null;

    final oIndex = uri.pathSegments.indexOf('o');
    if (oIndex == -1 || oIndex + 1 >= uri.pathSegments.length) {
      return null;
    }

    final encodedPath = uri.pathSegments[oIndex + 1];
    return Uri.decodeComponent(encodedPath);
  }

  static Future<String?> resolveToDownloadUrl(String? value) async {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    if (isHttpUrl(value)) {
      return value;
    }

    final path = extractPath(value);
    if (path == null || path.isEmpty) {
      return null;
    }

    final ref = FirebaseStorage.instance.ref().child(path);
    return ref.getDownloadURL();
  }

  static String encodeForTransport(String path) {
    return base64Encode(utf8.encode(path));
  }

  static String? decodeTransport(String? encodedPath) {
    if (encodedPath == null || encodedPath.isEmpty) return null;
    try {
      return utf8.decode(base64Decode(encodedPath));
    } catch (_) {
      return null;
    }
  }
}
