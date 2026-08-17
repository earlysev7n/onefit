import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/conditioning_finisher.dart';
import 'package:onefit/algorithms/greedy_algorithm.dart';
import 'package:onefit/models/exercise.dart';
import 'package:onefit/models/user_profile.dart';

Exercise _ex({
  required String id,
  required String name,
  List<String> primaryMuscles = const ['pectorals'],
  String difficulty = 'beginner',
  List<String> goals = const ['muscle_gain', 'general'],
  List<String> equipment = const ['bodyweight'],
  String category = 'chest',
  List<String> locations = const ['home', 'gym'],
}) => Exercise(
  id: id,
  name: name,
  category: category,
  primaryMuscles: primaryMuscles,
  secondaryMuscles: const [],
  equipment: equipment,
  difficulty: difficulty,
  goals: goals,
  locations: locations,
  instructions: '',
);

UserProfile _profile({
  String goal = 'Weight Loss',
  String level = 'Beginner',
  String location = 'Home', // default Home → bodyweight conditioning path
  List<String> limitations = const [],
}) => UserProfile(
  uid: 'u1',
  name: 'Test',
  gender: 'Male',
  age: 30,
  weight: 80,
  height: 180,
  fitnessGoal: goal,
  experienceLevel: level,
  workoutLocation: location,
  equipment: const [],
  dietaryRestrictions: const ['Balanced'],
  workoutSplit: 'Full Body Training',
  sessionMinutes: 45,
  workoutDaysPerWeek: 3,
  physicalLimitations: limitations,
);

// A strength move (never a finisher — no cardio category / endurance tag).
final _bench = _ex(id: 'bench', name: 'Bench Press', primaryMuscles: ['pectorals']);
final _squat = _ex(id: 'squat', name: 'Bodyweight Squat', primaryMuscles: ['quads'],
    category: 'upper legs');

// Conditioning moves. `endurance` tag makes them finisher-eligible.
final _burpee = _ex(id: 'burpee', name: 'Burpee', primaryMuscles: ['quads'],
    goals: ['endurance', 'weight_loss'], category: 'cardio');
final _jumpsquat = _ex(id: 'jumpsquat', name: 'Jump Squat', primaryMuscles: ['quads'],
    goals: ['endurance'], category: 'upper legs');
// Knee-safe cardio (no jump/plyo/squat keyword, not a quad-plyo).
final _rope = _ex(id: 'rope', name: 'Battle Rope Wave', primaryMuscles: ['delts'],
    goals: ['endurance', 'weight_loss'], category: 'cardio');
// Gym-located treadmill (excluded for Home users by eligibility).
final _treadmill = _ex(id: 'treadmill', name: 'Treadmill Run',
    primaryMuscles: ['full body'], goals: ['endurance', 'weight_loss'],
    category: 'cardio', equipment: ['gym'], locations: ['gym']);

WorkoutExercise _we(Exercise e) =>
    WorkoutExercise(exercise: e, sets: 3, reps: '8-12', restSeconds: 60);

WorkoutDay _trainDay(String name, List<Exercise> ex, {String focus = 'Full Body'}) =>
    WorkoutDay(dayName: name, focus: focus, exercises: ex.map(_we).toList());

WorkoutDay _restDay(String name) =>
    WorkoutDay(dayName: name, focus: 'Rest Day', exercises: const [], isRest: true);

