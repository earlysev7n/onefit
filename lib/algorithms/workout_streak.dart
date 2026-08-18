import '../models/workout_log.dart';

/// Pure "days on plan" workout-streak calculator.
///
/// The streak is the number of consecutive calendar days — counting back from
/// today — that belong to an unbroken run of on-plan weeks. It is deliberately
/// **rest-day agnostic and week-based**, matching the product rule:
///
/// * Rest days never break the streak (they're just days on the plan).
/// * A *finished* (past) week is "on plan" when its completed workouts reach the
///   user's [plannedPerWeek]. The first past week that fell short breaks the run.
/// * The current, in-progress week can never count as a miss — its elapsed days
///   always extend the streak while it's still running.
/// * It spans weeks; it does not reset every week or every rest day.
///
/// Weeks are Monday-anchored (Mon–Sun), consistent with the weekly stats
/// elsewhere in [ProgressProvider]. Returns 0 when there is no plan
/// ([plannedPerWeek] <= 0) or the user has no on-plan activity yet.
class WorkoutStreak {
  const WorkoutStreak._();

  static DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  /// Completed workouts logged within the 7-day window `[start, start + 7)`.
  static int _completedIn(List<WorkoutLog> logs, DateTime start) {
    final end = start.add(const Duration(days: 7));
    return logs.where((l) {
      final d = DateTime(l.date.year, l.date.month, l.date.day);
      return !d.isBefore(start) && d.isBefore(end);
    }).length;
  }

  static int days(
    List<WorkoutLog> logs, {
    required int plannedPerWeek,
    required DateTime now,
  }) {
    if (plannedPerWeek <= 0) return 0;

    final today = DateTime(now.year, now.month, now.day);
    final currentStart = _mondayOf(today);

    // Consecutive fully-on-plan weeks immediately preceding the current one.
    int weeksBack = 0;
    var wk = currentStart.subtract(const Duration(days: 7));
    while (_completedIn(logs, wk) >= plannedPerWeek) {
      weeksBack++;
      wk = wk.subtract(const Duration(days: 7));
    }

    final currentCompleted = _completedIn(logs, currentStart);
    // No prior on-plan run and nothing done this week yet → no streak.
    if (weeksBack == 0 && currentCompleted == 0) return 0;

    // Days elapsed in the current week (Mon = 1 … today).
    final currentElapsed = today.difference(currentStart).inDays + 1;
    return weeksBack * 7 + currentElapsed;
  }
}
