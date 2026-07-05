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
    exercises: (m['exercises'] as List? ?? [])
        .map((e) => WorkoutExercise.fromMap(e as Map<String, dynamic>))
        .toList(),
  );
}

class WorkoutExercise {
  final Exercise exercise;
  final int sets;
  final String reps; // e.g. "10-12" or "30 sec"
  final int restSeconds;
  final int timePerSetSeconds; // work-timer duration per set (session-budget fit)

  WorkoutExercise({
    required this.exercise,
    required this.sets,
    required this.reps,
    required this.restSeconds,
    this.timePerSetSeconds = 45,
  });

  Map<String, dynamic> toMap() => {
    'exercise': exercise.toMap(),
    'sets': sets,
    'reps': reps,
    'restSeconds': restSeconds,
    'timePerSetSeconds': timePerSetSeconds,
  };

  factory WorkoutExercise.fromMap(Map<String, dynamic> m) => WorkoutExercise(
    exercise: Exercise.fromMap(m['exercise'] as Map<String, dynamic>),
    sets: m['sets'] as int? ?? 3,
    reps: m['reps'] as String? ?? '10-12',
    restSeconds: m['restSeconds'] as int? ?? 60,
    timePerSetSeconds: m['timePerSetSeconds'] as int? ?? 45,
  );
}

class GreedyAlgorithm {
  // ── ELIGIBILITY — hard constraints, shared with PlansScreen edit paths ─────
  static final _maleTag = RegExp(r'\bmale\b'); // does NOT match "female"
  static final _femaleTag = RegExp(r'\bfemale\b');
  static final _benchTag = RegExp(r'\b(incline|decline|bench)\b');
  // Some API exercises are mis-tagged with home equipment (e.g. 'pull-up bar')
  // but are actually cable/machine moves — catch them by name so they can never
  // appear in a home plan regardless of what the cached equipment list says.
  static final _gymOnlyName = RegExp(
    r'\b(cable|smith machine|leverage machine)\b',
  );
  // Barbell lifts that need a power/squat rack to start (bar racked at
  // shoulder/upper-chest height). Floor-start barbell work — deadlift, row,
  // overhead press (cleaned), hip thrust, RDL — is NOT here, so it stays
  // eligible on a bare 'Barbell' chip without a rack.
  static final _rackTag = RegExp(r'\b(squat|bench press)\b');
  // Pull-up/chin-up moves are bodyweight-powered but still need a bar.
  static final _pullupTag = RegExp(r'\b(pull.?up|chin.?up)\b', caseSensitive: false);
  static const _freeWeights = {
    'dumbbells',
    'barbell',
    'ez barbell',
    'kettlebells',
  };
  static const _barbellEquip = {'barbell', 'ez barbell'};

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
    // Name-based gym-only guard: some exercises are mis-tagged with home
    // equipment (e.g. 'pull-up bar') by the API but are actually cable/machine
    // moves — "Inverse Leg Curl (on Pull-up Cable Machine)" being the example.
    if (_gymOnlyName.hasMatch(name)) return false;

    // ...with equipment the user owns. Bodyweight is always available — the
    // profile guarantees a 'Bodyweight' chip (see ProfileInputScreen), so a
    // bodyweight-only home user always has a usable pool.
    final exEquip = e.equipment.map((x) => x.toLowerCase()).toList();
    final isBodyweight = exEquip.contains('bodyweight');
    if (isBodyweight) {
      // Pull-up/chin-up moves are bodyweight-powered but still need a bar;
      // gate them on the 'Pull-up Bar' chip exactly like _rackTag / _benchTag.
      if (_pullupTag.hasMatch(name)) {
        final hasBar = p.equipment.any((x) => x.toLowerCase() == 'pull-up bar');
        if (!hasBar) return false;
      }
      return true;
    }

    final userEquip = p.equipment.map((x) => x.toLowerCase()).toSet();
    final hasBarbell = userEquip.contains('barbell'); // chip covers ez barbell
    final hasBench = userEquip.contains('bench');
    final hasRack = userEquip.contains('home gym'); // power/squat rack
    final usesBarbell = exEquip.any(_barbellEquip.contains);

    // Equipment intersection. The 'Barbell' chip stands in for both 'barbell'
    // and 'ez barbell', so an ez-bar move is owned if the user has Barbell.
    final owns = exEquip.any(userEquip.contains) || (usesBarbell && hasBarbell);
    if (!owns) return false;

    // Rack-dependent barbell lifts (back/front squat, bench press) need a rack;
    // declared via the 'Home Gym' chip. Floor-start barbell work is unaffected.
    if (usesBarbell && _rackTag.hasMatch(name) && !hasRack) return false;

