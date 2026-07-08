// Verify PPL consecutive scheduling: rest days come after the full P/P/L
// cycle, not interspersed within it.
// Run: dart run test/ppl_schedule_test.dart

import 'package:onefit/algorithms/greedy_algorithm.dart';
import 'package:onefit/models/exercise.dart';
import 'package:onefit/models/user_profile.dart';

Exercise _ex(String id, String name, List<String> pri) => Exercise(
      id: id, name: name, category: 'strength',
      primaryMuscles: pri, secondaryMuscles: [],
      equipment: ['Barbell'], difficulty: 'intermediate',
      goals: ['muscle_gain'], locations: ['gym'], instructions: '',
    );

UserProfile _profile(int days) => UserProfile(
      uid: 'test', name: 'Test', gender: 'Male', age: 25,
      weight: 80.0, height: 178.0,
      fitnessGoal: 'Muscle Gain', experienceLevel: 'Intermediate',
      workoutLocation: 'Gym', equipment: [],
      dietaryRestrictions: [],
      workoutDaysPerWeek: days,
      sessionMinutes: 45,
      workoutSplit: 'Push / Pull / Legs (PPL)',
    );

void main() {
  final pool = [
    _ex('bench', 'Bench Press', ['pectorals']),
    _ex('row',   'Barbell Row', ['lats']),
    _ex('squat', 'Back Squat',  ['quads']),
  ];

  for (final days in [3, 4, 5, 6]) {
    final plan = GreedyAlgorithm().generatePlan(
      allExercises: pool, profile: _profile(days),
    );
    print('');
    print('=== PPL $days-day schedule ===');
    for (int i = 0; i < plan.length; i++) {
      final d = plan[i];
      print('  Day ${i + 1}: ${d.isRest ? "REST" : d.focus}');
    }

    // Assert: no training day appears after a rest day that interrupts the cycle.
    // That is: all rest days must appear AFTER all training days.
    final indices = plan.asMap().entries.toList();
    final lastTrain = indices.lastWhere((e) => !e.value.isRest).key;
    final firstRest  = indices.firstWhere((e) =>  e.value.isRest).key;
    final ok = firstRest > lastTrain;
    print('  → ${ok ? "PASS" : "FAIL"} (first rest at day ${firstRest + 1}, last train at day ${lastTrain + 1})');
  }
}
