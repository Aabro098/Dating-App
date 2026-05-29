import 'package:cloud_firestore/cloud_firestore.dart';

class SupportMessageModel {
  String roomId;
  String uid;
  String text;
  DateTime date;
  late String docId;
  bool seen;
  bool isAutoReply;
  bool? isResolved;
  String? categoryId;
  String? questionId;
  String messageType; // 'user', 'auto', 'resolution', 'title'
  List<String>? imageUrls;

  SupportMessageModel({
    required this.roomId,
    required this.uid,
    required this.text,
    required this.date,
    required this.seen,
    this.isAutoReply = false,
    this.isResolved,
    this.categoryId,
    this.questionId,
    this.messageType = 'user',
    this.imageUrls,
  });

  SupportMessageModel.fromJson(Map<String, dynamic> json)
    : roomId = json['roomId'] ?? '',
      uid = json['uid'] ?? '',
      text = json['text'] ?? '',
      seen = json['seen'] is bool
          ? json['seen']
          : (json['seen']?.toString().toLowerCase() == 'true'),
      isAutoReply = json['isAutoReply'] is bool
          ? json['isAutoReply']
          : (json['isAutoReply']?.toString().toLowerCase() == 'true'),
      isResolved = json['isResolved'] is bool ? json['isResolved'] : null,
      categoryId = json['categoryId'],
      questionId = json['questionId'],
      messageType = json['messageType'] ?? 'user',
      date = json['date'] is Timestamp
          ? (json['date'] as Timestamp).toDate()
          : DateTime.now(),
      imageUrls = json['imageUrls'] != null
          ? List<String>.from(json['imageUrls'])
          : null;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['roomId'] = roomId;
    data['uid'] = uid;
    data['text'] = text;
    data['date'] = date;
    data['seen'] = seen;
    data['isAutoReply'] = isAutoReply;
    data['messageType'] = messageType;
    if (isResolved != null) data['isResolved'] = isResolved;
    if (categoryId != null) data['categoryId'] = categoryId;
    if (questionId != null) data['questionId'] = questionId;
    if (imageUrls != null) data['imageUrls'] = imageUrls;
    return data;
  }
}

// class SupportQuestion {
//   final String id;
//   final String question;
//   final String answer;
//   final bool requiresInput;

//   SupportQuestion({
//     required this.id,
//     required this.question,
//     required this.answer,
//     this.requiresInput = false,
//   });
// }

// class SupportCategory {
//   final String id;
//   final String title;
//   final String icon;
//   final List<SupportQuestion> questions;

//   SupportCategory({
//     required this.id,
//     required this.title,
//     required this.icon,
//     required this.questions,
//   });
// }

// class SupportData {
//   static List<SupportCategory> getCategories() {
//     return [
//       // 1. Payment / Purchase issue
//       SupportCategory(
//         id: 'payment',
//         title: 'Payment / Purchase Issue',
//         icon: '💳',
//         questions: [
//           SupportQuestion(
//             id: 'payment_1',
//             question: 'Money debited but coins/subscription not received',
//             answer:
//                 'It looks like your payment was deducted but the coins/subscription hasn\'t arrived yet. Since purchases are made through Google Play, please share the Google Play Order ID (example: GPA.1234-5678-9123-45678) from the receipt email you received from Google. Once we have the Order ID, we will verify it directly with Google and credit your purchase.\n\nIf you haven\'t received the receipt from Google, please check the subscription status in the Google Play Store account. If the status shows payment failure, then your money will be automatically refunded back to your bank account by Google.',
//             requiresInput: true,
//           ),
//           SupportQuestion(
//             id: 'payment_2',
//             question: 'Payment stuck / Transaction pending',
//             answer:
//                 'Your purchase might still be pending in Google Play. Pending orders usually get resolved automatically by Google within a few minutes to a few hours. Please wait and check again shortly.',
//           ),
//           SupportQuestion(
//             id: 'payment_3',
//             question: 'Payment method not working (UPI/Card/Wallet)',
//             answer:
//                 'Payments are processed by Google Play, so failures usually happen because:\n\n• Insufficient balance\n• UPI/Card/Wallet downtime\n• Google Play rejecting the payment\n\nPlease try again after a minute or switch to a different payment method.',
//           ),
//           SupportQuestion(
//             id: 'payment_4',
//             question: 'Other payment issue',
//             answer:
//                 'Please describe your payment issue in detail below, and our support team will assist you as soon as possible.',
//             requiresInput: true,
//           ),
//         ],
//       ),

