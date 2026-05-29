import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

class UserDetails {
  String? name;
  String? email;
  String? phone; // Full phone number with country code (e.g., '+919874957389')
  String? state;
  String? gender;
  bool? isOnline, isDisabled, isVerified;
  String? city;
  String? isTyping;
  String? fcmToken;
  String? verifiedImageUrl; // URL of the verification photo
  String? verifiedImagePath; // Storage path of the verification photo
  int? age;
  String? maritalStatus;
  List<String>? sexualOrientation;
  List<String>? images;
  List<String>? relTypes;
  DateTime? joiningDate, lastOnline, dateOfBirth;
  late String uid;
  int? coins, notiCount, unseenCount, connectionCount;
  double? latitude, longitude;
  int? verificationRetries; // Number of gender mismatch retries
  int?
  safetyTipsVersion; // Version of safety tips user has seen (user-specific)
  // Top Picks scoring fields
  String? about;
  String? diet;
  String? zodiac;
  String? religion;
  String? smoker;
  String? drinking;
  List<String>? interests;
  String? messagePermission; // New field for message permissions
  int? height;
  String? work;
  String? education;
  String? nationality;
  DateTime? lastDate;

  UserDetails({
    this.name,
    this.email,
    this.phone,
    this.state,
    this.city,
    this.age,
    this.dateOfBirth,
    this.images,
    this.joiningDate,
    this.gender,
    this.isOnline,
    this.lastOnline,
    this.fcmToken,
    this.maritalStatus,
    this.sexualOrientation,
    this.relTypes,
    this.isTyping,
    this.coins,
    this.notiCount,
    this.unseenCount,
    this.connectionCount,
    this.isDisabled,
    this.isVerified,
    this.verifiedImageUrl,
    this.verifiedImagePath,
    this.latitude,
    this.longitude,
    this.verificationRetries,
    this.safetyTipsVersion,
    this.about,
    this.diet,
    this.zodiac,
    this.religion,
    this.smoker,
    this.drinking,
    this.interests,
    this.messagePermission,
    this.height,
    this.work,
    this.education,
    this.nationality,
    this.lastDate,
  });

