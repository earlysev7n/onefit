import '../models/exercise.dart';
import '../models/user_profile.dart';

class WorkoutDay {
  final String dayName;
  final String focus;
  final List<WorkoutExercise> exercises;
  final bool isRest;

  WorkoutDay({
    required this.dayName,
    required this.focus,
    required this.exercises,
    this.isRest = false,
  });

  Map<String, dynamic> toMap() => {
    'dayName': dayName,
    'focus': focus,
    'isRest': isRest,
    'exercises': exercises.map((e) => e.toMap()).toList(),
  };

  factory WorkoutDay.fromMap(Map<String, dynamic> m) => WorkoutDay(
    dayName: m['dayName'] as String? ?? '',
    focus: m['focus'] as String? ?? '',
    isRest: m['isRest'] as bool? ?? false,
    exercises:
        (m['exercises'] as List? ?? [])
            .map((e) => WorkoutExercise.fromMap(e as Map<String, dynamic>))
            .toList(),
  );
}

class WorkoutExercise {
  final Exercise exercise;
  final int sets;
  final String reps; // e.g. "10-12" or "30 sec"
  final int restSeconds;

  WorkoutExercise({
    required this.exercise,
    required this.sets,
    required this.reps,
    required this.restSeconds,
  });

  Map<String, dynamic> toMap() => {
    'exercise': exercise.toMap(),
    'sets': sets,
    'reps': reps,
    'restSeconds': restSeconds,
  };

  factory WorkoutExercise.fromMap(Map<String, dynamic> m) => WorkoutExercise(
    exercise: Exercise.fromMap(m['exercise'] as Map<String, dynamic>),
    sets: m['sets'] as int? ?? 3,
    reps: m['reps'] as String? ?? '10-12',
    restSeconds: m['restSeconds'] as int? ?? 60,
  );
}

class GreedyAlgorithm {
  //  SCORING
  double _scoreExercise({
    required Exercise exercise,
    required UserProfile profile,
    required Map<String, int> muscleHitCount, // tracks muscle group usage
  }) {
    double score = 0;

    // 1. Goal match
    final goalKey = _goalKey(profile.fitnessGoal);
    if (exercise.goals.contains(goalKey)) score += 40;

    // 2. Location match
    final loc = profile.workoutLocation.toLowerCase();
    if (exercise.locations.contains(loc)) score += 30;

    // 3. Equipment match
    if (_equipmentMatches(exercise, profile)) score += 20;

    // 4. Difficulty match
    if (_difficultyMatches(exercise.difficulty, profile.experienceLevel))
      score += 10;

    // 5. Muscle balance penalty
    for (final muscle in exercise.primaryMuscles) {
      final hits = muscleHitCount[muscle] ?? 0;
      score -= hits * 15;
    }

    return score;
  }

  //  Main:
  List<WorkoutDay> generatePlan({
    required List<Exercise> allExercises,
    required UserProfile profile,
    String difficultyBias = 'same', // 'up' | 'down' | 'same'
  }) {
    // Filter exercises that are valid for this user
    final filtered = allExercises.where((e) {
      final goalKey = _goalKey(profile.fitnessGoal);
      final loc = profile.workoutLocation.toLowerCase();
      return e.goals.contains(goalKey) &&
          e.locations.contains(loc) &&
          _equipmentMatches(e, profile);
    }).toList();

    // Build 7-day schedule from user's chosen split + available days
    var schedule = _getSchedule(profile);

    // Adaptation: if user couldn't keep up, drop the last workout day to rest
    if (difficultyBias == 'down') {
      final lastWorkoutIdx = schedule.lastIndexWhere((d) => d != 'Rest');
      if (lastWorkoutIdx >= 0) {
        schedule = List.from(schedule)..[lastWorkoutIdx] = 'Rest';
      }
    }

    final List<WorkoutDay> plan = [];
    final muscleHitCount = <String, int>{};

    for (int i = 0; i < 7; i++) {
      final focus = schedule[i];
      final dayName = _dayName(i);

      if (focus == 'Rest') {
        plan.add(
          WorkoutDay(
            dayName: dayName,
            focus: 'Rest Day',
            exercises: [],
            isRest: true,
          ),
        );
        continue;
      }

      final targetMuscles = _focusToMuscles(focus);
      final dayExercises = _selectExercisesForDay(
        exercises: filtered,
        targetMuscles: targetMuscles,
        profile: profile,
        muscleHitCount: muscleHitCount,
        count: _exercisesPerDay(profile),
        difficultyBias: difficultyBias,
      );

      for (final we in dayExercises) {
        for (final m in we.exercise.primaryMuscles) {
          muscleHitCount[m] = (muscleHitCount[m] ?? 0) + 1;
        }
      }

      plan.add(
        WorkoutDay(dayName: dayName, focus: focus, exercises: dayExercises),
      );
    }

    return plan;
  }

