// Greedy Algorithm — Interactive Demo
// Run: dart run test/greedy_demo.dart

import 'dart:convert';
import 'dart:io';
import 'package:onefit/algorithms/greedy_algorithm.dart';
import 'package:onefit/models/exercise.dart';
import 'package:onefit/models/user_profile.dart';
import 'package:onefit/services/difficulty_inference.dart';

class _C {
  final Exercise exercise;
  final double focus, goal, comp, heavy, diff, dayPen, wkPen, total;
  _C(this.exercise, this.focus, this.goal, this.comp, this.heavy, this.diff,
      this.dayPen, this.wkPen, this.total);
}

Future<void> main() async {
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

  final location = _menu('Workout location', const ['Gym', 'Home']);

  stderr.write('Fetching exercises from ExerciseDB');
  final pool = await _fetchExercises();
  stderr.writeln(' — ${pool.length} exercises loaded.');

  final profile = UserProfile(
    uid: 'demo',
    name: 'Demo User',
    gender: 'Male',
    age: 25,
    weight: 80.0,
    height: 178.0,
    fitnessGoal: fitnessGoal,
    experienceLevel: level,
    workoutLocation: location,
    equipment: location == 'Home' ? ['Bodyweight'] : [],
    dietaryRestrictions: [],
    workoutDaysPerWeek: 3,
    sessionMinutes: int.parse(durationStr),
    workoutSplit: split,
  );

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
  print('Location        : $location'
      '${location == 'Gym' ? ' (all equipment available)' : ' (bodyweight only)'}');

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
  print('+8   heavy compound — foundational barbell/dumbbell lift (opens session)');
  print('+10  compatibility  — exercise.difficulty <= "${level.toLowerCase()}"');
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
      final h  = GreedyAlgorithm.isHeavyCompound(ex) ? 8.0 : 0.0;
      final d  = GreedyAlgorithm.difficultyAllowed(ex.difficulty, level) ? 10.0 : 0.0;
      final dp = ex.primaryMuscles.fold(0.0, (s, m) => s + (dayHits[m]  ?? 0) * 25.0);
      final wp = ex.primaryMuscles.fold(0.0, (s, m) => s + (weeklyHits[m] ?? 0) * 15.0);
      // Use the public scoreExercise wrapper for the verified total
      final total = ga.scoreExercise(
        exercise: ex, profile: profile,
        targetMuscles: targets, weeklyHits: weeklyHits, dayHits: dayHits,
      );
      return _C(ex, f, g, c, h, d, dp, wp, total);
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
    print('  Rank  Exercise                    Focus  Goal  Cpnd  Hvy  Comp  -Day  -Week  Score');
    print('  ----  --------------------------  -----  ----  ----  ---  ----  ----  -----  -----');

    for (int ri = 0; ri < scored.length; ri++) {
      final c   = scored[ri];
      final tag = c.exercise.id == winner.exercise.id ? '  <-- SELECTED' : '';
      final nm  = c.exercise.name.length > 26
          ? c.exercise.name.substring(0, 25) + '.'
          : c.exercise.name.padRight(26);
      final hvStr = c.heavy > 0 ? '+${c.heavy.toInt()}'.padLeft(3) : '  0';
      final dpStr = c.dayPen > 0 ? '-${c.dayPen.toInt()}'.padLeft(4) : '   0';
      final wpStr = c.wkPen  > 0 ? '-${c.wkPen.toInt()}'.padLeft(5)  : '    0';
      print('  ${(ri + 1).toString().padLeft(4)}  $nm  '
          '${_pts(c.focus)}  ${_pts(c.goal)}  ${_pts(c.comp)}  $hvStr  ${_pts(c.diff)}'
          '  $dpStr  $wpStr  '
          '${c.total.toStringAsFixed(1).padLeft(5)}$tag');
    }

    final reasons = <String>[];
    if (winner.focus > 0)  reasons.add('focus +50');
    if (winner.goal  > 0)  reasons.add('goal +15');
    if (winner.comp  > 0)  reasons.add('compound +12');
    if (winner.heavy > 0)  reasons.add('heavy compound +8');
    if (winner.diff  > 0)  reasons.add('compatible +10');
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
  for (int i = 0; i < firstTraining.exercises.length; i++) {
    final e = firstTraining.exercises[i];
    print('  ${i + 1}. ${e.exercise.name.padRight(30)}'
        '  ${e.sets} x ${e.reps}  @  ${e.restSeconds}s rest');
  }
  print('');
}

// ── ExerciseDB fetch ──────────────────────────────────────────────────────────

const _apiBase = 'https://oss.exercisedb.dev/api/v1';

Future<List<Exercise>> _fetchExercises() async {
  const maxPages = 100;
  final exercises = <Exercise>[];
  String? cursor;
  final client = HttpClient();

  try {
    int retries = 0;
    for (int page = 0; page < maxPages; page++) {
      final query = cursor == null ? '' : '?after=$cursor';
      final uri = Uri.parse('$_apiBase/exercises$query');
      final req = await client.getUrl(uri);
      req.headers.set('Content-Type', 'application/json');
      final resp = await req.close().timeout(const Duration(seconds: 30));

      if (resp.statusCode == 429 && retries < 4) {
        retries++;
        page--;
        await Future.delayed(Duration(milliseconds: 1500 * retries));
        continue;
      }
      if (resp.statusCode != 200) break;
      retries = 0;

      final body = await resp.transform(const Utf8Decoder()).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final rawList = json['data'] as List? ?? [];
      exercises.addAll(
        rawList
            .cast<Map<String, dynamic>>()
            .map(_mapToExercise)
            .where((e) => !_isLikelyAutoGenerated(e.name)),
      );

      final meta = json['meta'] as Map<String, dynamic>? ?? {};
      final hasNext = meta['hasNextPage'] == true;
      cursor = meta['nextCursor'] as String?;
      stderr.write('.');
      if (!hasNext || cursor == null || cursor.isEmpty) break;

      await Future.delayed(const Duration(milliseconds: 350));
    }
  } catch (_) {
    // Return whatever was gathered before the failure.
  } finally {
    client.close();
  }

  return exercises;
}

