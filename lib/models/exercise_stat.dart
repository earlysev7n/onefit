import 'package:cloud_firestore/cloud_firestore.dart';

import 'workout_log.dart';

/// Denormalized per-exercise performance summary, stored at
/// `users/{uid}/exercise_stats/{exerciseId}`. Powers the "Last: 60 kg × 8"
/// target and the PR badge shown on exercise cards without having to scan the
/// `exercises` array inside every workout log (which Firestore can't query).
///
/// Weight is always stored in kg internally (same convention as UserProfile);
/// display conversion to lbs happens in the UI.
class ExerciseStat {
  final String exerciseId;
  final String name;
  final double lastWeightKg;
  final int? lastReps;
  final DateTime lastDate;
  final double bestWeightKg;
  final DateTime bestDate;
  // Full set list from the last session (empty for legacy stats) so the next
  // session can pre-fill every set, not just the top set.
  final List<SetEntry> lastSets;

  const ExerciseStat({
    required this.exerciseId,
    required this.name,
    required this.lastWeightKg,
    required this.lastReps,
    required this.lastDate,
    required this.bestWeightKg,
    required this.bestDate,
    this.lastSets = const [],
  });

  Map<String, dynamic> toMap() => {
    'exerciseId': exerciseId,
    'name': name,
    'lastWeightKg': lastWeightKg,
    'lastReps': lastReps,
    'lastDate': Timestamp.fromDate(lastDate),
    'bestWeightKg': bestWeightKg,
    'bestDate': Timestamp.fromDate(bestDate),
    'lastSets': lastSets.map((s) => s.toMap()).toList(),
  };

  factory ExerciseStat.fromMap(Map<String, dynamic> m) {
    DateTime ts(dynamic v) => v is Timestamp ? v.toDate() : DateTime.now();
    return ExerciseStat(
      exerciseId: m['exerciseId'] ?? '',
      name: m['name'] ?? '',
      lastWeightKg: (m['lastWeightKg'] as num?)?.toDouble() ?? 0,
      lastReps: (m['lastReps'] as num?)?.toInt(),
      lastDate: ts(m['lastDate']),
      bestWeightKg: (m['bestWeightKg'] as num?)?.toDouble() ?? 0,
      bestDate: ts(m['bestDate']),
      lastSets:
          (m['lastSets'] as List?)
              ?.cast<Map<String, dynamic>>()
              .map(SetEntry.fromMap)
              .toList() ??
          const [],
    );
  }
}
