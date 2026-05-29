import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  String roomId;
  String uid;
  String receiver;
  String text;
  List<String>? imagePath;
  DateTime date;
  late String docId;
  bool seen;
  MessageModel({
    required this.roomId,
    required this.uid,
    required this.text,
    this.imagePath,
    required this.date,
    required this.seen,
    required this.receiver,
  });

  MessageModel.fromJson(Map<String, dynamic> json)
    : roomId = json['roomId'] ?? '',
      uid = json['uid'] ?? '',
      receiver = json['receiver'] ?? '',
      docId = json['docId'] ?? '',
      text = json['text'] ?? '',
      imagePath = _parseImagePath(json['imagePath']),
      seen = json['seen'] is bool
          ? json['seen']
          : (json['seen']?.toString().toLowerCase() == 'true'),
      date = (json['date'] as Timestamp).toDate();

  static List<String>? _parseImagePath(dynamic imagePath) {
    if (imagePath == null) return null;
    if (imagePath is List) {
      return List<String>.from(imagePath);
    }
    if (imagePath is String) {
      return [imagePath];
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['roomId'] = roomId;
    data['uid'] = uid;
    data['text'] = text;
    data['imagePath'] = imagePath;
    data['date'] = date;
    data['seen'] = seen;
    data['receiver'] = receiver;
    return data;
  }
}