    // Free-weight incline/decline/bench moves need a bench. Bodyweight variants
    // (decline push-up etc.) already returned above — a couch or stairs will do.
    if (_benchTag.hasMatch(name) &&
        exEquip.any(_freeWeights.contains) &&
        !hasBench) {
      return false;
    }
    return true;
  }

  /// Human-readable equipment/location restrictions [e] fails for [p]
  /// (empty = no restriction). Mirrors the gates in [isEligibleForUser]; keep
  /// in sync. Gender-variant duplicates are NOT reported (not a real
  /// restriction). Used by PlansScreen's picker to warn-then-allow so the user
  /// can deliberately add a move they don't have the gear for.
  static List<String> equipmentRestrictions(Exercise e, UserProfile p) {
    final reasons = <String>[];
    // At a gym everything is available — no equipment restriction.
    if (p.workoutLocation == 'Gym') return reasons;

    final name = e.name.toLowerCase();

    if (!e.locations.contains('home')) {
      reasons.add('Not typically doable at home.');
      return reasons;
    }
    if (_gymOnlyName.hasMatch(name)) {
      reasons.add('Requires gym machine equipment (cable / Smith / leverage).');
      return reasons;
    }

    final exEquip = e.equipment.map((x) => x.toLowerCase()).toList();
    final isBodyweight = exEquip.contains('bodyweight');
    if (isBodyweight) {
      if (_pullupTag.hasMatch(name)) {
        final hasBar =
            p.equipment.any((x) => x.toLowerCase() == 'pull-up bar');
        if (!hasBar) reasons.add('Needs a Pull-up Bar you don\'t have.');
      }
      return reasons;
    }

    final userEquip = p.equipment.map((x) => x.toLowerCase()).toSet();
    final hasBarbell = userEquip.contains('barbell');
    final hasBench = userEquip.contains('bench');
    final hasRack = userEquip.contains('home gym');
    final usesBarbell = exEquip.any(_barbellEquip.contains);

    final owns = exEquip.any(userEquip.contains) || (usesBarbell && hasBarbell);
    if (!owns) {
      reasons.add('Needs equipment you don\'t have (${e.equipment.join(', ')}).');
    }
    if (usesBarbell && _rackTag.hasMatch(name) && !hasRack) {
      reasons.add('Needs a squat/bench rack (Home Gym) you don\'t have.');
    }
    if (_benchTag.hasMatch(name) &&
        exEquip.any(_freeWeights.contains) &&
        !hasBench) {
      reasons.add('Needs a Bench you don\'t have.');
    }
    return reasons;
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
    final filtered = allExercises
        .where((e) => isEligibleForUser(e, profile))
        .toList();

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
      // Session duration drives the exercise COUNT; NSCA goal loading drives the
      // per-set sets/reps/rest (computed inside _selectExercisesForDay).
      final daySets = _getSets(profile, difficultyBias);
      final dayRest = _getRestSeconds(profile);
      final dayWork = _estimateWorkSeconds(_getReps(profile, 'strength'));
      final dayExercises = _selectExercisesForDay(
        exercises: filtered,
        targetMuscles: targetMuscles,
        profile: profile,
        muscleHitCount: muscleHitCount,
        count: _fitExerciseCount(
          profile: profile,
          sets: daySets,
          restSeconds: dayRest,
          work: dayWork,
          poolSize: filtered.length,
        ),
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

  // Explicit big-lift movement patterns — true multi-joint barbell/dumbbell
  // movements that should always open a strength day. Deliberately excludes
  // isolation patterns: "french press" (tricep), "front raise" (delt), and
  // "pullover" (single-joint) do not match any term here.
  static final _bigLiftKeywords = RegExp(
    r'\b(squat|deadlift|hip thrust|lunge|row|'
    r'bench press|incline press|decline press|'
    r'overhead press|military press|shoulder press)\b',
  );

  /// True multi-joint barbell/dumbbell lift — squat, deadlift, bench press,
  /// row, OHP etc. Isolation exercises with barbell (french press, front raise,
  /// pullover) do not match [_bigLiftKeywords] and are correctly excluded.
  bool _isHeavyCompound(Exercise e) =>
      _bigLiftKeywords.hasMatch(e.name.toLowerCase()) &&
      e.equipment.any((q) {
        final q2 = q.toLowerCase();
        return q2 == 'barbell' || q2 == 'ez barbell' || q2 == 'dumbbell';
      });

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

    // Day focus is a HARD pool constraint, not just a score: only exercises that
    // train the focus may be selected, falling back to secondary-mover matches,
    // and the day stays shorter rather than ever pulling in an unrelated muscle.
    // (Relying on the +50 focus score alone let a fresh off-focus muscle — e.g.
    // forearms, which no focus targets and so carries 0 weekly-balance penalty —
    // outscore a heavily-used focus muscle on late-week days: a wrist curl landed
    // on Leg day.) musclesForFocus always returns a non-empty set, so this is safe.
    final primaryPool = targetMuscles.isEmpty
        ? eligible
        : eligible
              .where((e) => e.primaryMuscles.any(targetMuscles.contains))
              .toList();
    final assistPool = targetMuscles.isEmpty
        ? const <Exercise>[]
        : eligible
              .where(
                (e) =>
                    !e.primaryMuscles.any(targetMuscles.contains) &&
                    e.secondaryMuscles.any(targetMuscles.contains),
              )
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
          if (e.id == id) {
            pin = e;
            break;
          }
        }
        if (pin == null) continue;
        selected.add(pin);
        seenIds.add(pin.id);
        for (final m in pin.primaryMuscles) {
          dayHits[m] = (dayHits[m] ?? 0) + 1;
        }
      }
    }

    // Incremental greedy over a given pool: pick best, update day-local muscle
    // hits, re-score, repeat. `enforceCap` applies the per-muscle-per-day cap.
    void fill(List<Exercise> pool, bool enforceCap) {
      while (selected.length < count) {
        Exercise? best;
        double bestScore = double.negativeInfinity;
        for (final e in pool) {
          if (seenIds.contains(e.id)) continue;
          if (enforceCap &&
              e.primaryMuscles.any((m) => (dayHits[m] ?? 0) >= perMuscleCap)) {
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
    }

    // Prefer exercises WITH a demo GIF — a generated plan shouldn't recommend an
    // exercise it can't animate. GIF-having focus pools are tried first (primary,
    // then assist); the full pools (incl. no-GIF) are a graceful fallback only
    // when the GIF pool can't reach `count`, so days never starve. `fill` skips
    // seenIds, so the fallback rounds only add what the GIF rounds missed. When
    // no exercise has a GIF the GIF pools are empty and this is identical to the
    // original primary→primary→assist sequence.
    bool hasGif(Exercise e) => e.gifUrl != null && e.gifUrl!.isNotEmpty;
    final primaryGif = primaryPool.where(hasGif).toList();
    final assistGif = assistPool.where(hasGif).toList();

    fill(primaryGif, true);
    if (selected.length < count) fill(primaryGif, false);
    if (selected.length < count) fill(assistGif, false);
    if (selected.length < count) fill(primaryPool, true);
    if (selected.length < count) fill(primaryPool, false);
    if (selected.length < count) fill(assistPool, false);

    // 3-tier compound-first sort: barbell/dumbbell compounds (squat, deadlift,
    // bench, row) → bodyweight compounds (push-up, pull-up, dip) → isolations.
    // Pure reorder — selection, counts, and muscle balance are unchanged.
    final ordered = <Exercise>[
      ...selected.where(_isHeavyCompound),
      ...selected.where((e) => isStapleCompound(e) && !_isHeavyCompound(e)),
      ...selected.where((e) => !isStapleCompound(e)),
    ];

    // Sets and rest are profile-derived (NSCA goal loading) and constant for the
    // whole day; per-set reps/work-timer length vary per exercise (cardio vs lift).
    final daySets = _getSets(profile, difficultyBias);
    final dayRest = _getRestSeconds(profile);
    return ordered.map((e) {
      final reps = _getReps(profile, e.category);
      return WorkoutExercise(
        exercise: e,
        sets: daySets,
        reps: reps,
        restSeconds: dayRest,
        timePerSetSeconds: _estimateWorkSeconds(reps),
      );
    }).toList();
  }

  /// Per-set work-timer length (seconds), estimated from the prescription so the
  /// session-duration fit (see [_fitExerciseCount]) is realistic. NOT an NSCA
  /// loading parameter — it only sizes the live countdown the user can cut short.
  /// Timed move ("45 sec") → that value; rep range "A-B"/"A" → ~3s/rep + setup.
  int _estimateWorkSeconds(String reps) {
    final lower = reps.toLowerCase();
    final nums = RegExp(
      r'\d+',
    ).allMatches(lower).map((m) => int.parse(m.group(0)!)).toList();
    if (lower.contains('sec') && nums.isNotEmpty) {
      return nums.first.clamp(30, 75);
    }
    final maxRep = nums.isEmpty ? 12 : nums.reduce((a, b) => a > b ? a : b);
    return (maxRep * 3 + 15).clamp(30, 75);
  }

  /// Duration-driven Greedy selection lever (Objective 4): the user's chosen
  /// [UserProfile.sessionMinutes] decides HOW MANY exercises to select, while the
  /// per-set loading (sets/reps/rest) stays pinned to the NSCA goal ranges. Picks
  /// the largest exercise count that still fits the time budget (never over);
  /// when NSCA-bounded volume can't fill a long session we accept the undershoot.
  int _fitExerciseCount({
    required UserProfile profile,
    required int sets,
    required int restSeconds,
    required int work,
    required int poolSize,
  }) {
    const warmupReserveSec = 180; // gated warm-up phase before the lifts
    final budget = profile.sessionMinutes * 60 - warmupReserveSec;
    // Split breadth cap: a Full Body day covers ~6 muscle groups → at most one
    // exercise each, so it never balloons (never 7). Frequency temper: a muscle
    // trained more often (≥5 days/wk) needs less per-session breadth — NSCA
    // weekly-volume distribution.
    int maxE = profile.workoutDaysPerWeek >= 5 ? 5 : 6;
    if (poolSize < maxE) maxE = poolSize;
    if (maxE < 1) maxE = 1;
    // Largest count that still fits the time budget (never over). Starting at 1
    // guarantees a non-empty day even when only one exercise fits; for any
    // realistic session the fit grows toward maxE.
    int planned(int e) => e * sets * work + (e * sets - 1) * restSeconds;
    int best = 1;
    for (int e = 1; e <= maxE; e++) {
      if (planned(e) <= budget) {
        best = e;
      } else {
        break;
      }
    }
    return best;
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

  /// Sets per exercise — pinned to the NSCA goal-loading ranges and never
  /// stretched to fill session time (NSCA — Sheppard & Triplett, "Program Design
  /// for Resistance Training," in Essentials of Strength Training and
  /// Conditioning, 4th ed.): hypertrophy 3–6 (capped 5 here), muscular endurance
  /// 2–3, general 2–4. Experience picks within the range; recovery/adaptation
  /// nudge ±1 but the final clamp keeps it inside the goal's NSCA range.
  /// Public view of the set count this profile would train at for a given
  /// difficulty bias. Lets callers detect when an 'up'/'down' is fully absorbed
  /// by the NSCA range clamp (i.e. produces no real volume change) so a
  /// misleading "stepped up/down" message can be swapped (see plans_screen W2).
  int setsForDifficulty(UserProfile profile, String difficultyBias) =>
      _getSets(profile, difficultyBias);

  int _getSets(UserProfile profile, String difficultyBias) {
    int sets;
    int lo, hi; // NSCA set range for the goal
    if (profile.fitnessGoal == 'Muscle Gain') {
      lo = 3;
      hi = 5; // NSCA hypertrophy 3–6, capped at 5
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
    } else if (profile.fitnessGoal == 'Weight Loss' ||
        profile.fitnessGoal == 'Endurance') {
      lo = 2;
      hi = 3; // NSCA muscular endurance 2–3
      sets = profile.experienceLevel == 'Beginner' ? 2 : 3;
    } else {
      lo = 2;
      hi = 4; // general / maintenance
      sets = profile.experienceLevel == 'Advanced' ? 4 : 3;
    }
    // Adaptation: great week → +1 set, rough week → −1 set
    if (difficultyBias == 'up') sets++;
    if (difficultyBias == 'down') sets--;
    return sets.clamp(lo, hi);
  }

  /// Reps — from goal and split style, within the NSCA goal-loading ranges
  /// (Essentials of S&C, 4th ed.): hypertrophy 6–12, muscular endurance ≥12,
  /// general 8–15; conditioning splits use timed/higher-rep work.
  String _getReps(UserProfile profile, String category) {
    final split = profile.workoutSplit;
    if (split == 'HIIT + Strength Split' || split == 'Circuit Training Split') {
      return category == 'cardio' ? '60 sec' : '15-20';
    }
    if (split == 'Strength + Conditioning Split') {
      return category == 'cardio' ? '45 sec' : '8-12';
    }
    if (category == 'cardio') return '45 sec';
    if (profile.fitnessGoal == 'Weight Loss' ||
        profile.fitnessGoal == 'Endurance') {
      return '15-20';
    }
    if (profile.fitnessGoal == 'Muscle Gain') return '8-12';
    return '12-15';
  }

  /// Rest seconds — within the NSCA goal-loading rest ranges (Essentials of S&C,
  /// 4th ed.): hypertrophy 30 s–1.5 min, muscular endurance ≤30 s (circuit
  /// tolerance up to ~45 s for weight loss), strength 2–5 min; conditioning-style
  /// splits get the shortest rests.
  int _getRestSeconds(UserProfile profile) {
    final split = profile.workoutSplit;
    if (split == 'HIIT + Strength Split' || split == 'Circuit Training Split') {
      return 30; // NSCA endurance / circuit
    }
    if (split == 'Strength + Conditioning Split') return 60;
    if (profile.fitnessGoal == 'Muscle Gain') return 90; // NSCA hypertrophy max
    if (profile.fitnessGoal == 'Weight Loss' ||
        profile.fitnessGoal == 'Endurance') {
      return 45; // NSCA endurance baseline (≤30 s) + circuit tolerance
    }
    return 60; // general
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
