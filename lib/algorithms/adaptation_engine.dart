class AdaptationResult {
  final int calorieBiasKcal;
  final String difficultyBias; // 'up' | 'down' | 'same'
  final String notes;

  const AdaptationResult({
    required this.calorieBiasKcal,
    required this.difficultyBias,
    required this.notes,
  });
}

/// Pure-Dart engine. No Flutter/Firebase imports.
/// Takes last week's aggregated data and returns adaptation signals
/// for the next week's plan generation.
class AdaptationEngine {
  // Difficulty note text exposed as constants so the UI can detect and swap a
  // step message that the NSCA set-range clamp ends up fully absorbing (W2):
  // when the prescribed set count is already at the goal range edge, an
  // 'up'/'down' produces no real volume change and these "stepped" lines would
  // mislead. plans_screen swaps them for the ceiling/floor nudges below.
  static const noteStepUp =
      'Workout difficulty stepped up — great completion rate last week!';
  static const noteStepUpEasy =
      'Stepped difficulty up — last week felt easy (low effort rating).';
  static const noteVolumeDownSchedule =
      'Workout volume reduced to better fit your schedule.';
  static const noteVolumeDownHard =
      'Workout volume eased — last week felt hard (high effort rating).';
  static const noteAtSetCeiling =
      "You're already at the top of your goal's set range — keep progressing by "
      'adding a little weight to your top set (NSCA 2-for-2 rule).';
  static const noteAtSetFloor =
      "Your set count is already at your goal's minimum — focus on form and "
      'recovery this week.';

