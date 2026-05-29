class NotificationData {
  String name;
  String imgUrl;
  String type;
  bool seen;

  DateTime date;
  String uid;

  NotificationData({
    required this.name,
    required this.uid,
    required this.date,
    required this.imgUrl,
    required this.type,
    this.seen = false,
  });

  NotificationData.fromJson(Map<String, dynamic> json)
    : name = json['name'] ?? '',
      uid = json['uid'] ?? '',
      imgUrl = json['imgUrl'] ?? '',
      type = json['type'] ?? '',
      seen = json['seen'] == true,
      date = json['date'] != null
          ? (json['date'] is DateTime ? json['date'] : json['date'].toDate())
          : DateTime.now();

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['name'] = this.name;
    data['uid'] = this.uid;
    data['imgUrl'] = this.imgUrl;
    data['type'] = this.type;
    data['seen'] = this.seen;
    data['date'] =
        this.date; // Firestore will auto-convert DateTime to Timestamp
    return data;
  }
}
