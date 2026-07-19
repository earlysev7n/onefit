import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/greedy_algorithm.dart';
import 'package:onefit/data/physical_limitations.dart';
import 'package:onefit/models/exercise.dart';
import 'package:onefit/models/user_profile.dart';

Exercise _ex({
  required String name,
  String category = 'strength',
  List<String> primaryMuscles = const ['chest'],
  List<String> equipment = const ['barbell'],
  List<String> locations = const ['home', 'gym'],
  String difficulty = 'beginner',
}) => Exercise(
  id: name.toLowerCase().replaceAll(' ', '_'),
  name: name,
  category: category,
  primaryMuscles: primaryMuscles,
  secondaryMuscles: const [],
  equipment: equipment,
  difficulty: difficulty,
  goals: const [],
  locations: locations,
  instructions: '',
);

UserProfile _profile({
  List<String> limitations = const [],
  String location = 'Gym',
}) => UserProfile(
  uid: 'u1',
  name: 'Test',
  gender: 'Male',
  age: 30,
  weight: 80,
  height: 180,
  fitnessGoal: 'Muscle Gain',
  experienceLevel: 'Advanced',
  workoutLocation: location,
  equipment: const [],
  dietaryRestrictions: const ['Balanced'],
  physicalLimitations: limitations,
);

void main() {
  group('exerciseBlockedByLimitations', () {
    test('empty limitations never blocks (existing users unaffected)', () {
      expect(
        exerciseBlockedByLimitations(
          _ex(name: 'Burpee', category: 'cardio'),
          const [],
        ),
        isFalse,
      );
    });

    test('Asthma blocks the cardio category', () {
      expect(
        exerciseBlockedByLimitations(
          _ex(name: 'Treadmill Run', category: 'cardio'),
          const ['Asthma'],
        ),
        isTrue,
      );
    });

    test('Asthma blocks a HIIT keyword (burpee) even if not cardio-tagged', () {
      expect(
        exerciseBlockedByLimitations(
          _ex(name: 'Burpee', category: 'full body'),
          const ['Asthma'],
        ),
        isTrue,
      );
    });

    test('Asthma leaves a normal strength lift alone', () {
      expect(
        exerciseBlockedByLimitations(
          _ex(name: 'Bench Press', category: 'chest'),
          const ['Asthma'],
        ),
        isFalse,
      );
    });

    test('Lower-back pain blocks deadlift but not leg press', () {
      expect(
        exerciseBlockedByLimitations(
          _ex(name: 'Barbell Deadlift', category: 'legs'),
          const ['Lower-back pain'],
        ),
        isTrue,
      );
      expect(
        exerciseBlockedByLimitations(
          _ex(name: 'Leg Press', category: 'legs'),
          const ['Lower-back pain'],
        ),
        isFalse,
      );
    });

    test('Shoulder injury blocks overhead press but not a bench press', () {
      expect(
        exerciseBlockedByLimitations(
          _ex(name: 'Overhead Press', category: 'shoulders'),
          const ['Shoulder injury'],
        ),
        isTrue,
      );
      expect(
        exerciseBlockedByLimitations(
          _ex(name: 'Bench Press', category: 'chest'),
          const ['Shoulder injury'],
        ),
        isFalse,
      );
    });

    test('specific "dip" keywords do not over-match unrelated moves', () {
      expect(
        exerciseBlockedByLimitations(
          _ex(name: 'Triceps Dip', category: 'arms'),
          const ['Shoulder injury'],
        ),
        isTrue,
      );
      // Bare "dip" substring should NOT trigger on an unrelated hip move.
      expect(
        exerciseBlockedByLimitations(
          _ex(name: 'Standing Hip Dip', category: 'core'),
          const ['Shoulder injury'],
        ),
        isFalse,
      );
    });
  });

  group('isEligibleForUser respects limitations (even for Gym)', () {
    test('Gym profile still excludes a cardio move when Asthma is set', () {
      final cardio = _ex(name: 'Jump Rope', category: 'cardio');
      expect(
        GreedyAlgorithm.isEligibleForUser(cardio, _profile()),
        isTrue,
        reason: 'no limitation → eligible',
      );
      expect(
        GreedyAlgorithm.isEligibleForUser(
          cardio,
          _profile(limitations: const ['Asthma']),
        ),
        isFalse,
        reason: 'Asthma → cardio excluded even at a gym',
      );
    });
  });
}
