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

    // ── Recovery check — sleep overrides difficulty step-up ─────────────────
    final isSleepDeprived = avgHoursSlept < 6.5;
    if (isSleepDeprived) {
      // Even excellent completion shouldn't bump difficulty when under-rested
      difficultyBias = 'same';
      notes.add('Difficulty held steady — your reported sleep is under 6.5 h. Prioritise recovery.');
    } else if (lastWeekWorkoutCompletion >= 0.8 &&
        currentExperienceLevel != 'Advanced') {
      difficultyBias = 'up';
      notes.add('Workout difficulty stepped up — great completion rate last week!');
    } else if (lastWeekWorkoutCompletion < 0.5) {
      difficultyBias = 'down';
      notes.add('Workout volume reduced to better fit your schedule.');
    }

    return AdaptationResult(
      calorieBiasKcal: calorieBias,
      difficultyBias: difficultyBias,
      notes: notes.join(' '),
    );
  }
}
