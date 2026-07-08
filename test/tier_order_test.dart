// Verify 5-tier ACSM/NSCA post-selection ordering from generatePlan.
// Run: dart run test/tier_order_test.dart

import 'package:onefit/algorithms/greedy_algorithm.dart';
import 'package:onefit/models/exercise.dart';
import 'package:onefit/models/user_profile.dart';

Exercise _ex(String id, String name, List<String> eq, List<String> pri,
    List<String> sec, List<String> goals, String diff) =>
    Exercise(
      id: id, name: name, category: 'strength',
      primaryMuscles: pri, secondaryMuscles: sec,
      equipment: eq, difficulty: diff,
      goals: goals, locations: ['gym'], instructions: '',
    );

void main() {
  // All exercises share 'pectorals' as primary so they all enter the same
  // primaryPool for a Full Body day, forcing the sort to be the only orderer.
  final pool = [
    _ex('lat_raise', 'Lateral Raise',    ['Dumbbells'], ['pectorals'], [],
        ['general'], 'beginner'),
    _ex('bench',     'Bench Press',      ['Barbell'],   ['pectorals'],
        ['triceps', 'delts'], ['muscle_gain'], 'intermediate'),
    _ex('pushdown',  'Triceps Pushdown', ['Cable'],     ['pectorals'], [],
        ['general'], 'beginner'),
    _ex('row',       'Barbell Row',      ['Barbell'],   ['pectorals'],
        ['upper back', 'biceps'], ['muscle_gain'], 'intermediate'),
    _ex('facepull',  'Face Pull',        ['Cable'],     ['pectorals'],
        ['delts'], ['general'], 'beginner'),
  ];

  final profile = UserProfile(
    uid: 'test', name: 'Test', gender: 'Male', age: 25,
    weight: 80.0, height: 178.0,
    fitnessGoal: 'Muscle Gain', experienceLevel: 'Advanced',
    workoutLocation: 'Gym', equipment: [],
    dietaryRestrictions: [],
    workoutDaysPerWeek: 3, sessionMinutes: 90,
    workoutSplit: 'Full Body Training',
  );

  final plan = GreedyAlgorithm().generatePlan(
    allExercises: pool, profile: profile,
  );

  final day1 = plan.firstWhere((d) => !d.isRest);

  print('');
  print('=== 5-TIER SORT VERIFICATION ===');
  print('Sorted order from generatePlan (Day 1):');
  for (int i = 0; i < day1.exercises.length; i++) {
    print('  ${i + 1}. ${day1.exercises[i].exercise.name}');
  }
  print('');
  print('Expected: Bench Press → Barbell Row → Lateral Raise → Triceps Pushdown → Face Pull');
  print('          (tier 2)        (tier 2)      (tier 4)       (tier 4)           (tier 5)');

  final names = day1.exercises.map((e) => e.exercise.name).toList();
  final benchIdx   = names.indexOf('Bench Press');
  final rowIdx     = names.indexOf('Barbell Row');
  final raiseIdx   = names.indexOf('Lateral Raise');
  final pushIdx    = names.indexOf('Triceps Pushdown');
  final faceIdx    = names.indexOf('Face Pull');

  final ok = benchIdx < raiseIdx && benchIdx < pushIdx && benchIdx < faceIdx &&
             rowIdx   < raiseIdx && rowIdx   < pushIdx && rowIdx   < faceIdx &&
             raiseIdx < faceIdx  && pushIdx  < faceIdx;

  print('');
  print(ok ? 'PASS — compounds before isolations before accessories' : 'FAIL — order incorrect');
}
