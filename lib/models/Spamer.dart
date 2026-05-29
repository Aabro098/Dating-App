class Spamer {
  String spamerId;
  DateTime lastSpamDate;
  String lastSpamMessage;

  Spamer({required this.spamerId,required this.lastSpamDate,required this.lastSpamMessage});

  Spamer.fromJson(Map<String, dynamic> json) :
    spamerId = json['spamerId'],
    lastSpamDate = json['lastSpamDate'].toDate(),
    lastSpamMessage = json['lastSpamMessage'];


  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['spamerId'] = this.spamerId;
    data['lastSpamDate'] = this.lastSpamDate;
    data['lastSpamMessage'] = this.lastSpamMessage;
    return data;
  }
}
