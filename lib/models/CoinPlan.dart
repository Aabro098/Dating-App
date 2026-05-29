class CoinPlan {
  late String planId;
  int coins;
  int price;
  bool visibility;
  DateTime date;

  CoinPlan({required this.coins,required this.price,required this.date,required this.visibility});

  CoinPlan.fromJson(Map<String, dynamic> json) :
    planId = json['planId'] ?? '',
    coins = json['coins'] ?? 0,
    price = json['price'] ?? 0,
    visibility = json['visibility'] is bool ? json['visibility'] : (json['visibility']?.toString().toLowerCase() == 'true'),
    date = DateTime.parse(json['date'] ?? DateTime.now().toIso8601String());


  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['planId'] = this.planId;
    data['coins'] = this.coins;
    data['price'] = this.price;
    data['visibility'] = this.visibility;
    data['date'] = this.date;
    return data;
  }
}
