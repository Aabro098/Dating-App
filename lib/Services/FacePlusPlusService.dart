import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:viora/Services/AppConfigService.dart';
import 'package:viora/Services/exceptions/exceptions.dart';

// Helper for conditional logging
void _log(String message) {
  if (kDebugMode) {
    debugPrint('[FacePlusPlus] $message');
  }
}

/// Face++ API Service for gender detection and face quality analysis
class FacePlusPlusService {
  static const String _baseUrl = 'https://api-us.faceplusplus.com/facepp/v3/detect';
  
  // API credentials from Firestore AppConfig
  static String get _apiKey => AppConfigService.facePlusApiKey;
  static String get _apiSecret => AppConfigService.facePlusApiSecret;

  /// Result class for Face++ detection
  static FaceDetectionResult? _lastResult;
  static FaceDetectionResult? get lastResult => _lastResult;

  /// Analyzes a face image and returns detection results
  /// 
  /// [imageBytes] - The image data as bytes (PNG/JPEG)
  /// Returns [FaceDetectionResult] with gender, quality, and other attributes
  static Future<FaceDetectionResult> analyzeImage(Uint8List imageBytes) async {
    try {
      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse(_baseUrl));
      
      // Add API credentials
      request.fields['api_key'] = _apiKey;
      request.fields['api_secret'] = _apiSecret;
      request.fields['return_attributes'] = 'gender,facequality,blur,headpose';
      
      // Add image as file
      request.files.add(
        http.MultipartFile.fromBytes(
          'image_file',
          imageBytes,
          filename: 'selfie.jpg',
        ),
      );

      _log('Sending Face++ API request...');
      
      // Send request with 30 second timeout
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Face++ API request timed out after 30 seconds');
        },
      );
      final response = await http.Response.fromStream(streamedResponse);
      
      _log('Face++ API Response Status: ${response.statusCode}');
      _log('Face++ API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        _lastResult = FaceDetectionResult.fromJson(jsonData);
        return _lastResult!;
      } else {
        final errorData = json.decode(response.body);
        throw FacePlusPlusException(
          'API Error: ${errorData['error_message'] ?? 'Unknown error'}',
          response.statusCode,
        );
      }
    } catch (e, stackTrace) {
      if (e is FacePlusPlusException) rethrow;
      _log('Face++ API error: $e');
      final appException = ErrorHandler.convert(e, stackTrace);
      _log('Converted to: ${appException.runtimeType}');
      throw FacePlusPlusException(appException.userMessage, 0);
    }
  }

  /// Analyzes image from file path
  static Future<FaceDetectionResult> analyzeImageFromFile(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return analyzeImage(bytes);
  }

  /// Validates if the detected gender matches the profile gender
  /// 
  /// [detectedGender] - Gender detected by Face++ ("Male" or "Female")
  /// [profileGender] - Gender from user profile
  static bool validateGender(String? detectedGender, String? profileGender) {
    if (detectedGender == null || profileGender == null) return false;
    
    // Normalize both values for comparison
    final detected = detectedGender.toLowerCase().trim();
    final profile = profileGender.toLowerCase().trim();
    
    return detected == profile;
  }

  /// Checks if the face quality is acceptable for verification
  /// 
  /// [result] - The Face++ detection result
  /// [minQuality] - Minimum quality threshold (default: 70.1 as per Face++ docs)
  static bool isQualityAcceptable(FaceDetectionResult result, {double minQuality = 50.0}) {
    if (result.faces.isEmpty) return false;
    
    final face = result.faces.first;
    final quality = face.attributes?.faceQuality?.value ?? 0;
    
    return quality >= minQuality;
  }

  /// Checks if the image blur is acceptable
  static bool isBlurAcceptable(FaceDetectionResult result, {double maxBlur = 50.0}) {
    if (result.faces.isEmpty) return false;
    
    final face = result.faces.first;
    final blur = face.attributes?.blur?.blurness?.value ?? 100;
    
    return blur < maxBlur;
  }
}

/// Exception class for Face++ API errors
class FacePlusPlusException implements Exception {
  final String message;
  final int statusCode;

  FacePlusPlusException(this.message, this.statusCode);

  @override
  String toString() => 'FacePlusPlusException: $message (Status: $statusCode)';
}

/// Result model for Face++ detection
class FaceDetectionResult {
  final String requestId;
  final int timeUsed;
  final List<DetectedFace> faces;
  final String imageId;
  final int faceNum;

  FaceDetectionResult({
    required this.requestId,
    required this.timeUsed,
    required this.faces,
    required this.imageId,
    required this.faceNum,
  });

  factory FaceDetectionResult.fromJson(Map<String, dynamic> json) {
    return FaceDetectionResult(
      requestId: json['request_id'] ?? '',
      timeUsed: json['time_used'] ?? 0,
      faces: (json['faces'] as List?)
              ?.map((f) => DetectedFace.fromJson(f))
              .toList() ??
          [],
      imageId: json['image_id'] ?? '',
      faceNum: json['face_num'] ?? 0,
    );
  }

