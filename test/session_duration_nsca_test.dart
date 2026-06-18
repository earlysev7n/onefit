// Panelist-style verification of Objective 4: the Greedy generator honors the
// user's chosen session duration WITHOUT ever exceeding it, while every per-set
// loading parameter (sets / reps / rest) stays inside the NSCA goal range
// (Sheppard & Triplett, Essentials of S&C, 4th ed.).
//
// GreedyAlgorithm.generatePlan is pure over plain Exercise/UserProfile objects
// (no Firebase), so this runs with `flutter test test/session_duration_nsca_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/greedy_algorithm.dart';
import 'package:onefit/models/exercise.dart';
import 'package:onefit/models/user_profile.dart';

const _warmupReserveSec = 180; // must match GreedyAlgorithm

Exercise _ex(String name, List<String> primary) => Exercise(
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
);

// A catalog wide enough (2 moves per muscle) that selection never starves a
// Full Body (6 muscle) or PPL day.
final _catalog = <Exercise>[
  for (final m in const [
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
    'forearms', // off-focus: no focus map targets it — must never be selected
  ]) ...[
    _ex('$m move A', [m]),
    _ex('$m move B', [m]),
  ],
];

UserProfile _profile({
  required String goal,
  required int sessionMinutes,
  required String split,
  required int days,
  String level = 'Intermediate',
}) => UserProfile(
  uid: 'test',
  name: 'Test',
  gender: 'Male',
  age: 30,
  weight: 75,
  height: 175,
  fitnessGoal: goal,
  experienceLevel: level,
  workoutLocation: 'Gym', // everything eligible — isolate the volume logic
  equipment: const [],
  dietaryRestrictions: const [],
  sessionMinutes: sessionMinutes,
  workoutSplit: split,
  workoutDaysPerWeek: days,
);

// NSCA goal-loading ranges (Essentials of S&C, 4th ed.).
({int setLo, int setHi, int restLo, int restHi, int repLo, int repHi}) _nsca(
  String goal,
) {
  switch (goal) {
    case 'Muscle Gain': // hypertrophy
      return (setLo: 3, setHi: 5, restLo: 30, restHi: 90, repLo: 6, repHi: 12);
    case 'Weight Loss':
    case 'Endurance': // muscular endurance
      return (setLo: 2, setHi: 3, restLo: 30, restHi: 60, repLo: 12, repHi: 30);
    default: // general / maintenance
      return (setLo: 2, setHi: 4, restLo: 30, restHi: 90, repLo: 8, repHi: 15);
  }
}

// Largest rep in "8-12" / "15-20" / "12" (timed moves excluded from this check).
List<int> _repBounds(String reps) => RegExp(r'\d+')
    .allMatches(reps)
    .map((m) => int.parse(m.group(0)!))
    .toList();

void main() {
  final goals = ['Muscle Gain', 'Weight Loss'];
  final sessions = [30, 45, 60, 90];
  final splits = ['Full Body Training', 'Push / Pull / Legs (PPL)'];
  final dayCounts = [3, 6];

  for (final goal in goals) {
    for (final session in sessions) {
      for (final split in splits) {
        for (final days in dayCounts) {
          final label = '$goal · ${session}min · $split · ${days}d';
          test('$label — fits duration & stays in NSCA ranges', () {
            final profile = _profile(
              goal: goal,
              sessionMinutes: session,
              split: split,
              days: days,
            );
            final plan = GreedyAlgorithm().generatePlan(
              allExercises: _catalog,
              profile: profile,
            );
            final nsca = _nsca(goal);
            final maxCount = days >= 5 ? 5 : 6;

            final trainingDays = plan.where((d) => !d.isRest).toList();
            expect(trainingDays.length, days,
                reason: '$label: should place exactly $days training days');

            for (final day in trainingDays) {
              expect(day.exercises, isNotEmpty,
                  reason: '$label/${day.dayName}: training day must not be empty');

              // (a) Never schedules OVER the chosen session length.
              var totalSets = 0;
              var workSum = 0;
              for (final we in day.exercises) {
                totalSets += we.sets;
                workSum += we.sets * we.timePerSetSeconds;
              }
              final rest = day.exercises.first.restSeconds;
              final estimate =
                  _warmupReserveSec + workSum + (totalSets - 1) * rest;
              expect(estimate, lessThanOrEqualTo(session * 60),
                  reason: '$label/${day.dayName}: estimate ${estimate}s '
                      'must not exceed ${session * 60}s');

              // (b) Exercise count bounded by split breadth / frequency.
              expect(day.exercises.length, lessThanOrEqualTo(maxCount),
                  reason: '$label/${day.dayName}: '
                      '${day.exercises.length} exercises exceeds cap $maxCount');

              // (b2) Focus integrity: every exercise trains the day's focus
              // (primary or secondary). Guards the "forearm curl on Leg day" bug
              // — late-week days are the trigger (high weekly-balance penalty).
              final focusMuscles = GreedyAlgorithm.musclesForFocus(day.focus);
              for (final we in day.exercises) {
                final onFocus = we.exercise.primaryMuscles.any(focusMuscles.contains) ||
                    we.exercise.secondaryMuscles.any(focusMuscles.contains);
                expect(onFocus, isTrue,
                    reason: '$label/${day.dayName} (${day.focus}): '
                        '"${we.exercise.name}" '
                        '${we.exercise.primaryMuscles} is off-focus');
              }

              // (c) Per-set loading inside the goal's NSCA range.
              for (final we in day.exercises) {
                expect(we.sets,
                    allOf(greaterThanOrEqualTo(nsca.setLo),
                        lessThanOrEqualTo(nsca.setHi)),
                    reason: '$label: ${we.sets} sets outside NSCA '
                        '${nsca.setLo}-${nsca.setHi}');
                expect(we.restSeconds,
                    allOf(greaterThanOrEqualTo(nsca.restLo),
                        lessThanOrEqualTo(nsca.restHi)),
                    reason: '$label: ${we.restSeconds}s rest outside NSCA '
                        '${nsca.restLo}-${nsca.restHi}');
                final bounds = _repBounds(we.reps);
                if (bounds.isNotEmpty) {
                  expect(bounds.first, greaterThanOrEqualTo(nsca.repLo),
                      reason: '$label: reps "${we.reps}" below NSCA min '
                          '${nsca.repLo}');
                  expect(bounds.last, lessThanOrEqualTo(nsca.repHi),
                      reason: '$label: reps "${we.reps}" above NSCA max '
                          '${nsca.repHi}');
                }
              }
            }
          });
        }
      }
    }
  }
}
