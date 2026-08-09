// Golden / characterization test for the profile-driven greedy scoring.
//
// Two things are proved here:
//  1. "NOT WORSE" — invariants that must hold for EVERY profile in a sampling
//     matrix that spans every input axis (goal x level x location x split x
//     time x limitation). These are properties of the UNCHANGED hard filters,
//     schedule, and count logic, so they hold by construction; the matrix just
//     confirms it empirically. If any breaks, the personalised scoring leaked
//     an unsafe/ineligible exercise, dropped a training day, or emptied a day.
//  2. "BETTER / PERSONALISED" — deterministic unit assertions on scoreExercise
//     proving the ranking actually responds to Fitness Goal, Experience Level,
//     and Time Per Session (the whole point of the change).
//
// Run: flutter test test/greedy_scoring_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/greedy_algorithm.dart';
import 'package:onefit/data/physical_limitations.dart';
import 'package:onefit/models/exercise.dart';
import 'package:onefit/models/user_profile.dart';

Exercise _ex({
  required String id,
  required String name,
  required List<String> primaryMuscles,
  List<String> secondaryMuscles = const [],
  List<String> equipment = const ['barbell'],
  List<String> locations = const ['home', 'gym'],
  String difficulty = 'beginner',
  List<String> goals = const [],
  String category = 'strength',
}) => Exercise(
  id: id,
  name: name,
  category: category,
  primaryMuscles: primaryMuscles,
  secondaryMuscles: secondaryMuscles,
  equipment: equipment,
  difficulty: difficulty,
  goals: goals,
  locations: locations,
  instructions: '',
);

