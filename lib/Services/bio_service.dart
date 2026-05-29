import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:overlay_support/overlay_support.dart';

class BioService {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/',
      headers: {"Content-Type": "application/json"},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  // Do NOT expose this in production Flutter apps.
  // Put Gemini calls behind your backend.
  static final String _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

  Future<String?> generateBio({
    int? age,
    List<String>? interests,
    List<String>? relationshipType,
    String? prompt,
    String? work,
    String? diet,
    String? smoker,
    String? drinker,
    String? zodiac,
    String? nationality,
  }) async {
    final finalPrompt = _buildPrompt(
      age: age,
      interests: interests,
      relationshipType: relationshipType,
      work: work,
      diet: diet,
      smoker: smoker,
      drinker: drinker,
      zodiac: zodiac,
      userPrompt: prompt,
      nationality: nationality,
    );
    try {
      final response = await _dio.post(
        'models/gemini-2.5-flash:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          "contents": [
            {
              "parts": [
                {"text": finalPrompt},
              ],
            },
          ],
          "generationConfig": {
            "maxOutputTokens": 1024,
            "temperature": 0.7,
            "topP": 0.95,
            "topK": 40,
            "responseMimeType": "application/json",
            "responseSchema": {
              "type": "OBJECT",
              "properties": {
                "bio": {"type": "STRING"},
              },
              "required": ["bio"],
            },
            "thinkingConfig": {"thinkingBudget": 0},
          },
          "safetySettings": [
            {
              "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
              "threshold": "BLOCK_MEDIUM_AND_ABOVE",
            },
            {
              "category": "HARM_CATEGORY_HARASSMENT",
              "threshold": "BLOCK_MEDIUM_AND_ABOVE",
            },
          ],
        },
      );

      final candidate = response.data?['candidates']?[0];
      final finishReason = candidate?['finishReason'];

      if (finishReason == 'SAFETY') {
        showSimpleNotification(
          Text('Failed to generate bio. Please try again.'),
          background: Colors.red,
        );
        debugPrint("⚠️ Response blocked by Gemini safety filter.");
        return null;
      }

      if (finishReason == 'MAX_TOKENS') {
        showSimpleNotification(
          Text('Failed to generate bio. Please try again.'),
          background: Colors.red,
        );
        return null;
      }

      final text = candidate?['content']?['parts']?[0]?['text'];

      final bio = _extractBio(text);

      if (bio != null && _isValidBio(bio)) {
        return bio;
      }

