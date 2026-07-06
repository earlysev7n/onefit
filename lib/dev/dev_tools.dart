import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../algorithms/greedy_algorithm.dart';
import '../app_clock.dart';
import '../models/exercise.dart';
import '../models/food_item.dart';
import '../models/user_profile.dart';
import '../models/workout_log.dart';
import '../providers/plan_provider.dart';
import '../providers/profile_provider.dart';
import '../services/firestore_service.dart';

/// Developer-mode demo helpers (gated behind [developerModeEnabled], surfaced
/// from the Settings screen). They write real workout_logs / food_logs the same
/// way the app does, so the weekly [AdaptationEngine] treats the seeded week as
/// genuine history and adapts when the clock jumps forward.
///
/// Every provider read happens synchronously before the first `await` so the
/// passed-in [BuildContext] is never used across an async gap.
class DevTools {
  DevTools._();

  static final FirestoreService _fs = FirestoreService();

  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static String scenarioLabel(DevScenario s) {
    switch (s) {
      case DevScenario.levelUp:
        return 'Level up';
      case DevScenario.easeOff:
        return 'Ease off';
      case DevScenario.realistic:
        return 'Realistic';
    }
  }

  /// Logs today's planned workout as completed in one tap. Returns a status
  /// message for a snackbar.
  static Future<String> autoCompleteToday(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 'Not signed in';
    final profile = context.read<ProfileProvider>().profile;
    var plan = context.read<PlanProvider>().workoutPlan;

    final weekId = FirestoreService.weekIdFor(appToday());
    if (plan.isEmpty) {
      plan = await _fs.loadWeeklyWorkoutPlan(uid, weekId) ?? const [];
    }
    if (plan.isEmpty) return 'No plan yet — open Plans first';

    final idx = (appNow().weekday - 1).clamp(0, plan.length - 1);
    final day = plan[idx];
    if (day.isRest || day.exercises.isEmpty) {
      return 'No workout scheduled today (${day.dayName})';
    }
    await _logWorkout(uid, profile, day, appToday(), rating: 1, skip: false);
    return 'Logged ${day.exercises.length} exercises for ${day.dayName}';
  }

