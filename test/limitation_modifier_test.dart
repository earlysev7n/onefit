import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/conditioning_finisher.dart';
import 'package:onefit/algorithms/greedy_algorithm.dart';
import 'package:onefit/data/physical_limitations.dart';
import 'package:onefit/models/exercise.dart';
import 'package:onefit/models/user_profile.dart';

Exercise _ex({
  required String id,
  required String name,
  String category = 'chest',
  List<String> primaryMuscles = const ['pectorals'],
  List<String> goals = const ['muscle_gain'],
  List<String> equipment = const ['bodyweight'],
  List<String> locations = const ['home', 'gym'],
}) => Exercise(
  id: id,
  name: name,
  category: category,
  primaryMuscles: primaryMuscles,
  secondaryMuscles: const [],
  equipment: equipment,
  difficulty: 'beginner',
  goals: goals,
  locations: locations,
  instructions: '',
);

UserProfile _profile({
  String goal = 'Muscle Gain',
  String level = 'Intermediate',
  String location = 'Home',
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

WorkoutExercise _we(Exercise e) =>
    WorkoutExercise(exercise: e, sets: 4, reps: '8-12', restSeconds: 90);

void main() {
  final greedy = GreedyAlgorithm();

  group('limitationsReduceIntensity', () {
    test('true for Asthma and High Blood Pressure, false otherwise', () {
      expect(limitationsReduceIntensity(const ['High Blood Pressure']), isTrue);
      expect(limitationsReduceIntensity(const ['Asthma']), isTrue);
      expect(limitationsReduceIntensity(const ['Knee Pain']), isFalse);
      expect(limitationsReduceIntensity(const []), isFalse);
    });
  });

  group('sets — slightly reduced (never reps)', () {
    test('HBP reduces sets vs no limitation (Muscle Gain / Intermediate)', () {
      final hbp = greedy.setsForDifficulty(
        _profile(limitations: const ['High Blood Pressure']),
        'same',
      );
      final none = greedy.setsForDifficulty(_profile(), 'same');
      expect(none, 4); // Muscle Gain / Intermediate baseline
      expect(hbp, 3); // −1 set
      expect(hbp, lessThan(none));
    });

    test('Asthma reduces sets the same way', () {
      final asthma = greedy.setsForDifficulty(
        _profile(limitations: const ['Asthma']),
        'same',
      );
      expect(asthma, lessThan(greedy.setsForDifficulty(_profile(), 'same')));
      expect(asthma, greaterThanOrEqualTo(2));
    });

    test('never drops below the 2-set floor (Endurance / Beginner)', () {
      final hbp = greedy.setsForDifficulty(
        _profile(goal: 'Endurance', level: 'Beginner',
            limitations: const ['High Blood Pressure']),
        'same',
      );
      expect(hbp, greaterThanOrEqualTo(2));
    });
  });

  group('rest — increased', () {
    test('HBP lengthens rest vs no limitation', () {
      final hbp = greedy.restSecondsForProfile(
        _profile(limitations: const ['High Blood Pressure']),
      );
      final none = greedy.restSecondsForProfile(_profile());
      expect(hbp, greaterThan(none));
      expect(hbp, none + 45); // +_kLimitationRestBonus
    });
  });

  group('reps — unchanged (goal-driven), rest still differs', () {
    test('represcribeDay: same reps, longer rest under HBP', () {
      final ordered = [
        _we(_ex(id: 'bench', name: 'Bench Press')),
        _we(_ex(id: 'fly', name: 'Cable Fly', category: 'chest')),
      ];
      final none = greedy.represcribeDay(_profile(), ordered);
      final hbp = greedy.represcribeDay(
        _profile(limitations: const ['High Blood Pressure']),
        ordered,
      );
      // Reps identical (limitation must NOT touch reps).
      expect(
        hbp.map((w) => w.reps).toList(),
        none.map((w) => w.reps).toList(),
      );
      // Rest is longer under HBP.
      expect(hbp.first.restSeconds, greaterThan(none.first.restSeconds));
    });
  });

  group('conditioning finisher — excluded under intensity-caution', () {
    final bench = _ex(id: 'bench', name: 'Bench Press');
    final burpee = _ex(id: 'burpee', name: 'Burpee', category: 'cardio',
        goals: const ['endurance', 'weight_loss'], primaryMuscles: const ['quads']);
    final pool = [bench, burpee];
    final plan = [
      WorkoutDay(dayName: 'Mon', focus: 'Full Body', exercises: [_we(bench)]),
    ];

    test('Weight Loss without limitation appends a finisher', () {
      final out = ConditioningFinisher.apply(
        plan, _profile(goal: 'Weight Loss', location: 'Home'), pool);
      expect(out.first.exercises.length, 2); // finisher appended
    });

    test('Weight Loss + HBP appends nothing', () {
      final out = ConditioningFinisher.apply(
        plan,
        _profile(goal: 'Weight Loss', location: 'Home',
            limitations: const ['High Blood Pressure']),
        pool,
      );
      expect(out.first.exercises.length, 1); // unchanged
    });

    test('Weight Loss + Asthma appends nothing', () {
      final out = ConditioningFinisher.apply(
        plan,
        _profile(goal: 'Weight Loss', location: 'Home',
            limitations: const ['Asthma']),
        pool,
      );
      expect(out.first.exercises.length, 1); // unchanged
    });
  });
}