      return null;
    } on DioException {
      showSimpleNotification(
        Text('Failed to generate bio. Please try again.'),
        background: Colors.red,
      );
      return null;
    } catch (e) {
      showSimpleNotification(
        Text('Failed to generate bio. Please try again.'),
        background: Colors.red,
      );
      return null;
    }
  }

  String _buildPrompt({
    int? age,
    List<String>? interests,
    List<String>? relationshipType,
    String? userPrompt,
    String? work,
    String? diet,
    String? smoker,
    String? drinker,
    String? zodiac,
    String? nationality,
  }) {
    final cleanInterests = interests
        ?.map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final cleanRelationshipType = relationshipType?.join(', ');
    final cleanUserPrompt = userPrompt?.trim();

    final detailLines = <String>[];

    if (age != null) {
      detailLines.add("- Age: $age");
    }

    if (cleanInterests != null && cleanInterests.isNotEmpty) {
      detailLines.add("- Hobbies: ${cleanInterests.join(', ')}");
    }

    if (cleanRelationshipType != null && cleanRelationshipType.isNotEmpty) {
      detailLines.add("- Looking for: $cleanRelationshipType");
    }

    if (work != null && work.trim().isNotEmpty) {
      detailLines.add("- Work: ${work.trim()}");
    }

    if (diet != null && diet.trim().isNotEmpty) {
      detailLines.add("- Diet: ${diet.trim()}");
    }

    if (smoker != null && smoker.trim().isNotEmpty) {
      detailLines.add("- Smoker: ${smoker.trim()}");
    }

    if (drinker != null && drinker.trim().isNotEmpty) {
      detailLines.add("- Drinker: ${drinker.trim()}");
    }

    if (zodiac != null && zodiac.trim().isNotEmpty) {
      detailLines.add("- Zodiac: ${zodiac.trim()}");
    }

    if (nationality != null && nationality.trim().isNotEmpty) {
      detailLines.add("- Nationality: ${nationality.trim()}");
    }

    if (cleanUserPrompt != null && cleanUserPrompt.isNotEmpty) {
      detailLines.add("- Additional info: $cleanUserPrompt");
    }

    final detailsBlock = detailLines.isEmpty
        ? "No personal details provided."
        : detailLines.join('\n');

    return """
Write exactly ONE dating app bio.

PERSON DETAILS:
$detailsBlock

RULES:
- Use only the details provided.
- If no details are provided, write confident, witty, broadly attractive bullet points without age, hobbies, diet, work, nationality, smoker/drinker status, zodiac, or relationship intent.
- If age is missing, do not mention or imply age.
- If hobbies are missing, do not invent hobbies or activities.
- If diet is missing, do not mention diet.
- If nationality is missing, do not mention nationality.
- If work is missing, do not mention work.
- If smoker is missing, do not mention smoking.
- If drinker is missing, do not mention drinking.
- If zodiac is missing, do not mention zodiac.
- If relationship intent is missing, keep the tone neutral and open.
- If relationship intent is provided, reflect it subtly through tone. Do not state it directly.
- Output exactly 3 bullet points.
- Each bullet must be natural, confident, message-worthy, and profile-ready.
- Total bio text must be 600 to 800 characters.
- Total bio text must not exceed 900 characters.
- Include one subtle hook that makes someone want to reply.
- No emojis.
- No hashtags.
- No markdown outside the JSON.
- No explanation.
- No self-deprecation.
- Do not use these banned phrases: loves to laugh, adventurous soul, work hard play hard, fluent in sarcasm, wanderlust, dog mom, dog dad, living my best life, ride or die, partner in crime, looking for my person, swipe right if, let's vibe, just a girl, just a guy, good vibes only.

OUTPUT FORMAT:
Return valid JSON only.
The "bio" value must be a single string containing exactly 3 bullet points separated by newline characters.
Each bullet must start with "- ".

Example format:
{"bio":"- First bullet here.\n- Second bullet here.\n- Third bullet here."}
""";
  }

  String? _extractBio(String? rawText) {
    if (rawText == null || rawText.trim().isEmpty) return null;

    final cleanedText = rawText
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    try {
      final decoded = jsonDecode(cleanedText);

      if (decoded is Map<String, dynamic>) {
        final bio = decoded["bio"];

        if (bio is String && bio.trim().isNotEmpty) {
          return bio.trim();
        }
      }
    } catch (e) {
      debugPrint("Direct JSON parse error: $e");
    }

    try {
      final start = cleanedText.indexOf('{');
      final end = cleanedText.lastIndexOf('}');

      if (start != -1 && end != -1 && end > start) {
        final jsonString = cleanedText.substring(start, end + 1);
        final decoded = jsonDecode(jsonString);

        if (decoded is Map<String, dynamic>) {
          final bio = decoded["bio"];

          if (bio is String && bio.trim().isNotEmpty) {
            return bio.trim();
          }
        }
      }
    } catch (e) {
      debugPrint("JSON substring parse error: $e");
    }

    return null;
  }

  bool _isValidBio(String bio) {
    final length = bio.length;

    if (length < 200 || length > 800) return false;
    if (bio.contains('#')) return false;

    final emojiRegex = RegExp(
      r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]',
      unicode: true,
    );

    if (emojiRegex.hasMatch(bio)) return false;
    return true;
  }
}
