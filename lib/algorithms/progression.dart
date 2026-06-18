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
