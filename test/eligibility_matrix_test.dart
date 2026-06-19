// Panelist-style verification of the workout eligibility matrix:
// experience level × workout location × home-equipment set.
//
// GreedyAlgorithm.isEligibleForUser and difficultyAllowed are pure static
// methods over plain Exercise/UserProfile objects (no Firebase), so the whole
// matrix can be asserted with `flutter test test/eligibility_matrix_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/greedy_algorithm.dart';
import 'package:onefit/models/exercise.dart';
import 'package:onefit/models/user_profile.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

Exercise _ex({
  required String name,
  required List<String> equipment,
  required List<String> locations,
  String difficulty = 'beginner',
  List<String> primary = const ['pectorals'],
  List<String> secondary = const [],
}) => Exercise(
  id: name,
  name: name,
  category: 'Other',
  primaryMuscles: primary,
  secondaryMuscles: secondary,
  equipment: equipment,
  difficulty: difficulty,
  goals: const ['general'],
  locations: locations,
  instructions: '',
);

UserProfile _profile({
  String level = 'Intermediate',
  String location = 'Home',
  List<String> equipment = const ['Bodyweight'],
  String gender = 'Male',
}) => UserProfile(
  uid: 'test',
  name: 'Test',
  gender: gender,
  age: 30,
  weight: 75,
  height: 175,
  fitnessGoal: 'Muscle Gain',
  experienceLevel: level,
  workoutLocation: location,
  equipment: equipment,
  dietaryRestrictions: const [],
);

// Mirrors PlansScreen._usableByUser — hard constraints + experience gate.
bool _usable(Exercise e, UserProfile p) =>
    GreedyAlgorithm.isEligibleForUser(e, p) &&
    GreedyAlgorithm.difficultyAllowed(e.difficulty, p.experienceLevel);

// Representative exercises (all home-eligible locations except the gym machine).
final pushup = _ex(
  name: 'Push Up',
  equipment: const ['Bodyweight'],
  locations: const ['home', 'gym'],
);
final dbCurl = _ex(
  name: 'Dumbbell Curl',
  equipment: const ['Dumbbells'],
  locations: const ['home', 'gym'],
  primary: const ['biceps'],
);
final pullup = _ex(
  name: 'Pull Up',
  equipment: const ['Pull-up Bar'],
  locations: const ['home', 'gym'],
  difficulty: 'intermediate',
  primary: const ['lats'],
);
final bbDeadlift = _ex(
  name: 'Barbell Deadlift',
  equipment: const ['Barbell'],
  locations: const ['home', 'gym'],
  difficulty: 'intermediate',
  primary: const ['glutes'],
);
final bbBackSquat = _ex(
  name: 'Barbell Back Squat',
  equipment: const ['Barbell'],
  locations: const ['home', 'gym'],
  difficulty: 'intermediate',
  primary: const ['quads'],
);
final bbBenchPress = _ex(
  name: 'Barbell Bench Press',
  equipment: const ['Barbell'],
  locations: const ['home', 'gym'],
  difficulty: 'intermediate',
  primary: const ['pectorals'],
);
final dbInclinePress = _ex(
  name: 'Dumbbell Incline Press',
  equipment: const ['Dumbbells'],
  locations: const ['home', 'gym'],
  difficulty: 'intermediate',
  primary: const ['pectorals'],
);
final cableRow = _ex(
  name: 'Cable Row',
  equipment: const ['Cable Machine'],
  locations: const ['gym'],
  difficulty: 'intermediate',
  primary: const ['lats'],
);
// ExerciseDB tags pull-up moves with 'body weight' (the resistance source),
// normalized to 'Bodyweight'. The exercise still needs a physical bar.
final pullupBwTagged = _ex(
  name: 'Pull Up (neutral Grip)',
  equipment: const ['Bodyweight'], // ← how ExerciseDB actually tags it
  locations: const ['home', 'gym'],
  difficulty: 'intermediate',
  primary: const ['lats'],
);
// API mis-tag: has 'pull-up bar' equipment but is a cable machine exercise.
final inverseLegCurl = _ex(
  name: 'Inverse Leg Curl (on Pull-up Cable Machine)',
  equipment: const ['Pull-up Bar'],
  locations: const ['home', 'gym'],
  primary: const ['hamstrings'],
);
final pistolSquat = _ex(
  name: 'Pistol Squat',
  equipment: const ['Bodyweight'],
  locations: const ['home', 'gym'],
  difficulty: 'advanced',
  primary: const ['quads'],
);
final maleCrunch = _ex(
  name: 'Crunch (male)',
  equipment: const ['Bodyweight'],
  locations: const ['home', 'gym'],
  primary: const ['abs'],
);

