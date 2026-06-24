// Verifies the rule-based daily calorie carry-forward arithmetic in isolation.
// Pure Dart — run with `flutter test test/daily_carry_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/daily_carry.dart';

void main() {
  group('DailyCarry.dailyAdjustedGoal', () {
    test('overate yesterday → target cut by half the surplus', () {
      // 2500 logged on a 2000 goal → surplus 500 → 2000 − 250 = 1750.
      expect(
        DailyCarry.dailyAdjustedGoal(baseGoal: 2000, yesterdayLogged: 2500),
        1750,
      );
    });

    test('underate yesterday → target raised by half the deficit', () {
      // 1500 logged → surplus −500 → 2000 + 250 = 2250.
      expect(
        DailyCarry.dailyAdjustedGoal(baseGoal: 2000, yesterdayLogged: 1500),
        2250,
      );
    });

    test('exact target → unchanged', () {
      expect(
        DailyCarry.dailyAdjustedGoal(baseGoal: 2000, yesterdayLogged: 2000),
        2000,
      );
    });

    test('extreme overshoot clamps to 75% of goal', () {
      // 4000 logged → surplus 2000 → 1000, clamped up to 1500.
      expect(
        DailyCarry.dailyAdjustedGoal(baseGoal: 2000, yesterdayLogged: 4000),
        1500,
      );
    });

    test('extreme undershoot clamps to 125% of goal', () {
      // 0 logged → surplus −2000 → 3000, clamped down to 2500.
      expect(
        DailyCarry.dailyAdjustedGoal(baseGoal: 2000, yesterdayLogged: 0),
        2500,
      );
    });

    test('no data (null) → goal unchanged', () {
      expect(
        DailyCarry.dailyAdjustedGoal(baseGoal: 2000, yesterdayLogged: null),
        2000,
      );
    });

    test('small overshoot → smooth small adjustment', () {
      // 2050 → surplus 50 → 1975.
      expect(
        DailyCarry.dailyAdjustedGoal(baseGoal: 2000, yesterdayLogged: 2050),
        1975,
      );
    });

    test('carryFraction is tunable (full carry)', () {
      expect(
        DailyCarry.dailyAdjustedGoal(
          baseGoal: 2000,
          yesterdayLogged: 2500,
          carryFraction: 1.0,
        ),
        1500,
      );
    });

    test('half-carry converges over consecutive days (no yo-yo)', () {
      // Day 1 overate 500. Each subsequent day the user logs exactly the
      // previous day's target; the error should shrink, not flip-flop wildly.
      var goal = DailyCarry.dailyAdjustedGoal(
          baseGoal: 2000, yesterdayLogged: 2500); // 1750
      goal = DailyCarry.dailyAdjustedGoal(
          baseGoal: 2000, yesterdayLogged: goal); // logged 1750 → 2125
      goal = DailyCarry.dailyAdjustedGoal(
          baseGoal: 2000, yesterdayLogged: goal); // logged 2125 → 1937.5
      // Third-day target is within 65 kcal of the true goal — converging.
      expect((goal - 2000).abs(), lessThan(65));
    });
  });
}