UserProfile _profile({
  String goal = 'Muscle Gain',
  String level = 'Intermediate',
  String location = 'Gym',
  List<String> equipment = const [],
  String split = 'Full Body Training',
  int sessionMinutes = 45,
  int days = 3,
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
  equipment: equipment,
  dietaryRestrictions: const ['Balanced'],
  workoutSplit: split,
  sessionMinutes: sessionMinutes,
  workoutDaysPerWeek: days,
  physicalLimitations: limitations,
);

// A representative synthetic catalog covering every default focus muscle
// (pectorals, lats, quads, glutes, abs, delts) plus arms/hamstrings, mixing
// compound/isolation, difficulties, goal tags, and bodyweight/loaded so home
// and gym profiles both fill. Includes moves that SHOULD be blocked by each
// limitation so exclusion is meaningfully tested.
final List<Exercise> _catalog = [
  // Compound, loaded, gym+home.
  _ex(id: 'bench', name: 'Barbell Bench Press', primaryMuscles: ['pectorals'],
      secondaryMuscles: ['triceps', 'delts'], difficulty: 'intermediate',
      goals: ['muscle_gain', 'general']),
  _ex(id: 'row', name: 'Barbell Row', primaryMuscles: ['lats'],
      secondaryMuscles: ['biceps', 'upper back'], difficulty: 'intermediate',
      goals: ['muscle_gain', 'general']),
  _ex(id: 'squat', name: 'Barbell Back Squat', primaryMuscles: ['quads'],
      secondaryMuscles: ['glutes', 'hamstrings'], difficulty: 'intermediate',
      goals: ['muscle_gain', 'general'], equipment: ['barbell']),
  _ex(id: 'hipthrust', name: 'Barbell Hip Thrust', primaryMuscles: ['glutes'],
      secondaryMuscles: ['hamstrings', 'quads'], goals: ['muscle_gain']),
  _ex(id: 'ohp', name: 'Standing Dumbbell Press', primaryMuscles: ['delts'],
      secondaryMuscles: ['triceps'], difficulty: 'intermediate',
      goals: ['muscle_gain'], equipment: ['dumbbell']),
  _ex(id: 'lunge', name: 'Dumbbell Lunge', primaryMuscles: ['quads'],
      secondaryMuscles: ['glutes', 'hamstrings'], goals: ['general'],
      equipment: ['dumbbell']),

  // Isolation, loaded.
  _ex(id: 'curl', name: 'Dumbbell Biceps Curl', primaryMuscles: ['biceps'],
      goals: ['muscle_gain'], equipment: ['dumbbell']),
  _ex(id: 'pushdown', name: 'Cable Triceps Pushdown', primaryMuscles: ['triceps'],
      goals: ['general'], equipment: ['cable'], locations: ['gym']),
  _ex(id: 'latraise', name: 'Dumbbell Lateral Raise', primaryMuscles: ['delts'],
      goals: ['endurance'], equipment: ['dumbbell']),
  _ex(id: 'legext', name: 'Leg Extension', primaryMuscles: ['quads'],
      goals: ['endurance'], equipment: ['machine'], locations: ['gym']),
  _ex(id: 'pecdeck', name: 'Cable Chest Fly', primaryMuscles: ['pectorals'],
      goals: ['endurance'], equipment: ['cable'], locations: ['gym']),
  _ex(id: 'pulldown', name: 'Lat Pulldown', primaryMuscles: ['lats'],
      goals: ['general'], equipment: ['machine'], locations: ['gym']),

  // Bodyweight, home+gym, covering all default focus muscles so a
  // bodyweight-only home user still fills a Full Body day.
  _ex(id: 'pushup', name: 'Push-up', primaryMuscles: ['pectorals'],
      secondaryMuscles: ['triceps'], goals: ['general', 'endurance'],
      equipment: ['bodyweight'], category: 'strength'),
  _ex(id: 'invrow', name: 'Inverted Row', primaryMuscles: ['lats'],
      secondaryMuscles: ['biceps'], goals: ['general'],
      equipment: ['bodyweight']),
  _ex(id: 'bwsquat', name: 'Bodyweight Squat', primaryMuscles: ['quads'],
      secondaryMuscles: ['glutes'], goals: ['general', 'endurance'],
      equipment: ['bodyweight']),
  _ex(id: 'glutebridge', name: 'Glute Bridge', primaryMuscles: ['glutes'],
      secondaryMuscles: ['hamstrings'], goals: ['general'],
      equipment: ['bodyweight']),
  _ex(id: 'crunch', name: 'Crunch', primaryMuscles: ['abs'],
      goals: ['endurance'], equipment: ['bodyweight']),
  _ex(id: 'pikepush', name: 'Pike Push-up', primaryMuscles: ['delts'],
      secondaryMuscles: ['triceps'], difficulty: 'intermediate',
      goals: ['general'], equipment: ['bodyweight']),
  _ex(id: 'hollow', name: 'Hollow Hold', primaryMuscles: ['abs'],
      goals: ['endurance'], equipment: ['bodyweight']),

  // Advanced-difficulty moves (only Advanced users can be scored/selected).
  _ex(id: 'pistol', name: 'Pistol Squat', primaryMuscles: ['quads'],
      secondaryMuscles: ['glutes'], difficulty: 'advanced',
      goals: ['general'], equipment: ['bodyweight']),

  // Moves that must be BLOCKED by specific limitations.
  _ex(id: 'deadlift', name: 'Barbell Deadlift', primaryMuscles: ['hamstrings'],
      secondaryMuscles: ['glutes', 'lats'], difficulty: 'intermediate',
      goals: ['muscle_gain'], category: 'legs'), // lower-back
  _ex(id: 'overheadpress', name: 'Barbell Overhead Press',
      primaryMuscles: ['delts'], secondaryMuscles: ['triceps'],
      difficulty: 'intermediate', goals: ['muscle_gain'],
      category: 'shoulders'), // shoulder
  _ex(id: 'burpee', name: 'Burpee', primaryMuscles: ['quads'],
      secondaryMuscles: ['pectorals'], goals: ['endurance'],
      equipment: ['bodyweight'], category: 'cardio'), // asthma + knee
  _ex(id: 'jumpsquat', name: 'Jump Squat', primaryMuscles: ['quads'],
      secondaryMuscles: ['glutes'], goals: ['endurance'],
      equipment: ['bodyweight'], category: 'plyometrics'), // knee
  _ex(id: 'plank', name: 'Plank', primaryMuscles: ['abs'],
      goals: ['endurance'], equipment: ['bodyweight'],
      category: 'core'), // high blood pressure
];

void main() {
  final ga = GreedyAlgorithm();

  group('INVARIANTS across the input matrix (the "not worse" proof)', () {
    // Build a matrix that hits every value on every axis at least once.
    final profiles = <UserProfile>[
      // 4 goals x 3 levels.
      for (final goal in const [
        'Weight Loss',
        'Muscle Gain',
        'Endurance',
        'General Fitness',
      ])
        for (final level in const ['Beginner', 'Intermediate', 'Advanced'])
          _profile(goal: goal, level: level),
      // Each physical limitation at least once (Gym, so only the ban filters).
      for (final lim in kPhysicalLimitations)
        _profile(limitations: [lim.id]),
      // Locations / equipment.
      _profile(location: 'Home', equipment: const ['Bodyweight']),
      _profile(
        location: 'Home',
        equipment: const ['Bodyweight', 'Dumbbells', 'Barbell', 'Bench'],
      ),
      // Session-length extremes.
      _profile(sessionMinutes: 30),
      _profile(sessionMinutes: 90),
      // Every split.
      for (final split in const [
        'Full Body Training',
        'Upper / Lower Split',
        'Push / Pull / Legs (PPL)',
        'Functional Training Split',
        'Strength + Conditioning Split',
      ])
        _profile(split: split, days: 4),
    ];

    for (final p in profiles) {
      final label =
          '${p.fitnessGoal}/${p.experienceLevel}/${p.workoutLocation}/'
          '${p.workoutSplit}/${p.sessionMinutes}m/'
          'lim=${p.physicalLimitations.join("+")}';

      test('[$label] output is safe and structurally intact', () {
        final plan = ga.generatePlan(allExercises: _catalog, profile: p);
        final trainingDays = plan.where((d) => !d.isRest).toList();

        // Exactly workoutDaysPerWeek training days — adaptation/scoring never
        // add or remove training days.
        expect(
          trainingDays.length,
          p.workoutDaysPerWeek,
          reason: 'training-day count must equal workoutDaysPerWeek',
        );

        for (final day in trainingDays) {
          // No empty training day.
          expect(day.exercises, isNotEmpty,
              reason: 'a training day must never be empty');
          // Never more than the documented cap of 6.
          expect(day.exercises.length, lessThanOrEqualTo(6));

          for (final we in day.exercises) {
            final e = we.exercise;
            // Every selected exercise is genuinely usable by this user.
            expect(
              GreedyAlgorithm.isEligibleForUser(e, p),
              isTrue,
              reason: '${e.name} must pass isEligibleForUser',
            );
            expect(
              GreedyAlgorithm.difficultyAllowed(e.difficulty, p.experienceLevel),
              isTrue,
              reason: '${e.name} must pass the experience gate',
            );
            // Never a limitation-contraindicated move.
            expect(
              exerciseBlockedByLimitations(
                e,
                p.physicalLimitations,
                p.avoidedMovements,
              ),
              isFalse,
              reason: '${e.name} is contraindicated for ${p.physicalLimitations}',
            );
          }
        }
      });
    }

    test('knee-injury plan never contains jump/plyo moves', () {
      final plan = ga.generatePlan(
        allExercises: _catalog,
        profile: _profile(
          goal: 'Weight Loss',
          level: 'Beginner',
          limitations: const ['Knee injury/pain'],
          sessionMinutes: 30,
        ),
      );
      final names = [
        for (final d in plan.where((d) => !d.isRest))
          for (final we in d.exercises) we.exercise.name.toLowerCase(),
      ];
      expect(names.any((n) => n.contains('jump')), isFalse);
      expect(names.any((n) => n.contains('burpee')), isFalse);
      expect(names.any((n) => n.contains('pistol')), isFalse);
    });
  });

  group('SCORING is profile-driven (the "better / personalised" proof)', () {
    // Isolate the profile block: empty targetMuscles => no focus bonus, empty
    // hit maps => no balance penalty. So score == the clamped Goal+Exp+Time
    // block, and cross-profile deltas reflect ONLY the profile inputs.
    double s(Exercise e, UserProfile p) => ga.scoreExercise(
          exercise: e,
          profile: p,
          targetMuscles: const [],
          weeklyHits: const {},
          dayHits: const {},
        );

    final heavyCompound = _ex(
      id: 'hc', name: 'Barbell Squat', primaryMuscles: ['quads'],
      secondaryMuscles: ['glutes', 'hamstrings'], difficulty: 'intermediate',
      goals: ['muscle_gain'],
    );
    final highRepIso = _ex(
      id: 'hr', name: 'Cable Lateral Raise', primaryMuscles: ['delts'],
      goals: ['endurance'], equipment: ['cable'],
    );

    test('Endurance ranks a high-rep isolation higher (vs a heavy compound) '
        'than Muscle Gain does', () {
      final endur = _profile(goal: 'Endurance', level: 'Beginner');
      final gain = _profile(goal: 'Muscle Gain', level: 'Beginner');
      final endurDelta = s(highRepIso, endur) - s(heavyCompound, endur);
      final gainDelta = s(highRepIso, gain) - s(heavyCompound, gain);
      expect(endurDelta, greaterThan(gainDelta),
          reason: 'the goal must change relative ranking');
    });

    test('Muscle Gain scores a heavy compound higher than Endurance does', () {
      final gain = _profile(goal: 'Muscle Gain', level: 'Intermediate');
      final endur = _profile(goal: 'Endurance', level: 'Intermediate');
      expect(s(heavyCompound, gain), greaterThan(s(heavyCompound, endur)));
    });

    test('session length does NOT affect ranking (only exercise count)', () {
      // sessionMinutes drives the per-day exercise COUNT (_fitExerciseCount),
      // never the score — so the user's Exercise Priority is never overridden by
      // choosing a short session. A 30-min and a 90-min profile must score the
      // same exercise identically.
      final short = _profile(sessionMinutes: 30, level: 'Beginner');
      final long = _profile(sessionMinutes: 90, level: 'Beginner');
      expect(s(highRepIso, short), s(highRepIso, long),
          reason: 'time-per-session must not change ranking');
      expect(s(heavyCompound, short), s(heavyCompound, long),
          reason: 'time-per-session must not change ranking');
    });

    test('Advanced user ranks an advanced-difficulty move above a beginner one',
        () {
      final adv = _profile(goal: 'General Fitness', level: 'Advanced');
      // Identical isolation moves differing ONLY in difficulty, so the delta
      // isolates the graduated experience weight (advanced +10 vs beginner +2).
      final advMove = _ex(
        id: 'am', name: 'Single-Arm Cable Raise', primaryMuscles: ['delts'],
        difficulty: 'advanced', equipment: ['cable'], locations: ['gym'],
      );
      final begMove = _ex(
        id: 'bm', name: 'Cable Raise', primaryMuscles: ['delts'],
        difficulty: 'beginner', equipment: ['cable'], locations: ['gym'],
      );
      expect(s(advMove, adv), greaterThan(s(begMove, adv)),
          reason: 'graduated experience score must reward the harder move '
              'for an Advanced user');
    });

    test('user goalPriorities ranking changes the score', () {
      // Same isolation exercise, same profile — only the feature ranking differs.
      // Ranking "isolation" #1 (12 pts) must score strictly higher than ranking
      // it last (2 pts).
      final iso = _ex(
        id: 'iso', name: 'Cable Curl', primaryMuscles: ['biceps'],
        goals: const [], equipment: ['cable'], locations: ['gym'],
      );
      final isoFirst = _profile(goal: 'Muscle Gain', level: 'Beginner')
          .copyWith(goalPriorities: const [
        'isolation',
        'compound',
        'heavyLift',
        'fullBody',
        'highRep',
      ]);
      final isoLast = _profile(goal: 'Muscle Gain', level: 'Beginner')
          .copyWith(goalPriorities: const [
        'compound',
        'heavyLift',
        'fullBody',
        'highRep',
        'isolation',
      ]);
      expect(s(iso, isoFirst), greaterThan(s(iso, isoLast)),
          reason: 'ranking a feature higher must raise the score of exercises '
              'with that feature');
    });

    test('empty goalPriorities reproduces the goal default ordering', () {
      // With no custom ranking, defaultGoalPriorities is used — so an explicit
      // default-order list scores identically to an empty one.
      final e = heavyCompound;
      final empty = _profile(goal: 'Weight Loss', level: 'Beginner');
      final explicitDefault = empty.copyWith(
        goalPriorities: GreedyAlgorithm.defaultGoalPriorities('Weight Loss'),
      );
      expect(s(e, empty), s(e, explicitDefault));
    });

    test('profile block never overpowers a single balance penalty (clamp)', () {
      // A maximally attractive exercise still loses to a fresh-muscle pick once
      // it has one day-hit: +45 clamp - 25 = 20 < a fresh +45. This is what
      // preserves within-session variety.
      final maxAttractive = _ex(
        id: 'max', name: 'Barbell Deadlift Variation',
        primaryMuscles: ['quads'],
        secondaryMuscles: ['glutes', 'hamstrings', 'lats'],
        goals: ['muscle_gain'], difficulty: 'beginner',
      );
      final p = _profile(goal: 'Muscle Gain', level: 'Advanced');
      final fresh = ga.scoreExercise(
        exercise: maxAttractive, profile: p, targetMuscles: const [],
        weeklyHits: const {}, dayHits: const {},
      );
      final repeated = ga.scoreExercise(
        exercise: maxAttractive, profile: p, targetMuscles: const [],
        weeklyHits: const {}, dayHits: const {'quads': 1},
      );
      expect(fresh - repeated, closeTo(25, 0.001),
          reason: 'one day-hit costs a fixed -25 regardless of attractiveness');
    });
  });

  group('explainSelection (why-this-exercise reasons)', () {
    final compoundGoalMatch = _ex(
      id: 'sq', name: 'Barbell Squat', primaryMuscles: ['quads'],
      secondaryMuscles: ['glutes', 'hamstrings'], difficulty: 'beginner',
      goals: ['muscle_gain'],
    );

    test('lists the goal match and the top-ranked feature priority', () {
      final p = _profile(goal: 'Muscle Gain', level: 'Beginner').copyWith(
        goalPriorities: const [
          'compound',
          'heavyLift',
          'fullBody',
          'highRep',
          'isolation',
        ],
      );
      final reasons =
          GreedyAlgorithm.explainSelection(compoundGoalMatch, p, 'Legs');
      expect(reasons, isNotEmpty);
      expect(reasons.any((r) => r.contains('Muscle Gain goal')), isTrue);
      expect(reasons.any((r) => r.contains('Compound') && r.contains('#1')),
          isTrue,
          reason: 'compound ranked #1 must be stated as the #1 priority');
    });

    test('re-ranking a feature changes its stated rank/points', () {
      final low = _profile(goal: 'Muscle Gain', level: 'Beginner').copyWith(
        goalPriorities: const [
          'isolation',
          'heavyLift',
          'fullBody',
          'highRep',
          'compound',
        ],
      );
      final reasons =
          GreedyAlgorithm.explainSelection(compoundGoalMatch, low, 'Legs');
      expect(reasons.any((r) => r.contains('Compound') && r.contains('#5')),
          isTrue,
          reason: 'compound ranked last must be stated as the #5 priority');
    });
  });
}
