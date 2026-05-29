import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:viora/Services/AppConfigService.dart';

class VisionNsfwService {
  VisionNsfwService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'Content-Type': 'application/json'},
            ),
          );

  final Dio _dio;

  String get _apiKey {
    final key = dotenv.env['GOOGLE_VISION_API_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception('GOOGLE_VISION_API_KEY is missing');
    }
    return key;
  }

  String get _url =>
      'https://vision.googleapis.com/v1/images:annotate?key=$_apiKey';

  Future<List<ImageModerationResult>> analyzeImages(List<File> images) async {
    return Future.wait(images.map(analyzeSingle));
  }

  Future<ImageModerationResult> analyzeSingle(File image) async {
    if (!await image.exists()) {
      return ImageModerationResult.rejected(reason: 'Image file not found');
    }

    final bytes = await image.readAsBytes();

    if (bytes.isEmpty) {
      return ImageModerationResult.rejected(reason: 'Image file is empty');
    }

    if (bytes.length > 20 * 1024 * 1024) {
      return ImageModerationResult.rejected(reason: 'Image file too large');
    }

    try {
      final response = await _dio.post(
        _url,
        data: {
          "requests": [
            {
              "image": {"content": base64Encode(bytes)},
              "features": [
                {"type": "SAFE_SEARCH_DETECTION", "maxResults": 1},
                {"type": "TEXT_DETECTION", "maxResults": 10},
              ],
            },
          ],
        },
      );

      final responses = response.data['responses'] as List?;
      if (responses == null || responses.isEmpty) {
        return ImageModerationResult.rejected(
          reason: 'Invalid Vision response',
        );
      }

      final data = responses.first as Map<String, dynamic>;

      if (data['error'] != null) {
        return ImageModerationResult.rejected(
          reason: 'Vision API error: ${data['error']['message'] ?? 'unknown'}',
        );
      }

      final safeSearch =
          (data['safeSearchAnnotation'] as Map<String, dynamic>?) ?? {};

      final textAnnotations =
          (data['textAnnotations'] as List?)?.cast<Map<String, dynamic>>() ??
          [];

      return _evaluateStrictly(
        safeSearch: safeSearch,
        textAnnotations: textAnnotations,
      );
    } catch (e) {
      return ImageModerationResult.rejected(
        reason: 'Failed to analyze image: $e',
      );
    }
  }

  ImageModerationResult _evaluateStrictly({
    required Map<String, dynamic> safeSearch,
    required List<Map<String, dynamic>> textAnnotations,
  }) {
    final adult = _likelihoodValue(safeSearch['adult']);
    // final racy = _likelihoodValue(safeSearch['racy']);

    // Reject NSFW images.
    if (adult == 5) {
      return ImageModerationResult.rejected(
        reason: 'Rejected: inappropriate image content suspected',
        nsfwScore: _scoreLikelihood(adult),
      );
    }

    final textCheck = _getDisallowedTextReason(textAnnotations);

    if (textCheck != null) {
      return ImageModerationResult.rejected(reason: textCheck, nsfwScore: 0.0);
    }

    return ImageModerationResult.accepted(nsfwScore: 0.0, category: 'general');
  }

  String? _getDisallowedTextReason(List<Map<String, dynamic>> textAnnotations) {
    if (textAnnotations.isEmpty) return null;

    final fullText = (textAnnotations.first['description'] ?? '')
        .toString()
        .trim();

    if (fullText.isEmpty) return null;

    final normalized = fullText.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lowerText = normalized.toLowerCase();

    if (normalized.isEmpty) return null;

    final emailRegex = AppConfigService.emailRegex;
    final phoneRegex = AppConfigService.phoneRegex;
    final socialProfileRegex = AppConfigService.socialProfileRegex;
    final suspiciousEmailTextRegex = AppConfigService.suspiciousEmailRegex;
    final socialUrlRegex = AppConfigService.socialUrlRegex;
    final genericUrlRegex = AppConfigService.genericUrlRegex;

    final handleRegex = RegExp(r'(?<!\w)@[a-zA-Z0-9._]{3,}(?!\w)');

    final contactIntentRegex = RegExp(
      r'\b(call|contact|phone|mobile|number|whatsapp|message me|text me|dm me|reach me|email me|mail me)\b',
      caseSensitive: false,
    );

    final hasEmail = emailRegex.hasMatch(normalized);
    final hasPhone = phoneRegex.hasMatch(normalized);
    final hasSocialProfile = socialProfileRegex.hasMatch(lowerText);
    final hasSocialUrl = socialUrlRegex.hasMatch(lowerText);
    final hasGenericUrl = genericUrlRegex.hasMatch(lowerText);
    final hasHandle = handleRegex.hasMatch(normalized);
    final hasContactIntent = contactIntentRegex.hasMatch(lowerText);
    final hasSuspiciousEmailText = suspiciousEmailTextRegex.hasMatch(lowerText);

    if (hasEmail) {
      return 'Rejected: image contains an email address';
    }

    if (hasPhone) {
      return 'Rejected: image contains a phone number';
    }

    if (hasSocialUrl || hasSocialProfile || hasHandle) {
      return 'Rejected: image contains social media or profile information';
    }

    if (hasGenericUrl) {
      return 'Rejected: image contains a website link';
    }

    if (hasContactIntent || hasSuspiciousEmailText) {
      return 'Rejected: image contains contact-related text';
    }

    return null;
  }

  int _likelihoodValue(dynamic value) {
    switch ((value ?? '').toString()) {
      case 'VERY_UNLIKELY':
        return 1;
      case 'UNLIKELY':
        return 2;
      case 'POSSIBLE':
        return 3;
      case 'LIKELY':
        return 4;
      case 'VERY_LIKELY':
        return 5;
      default:
        return 0; // UNKNOWN
    }
  }

  double _scoreLikelihood(int level) {
    switch (level) {
      case 5:
        return 1.0;
      case 4:
        return 0.85;
      case 3:
        return 0.65;
      case 2:
        return 0.25;
      case 1:
        return 0.05;
      default:
        return 0.0;
    }
  }

  // static const Set<String> _hardRejectKeywords = {
  //   'text',
  //   'font',
  //   'document',
  //   'paper',
  //   'receipt',
  //   'invoice',
  //   'logo',
  //   'brand',
  //   'sign',
  //   'screenshot',
  //   'software',
  //   'website',
  //   'web page',
  //   'app',
  //   'mobile phone',
  //   'diagram',
  //   'chart',
  //   'plot',
  //   'map',
  //   'symbol',
  //   'number',
  //   'handwriting',
  //   'facebook',
  //   'telegram',
  // };
}

class ImageModerationResult {
  final bool accepted;
  final double nsfwScore;
  final String reason;
  final String? category;

  const ImageModerationResult({
    required this.accepted,
    required this.nsfwScore,
    required this.reason,
    this.category,
  });

  factory ImageModerationResult.accepted({
    required double nsfwScore,
    required String category,
  }) {
    return ImageModerationResult(
      accepted: true,
      nsfwScore: nsfwScore,
      reason: 'Accepted',
      category: category,
    );
  }

  factory ImageModerationResult.rejected({
    required String reason,
    double nsfwScore = 0.0,
  }) {
    return ImageModerationResult(
      accepted: false,
      nsfwScore: nsfwScore,
      reason: reason,
    );
  }

  Map<String, dynamic> toJson() => {
    'accepted': accepted,
    'nsfw': nsfwScore,
    'reason': reason,
    'category': category,
  };
}
