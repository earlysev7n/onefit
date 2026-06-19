import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/firestore_service.dart';

/// Single reactive source of truth for the current user's [UserProfile].
///
/// Replaces the six independent profile fetches that previously lived in the
/// home, nutrition, progress and plans screens. Mutations ([save],
/// [updateWeight], [applyCalorieAdjustment]) persist to Firestore and notify
/// listeners so every consumer recomputes its calorie/macro targets reactively.
class ProfileProvider extends ChangeNotifier {
  final _fs = FirestoreService();

  UserProfile? _profile;
  bool _isLoading = false;

  UserProfile? get profile => _profile;
  bool get isLoading => _isLoading;

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
    } finally {
      _isLoading = false;
      notifyListeners();
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