// Home-equipment sets (Bodyweight always present — the locked baseline).
const bwOnly = ['Bodyweight'];
const withDumbbells = ['Bodyweight', 'Dumbbells'];
const withPullupBar = ['Bodyweight', 'Pull-up Bar'];
const withBarbell = ['Bodyweight', 'Barbell'];
const withBarbellBench = ['Bodyweight', 'Barbell', 'Bench'];
const homeGymFull = [
  'Bodyweight',
  'Dumbbells',
  'Pull-up Bar',
  'Barbell',
  'Bench',
  'Home Gym',
];

void main() {
  group('Equipment matrix at Home (Intermediate)', () {
    void expectEligible(Exercise e, List<String> equip, bool want) {
      final p = _profile(location: 'Home', equipment: equip);
      expect(
        GreedyAlgorithm.isEligibleForUser(e, p),
        want,
        reason: '${e.name} with $equip should be ${want ? "eligible" : "blocked"}',
      );
    }

    test('Push-up (bodyweight) is eligible with every equipment set', () {
      for (final set in [
        bwOnly,
        withDumbbells,
        withPullupBar,
        withBarbell,
        withBarbellBench,
        homeGymFull,
      ]) {
        expectEligible(pushup, set, true);
      }
    });

    test('Dumbbell curl needs Dumbbells', () {
      expectEligible(dbCurl, bwOnly, false);
      expectEligible(dbCurl, withDumbbells, true);
      expectEligible(dbCurl, withPullupBar, false);
      expectEligible(dbCurl, homeGymFull, true);
    });

    test('Pull-up needs the Pull-up Bar', () {
      expectEligible(pullup, bwOnly, false);
      expectEligible(pullup, withPullupBar, true);
      expectEligible(pullup, withDumbbells, false);
      expectEligible(pullup, homeGymFull, true);
    });

    test('Pull-up tagged Bodyweight by API still needs Pull-up Bar chip', () {
      // ExerciseDB returns equipment:"body weight" for pull-ups (the resistance
      // source). After normalisation that's 'Bodyweight', which previously
      // short-circuited the equipment gate and let pull-ups slip through for
      // Bodyweight-only users. _pullupTag closes this gap.
      expectEligible(pullupBwTagged, bwOnly, false);
      expectEligible(pullupBwTagged, withPullupBar, true);
      expectEligible(pullupBwTagged, withDumbbells, false);
      expectEligible(pullupBwTagged, homeGymFull, true);
    });

    test('Barbell deadlift (no rack) needs only Barbell', () {
      expectEligible(bbDeadlift, bwOnly, false);
      expectEligible(bbDeadlift, withBarbell, true);
      expectEligible(bbDeadlift, withBarbellBench, true);
      expectEligible(bbDeadlift, homeGymFull, true);
    });

    test('Barbell back squat needs a rack (Home Gym)', () {
      expectEligible(bbBackSquat, withBarbell, false);
      expectEligible(bbBackSquat, withBarbellBench, false);
      expectEligible(bbBackSquat, homeGymFull, true);
    });

    test('Barbell bench press needs barbell + bench + rack', () {
      expectEligible(bbBenchPress, withBarbell, false);
      expectEligible(bbBenchPress, withBarbellBench, false); // no rack
      expectEligible(bbBenchPress, homeGymFull, true);
    });

    test('Dumbbell incline press needs a Bench', () {
      expectEligible(dbInclinePress, withDumbbells, false); // no bench
      expectEligible(dbInclinePress, withBarbellBench, false); // no dumbbells
      expectEligible(
        dbInclinePress,
        const ['Bodyweight', 'Dumbbells', 'Bench'],
        true,
      );
      expectEligible(dbInclinePress, homeGymFull, true);
    });

    test('Cable/machine move is never home-eligible', () {
      for (final set in [bwOnly, withBarbell, homeGymFull]) {
        expectEligible(cableRow, set, false);
      }
    });

    test('API mis-tagged cable exercise blocked even with pull-up bar', () {
      // "Inverse Leg Curl (on Pull-up Cable Machine)" has pull-up bar in its
      // equipment list (API data quality bug) but the name reveals it is a
      // cable machine — must be rejected for all home equipment sets.
      for (final set in [bwOnly, withPullupBar, homeGymFull]) {
        expectEligible(inverseLegCurl, set, false);
      }
    });
  });

  group('Gym allows everything (equipment ignored)', () {
    final gym = _profile(location: 'Gym', equipment: const []);
    test('every representative move is gym-eligible', () {
      for (final e in [
        pushup,
        dbCurl,
        pullup,
        bbDeadlift,
        bbBackSquat,
        bbBenchPress,
        dbInclinePress,
        cableRow,
      ]) {
        expect(GreedyAlgorithm.isEligibleForUser(e, gym), true,
            reason: '${e.name} should be gym-eligible');
      }
    });
  });

  group('Experience gate (difficultyAllowed)', () {
    test('advanced pistol squat: only Advanced may use it', () {
      final bw = bwOnly;
      expect(_usable(pistolSquat, _profile(level: 'Beginner', equipment: bw)),
          false);
      expect(
          _usable(pistolSquat, _profile(level: 'Intermediate', equipment: bw)),
          false);
      expect(_usable(pistolSquat, _profile(level: 'Advanced', equipment: bw)),
          true);
    });

    test('beginner push-up usable at every level', () {
      for (final lvl in ['Beginner', 'Intermediate', 'Advanced']) {
        expect(_usable(pushup, _profile(level: lvl, equipment: bwOnly)), true);
      }
    });
  });

  group('Gender variant filter', () {
    test('(male) demo excluded for a Female profile', () {
      final female = _profile(gender: 'Female', equipment: bwOnly);
      final male = _profile(gender: 'Male', equipment: bwOnly);
      expect(GreedyAlgorithm.isEligibleForUser(maleCrunch, female), false);
      expect(GreedyAlgorithm.isEligibleForUser(maleCrunch, male), true);
    });
  });

  group('Bodyweight-only home user always has a pool', () {
    test('a real-ish bodyweight catalog yields eligible moves per focus', () {
      final p = _profile(level: 'Intermediate', equipment: bwOnly);
      final catalog = [
        pushup,
        pistolSquat, // advanced — gated out by the level gate, not equipment
        _ex(
          name: 'Bodyweight Squat',
          equipment: const ['Bodyweight'],
          locations: const ['home', 'gym'],
          primary: const ['quads'],
        ),
        _ex(
          name: 'Plank',
          equipment: const ['Bodyweight'],
          locations: const ['home', 'gym'],
          primary: const ['abs'],
        ),
        bbBackSquat, // barbell — gated out by equipment
      ];
      final usable = catalog.where((e) => _usable(e, p)).toList();
      expect(usable.map((e) => e.name),
          containsAll(['Push Up', 'Bodyweight Squat', 'Plank']));
      expect(usable.contains(bbBackSquat), false);
      expect(usable.contains(pistolSquat), false);
    });
  });
}
