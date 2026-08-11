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
  /// [daysElapsed]   Days already accounted for in the *tracked* week. `null`
  ///                 reproduces the legacy full calendar week (`7 − daysLeft`),
  ///                 so pre-existing callers and tests are unaffected.
  ///                 `ProfileProvider` passes the number of days that actually
  ///                 have logs: a day with no data is missing data, not a
  ///                 zero-intake day, and counting it would read as a full
  ///                 shortfall and inflate today's goal.
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