  /// Seeds the current week with workout + food logs for every day (shaped by
  /// [scenario]) so it becomes a rich "last week", then jumps the clock forward
  /// 7 days. Opening the Plans tab afterwards fires the weekly adaptation.
  static Future<String> simulateWeekAndAdvance(
    BuildContext context,
    DevScenario scenario,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 'Not signed in';
    final profile = context.read<ProfileProvider>().profile;
    if (profile == null) return 'Profile not loaded';
    var plan = context.read<PlanProvider>().workoutPlan;

    // The week that is about to become "last week".
    final today = appToday();
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final weekId = FirestoreService.weekIdFor(monday);

    if (plan.isEmpty) {
      plan = await _fs.loadWeeklyWorkoutPlan(uid, weekId) ?? const [];
    }
    final hasRealPlan = plan.any((d) => !d.isRest && d.exercises.isNotEmpty);
    if (hasRealPlan) {
      // Guarantee last week has a persisted plan so `hasHistory` holds even if
      // (defensively) no workout log lands.
      await _fs.saveWeeklyWorkoutPlan(uid, weekId, plan);
    }

    // Which day indices are training days (real plan) or evenly-spaced slots.
    final trainingDays = hasRealPlan
        ? [
            for (var i = 0; i < plan.length && i < 7; i++)
              if (!plan[i].isRest && plan[i].exercises.isNotEmpty) i,
          ]
        : _evenlySpaced(profile.workoutDaysPerWeek);

    // Scenario knobs — see the table in the plan / AdaptationEngine.
    final double calFactor;
    final int rating;
    final int workoutsToLog;
    switch (scenario) {
      case DevScenario.levelUp:
        calFactor = 0.80; // clearly under target → +100 kcal next week
        rating = 1; // "too easy" → difficulty up
        workoutsToLog = trainingDays.length; // full completion
        break;
      case DevScenario.easeOff:
        calFactor = 1.0; // on target → no calorie change
        rating = 5; // "too hard" → difficulty down (+ safety brake)
        workoutsToLog = (trainingDays.length * 0.4).floor(); // <50% completion
        break;
      case DevScenario.realistic:
        calFactor = 0.83; // mildly under → +100 kcal, difficulty held steady
        rating = 3; // neutral vote → no difficulty step
        workoutsToLog = (trainingDays.length * 0.7).floor(); // ~steady, <0.8
        break;
    }

    // Food for all 7 days (≥4 logged days is required for adherence to count).
    for (var i = 0; i < 7; i++) {
      await _logFood(uid, profile, monday.add(Duration(days: i)), calFactor);
    }

    // Workouts for the chosen number of training days.
    for (final di in trainingDays.take(workoutsToLog)) {
      final date = monday.add(Duration(days: di));
      final day = hasRealPlan
          ? plan[di]
          : WorkoutDay(
              dayName: _weekdays[di.clamp(0, 6)],
              focus: 'Full Body',
              exercises: const [],
            );
      await _logWorkout(uid, profile, day, date, rating: rating, skip: false);
    }

    // Jump one week forward so the Plans tab regenerates and adapts.
    devDayChangerEnabled.value = true;
    debugDayOffset.value += 7;

    return 'Seeded last week (${scenarioLabel(scenario)}). '
        'Open Plans to see the adaptation.';
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  static Future<void> _logWorkout(
    String uid,
    UserProfile? profile,
    WorkoutDay day,
    DateTime date, {
    required int rating,
    required bool skip,
  }) async {
    final logged = <WorkoutLogExercise>[];
    final statWrites = <Future<void>>[];
    for (final e in day.exercises) {
      final reps = _midReps(e.reps);
      final timed = reps == null;
      final weight = _nominalWeight(e.exercise);
      final sets = List<SetEntry>.generate(
        e.sets,
        (_) => timed
            ? SetEntry(seconds: _timedSeconds(e.reps))
            : SetEntry(reps: reps, weightKg: weight),
      );
      logged.add(
        WorkoutLogExercise(
          name: e.exercise.name,
          sets: e.sets,
          reps: e.reps,
          restSeconds: e.restSeconds,
          primaryMuscles: e.exercise.primaryMuscles,
          loggedSets: skip ? const [] : sets,
          skipped: skip,
        ),
      );
      if (!skip && !timed) {
        statWrites.add(
          _fs.saveExerciseStat(
            userId: uid,
            exerciseId: e.exercise.id,
            name: e.exercise.name,
            weightKg: weight ?? 0,
            reps: reps,
            lastSets: sets,
          ),
        );
      }
    }

    final log = WorkoutLog(
      id: '',
      userId: uid,
      date: DateTime(date.year, date.month, date.day),
      weekId: FirestoreService.weekIdFor(date),
      dayName: day.dayName,
      focus: day.focus,
      durationMinutes: profile?.sessionMinutes ?? 45,
      completedAt: date,
      rating: rating,
      exercises: logged,
    );
    await _fs.saveWorkoutLog(log);
    await Future.wait(statWrites);
  }

  static Future<void> _logFood(
    String uid,
    UserProfile profile,
    DateTime date,
    double calFactor,
  ) async {
    final goal = profile.calorieGoal.toDouble();
    final macros = profile.macroGoals;
    final pGoal = (macros['protein'] ?? 0).toDouble();
    final cGoal = (macros['carbs'] ?? 0).toDouble();
    final fGoal = (macros['fat'] ?? 0).toDouble();

    const meals = <String, double>{
      'breakfast': 0.30,
      'lunch': 0.40,
      'dinner': 0.30,
    };

    var i = 0;
    for (final entry in meals.entries) {
      final frac = entry.value;
      // Space meals through the day; hour is cosmetic (date drives the logic).
      final loggedAt =
          DateTime(date.year, date.month, date.day, 8 + i * 5);
      final item = FoodItem(
        id: '${loggedAt.millisecondsSinceEpoch}_${entry.key}_dev',
        userId: uid,
        name: 'Demo ${_capitalize(entry.key)}',
        barcode: 'dev_seed',
        servingSize: 1,
        servingSizeUnit: 'serving',
        calories: goal * calFactor * frac,
        protein: pGoal * calFactor * frac,
        carbs: cGoal * calFactor * frac,
        fat: fGoal * calFactor * frac,
        loggedAt: loggedAt,
        mealType: entry.key,
      );
      await _fs.logFoodItem(item);
      i++;
    }
  }

  /// Evenly-spaced weekday indices for [count] training days across a week.
  static List<int> _evenlySpaced(int count) {
    if (count <= 0) return const [];
    if (count >= 7) return List.generate(7, (i) => i);
    final step = 7 / count;
    return [for (var i = 0; i < count; i++) (i * step).floor()];
  }

  /// Bodyweight moves (no equipment) log reps only; loaded moves get a nominal
  /// weight so the Week-2 progression prefill has something to show.
  static double? _nominalWeight(Exercise ex) {
    final eq = ex.equipment.map((e) => e.toLowerCase());
    final bodyweight = ex.equipment.isEmpty || eq.any((e) => e.contains('body'));
    return bodyweight ? null : 20.0;
  }

  /// Midpoint of a rep range ("8-12" → 10), single value ("10" → 10), or null
  /// for timed prescriptions ("45 sec").
  static int? _midReps(String reps) {
    final r = reps.toLowerCase();
    if (r.contains('sec') || r.contains('min')) return null;
    final nums =
        RegExp(r'\d+').allMatches(r).map((m) => int.parse(m.group(0)!)).toList();
    if (nums.isEmpty) return null;
    if (nums.length == 1) return nums.first;
    return ((nums[0] + nums[1]) / 2).round();
  }

  static int _timedSeconds(String reps) {
    final m = RegExp(r'\d+').firstMatch(reps);
    final v = m != null ? int.parse(m.group(0)!) : 30;
    return reps.toLowerCase().contains('min') ? v * 60 : v;
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
