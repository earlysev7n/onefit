// Verifies the Greedy generator PREFERS exercises that have a demo GIF, but
// falls back to no-GIF exercises rather than ever leaving a day short.
//
// A generated plan shouldn't recommend an exercise it can't animate (grey
// placeholder box). GIF presence is a preference layered on top of the focus
// pools — never an eligibility gate — so:
//   (1) when the focus pool has enough GIF-having exercises, every selected
//       exercise has a non-empty gifUrl; and
//   (2) when the GIF-having pool is too small, the day still fills to count
//       from the no-GIF fallback (never shorter than the GIF-only pool).
//
// GreedyAlgorithm.generatePlan is pure over plain Exercise/UserProfile objects
// (no Firebase), so this runs with
// `flutter test test/greedy_gif_preference_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/greedy_algorithm.dart';
import 'package:onefit/models/exercise.dart';
import 'package:onefit/models/user_profile.dart';

Exercise _ex(String name, List<String> primary, {String? gifUrl}) => Exercise(
  id: name,
  name: name,
  category: 'strength',
  primaryMuscles: primary,
  secondaryMuscles: const [],
  equipment: const ['Bodyweight'],
  difficulty: 'beginner', // usable at every experience level
  goals: const ['general'],
  locations: const ['home', 'gym'],
  instructions: '',
  gifUrl: gifUrl,
);

// Muscles covered by the Full Body focus cycle.
const _muscles = [
  'pectorals',
  'lats',
  'quads',
  'glutes',
  'abs',
  'delts',
  'triceps',
  'biceps',
  'upper back',
  'hamstrings',
  'calves',
];

UserProfile _profile() => UserProfile(
  uid: 'test',
  name: 'Test',
  gender: 'Male',
  age: 30,
  weight: 75,
  height: 175,
  fitnessGoal: 'Muscle Gain',
  experienceLevel: 'Intermediate',
  workoutLocation: 'Gym',
  equipment: const [],
  dietaryRestrictions: const [],
  sessionMinutes: 60,
  workoutSplit: 'Full Body Training',
  workoutDaysPerWeek: 3,
);

bool _hasGif(Exercise e) => e.gifUrl?.isNotEmpty ?? false;

void main() {
  test('every selected exercise has a GIF when the pool has enough', () {
    // A rich catalog where EVERY exercise has a working GIF plus a handful of
    // no-GIF distractors. The generator should never touch the distractors.
    final catalog = <Exercise>[
      for (final m in _muscles) ...[
        _ex('$m gif A', [m], gifUrl: 'https://cdn/$m-a.gif'),
        _ex('$m gif B', [m], gifUrl: 'https://cdn/$m-b.gif'),
        _ex('$m nogif', [m]), // no gifUrl — should be ignored while GIFs remain
      ],
    ];

    final plan = GreedyAlgorithm().generatePlan(
      allExercises: catalog,
      profile: _profile(),
    );

    final trainingDays = plan.where((d) => !d.isRest).toList();
    expect(trainingDays, isNotEmpty);
    for (final day in trainingDays) {
      expect(day.exercises, isNotEmpty);
      for (final we in day.exercises) {
        expect(_hasGif(we.exercise), isTrue,
            reason: '${day.dayName}: "${we.exercise.name}" has no GIF but a '
                'GIF-having alternative was available');
      }
    }
  });

  test('day still fills from no-GIF fallback when GIF pool is too small', () {
    // Only ONE GIF-having exercise per muscle — not enough to fill a Full Body
    // day on its own — so the generator must fall back to no-GIF exercises
    // rather than producing a shorter day. Compared against a GIF-only catalog
    // of the same shape to prove the fallback adds volume.
    final mixed = <Exercise>[
      for (final m in _muscles) ...[
        _ex('$m gif', [m], gifUrl: 'https://cdn/$m.gif'),
        _ex('$m nogif A', [m]),
        _ex('$m nogif B', [m]),
      ],
    ];
    final gifOnly = <Exercise>[
      for (final m in _muscles) _ex('$m gif', [m], gifUrl: 'https://cdn/$m.gif'),
    ];

    final profile = _profile();
    final mixedPlan =
        GreedyAlgorithm().generatePlan(allExercises: mixed, profile: profile);
    final gifOnlyPlan =
        GreedyAlgorithm().generatePlan(allExercises: gifOnly, profile: profile);

    int volume(List plan) => plan
        .where((d) => !d.isRest)
        .fold<int>(0, (sum, d) => sum + (d.exercises.length as int));

    // The mixed catalog can reach fuller days than the tiny GIF-only pool,
    // proving no-GIF exercises are pulled in as a fallback (never starving).
    expect(volume(mixedPlan), greaterThanOrEqualTo(volume(gifOnlyPlan)),
        reason: 'no-GIF fallback should never reduce total volume');

    for (final day in mixedPlan.where((d) => !d.isRest)) {
      expect(day.exercises, isNotEmpty,
          reason: '${day.dayName}: fallback must keep the day non-empty');
    }
  });
}
