import 'dart:convert';

class PlanTransaction {
  String planId;
  int coins;
  int price;
  DateTime date;
  String transactionId;
  String uId;

  PlanTransaction({
    required this.planId,
    required this.coins,
    required this.price,
    required this.date,
    required this.uId,
    required this.transactionId,
  });

  PlanTransaction.fromJson(Map<String, dynamic> json)
    : planId = json['planId'],
      coins = json['coins'],
      transactionId = json['transactionId'],
      price = json['price'],
      uId = json['uId'],
      date = json['date'].toDate();

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['planId'] = this.planId;
    data['coins'] = this.coins;
    data['price'] = this.price;
    data['date'] = this.date;
    data['uId'] = this.uId;
    data['transactionId'] = this.transactionId;
    return data;
  }
}

class TransactionScreenModel {
  String productId;
  double price;
  DateTime date;
  String transactionId;
  String uId;
  String status;
  String eventType;

  TransactionScreenModel({
    required this.productId,
    required this.price,
    required this.date,
    required this.uId,
    required this.transactionId,
    required this.status,
    required this.eventType,
  });

  TransactionScreenModel.fromJson(Map<String, dynamic> json)
    : productId = json['productId'],
      transactionId = json['transactionId'],
      price = (json['priceInPurchasedCurrency'] as num).toDouble(),
      uId = json['appUserId'],
      date = json['serverReceivedAt'].toDate(),
      status = json['status'] ?? 'Not Known',
      eventType = json['eventType'] ?? 'Not Known';

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['productId'] = productId;
    data['priceInPurchasedCurrency'] = price;
    data['serverReceivedAt'] = date;
    data['appUserId'] = uId;
    data['transactionId'] = transactionId;
    data['status'] = status;
    data['eventType'] = eventType;
    return data;
  }
}