  List<WorkoutExercise> _selectExercisesForDay({
    required List<Exercise> exercises,
    required List<String> targetMuscles,
    required UserProfile profile,
    required Map<String, int> muscleHitCount,
    required int count,
    String difficultyBias = 'same',
  }) {
    // Hard constraint — if bias is 'up', also allow the next difficulty tier
    final eligible = exercises.where((e) {
      if (_difficultyMatches(e.difficulty, profile.experienceLevel)) return true;
      if (difficultyBias == 'up') {
        // Allow one tier above
        if (profile.experienceLevel == 'Beginner' && e.difficulty == 'intermediate') return true;
        if (profile.experienceLevel == 'Intermediate' && e.difficulty == 'advanced') return true;
      }
      return false;
    }).toList();

    // Prefer exercises that hit target muscles
    final scored = eligible.map((e) {
      double s = _scoreExercise(
        exercise: e,
        profile: profile,
        muscleHitCount: muscleHitCount,
      );

      for (final m in e.primaryMuscles) {
        if (targetMuscles.contains(m)) s += 25;
      }
      return MapEntry(e, s);
    }).toList()..sort((a, b) => b.value.compareTo(a.value));

    // Take top N unique exercises (no duplicates)
    final selected = <Exercise>[];
    final seenIds = <String>{};
    for (final entry in scored) {
      if (seenIds.contains(entry.key.id)) continue;
      seenIds.add(entry.key.id);
      selected.add(entry.key);
      if (selected.length >= count) break;
    }

    return selected
        .map(
          (e) => WorkoutExercise(
            exercise: e,
            sets: _getSets(profile),
            reps: _getReps(profile, e.category),
            restSeconds: _getRestSeconds(profile),
          ),
        )
        .toList();
  }

  // ── SCHEDULE — driven by workoutSplit + workoutDaysPerWeek ──────────────────
  List<String> _getSchedule(UserProfile profile) {
    final trainDays = profile.workoutDaysPerWeek.clamp(1, 7);
    final focusSequence = _splitFocusSequence(profile.workoutSplit);

    // Build positions (0–6) for training days, spread as evenly as possible.
    final trainPositions = <int>{};
    for (int i = 0; i < trainDays; i++) {
      trainPositions.add((i * 7 / trainDays).floor());
    }

    // Fill 7-day schedule
    int focusIdx = 0;
    final schedule = List<String>.filled(7, 'Rest');
    for (int i = 0; i < 7; i++) {
      if (trainPositions.contains(i)) {
        schedule[i] = focusSequence[focusIdx % focusSequence.length];
        focusIdx++;
      }
    }
    return schedule;
  }

  /// Maps each workout split to an ordered cycle of day focuses.
  List<String> _splitFocusSequence(String split) {
    switch (split) {
      case 'Upper / Lower Split':
        return ['Upper Body', 'Lower Body'];
      case 'Push / Pull / Legs (PPL)':
        return ['Chest & Triceps', 'Back & Biceps', 'Legs'];
      case 'Bro Split':
      case 'Body Part Split':
        return [
          'Chest & Triceps',
          'Back & Biceps',
          'Legs',
          'Shoulders & Arms',
          'Arms',
        ];
      case 'Hybrid Split':
        return ['Full Body', 'Upper Body', 'Lower Body'];
      case 'HIIT + Strength Split':
        return ['Full Body', 'Cardio'];
      case 'Strength + Conditioning Split':
        return ['Full Body', 'Cardio'];
      case 'Functional Training Split':
      case 'Circuit Training Split':
      case 'Full Body Training':
      default:
        return ['Full Body'];
    }
  }

