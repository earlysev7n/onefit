// WorkoutLogExercise per-set serialization + backward-compatible reads.
//
// Pure Dart — runs with `flutter test test/workout_log_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/models/workout_log.dart';

void main() {
  group('WorkoutLogExercise round-trip', () {
    test('loggedSets + skipped survive toMap → fromMap', () {
      final ex = WorkoutLogExercise(
        name: 'Bench Press',
        sets: 3,
        reps: '8-12',
        restSeconds: 90,
        primaryMuscles: const ['chest'],
        loggedSets: const [
          SetEntry(weightKg: 40, reps: 12),
          SetEntry(weightKg: 45, reps: 10),
          SetEntry(weightKg: 45, reps: 8),
        ],
      );
      final back = WorkoutLogExercise.fromMap(ex.toMap());
      expect(back.loggedSets.length, 3);
      expect(back.loggedSets[1].weightKg, 45);
      expect(back.loggedSets[1].reps, 10);
      // Legacy top-set fields derive from the heaviest logged set.
      expect(back.weightKg, 45);
      expect(back.topSet?.weightKg, 45);
    });

    test('skipped flag round-trips', () {
      final ex = WorkoutLogExercise(
        name: 'Squat',
        sets: 3,
        reps: '8-12',
        restSeconds: 120,
        primaryMuscles: const ['quads'],
        skipped: true,
      );
      expect(WorkoutLogExercise.fromMap(ex.toMap()).skipped, isTrue);
    });

    test('legacy log (only top set, no loggedSets) reads into a single set', () {
      // A pre-feature Firestore doc.
      final legacy = {
        'name': 'Deadlift',
        'sets': 3,
        'reps': '5',
        'restSeconds': 120,
        'primaryMuscles': ['back'],
        'weightKg': 100.0,
        'repsDone': 5,
      };
      final ex = WorkoutLogExercise.fromMap(legacy);
      expect(ex.loggedSets.length, 1);
      expect(ex.loggedSets.single.weightKg, 100);
      expect(ex.loggedSets.single.reps, 5);
      expect(ex.skipped, isFalse);
    });

    test('bodyweight set (no weight) keeps weightKg null', () {
      final ex = WorkoutLogExercise(
        name: 'Push-up',
        sets: 3,
        reps: '10-20',
        restSeconds: 60,
        primaryMuscles: const ['chest'],
        loggedSets: const [SetEntry(reps: 18), SetEntry(reps: 16)],
      );
      final back = WorkoutLogExercise.fromMap(ex.toMap());
      expect(back.loggedSets.first.weightKg, isNull);
      expect(back.loggedSets.first.reps, 18);
      expect(back.weightKg, isNull); // no weight → no legacy top-set weight
    });
  });
}
