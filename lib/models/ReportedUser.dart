class ReportedUser {
  DateTime date;
  String reportedUid, reportedByUid;

  ReportedUser({
    required this.reportedByUid,
    required this.reportedUid,
    required this.date,
  });

  ReportedUser.fromJson(Map<String, dynamic> json) :
    reportedByUid = json['reportedByUid'],
    reportedUid = json['reportedUid'],
    date = json['date'].toDate();


  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['reportedByUid'] = this.reportedByUid;
    data['reportedUid'] = this.reportedUid;
    data['date'] = this.date;
    return data;
  }
}