  Map<String, List<String>> get _focusMuscleMap => {
    'Full Body': ['chest', 'back', 'quads', 'glutes', 'core', 'shoulders'],
    'Full Body Cardio': ['full body', 'quads', 'glutes', 'core', 'hip flexors'],
    'HIIT': ['full body', 'quads', 'glutes', 'core'],
    'Cardio': ['full body', 'quads', 'glutes', 'core', 'hip flexors'],
    'Upper Body': [
      'chest',
      'back',
      'shoulders',
      'biceps',
      'triceps',
      'upper back',
    ],
    'Lower Body': ['quads', 'glutes', 'hamstrings', 'calves'],
    'Core': ['core', 'abs', 'obliques', 'lower abs'],
    'Chest & Triceps': ['chest', 'triceps', 'upper chest'],
    'Back & Biceps': ['lats', 'upper back', 'biceps', 'lower back'],
    'Legs': ['quads', 'glutes', 'hamstrings', 'calves'],
    'Shoulders & Arms': ['shoulders', 'biceps', 'triceps', 'rear delts'],
    'Arms': ['biceps', 'triceps', 'forearms'],
  };

  List<String> _focusToMuscles(String focus) =>
      _focusMuscleMap[focus] ?? ['full body'];

  //  HELPERS
  String _goalKey(String goal) {
    switch (goal) {
      case 'Weight Loss':
        return 'weight_loss';
      case 'Muscle Gain':
        return 'muscle_gain';
      case 'Endurance':
        return 'endurance';
      default:
        return 'general';
    }
  }

  bool _equipmentMatches(Exercise exercise, UserProfile profile) {
    if (exercise.equipment.contains('bodyweight')) return true;
    if (exercise.equipment.contains('gym') && profile.workoutLocation == 'Gym')
      return true;
    for (final eq in exercise.equipment) {
      if (profile.equipment
          .map((e) => e.toLowerCase())
          .contains(eq.toLowerCase()))
        return true;
    }
    return false;
  }

  bool _difficultyMatches(String exDifficulty, String level) {
    if (level == 'Beginner') return exDifficulty == 'beginner';
    if (level == 'Intermediate')
      return exDifficulty == 'beginner' || exDifficulty == 'intermediate';
    return true; // Advanced can do all
  }

  /// Exercise count per day — driven by sessionMinutes, nudged by experience
  /// and scaled down by recoveryScore (poor sleep → fewer exercises).
  int _exercisesPerDay(UserProfile profile) {
    // Base count from session length
    int base;
    if (profile.sessionMinutes <= 30) {
      base = 3;
    } else if (profile.sessionMinutes <= 45) {
      base = 5;
    } else if (profile.sessionMinutes <= 60) {
      base = 6;
    } else {
      base = 8; // 90 min
    }

    // ±1 experience nudge
    if (profile.experienceLevel == 'Beginner') base--;
    if (profile.experienceLevel == 'Advanced') base++;

    // Recovery reduction: under-slept → drop one exercise
    if (profile.recoveryScore < 0.8) base--;

    return base.clamp(2, 10);
  }

  /// Sets per exercise — from goal/experience, reduced when recovery is low.
  int _getSets(UserProfile profile) {
    int sets;
    if (profile.fitnessGoal == 'Muscle Gain') {
      switch (profile.experienceLevel) {
        case 'Beginner':
          sets = 3;
          break;
        case 'Intermediate':
          sets = 4;
          break;
        default:
          sets = 5;
      }
    } else {
      sets = profile.experienceLevel == 'Advanced' ? 4 : 3;
    }
    // Recovery shave
    if (profile.recoveryScore < 0.8) sets--;
    return sets.clamp(2, 6);
  }

  /// Reps — from goal and split style (conditioning splits get higher reps/timed).
  String _getReps(UserProfile profile, String category) {
    final split = profile.workoutSplit;
    if (split == 'HIIT + Strength Split' || split == 'Circuit Training Split') {
      return category == 'cardio' ? '60 sec' : '15-20';
    }
    if (split == 'Strength + Conditioning Split') {
      return category == 'cardio' ? '45 sec' : '8-12';
    }
    if (category == 'cardio') return '45 sec';
    if (profile.fitnessGoal == 'Weight Loss' || profile.fitnessGoal == 'Endurance') {
      return '15-20';
    }
    if (profile.fitnessGoal == 'Muscle Gain') return '8-12';
    return '12-15';
  }

  /// Rest seconds — conditioning-style splits get shorter rests.
  int _getRestSeconds(UserProfile profile) {
    final split = profile.workoutSplit;
    if (split == 'HIIT + Strength Split' || split == 'Circuit Training Split') {
      return 30;
    }
    if (split == 'Strength + Conditioning Split') return 60;
    if (profile.fitnessGoal == 'Muscle Gain') return 90;
    if (profile.fitnessGoal == 'Weight Loss' || profile.fitnessGoal == 'Endurance') {
      return 45;
    }
    return 60;
  }

  String _dayName(int index) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[index];
  }
}
