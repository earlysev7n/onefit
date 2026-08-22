import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/greedy_algorithm.dart';
import 'package:onefit/data/age_prescription.dart';
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
  int age = 30,
  String goal = 'Muscle Gain',
  String level = 'Intermediate',
  String location = 'Home',
  List<String> limitations = const [],
}) => UserProfile(
  uid: 'u1',
  name: 'Test',
  gender: 'Male',
  age: age,
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

  group('ageReducesIntensity gate', () {
    test('true at/above 65, false below', () {
      expect(ageReducesIntensity(30), isFalse);
      expect(ageReducesIntensity(64), isFalse);
      expect(ageReducesIntensity(65), isTrue);
      expect(ageReducesIntensity(70), isTrue);
      expect(kOlderAdultAge, 65);
    });
  });

  group('sets — slightly reduced for older adults (never reps)', () {
    test('age 70 reduces sets vs a younger profile (Muscle Gain / Intermediate)',
        () {
      final young = greedy.setsForDifficulty(_profile(age: 30), 'same');
      final old = greedy.setsForDifficulty(_profile(age: 70), 'same');
      expect(young, 4); // Muscle Gain / Intermediate baseline
      expect(old, 3); // −1 set
      expect(old, lessThan(young));
    });

    test('just under the threshold (age 64) gets no reduction', () {
      expect(
        greedy.setsForDifficulty(_profile(age: 64), 'same'),
        greedy.setsForDifficulty(_profile(age: 30), 'same'),
      );
    });

    test('never drops below the 2-set floor (Endurance / Beginner)', () {
      final old = greedy.setsForDifficulty(
        _profile(age: 70, goal: 'Endurance', level: 'Beginner'),
        'same',
      );
      expect(old, greaterThanOrEqualTo(2));
    });
  });

  group('rest — increased for older adults', () {
    test('age 70 lengthens rest by _kAgeRestBonus (30 s)', () {
      final young = greedy.restSecondsForProfile(_profile(age: 30));
      final old = greedy.restSecondsForProfile(_profile(age: 70));
      expect(old, greaterThan(young));
      expect(old, young + 30); // +_kAgeRestBonus
    });

    test('age 64 gets no rest bonus', () {
      expect(
        greedy.restSecondsForProfile(_profile(age: 64)),
        greedy.restSecondsForProfile(_profile(age: 30)),
      );
    });
  });

  group('reps — unchanged (goal-driven), rest still differs', () {
    test('represcribeDay: same reps, longer rest at age 70', () {
      final ordered = [
        _we(_ex(id: 'bench', name: 'Bench Press')),
        _we(_ex(id: 'fly', name: 'Cable Fly', category: 'chest')),
      ];
      final young = greedy.represcribeDay(_profile(age: 30), ordered);
      final old = greedy.represcribeDay(_profile(age: 70), ordered);
      // Reps identical (age must NOT touch reps).
      expect(
        old.map((w) => w.reps).toList(),
        young.map((w) => w.reps).toList(),
      );
      // Rest is longer at age 70.
      expect(old.first.restSeconds, greaterThan(young.first.restSeconds));
    });
  });

  group('stacks additively with the limitation modifier', () {
    test('age 70 + High Blood Pressure: sets hit the 2 floor', () {
      final both = greedy.setsForDifficulty(
        _profile(age: 70, limitations: const ['High Blood Pressure']),
        'same',
      );
      // Muscle Gain / Intermediate base 4 → −1 (HBP) → −1 (age) → 2 (floor).
      expect(both, 2);
    });

    test('age 70 + High Blood Pressure: rest stacks (+45 +30)', () {
      final base = greedy.restSecondsForProfile(_profile(age: 30));
      final both = greedy.restSecondsForProfile(
        _profile(age: 70, limitations: const ['High Blood Pressure']),
      );
      final hbpOnly = greedy.restSecondsForProfile(
        _profile(age: 30, limitations: const ['High Blood Pressure']),
      );
      expect(both, base + 45 + 30); // both bonuses, below the 210 ceiling
      expect(both, greaterThan(hbpOnly));
      expect(both, lessThanOrEqualTo(210)); // extended rest ceiling
    });
  });
}
