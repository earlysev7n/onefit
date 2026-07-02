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
  /// [weekConsumed]  Total amount of this nutrient logged since Monday.
  /// [daysLeft]      Calendar days remaining in the week, including today (1–7).
  /// [clamp]         Max allowed deviation from [base] as a fraction (default
  ///                 0.10 = ±10%). The result is always in
  ///                 `[base*(1−clamp), base*(1+clamp)]`.
  ///
  /// Formula:
  ///   remaining = base × 7 − weekConsumed
  ///   target    = remaining / daysLeft
  ///   result    = target.clamp(base × (1 − clamp), base × (1 + clamp))
  ///
  /// Returns [base] unchanged when [daysLeft] ≤ 0 (safety guard — this should
  /// never occur in production since the week has at least today left).
  static double adjust({
    required double base,
    required double weekConsumed,
    required int daysLeft,
    double clamp = 0.10,
  }) {
    if (daysLeft <= 0) return base;
    final remaining = base * 7 - weekConsumed;
    final target = remaining / daysLeft;
    return target.clamp(base * (1 - clamp), base * (1 + clamp));
  }
}
