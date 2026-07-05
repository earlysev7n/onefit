/// Progressive-overload prescription and warm-up ramp generation.
///
/// Pure Dart — no Flutter/Firebase imports — so it can be exercised by a
/// standalone `dart run` script (see the repo-root `verify_*.dart` files) as
/// well as by PlansScreen.
///
/// The app already *records* the user's last performed top set
/// (`ExerciseStat.lastWeightKg/lastReps`). This module turns that history into
/// the *next* prescription:
///
///  * `nextTarget` implements **double progression** — the standard novice/
///    intermediate model: keep adding reps within the prescribed range, and once
///    the top of the range is reached at the current load, add weight and reset
///    to the bottom of the range (ACSM Progression Models position stand,
///    Ratamess et al. 2009; RIR/RPE autoregulation, Helms et al. 2016).
///
/// Weight is always in kg internally (same convention as UserProfile /
/// ExerciseStat); the UI converts for display.
library;

import '../models/workout_log.dart';

/// Load increments (kg) when stepping weight up in double progression.
const double kProgressionIncrementCompound = 5.0; // lower-body / big compounds
const double kProgressionIncrementIsolation = 2.5; // upper-body / isolation

/// Parses a prescribed rep string like `"10-12"` or `"8"` into `(min, max)`.
/// Returns `null` for non-numeric prescriptions (`"30 sec"`, `"AMRAP"`, …),
/// which carry no load progression.
({int min, int max})? parseRepRange(String reps) {
  final match = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+))?\s*$').firstMatch(reps);
  if (match == null) return null;
  final min = int.parse(match.group(1)!);
  final max = match.group(2) != null ? int.parse(match.group(2)!) : min;
  if (max < min) return (min: max, max: min);
  return (min: min, max: max);
}

/// The next prescribed working set for an exercise.
class ProgressionTarget {
  final double weightKg;
  final int reps;

  /// True when the prescription steps the *load* up (vs. just adding a rep).
  final bool isIncrease;
  final String note;

  const ProgressionTarget({
    required this.weightKg,
    required this.reps,
    required this.isIncrease,
    required this.note,
  });

  @override
  String toString() =>
      'ProgressionTarget($weightKg kg × $reps, '
      'isIncrease: $isIncrease, "$note")';
}

/// Computes the next working-set target via double progression.
///
/// Returns `null` when there is nothing to prescribe — no prior load logged, or
/// a non-numeric rep prescription (timed / bodyweight work).
ProgressionTarget? nextTarget({
  required double? lastWeightKg,
  required int? lastReps,
  required String repRange,
  required bool isLowerOrCompound,
}) {
  final range = parseRepRange(repRange);
  if (range == null) return null;
  if (lastWeightKg == null || lastWeightKg <= 0) return null;

  // No reps recorded — repeat the same load at the bottom of the range.
  final reps = lastReps ?? range.min;

  if (reps >= range.max) {
    final increment = isLowerOrCompound
        ? kProgressionIncrementCompound
        : kProgressionIncrementIsolation;
    return ProgressionTarget(
      weightKg: lastWeightKg + increment,
      reps: range.min,
      isIncrease: true,
      note: 'Hit the top of the range last time — add weight.',
    );
  }

  final nextReps = (reps + 1).clamp(range.min, range.max);
  return ProgressionTarget(
    weightKg: lastWeightKg,
    reps: nextReps,
    isIncrease: false,
    note: 'Add a rep at the same weight.',
  );
}

/// Per-set progression: suggests every set of the next session from the prior
/// session's [lastSets], generalizing [nextTarget] from one top set to the
/// whole set list. Returns an empty list when there's no history (Week 1 →
/// blank inputs). The user's own log always overrides these suggestions.
///
///  * **Loaded** (weight logged): if *every* set reached the top of the rep
///    range → add load and reset all sets to the range minimum; else hold the
///    heaviest logged weight and nudge each set's reps up toward the top.
///  * **Bodyweight** (reps, no weight): +1 rep per set toward
///    [bodyweightRepCap]; once every set is at the cap, add one more set.
///  * **Timed** (seconds): +[timedIncrement]s per set toward [timedCap].
List<SetEntry> nextSetTargets({
  required List<SetEntry> lastSets,
  required String repRange,
  required bool isLowerOrCompound,
  int bodyweightRepCap = 20,
  int timedCap = 90,
  int timedIncrement = 5,
}) {
  if (lastSets.isEmpty) return const [];
  final range = parseRepRange(repRange);

  // Timed moves: no numeric rep range, or seconds were logged → progress time.
  final isTimed = range == null || lastSets.any((s) => s.seconds != null);
  if (isTimed) {
    return [
      for (final s in lastSets)
        SetEntry(seconds: ((s.seconds ?? 30) + timedIncrement).clamp(5, timedCap)),
    ];
  }

  final hasWeight = lastSets.any((s) => (s.weightKg ?? 0) > 0);

  // Bodyweight: progress reps toward the cap, then add a set.
  if (!hasWeight) {
    final next = [
      for (final s in lastSets)
        SetEntry(
          reps: ((s.reps ?? range.min) + 1).clamp(range.min, bodyweightRepCap),
        ),
    ];
    final allAtCap = lastSets.every((s) => (s.reps ?? 0) >= bodyweightRepCap);
    if (allAtCap) next.add(SetEntry(reps: range.min));
    return next;
  }

  // Loaded: double progression across the full set list.
  final topWeight = lastSets
      .map((s) => s.weightKg ?? 0)
      .fold<double>(0, (a, b) => a > b ? a : b);
  final allHitTop = lastSets.every((s) => (s.reps ?? 0) >= range.max);
  if (allHitTop) {
    final increment = isLowerOrCompound
        ? kProgressionIncrementCompound
        : kProgressionIncrementIsolation;
    return [
      for (final _ in lastSets)
        SetEntry(weightKg: topWeight + increment, reps: range.min),
    ];
  }
  return [
    for (final s in lastSets)
      SetEntry(
        weightKg: topWeight,
        reps: ((s.reps ?? range.min) + 1).clamp(range.min, range.max),
      ),
  ];
}