  /// Check if a valid face was detected
  bool get hasFace => faces.isNotEmpty;

  /// Get the detected gender (from first face)
  String? get detectedGender => faces.isNotEmpty 
      ? faces.first.attributes?.gender?.value 
      : null;

  /// Get face quality score (from first face)
  double? get faceQuality => faces.isNotEmpty 
      ? faces.first.attributes?.faceQuality?.value 
      : null;

  /// Check if image is too blurry
  bool get isBlurry {
    if (faces.isEmpty) return true;
    final blur = faces.first.attributes?.blur?.blurness?.value ?? 100;
    return blur > 50;
  }
}

/// Detected face model
class DetectedFace {
  final String faceToken;
  final FaceRectangle? faceRectangle;
  final FaceAttributes? attributes;

  DetectedFace({
    required this.faceToken,
    this.faceRectangle,
    this.attributes,
  });

  factory DetectedFace.fromJson(Map<String, dynamic> json) {
    return DetectedFace(
      faceToken: json['face_token'] ?? '',
      faceRectangle: json['face_rectangle'] != null
          ? FaceRectangle.fromJson(json['face_rectangle'])
          : null,
      attributes: json['attributes'] != null
          ? FaceAttributes.fromJson(json['attributes'])
          : null,
    );
  }
}

/// Face rectangle coordinates
class FaceRectangle {
  final int top;
  final int left;
  final int width;
  final int height;

  FaceRectangle({
    required this.top,
    required this.left,
    required this.width,
    required this.height,
  });

  factory FaceRectangle.fromJson(Map<String, dynamic> json) {
    return FaceRectangle(
      top: json['top'] ?? 0,
      left: json['left'] ?? 0,
      width: json['width'] ?? 0,
      height: json['height'] ?? 0,
    );
  }
}

/// Face attributes from Face++ API
class FaceAttributes {
  final GenderAttribute? gender;
  final FaceQualityAttribute? faceQuality;
  final BlurAttribute? blur;
  final HeadPoseAttribute? headpose;

  FaceAttributes({
    this.gender,
    this.faceQuality,
    this.blur,
    this.headpose,
  });

  factory FaceAttributes.fromJson(Map<String, dynamic> json) {
    return FaceAttributes(
      gender: json['gender'] != null
          ? GenderAttribute.fromJson(json['gender'])
          : null,
      faceQuality: json['facequality'] != null
          ? FaceQualityAttribute.fromJson(json['facequality'])
          : null,
      blur: json['blur'] != null ? BlurAttribute.fromJson(json['blur']) : null,
      headpose: json['headpose'] != null
          ? HeadPoseAttribute.fromJson(json['headpose'])
          : null,
    );
  }
}

/// Gender attribute
class GenderAttribute {
  final String value;

  GenderAttribute({required this.value});

  factory GenderAttribute.fromJson(Map<String, dynamic> json) {
    return GenderAttribute(value: json['value'] ?? '');
  }
}

/// Face quality attribute
class FaceQualityAttribute {
  final double value;
  final double threshold;

  FaceQualityAttribute({required this.value, required this.threshold});

  factory FaceQualityAttribute.fromJson(Map<String, dynamic> json) {
    return FaceQualityAttribute(
      value: (json['value'] ?? 0).toDouble(),
      threshold: (json['threshold'] ?? 70.1).toDouble(),
    );
  }
}

/// Blur attribute
class BlurAttribute {
  final BlurValue? blurness;
  final BlurValue? motionblur;
  final BlurValue? gaussianblur;

  BlurAttribute({this.blurness, this.motionblur, this.gaussianblur});

  factory BlurAttribute.fromJson(Map<String, dynamic> json) {
    return BlurAttribute(
      blurness:
          json['blurness'] != null ? BlurValue.fromJson(json['blurness']) : null,
      motionblur: json['motionblur'] != null
          ? BlurValue.fromJson(json['motionblur'])
          : null,
      gaussianblur: json['gaussianblur'] != null
          ? BlurValue.fromJson(json['gaussianblur'])
          : null,
    );
  }
}

/// Blur value
class BlurValue {
  final double value;
  final double threshold;

  BlurValue({required this.value, required this.threshold});

  factory BlurValue.fromJson(Map<String, dynamic> json) {
    return BlurValue(
      value: (json['value'] ?? 0).toDouble(),
      threshold: (json['threshold'] ?? 50).toDouble(),
    );
  }
}

/// Head pose attribute
class HeadPoseAttribute {
  final double pitchAngle;
  final double rollAngle;
  final double yawAngle;

  HeadPoseAttribute({
    required this.pitchAngle,
    required this.rollAngle,
    required this.yawAngle,
  });

  factory HeadPoseAttribute.fromJson(Map<String, dynamic> json) {
    return HeadPoseAttribute(
      pitchAngle: (json['pitch_angle'] ?? 0).toDouble(),
      rollAngle: (json['roll_angle'] ?? 0).toDouble(),
      yawAngle: (json['yaw_angle'] ?? 0).toDouble(),
    );
  }
}
