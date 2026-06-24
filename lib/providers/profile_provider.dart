import 'package:flutter/material.dart';
import '../algorithms/daily_carry.dart';
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
/// [dailyEffectiveGoal] / [effectiveMacroGoals] layer the rule-based daily
/// calorie carry-forward on top of the profile's weekly-adapted [calorieGoal].
/// They are **provider-level, transient state** — never persisted, never visible
/// to the weekly [AdaptationEngine], recomputed on [load]/[refresh].
class ProfileProvider extends ChangeNotifier {
  final _fs = FirestoreService();

  UserProfile? _profile;
  bool _isLoading = false;
  double? _dailyEffectiveGoal;

  UserProfile? get profile => _profile;
  bool get isLoading => _isLoading;

  /// Today's effective calorie goal (daily-carry-adjusted). All display screens
  /// should use this, NOT `profile.calorieGoal`, for the current day's target.
  /// The weekly engine continues to read `profile.calorieGoal` directly.
  int get dailyEffectiveGoal =>
      (_dailyEffectiveGoal ?? _profile?.calorieGoal ?? 2000).round();

  /// Macro targets scaled to [dailyEffectiveGoal]. Same ratios as
  /// [UserProfile.macroGoals] but applied to the daily-adjusted calorie number.
  Map<String, int> get effectiveMacroGoals {
    final p = _profile;
    if (p == null) return {};
    final base = p.calorieGoal;
    if (base <= 0) return p.macroGoals;
    final scale = dailyEffectiveGoal / base;
    final m = p.macroGoals;
    return {
      'protein': (m['protein']! * scale).round(),
      'carbs': (m['carbs']! * scale).round(),
      'fat': (m['fat']! * scale).round(),
      'fiber': m['fiber']!,
      'sugar': m['sugar']!,
      'sodium': m['sodium']!,
    };
  }

  /// Loads the profile once and caches it. No-op if already loaded — safe to
  /// call from every screen's initState without triggering redundant reads.
  Future<void> load(String uid) async {
    if (_profile != null) return;
    await refresh(uid);
  }

  /// Force-fetches the profile from Firestore, replacing the cache.
  Future<void> refresh(String uid) async {
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

  /// Computes today's daily-carry-adjusted goal from yesterday's food logs.
  /// Fail-safe: falls back to the profile's base goal on any error.
  Future<void> _computeDailyGoal(String uid) async {
    final p = _profile;
    if (p == null) return;
    try {
      final yesterday = appToday().subtract(const Duration(days: 1));
      final logs = await _fs.getFoodLogsForDate(uid, yesterday);
      if (logs.isEmpty) {
        _dailyEffectiveGoal = null; // no data → use base goal
        return;
      }
      final yesterdayLogged =
          logs.fold<double>(0, (s, f) => s + f.totalCalories);
      _dailyEffectiveGoal = DailyCarry.dailyAdjustedGoal(
        baseGoal: p.calorieGoal.toDouble(),
        yesterdayLogged: yesterdayLogged,
      );
    } catch (_) {
      _dailyEffectiveGoal = null; // error → use base goal
    }
  }

  /// Persists [p] and updates the cache. Used by onboarding and the edit screen.
  Future<void> save(UserProfile p) async {
    await _fs.saveUserProfile(p);
    _profile = p;
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
