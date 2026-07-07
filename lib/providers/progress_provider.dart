import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../models/user_profile.dart';
import '../models/food_item.dart';
import '../models/workout_log.dart';
import '../models/weight_log.dart';
import '../app_clock.dart';

/// Time window for the Progress screen trend cards.
enum TrendRange { week, month, year }

/// One aggregated point on a trend chart. Calorie/macro values are the
/// **average per logged day** within the bucket, so the daily-goal reference
/// line stays comparable across every range.
class TrendBucket {
  final String label;
  final DateTime start;
  final DateTime end; // exclusive
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final int daysLogged;

  const TrendBucket({
    required this.label,
    required this.start,
    required this.end,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.daysLogged,
  });
}

class ProgressProvider extends ChangeNotifier {
  final _fs = FirestoreService();

  UserProfile? _profile;
  List<FoodItem> _todayLogs = [];
  List<FoodItem> _yearFoodLogs = [];
  List<WorkoutLog> _yearWorkoutLogs = [];
  List<WeightLog> _weightLogs = [];
  bool _isLoading = false;
  String? _error;

  /// Memoised bucket lists per range — cleared on every [loadAll].
  final Map<TrendRange, List<TrendBucket>> _bucketCache = {};

  UserProfile? get profile => _profile;
  List<FoodItem> get todayLogs => _todayLogs;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ── Back-compat getters (derived from the year lists / week bucket) ──────────

  WorkoutLog? get todayWorkoutLog {
    final now = appNow();
    final todayStart = DateTime(now.year, now.month, now.day);
    return _yearWorkoutLogs.where((l) {
      final ld = DateTime(l.date.year, l.date.month, l.date.day);
      return ld == todayStart;
    }).firstOrNull;
  }

  /// Workout logs for the current Mon–Sun week.
  List<WorkoutLog> get weekWorkoutLogs {
    final (start, end) = _rangeBounds(TrendRange.week);
    return _yearWorkoutLogs.where((l) {
      final d = l.date;
      return !d.isBefore(start) && d.isBefore(end);
    }).toList();
  }

  /// Per-day calorie totals for the current week, keyed by weekday abbrev.
  Map<String, double> get weeklyCalories {
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final out = {for (final d in dayNames) d: 0.0};
    final (start, end) = _rangeBounds(TrendRange.week);
    for (final f in _yearFoodLogs) {
      final t = f.loggedAt;
      if (t.isBefore(start) || !t.isBefore(end)) continue;
      out[dayNames[t.weekday - 1]] = out[dayNames[t.weekday - 1]]! + f.totalCalories;
    }
    return out;
  }

  /// Per-day macro totals for the current week, keyed by weekday abbrev.
  Map<String, Map<String, double>> get weeklyMacros {
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final out = {
      for (final d in dayNames) d: {'protein': 0.0, 'carbs': 0.0, 'fat': 0.0},
    };
    final (start, end) = _rangeBounds(TrendRange.week);
    for (final f in _yearFoodLogs) {
      final t = f.loggedAt;
      if (t.isBefore(start) || !t.isBefore(end)) continue;
      final key = dayNames[t.weekday - 1];
      out[key]!['protein'] = out[key]!['protein']! + f.totalProtein;
      out[key]!['carbs'] = out[key]!['carbs']! + f.totalCarbs;
      out[key]!['fat'] = out[key]!['fat']! + f.totalFat;
    }
    return out;
  }

