import 'package:flutter/foundation.dart';

/// Which adaptation the developer-mode "Skip to Next Week" seeder should
/// provoke — it decides what last week's fake data makes the AdaptationEngine
/// do (see `lib/dev/dev_tools.dart`).
enum DevScenario { levelUp, easeOff, realistic }

/// Master switch for Developer Mode, toggled from the Settings screen. When
/// off, the whole demo toolset (the day-changer pill and the seeding actions)
/// is hidden/inert. Persisted to SharedPreferences ('developerMode') so it
/// survives a hot restart. MUST default `false` — real users never enable it.
final ValueNotifier<bool> developerModeEnabled = ValueNotifier<bool>(false);

/// Whether the floating day-changer pill is shown and its offset applied to
/// [appNow]. A sub-toggle of Developer Mode ("Change Day"); turning Developer
/// Mode off resets this to false and the offset to 0.
final ValueNotifier<bool> devDayChangerEnabled = ValueNotifier<bool>(false);

/// The scenario picked in Developer Mode for the week seeder.
final ValueNotifier<DevScenario> devScenario =
    ValueNotifier<DevScenario>(DevScenario.levelUp);

/// Developer-Mode "Force Offline" switch. When true (and Developer Mode is on),
/// the app behaves as if the device has no connection: the offline banner shows
/// and every network-only feature is disabled — without touching Wi-Fi. The
/// [ConnectivityProvider] also drives Firestore's `disableNetwork()` off this so
/// it is a *real* offline test (cached reads + queued writes), not just a UI gate.
/// A sub-toggle of Developer Mode; turning Developer Mode off resets it to false.
/// MUST default `false` — real users never reach it.
final ValueNotifier<bool> forceOfflineEnabled = ValueNotifier<bool>(false);

/// True only while a workout session is in progress (Start Workout pressed,
/// not yet finished/abandoned). Drives the immersive session UI: the Plans
/// title + tabs, the date strip/chips, and the bottom nav are hidden while a
/// workout is running so the exercise flow is full-screen (like the food-add
/// flow). Set in `_startWorkout`/`_resetWorkoutState`/`_autoComplete` and
/// consumed via `ValueListenableBuilder` in HomeScreen + PlansScreen.
final ValueNotifier<bool> workoutSessionActive = ValueNotifier<bool>(false);

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
  Duration(days: devDayChangerEnabled.value ? debugDayOffset.value : 0),
);

/// Midnight of the simulated day — convenience for date-only comparisons.
DateTime appToday() {
  final n = appNow();
  return DateTime(n.year, n.month, n.day);
}
