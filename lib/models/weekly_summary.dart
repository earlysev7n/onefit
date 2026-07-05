import 'package:cloud_firestore/cloud_firestore.dart';

/// Immutable snapshot of one weekly adaptation event, persisted to
/// `users/{uid}/weekly_summaries/{weekId}` by `plans_screen._generate()` once
/// per week (same guard as the calorie-bias application). It records the
/// performance of the week that was *reviewed* (the prior, completed week) and
/// the adjustments that were applied to the *active* week as a result.
///
/// Read back by the Weekly Review screen (current week + history). The macro
/// fields are derived from `UserProfile.macroGoals` before/after the calorie
/// change — the engine tunes calories only; macros follow the goal.
class WeeklySummary {
  /// The active week the plan was generated for (doc id, e.g. `week_2026_25`).
  final String weekId;
  final DateTime generatedAt;
  final DateTime weekStart; // active week Monday
  final DateTime weekEnd; // active week Sunday

  // ── Reviewed-week performance (drove the decision) ────────────────────────
  final double calorieAdherence; // % of calorie goal (avg over logged days)
  final double?
  proteinAdherence; // % of protein goal; null if too little logging
  final int workoutsCompleted;
  final int workoutsPlanned;
  final double? avgRating; // avg perceived difficulty 1–5; null if unrated
  final int daysLogged;

  // ── Adjustments applied to the active week ────────────────────────────────
  final int calorieBias; // ± kcal (or 0)
  final int oldCalorieGoal;
  final int newCalorieGoal;
  final int oldProtein;
  final int newProtein;
  final int oldCarbs;
  final int newCarbs;
  final int oldFat;
  final int newFat;
  final String difficultyBias; // 'up' | 'down' | 'same'
  final bool
  volumeChanged; // whether the difficulty step actually moved sets (W2)
  final String notes; // the "Why these changes?" reasoning

  const WeeklySummary({
    required this.weekId,
    required this.generatedAt,
    required this.weekStart,
    required this.weekEnd,
    required this.calorieAdherence,
    required this.proteinAdherence,
    required this.workoutsCompleted,
    required this.workoutsPlanned,
    required this.avgRating,
    required this.daysLogged,
    required this.calorieBias,
    required this.oldCalorieGoal,
    required this.newCalorieGoal,
    required this.oldProtein,
    required this.newProtein,
    required this.oldCarbs,
    required this.newCarbs,
    required this.oldFat,
    required this.newFat,
    required this.difficultyBias,
    required this.volumeChanged,
    required this.notes,
  });

  // ── Derived display helpers ───────────────────────────────────────────────

  /// Net macro deltas (new − old), derived from the calorie change.
  int get proteinDelta => newProtein - oldProtein;
  int get carbsDelta => newCarbs - oldCarbs;
  int get fatDelta => newFat - oldFat;

  /// One-word headline for the History list. Calories take priority because
  /// they're the primary lever; intensity only counts when the set count
  /// actually moved (a clamp-absorbed step is not a real change — see W2).
  /// There is deliberately no "Increased Protein" — macros follow calories, so
  /// protein can never rise independently of an "Increased Calories" event.
  String get adjustmentBadge {
    if (calorieBias > 0) return 'Increased Calories';
    if (calorieBias < 0) return 'Reduced Calories';
    if (volumeChanged && difficultyBias == 'up') return 'Increased Intensity';
    if (volumeChanged && difficultyBias == 'down') return 'Reduced Intensity';
    return 'Stable';
  }

  Map<String, dynamic> toMap() => {
    'weekId': weekId,
    'generatedAt': Timestamp.fromDate(generatedAt),
    'weekStart': Timestamp.fromDate(weekStart),
    'weekEnd': Timestamp.fromDate(weekEnd),
    'calorieAdherence': calorieAdherence,
    'proteinAdherence': proteinAdherence,
    'workoutsCompleted': workoutsCompleted,
    'workoutsPlanned': workoutsPlanned,
    'avgRating': avgRating,
    'daysLogged': daysLogged,
    'calorieBias': calorieBias,
    'oldCalorieGoal': oldCalorieGoal,
    'newCalorieGoal': newCalorieGoal,
    'oldProtein': oldProtein,
    'newProtein': newProtein,
    'oldCarbs': oldCarbs,
    'newCarbs': newCarbs,
    'oldFat': oldFat,
    'newFat': newFat,
    'difficultyBias': difficultyBias,
    'volumeChanged': volumeChanged,
    'notes': notes,
  };

  factory WeeklySummary.fromMap(Map<String, dynamic> m, String id) {
    DateTime ts(dynamic v) => v is Timestamp ? v.toDate() : DateTime.now();
    return WeeklySummary(
      weekId: m['weekId'] ?? id,
      generatedAt: ts(m['generatedAt']),
      weekStart: ts(m['weekStart']),
      weekEnd: ts(m['weekEnd']),
      calorieAdherence: (m['calorieAdherence'] as num?)?.toDouble() ?? 0,
      proteinAdherence: (m['proteinAdherence'] as num?)?.toDouble(),
      workoutsCompleted: (m['workoutsCompleted'] as num?)?.toInt() ?? 0,
      workoutsPlanned: (m['workoutsPlanned'] as num?)?.toInt() ?? 0,
      avgRating: (m['avgRating'] as num?)?.toDouble(),
      daysLogged: (m['daysLogged'] as num?)?.toInt() ?? 0,
      calorieBias: (m['calorieBias'] as num?)?.toInt() ?? 0,
      oldCalorieGoal: (m['oldCalorieGoal'] as num?)?.toInt() ?? 0,
      newCalorieGoal: (m['newCalorieGoal'] as num?)?.toInt() ?? 0,
      oldProtein: (m['oldProtein'] as num?)?.toInt() ?? 0,
      newProtein: (m['newProtein'] as num?)?.toInt() ?? 0,
      oldCarbs: (m['oldCarbs'] as num?)?.toInt() ?? 0,
      newCarbs: (m['newCarbs'] as num?)?.toInt() ?? 0,
      oldFat: (m['oldFat'] as num?)?.toInt() ?? 0,
      newFat: (m['newFat'] as num?)?.toInt() ?? 0,
      difficultyBias: m['difficultyBias'] ?? 'same',
      volumeChanged: m['volumeChanged'] ?? false,
      notes: m['notes'] ?? '',
    );
  }
}
