import '../models/workout_log.dart';

/// Consecutive-day workout streak calculator.
///
/// Walks backwards from today counting consecutive days. A rest day (not
/// scheduled for a workout) never breaks the streak. A workout day without
/// a completed [WorkoutLog] breaks it. Today is given grace: if it is a
/// workout day the user hasn't completed yet, it is skipped (the day isn't
/// over). The streak is 0 when no completed workout day exists in the run
/// (leading rest days alone don't start a streak).
class WorkoutStreak {
  const WorkoutStreak._();

  static int days(
    List<WorkoutLog> logs, {
    required List<bool> workoutDays,
    required DateTime now,
    DateTime? startDate,
  }) {
    if (workoutDays.length != 7 || !workoutDays.contains(true)) return 0;

    final today = DateTime(now.year, now.month, now.day);
    final logDates = <DateTime>{};
    for (final l in logs) {
      logDates.add(DateTime(l.date.year, l.date.month, l.date.day));
    }

    final DateTime earliest;
    if (startDate != null) {
      earliest = DateTime(startDate.year, startDate.month, startDate.day);
    } else if (logs.isNotEmpty) {
      earliest = logs
          .map((l) => DateTime(l.date.year, l.date.month, l.date.day))
          .reduce((a, b) => a.isBefore(b) ? a : b);
    } else {
      return 0;
    }

    int streak = 0;
    bool hasWorkout = false;
    var day = today;

    while (true) {
      if (day.isBefore(earliest)) break;

      final isWorkoutDay = workoutDays[day.weekday - 1]; // weekday 1=Mon → index 0

      if (day == today && isWorkoutDay && !logDates.contains(day)) {
        // Today is a workout day the user hasn't completed yet — skip it
        // (the day isn't over, so it can't break the streak).
        day = day.subtract(const Duration(days: 1));
        continue;
      }

      if (isWorkoutDay) {
        if (logDates.contains(day)) {
          streak++;
          hasWorkout = true;
        } else {
          break; // missed workout day → streak breaks
        }
      } else {
        streak++; // rest day — never breaks
      }

      day = day.subtract(const Duration(days: 1));
    }

    return hasWorkout ? streak : 0;
  }
}
