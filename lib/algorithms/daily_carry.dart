/// Daily calorie carry-forward — a pure, rule-based nudge that lets *yesterday's*
/// over/under-eating shift the calorie target the meal generator aims for *today*.
///
/// This is intentionally separate from the weekly [AdaptationEngine]: it never
/// touches `UserProfile.calorieAdjustment`, is never persisted, and is never the
/// displayed goal. It only sizes generated food. The weekly engine continues to
/// read the user's *actual logged* weekly average against the unchanged
/// `UserProfile.calorieGoal`, so the two systems can't interfere.
class DailyCarry {
  /// Today's effective generation goal given [yesterdayLogged] total calories.
  ///
  /// `surplus = yesterdayLogged − baseGoal` (positive = overate); today's target
  /// is `baseGoal − surplus·carryFraction`, clamped to ±25% of [baseGoal] so a
  /// single binge/fast day can't dangerously slash or balloon the target.
  ///
  /// [carryFraction] defaults to 0.5: carrying the *full* surplus oscillates
  /// (overshoot → deep cut → undershoot → big surplus); half-carry converges in
  /// 2–3 days. Returns [baseGoal] unchanged when [yesterdayLogged] is null
  /// (no data — e.g. a brand-new user or an untracked day).
  static double dailyAdjustedGoal({
    required double baseGoal,
    double? yesterdayLogged,
    double carryFraction = 0.5,
  }) {
    if (yesterdayLogged == null) return baseGoal;
    final surplus = yesterdayLogged - baseGoal;
    final adjusted = baseGoal - (surplus * carryFraction);
    return adjusted.clamp(baseGoal * 0.75, baseGoal * 1.25);
  }
}
