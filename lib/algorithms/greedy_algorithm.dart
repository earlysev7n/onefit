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
  // ── ELIGIBILITY — hard constraints, shared with PlansScreen edit paths ─────
  static final _maleTag = RegExp(r'\bmale\b'); // does NOT match "female"
  static final _femaleTag = RegExp(r'\bfemale\b');
  static final _benchTag = RegExp(r'\b(incline|decline|bench)\b');
  static const _freeWeights = {
    'dumbbells', 'barbell', 'ez barbell', 'kettlebells',
  };

  /// What the user can physically do: gender-tagged demo variants, location,
  /// equipment, and bench availability. Goal and difficulty are NOT gated
  /// here — goal is a scoring signal and the experience gate lives in
  /// [difficultyAllowed]. Reused by PlansScreen's picker/gap-fill/volume-debt
  /// paths so manual edits can't inject exercises the user can't perform.
  static bool isEligibleForUser(Exercise e, UserProfile p) {
    final name = e.name.toLowerCase();

    // The catalog duplicates many moves as "(male)" / "(female)" demo
    // variants — keep only the variant matching the user.
    if (p.gender == 'Female' && _maleTag.hasMatch(name)) return false;
    if (p.gender == 'Male' && _femaleTag.hasMatch(name)) return false;

    // At a gym every equipment type (and a bench) is available. Gym profiles
    // store equipment: [] (see ProfileInputScreen), so equipment must not be
    // matched against the user's list here.
    if (p.workoutLocation == 'Gym') return true;

    // Home: exercise must be doable at home...
    if (!e.locations.contains('home')) return false;

    // ...with equipment the user owns (bodyweight always available).
    final exEquip = e.equipment.map((x) => x.toLowerCase()).toList();
    final isBodyweight = exEquip.contains('bodyweight');
    if (!isBodyweight) {
      final userEquip = p.equipment.map((x) => x.toLowerCase()).toSet();
      if (!exEquip.any(userEquip.contains)) return false;

      // Free-weight incline/decline/bench moves need a bench, which is not a
      // home equipment option. Bodyweight variants (decline push-up etc.)
      // stay eligible — a couch or stairs will do.
      if (_benchTag.hasMatch(name) && exEquip.any(_freeWeights.contains)) {
        return false;
      }
    }
    return true;
  }

  // Canonical multi-joint lift names. The catalog has no `mechanic` field, so
  // staple compounds are detected by name keyword or a secondary-muscle proxy.
  static final _compoundKeywords = RegExp(
    r'\b(squat|deadlift|bench|press|row|pull[- ]?up|chin[- ]?up|push[- ]?up|dip|lunge|thrust|clean|snatch|jerk)\b',
  );

  /// Staple compound (multi-joint) lifts — squat/bench/deadlift/row/press etc.,
  /// or anything hitting ≥2 secondary muscles. Used to prioritise compounds in
  /// generation (ACSM progression guidance; Simão 2012 on exercise order).
  static bool isStapleCompound(Exercise e) {
    if (_compoundKeywords.hasMatch(e.name.toLowerCase())) return true;
    return e.secondaryMuscles.length >= 2;
  }

  /// STRICT experience gate — Beginner → beginner only; Intermediate →
  /// beginner + intermediate; Advanced → all. No cross-tier progression.
  static bool difficultyAllowed(String exDifficulty, String level) {
    if (level == 'Beginner') return exDifficulty == 'beginner';
    if (level == 'Intermediate') {
      return exDifficulty == 'beginner' || exDifficulty == 'intermediate';
    }
    return true;
  }

  //  SCORING — runs over candidates that already passed the hard filters, so
  //  location/equipment carry no score weight (they'd be constants).
  double _scoreExercise({
    required Exercise exercise,
    required UserProfile profile,
    required List<String> targetMuscles,
    required Map<String, int> weeklyHits,
    required Map<String, int> dayHits,
  }) {
    double score = 0;

    // 1. Day focus dominates — a Chest day must stay a chest day.
    if (exercise.primaryMuscles.any(targetMuscles.contains)) score += 50;

    // 2. Goal tag is a soft nudge only. At its old weight (+40) it buried the
    //    focus bonus and let one goal-tagged muscle (abs, for weight loss)
    //    sweep every slot of a day.
    if (exercise.goals.contains(_goalKey(profile.fitnessGoal))) score += 15;

    // 2b. Compound (multi-joint) bonus — staples like squat/bench/row recruit
    //     more muscle mass and belong early in a session (ACSM; Simão 2012).
    //     Kept below the focus bonus (+50) so the day's focus still dominates,
    //     but above isolation so the big lift is picked first.
    if (isStapleCompound(exercise)) score += 12;

    // 3. Prefer exercises at exactly the user's tier (the gate already
    //    excluded anything above it).
    if (exercise.difficulty == profile.experienceLevel.toLowerCase()) {
      score += 10;
    }

    // 4. Muscle balance: a strong day-local penalty forces variety within a
    //    session; a milder weekly penalty spreads volume across the week.
    for (final muscle in exercise.primaryMuscles) {
      score -= (dayHits[muscle] ?? 0) * 25;
      score -= (weeklyHits[muscle] ?? 0) * 15;
    }

    return score;
  }

  //  Main:
  List<WorkoutDay> generatePlan({
    required List<Exercise> allExercises,
    required UserProfile profile,
    String difficultyBias = 'same', // 'up' | 'down' | 'same'
  }) {
    // Hard constraints: gender variant + location + equipment + bench (what
    // the user can physically do). Goal is a scoring signal, not a gate —
    // gating on it collapses the candidate pool (e.g. a Weight-Loss user
    // would be excluded from all chest/back/arm work).
    final filtered =
        allExercises.where((e) => isEligibleForUser(e, profile)).toList();

    // Build 7-day schedule from user's chosen split + available days.
    // workoutDaysPerWeek is a hard constraint: adaptation never adds or
    // removes training days — difficultyBias modulates per-day volume
    // (exercise count and sets) instead, per ACSM progression guidance.
    final schedule = _getSchedule(profile);

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

      final targetMuscles = musclesForFocus(focus);
      final dayExercises = _selectExercisesForDay(
        exercises: filtered,
        targetMuscles: targetMuscles,
        profile: profile,
        muscleHitCount: muscleHitCount,
        count: _exercisesPerDay(profile, difficultyBias),
        difficultyBias: difficultyBias,
        dayFocus: focus,
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
    required String difficultyBias,
    required String dayFocus,
  }) {
    // Experience gate (see difficultyAllowed). The pool never starves because
    // difficulty inference defaults to 'beginner' (difficulty_inference.dart).
    final eligible = exercises
        .where((e) => difficultyAllowed(e.difficulty, profile.experienceLevel))
        .toList();

    // Cap how often one primary muscle can headline a single session: a
    // Full Body day (6 targets, 5 slots) caps at 2 per muscle, a Chest &
    // Triceps day (2 targets, 5 slots) at 3. Without a cap (and with the
    // old score-once-take-top-N selection) the highest-scoring muscle
    // swept every slot — the "Monday is all abs" bug.
    final perMuscleCap = targetMuscles.isEmpty
        ? count
        : (count / targetMuscles.length).ceil().clamp(2, count);

    // True greedy: pick the best candidate, update the day-local muscle
    // counts, re-score, repeat — so each pick is penalised by what the day
    // already contains. Second pass without the cap covers tiny pools
    // (limited home equipment) rather than returning a short day.
    final selected = <Exercise>[];
    final seenIds = <String>{};
    final dayHits = <String, int>{};

    // Force-include the user's pinned anchor lifts for this focus FIRST, so a
    // key lift (e.g. bench on Upper day) is always present and ordered first.
    // Still gated by the hard constraints (a pin not in `eligible` — e.g. a home
    // user who pinned a barbell lift — is silently skipped). Capped at count-1
    // when there's room, so at least one generated slot remains for variety.
    final pinnedIds = profile.pinnedExercises[dayFocus] ?? const <String>[];
    if (pinnedIds.isNotEmpty) {
      final cap = count > 1 ? count - 1 : count;
      for (final id in pinnedIds) {
        if (selected.length >= cap) break;
        if (seenIds.contains(id)) continue;
        Exercise? pin;
        for (final e in eligible) {
          if (e.id == id) { pin = e; break; }
        }
        if (pin == null) continue;
        selected.add(pin);
        seenIds.add(pin.id);
        for (final m in pin.primaryMuscles) {
          dayHits[m] = (dayHits[m] ?? 0) + 1;
        }
      }
    }

    for (final enforceCap in [true, false]) {
      while (selected.length < count) {
        Exercise? best;
        double bestScore = double.negativeInfinity;
        for (final e in eligible) {
          if (seenIds.contains(e.id)) continue;
          if (enforceCap &&
              e.primaryMuscles
                  .any((m) => (dayHits[m] ?? 0) >= perMuscleCap)) {
            continue;
          }
          final s = _scoreExercise(
            exercise: e,
            profile: profile,
            targetMuscles: targetMuscles,
            weeklyHits: muscleHitCount,
            dayHits: dayHits,
          );
          if (s > bestScore) {
            bestScore = s;
            best = e;
          }
        }
        if (best == null) break; // pool exhausted under current constraints
        selected.add(best);
        seenIds.add(best.id);
        for (final m in best.primaryMuscles) {
          dayHits[m] = (dayHits[m] ?? 0) + 1;
        }
      }
      if (selected.length >= count) break;
    }

    return selected
        .map(
          (e) => WorkoutExercise(
            exercise: e,
            sets: _getSets(profile, difficultyBias),
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
  ///
  /// Selectable splits (ProfileInputScreen): Full Body Training,
  /// Upper / Lower Split, Push / Pull / Legs (PPL), Functional Training
  /// Split, Strength + Conditioning Split. The remaining arms are legacy —
  /// kept so profiles saved before the split list was reduced still generate
  /// sanely until the user re-saves their profile.
  List<String> _splitFocusSequence(String split) {
    switch (split) {
      case 'Upper / Lower Split':
        return ['Upper Body', 'Lower Body'];
      case 'Push / Pull / Legs (PPL)':
        return ['Chest & Triceps', 'Back & Biceps', 'Legs'];
      case 'Strength + Conditioning Split':
        return ['Full Body', 'Cardio'];
      // ── Legacy splits (no longer selectable) ──────────────────────────────
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
      // ──────────────────────────────────────────────────────────────────────
      case 'Functional Training Split':
      case 'Circuit Training Split': // legacy
      case 'Full Body Training':
      default:
        return ['Full Body'];
    }
  }

  // Muscle names below use the ExerciseDB `targetMuscles` vocabulary so the
  // focus bonus in _selectExercisesForDay actually fires:
  // abductors, abs, biceps, calves, cardiovascular system, delts, forearms,
  // glutes, hamstrings, lats, pectorals, quads, spine, triceps, upper back.
  static Map<String, List<String>> get _focusMuscleMap => {
    'Full Body': ['pectorals', 'lats', 'quads', 'glutes', 'abs', 'delts'],
    'Full Body Cardio': ['cardiovascular system', 'quads', 'glutes', 'abs'],
    'HIIT': ['cardiovascular system', 'quads', 'glutes', 'abs'],
    'Cardio': ['cardiovascular system', 'quads', 'glutes', 'abs'],
    'Upper Body': [
      'pectorals',
      'lats',
      'delts',
      'biceps',
      'triceps',
      'upper back',
    ],
    'Lower Body': ['quads', 'glutes', 'hamstrings', 'calves'],
    'Core': ['abs', 'spine'],
    'Chest & Triceps': ['pectorals', 'triceps'],
    'Back & Biceps': ['lats', 'upper back', 'biceps'],
    'Legs': ['quads', 'glutes', 'hamstrings', 'calves'],
    'Shoulders & Arms': ['delts', 'biceps', 'triceps'],
    'Arms': ['biceps', 'triceps', 'forearms'],
  };

  /// Public, reusable focus→muscle resolver (ExerciseDB `targetMuscles`
  /// vocabulary). PlansScreen's picker/gap-fill/volume-debt paths call this so
  /// they resolve muscles in the same vocabulary the generator scores against —
  /// preventing the two from drifting (e.g. 'chest' vs 'pectorals').
  static List<String> musclesForFocus(String focus) =>
      _focusMuscleMap[focus] ??
      const ['pectorals', 'lats', 'quads', 'glutes', 'abs', 'delts'];

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

  /// Exercise count per day — driven by sessionMinutes, nudged by experience,
  /// scaled down by recoveryScore (poor sleep → fewer exercises), and reduced
  /// by one when the weekly adaptation says 'down' (volume, not frequency).
  int _exercisesPerDay(UserProfile profile, String difficultyBias) {
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

    // Adaptation: struggled last week → one fewer exercise per day
    if (difficultyBias == 'down') base--;

    return base.clamp(2, 10);
  }

  /// Sets per exercise — from goal/experience, reduced when recovery is low,
  /// nudged ±1 by the weekly adaptation bias.
  int _getSets(UserProfile profile, String difficultyBias) {
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
    // Adaptation: great week → +1 set, rough week → −1 set
    if (difficultyBias == 'up') sets++;
    if (difficultyBias == 'down') sets--;
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
