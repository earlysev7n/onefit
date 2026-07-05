import 'package:cloud_firestore/cloud_firestore.dart';

class WeightLog {
  final String id;
  final String userId;
  final DateTime date;
  final double weight; // always kg internally
  final DateTime loggedAt;

  const WeightLog({
    required this.id,
    required this.userId,
    required this.date,
    required this.weight,
    required this.loggedAt,
  });

  factory WeightLog.fromMap(Map<String, dynamic> m, String id) {
    DateTime ts(dynamic v) => v is Timestamp ? v.toDate() : DateTime.now();
    return WeightLog(
      id: id,
      userId: m['userId'] ?? '',
      date: ts(m['date']),
      weight: (m['weight'] as num?)?.toDouble() ?? 0.0,
      loggedAt: ts(m['loggedAt']),
    );
  }
}
