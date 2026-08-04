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
  List<String> avoided = const [],
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
  avoidedMovements: avoided,
);

// Convenience: no opt-in movements.
bool _blocked(Exercise e, List<String> areas, [List<String> avoided = const []]) =>
    exerciseBlockedByLimitations(e, areas, avoided);

void main() {
  group('exerciseBlockedByLimitations — auto-block layer', () {
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
        _blocked(
          _ex(name: 'Burpee', category: 'full body'),
          const ['Asthma'],
        ),
        isTrue,
      );
    });

    test('Asthma leaves a normal strength lift alone', () {
      expect(
        _blocked(
          _ex(name: 'Bench Press', category: 'chest'),
          const ['Asthma'],
        ),
        isFalse,
      );
    });

    group('Shoulder Pain auto-block covers overhead-press variants', () {
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
            _blocked(_ex(name: name, category: 'shoulders'),
                const ['Shoulder Pain']),
            isTrue,
          );
        });
      }
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
            _blocked(_ex(name: name, category: 'shoulders'),
                const ['Shoulder Pain']),
            isFalse,
          );
        });
      }
    });

    test('specific "dip" keywords do not over-match unrelated moves', () {
      // Bare "dip" substring should NOT trigger on an unrelated hip move.
      expect(
        _blocked(
          _ex(name: 'Standing Hip Dip', category: 'core'),
          const ['Shoulder Pain'],
        ),
        isFalse,
      );
    });

    test('Lower Back Pain auto-blocks sit-up but not squats/deadlift', () {
      expect(
        _blocked(_ex(name: 'Sit-Up', category: 'core'),
            const ['Lower Back Pain']),
        isTrue,
      );
      // Squat & deadlift are opt-in, not auto-blocked.
      expect(
        _blocked(_ex(name: 'Barbell Back Squat', category: 'legs'),
            const ['Lower Back Pain']),
        isFalse,
      );
      expect(
        _blocked(_ex(name: 'Barbell Deadlift', category: 'legs'),
            const ['Lower Back Pain']),
        isFalse,
      );
    });

    test('Ankle Pain auto-blocks box jump', () {
      expect(
        _blocked(_ex(name: 'Box Jump', category: 'plyometrics'),
            const ['Ankle Pain']),
        isTrue,
      );
    });
  });

  group('exerciseBlockedByLimitations — opt-in movement layer', () {
    test('lateral raise blocked ONLY when opted in', () {
      final latRaise = _ex(name: 'Dumbbell Lateral Raise', category: 'shoulders');
      expect(_blocked(latRaise, const ['Shoulder Pain']), isFalse);
      expect(
        _blocked(latRaise, const ['Shoulder Pain'], const ['Lateral Raise']),
        isTrue,
      );
    });

    test('Lower Back: back squat blocked only when opted in', () {
      final squat = _ex(name: 'Barbell Back Squat', category: 'legs');
      expect(_blocked(squat, const ['Lower Back Pain']), isFalse);
      expect(
        _blocked(squat, const ['Lower Back Pain'], const ['Barbell Squat']),
        isTrue,
      );
    });

    test('precise keywords: opting out of Barbell Squat spares Front Squat', () {
      expect(
        _blocked(
          _ex(name: 'Front Squat', category: 'legs'),
          const ['Knee Pain'],
          const ['Barbell Squat'],
        ),
        isFalse,
      );
    });

    group('new areas block a sample movement when opted in', () {
      final cases = {
        'Wrist Pain': ['Push-Up', 'Diamond Push-Up'],
        'Elbow Pain': ['Skullcrusher', 'EZ-Bar Skullcrusher'],
        'Hip Pain': ['Deadlift', 'Trap Bar Deadlift'],
        'Neck Pain': ['Upright Row', 'Cable Upright Row'],
      };
      cases.forEach((area, pair) {
        final movementId = pair[0];
        final exName = pair[1];
        test('$area + "$movementId" blocks "$exName"', () {
          final ex = _ex(name: exName);
          expect(_blocked(ex, [area]), isFalse);
          expect(_blocked(ex, [area], [movementId]), isTrue);
        });
      });
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

    test('Gym profile excludes an opted-in movement (Shoulder Pain)', () {
      final latRaise = _ex(name: 'Dumbbell Lateral Raise', category: 'shoulders');
      expect(
        GreedyAlgorithm.isEligibleForUser(
          latRaise,
          _profile(limitations: const ['Shoulder Pain']),
        ),
        isTrue,
        reason: 'lateral raise is opt-in, not auto-blocked',
      );
      expect(
        GreedyAlgorithm.isEligibleForUser(
          latRaise,
          _profile(
            limitations: const ['Shoulder Pain'],
            avoided: const ['Lateral Raise'],
          ),
        ),
        isFalse,
        reason: 'opted-in → excluded',
      );
    });
  });
}
