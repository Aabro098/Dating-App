import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRImageProcessor {
  static final _textRecognizer = TextRecognizer();

  /// Main method to process and recognize text
  static Future<RecognizedText> recognizeTextFromImage(String imagePath) async {
    // Load the original image
    final originalImage = img.decodeImage(File(imagePath).readAsBytesSync());
    if (originalImage == null) throw Exception('Failed to decode image');

    // Apply preprocessing
    final processedImage = preprocessForOCR(originalImage);

    // Save processed image temporarily
    final tempPath = await _saveTempImage(processedImage);

    // Perform text recognition
    final inputImage = InputImage.fromFilePath(tempPath);
    final recognizedText = await _textRecognizer.processImage(inputImage);

    // Cleanup
    File(tempPath).deleteSync();

    return recognizedText;
  }

  /// Comprehensive preprocessing pipeline
  static img.Image preprocessForOCR(img.Image image) {
    var processed = image.clone();

    // 1. Convert to grayscale
    processed = img.grayscale(processed);

    // 2. Increase contrast
    processed = img.adjustColor(processed, contrast: 1.5, brightness: 1.1);

    // 3. Sharpen the image
    processed = img.convolution(processed, filter: [
       0, -1, 0,
      -1, 5, -1,
       0, -1, 0
       ]);


    // 4. Apply adaptive threshold (converts to black/white)
    processed = _adaptiveThreshold(processed);

    // 5. Denoise
    processed = img.gaussianBlur(processed, radius: 1);

    return processed;
  }

  /// Alternative: Lighter preprocessing for better-quality images
  static img.Image lightPreprocessing(img.Image image) {
    var processed = image.clone();
    processed = img.grayscale(processed);
    processed = img.adjustColor(processed, contrast: 1.3);
    return processed;
  }

  /// Alternative: Aggressive preprocessing for poor-quality images
  static img.Image aggressivePreprocessing(img.Image image) {
    var processed = image.clone();

    // Resize if too large (ML Kit works better with reasonable sizes)
    if (processed.width > 2000 || processed.height > 2000) {
      processed = img.copyResize(
        processed,
        width: processed.width > processed.height ? 2000 : null,
        height: processed.height > processed.width ? 2000 : null,
      );
    }

    processed = img.grayscale(processed);
    processed = img.adjustColor(processed, contrast: 1.8, brightness: 1.2);

    // Strong sharpening
    processed = img.convolution(processed, filter:  [-1, -1, -1, -1, 9, -1, -1, -1, -1]);

    processed = _adaptiveThreshold(processed);
    return processed;
  }

  /// Simple adaptive threshold implementation
  static img.Image _adaptiveThreshold(img.Image image) {
    final result = image.clone();
    final threshold = _calculateOtsuThreshold(image);

    for (var y = 0; y < result.height; y++) {
      for (var x = 0; x < result.width; x++) {
        final pixel = result.getPixel(x, y);
        final luminance = pixel.r.toInt();

        // Convert to pure black or white
        final newValue = luminance > threshold ? 255 : 0;
        result.setPixelRgba(x, y, newValue, newValue, newValue, 255);
      }
    }
    return result;
  }

  /// Otsu's method for automatic threshold calculation
  static int _calculateOtsuThreshold(img.Image image) {
    final histogram = List<int>.filled(256, 0);

    // Build histogram
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        histogram[pixel.r.toInt()]++;
      }
    }

    final total = image.width * image.height;
    double sum = 0;
    for (int i = 0; i < 256; i++) {
      sum += i * histogram[i];
    }

    double sumB = 0;
    int wB = 0;
    int wF = 0;
    double maxVariance = 0;
    int threshold = 0;

    for (int i = 0; i < 256; i++) {
      wB += histogram[i];
      if (wB == 0) continue;

      wF = total - wB;
      if (wF == 0) break;

      sumB += i * histogram[i];
      final mB = sumB / wB;
      final mF = (sum - sumB) / wF;
      final variance = wB * wF * (mB - mF) * (mB - mF);

      if (variance > maxVariance) {
        maxVariance = variance;
        threshold = i;
      }
    }

    return threshold;
  }

  /// Save processed image to temporary file
  static Future<String> _saveTempImage(img.Image image) async {
    final tempDir = await getTemporaryDirectory();
    final tempPath =
        '${tempDir.path}/processed_${DateTime.now().millisecondsSinceEpoch}.png';
    File(tempPath).writeAsBytesSync(img.encodePng(image));
    return tempPath;
  }

  /// Try multiple preprocessing strategies and return best result
  static Future<RecognizedText> recognizeWithMultipleStrategies(
    String imagePath,
  ) async {
    final originalImage = img.decodeImage(File(imagePath).readAsBytesSync());
    if (originalImage == null) throw Exception('Failed to decode image');

    final strategies = [
      ('light', lightPreprocessing(originalImage)),
      ('standard', preprocessForOCR(originalImage)),
      ('aggressive', aggressivePreprocessing(originalImage)),
    ];

    RecognizedText? bestResult;
    int maxTextLength = 0;

    for (final (name, processed) in strategies) {
      final tempPath = await _saveTempImage(processed);
      final inputImage = InputImage.fromFilePath(tempPath);
      final result = await _textRecognizer.processImage(inputImage);
      File(tempPath).deleteSync();

      print('Strategy "$name" found ${result.text.length} characters');

      if (result.text.length > maxTextLength) {
        maxTextLength = result.text.length;
        bestResult = result;
      }
    }

    return bestResult ?? RecognizedText(text: '', blocks: []);
  }

  void dispose() {
    _textRecognizer.close();
  }
}