  AdaptationResult compute({
    required double lastWeekCalorieAdherence, // avgCalories / calorieGoal * 100
    required double lastWeekWorkoutCompletion, // completedWorkouts / plannedWorkouts (0–1)
    required String currentExperienceLevel, // 'Beginner'|'Intermediate'|'Advanced'
    List<int> lastWeekRatings = const [], // per-session difficulty 1 (too easy) – 5 (too hard)
    double? weightChangeKg, // last week's net weight change (kg); + gain / − loss; null if <2 weigh-ins
    String fitnessGoal = 'General Fitness',
    double? lastWeekProteinAdherence, // avgProtein / proteinGoal * 100; null = not enough data
  }) {
    int calorieBias = 0;
    String difficultyBias = 'same';
    final notes = <String>[];

    // ── Calorie adjustment ──────────────────────────────────────────────────
    if (lastWeekCalorieAdherence < 85) {
      calorieBias = 100;
      notes.add('Calorie target nudged +100 kcal — you were consistently under last week.');
    } else if (lastWeekCalorieAdherence > 110) {
      // W4: a Weight-Loss user who is over their logged calorie target but is
      // actually losing weight is already succeeding — don't cut further. Here
      // the outcome (weight) overrides the intake signal, even though the
      // weight modifier is otherwise non-stacking.
      final losingOnWeightLoss = fitnessGoal == 'Weight Loss' &&
          weightChangeKg != null &&
          weightChangeKg < -0.1;
      if (losingOnWeightLoss) {
        notes.add('Calorie target held — you were over your logged target but still losing weight, so the deficit is working.');
      } else {
        calorieBias = -100;
        notes.add('Calorie target nudged −100 kcal — you were over target last week.');
      }
    }

    // ── Weight-trend modifier (outcome signal, non-stacking) ────────────────
    // Only fires when adherence didn't already move calories, so the two
    // calorie signals never fight. Needs a real weekly delta (>=2 weigh-ins).
    if (calorieBias == 0 && weightChangeKg != null) {
      const flat = 0.1; // within ±0.1 kg ≈ no real change this week
      const fastLoss = -1.0; // losing faster than this is too aggressive
      const fastGain = 0.75; // gaining faster than this adds excess fat
      if (fitnessGoal == 'Weight Loss') {
        if (weightChangeKg > -flat) {
          // not losing
          calorieBias = -100;
          notes.add('Calorie target nudged −100 kcal — weight held steady last week despite a fat-loss goal.');
        } else if (weightChangeKg < fastLoss) {
          // losing too fast
          calorieBias = 100;
          notes.add('Calorie target nudged +100 kcal — you lost weight quickly last week; easing the deficit protects muscle.');
        }
      } else if (fitnessGoal == 'Muscle Gain') {
        if (weightChangeKg < flat) {
          // not gaining
          calorieBias = 100;
          notes.add('Calorie target nudged +100 kcal — weight stalled last week despite a muscle-gain goal.');
        } else if (weightChangeKg > fastGain) {
          // gaining too fast
          calorieBias = -100;
          notes.add('Calorie target nudged −100 kcal — you gained quickly last week; trimming keeps the gain lean.');
        }
      }
      // 'Endurance' / 'General Fitness' are maintenance — no weight action.
    }

    // ── Macro (protein) check — note only, never moves calories/difficulty ───
    // N1: macros already scale with the calorie goal, so the engine does not
    // re-target them; but a protein shortfall while calories are on track was
    // previously invisible. Surface it as guidance using the already-collected
    // weekly avg protein. Null adherence = too little logging to judge.
    if (lastWeekProteinAdherence != null &&
        lastWeekCalorieAdherence >= 85 &&
        lastWeekProteinAdherence < 85) {
      notes.add('Protein was low last week (~${lastWeekProteinAdherence.round()}% of target) even though calories were on track — prioritise protein-rich foods.');
    }

    // ── Difficulty step (completion baseline + RPE vote) ─────────────────────
    // Completion sets the baseline; the week's per-session ratings then refine
    // it via a vote (Foster 2001 session-RPE; Helms 2016 RIR autoregulation).
    // Each rating votes: 1→+2, 2→+1, 3→0, 4→−1, 5→−2. A single "too hard" (5)
    // or completion < 0.5 is a safety brake that forbids stepping up.
    final struggling = lastWeekWorkoutCompletion < 0.5;
    final completionUp =
        lastWeekWorkoutCompletion >= 0.8 && currentExperienceLevel != 'Advanced';

    int? vote;
    var hasTooHard = false;
    if (lastWeekRatings.isNotEmpty) {
      vote = 0;
      for (final r in lastWeekRatings) {
        if (r <= 1) {
          vote = vote! + 2;
        } else if (r == 2) {
          vote = vote! + 1;
        } else if (r == 3) {
          vote = vote!; // neutral
        } else if (r == 4) {
          vote = vote! - 1;
        } else {
          vote = vote! - 2; // 5+ = too hard
          hasTooHard = true;
        }
      }
    }
    final blockUp = hasTooHard || struggling;

    // Baseline from completion.
    String? diffNote;
    if (struggling) {
      difficultyBias = 'down';
      diffNote = noteVolumeDownSchedule;
    } else if (completionUp) {
      difficultyBias = 'up';
      diffNote = noteStepUp;
    }

    // Vote refinement (only when the week has ratings).
    if (vote != null) {
      if (vote <= -2 && difficultyBias != 'down') {
        // Felt hard overall — ease one step, overriding an up/same baseline.
        difficultyBias = 'down';
        diffNote = noteVolumeDownHard;
      } else if (vote >= 2 &&
          !blockUp &&
          lastWeekWorkoutCompletion >= 0.7 && // W3: don't reward partial-skippers
          currentExperienceLevel != 'Advanced' &&
          difficultyBias != 'up') {
        difficultyBias = 'up';
        diffNote = noteStepUpEasy;
      }
      // Safety: never step up when a session was too hard or completion was poor.
      if (difficultyBias == 'up' && blockUp) {
        difficultyBias = 'same';
        diffNote =
            'Held difficulty steady — last week felt hard (high effort rating).';
      }
    }
    if (diffNote != null) notes.add(diffNote);

    return AdaptationResult(
      calorieBiasKcal: calorieBias,
      difficultyBias: difficultyBias,
      notes: notes.join(' '),
    );
  }
}
