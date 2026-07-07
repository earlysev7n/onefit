import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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
/// targets — `(weekly_goal − week_consumed) / days_left`, clamped ±10%. They
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

  UserProfile? get profile => _profile;
  bool get isLoading => _isLoading;

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
      final monday = today.subtract(Duration(days: today.weekday - 1));
      final weekEnd = today; // exclude today's logs — goal is fixed for the current day

      // Anchor the tracked week to account creation so days *before* the account
      // existed aren't read as under-eaten (which would inflate a new user's
      // day-one goal by up to +10%). Fall back to Firebase auth creation time for
      // legacy profiles with no stored createdAt, then to `monday` (legacy full
      // calendar week).
      final created = p.createdAt ??
          FirebaseAuth.instance.currentUser?.metadata.creationTime?.toLocal();
      final createdDay = created == null
          ? monday
          : DateTime(created.year, created.month, created.day);
      final anchor = createdDay.isAfter(monday) ? createdDay : monday;
      final logs = await _fs.getFoodLogsForDateRange(uid, anchor, weekEnd);

      final daysLeft = 8 - today.weekday; // Mon→7, Sun→1
      final daysElapsed = today.difference(anchor).inDays.clamp(0, 6);

      double sumCals = 0, sumProt = 0, sumCarbs = 0, sumFat = 0;
      for (final f in logs) {
        sumCals += f.totalCalories;
        sumProt += f.totalProtein;
        sumCarbs += f.totalCarbs;
        sumFat += f.totalFat;
      }

      _dailyEffectiveGoal = WeeklyAdaptiveGoal.adjust(
        base: p.calorieGoal.toDouble(),
        weekConsumed: sumCals,
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
  Future<void> save(UserProfile p) async {
    await _fs.saveUserProfile(p);
    _profile = p;
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
