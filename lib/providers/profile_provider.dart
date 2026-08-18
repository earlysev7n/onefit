import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../algorithms/calorie_tolerance.dart';
import '../algorithms/weekly_adaptive_goal.dart';
import '../app_clock.dart';
import '../models/user_profile.dart';
import '../services/firestore_service.dart';

/// Single reactive source of truth for the current user's [UserProfile].
///
/// Replaces the six independent profile fetches that previously lived in the
/// home, nutrition, progress and plans screens. Mutations ([save],
/// [updateWeight], [applyCalorieAdjustment]) persist to Firestore and notify
/// listeners so every consumer recomputes its calorie/macro targets reactively.
///
/// [dailyEffectiveGoal] / [effectiveMacroGoals] expose today's weekly-adaptive
/// targets — `(weekly_goal − week_consumed) / days_left`, clamped ±10%, where
/// past days inside the ±5% [CalorieTolerance] band count as exactly on target
/// so only meaningful calorie deviations are redistributed. They
/// are **provider-level, transient state** — never persisted, never visible to
/// the weekly [AdaptationEngine], recomputed on [load]/[refresh].
class ProfileProvider extends ChangeNotifier {
  final _fs = FirestoreService();

  UserProfile? _profile;
  String? _uid;
  bool _isLoading = false;
  double? _dailyEffectiveGoal;
  double? _weeklyEffectiveProtein;
  double? _weeklyEffectiveCarbs;
  double? _weeklyEffectiveFat;
  int _daysInToleranceThisWeek = 0;
  int _daysLoggedThisWeek = 0;
  double? _lastBreachKcal;

  UserProfile? get profile => _profile;
  bool get isLoading => _isLoading;

  /// Days so far this week whose logged calories landed inside the ±5%
  /// [CalorieTolerance] band around the base goal (excludes today, which is
  /// still in progress). Paired with [daysLoggedThisWeek] for display.
  int get daysInToleranceThisWeek => _daysInToleranceThisWeek;

  /// Days so far this week with at least one food log (excludes today).
  int get daysLoggedThisWeek => _daysLoggedThisWeek;

  /// Logged days this week that fell outside the band — the days whose
  /// deviation was real enough to be redistributed into today's goal.
  int get daysOutOfToleranceThisWeek =>
      _daysLoggedThisWeek - _daysInToleranceThisWeek;

  /// Signed kcal deviation of the **most recent** out-of-band day (negative =
  /// under target), so the goal-adjustment dialog can name a real number.
  /// `null` when every logged day this week was on target.
  double? get lastBreachKcal => _lastBreachKcal;

  /// Today's effective calorie goal (daily-carry-adjusted). All display screens
  /// should use this, NOT `profile.calorieGoal`, for the current day's target.
  /// The weekly engine continues to read `profile.calorieGoal` directly.
  int get dailyEffectiveGoal =>
      (_dailyEffectiveGoal ?? _profile?.calorieGoal ?? 2000).round();

  /// Per-macro weekly-adaptive targets. Each nutrient is redistributed
  /// independently from its own weekly remaining budget, so protein, carbs and
  /// fat adjust at their own rates regardless of calorie adherence.
  Map<String, int> get effectiveMacroGoals {
    final p = _profile;
    if (p == null) return {};
    final m = p.macroGoals;
    return {
      'protein': (_weeklyEffectiveProtein ?? m['protein']!.toDouble()).round(),
      'carbs': (_weeklyEffectiveCarbs ?? m['carbs']!.toDouble()).round(),
      'fat': (_weeklyEffectiveFat ?? m['fat']!.toDouble()).round(),
      'fiber': m['fiber']!,
      'sugar': m['sugar']!,
      'sodium': m['sodium']!,
    };
  }

  /// Loads the profile once and caches it. No-op if already loaded — safe to
  /// call from every screen's initState without triggering redundant reads.
  Future<void> load(String uid) async {
    _uid = uid;
    if (_profile != null) return;
    await refresh(uid);
  }

