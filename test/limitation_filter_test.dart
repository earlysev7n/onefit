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

bool _blocked(Exercise e, List<String> areas) =>
    exerciseBlockedByLimitations(e, areas);

void main() {
  group('exerciseBlockedByLimitations — single always-on layer', () {
    test('empty inputs never block (existing users unaffected)', () {
      expect(
        _blocked(_ex(name: 'Burpee', category: 'cardio'), const []),
        isFalse,
      );
    });

    test('Asthma blocks the cardio category', () {
      expect(
        _blocked(
          _ex(name: 'Treadmill Run', category: 'cardio'),
          const ['Asthma'],
        ),
        isTrue,
      );
    });

    test('Asthma blocks a HIIT keyword (burpee) even if not cardio-tagged', () {
      expect(
        _blocked(_ex(name: 'Burpee', category: 'full body'), const ['Asthma']),
        isTrue,
      );
    });

    test('Asthma leaves a normal strength lift alone', () {
      expect(
        _blocked(_ex(name: 'Bench Press', category: 'chest'), const ['Asthma']),
        isFalse,
      );
    });

    group('Shoulder Pain blocks overhead-press variants (auto-block)', () {
      for (final name in const [
        'Overhead Press',
        'Dumbbell Bench Seated Press',
        'Pike Push-Up',
        'Barbell Push Press',
        'Handstand Push-Up',
        'Arnold Press',
        'Triceps Dip',
      ]) {
        test('blocks "$name"', () {
          expect(
            _blocked(
              _ex(name: name, category: 'shoulders'),
              const ['Shoulder Pain'],
            ),
            isTrue,
          );
        });
      }
    });

    test('Shoulder Pain now ALSO blocks its mapped movements (always-on)', () {
      // Lateral/front raise were opt-in before; selecting the area now blocks
      // them directly, with no avoidedMovements needed.
      expect(
        _blocked(
          _ex(name: 'Dumbbell Lateral Raise', category: 'shoulders'),
          const ['Shoulder Pain'],
        ),
        isTrue,
      );
      expect(
        _blocked(
          _ex(name: 'Cable Front Raise', category: 'shoulders'),
          const ['Shoulder Pain'],
        ),
        isTrue,
      );
    });

    group('Shoulder Pain leaves therapeutic rear-delt work alone', () {
      for (final name in const [
        'Cable Face Pull',
        'Band Pull Apart',
        'Rear Delt Fly',
        'Bench Press',
      ]) {
        test('does not block "$name"', () {
          expect(
            _blocked(
              _ex(name: name, category: 'shoulders'),
              const ['Shoulder Pain'],
            ),
            isFalse,
          );
        });
      }
    });

    test('specific "dip" keywords do not over-match unrelated moves', () {
      expect(
        _blocked(
          _ex(name: 'Standing Hip Dip', category: 'core'),
          const ['Shoulder Pain'],
        ),
        isFalse,
      );
    });

    test('Lower Back Pain blocks sit-up (auto) AND squat/deadlift (movements)', () {
      expect(
        _blocked(
          _ex(name: 'Sit-Up', category: 'core'),
          const ['Lower Back Pain'],
        ),
        isTrue,
      );
      // Squat & deadlift are now always-on for a selected area.
      expect(
        _blocked(
          _ex(name: 'Barbell Back Squat', category: 'legs'),
          const ['Lower Back Pain'],
        ),
        isTrue,
      );
      expect(
        _blocked(
          _ex(name: 'Barbell Deadlift', category: 'legs'),
          const ['Lower Back Pain'],
        ),
        isTrue,
      );
    });

    test('Ankle Pain auto-blocks box jump', () {
      expect(
        _blocked(
          _ex(name: 'Box Jump', category: 'plyometrics'),
          const ['Ankle Pain'],
        ),
        isTrue,
      );
    });

    group('formerly opt-in areas now block their movements on selection', () {
      // area → an exercise name that should be blocked purely by selecting it.
      final cases = {
        'Wrist Pain': 'Diamond Push-Up',
        'Elbow Pain': 'EZ-Bar Skullcrusher',
        'Hip Pain': 'Trap Bar Deadlift',
        'Neck Pain': 'Cable Upright Row',
        'Knee Pain': 'Front Squat',
      };
      cases.forEach((area, exName) {
        test('$area blocks "$exName" with no avoidedMovements', () {
          expect(_blocked(_ex(name: exName), [area]), isTrue);
        });
      });
    });

    test('precise keywords still avoid over-matching (leg curl under Knee)', () {
      expect(
        _blocked(
          _ex(name: 'Seated Leg Curl', category: 'legs'),
          const ['Knee Pain'],
        ),
        isFalse,
      );
    });
  });

  group('limitationReasonFor', () {
    test('returns the offending area id for a blocked move', () {
      expect(
        limitationReasonFor(
          _ex(name: 'Overhead Press', category: 'shoulders'),
          const ['Shoulder Pain'],
        ),
        'Shoulder Pain',
      );
    });

    test('returns null for a move the user can safely perform', () {
      expect(
        limitationReasonFor(
          _ex(name: 'Rear Delt Fly', category: 'shoulders'),
          const ['Shoulder Pain'],
        ),
        isNull,
      );
    });

    test('returns null when no areas are selected', () {
      expect(
        limitationReasonFor(_ex(name: 'Burpee', category: 'cardio'), const []),
        isNull,
      );
    });
  });

  group('isEligibleForUser respects limitations (even for Gym)', () {
    test('Gym profile excludes a cardio move when Asthma is set', () {
      final cardio = _ex(name: 'Jump Rope', category: 'cardio');
      expect(GreedyAlgorithm.isEligibleForUser(cardio, _profile()), isTrue);
      expect(
        GreedyAlgorithm.isEligibleForUser(
          cardio,
          _profile(limitations: const ['Asthma']),
        ),
        isFalse,
      );
    });

    test('Gym profile excludes a mapped movement on selection (Shoulder Pain)', () {
      final latRaise = _ex(
        name: 'Dumbbell Lateral Raise',
        category: 'shoulders',
      );
      expect(
        GreedyAlgorithm.isEligibleForUser(latRaise, _profile()),
        isTrue,
        reason: 'no limitation → eligible',
      );
      expect(
        GreedyAlgorithm.isEligibleForUser(
          latRaise,
          _profile(limitations: const ['Shoulder Pain']),
        ),
        isFalse,
        reason: 'selecting Shoulder Pain now excludes it directly',
      );
    });
  });
}
