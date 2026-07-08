// Greedy Algorithm — Interactive Demo
// Run: dart run test/greedy_demo.dart

import 'dart:io';
import 'package:onefit/algorithms/greedy_algorithm.dart';
import 'package:onefit/models/exercise.dart';
import 'package:onefit/models/user_profile.dart';

class _C {
  final Exercise exercise;
  final double focus, goal, comp, diff, dayPen, wkPen, total;
  _C(this.exercise, this.focus, this.goal, this.comp, this.diff,
      this.dayPen, this.wkPen, this.total);
}

void main() {
  print('');
  print('GREEDY ALGORITHM — EXERCISE RECOMMENDATION DEMO');
  print('');

  final fitnessGoal = _menu('Fitness Goal', const [
    'Muscle Gain', 'Weight Loss', 'Endurance', 'General Fitness',
  ]);

  final level = _menu('Experience Level', const [
    'Beginner', 'Intermediate', 'Advanced',
  ]);

  final durationStr = _menu('Session duration (minutes)', const [
    '30', '45', '60', '90',
  ]);

  final split = _menu('Workout split', const [
    'Full Body Training',
    'Upper / Lower Split',
    'Push / Pull / Legs (PPL)',
    'Strength + Conditioning Split',
  ]);

  final profile = UserProfile(
    uid: 'demo',
    name: 'Demo User',
    gender: 'Male',
    age: 25,
    weight: 80.0,
    height: 178.0,
    fitnessGoal: fitnessGoal,
    experienceLevel: level,
    workoutLocation: 'Gym',
    equipment: [],
    dietaryRestrictions: [],
    workoutDaysPerWeek: 3,
    sessionMinutes: int.parse(durationStr),
    workoutSplit: split,
  );

  final pool = _buildPool();
  final ga = GreedyAlgorithm();

  // Call generatePlan once to read Day 1 metadata: focus, exercise count, NSCA params.
  // The actual pick-by-pick trace uses its own greedy replay (see below) so that
  // the selected exercise is always the table's top scorer — no display discrepancy.
  final plan = ga.generatePlan(allExercises: pool, profile: profile);
  final firstTraining = plan.firstWhere((d) => !d.isRest, orElse: () => plan.first);
  final exerciseCount = firstTraining.exercises.length;
  final dayFocus    = firstTraining.focus;
  final dayName     = firstTraining.dayName;
  final sampleSets  = firstTraining.exercises.isNotEmpty
      ? firstTraining.exercises.first.sets
      : ga.setsForDifficulty(profile, 'same');
  final sampleReps  = firstTraining.exercises.isNotEmpty
      ? firstTraining.exercises.first.reps : '?';
  final sampleRest  = firstTraining.exercises.isNotEmpty
      ? firstTraining.exercises.first.restSeconds : 60;

  // ── PROFILE ─────────────────────────────────────────────────────────────────

  print('');
  print('=== PROFILE ===');
  print('Fitness Goal    : $fitnessGoal');
  print('Experience      : $level');
  print('Session Duration: $durationStr minutes');
  print('Workout Split   : $split');
  print('Location        : Gym (all equipment available)');

  print('');
  print('=== NSCA PRESCRIPTION ($fitnessGoal) ===');
  print('Sets: $sampleSets per exercise');
  print('Reps: $sampleReps');
  print('Rest: ${sampleRest}s between sets');

  print('');
  print('=== SCORING WEIGHTS ===');
  print('+50  focus match    — primary muscle targets the day focus');
  print('+15  goal tag       — exercise tagged for "${_gk(fitnessGoal)}"');
  print('+12  compound bonus — multi-joint lift');
  print('+10  difficulty     — exercise.difficulty == "${level.toLowerCase()}"');
  print('-25  day penalty    — per primary muscle already used this session');
  print('-15  weekly penalty — per primary muscle used earlier this week');

  // ── GREEDY REPLAY — DAY 1 ONLY ──────────────────────────────────────────────
  // We implement the greedy pick loop ourselves so the score table is always
  // self-consistent: the marked exercise is always rank 1. This avoids the
  // discrepancy that comes from reading day.exercises in its post-sort order
  // (the algorithm sorts exercises by compound tier after selection, which
  // does not match the greedy pick order).

  final targets = GreedyAlgorithm.musclesForFocus(dayFocus);

  final primaryPool = pool
      .where((e) =>
          GreedyAlgorithm.isEligibleForUser(e, profile) &&
          GreedyAlgorithm.difficultyAllowed(e.difficulty, level) &&
          e.primaryMuscles.any(targets.contains))
      .toList();

  final selectedIds = <String>{};
  final dayHits     = <String, int>{};
  final weeklyHits  = <String, int>{}; // Day 1 — no prior days
  final picked      = <_C>[];

  print('');
  print('=== DAY 1 — ${dayName.toUpperCase()} — ${dayFocus.toUpperCase()} ===');
  print('Target muscles: ${targets.join(', ')}');
  print('Exercises: $exerciseCount selected');

  for (int pick = 0; pick < exerciseCount; pick++) {
    final remaining = primaryPool.where((e) => !selectedIds.contains(e.id)).toList();

    final scored = remaining.map((ex) {
      final f  = ex.primaryMuscles.any(targets.contains) ? 50.0 : 0.0;
      final g  = ex.goals.contains(_gk(fitnessGoal)) ? 15.0 : 0.0;
      final c  = GreedyAlgorithm.isStapleCompound(ex) ? 12.0 : 0.0;
      final d  = ex.difficulty == level.toLowerCase() ? 10.0 : 0.0;
      final dp = ex.primaryMuscles.fold(0.0, (s, m) => s + (dayHits[m]  ?? 0) * 25.0);
      final wp = ex.primaryMuscles.fold(0.0, (s, m) => s + (weeklyHits[m] ?? 0) * 15.0);
      // Use the public scoreExercise wrapper for the verified total
      final total = ga.scoreExercise(
        exercise: ex, profile: profile,
        targetMuscles: targets, weeklyHits: weeklyHits, dayHits: dayHits,
      );
      return _C(ex, f, g, c, d, dp, wp, total);
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    // Winner is always the top scorer — no discrepancy possible
    final winner = scored.first;

    final hStr = dayHits.isEmpty
        ? 'none'
        : dayHits.entries.map((e) => '${e.key} x${e.value}').join(', ');

    print('');
    print('Pick ${pick + 1}  (session so far: $hStr)');
    print('');
    print('  Rank  Exercise                    Focus  Goal  Cpnd  Diff  -Day  -Week  Score');
    print('  ----  --------------------------  -----  ----  ----  ----  ----  -----  -----');

    for (int ri = 0; ri < scored.length; ri++) {
      final c   = scored[ri];
      final tag = c.exercise.id == winner.exercise.id ? '  <-- SELECTED' : '';
      final nm  = c.exercise.name.length > 26
          ? c.exercise.name.substring(0, 25) + '.'
          : c.exercise.name.padRight(26);
      final dpStr = c.dayPen > 0 ? '-${c.dayPen.toInt()}'.padLeft(4) : '   0';
      final wpStr = c.wkPen  > 0 ? '-${c.wkPen.toInt()}'.padLeft(5)  : '    0';
      print('  ${(ri + 1).toString().padLeft(4)}  $nm  '
          '${_pts(c.focus)}  ${_pts(c.goal)}  ${_pts(c.comp)}  ${_pts(c.diff)}'
          '  $dpStr  $wpStr  '
          '${c.total.toStringAsFixed(1).padLeft(5)}$tag');
    }

    final reasons = <String>[];
    if (winner.focus > 0)  reasons.add('focus +50');
    if (winner.goal  > 0)  reasons.add('goal +15');
    if (winner.comp  > 0)  reasons.add('compound +12');
    if (winner.diff  > 0)  reasons.add('tier match +10');
    if (winner.dayPen > 0) reasons.add('day penalty -${winner.dayPen.toInt()}');

    print('');
    print('  Selected: ${winner.exercise.name} — ${winner.total.toStringAsFixed(1)} pts'
        '  (${reasons.join(', ')})');

    selectedIds.add(winner.exercise.id);
    for (final m in winner.exercise.primaryMuscles) {
      dayHits[m] = (dayHits[m] ?? 0) + 1;
    }
    picked.add(winner);
  }

  // ── FINAL PLAN ──────────────────────────────────────────────────────────────

  print('');
  print('=== DAY 1 FINAL PLAN ===');
  for (int i = 0; i < picked.length; i++) {
    print('  ${i + 1}. ${picked[i].exercise.name.padRight(30)}'
        '  $sampleSets x $sampleReps  @  ${sampleRest}s rest');
  }
  print('');
}

// ── EXERCISE POOL ─────────────────────────────────────────────────────────────

List<Exercise> _buildPool() => [
      _ex(id: 'bench_press_bb', name: 'Barbell Bench Press',
          category: 'strength', primary: ['pectorals'],
          secondary: ['triceps', 'delts'], equipment: ['barbell'],
          difficulty: 'intermediate', goals: ['muscle_gain']),
      _ex(id: 'shoulder_press_db', name: 'Dumbbell Shoulder Press',
          category: 'strength', primary: ['delts'],
          secondary: ['triceps'], equipment: ['dumbbells'],
          difficulty: 'beginner', goals: ['muscle_gain']),
      _ex(id: 'incline_press_db', name: 'Incline Dumbbell Press',
          category: 'strength', primary: ['pectorals'],
          secondary: ['triceps', 'delts'], equipment: ['dumbbells'],
          difficulty: 'intermediate', goals: ['muscle_gain']),
      _ex(id: 'row_bb', name: 'Barbell Row',
          category: 'strength', primary: ['lats'],
          secondary: ['upper back', 'biceps'], equipment: ['barbell'],
          difficulty: 'intermediate', goals: ['muscle_gain']),
      _ex(id: 'overhead_press_bb', name: 'Overhead Press',
          category: 'strength', primary: ['delts'],
          secondary: ['triceps', 'upper back'], equipment: ['barbell'],
          difficulty: 'intermediate', goals: ['muscle_gain']),
      _ex(id: 'lat_pulldown', name: 'Lat Pulldown',
          category: 'strength', primary: ['lats'],
          secondary: ['biceps', 'upper back'], equipment: ['cable'],
          difficulty: 'beginner', goals: ['muscle_gain']),
      _ex(id: 'cable_row', name: 'Seated Cable Row',
          category: 'strength', primary: ['lats'],
          secondary: ['upper back', 'biceps'], equipment: ['cable'],
          difficulty: 'beginner', goals: ['muscle_gain']),
      _ex(id: 'pull_up', name: 'Pull-Up',
          category: 'strength', primary: ['lats'],
          secondary: ['biceps', 'upper back'], equipment: ['body weight'],
          difficulty: 'intermediate', goals: ['muscle_gain']),
      _ex(id: 'chest_fly_cable', name: 'Cable Chest Fly',
          category: 'strength', primary: ['pectorals'],
          secondary: ['biceps'], equipment: ['cable'],
          difficulty: 'beginner', goals: ['muscle_gain', 'general']),
      _ex(id: 'tricep_pushdown', name: 'Tricep Pushdown',
          category: 'strength', primary: ['triceps'],
          secondary: [], equipment: ['cable'],
          difficulty: 'beginner', goals: ['weight_loss', 'general']),
      _ex(id: 'lateral_raise', name: 'Lateral Raise',
          category: 'strength', primary: ['delts'],
          secondary: [], equipment: ['dumbbells'],
          difficulty: 'beginner', goals: ['weight_loss']),
      _ex(id: 'face_pull', name: 'Face Pull',
          category: 'strength', primary: ['upper back'],
          secondary: ['delts'], equipment: ['cable'],
          difficulty: 'beginner', goals: ['general']),
      _ex(id: 'dumbbell_curl', name: 'Dumbbell Curl',
          category: 'strength', primary: ['biceps'],
          secondary: ['forearms'], equipment: ['dumbbells'],
          difficulty: 'beginner', goals: ['muscle_gain']),
      _ex(id: 'hammer_curl', name: 'Hammer Curl',
          category: 'strength', primary: ['biceps'],
          secondary: [], equipment: ['dumbbells'],
          difficulty: 'beginner', goals: ['general']),
      _ex(id: 'push_up', name: 'Push-Up',
          category: 'strength', primary: ['pectorals'],
          secondary: ['triceps', 'delts'], equipment: ['body weight'],
          difficulty: 'beginner', goals: ['general', 'weight_loss']),
      _ex(id: 'tricep_overhead_ext', name: 'Overhead Tricep Extension',
          category: 'strength', primary: ['triceps'],
          secondary: [], equipment: ['dumbbells'],
          difficulty: 'beginner', goals: ['muscle_gain']),
      _ex(id: 'squat_bb', name: 'Barbell Back Squat',
          category: 'strength', primary: ['quads'],
          secondary: ['glutes', 'hamstrings'], equipment: ['barbell'],
          difficulty: 'intermediate', goals: ['muscle_gain']),
      _ex(id: 'rdl_bb', name: 'Romanian Deadlift',
          category: 'strength', primary: ['hamstrings'],
          secondary: ['glutes', 'lats'], equipment: ['barbell'],
          difficulty: 'intermediate', goals: ['muscle_gain']),
      _ex(id: 'lunge_db', name: 'Dumbbell Lunge',
          category: 'strength', primary: ['quads'],
          secondary: ['glutes', 'hamstrings'], equipment: ['dumbbells'],
          difficulty: 'beginner', goals: ['weight_loss', 'general']),
      _ex(id: 'hip_thrust_bb', name: 'Hip Thrust',
          category: 'strength', primary: ['glutes'],
          secondary: ['hamstrings'], equipment: ['barbell'],
          difficulty: 'intermediate', goals: ['muscle_gain']),
      _ex(id: 'leg_press', name: 'Leg Press',
          category: 'strength', primary: ['quads'],
          secondary: ['glutes', 'hamstrings'], equipment: ['leverage machine'],
          difficulty: 'beginner', goals: ['muscle_gain', 'general']),
      _ex(id: 'leg_curl', name: 'Leg Curl',
          category: 'strength', primary: ['hamstrings'],
          secondary: [], equipment: ['leverage machine'],
          difficulty: 'beginner', goals: ['general']),
      _ex(id: 'calf_raise', name: 'Calf Raise',
          category: 'strength', primary: ['calves'],
          secondary: [], equipment: ['leverage machine'],
          difficulty: 'beginner', goals: ['general']),
      _ex(id: 'deadlift_bb', name: 'Deadlift',
          category: 'strength', primary: ['hamstrings'],
          secondary: ['glutes', 'lats', 'upper back'], equipment: ['barbell'],
          difficulty: 'intermediate', goals: ['muscle_gain']),
      _ex(id: 'plank', name: 'Plank',
          category: 'strength', primary: ['abs'],
          secondary: ['spine'], equipment: ['body weight'],
          difficulty: 'beginner', goals: ['general', 'weight_loss']),
      _ex(id: 'burpee', name: 'Burpee',
          category: 'cardio', primary: ['cardiovascular system'],
          secondary: ['quads', 'abs'], equipment: ['body weight'],
          difficulty: 'intermediate', goals: ['endurance', 'weight_loss']),
    ];

Exercise _ex({
  required String id, required String name, required String category,
  required List<String> primary, required List<String> secondary,
  required List<String> equipment, required String difficulty,
  required List<String> goals,
}) =>
    Exercise(
      id: id, name: name, category: category,
      primaryMuscles: primary, secondaryMuscles: secondary,
      equipment: equipment, difficulty: difficulty,
      goals: goals, locations: ['gym'], instructions: '',
    );

String _gk(String g) => switch (g) {
      'Muscle Gain' => 'muscle_gain',
      'Weight Loss' => 'weight_loss',
      'Endurance'   => 'endurance',
      _             => 'general',
    };

String _pts(double v) => v > 0 ? '+${v.toInt()}'.padLeft(4) : '   0';

String _menu(String prompt, List<String> options) {
  print('');
  print('$prompt:');
  for (int i = 0; i < options.length; i++) {
    print('  ${i + 1}. ${options[i]}');
  }
  while (true) {
    stdout.write('Enter choice (1-${options.length}): ');
    final line = stdin.readLineSync()?.trim() ?? '';
    final n = int.tryParse(line);
    if (n != null && n >= 1 && n <= options.length) return options[n - 1];
    print('Invalid — enter a number between 1 and ${options.length}');
  }
}