//       // 2. Unauthorized coin debit / Unexpected charges
//       SupportCategory(
//         id: 'unauthorized_charges',
//         title: 'Unauthorized Coin Debit / Unexpected Charges',
//         icon: '⚠️',
//         questions: [
//           SupportQuestion(
//             id: 'charges_1',
//             question: 'Coins deducted without using any feature',
//             answer:
//                 'We understand your concern. Coins may be deducted when certain features are used such as sending messages, using boosts, or super likes. Please check your recent activity to confirm.\n\nIf you believe coins were deducted incorrectly, please describe the situation below and our team will investigate.',
//             requiresInput: true,
//           ),
//           SupportQuestion(
//             id: 'charges_2',
//             question: 'Sudden big drop in coin balance',
//             answer:
//                 'A large drop in coin balance can happen if multiple features were used in a short period. Please review your recent activity.\n\nIf you believe this is an error, please share details below and our team will look into it immediately.',
//             requiresInput: true,
//           ),
//         ],
//       ),

//       // 3. Blocking / Report a user
//       SupportCategory(
//         id: 'blocking_report',
//         title: 'Blocking / Report a User',
//         icon: '🚫',
//         questions: [
//           SupportQuestion(
//             id: 'block_1',
//             question: 'Blocked user can still message me',
//             answer:
//                 'If a blocked user is still able to message you, this may be a sync delay. Please try restarting the app. If the issue persists, please share the details below and our team will resolve it.',
//             requiresInput: true,
//           ),
//           SupportQuestion(
//             id: 'block_2',
//             question: 'Unable to block a user',
//             answer:
//                 'To block a user, go to their profile or open the chat, tap the menu icon (three dots), and select "Block". If the option is not available or not working, please describe the issue below.',
//             requiresInput: true,
//           ),
//           SupportQuestion(
//             id: 'block_3',
//             question: 'Want to report an abusive user',
//             answer:
//                 'To report an abusive user, go to their profile, tap the menu icon (three dots), and select "Report". Choose the appropriate reason and submit. Our safety team reviews all reports and takes action promptly.\n\nIf you need immediate assistance, please share the details below.',
//             requiresInput: true,
//           ),
//           SupportQuestion(
//             id: 'block_4',
//             question: 'Fake profile / Spam account',
//             answer:
//                 'If you\'ve encountered a fake or spam profile, please report it using the Report option on their profile. Our team actively monitors and removes fake accounts.\n\nYou can also share additional details below to help us take faster action.',
//             requiresInput: true,
//           ),
//           SupportQuestion(
//             id: 'block_5',
//             question: 'Other blocking/reporting issue',
//             answer:
//                 'Please describe your issue in detail below, and our support team will assist you.',
//             requiresInput: true,
//           ),
//         ],
//       ),

//       // 4. Profile / Account settings
//       SupportCategory(
//         id: 'profile_account',
//         title: 'Profile / Account Settings',
//         icon: '👤',
//         questions: [
//           SupportQuestion(
//             id: 'profile_1',
//             question: 'Unable to update profile photo',
//             answer:
//                 'Please make sure the photo meets our guidelines (clear face photo, no inappropriate content). Also check that you\'ve granted camera and storage permissions to the app.\n\nIf the issue persists, try clearing the app cache or reinstalling the app. You can also describe the issue below for further help.',
//             requiresInput: true,
//           ),
//           SupportQuestion(
//             id: 'profile_2',
//             question: 'Unable to edit/update profile fields in My Profile',
//             answer:
//                 'Some profile fields may have restrictions on how often they can be changed. Please make sure you are on the latest version of the app.\n\nIf you\'re still facing issues, please describe the problem below and our team will assist you.',
//             requiresInput: true,
//           ),
//           SupportQuestion(
//             id: 'profile_3',
//             question: 'Unable to see chat/message options for some profiles',
//             answer:
//                 'Chat options will be hidden if the user has restricted access as per their setting option (Who can Message me) to only Matched/Liked users. You can try liking the profile first to enable messaging once matched.',
//           ),
//           SupportQuestion(
//             id: 'profile_4',
//             question: 'Login / OTP issues',
//             answer:
//                 'If you\'re having trouble logging in or not receiving OTP, please try the following:\n\n• Check your internet connection\n• Make sure the phone number is correct with country code\n• Wait a minute and request OTP again\n• Check your SMS spam/blocked folder\n\nIf the issue persists, please share your registered phone number or email below.',
//             requiresInput: true,
//           ),
//           SupportQuestion(
//             id: 'profile_5',
//             question: 'Need to delete my account',
//             answer:
//                 'To delete your account, go to Settings > Account > Delete Account. Please note that this action is permanent — all your data, matches, and conversations will be permanently removed and cannot be recovered.\n\nIf you\'re facing any issue with deletion, please describe it below.',
//             requiresInput: true,
//           ),
//           SupportQuestion(
//             id: 'profile_6',
//             question: 'Other account issue',
//             answer:
//                 'Please describe your account issue in detail below, and our support team will assist you.',
//             requiresInput: true,
//           ),
//         ],
//       ),