  /// Reset cached profile + transient goal state on sign-out, so the next
  /// account's [load] actually re-fetches (recall [load] is a no-op while
  /// `_profile != null`).
  void clear() {
    _profile = null;
    _uid = null;
    _isLoading = false;
    _dailyEffectiveGoal = null;
    _weeklyEffectiveProtein = null;
    _weeklyEffectiveCarbs = null;
    _weeklyEffectiveFat = null;
    _daysInToleranceThisWeek = 0;
    _daysLoggedThisWeek = 0;
    _lastBreachKcal = null;
    notifyListeners();
  }

  /// Force-fetches the profile from Firestore, replacing the cache.
  Future<void> refresh(String uid) async {
    _uid = uid;
    _isLoading = true;
    notifyListeners();
    try {
      _profile = await _fs.getUserProfile(uid);
      await _computeDailyGoal(uid);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Computes today's weekly-adaptive targets for calories and each macro.
  ///
  /// Loads all food logs from Monday of the current ISO week to today, then
  /// applies [WeeklyAdaptiveGoal.adjust] independently per nutrient so the
  /// user can still hit their **weekly** goals even after over/under days.
  /// Fail-safe: all effective goals fall back to base profile values on error.
  Future<void> _computeDailyGoal(String uid) async {
    final p = _profile;
    if (p == null) return;
    try {
      final today = appToday();
      final anchorWeekday = p.createdAt?.weekday ?? 1;
      final weekStartDay = FirestoreService.weekStartFor(today, anchorWeekday: anchorWeekday);
      final weekEnd = today; // exclude today's logs — goal is fixed for the current day

      // Anchor the tracked week to account creation so days *before* the account
      // existed aren't read as under-eaten (which would inflate a new user's
      // day-one goal by up to +10%). Fall back to Firebase auth creation time for
      // legacy profiles with no stored createdAt, then to `weekStartDay`.
      final created = p.createdAt ??
          FirebaseAuth.instance.currentUser?.metadata.creationTime?.toLocal();
      final createdDay = created == null
          ? weekStartDay
          : DateTime(created.year, created.month, created.day);
      final anchor = createdDay.isAfter(weekStartDay) ? createdDay : weekStartDay;
      final logs = await _fs.getFoodLogsForDateRange(uid, anchor, weekEnd);

      final daysLeft = 7 - (today.weekday - anchorWeekday + 7) % 7;

      double sumProt = 0, sumCarbs = 0, sumFat = 0;
      // Calories are also bucketed per day so the ±5% tolerance can be applied
      // day-by-day before redistribution (see below). Macros stay on raw sums —
      // the tolerance rationale is about *energy* intake measurement error.
      final dayCals = <DateTime, double>{};
      for (final f in logs) {
        final d = f.loggedAt;
        final key = DateTime(d.year, d.month, d.day);
        dayCals[key] = (dayCals[key] ?? 0) + f.totalCalories;
        sumProt += f.totalProtein;
        sumCarbs += f.totalCarbs;
        sumFat += f.totalFat;
      }
      // Chronological, so "the most recent breach" below is unambiguous rather
      // than relying on the query's ordering.
      final days = dayCals.keys.toList()..sort();

      // Only *meaningful* deviations get redistributed: a day inside the ±5%
      // band is booked as exactly on target, so ordinary logging noise never
      // moves tomorrow's goal (NASEM 2023 — see CalorieTolerance).
      final baseGoal = p.calorieGoal.toDouble();
      final dayTotals = [for (final d in days) dayCals[d]!];
      _daysLoggedThisWeek = dayTotals.length;
      _daysInToleranceThisWeek = CalorieTolerance.daysInTolerance(
        dayTotals,
        baseGoal,
      );
      // The deviation the dialog quotes: the latest day that actually breached.
      _lastBreachKcal = null;
      for (final total in dayTotals) {
        if (!CalorieTolerance.within(total, baseGoal)) {
          _lastBreachKcal = total - baseGoal;
        }
      }

      // Redistribute over the days that actually have data. A day with no logs
      // is *missing data*, not a zero-calorie day — counting it as a full
      // shortfall used to inflate today's goal by up to +10% and fire the
      // "Today's Goal Adjusted" dialog at anyone who simply forgot to log.
      final daysElapsed = dayTotals.length.clamp(0, 6);

      _dailyEffectiveGoal = WeeklyAdaptiveGoal.adjust(
        base: baseGoal,
        weekConsumed: CalorieTolerance.effectiveWeekConsumed(
          dayTotals,
          baseGoal,
        ),
        daysLeft: daysLeft,
        daysElapsed: daysElapsed,
      );
      _weeklyEffectiveProtein = WeeklyAdaptiveGoal.adjust(
        base: p.macroGoals['protein']!.toDouble(),
        weekConsumed: sumProt,
        daysLeft: daysLeft,
        daysElapsed: daysElapsed,
      );
      _weeklyEffectiveCarbs = WeeklyAdaptiveGoal.adjust(
        base: p.macroGoals['carbs']!.toDouble(),
        weekConsumed: sumCarbs,
        daysLeft: daysLeft,
        daysElapsed: daysElapsed,
      );
      _weeklyEffectiveFat = WeeklyAdaptiveGoal.adjust(
        base: p.macroGoals['fat']!.toDouble(),
        weekConsumed: sumFat,
        daysLeft: daysLeft,
        daysElapsed: daysElapsed,
      );
    } catch (_) {
      _dailyEffectiveGoal = null;
      _weeklyEffectiveProtein = null;
      _weeklyEffectiveCarbs = null;
      _weeklyEffectiveFat = null;
      _daysInToleranceThisWeek = 0;
      _daysLoggedThisWeek = 0;
      _lastBreachKcal = null;
    }
  }

  /// Re-runs the weekly-adaptive goal computation without re-fetching the profile.
  /// Call this after any food-logging operation so screens see up-to-date effective
  /// goals in the same session.
  Future<void> recomputeGoal(String uid) async {
    await _computeDailyGoal(uid);
    notifyListeners();
  }

  /// Persists [p] and updates the cache. Used by onboarding and the edit screen.
  ///
  /// Updates the in-memory profile **before** the write (which is non-blocking —
  /// see [FirestoreService.saveUserProfile]) so weight logging, profile edits and
  /// the weekly calorie adaptation take effect offline immediately. Because
  /// `lastAdaptationWeekId` is set in memory here, the once-per-week adaptation
  /// guard still prevents double-application offline and across reconnect.
  Future<void> save(UserProfile p) async {
    _profile = p;
    await _fs.saveUserProfile(p);
    if (_uid != null) await _computeDailyGoal(_uid!);
    notifyListeners();
  }

  /// Syncs the body weight that drives BMR/TDEE/calorieGoal/BMI. Called when
  /// the user logs today's weight on the Progress screen.
  Future<void> updateWeight(double kg) async {
    if (_profile == null) return;
    await save(_profile!.copyWith(weight: kg));
  }

  /// Applies the weekly [AdaptationEngine] calorie bias on top of the existing
  /// accumulated adjustment, clamped to ±500 kcal to prevent week-over-week drift.
  Future<void> applyCalorieAdjustment(
    int weeklyBiasKcal, {
    String? markWeekId,
  }) async {
    if (_profile == null) return;
    final next = (_profile!.calorieAdjustment + weeklyBiasKcal).clamp(-500, 500);
    await save(_profile!.copyWith(
      calorieAdjustment: next,
      lastAdaptationWeekId: markWeekId ?? _profile!.lastAdaptationWeekId,
    ));
  }
}
