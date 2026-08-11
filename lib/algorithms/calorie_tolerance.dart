/// Shared ±5% calorie tolerance band — the single source of truth for what
/// counts as "on target" anywhere in the app.
///
/// Rationale: dietary assessment methods carry measurement error, so reported
/// or estimated energy intake differs from a person's actual intake (National
/// Academies of Sciences, Engineering, and Medicine, 2023). A small gap between
/// logged intake and the daily target is therefore measurement noise, not a
/// meaningful deviation, and should not trigger feedback or an adjustment.
///
/// Every threshold that asks "is this intake on target?" reads from here — the
/// daily ring status, the weekly-budget redistribution, the weekly
/// [AdaptationEngine] calorie branch and the Weekly Review labels — so the four
/// can never disagree.
///
/// Pure Dart — no Flutter or Firebase dependencies.
class CalorieTolerance {
  /// Half-width of the band as a fraction of target (±5%).
  static const double fraction = 0.05;

  /// Percent-scale edges, for callers that work in adherence % rather than kcal.
  static const double lowerPct = (1 - fraction) * 100; // 95.0
  static const double upperPct = (1 + fraction) * 100; // 105.0

  /// Tolerance in kcal for [target] (e.g. 3000 → 150).
  static double bandKcal(num target) => target * fraction;

  /// Lowest intake still on target (e.g. 3000 → 2850).
  static double lower(num target) => target * (1 - fraction);

  /// Highest intake still on target (e.g. 3000 → 3150).
  static double upper(num target) => target * (1 + fraction);

  /// Whether [consumed] is within the band around [target]. Both edges are
  /// inclusive — exactly 2850 and exactly 3150 are on target for a 3000 goal.
  /// A non-positive target has no meaningful band.
  static bool within(num consumed, num target) {
    if (target <= 0) return false;
    return consumed >= lower(target) && consumed <= upper(target);
  }

  /// Whether an adherence percentage (intake / target × 100) is on target.
  static bool withinPct(double pct) => pct >= lowerPct && pct <= upperPct;

  /// Signed deviation in kcal that actually counts: 0 inside the band,
  /// otherwise the full distance from [target] (negative = under, positive =
  /// over). Reporting the distance from target — not from the band edge — keeps
  /// redistribution arithmetic exact once a day is deemed meaningful.
  static double deviation(num consumed, num target) =>
      within(consumed, target) ? 0 : (consumed - target).toDouble();

  /// Tolerance-normalised weekly total for redistribution: a day inside the
  /// band is booked as exactly [base] (contributing zero deviation), a day
  /// outside contributes its real total. Feeding this to
  /// [WeeklyAdaptiveGoal.adjust] means only meaningful deviations get spread
  /// across the remaining days.
  static double effectiveWeekConsumed(
    Iterable<double> dailyTotals,
    double base,
  ) {
    var sum = 0.0;
    for (final day in dailyTotals) {
      sum += within(day, base) ? base : day;
    }
    return sum;
  }

  /// How many of [dailyTotals] landed inside the band around [base].
  static int daysInTolerance(Iterable<double> dailyTotals, double base) =>
      dailyTotals.where((d) => within(d, base)).length;

  /// Whether to announce that today's goal was re-balanced.
  ///
  /// The trigger is **a day that breached the band**, not the size of the
  /// resulting nudge: a real breach is diluted across the remaining days by
  /// construction (212 kcal over 6 days is only +35/day), so gating on the
  /// nudge would stay silent for exactly the weeks that matter most.
  static bool shouldAnnounceGoalShift({
    required int daysOutOfTolerance,
    required int adjusted,
    required int base,
  }) => daysOutOfTolerance > 0 && adjusted != base;
}
