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

// 3-day plan: Mon, Wed, Fri are workout days; Tue, Thu, Sat, Sun are rest.
final threeDayPlan = [true, false, true, false, true, false, false];

// Every day is a workout day.
final sevenDayPlan = List.filled(7, true);

void main() {
  // Wednesday 2026-08-26 (weekday 3)
  final wed = DateTime(2026, 8, 26);
  final tue = wed.subtract(const Duration(days: 1));
  final mon = wed.subtract(const Duration(days: 2));

  group('WorkoutStreak.days — basic', () {
    test('no logs → 0', () {
      expect(WorkoutStreak.days([], workoutDays: threeDayPlan, now: wed), 0);
    });

    test('no workout days in pattern → 0', () {
      expect(
        WorkoutStreak.days([_log(wed)],
            workoutDays: List.filled(7, false), now: wed),
        0,
      );
    });

    test('workout on a workout day → streak = 1', () {
      expect(
        WorkoutStreak.days([_log(mon)],
            workoutDays: threeDayPlan, now: mon, startDate: mon),
        1,
      );
    });

    test('rest day after workout keeps streak', () {
      // Mon workout done, now Tue (rest day). Started Mon.
      expect(
        WorkoutStreak.days([_log(mon)],
            workoutDays: threeDayPlan, now: tue, startDate: mon),
        2, // Mon + Tue
      );
    });

    test('missed workout day breaks streak', () {
      // Mon workout, Tue rest, Wed is workout day — no log.
      // Check on Thursday (rest day): Wed missed → break.
      final thu = wed.add(const Duration(days: 1));
      expect(
        WorkoutStreak.days([_log(mon)],
            workoutDays: threeDayPlan, now: thu, startDate: mon),
        0, // only Thu (rest), but no workout in run → 0
      );
    });

    test('today is an incomplete workout day — skipped, not a break', () {
      // Mon workout done. Now Wed (workout day), no log yet. Started Mon.
      // Streak should be 2 (Mon + Tue), Wed skipped.
      expect(
        WorkoutStreak.days([_log(mon)],
            workoutDays: threeDayPlan, now: wed, startDate: mon),
        2,
      );
    });

    test('today is a completed workout day — counted', () {
      // Mon + Wed done. Started Mon.
      expect(
        WorkoutStreak.days([_log(mon), _log(wed)],
            workoutDays: threeDayPlan, now: wed, startDate: mon),
        3, // Mon + Tue(rest) + Wed
      );
    });

    test('rest days alone do not start a streak', () {
      // Sat and Sun are rest days. No workouts at all.
      final sunday = DateTime(2026, 8, 30);
      expect(
        WorkoutStreak.days([], workoutDays: threeDayPlan, now: sunday),
        0,
      );
    });
  });

  group('WorkoutStreak.days — multi-week', () {
    test('streak spans weeks when all workout days are completed', () {
      // Previous week: Mon/Wed/Fri all done. This week: Mon done.
      // Now is Tue (rest day).
      final prevMon = mon.subtract(const Duration(days: 7));
      final prevWed = prevMon.add(const Duration(days: 2));
      final prevFri = prevMon.add(const Duration(days: 4));
      final logs = [_log(prevMon), _log(prevWed), _log(prevFri), _log(mon)];
      expect(
        WorkoutStreak.days(logs,
            workoutDays: threeDayPlan, now: tue, startDate: prevMon),
        9, // prevMon through Tue = 9 days
      );
    });

    test('missed workout last week breaks streak at that point', () {
      // Last week: Mon done, Wed MISSED, Fri done. This week: Mon done, now Tue.
      final prevMon = mon.subtract(const Duration(days: 7));
      final prevFri = prevMon.add(const Duration(days: 4));
      final logs = [_log(prevMon), _log(prevFri), _log(mon)];
      // Walking back from Tue: Tue(rest), Mon(done), Sun(rest), Sat(rest),
      // Fri(done), Thu(rest), Wed(MISSED) → break.
      // Count: Tue+Mon+Sun+Sat+Fri+Thu = 6 days (has workout).
      expect(
        WorkoutStreak.days(logs,
            workoutDays: threeDayPlan, now: tue, startDate: prevMon),
        6,
      );
    });
  });

  group('WorkoutStreak.days — every day plan', () {
    test('missed yesterday resets to 0 if today not done', () {
      // 7-day plan. Yesterday no log, today no log.
      expect(
        WorkoutStreak.days([], workoutDays: sevenDayPlan, now: wed, startDate: mon),
        0,
      );
    });

    test('consecutive workouts count', () {
      expect(
        WorkoutStreak.days([_log(mon), _log(tue), _log(wed)],
            workoutDays: sevenDayPlan, now: wed, startDate: mon),
        3,
      );
    });

    test('gap yesterday breaks it', () {
      // Mon done, Tue missed, Wed done.
      expect(
        WorkoutStreak.days([_log(mon), _log(wed)],
            workoutDays: sevenDayPlan, now: wed, startDate: mon),
        1, // only Wed
      );
    });
  });

  group('WorkoutStreak.days — startDate clamp', () {
    test('first day with a workout → 1', () {
      expect(
        WorkoutStreak.days([_log(wed)],
            workoutDays: threeDayPlan, now: wed, startDate: wed),
        1,
      );
    });

    test('startDate stops the backward scan', () {
      // Started Tuesday. Now Wed (workout done). Tue is rest.
      // Streak = 2 (Tue + Wed).
      expect(
        WorkoutStreak.days([_log(wed)],
            workoutDays: threeDayPlan, now: wed, startDate: tue),
        2,
      );
    });

    test('startDate before a missed day still breaks', () {
      // Started long ago. This week: Mon done, Wed missed (no log).
      // Now Thu (rest). Walking back: Thu(rest), Wed(missed) → break.
      // No workout in run → 0.
      final thu = wed.add(const Duration(days: 1));
      final startedLong = mon.subtract(const Duration(days: 14));
      expect(
        WorkoutStreak.days([_log(mon)],
            workoutDays: threeDayPlan, now: thu, startDate: startedLong),
        0,
      );
    });
  });

  group('WorkoutStreak.days — no startDate (uses earliest log)', () {
    test('single workout without startDate → 1', () {
      expect(
        WorkoutStreak.days([_log(mon)], workoutDays: threeDayPlan, now: mon),
        1,
      );
    });

    test('workout with rest days between uses earliest log as floor', () {
      // Mon workout. Now Tue. No startDate → floor is Mon (earliest log).
      expect(
        WorkoutStreak.days([_log(mon)], workoutDays: threeDayPlan, now: tue),
        2,
      );
    });
  });
}
