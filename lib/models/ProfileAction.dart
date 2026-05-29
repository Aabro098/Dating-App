class ProfileAction {
  String uid;
  DateTime date;
  bool seen;
  String?
  actionType; // 'View', 'Crush', 'Fav', or null for backward compatibility

  ProfileAction({
    required this.uid,
    required this.date,
    this.seen = false,
    this.actionType,
  });

  ProfileAction.fromJson(Map<String, dynamic> json)
    : uid = json['uid'],
      date = json['date'].toDate(),
      seen = json['seen'] == true,
      actionType = json['actionType'] as String?;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = Map<String, dynamic>();

    data['uid'] = uid;
    data['date'] = date;
    data['seen'] = seen;
    if (actionType != null) {
      data['actionType'] = actionType;
    }
    return data;
  }
}
