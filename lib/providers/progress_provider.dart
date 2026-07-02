import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../models/user_profile.dart';
import '../models/food_item.dart';
import '../models/workout_log.dart';
import '../models/weight_log.dart';
import '../app_clock.dart';

class ProgressProvider extends ChangeNotifier {
  final _fs = FirestoreService();

  UserProfile? _profile;
  List<FoodItem> _todayLogs = [];
  WorkoutLog? _todayWorkoutLog;
  Map<String, double> _weeklyCalories = {};
  Map<String, Map<String, double>> _weeklyMacros = {};
  List<WorkoutLog> _weekWorkoutLogs = [];
  List<WeightLog> _weightLogs = [];
  bool _isLoading = false;
  String? _error;

  UserProfile? get profile => _profile;
  List<FoodItem> get todayLogs => _todayLogs;
  WorkoutLog? get todayWorkoutLog => _todayWorkoutLog;
  Map<String, double> get weeklyCalories => _weeklyCalories;
  Map<String, Map<String, double>> get weeklyMacros => _weeklyMacros;
  List<WorkoutLog> get weekWorkoutLogs => _weekWorkoutLogs;
  List<WeightLog> get weightLogs => _weightLogs;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ── Computed ────────────────────────────────────────────────────────────────

  double get todayCalories => _todayLogs.fold(0, (s, f) => s + f.totalCalories);
  double get todayProtein => _todayLogs.fold(0, (s, f) => s + f.totalProtein);

  /// Today's display goal (daily-carry-adjusted). Set by [loadAll] from
  /// [ProfileProvider.dailyEffectiveGoal]. The today-ring and chart use this.
  int _effectiveGoal = 2000;
  int get calorieGoal => _effectiveGoal;
  double get proteinGoal => (_profile?.macroGoals['protein'] ?? 150).toDouble();

  /// Planned training days per week — driven by the user's real profile input.
  int get plannedWorkoutDays => _profile?.workoutDaysPerWeek ?? 3;

  /// Weekly workout completion 0–1 using the actual planned-days denominator.
  double get weeklyWorkoutCompletion {
    if (plannedWorkoutDays == 0) return 0;
    return (_weekWorkoutLogs.length / plannedWorkoutDays).clamp(0.0, 1.0);
  }

  /// Weekly calorie adherence (%). Uses the **profile's base `calorieGoal`**
  /// (NOT the daily-adjusted one) — the weekly [AdaptationEngine] reads this
  /// same metric, so it must use the same denominator.
  double get calorieAdherence {
    final baseGoal = _profile?.calorieGoal ?? 2000;
    final days = _weeklyCalories.values.where((v) => v > 0).toList();
    if (days.isEmpty) return 0;
    final avg = days.reduce((a, b) => a + b) / days.length;
    return (avg / baseGoal * 100).clamp(0, 200);
  }

  int get workoutStreak {
    int streak = 0;
    final today = appNow();
    for (int i = 0; i < 30; i++) {
      final date = today.subtract(Duration(days: i));
      final dayStart = DateTime(date.year, date.month, date.day);
      final hasLog = _weekWorkoutLogs.any((l) {
        final ld = DateTime(l.date.year, l.date.month, l.date.day);
        return ld == dayStart;
      });
      if (hasLog) {
        streak++;
      } else if (i > 0) {
        break;
      }
    }
    return streak;
  }

  double get proteinConsistency {
    final days = _weeklyMacros.values.toList();
    if (days.isEmpty) return 0;
    final onTarget = days.where((d) => (d['protein'] ?? 0) >= proteinGoal * 0.9).length;
    return onTarget / days.length * 100;
  }

  double? get latestWeight => _weightLogs.isEmpty ? null : _weightLogs.first.weight;
  double? get startWeight => _weightLogs.isEmpty ? null : _weightLogs.last.weight;

  WeightLog? get todayWeightLog {
    if (_weightLogs.isEmpty) return null;
    final today = appToday();
    final first = _weightLogs.first;
    return (first.date.year == today.year &&
            first.date.month == today.month &&
            first.date.day == today.day)
        ? first
        : null;
  }

  // ── Load ────────────────────────────────────────────────────────────────────

  /// Refreshes all weekly stats. Pass [profile] (from [ProfileProvider]) to use
  /// the shared cached profile and skip a redundant Firestore read; omit it to
  /// fetch (keeps callers like [logWeight] backward-compatible).
  Future<void> loadAll(String userId, {UserProfile? profile, int? effectiveGoal}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = appNow();
      final weekday = now.weekday;
      final weekStart = now.subtract(Duration(days: weekday - 1));
      final monday = DateTime(weekStart.year, weekStart.month, weekStart.day);

      // Use the passed-in shared profile when available; otherwise fetch it in
      // parallel with the rest of the weekly data.
      final profileFuture =
          profile != null ? Future.value(profile) : _fs.getUserProfile(userId);

      final results = await Future.wait([
        _fs.getFoodLogsForDate(userId, now),
        _fs.getDailyCalorieTotals(userId, monday),
        _fs.getWorkoutLogsForDateRange(userId, monday, monday.add(const Duration(days: 7))),
        _fs.getWeightLogs(userId),
        _fs.getFoodLogsForDateRange(userId, monday, monday.add(const Duration(days: 7))),
      ]);

      _profile = await profileFuture;
      _effectiveGoal = effectiveGoal ?? _profile?.calorieGoal ?? 2000;
      _todayLogs = results[0] as List<FoodItem>;
      _weeklyCalories = results[1] as Map<String, double>;
      _weekWorkoutLogs = results[2] as List<WorkoutLog>;

      final rawWeightLogs = results[3] as List<Map<String, dynamic>>;
      _weightLogs = rawWeightLogs.asMap().entries.map((e) {
        final m = e.value;
        return WeightLog.fromMap(m, e.key.toString());
      }).toList();

      // Build per-day macro totals for the week
      final weekFoodLogs = results[4] as List<FoodItem>;
      const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      _weeklyMacros = {for (final d in dayNames) d: {'protein': 0.0, 'carbs': 0.0, 'fat': 0.0}};
      for (final food in weekFoodLogs) {
        final dayIdx = food.loggedAt.weekday - 1;
        if (dayIdx >= 0 && dayIdx < 7) {
          final key = dayNames[dayIdx];
          _weeklyMacros[key]!['protein'] = (_weeklyMacros[key]!['protein'] ?? 0) + food.totalProtein;
          _weeklyMacros[key]!['carbs'] = (_weeklyMacros[key]!['carbs'] ?? 0) + food.totalCarbs;
          _weeklyMacros[key]!['fat'] = (_weeklyMacros[key]!['fat'] ?? 0) + food.totalFat;
        }
      }

      // Today's workout log
      final todayStart = DateTime(now.year, now.month, now.day);
      _todayWorkoutLog = _weekWorkoutLogs.where((l) {
        final ld = DateTime(l.date.year, l.date.month, l.date.day);
        return ld == todayStart;
      }).firstOrNull;
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> logWeight(String userId, double weightKg) async {
    await _fs.saveWeightLog(userId, weightKg);
    await loadAll(userId);
  }
}
