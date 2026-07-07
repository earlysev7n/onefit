// Unit tests for WeeklyAdaptiveGoal.adjust.
// Run with `flutter test test/weekly_adaptive_goal_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/weekly_adaptive_goal.dart';

void main() {
  group('WeeklyAdaptiveGoal.adjust', () {
    // Monday with no logs yet: remaining = base×7, target = base×7/7 = base.
    test('Monday with no logs returns base exactly', () {
      expect(
        WeeklyAdaptiveGoal.adjust(base: 2000, weekConsumed: 0, daysLeft: 7),
        2000.0,
      );
    });

    // Within-clamp adjustment: light under-eating gives a proportional increase.
    test('light under-eating gives a proportional target increase', () {
      // 2 days done, consumed 3500 (expected 4000). 5 days left.
      // remaining = 14000 − 3500 = 10500; target = 10500/5 = 2100 (+5%, within ±10%).
      expect(
        WeeklyAdaptiveGoal.adjust(base: 2000, weekConsumed: 3500, daysLeft: 5),
        closeTo(2100.0, 0.01),
      );
    });

    // Under-eating so severe that the raw target exceeds +10% → clamped.
    test('severe under-eating is clamped to +10% of base', () {
      // 2 days done, consumed only 1000. 5 days left.
      // remaining = 13000; target = 2600 (+30%) → clamped to 2200.
      expect(
        WeeklyAdaptiveGoal.adjust(base: 2000, weekConsumed: 1000, daysLeft: 5),
        2200.0,
      );
    });

    // Light over-eating gives a proportional decrease.
    test('light over-eating gives a proportional target decrease', () {
      // 2 days done, consumed 4500 (expected 4000). 5 days left.
      // remaining = 14000 − 4500 = 9500; target = 9500/5 = 1900 (−5%, within ±10%).
      expect(
        WeeklyAdaptiveGoal.adjust(base: 2000, weekConsumed: 4500, daysLeft: 5),
        closeTo(1900.0, 0.01),
      );
    });

    // Severe over-eating → clamped to −10%.
    test('severe over-eating is clamped to −10% of base', () {
      // 2 days done, consumed 9000. 5 days left.
      // remaining = 5000; target = 1000 (−50%) → clamped to 1800.
      expect(
        WeeklyAdaptiveGoal.adjust(base: 2000, weekConsumed: 9000, daysLeft: 5),
        1800.0,
      );
    });

    // Week already over the total weekly goal.
    test('week already over goal returns the −10% floor', () {
      // Consumed 16000 of 14000 weekly budget with 3 days left.
      // remaining = −2000; target = −666 → clamped to 1800.
      expect(
        WeeklyAdaptiveGoal.adjust(base: 2000, weekConsumed: 16000, daysLeft: 3),
        1800.0,
      );
    });

    // Last day (Sunday): absorbs whatever is left, clamped.
    test('last day absorbs all remaining, still clamped', () {
      // Consumed 11 000 of 14 000; 1 day left → target = 3000 → clamped to 2200.
      expect(
        WeeklyAdaptiveGoal.adjust(base: 2000, weekConsumed: 11000, daysLeft: 1),
        2200.0,
      );
      // Exactly on track with 1 day left → target = 2000 → no clamp needed.
      expect(
        WeeklyAdaptiveGoal.adjust(base: 2000, weekConsumed: 12000, daysLeft: 1),
        2000.0,
      );
    });

    // daysLeft ≤ 0 guard: should never happen, but never crashes.
    test('daysLeft ≤ 0 returns base unchanged', () {
      expect(
        WeeklyAdaptiveGoal.adjust(base: 2000, weekConsumed: 5000, daysLeft: 0),
        2000.0,
      );
      expect(
        WeeklyAdaptiveGoal.adjust(base: 2000, weekConsumed: 5000, daysLeft: -1),
        2000.0,
      );
    });

    // The clamp ceiling is ±10% — NOT the old DailyCarry ±25%.
    test('clamp ceiling is +10% of base, not +25%', () {
      // Zero consumption, 3 days left → target = 14000/3 ≈ 4667 → clamped to 2200.
      // If clamp were 25%, ceiling would be 2500. Verify it is NOT 2500.
      final result = WeeklyAdaptiveGoal.adjust(
        base: 2000,
        weekConsumed: 0,
        daysLeft: 3,
      );
      expect(result, 2200.0); // +10% ceiling
      expect(result, isNot(2500.0)); // not the old +25% ceiling
    });

    // Custom clamp percentage.
    test('custom clamp parameter is respected', () {
      // 5% clamp ceiling: 2000 × 1.05 = 2100.
      expect(
        WeeklyAdaptiveGoal.adjust(
          base: 2000,
          weekConsumed: 0,
          daysLeft: 3,
          clamp: 0.05,
        ),
        2100.0,
      );
      // 20% clamp: raw target = 14000/3 ≈ 4667 → clamped to 2000×1.20 = 2400.
      expect(
        WeeklyAdaptiveGoal.adjust(
          base: 2000,
          weekConsumed: 0,
          daysLeft: 3,
          clamp: 0.20,
        ),
        2400.0,
      );
    });

    // Regression: a brand-new account created mid-week must NOT be inflated.
    // Before the fix, base×7/6 clamped to +10% (3079 → 3387). With daysElapsed:0
    // the tracked budget is base×6, so today's target is exactly base.
    test('new account mid-week (daysElapsed:0) returns base, not inflated', () {
      expect(
        WeeklyAdaptiveGoal.adjust(
          base: 3079,
          weekConsumed: 0,
          daysLeft: 6,
          daysElapsed: 0,
        ),
        3079.0,
      );
    });

    // Back-compat: omitting daysElapsed reproduces the legacy full-week (base×7)
    // budget, so existing callers/tests are unaffected.
    test('omitting daysElapsed matches legacy base×7 behaviour', () {
      // Legacy: base×7 − 0 over 6 days = 3592 → clamped to +10% = 2200 at base 2000.
      final legacy =
          WeeklyAdaptiveGoal.adjust(base: 2000, weekConsumed: 0, daysLeft: 6);
      final explicit = WeeklyAdaptiveGoal.adjust(
        base: 2000,
        weekConsumed: 0,
        daysLeft: 6,
        daysElapsed: 7 - 6, // == default
      );
      expect(legacy, explicit);
      expect(legacy, 2200.0);
    });

    // Active user part-way through a fully-tracked week still gets catch-up.
    // 2 elapsed days, consumed 3500 (expected 4000), 5 left → target 2100 (+5%).
    test('active user with daysElapsed still catches up correctly', () {
      expect(
        WeeklyAdaptiveGoal.adjust(
          base: 2000,
          weekConsumed: 3500,
          daysLeft: 5,
          daysElapsed: 2,
        ),
        closeTo(2100.0, 0.01),
      );
    });

    // Works correctly for macro-sized bases (protein grams, not kcal).
    test('formula works for macro gram targets (small base values)', () {
      // base=150g protein, consumed 200g in 2 days (over), 5 left.
      // remaining = 1050−200 = 850; target = 850/5 = 170 → +13% → clamped to 165.
      expect(
        WeeklyAdaptiveGoal.adjust(
          base: 150,
          weekConsumed: 200,
          daysLeft: 5,
        ),
        closeTo(165.0, 0.01),
      );
    });
  });
}