  List<WeightLog> get weightLogs => _weightLogs;

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
    return (weekWorkoutLogs.length / plannedWorkoutDays).clamp(0.0, 1.0);
  }

  /// Weekly calorie adherence (%). Uses the **profile's base `calorieGoal`**
  /// (NOT the daily-adjusted one) — the weekly [AdaptationEngine] reads this
  /// same metric, so it must use the same denominator.
  double get calorieAdherence => calorieAdherenceFor(TrendRange.week);

  int get workoutStreak {
    int streak = 0;
    final today = appNow();
    for (int i = 0; i < 365; i++) {
      final date = today.subtract(Duration(days: i));
      final dayStart = DateTime(date.year, date.month, date.day);
      final hasLog = _yearWorkoutLogs.any((l) {
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

  double get proteinConsistency => proteinConsistencyFor(TrendRange.week);

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

  // ── Range-aware trend API ─────────────────────────────────────────────────────

  List<TrendBucket> buckets(TrendRange r) =>
      _bucketCache[r] ??= _buildBuckets(r);

  List<String> bucketLabels(TrendRange r) =>
      buckets(r).map((b) => b.label).toList();

  List<double> calorieSeries(TrendRange r) =>
      buckets(r).map((b) => b.calories).toList();

  List<double> macroSeries(TrendRange r, String macro) => buckets(r).map((b) {
        switch (macro) {
          case 'protein':
            return b.protein;
          case 'carbs':
            return b.carbs;
          case 'fat':
            return b.fat;
          default:
            return 0.0;
        }
      }).toList();

  /// Weight logs falling inside the range, ordered oldest → newest.
  List<WeightLog> weightSeries(TrendRange r) {
    final (start, end) = _rangeBounds(r);
    final inRange = _weightLogs.where((l) {
      final d = l.date;
      return !d.isBefore(start) && d.isBefore(end);
    }).toList();
    inRange.sort((a, b) => a.date.compareTo(b.date));
    return inRange;
  }

  double calorieAdherenceFor(TrendRange r) {
    final baseGoal = _profile?.calorieGoal ?? 2000;
    final logged = buckets(r)
        .where((b) => b.daysLogged > 0)
        .map((b) => b.calories)
        .toList();
    if (logged.isEmpty) return 0;
    final avg = logged.reduce((a, b) => a + b) / logged.length;
    return (avg / baseGoal * 100).clamp(0, 200);
  }

  int workoutsDoneFor(TrendRange r) {
    final (start, end) = _rangeBounds(r);
    return _yearWorkoutLogs.where((l) {
      final d = l.date;
      return !d.isBefore(start) && d.isBefore(end);
    }).length;
  }

  double proteinConsistencyFor(TrendRange r) {
    // % of days with a food log where protein ≥ 90% of goal, over the range.
    final (start, end) = _rangeBounds(r);
    final byDay = <DateTime, double>{};
    for (final f in _yearFoodLogs) {
      final t = f.loggedAt;
      if (t.isBefore(start) || !t.isBefore(end)) continue;
      final day = DateTime(t.year, t.month, t.day);
      byDay[day] = (byDay[day] ?? 0) + f.totalProtein;
    }
    if (byDay.isEmpty) return 0;
    final onTarget =
        byDay.values.where((p) => p >= proteinGoal * 0.9).length;
    return onTarget / byDay.length * 100;
  }

  // ── Load ────────────────────────────────────────────────────────────────────

  /// Refreshes all trend stats over a trailing year. Pass [profile] (from
  /// [ProfileProvider]) to use the shared cached profile and skip a redundant
  /// Firestore read; omit it to fetch (keeps callers like [logWeight] working).
  Future<void> loadAll(String userId, {UserProfile? profile, int? effectiveGoal}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = appNow();
      final yearAgo = DateTime(now.year - 1, now.month, now.day);

      final profileFuture =
          profile != null ? Future.value(profile) : _fs.getUserProfile(userId);

      final results = await Future.wait([
        _fs.getFoodLogsForDate(userId, now),
        _fs.getFoodLogsForDateRange(userId, yearAgo, now),
        _fs.getWorkoutLogsForDateRange(userId, yearAgo, now.add(const Duration(days: 1))),
        _fs.getWeightLogs(userId, limit: 400),
      ]);

      _profile = await profileFuture;
      _effectiveGoal = effectiveGoal ?? _profile?.calorieGoal ?? 2000;
      _todayLogs = results[0] as List<FoodItem>;
      _yearFoodLogs = results[1] as List<FoodItem>;
      _yearWorkoutLogs = results[2] as List<WorkoutLog>;

      final rawWeightLogs = results[3] as List<Map<String, dynamic>>;
      _weightLogs = rawWeightLogs
          .asMap()
          .entries
          .map((e) => WeightLog.fromMap(e.value, e.key.toString()))
          .toList();

      _bucketCache.clear();
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

  // ── Bucketing internals ───────────────────────────────────────────────────────

  /// Inclusive-start, exclusive-end bounds for a range, anchored on [appNow].
  (DateTime, DateTime) _rangeBounds(TrendRange r) {
    final now = appNow();
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: 1)); // include all of today
    switch (r) {
      case TrendRange.week:
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return (monday, monday.add(const Duration(days: 7)));
      case TrendRange.month:
        // Current week + 3 prior weeks = 4 weekly buckets.
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return (monday.subtract(const Duration(days: 21)), monday.add(const Duration(days: 7)));
      case TrendRange.year:
        // Start of the month 11 months back → 12 monthly buckets.
        final firstOfThisMonth = DateTime(today.year, today.month, 1);
        final start = DateTime(firstOfThisMonth.year, firstOfThisMonth.month - 11, 1);
        return (start, end);
    }
  }

  List<TrendBucket> _buildBuckets(TrendRange r) {
    switch (r) {
      case TrendRange.week:
        return _dailyBuckets();
      case TrendRange.month:
        return _weeklyBuckets();
      case TrendRange.year:
        return _monthlyBuckets();
    }
  }

  /// Aggregates food logs whose `loggedAt` falls in [start, end) into one bucket.
  TrendBucket _aggregate(String label, DateTime start, DateTime end) {
    final byDay = <DateTime, List<double>>{}; // day → [cal, prot, carb, fat]
    for (final f in _yearFoodLogs) {
      final t = f.loggedAt;
      if (t.isBefore(start) || !t.isBefore(end)) continue;
      final day = DateTime(t.year, t.month, t.day);
      final acc = byDay.putIfAbsent(day, () => [0, 0, 0, 0]);
      acc[0] += f.totalCalories;
      acc[1] += f.totalProtein;
      acc[2] += f.totalCarbs;
      acc[3] += f.totalFat;
    }
    final n = byDay.length;
    if (n == 0) {
      return TrendBucket(
        label: label,
        start: start,
        end: end,
        calories: 0,
        protein: 0,
        carbs: 0,
        fat: 0,
        daysLogged: 0,
      );
    }
    double cal = 0, prot = 0, carb = 0, fat = 0;
    for (final v in byDay.values) {
      cal += v[0];
      prot += v[1];
      carb += v[2];
      fat += v[3];
    }
    return TrendBucket(
      label: label,
      start: start,
      end: end,
      calories: cal / n,
      protein: prot / n,
      carbs: carb / n,
      fat: fat / n,
      daysLogged: n,
    );
  }

  List<TrendBucket> _dailyBuckets() {
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = appNow();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return [
      for (var i = 0; i < 7; i++)
        _aggregate(
          dayNames[i],
          monday.add(Duration(days: i)),
          monday.add(Duration(days: i + 1)),
        ),
    ];
  }

  List<TrendBucket> _weeklyBuckets() {
    final now = appNow();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final firstMonday = monday.subtract(const Duration(days: 21));
    return [
      for (var i = 0; i < 4; i++)
        () {
          final s = firstMonday.add(Duration(days: i * 7));
          final e = s.add(const Duration(days: 7));
          return _aggregate('${s.month}/${s.day}', s, e);
        }(),
    ];
  }

  List<TrendBucket> _monthlyBuckets() {
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final now = appNow();
    final firstOfThisMonth = DateTime(now.year, now.month, 1);
    return [
      for (var i = 11; i >= 0; i--)
        () {
          final s = DateTime(firstOfThisMonth.year, firstOfThisMonth.month - i, 1);
          final e = DateTime(s.year, s.month + 1, 1);
          return _aggregate(monthNames[s.month - 1], s, e);
        }(),
    ];
  }
}
