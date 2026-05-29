import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRoom {
  late String roomId;
  List<String> users;
  String lastMessage;
  DateTime lastMessageDate;
  bool isBlocked;
  String blockedBy;
  List<String>? categoryId;
  String? status;
  ChatRoom({
    required this.users,
    required this.lastMessage,
    required this.lastMessageDate,
    required this.blockedBy,
    required this.isBlocked,
    this.categoryId,
    this.status,
  });

  ChatRoom.fromJson(Map<String, dynamic> json)
    : roomId = json['roomId'] ?? '',
      lastMessage = json['lastMessage'] ?? '',
      blockedBy = json['blockedBy'] ?? '',
      isBlocked = json['isBlocked'] is bool
          ? json['isBlocked']
          : (json['isBlocked']?.toString().toLowerCase() == 'true'),
      users = (json['users'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      lastMessageDate = (json['lastMessageDate'] as Timestamp).toDate(),
      categoryId = json['categoryId'] != null
          ? (json['categoryId'] as List<dynamic>)
                .map((e) => e.toString())
                .toList()
          : null,
      status = json['status'];

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['roomId'] = roomId;
    data['users'] = users;
    data['lastMessage'] = lastMessage;
    data['lastMessageDate'] = lastMessageDate;
    data['categoryId'] = categoryId;
    data['status'] = status;
    return data;
  }
}
