import 'package:flutter/foundation.dart';

/// Master switch for the debug day-changer overlay.
/// MUST be `false` for any build intended for real use.
const bool kDebugDayChanger = false;

/// When true, shows an amber ⚡ "Auto-Complete" button on each training day
/// card in the Workout tab so workouts can be logged without doing the full
/// exercise flow. Use this to rapidly populate workout_logs for adaptation
/// testing. MUST be `false` for any build intended for real use.
const bool kDebugAutoFinishWorkout = false;

/// Number of days to shift the app's notion of "today" by. 0 = real today.
/// Wrapped in a [ValueNotifier] so the UI can rebuild live when it changes
/// (see the `MaterialApp.builder` wiring in main.dart).
final ValueNotifier<int> debugDayOffset = ValueNotifier<int>(0);

/// App-wide clock. Use this instead of `DateTime.now()` for any *logical*
/// date — which day's plan/meals render, the weekId, streaks, date labels,
/// and the timestamp new logs are written with.
///
/// Do NOT use it for cache TTLs, unique IDs (`millisecondsSinceEpoch`), or
/// elapsed-time timers (e.g. workout duration) — those must track real time.
DateTime appNow() => DateTime.now().add(
  Duration(days: kDebugDayChanger ? debugDayOffset.value : 0),
);

/// Midnight of the simulated day — convenience for date-only comparisons.
DateTime appToday() {
  final n = appNow();
  return DateTime(n.year, n.month, n.day);
}