void main() {
  final catalog = [_bench, _squat, _burpee, _jumpsquat, _rope];

  group('ConditioningFinisher', () {
    test('Weight Loss: appends one conditioning finisher (last) to each training day', () {
      final plan = [
        _trainDay('Mon', [_bench, _squat]),
        _restDay('Tue'),
        _trainDay('Wed', [_bench, _squat]),
      ];
      final out = ConditioningFinisher.apply(plan, _profile(goal: 'Weight Loss'), catalog);

      // Rest day untouched.
      expect(out[1].isRest, isTrue);
      expect(out[1].exercises, isEmpty);

      for (final i in [0, 2]) {
        expect(out[i].exercises.length, 3, reason: 'day $i gained exactly one finisher');
        final last = out[i].exercises.last.exercise;
        expect(
          last.category.toLowerCase() == 'cardio' || last.goals.contains('endurance'),
          isTrue,
          reason: 'the appended last move is a conditioning exercise',
        );
        // Strength moves preserved, in order, ahead of the finisher.
        expect(out[i].exercises[0].exercise.id, 'bench');
        expect(out[i].exercises[1].exercise.id, 'squat');
      }
    });

    test('Endurance also gets a finisher', () {
      final plan = [_trainDay('Mon', [_bench])];
      final out = ConditioningFinisher.apply(plan, _profile(goal: 'Endurance'), catalog);
      expect(out[0].exercises.length, 2);
    });

    test('Muscle Gain and General are unchanged (no finisher)', () {
      final plan = [_trainDay('Mon', [_bench, _squat])];
      for (final goal in ['Muscle Gain', 'General Fitness']) {
        final out = ConditioningFinisher.apply(plan, _profile(goal: goal), catalog);
        expect(out[0].exercises.length, 2, reason: '$goal must not get a finisher');
        expect(out, same(plan), reason: '$goal returns the same plan instance');
      }
    });

    test('Knee limitation excludes jump/plyo finishers; a knee-safe one is still used', () {
      final plan = [_trainDay('Mon', [_bench])];
      final out = ConditioningFinisher.apply(
        plan,
        _profile(goal: 'Weight Loss', limitations: ['Knee Pain']),
        catalog,
      );
      expect(out[0].exercises.length, 2);
      final finisher = out[0].exercises.last.exercise;
      expect(finisher.id, 'rope', reason: 'burpee/jump squat blocked by knee → the safe rope');
    });

    test('Knee limitation with only jump conditioning → day unchanged (graceful)', () {
      final plan = [_trainDay('Mon', [_bench])];
      final out = ConditioningFinisher.apply(
        plan,
        _profile(goal: 'Weight Loss', limitations: ['Knee Pain']),
        [_bench, _burpee, _jumpsquat], // no knee-safe conditioning move
      );
      expect(out[0].exercises.length, 1, reason: 'no eligible finisher → unchanged');
    });

    test('does not duplicate a conditioning move already in the day', () {
      final plan = [_trainDay('Mon', [_bench, _rope])]; // rope already present
      final out = ConditioningFinisher.apply(
        plan,
        _profile(goal: 'Weight Loss'),
        [_bench, _rope], // rope is the only conditioning option
      );
      expect(out[0].exercises.length, 2, reason: 'only conditioning move already present → skip');
    });

    test('skips a day whose focus is already cardio/conditioning', () {
      final plan = [_trainDay('Mon', [_squat], focus: 'Conditioning (Cardio)')];
      final out = ConditioningFinisher.apply(plan, _profile(goal: 'Weight Loss'), catalog);
      expect(out[0].exercises.length, 1, reason: 'cardio-focus day gets no finisher');
    });

    test('empty pool → plan unchanged', () {
      final plan = [_trainDay('Mon', [_bench])];
      final out = ConditioningFinisher.apply(plan, _profile(goal: 'Weight Loss'), const []);
      expect(out, same(plan));
    });
  });

  group('ConditioningFinisher — Gym treadmill (15 min)', () {
    final gymCatalog = [_bench, _squat, _treadmill, _burpee];

    test('Gym + Weight Loss: each training day ends with treadmill 1 x 15 min', () {
      final plan = [
        _trainDay('Mon', [_bench, _squat]),
        _restDay('Tue'),
        _trainDay('Wed', [_bench]),
      ];
      final out = ConditioningFinisher.apply(
          plan, _profile(goal: 'Weight Loss', location: 'Gym'), gymCatalog);
      expect(out[1].isRest, isTrue);
      for (final i in [0, 2]) {
        final last = out[i].exercises.last;
        expect(last.exercise.id, 'treadmill');
        expect(last.reps, '15 min');
        expect(last.sets, 1);
      }
    });

    test('Gym + Endurance: treadmill finisher too', () {
      final out = ConditioningFinisher.apply(
          [_trainDay('Mon', [_bench])],
          _profile(goal: 'Endurance', location: 'Gym'), gymCatalog);
      expect(out[0].exercises.last.exercise.id, 'treadmill');
      expect(out[0].exercises.last.reps, '15 min');
    });

    test('Home + Weight Loss: gym treadmill excluded → bodyweight fallback', () {
      final out = ConditioningFinisher.apply(
          [_trainDay('Mon', [_bench])],
          _profile(goal: 'Weight Loss', location: 'Home'), gymCatalog);
      final last = out[0].exercises.last.exercise;
      expect(last.id, isNot('treadmill'));
      expect(last.id, 'burpee', reason: 'bodyweight conditioning fallback');
    });

    test('Gym + Weight Loss with no treadmill in pool → built-in treadmill (with gif)', () {
      final out = ConditioningFinisher.apply(
          [_trainDay('Mon', [_bench])],
          _profile(goal: 'Weight Loss', location: 'Gym'),
          [_bench, _burpee]);
      final last = out[0].exercises.last;
      expect(last.exercise.id, 'onefit_treadmill');
      expect(last.reps, '15 min');
      expect(last.sets, 1);
      expect(last.exercise.gifUrl, isNotNull);
      expect(last.exercise.gifUrl, isNotEmpty);
    });
  });
}
