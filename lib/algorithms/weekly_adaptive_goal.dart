/// Rule-based weekly calorie/macro redistribution.
///
/// Spreads the week's remaining nutrient budget across the remaining days so
/// the user hits their **weekly** goal even after over- or under-eating on
/// earlier days. Applied independently to calories, protein, carbs and fat.
///
/// Pure Dart — no Flutter or Firebase dependencies.
class WeeklyAdaptiveGoal {
  /// Returns today's adaptive daily target for one nutrient.
  ///
  /// [base]          Daily base goal from the user's profile (never modified).
  /// [weekConsumed]  Total amount of this nutrient logged over the elapsed days.
  /// [daysLeft]      Calendar days remaining in the week, including today (1–7).
  /// [daysElapsed]   Days already passed in the *tracked* week (i.e. since the
  ///                 later of Monday and account creation). `null` reproduces the
  ///                 legacy full calendar week (`7 − daysLeft`), so pre-existing
  ///                 callers and tests are unaffected. Anchoring to account
  ///                 creation stops pre-account days being read as under-eaten,
  ///                 which used to inflate a brand-new user's day-one goal.
  /// [clamp]         Max allowed deviation from [base] as a fraction (default
  ///                 0.10 = ±10%). The result is always in
  ///                 `[base*(1−clamp), base*(1+clamp)]`.
  ///
  /// Formula:
  ///   totalDays = (daysElapsed ?? 7 − daysLeft) + daysLeft   // tracked week span
  ///   remaining = base × totalDays − weekConsumed
  ///   target    = remaining / daysLeft
  ///   result    = target.clamp(base × (1 − clamp), base × (1 + clamp))
  ///
  /// Returns [base] unchanged when [daysLeft] ≤ 0 (safety guard — this should
  /// never occur in production since the week has at least today left).
  static double adjust({
    required double base,
    required double weekConsumed,
    required int daysLeft,
    int? daysElapsed,
    double clamp = 0.10,
  }) {
    if (daysLeft <= 0) return base;
    final totalDays = (daysElapsed ?? (7 - daysLeft)) + daysLeft;
    final remaining = base * totalDays - weekConsumed;
    final target = remaining / daysLeft;
    return target.clamp(base * (1 - clamp), base * (1 + clamp));
  }
}