// ── Mapping helpers (mirrored from ExerciseDBService) ────────────────────────

Exercise _mapToExercise(Map<String, dynamic> raw) {
  final bodyParts = List<String>.from(
      raw['bodyParts'] ?? (raw['bodyPart'] is String ? [raw['bodyPart']] : []));
  final equipments = List<String>.from(
      raw['equipments'] ?? (raw['equipment'] is String ? [raw['equipment']] : []));
  final targetMuscles = List<String>.from(
      raw['targetMuscles'] ?? (raw['target'] is String ? [raw['target']] : []));
  final secondaryMuscles = List<String>.from(raw['secondaryMuscles'] ?? []);
  final instructions = raw['instructions'] is List
      ? (raw['instructions'] as List).cast<String>().join('\n')
      : (raw['instructions'] as String? ?? '');
  final name = (raw['name'] as String? ?? '').toLowerCase();

  return Exercise(
    id: raw['exerciseId']?.toString() ??
        raw['id']?.toString() ??
        name.hashCode.toString(),
    name: _titleCase(name),
    category: bodyParts.isNotEmpty ? bodyParts.first : 'Other',
    primaryMuscles: targetMuscles,
    secondaryMuscles: secondaryMuscles,
    equipment: _normalizeEquipment(equipments),
    difficulty: inferExerciseDifficulty(name, equipments),
    goals: _inferGoals(bodyParts, name),
    locations: _inferLocations(equipments),
    instructions: instructions,
  );
}

List<String> _normalizeEquipment(List<String> raw) {
  const map = {
    'body weight': 'Bodyweight',
    'dumbbell': 'Dumbbells',
    'barbell': 'Barbell',
    'ez barbell': 'Barbell',
    'kettlebell': 'Kettlebells',
    'resistance band': 'Resistance Bands',
    'pull-up bar': 'Pull-up Bar',
    'cable': 'Cable Machine',
    'machine': 'Machine',
    'band': 'Resistance Bands',
    'assisted': 'Machine',
  };
  final normalized = raw.map((e) => map[e.toLowerCase()] ?? _titleCase(e)).toList();
  return normalized.isEmpty ? ['Bodyweight'] : normalized;
}

List<String> _inferGoals(List<String> bodyParts, String name) {
  final goals = <String>[];
  final bp = bodyParts.map((b) => b.toLowerCase()).toList();
  final isJumpMove = name.startsWith('jump') ||
      RegExp(r'\b(box|broad|depth|split|vertical|long)\s+jump\b').hasMatch(name);
  if (bp.contains('cardio') || name.contains('run') || isJumpMove) {
    goals.add('weight_loss');
    goals.add('endurance');
  }
  if (bp.any((b) =>
      ['chest', 'back', 'shoulders', 'upper arms', 'upper legs'].contains(b))) {
    goals.add('muscle_gain');
    goals.add('general');
  }
  if (bp.contains('waist') || bp.contains('lower legs')) {
    goals.add('weight_loss');
    goals.add('general');
  }
  if (goals.isEmpty) goals.addAll(['general', 'muscle_gain']);
  return goals.toSet().toList();
}

List<String> _inferLocations(List<String> raw) {
  const gymOnly = {
    'cable', 'machine', 'assisted', 'smith machine', 'leverage machine'
  };
  return raw.any((e) => gymOnly.contains(e.toLowerCase()))
      ? ['gym']
      : ['home', 'gym'];
}

final _stylePrefix = RegExp(r'\b[a-z-]+ style ');
final _gentleWord = RegExp(r'\bgentle\b');
const _danglingWithAdjectives = {
  'classic', 'simple', 'basic', 'intensified', 'declined', 'elevated',
  'extended', 'advanced', 'dynamic', 'narrow', 'targeted', 'traditional',
  'mega', 'horizontal', 'vertical', 'fierce', 'sharp', 'firm', 'precision',
  'complete', 'athletic', 'endurance', 'macro', 'high', 'triple', 'single',
  'inverted', 'stability',
};

bool _isLikelyAutoGenerated(String name) {
  final n = name.toLowerCase();
  if (_stylePrefix.hasMatch(n)) return true;
  if (_gentleWord.hasMatch(n)) return true;
  final withIdx = n.lastIndexOf(' with ');
  if (withIdx != -1) {
    final tail = n.substring(withIdx + ' with '.length).trim();
    if (_danglingWithAdjectives.contains(tail)) return true;
  }
  return false;
}

String _titleCase(String s) => s
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

// ── Misc helpers ──────────────────────────────────────────────────────────────

String _gk(String g) => switch (g) {
      'Muscle Gain' => 'muscle_gain',
      'Weight Loss' => 'weight_loss',
      'Endurance' => 'endurance',
      _ => 'general',
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
