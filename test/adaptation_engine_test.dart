// Source of truth for the question: "does one under-goal day flag the whole
// week?" Answer: NO. Calorie adherence is an AVERAGE over logged days, gated on
// >=4 logged days, and only adherence OUTSIDE the shared ±5% CalorieTolerance
// band (95–105%) nudges calories. A single -200 kcal day surrounded by
// on-target days averages to ~97.5%, lands inside the band, and triggers
// nothing. These tests pin that behavior against future regressions.
//
// Behavior mirrored here:
//   - AdaptationEngine.compute thresholds  -> lib/algorithms/adaptation_engine.dart (calorie branch)
//   - the ±5% band itself                  -> lib/algorithms/calorie_tolerance.dart
//   - adherence formula (avg logged / goal)-> lib/providers/progress_provider.dart:209-218
//   - >=4-day gate (else neutral 100.0)    -> lib/screens/plans_screen.dart (nutrition gate)

import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/adaptation_engine.dart';
import 'package:onefit/algorithms/calorie_tolerance.dart';

/// Replicates the adherence pipeline that lives in Firebase/widget-coupled code
/// (progress_provider + plans_screen) so it can be unit-tested purely.
///
/// If either cited source formula changes, update this helper to match.
double adherencePct(List<int> loggedCalsPerDay, int goal) {
  // plans_screen.dart:624-630 — sparse logging is untrustworthy; <4 logged days
  // reads as neutral (100%) so it never triggers a real adjustment.
  if (loggedCalsPerDay.length < 4) return 100.0;
  // progress_provider.dart:209-218 — average over LOGGED days, /goal*100, clamp.
  final avg =
      loggedCalsPerDay.reduce((a, b) => a + b) / loggedCalsPerDay.length;
  return (avg / goal * 100).clamp(0, 200).toDouble();
}

void main() {
  final engine = AdaptationEngine();

  // Isolate the calorie branch: perfect completion + Beginner + no ratings/weight
  // means only lastWeekCalorieAdherence decides calorieBiasKcal.
  AdaptationResult onCalories(double adherence, {String goal = 'General Fitness'}) =>
      engine.compute(
        lastWeekCalorieAdherence: adherence,
        lastWeekWorkoutCompletion: 1.0,
        currentExperienceLevel: 'Beginner',
        fitnessGoal: goal,
      );

  group('AdaptationEngine calorie thresholds', () {
    test('97.5% (one diluted under-day) -> no change, no "under" note', () {
      final r = onCalories(97.5);
      expect(r.calorieBiasKcal, 0);
      expect(r.notes.toLowerCase(), isNot(contains('under')));
    });

    test('82.5% (consistently under) -> +100 kcal with "under" note', () {
      final r = onCalories(82.5);
      expect(r.calorieBiasKcal, 100);
      expect(r.notes.toLowerCase(), contains('under'));
    });

    test('lower tolerance edge: 95.0 holds, 94.9 nudges up', () {
      expect(onCalories(CalorieTolerance.lowerPct).calorieBiasKcal, 0);
      expect(onCalories(94.9).calorieBiasKcal, 100);
    });

    test('upper tolerance edge: 105.0 holds, 105.1 cuts', () {
      expect(onCalories(CalorieTolerance.upperPct).calorieBiasKcal, 0);
      // General Fitness (not Weight Loss) so there is no "still losing" hold.
      expect(onCalories(105.1).calorieBiasKcal, -100);
    });

    test('the whole band is a dead zone — measurement noise moves nothing', () {
      for (final pct in const [95.0, 97.5, 100.0, 102.0, 105.0]) {
        expect(onCalories(pct).calorieBiasKcal, 0, reason: '$pct% should hold');
      }
    });
  });

  group('adherence averaging + >=4-day gate feeding the engine', () {
    test('Mon 1800 / Tue 2000 / Wed 2000 (3 days) -> gated neutral, no change', () {
      // The user's exact scenario. Only 3 logged days -> gate forces 100.0.
      final pct = adherencePct(const [1800, 2000, 2000], 2000);
      expect(pct, 100.0);
      expect(onCalories(pct).calorieBiasKcal, 0);
    });

    test('one -200 day among 4 on-target days -> 97.5%, diluted, no flag', () {
      final pct = adherencePct(const [1800, 2000, 2000, 2000], 2000);
      expect(pct, 97.5);
      final r = onCalories(pct);
      expect(r.calorieBiasKcal, 0);
      expect(r.notes.toLowerCase(), isNot(contains('under')));
    });

    test('consistently ~300 under (4 days @ 1650) -> 82.5%, flags "under"', () {
      final pct = adherencePct(const [1650, 1650, 1650, 1650], 2000);
      expect(pct, 82.5);
      expect(onCalories(pct).calorieBiasKcal, 100);
    });
  });
}