//       // 5. App bug / Crash
//       SupportCategory(
//         id: 'app_bug',
//         title: 'App Bug / Crash',
//         icon: '🐛',
//         questions: [
//           SupportQuestion(
//             id: 'bug_1',
//             question: 'App is crashing or freezing',
//             answer:
//                 'We\'re sorry for the inconvenience. Please try the following:\n\n1. Close and reopen the app\n2. Check for app updates in the Play Store\n3. Clear the app cache (Settings > Apps > Viora > Clear Cache)\n4. Restart your device\n\nIf the issue continues, please describe what you were doing when the crash happened.',
//             requiresInput: true,
//           ),
//           SupportQuestion(
//             id: 'bug_2',
//             question: 'A feature is not working properly',
//             answer:
//                 'Please make sure you are using the latest version of the app. If the issue persists, please describe which feature is not working and what exactly happens when you try to use it.',
//             requiresInput: true,
//           ),
//           SupportQuestion(
//             id: 'bug_3',
//             question: 'App is very slow or lagging',
//             answer:
//                 'App performance can be affected by:\n\n• Low device storage\n• Poor internet connection\n• Outdated app version\n• Too many background apps\n\nPlease try clearing cache and updating the app. If it\'s still slow, share your device model below so we can investigate.',
//             requiresInput: true,
//           ),
//           SupportQuestion(
//             id: 'bug_4',
//             question: 'Other bug or technical issue',
//             answer:
//                 'Please describe the bug or issue in detail below. Include steps to reproduce the problem if possible, and our team will investigate.',
//             requiresInput: true,
//           ),
//         ],
//       ),

//       // 6. Others
//       SupportCategory(
//         id: 'others',
//         title: 'Others',
//         icon: '💬',
//         questions: [
//           SupportQuestion(
//             id: 'others_1',
//             question: 'I have a suggestion or feedback',
//             answer:
//                 'We love hearing from our users! Please share your suggestion or feedback below and our team will review it.',
//             requiresInput: true,
//           ),
//           SupportQuestion(
//             id: 'others_2',
//             question: 'My issue is not listed above',
//             answer:
//                 'Please describe your issue in detail below, and our support team will get back to you as soon as possible.',
//             requiresInput: true,
//           ),
//         ],
//       ),
//     ];
//   }
// }

class SupportFaqModel {
  final List<SupportCategory> categories;
  final DateTime? updatedAt;

  const SupportFaqModel({required this.categories, this.updatedAt});

  factory SupportFaqModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    return SupportFaqModel.fromMap(data ?? {});
  }

  factory SupportFaqModel.fromMap(Map<String, dynamic> map) {
    return SupportFaqModel(
      categories:
          (map['categories'] as List?)
              ?.whereType<Map>()
              .map((e) => SupportCategory.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      updatedAt: _parseDateTime(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'categories': categories.map((e) => e.toMap()).toList(),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }
}

class SupportCategory {
  final String id;
  final String title;
  final String icon;
  final List<SupportQuestion> questions;

  const SupportCategory({
    required this.id,
    required this.title,
    required this.icon,
    required this.questions,
  });

  factory SupportCategory.fromMap(Map<String, dynamic> map) {
    return SupportCategory(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      icon: map['icon'] as String? ?? '',
      questions:
          (map['questions'] as List?)
              ?.whereType<Map>()
              .map((e) => SupportQuestion.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'icon': icon,
      'questions': questions.map((e) => e.toMap()).toList(),
    };
  }
}

class SupportQuestion {
  final String id;
  final String question;
  final String answer;
  final bool requiresInput;

  const SupportQuestion({
    required this.id,
    required this.question,
    required this.answer,
    required this.requiresInput,
  });

  factory SupportQuestion.fromMap(Map<String, dynamic> map) {
    return SupportQuestion(
      id: map['id'] as String? ?? '',
      question: map['question'] as String? ?? '',
      answer: map['answer'] as String? ?? '',
      requiresInput: map['requiresInput'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'question': question,
      'answer': answer,
      'requiresInput': requiresInput,
    };
  }
}
