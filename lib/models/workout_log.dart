import 'package:cloud_firestore/cloud_firestore.dart';

/// One performed set the user logged during a session. `weightKg` is null for
/// bodyweight moves; `seconds` is set (and reps null) for timed moves.
class SetEntry {
  final double? weightKg;
  final int? reps;
  final int? seconds;

  const SetEntry({this.weightKg, this.reps, this.seconds});

  Map<String, dynamic> toMap() => {
    if (weightKg != null) 'weightKg': weightKg,
    if (reps != null) 'reps': reps,
    if (seconds != null) 'seconds': seconds,
  };

  factory SetEntry.fromMap(Map<String, dynamic> m) => SetEntry(
    weightKg: (m['weightKg'] as num?)?.toDouble(),
    reps: (m['reps'] as num?)?.toInt(),
    seconds: (m['seconds'] as num?)?.toInt(),
  );
}

class WorkoutLogExercise {
  final String name;
  final int sets;
  final String reps;
  final int restSeconds;
  final List<String> primaryMuscles;
  // Legacy top-set performance (heaviest logged set), kept so existing readers
  // — PR detection, progress charts — keep working. `sets`/`reps` above are
  // *prescribed*; these are *performed*.
  final double? weightKg;
  final int? repsDone;
  // Every set the user logged this session (the source of truth for
  // progression). Empty when the exercise wasn't logged set-by-set.
  final List<SetEntry> loggedSets;
  // True when the user explicitly skipped this exercise — it does not count as
  // completed volume and never advances its own progression.
  final bool skipped;

  const WorkoutLogExercise({
    required this.name,
    required this.sets,
    required this.reps,
    required this.restSeconds,
    required this.primaryMuscles,
    this.weightKg,
    this.repsDone,
    this.loggedSets = const [],
    this.skipped = false,
  });

  /// Heaviest logged set (falls back to the first logged set for bodyweight,
  /// then to the legacy explicit fields). Drives the legacy top-set write.
  SetEntry? get topSet {
    if (loggedSets.isEmpty) {
      return (weightKg != null || repsDone != null)
          ? SetEntry(weightKg: weightKg, reps: repsDone)
          : null;
    }
    final weighted =
        loggedSets.where((s) => (s.weightKg ?? 0) > 0).toList()
          ..sort((a, b) => (b.weightKg ?? 0).compareTo(a.weightKg ?? 0));
    return weighted.isNotEmpty ? weighted.first : loggedSets.first;
  }

  Map<String, dynamic> toMap() {
    final top = topSet;
    return {
      'name': name,
      'sets': sets,
      'reps': reps,
      'restSeconds': restSeconds,
      'primaryMuscles': primaryMuscles,
      if (top?.weightKg != null) 'weightKg': top!.weightKg,
      if (top?.reps != null) 'repsDone': top!.reps,
      if (loggedSets.isNotEmpty)
        'loggedSets': loggedSets.map((s) => s.toMap()).toList(),
      if (skipped) 'skipped': true,
    };
  }

  factory WorkoutLogExercise.fromMap(Map<String, dynamic> m) {
    final rawSets = m['loggedSets'] as List?;
    final logged = rawSets != null
        ? rawSets.cast<Map<String, dynamic>>().map(SetEntry.fromMap).toList()
        : <SetEntry>[];
    final weightKg = (m['weightKg'] as num?)?.toDouble();
    final repsDone = (m['repsDone'] as num?)?.toInt();
    // Legacy logs carry only the top set — synthesize a single-entry list so
    // per-set consumers see a uniform shape.
    final effectiveSets = logged.isNotEmpty
        ? logged
        : (weightKg != null || repsDone != null)
        ? [SetEntry(weightKg: weightKg, reps: repsDone)]
        : <SetEntry>[];
    return WorkoutLogExercise(
      name: m['name'] ?? '',
      sets: (m['sets'] as num?)?.toInt() ?? 0,
      reps: m['reps'] ?? '',
      restSeconds: (m['restSeconds'] as num?)?.toInt() ?? 60,
      primaryMuscles: List<String>.from(m['primaryMuscles'] ?? []),
      weightKg: weightKg,
      repsDone: repsDone,
      loggedSets: effectiveSets,
      skipped: m['skipped'] == true,
    );
  }
}

class WorkoutLog {
  final String id;
  final String userId;
  final DateTime date;
  final String weekId;
  final String dayName;
  final String focus;
  final int durationMinutes;
  final DateTime completedAt;
  final List<WorkoutLogExercise> exercises;
  // Post-workout perceived difficulty (1 = too easy … 5 = too hard). Null when
  // the user skipped rating. Feeds AdaptationEngine autoregulation.
  final int? rating;

  const WorkoutLog({
    required this.id,
    required this.userId,
    required this.date,
    required this.weekId,
    required this.dayName,
    required this.focus,
    required this.durationMinutes,
    required this.completedAt,
    required this.exercises,
    this.rating,
  });

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'date': Timestamp.fromDate(date),
    'weekId': weekId,
    'dayName': dayName,
    'focus': focus,
    'durationMinutes': durationMinutes,
    'completedAt': Timestamp.fromDate(completedAt),
    'exercises': exercises.map((e) => e.toMap()).toList(),
    if (rating != null) 'rating': rating,
  };

  factory WorkoutLog.fromMap(Map<String, dynamic> m, String id) {
    DateTime _ts(dynamic v) => v is Timestamp ? v.toDate() : DateTime.now();
    return WorkoutLog(
      id: id,
      userId: m['userId'] ?? '',
      date: _ts(m['date']),
      weekId: m['weekId'] ?? '',
      dayName: m['dayName'] ?? '',
      focus: m['focus'] ?? '',
      durationMinutes: (m['durationMinutes'] as num?)?.toInt() ?? 0,
      completedAt: _ts(m['completedAt']),
      exercises: (m['exercises'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(WorkoutLogExercise.fromMap)
          .toList(),
      rating: (m['rating'] as num?)?.toInt(),
    );
  }
}
