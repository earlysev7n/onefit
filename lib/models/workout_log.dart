import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutLogExercise {
  final String name;
  final int sets;
  final String reps;
  final int restSeconds;
  final List<String> primaryMuscles;
  // Actual top-set performance the user entered during the session (null when
  // not logged). `sets`/`reps` above are what was *prescribed*; these are what
  // was *performed* — the data progressive overload is tracked against.
  final double? weightKg;
  final int? repsDone;

  const WorkoutLogExercise({
    required this.name,
    required this.sets,
    required this.reps,
    required this.restSeconds,
    required this.primaryMuscles,
    this.weightKg,
    this.repsDone,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'sets': sets,
    'reps': reps,
    'restSeconds': restSeconds,
    'primaryMuscles': primaryMuscles,
    if (weightKg != null) 'weightKg': weightKg,
    if (repsDone != null) 'repsDone': repsDone,
  };

  factory WorkoutLogExercise.fromMap(Map<String, dynamic> m) =>
      WorkoutLogExercise(
        name: m['name'] ?? '',
        sets: (m['sets'] as num?)?.toInt() ?? 0,
        reps: m['reps'] ?? '',
        restSeconds: (m['restSeconds'] as num?)?.toInt() ?? 60,
        primaryMuscles: List<String>.from(m['primaryMuscles'] ?? []),
        weightKg: (m['weightKg'] as num?)?.toDouble(),
        repsDone: (m['repsDone'] as num?)?.toInt(),
      );
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
