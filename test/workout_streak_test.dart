import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/workout_streak.dart';
import 'package:onefit/models/workout_log.dart';

WorkoutLog _log(DateTime d) => WorkoutLog(
      id: 'x',
      userId: 'u',
      date: d,
      weekId: '',
      dayName: '',
      focus: '',
      durationMinutes: 0,
      completedAt: d,
      exercises: const [],
    );

void main() {
  // A fixed reference "today". Monday of its week and the elapsed-day count are
  // derived from it so the assertions never hard-code a weekday by hand.
  final now = DateTime(2026, 8, 26, 12); // some weekday
  final mondayThis = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  final elapsedThisWeek = now.weekday; // Mon = 1 … today

  DateTime weekMon(int weeksAgo) => mondayThis.subtract(Duration(days: 7 * weeksAgo));

  group('WorkoutStreak.days', () {
    test('no logs → 0', () {
      expect(WorkoutStreak.days([], plannedPerWeek: 3, now: now), 0);
    });

    test('no plan (0/week) → 0 even with logs', () {
      expect(
        WorkoutStreak.days([_log(now)], plannedPerWeek: 0, now: now),
        0,
      );
    });

    test('one workout this week, no history → days elapsed this week', () {
      final streak = WorkoutStreak.days(
        [_log(mondayThis)],
        plannedPerWeek: 3,
        now: now,
      );
      expect(streak, elapsedThisWeek);
    });

    test('rest-day gaps within the week do not break the streak', () {
      // Logged Mon and Wed only (Tue is a rest/gap day), planned 3.
      final streak = WorkoutStreak.days(
        [_log(mondayThis), _log(mondayThis.add(const Duration(days: 2)))],
        plannedPerWeek: 3,
        now: now,
      );
      expect(streak, elapsedThisWeek); // still counts every day this week
    });

    test('two prior full weeks + this week span across weeks', () {
      final logs = <WorkoutLog>[
        // this week: 1 done so far
        _log(mondayThis),
        // last week: 3 (on plan)
        _log(weekMon(1)),
        _log(weekMon(1).add(const Duration(days: 2))),
        _log(weekMon(1).add(const Duration(days: 4))),
        // two weeks ago: 3 (on plan)
        _log(weekMon(2)),
        _log(weekMon(2).add(const Duration(days: 2))),
        _log(weekMon(2).add(const Duration(days: 4))),
        // three weeks ago: nothing → run stops here
      ];
      expect(
        WorkoutStreak.days(logs, plannedPerWeek: 3, now: now),
        2 * 7 + elapsedThisWeek,
      );
    });

    test('a finished week that fell short resets the streak', () {
      final logs = <WorkoutLog>[
        // this week: 2 done
        _log(mondayThis),
        _log(mondayThis.add(const Duration(days: 1))),
        // last week: only 2 (missed the plan of 3) → breaks the run
        _log(weekMon(1)),
        _log(weekMon(1).add(const Duration(days: 2))),
        // two weeks ago: 3 (irrelevant — run already broke at last week)
        _log(weekMon(2)),
        _log(weekMon(2).add(const Duration(days: 2))),
        _log(weekMon(2).add(const Duration(days: 4))),
      ];
      expect(
        WorkoutStreak.days(logs, plannedPerWeek: 3, now: now),
        elapsedThisWeek, // only the current week's days
      );
    });

    test('nothing this week yet but prior week on plan → streak continues', () {
      final logs = <WorkoutLog>[
        // this week: none yet (in progress, not a miss)
        // last week: 3 (on plan)
        _log(weekMon(1)),
        _log(weekMon(1).add(const Duration(days: 2))),
        _log(weekMon(1).add(const Duration(days: 4))),
      ];
      expect(
        WorkoutStreak.days(logs, plannedPerWeek: 3, now: now),
        1 * 7 + elapsedThisWeek,
      );
    });
  });

  group('WorkoutStreak.days — start-date clamp', () {
    // Monday/Wednesday derived from a base date so the assertions don't depend on
    // the base date's weekday.
    final base = DateTime(2026, 8, 26, 12);
    final monday = DateTime(base.year, base.month, base.day)
        .subtract(Duration(days: base.weekday - 1));
    final wednesday = monday.add(const Duration(days: 2));

    test('first day (startDate == today) with a workout logged → 1', () {
      expect(
        WorkoutStreak.days([_log(wednesday)],
            plannedPerWeek: 3, now: wednesday, startDate: wednesday),
        1,
      );
    });

    test('startDate mid-week counts only from the start date', () {
      // Created Monday, today Wednesday, workout done → Mon, Tue, Wed = 3.
      expect(
        WorkoutStreak.days([_log(wednesday)],
            plannedPerWeek: 3, now: wednesday, startDate: monday),
        3,
      );
    });

    test('startDate in a prior week does not clamp the current week', () {
      final logs = <WorkoutLog>[
        _log(wednesday), // this week
        for (int i = 0; i < 3; i++)
          _log(monday.subtract(Duration(days: 7 - i))), // last week: Mon/Tue/Wed
        for (int i = 0; i < 3; i++)
          _log(monday.subtract(Duration(days: 14 - i))), // two weeks ago
      ];
      final created = monday.subtract(const Duration(days: 21));
      expect(
        WorkoutStreak.days(logs,
            plannedPerWeek: 3, now: wednesday, startDate: created),
        2 * 7 + 3, // two prior on-plan weeks + Mon..Wed
      );
    });
  });
}
