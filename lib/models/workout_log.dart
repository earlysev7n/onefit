import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutLogExercise {
  final String name;
  final int sets;
  final String reps;
  final int restSeconds;
  final List<String> primaryMuscles;

  const WorkoutLogExercise({
    required this.name,
    required this.sets,
    required this.reps,
    required this.restSeconds,
    required this.primaryMuscles,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'sets': sets,
    'reps': reps,
    'restSeconds': restSeconds,
    'primaryMuscles': primaryMuscles,
  };

  factory WorkoutLogExercise.fromMap(Map<String, dynamic> m) =>
      WorkoutLogExercise(
        name: m['name'] ?? '',
        sets: (m['sets'] as num?)?.toInt() ?? 0,
        reps: m['reps'] ?? '',
        restSeconds: (m['restSeconds'] as num?)?.toInt() ?? 60,
        primaryMuscles: List<String>.from(m['primaryMuscles'] ?? []),
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
    );
  }
}
