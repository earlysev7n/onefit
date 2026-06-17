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
  AdaptationResult compute({
    required double lastWeekCalorieAdherence, // avgCalories / calorieGoal * 100
    required double lastWeekWorkoutCompletion, // completedWorkouts / plannedWorkouts (0–1)
    required String currentExperienceLevel, // 'Beginner'|'Intermediate'|'Advanced'
    double avgHoursSlept = 7.0, // user's reported average nightly sleep
    double? lastWeekAvgRating, // avg perceived difficulty 1 (too easy) – 5 (too hard)
  }) {
    int calorieBias = 0;
    String difficultyBias = 'same';
    final notes = <String>[];

    // ── Calorie adjustment ──────────────────────────────────────────────────
    if (lastWeekCalorieAdherence < 85) {
      calorieBias = 100;
      notes.add('Calorie target nudged +100 kcal — you were consistently under last week.');
    } else if (lastWeekCalorieAdherence > 110) {
      calorieBias = -100;
      notes.add('Calorie target nudged −100 kcal — you were over target last week.');
    }

    // ── Difficulty step — struggling wins, sleep only blocks the step-up ────
    // Order matters: a low completion rate reduces volume regardless of sleep
    // (lighter weeks aid both adherence and recovery). Poor sleep then blocks
    // any step-up, but never prevents an easing-off when the user is behind.
    final isSleepDeprived = avgHoursSlept < 6.5;
    if (lastWeekWorkoutCompletion < 0.5) {
      difficultyBias = 'down';
      notes.add('Workout volume reduced to better fit your schedule.');
    } else if (isSleepDeprived) {
      // Completing fine but under-rested — hold steady, never bump difficulty.
      difficultyBias = 'same';
      notes.add('Difficulty held steady — your reported sleep is under 6.5 h. Prioritise recovery.');
    } else if (lastWeekWorkoutCompletion >= 0.8 &&
        currentExperienceLevel != 'Advanced') {
      difficultyBias = 'up';
      notes.add('Workout difficulty stepped up — great completion rate last week!');
    }

    // ── RPE / rating autoregulation — a modifier, never a primary driver ────
    // A perceived-difficulty rating (1 too easy … 5 too hard) refines, but does
    // not override, the completion/sleep logic above (Foster 2001 session-RPE;
    // Helms 2016 RIR-based autoregulation).
    if (lastWeekAvgRating != null) {
      if (lastWeekAvgRating >= 4 && difficultyBias == 'up') {
        // Felt hard — don't pile on more load even if completion was high.
        difficultyBias = 'same';
        notes.add('Held difficulty steady — last week felt hard (high effort rating).');
      } else if (lastWeekAvgRating <= 2 &&
          difficultyBias == 'same' &&
          !isSleepDeprived &&
          currentExperienceLevel != 'Advanced' &&
          lastWeekWorkoutCompletion >= 0.5) {
        // Felt easy and you kept up — nudge up even if completion alone wouldn't.
        difficultyBias = 'up';
        notes.add('Stepped difficulty up — last week felt easy (low effort rating).');
      }
    }

    return AdaptationResult(
      calorieBiasKcal: calorieBias,
      difficultyBias: difficultyBias,
      notes: notes.join(' '),
    );
  }
}