  // EXISTING FIRESTORE METHODS (UNCHANGED)
  UserDetails.fromJson(Map<String, dynamic> json)
    : name = json['name'],
      email = json['email'],
      phone = json['phone'],
      state = json['state'],
      city = json['city'],
      age = json['age'],
      dateOfBirth = json['dateOfBirth'] != null
          ? (json['dateOfBirth'] as Timestamp).toDate()
          : null,
      images = List<String>.from(json['imagePaths'] ?? []),
      relTypes = List<String>.from(json['relTypes'] ?? []),
      joiningDate = json['joiningDate'] != null
          ? (json['joiningDate'] as Timestamp).toDate()
          : null,
      uid = json['uid'],
      gender = json['gender'],
      isOnline = json['isOnline'],
      isDisabled = json['isDisabled'] ?? false,
      isVerified = json['isVerified'] ?? false,
      verifiedImageUrl = json['verifiedImageUrl'],
      verifiedImagePath = json['verifiedImagePath'],
      latitude = json['latitude']?.toDouble(),
      longitude = json['longitude']?.toDouble(),
      fcmToken = json['fcmToken'],
      maritalStatus = json['maritalStatus'],
      sexualOrientation = _parseStringOrList(json['sexualOrientation']),
      isTyping = json['isTyping'],
      unseenCount = json['unseenCount'] ?? 0,
      notiCount = json['notiCount'] ?? 0,
      connectionCount = json['connectionCount'] ?? 0,
      coins = (json['coins'] is num)
          ? (json['coins'] as num).toInt()
          : int.tryParse(json['coins']?.toString() ?? ''),
      verificationRetries = json['verificationRetries'] ?? 0,
      safetyTipsVersion = json['safetyTipsVersion'] ?? 0,
      lastOnline = json['lastOnline'] != null
          ? (json['lastOnline'] as Timestamp).toDate()
          : null,
      // Top Picks scoring fields
      about = json['about'],
      diet = json['diet'],
      zodiac = json['zodiac'],
      religion = json['religion'],
      smoker = json['smoker'],
      drinking = json['drinking'],
      interests = _parseStringOrList(json['interests']),
      messagePermission = json['who_can_message'] ?? "All",
      height = (json['height'] is double)
          ? (json['height'] as double).toInt()
          : json['height'],
      work = json['work'],
      education = json['education'],
      nationality = json['nationality'],
      lastDate = json['lastDate'] != null
          ? (json['lastDate'] as Timestamp).toDate()
          : null;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['name'] = name;
    data['email'] = email;
    data['phone'] = phone;
    data['state'] = state;
    data['city'] = city;
    data['age'] = age;
    data['dateOfBirth'] = dateOfBirth != null
        ? Timestamp.fromDate(dateOfBirth!)
        : null;
    data['imagePaths'] = images;
    data['relTypes'] = relTypes;
    data['joiningDate'] = Timestamp.fromDate(joiningDate!);
    data['uid'] = uid;
    data['gender'] = gender;
    data['isOnline'] = isOnline;
    data['lastOnline'] = Timestamp.fromDate(lastOnline!);
    data['fcmToken'] = fcmToken;
    data['maritalStatus'] = maritalStatus;
    data['sexualOrientation'] = sexualOrientation;
    data['isTyping'] = isTyping;
    data['coins'] = coins;
    data['unseenCount'] = unseenCount;
    data['notiCount'] = notiCount;
    data['connectionCount'] = connectionCount;
    data['isDisabled'] = isDisabled;
    data['isVerified'] = isVerified;
    data['verifiedImageUrl'] = verifiedImageUrl;
    data['verifiedImagePath'] = verifiedImagePath;
    data['verificationRetries'] = verificationRetries;
    data['safetyTipsVersion'] = safetyTipsVersion;
    data['latitude'] = latitude;
    data['longitude'] = longitude;
    data['about'] = about;
    data['diet'] = diet;
    data['zodiac'] = zodiac;
    data['religion'] = religion;
    data['smoker'] = smoker;
    data['drinking'] = drinking;
    data['interests'] = interests;
    data['who_can_message'] = messagePermission;
    data['height'] = height;
    data['work'] = work;
    data['education'] = education;
    data['nationality'] = nationality;
    data['lastDate'] = lastDate != null ? Timestamp.fromDate(lastDate!) : null;
    return data;
  }

  // NEW METHODS SPECIFICALLY FOR SHARED PREFERENCES

  // Convert to JSON String for SharedPreferences (like Collection example)
  String toPrefsString() => json.encode(toPrefsMap());

  // Convert to Map for SharedPreferences (DateTime as ISO8601 strings)
  Map<String, dynamic> toPrefsMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'state': state,
      'city': city,
      'age': age,
      'imagePaths': images,
      'relTypes': relTypes,
      'joiningDate': joiningDate?.toIso8601String(),
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'uid': uid,
      'gender': gender,
      'isOnline': isOnline,
      'lastOnline': lastOnline?.toIso8601String(),
      'fcmToken': fcmToken,
      'maritalStatus': maritalStatus,
      'sexualOrientation': sexualOrientation,
      'isTyping': isTyping,
      'coins': coins,
      'unseenCount': unseenCount,
      'notiCount': notiCount,
      'connectionCount': connectionCount,
      'isDisabled': isDisabled,
      'isVerified': isVerified,
      'verifiedImageUrl': verifiedImageUrl,
      'verifiedImagePath': verifiedImagePath,
      'verificationRetries': verificationRetries,
      'safetyTipsVersion': safetyTipsVersion,
      'latitude': latitude,
      'longitude': longitude,
      // Top Picks scoring fields
      'about': about,
      'diet': diet,
      'zodiac': zodiac,
      'religion': religion,
      'smoker': smoker,
      'drinking': drinking,
      'interests': interests,
      'who_can_message': messagePermission,
      'height': height,
      'work': work,
      'education': education,
      'nationality': nationality,
      'lastDate': lastDate?.toIso8601String(),
    };
  }

  // Create from JSON String (for SharedPreferences)
  factory UserDetails.fromPrefsString(String str) =>
      UserDetails.fromPrefsMap(json.decode(str) as Map<String, dynamic>);

  // Create from Map (for SharedPreferences) - handles ISO8601 strings
  factory UserDetails.fromPrefsMap(Map<String, dynamic> json) {
    return UserDetails(
      name: json['name'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      state: json['state'] as String?,
      city: json['city'] as String?,
      age: json['age'] as int?,
      dateOfBirth: json['dateOfBirth'] != null
          ? DateTime.tryParse(json['dateOfBirth'] as String)
          : null,
      images: (json['imagePaths'] as List?)?.map((e) => e as String).toList(),
      relTypes: (json['relTypes'] as List?)?.map((e) => e as String).toList(),
      joiningDate: json['joiningDate'] != null
          ? DateTime.tryParse(json['joiningDate'] as String)
          : null,
      gender: json['gender'] as String?,
      isOnline: json['isOnline'] as bool?,
      isDisabled: json['isDisabled'] as bool? ?? false,
      isVerified: json['isVerified'] as bool? ?? false,
      verifiedImageUrl: json['verifiedImageUrl'] as String?,
      verifiedImagePath: json['verifiedImagePath'] as String?,
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
      fcmToken: json['fcmToken'] as String?,
      maritalStatus: json['maritalStatus'] as String?,
      sexualOrientation: _parseStringOrList(json['sexualOrientation']),
      isTyping: json['isTyping'] as String?,
      unseenCount: json['unseenCount'] as int? ?? 0,
      notiCount: json['notiCount'] as int? ?? 0,
      connectionCount: json['connectionCount'] as int? ?? 0,
      coins: (json['coins'] is num)
          ? (json['coins'] as num).toInt()
          : int.tryParse(json['coins']?.toString() ?? ''),
      verificationRetries: json['verificationRetries'] as int? ?? 0,
      safetyTipsVersion: json['safetyTipsVersion'] as int? ?? 0,
      lastOnline: json['lastOnline'] != null
          ? DateTime.tryParse(json['lastOnline'] as String)
          : null,
      // Top Picks scoring fields
      about: json['about'] as String?,
      diet: json['diet'] as String?,
      zodiac: json['zodiac'] as String?,
      religion: json['religion'] as String?,
      smoker: json['smoker'] as String?,
      drinking: json['drinking'] as String?,
      interests: (json['interests'] as List?)?.map((e) => e as String).toList(),
      messagePermission: json['who_can_message'] as String?,
      height: json['height'] as int?,
      work: json['work'] as String?,
      education: json['education'] as String?,
      nationality: json['nationality'] as String?,
      lastDate: json['lastDate'] != null
          ? DateTime.tryParse(json['lastDate'] as String)
          : null,
    )..uid = json['uid'] as String? ?? '';
  }

  /// Helper function to parse fields that can be either String (old format) or List (new format)
  static List<String> _parseStringOrList(dynamic value) {
    if (value == null) {
      return [];
    }
    // If it's already a List, convert to List<String>
    if (value is List) {
      return List<String>.from(value);
    }
    // If it's a String (old format), wrap it in a list
    if (value is String) {
      return value.isEmpty ? [] : [value];
    }
    return [];
  }
}

class QuestionValues {
  final String question;
  final String? value;
  final List<String>? options;

  QuestionValues({required this.question, this.value, this.options});
}
