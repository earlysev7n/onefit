// Pins the shared ±5% calorie tolerance band (NASEM 2023 measurement error).
// Every consumer reads these numbers: the daily status chip, the daily
// redistribution in ProfileProvider, the weekly AdaptationEngine calorie branch
// and the Weekly Review labels — so a change here is a change everywhere.

import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/calorie_tolerance.dart';

void main() {
  const target = 3000.0; // band = ±150 kcal -> 2850..3150

  group('band math', () {
    test('band/lower/upper for a 3000 kcal target', () {
      expect(CalorieTolerance.bandKcal(target), 150);
      expect(CalorieTolerance.lower(target), 2850);
      expect(CalorieTolerance.upper(target), 3150);
    });

    test('percent edges match the fraction', () {
      expect(CalorieTolerance.fraction, 0.05);
      expect(CalorieTolerance.lowerPct, 95.0);
      expect(CalorieTolerance.upperPct, 105.0);
    });
  });

  group('within', () {
    test('both edges are inclusive', () {
      expect(CalorieTolerance.within(2850, target), isTrue);
      expect(CalorieTolerance.within(3150, target), isTrue);
    });

    test('just outside either edge is a real deviation', () {
      expect(CalorieTolerance.within(2849.9, target), isFalse);
      expect(CalorieTolerance.within(3150.1, target), isFalse);
    });

    test('dead centre and typical noise are on target', () {
      expect(CalorieTolerance.within(3000, target), isTrue);
      expect(CalorieTolerance.within(2920, target), isTrue);
      expect(CalorieTolerance.within(3080, target), isTrue);
    });

    test('a non-positive target has no meaningful band', () {
      expect(CalorieTolerance.within(0, 0), isFalse);
      expect(CalorieTolerance.within(100, -1), isFalse);
    });

    test('an unlogged (0 kcal) day is outside the band', () {
      expect(CalorieTolerance.within(0, target), isFalse);
    });
  });

  group('withinPct', () {
    test('95–105 inclusive is on target', () {
      expect(CalorieTolerance.withinPct(95.0), isTrue);
      expect(CalorieTolerance.withinPct(100.0), isTrue);
      expect(CalorieTolerance.withinPct(105.0), isTrue);
    });

    test('outside 95–105 is not', () {
      expect(CalorieTolerance.withinPct(94.9), isFalse);
      expect(CalorieTolerance.withinPct(105.1), isFalse);
    });
  });

  group('deviation', () {
    test('is zero inside the band — noise is not redistributed', () {
      expect(CalorieTolerance.deviation(2900, target), 0);
      expect(CalorieTolerance.deviation(3150, target), 0);
    });

    test('is the full signed distance from target once meaningful', () {
      expect(CalorieTolerance.deviation(2500, target), -500);
      expect(CalorieTolerance.deviation(3500, target), 500);
    });
  });

  group('effectiveWeekConsumed', () {
    test('in-band days are booked at base — zero net deviation', () {
      // 3 noisy-but-on-target days should look exactly like 3 perfect days.
      final consumed = CalorieTolerance.effectiveWeekConsumed(
        const [2900.0, 3050.0, 2860.0],
        target,
      );
      expect(consumed, 3 * target);
    });

    test('out-of-band days keep their real total', () {
      final consumed = CalorieTolerance.effectiveWeekConsumed(
        const [2900.0, 2000.0],
        target,
      );
      // 2900 -> 3000 (in band), 2000 stays 2000.
      expect(consumed, 5000);
    });

    test('empty week consumes nothing', () {
      expect(
        CalorieTolerance.effectiveWeekConsumed(const <double>[], target),
        0,
      );
    });
  });

  group('shouldAnnounceGoalShift', () {
    // Regression: the trigger is the BREACH, not the size of the nudge.
    // Tue came in 212 kcal under a 2298 goal (9.2% — a real breach); spread
    // over the 6 remaining days that is only +35 on Wednesday (1.5%). Gating on
    // the nudge kept this silent, which is the bug.
    test('a breach announces even when the resulting nudge is tiny', () {
      expect(
        CalorieTolerance.shouldAnnounceGoalShift(
          daysOutOfTolerance: 1,
          adjusted: 2333,
          base: 2298,
        ),
        isTrue,
      );
      // ...and that nudge is indeed inside the band, proving the old gate blocked it.
      expect(CalorieTolerance.within(2333, 2298), isTrue);
    });

    test('no breached day → nothing to announce', () {
      expect(
        CalorieTolerance.shouldAnnounceGoalShift(
          daysOutOfTolerance: 0,
          adjusted: 2333,
          base: 2298,
        ),
        isFalse,
      );
    });

    test('a breach that left the goal unmoved → nothing to announce', () {
      // e.g. an over-day and an under-day cancelling out.
      expect(
        CalorieTolerance.shouldAnnounceGoalShift(
          daysOutOfTolerance: 2,
          adjusted: 2298,
          base: 2298,
        ),
        isFalse,
      );
    });
  });

  group('daysInTolerance', () {
    test('counts only days inside the band', () {
      expect(
        CalorieTolerance.daysInTolerance(
          const [2900.0, 3150.0, 3200.0, 2000.0, 3000.0],
          target,
        ),
        3,
      );
    });

    test('is 0 for an empty week', () {
      expect(CalorieTolerance.daysInTolerance(const <double>[], target), 0);
    });
  });
}
