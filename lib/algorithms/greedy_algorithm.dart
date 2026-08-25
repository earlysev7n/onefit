import '../data/age_prescription.dart';
import '../data/physical_limitations.dart';
import '../models/exercise.dart';
import '../models/user_profile.dart';

/// An exercise's role within a session, used ONLY by the rep/rest prescription
/// (never by selection). Assigned after the day is selected and ordered:
/// [mainCompound] is the first compound in the day, [secondaryCompound] any
/// later compound, [isolation] everything else. Training Focus × goal × role
/// then picks the rep range so, e.g., a Balanced Muscle-Gain day opens heavy on
/// the main compound and finishes with higher-rep isolation.
enum _ExerciseRole { mainCompound, secondaryCompound, isolation }

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
  final int
  timePerSetSeconds; // work-timer duration per set (session-budget fit)

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
  /// Which days of the week are workout days (index 0 = Mon, 6 = Sun).
  /// Derived from the profile's split and days-per-week — deterministic for a
  /// given profile, no plan doc needed.
  static List<bool> workoutDayPattern(UserProfile profile) {
    final schedule = GreedyAlgorithm()._getSchedule(profile);
    return [for (final s in schedule) s != 'Rest'];
  }

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
  static final _pullupTag = RegExp(
    r'\b(pull.?up|chin.?up)\b',
    caseSensitive: false,
  );
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

    // Physical limitations (e.g. asthma) hard-exclude contraindicated moves.
    // Checked first so it applies to Gym users and blocks even bodyweight moves
    // like burpees. No-op when the user has no limitations (empty list).
    if (exerciseBlockedByLimitations(e, p.physicalLimitations)) {
      return false;
    }

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
        final hasBar = p.equipment.any((x) => x.toLowerCase() == 'pull-up bar');
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
      reasons.add(
        'Needs equipment you don\'t have (${e.equipment.join(', ')}).',
      );
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
  // Single-joint movement names — never a compound even if they list ≥2
  // secondary muscles (ExerciseDB often does). Checked before the secondary-count
  // heuristic so isolations (front raise, fly, curl, …) classify correctly.
  // Bare 'lateral' is excluded so "lateral lunge" stays compound; 'raise' covers
  // lateral/front/calf raise.
  static final _isolationKeywords = RegExp(
    r'\b(raise|fly|flye|curl|extension|kickback|pullover|'
    r'pushdown|shrug|pec deck|rear delt|wrist)\b',
  );

  static bool isStapleCompound(Exercise e) {
    final name = e.name.toLowerCase();
    if (_isolationKeywords.hasMatch(name)) return false;
    if (_compoundKeywords.hasMatch(name)) return true;
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

  //  SCORING — three SEPARATE dimensions, never mixed into one comparable score:
  //
  //    1. WORKOUT STRUCTURE (what muscles the session covers) — enforced
  //       structurally UPSTREAM (the day-focus hard pool + per-muscle cap +
  //       balance penalties), NOT scored here. An exercise is never picked
  //       *because* it is "full body"; the collection of picks provides the
  //       coverage.
  //    2. EXERCISE PREFERENCE (which TYPE) — the ONLY selection-relevant user
  //       ranking: Compound vs Isolation. The preferred type scores +2, the
  //       other +1 (see _exerciseTypePoints) — a small tie-breaker, not a lever.
  //       An exercise is compound XOR isolation, so exactly ONE type value is
  //       ever awarded — overlapping
  //       traits (heavy/high/full-body) add NOTHING here, which is what fixes
  //       the old double-count (a Bench Press no longer stacked compound+heavy).
  //    3. TRAINING FOCUS (how the picks are dosed) — heavy/balanced/high is a
  //       PRESCRIPTION preference applied AFTER selection (reps/rest, see
  //       _getReps / _getRestSeconds). It never influences the score.
  //
  //  Runs over candidates that already passed the hard filters (limitation ban /
  //  gender / location / equipment / experience gate), so those carry no score
  //  weight (they'd be constants). Two terms are fixed STRUCTURAL anchors: the
  //  day-focus bonus (+50) and the muscle-balance penalties (-25 day / -15 week).
  //  The middle block — Exercise-Type preference + goal match + Experience — is
  //  selected from the user's UserProfile so the same eligible pool ranks
  //  differently per user, and is CLAMPED to [-20, +45] so it can never overpower
  //  the balance penalties. sessionMinutes is deliberately NOT a ranking term —
  //  it only sizes the exercise COUNT via _fitExerciseCount. Reuses
  //  isStapleCompound / isHeavyCompound / difficultyAllowed / _goalKey.

  // Display names for the two selectable exercise TYPES. These are the only
  // selection-relevant preference the user ranks (Compound vs Isolation); the
  // profile UI reads these labels.
  static const Map<String, String> goalFeatureLabels = {
    'compound': 'Compound',
    'isolation': 'Isolation',
  };

  /// The default Compound-vs-Isolation order for an untouched profile. Compound
  /// is favoured first for every goal (matching the historical weighting), and
  /// the scorer only consumes this relative order (see [_exerciseTypePoints]),
  /// so it is a fixed, goal-independent default. The [fitnessGoal] parameter is
  /// retained for call-site/back-compat stability. Used as the fallback when the
  /// user hasn't customised the order (empty [UserProfile.goalPriorities]) and to
  /// seed the profile UI.
  static List<String> defaultGoalPriorities(String fitnessGoal) => const [
    'compound',
    'isolation',
  ];

  /// Selection points for an exercise's TYPE (Compound vs Isolation), from the
  /// user's [priorities] ranking. With only two mutually-exclusive types the
  /// score just needs a small, consistent tie-breaker: the preferred type → +2,
  /// the other → +1. An exercise is compound XOR isolation, so exactly one value
  /// is ever awarded — no stacking from heavy/high/full-body traits (they aren't
  /// selection signals). The gap (1) is deliberately far smaller than the
  /// day-focus (+50) and muscle-balance (−25/−15) anchors, so type taste only
  /// breaks a genuine tie and never overrides coverage/variety. Fallback when
  /// the list has neither key: compound preferred (the historical default).
  static int _exerciseTypePoints(List<String> priorities, bool isCompound) {
    final ci = priorities.indexOf('compound');
    final ii = priorities.indexOf('isolation');
    final compoundPreferred = ii < 0 || (ci >= 0 && ci < ii);
    final isPreferred = isCompound ? compoundPreferred : !compoundPreferred;
    return isPreferred ? 2 : 1;
  }

  // Selection bonus for a foundational heavy barbell/dumbbell compound (bench,
  // squat, OHP, row, deadlift) when the user prefers Compound — so the big lifts
  // are picked ahead of lighter/bodyweight compound variants of the same muscle.
  // Applied inside the clamped profile block, so it never overpowers the +50
  // focus anchor or the −25/−15 balance penalties.
  static const int _kHeavyCompoundBonus = 6;

  // Graduated experience score
  static const Map<String, Map<String, int>> _experienceWeights = {
    'Beginner': {'beginner': 8},
    'Intermediate': {'beginner': 4, 'intermediate': 8},
    'Advanced': {'beginner': 2, 'intermediate': 6, 'advanced': 10},
  };

  // Note: sessionMinutes deliberately does NOT influence ranking. It drives the
  // per-day exercise COUNT via _fitExerciseCount only. Ranking is decided by the
  // user's Exercise Priority (goalScore) + experience, so a short session gives
  // FEWER exercises without overriding which TYPE the user prioritised.

  double _scoreExercise({
    required Exercise exercise,
    required UserProfile profile,
    required List<String> targetMuscles,
    required Map<String, int> weeklyHits,
    required Map<String, int> dayHits,
  }) {
    double score = 0;

    // Structural anchor 1 — day focus (also a hard pool constraint upstream).
    if (exercise.primaryMuscles.any(targetMuscles.contains)) score += 50;

    // ── Selection block: goal match + Exercise-TYPE preference + Experience ──
    // The exercise TYPE (Compound vs Isolation) is the user-ranked selection
    // signal. goalMatch stays a fixed +15. Empty goalPriorities falls back to the
    // goal's built-in order so legacy profiles are unchanged. When the user
    // prefers Compound, foundational heavy barbell/dumbbell lifts additionally
    // get [_kHeavyCompoundBonus] so the big lifts (bench/squat/OHP/row) are
    // picked ahead of lighter/bodyweight compound variants of the same muscle.
    // (Training Focus heavy/high is prescription; Full Body is coverage — neither
    // scored here.)
    final compound = isStapleCompound(exercise) || isHeavyCompound(exercise);
    final goalKey = _goalKey(profile.fitnessGoal);
    final priorities = profile.goalPriorities.isNotEmpty
        ? profile.goalPriorities
        : defaultGoalPriorities(profile.fitnessGoal);
    final compoundPreferred = _exerciseTypePoints(priorities, true) == 2;

    int goalScore = 0;
    if (exercise.goals.contains(goalKey)) goalScore += 15; // goalMatch — fixed
    goalScore += _exerciseTypePoints(priorities, compound); // +2 or +1
    if (compoundPreferred && isHeavyCompound(exercise)) {
      goalScore += _kHeavyCompoundBonus; // surface the big lifts
    }

    int expScore = 0;
    if (difficultyAllowed(exercise.difficulty, profile.experienceLevel)) {
      expScore =
          _experienceWeights[profile.experienceLevel]?[exercise.difficulty] ??
          0;
    }

    // Clamp so the personalised block can't overpower the balance penalties.
    // (sessionMinutes is intentionally not a term here — it drives the exercise
    // count via _fitExerciseCount, not ranking.)
    double profileBlock = (goalScore + expScore).toDouble();
    if (profileBlock > 45) profileBlock = 45;
    if (profileBlock < -20) profileBlock = -20;
    score += profileBlock;

    // Structural anchor 2 — muscle balance: a strong day-local penalty forces
    // variety within a session; a milder weekly penalty spreads volume across
    // the week.
    for (final muscle in exercise.primaryMuscles) {
      score -= (dayHits[muscle] ?? 0) * 25;
      score -= (weeklyHits[muscle] ?? 0) * 15;
    }

    return score;
  }

  /// Public wrapper so callers (e.g. the exercise picker) can rank candidates
  /// with the same formula used during plan generation.
  double scoreExercise({
    required Exercise exercise,
    required UserProfile profile,
    required List<String> targetMuscles,
    required Map<String, int> weeklyHits,
    required Map<String, int> dayHits,
  }) => _scoreExercise(
    exercise: exercise,
    profile: profile,
    targetMuscles: targetMuscles,
    weeklyHits: weeklyHits,
    dayHits: dayHits,
  );

  /// Plain-language reasons why [exercise] was placed in a [focus] day for
  /// [profile]. Mirrors the real scoring in [_scoreExercise] so the "Why this
  /// exercise?" sheet never drifts from what actually drives generation. Pure —
  /// reads only the profile/exercise. Ordered most-important first.
  static List<String> explainSelection(
    Exercise exercise,
    UserProfile profile,
    String focus,
  ) {
    final reasons = <String>[];

    // Pinned anchor (force-included first by the generator).
    final pinned = (profile.pinnedExercises[focus] ?? const <String>[])
        .contains(exercise.id);
    if (pinned) {
      reasons.add('You pinned this as an anchor lift for $focus.');
    }

    // Day focus — the +50 structural anchor / hard pool constraint.
    final focusMuscles = musclesForFocus(focus);
    if (exercise.primaryMuscles.any(focusMuscles.contains)) {
      reasons.add("Targets today's focus ($focus).");
    } else if (exercise.secondaryMuscles.any(focusMuscles.contains)) {
      reasons.add("Supports today's $focus focus as a secondary mover.");
    }

    // Goal-tag match — fixed +15.
    final goalKey = _goalKey(profile.fitnessGoal);
    if (exercise.goals.contains(goalKey)) {
      reasons.add('Matches your ${profile.fitnessGoal} goal (+15).');
    }

    // Exercise-TYPE preference — Compound vs Isolation, the only user-ranked
    // selection signal. Reported with its rank position and the actual points
    // awarded (+2 preferred / +1 other). No heavy/high/full-body reasons —
    // those are prescription/coverage, not selection.
    final priorities = profile.goalPriorities.isNotEmpty
        ? profile.goalPriorities
        : defaultGoalPriorities(profile.fitnessGoal);
    final compound = isStapleCompound(exercise) || isHeavyCompound(exercise);
    final typeKey = compound ? 'compound' : 'isolation';
    final typeLabel = compound ? 'Compound' : 'Isolation';
    final typePoints = _exerciseTypePoints(priorities, compound);
    final typeRank = priorities.indexOf(typeKey);
    if (typeRank >= 0) {
      reasons.add(
        "It's a $typeLabel move — your #${typeRank + 1} exercise-type "
        'priority (+$typePoints).',
      );
    } else {
      reasons.add("It's a $typeLabel move (+$typePoints).");
    }

    // Foundational-lift bonus — surfaced when it actually applied to selection.
    if (_exerciseTypePoints(priorities, true) == 2 && isHeavyCompound(exercise)) {
      reasons.add(
        'Foundational barbell/dumbbell lift — prioritised (+$_kHeavyCompoundBonus).',
      );
    }

    // Training Focus — decides the REPS, not the selection. Surfaced so the
    // sheet explains why the rep range is what it is.
    final focusNote = <String, String>{
      'heavy': 'Heavy Lift focus — prescribed at lower reps / heavier load.',
      'high': 'High Rep focus — prescribed at higher reps.',
      'balanced': "Balanced focus — reps scale with the exercise's role "
          '(main compound heavier, isolation higher-rep).',
    }[profile.effectiveTrainingFocus];
    if (focusNote != null) reasons.add(focusNote);

    // Experience level — graduated bonus for level-appropriate difficulty.
    if (difficultyAllowed(exercise.difficulty, profile.experienceLevel)) {
      final w =
          _experienceWeights[profile.experienceLevel]?[exercise.difficulty] ??
          0;
      if (w > 0) {
        reasons.add('Suited to your ${profile.experienceLevel} level (+$w).');
      }
    }

    if (reasons.isEmpty) {
      reasons.add('Chosen to round out your $focus session while keeping variety.');
    }
    return reasons;
  }

  //  Main:
  List<WorkoutDay> generatePlan({
    required List<Exercise> allExercises,
    required UserProfile profile,
    String difficultyBias = 'same', // 'up' | 'down' | 'same'
    int anchorWeekday = 1,
    int weekIndex = 0, // 0-based week since the user started — drives the PPL
    // partial-block rotation so the "extra" day advances each week.
  }) {
    // Hard constraints: gender variant + location + equipment + bench (what
    // the user can physically do). Goal is a scoring signal, not a gate —
    // gating on it collapses the candidate pool (e.g. a Weight-Loss user
    // would be excluded from all chest/back/arm work).
    final _blocked = profile.blockedExercises.toSet();
    final filtered = allExercises
        .where((e) => isEligibleForUser(e, profile) && !_blocked.contains(e.id))
        .toList();

    // Build 7-day schedule from user's chosen split + available days.
    // workoutDaysPerWeek is a hard constraint: adaptation never adds or
    // removes training days — difficultyBias modulates per-day volume
    // (exercise count and sets) instead, per ACSM progression guidance.
    final schedule = _getSchedule(profile, weekIndex: weekIndex);

    final List<WorkoutDay> plan = [];
    // Per-focus hit tracker. The weekly muscle penalty is scoped to
    // DIFFERENT-focus days so Upper/PPL repeat days (Upper 2, Push 2) are
    // not penalised for training the same muscles as their first instance —
    // that repetition is intentional in structured splits.
    final hitsByFocus = <String, Map<String, int>>{};

    for (int i = 0; i < 7; i++) {
      final focus = schedule[i];
      final dayName = _dayName(i, anchorWeekday: anchorWeekday);

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

      // Build weeklyHits from all focuses except today's — same-focus
      // repetition carries no penalty (Upper day 2 sees no penalty for chest).
      final weeklyHits = <String, int>{};
      for (final entry in hitsByFocus.entries) {
        if (entry.key == focus) continue;
        for (final h in entry.value.entries) {
          weeklyHits[h.key] = (weeklyHits[h.key] ?? 0) + h.value;
        }
      }

      final targetMuscles = musclesForFocus(focus);
      // Session duration drives the exercise COUNT; NSCA goal loading drives the
      // per-set sets/reps/rest (computed inside _selectExercisesForDay). The
      // count budget uses FOCUS-INDEPENDENT rest + reps (_getRestSeconds
      // applyFocus:false, _countBudgetReps) so that changing Training Focus
      // changes the prescription but never the number of exercises.
      // Count budget uses focus- AND limitation-independent sets/rest so neither
      // Training Focus nor a physical-limitation modifier changes how many
      // exercises fit — only the per-set prescription.
      final daySets = _getSets(
        profile,
        difficultyBias,
        applyLimitation: false,
      );
      final dayRest = _getRestSeconds(profile, applyFocus: false);
      final dayWork = _estimateWorkSeconds(_countBudgetReps(profile));
      final dayExercises = _selectExercisesForDay(
        exercises: filtered,
        targetMuscles: targetMuscles,
        profile: profile,
        muscleHitCount: weeklyHits,
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

      final focusHits = hitsByFocus.putIfAbsent(focus, () => {});
      for (final we in dayExercises) {
        for (final m in we.exercise.primaryMuscles) {
          focusHits[m] = (focusHits[m] ?? 0) + 1;
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
  /// Public + static so scoring, ordering, and the interactive demo share one
  /// definition of a "foundational compound".
  static bool isHeavyCompound(Exercise e) =>
      _bigLiftKeywords.hasMatch(e.name.toLowerCase()) &&
      e.equipment.any((q) {
        final q2 = q.toLowerCase();
        // `_normalizeEquipment` stores the plural 'Dumbbells' for real catalog
        // data, so match both forms — otherwise dumbbell staples (dumbbell
        // bench/press/row/lunge) would silently never count as heavy compounds.
        return q2 == 'barbell' ||
            q2 == 'ez barbell' ||
            q2 == 'dumbbell' ||
            q2 == 'dumbbells';
      });

  // ── ACSM/NSCA 5-tier ordering — now the TIEBREAK, not the primary sort ────
  // Haff & Triplett, "Program Design for Resistance Training," Essentials of
  // S&C, 4th ed.: power/explosive first (peak CNS demand), then large
  // multi-joint lifts, then secondary compounds, then isolations, accessories
  // last. The post-selection sort now orders primarily by the user's Exercise
  // Priority ranking (see _priorityOrderIndex) and uses these tiers only to
  // break ties within a priority bucket. Applied after greedy selection so
  // scores/selection are unchanged.

  // Tier 1 — Olympic/plyometric movements. "jump" alone is omitted (would
  // catch "jumping jack"); "swing" omitted (too broad across the catalog).
  static final _powerKeywords = RegExp(
    r'\b(clean|snatch|jerk|push press|thruster|'
    r'box jump|broad jump|depth jump|jump squat|'
    r'plyometric|plyo|explosive)\b',
  );

  // Tier 5 — Corrective, prehab, and joint-support exercises scheduled last.
  // "plank" intentionally omitted (primary core exercise for beginners).
  static final _accessoryKeywords = RegExp(
    r'\b(face pull|reverse fly|pull.?apart|shrug|'
    r'pallof|dead bug|bird dog|rotator)\b',
  );

  /// Returns the ACSM/NSCA ordering tier for [e] (1 = first, 5 = last).
  /// Used only as the TIEBREAK in the post-selection sort — not a scoring input.
  static int _exerciseTier(Exercise e) {
    final name = e.name.toLowerCase();
    if (_powerKeywords.hasMatch(name)) return 1;
    if (isHeavyCompound(e)) return 2;
    if (isStapleCompound(e)) return 3;
    if (_accessoryKeywords.hasMatch(name)) return 5;
    return 4; // single-joint isolation (default)
  }

  /// Primary ordering key for the post-selection sort: the index of the
  /// exercise's TYPE (Compound/Isolation) in the user's [priorities] ranking, so
  /// the preferred type leads within a muscle group. Only Compound vs Isolation
  /// order the session now — heavy/high are prescription and full-body is
  /// coverage, so they no longer influence display order (the ACSM tier tiebreak
  /// still keeps big compounds ahead of accessories). Falls back to
  /// compound-first when the key is absent from the list.
  static int _priorityOrderIndex(Exercise e, List<String> priorities) {
    final compound = isStapleCompound(e) || isHeavyCompound(e);
    final key = compound ? 'compound' : 'isolation';
    final i = priorities.indexOf(key);
    return i >= 0 ? i : (compound ? 0 : 1);
  }

  /// Muscle-importance key for display ordering: the BEST (lowest) index of any
  /// of [e]'s PRIMARY muscles within the day's [targetMuscles] list. The focus
  /// lists ([_focusMuscleMap]) are authored big→small, so this yields "chest
  /// before triceps" on a Chest & Triceps day and groups the big movers first on
  /// a Full Body day. An exercise with no focus-primary muscle (an assist-only
  /// mover, e.g. a triceps close-grip bench on a Full Body day) gets
  /// `targetMuscles.length` → it sorts AFTER every focus mover. Empty
  /// targetMuscles → 0 for all (no muscle preference; matches selection, where an
  /// empty focus makes the whole pool eligible).
  static int _muscleFocusIndex(Exercise e, List<String> targetMuscles) {
    if (targetMuscles.isEmpty) return 0;
    int best = targetMuscles.length; // assist-only / no focus-primary → last
    for (final m in e.primaryMuscles) {
      final i = targetMuscles.indexOf(m);
      if (i >= 0 && i < best) best = i;
    }
    return best;
  }

  /// Public display-ordering comparator — the single source of truth for the
  /// on-card exercise sequence, shared by generation ([_selectExercisesForDay])
  /// and the persisted-plan load path (PlansScreen), so a saved plan reorders to
  /// the same rules without a manual regenerate. Keys, applied in order:
  ///   1. MUSCLE FOCUS ([_muscleFocusIndex]) — the day's big movers first, assist
  ///      movers last; this is what keeps a triceps close-grip bench below the
  ///      chest work even though it ranks as the user's #1 Heavy Lift.
  ///   2. EXERCISE PRIORITY ([_priorityOrderIndex]) — the user's ranked features
  ///      (heavy lifts lead WITHIN a muscle group).
  ///   3. ACSM/NSCA TIER ([_exerciseTier]) — final tiebreak.
  /// Pure/stateless; a stable sort with this comparator preserves the incoming
  /// order beneath equal keys.
  static int compareForDisplay(
    Exercise a,
    Exercise b, {
    required List<String> targetMuscles,
    required UserProfile profile,
  }) {
    final ma = _muscleFocusIndex(a, targetMuscles);
    final mb = _muscleFocusIndex(b, targetMuscles);
    if (ma != mb) return ma.compareTo(mb);

    final priorities = profile.goalPriorities.isNotEmpty
        ? profile.goalPriorities
        : defaultGoalPriorities(profile.fitnessGoal);
    final pa = _priorityOrderIndex(a, priorities);
    final pb = _priorityOrderIndex(b, priorities);
    if (pa != pb) return pa.compareTo(pb);

    return _exerciseTier(a).compareTo(_exerciseTier(b));
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

    // Post-selection display ordering — muscle-focus (big movers first, assist
    // movers last) → Exercise Priority (heavy lifts lead within a muscle) → ACSM
    // tier. Shared with the persisted-plan load path via compareForDisplay so
    // generation and reload never disagree. Dart's List.sort is stable, so greedy
    // pick order is preserved beneath equal keys — selection, scores, and muscle
    // balance are completely unchanged.
    selected.sort(
      (a, b) => GreedyAlgorithm.compareForDisplay(
        a,
        b,
        targetMuscles: targetMuscles,
        profile: profile,
      ),
    );
    final ordered = selected;

    // Prescription. Sets are day-constant (NSCA goal loading + adaptation's
    // difficultyBias); rest is day-constant with a Training-Focus nudge; reps
    // come from Training Focus × goal × per-exercise ROLE. Roles are assigned
    // over the DISPLAY ORDER so the main compound leads and isolation trails.
    final daySets = _getSets(profile, difficultyBias);
    final dayRest = _getRestSeconds(profile);
    final roles = _assignRoles(ordered);
    final result = <WorkoutExercise>[];
    for (int i = 0; i < ordered.length; i++) {
      final e = ordered[i];
      final reps = _getReps(profile, e.category, roles[i]);
      result.add(
        WorkoutExercise(
          exercise: e,
          sets: daySets,
          reps: reps,
          restSeconds: dayRest,
          timePerSetSeconds: _estimateWorkSeconds(reps),
        ),
      );
    }
    return result;
  }

  /// Assigns a prescription [_ExerciseRole] to each exercise in DISPLAY ORDER:
  /// the first non-cardio compound is [_ExerciseRole.mainCompound], later
  /// compounds are [_ExerciseRole.secondaryCompound], everything else (including
  /// cardio, whose reps come from the timed branch anyway) is
  /// [_ExerciseRole.isolation]. Pure/stateless; shared by generation and the
  /// persisted-plan re-prescription path ([represcribeDay]) so both dose alike.
  static List<_ExerciseRole> _assignRoles(List<Exercise> ordered) {
    final roles = <_ExerciseRole>[];
    bool mainAssigned = false;
    for (final e in ordered) {
      final isComp = isStapleCompound(e) || isHeavyCompound(e);
      if (e.category == 'cardio') {
        roles.add(_ExerciseRole.isolation);
      } else if (isComp && !mainAssigned) {
        roles.add(_ExerciseRole.mainCompound);
        mainAssigned = true;
      } else if (isComp) {
        roles.add(_ExerciseRole.secondaryCompound);
      } else {
        roles.add(_ExerciseRole.isolation);
      }
    }
    return roles;
  }

  /// Re-derive reps/rest/timer for an already-selected, already-ordered day from
  /// the CURRENT profile, preserving each exercise's set count (adaptation owns
  /// sets via difficultyBias; Training Focus owns reps/rest). Selection is
  /// untouched — same exercises, same order. Used by the persisted-plan load
  /// path so switching Training Focus updates the prescription with no
  /// regenerate. Returns null-free list in the same order it was given.
  List<WorkoutExercise> represcribeDay(
    UserProfile profile,
    List<WorkoutExercise> ordered,
  ) {
    final roles = _assignRoles(ordered.map((w) => w.exercise).toList());
    final dayRest = _getRestSeconds(profile);
    final result = <WorkoutExercise>[];
    for (int i = 0; i < ordered.length; i++) {
      final w = ordered[i];
      final reps = _getReps(profile, w.exercise.category, roles[i]);
      result.add(
        WorkoutExercise(
          exercise: w.exercise,
          sets: w.sets, // preserve adaptation-owned set count
          reps: reps,
          restSeconds: dayRest,
          timePerSetSeconds: _estimateWorkSeconds(reps),
        ),
      );
    }
    return result;
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
  List<String> _getSchedule(UserProfile profile, {int weekIndex = 0}) {
    final trainDays = profile.workoutDaysPerWeek.clamp(1, 7);
    final focusSequence = _splitFocusSequence(profile.workoutSplit);
    final schedule = List<String>.filled(7, 'Rest');

    if (focusSequence.length == 3) {
      // 3-focus cycle (PPL, legacy Hybrid) — a rest follows each completed
      // triple, and any PARTIAL trailing block rotates across weeks so the
      // "extra" day is balanced over time. The first triple always restarts
      // Push/Pull/Legs in order; the split is capped at 6 effective training
      // days so a week always keeps ≥1 rest (a 7-day selection trains 6).
      final seq = focusSequence;
      final effectiveTrain = trainDays.clamp(1, 6);
      final fullSecondTriple = effectiveTrain == 6;

      final sessions = <String>[];
      for (int i = 0; i < effectiveTrain; i++) {
        if (i < 3) {
          sessions.add(seq[i]); // first triple — natural order every week
        } else if (fullSecondTriple) {
          sessions.add(seq[i - 3]); // full 2nd triple — no rotation
        } else {
          sessions.add(seq[(weekIndex + (i - 3)) % 3]); // partial → rotate
        }
      }
      return _placeWithCycleRests(sessions, 3);
    } else if (focusSequence.length == 2 &&
        profile.workoutSplit == 'Upper / Lower Split') {
      // Upper/Lower — PAIRED ("connected"): train Upper then Lower back-to-back
      // (different muscle groups, safe consecutively), then rest, repeat. An odd
      // trailing day is always the FIRST focus (Upper) — fixed, no rotation
      // (seq[i % 2] yields U on even indices). No cap: non-rest count == days.
      final sessions = [for (int i = 0; i < trainDays; i++) focusSequence[i % 2]];
      return _placeWithCycleRests(sessions, 2);
    } else if (focusSequence.length > 3) {
      // Legacy 5-focus splits (Bro / Body-Part) — pack training days
      // consecutively so rest days fall after the full cycle, not inside it.
      // Each day targets different muscles, so consecutive days are safe.
      for (int i = 0; i < trainDays; i++) {
        schedule[i] = focusSequence[i % focusSequence.length];
      }
    } else {
      // Remaining single/dual-focus splits (Full Body, Functional, S+C) —
      // spread days evenly so the same muscle groups get adequate mid-week
      // recovery.
      final trainPositions = <int>{};
      for (int i = 0; i < trainDays; i++) {
        trainPositions.add((i * 7 / trainDays).floor());
      }
      int focusIdx = 0;
      for (int i = 0; i < 7; i++) {
        if (trainPositions.contains(i)) {
          schedule[i] = focusSequence[focusIdx % focusSequence.length];
          focusIdx++;
        }
      }
    }

    return schedule;
  }

  /// Places [sessions] into a 7-slot week (pre-filled 'Rest'), leaving a rest
  /// after each completed cycle of [cycleLen] sessions, capped so every session
  /// still fits in 7 days (`maxRests = 7 − sessions.length`). Shared by the
  /// PPL (cycleLen 3) and Upper/Lower (cycleLen 2) paired schedules.
  List<String> _placeWithCycleRests(List<String> sessions, int cycleLen) {
    final schedule = List<String>.filled(7, 'Rest');
    final maxRests = (7 - sessions.length).clamp(0, 7);
    int restsUsed = 0;
    int dayPtr = 0;
    for (int s = 0; s < sessions.length && dayPtr < 7; s++) {
      schedule[dayPtr++] = sessions[s];
      final completedCycle = (s + 1) % cycleLen == 0;
      if (completedCycle && restsUsed < maxRests && dayPtr < 7) {
        dayPtr++; // leave this slot as 'Rest'
        restsUsed++;
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
  // NOTE: these lists are MEMBERSHIP-only — the on-card display order is derived
  // by musclesForFocus sorting them big→small via [_muscleSizeOrder], so the
  // order they're written here does not matter.
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

  // Canonical big→small muscle ordering — the single source of on-card grouping
  // for every multi-muscle day (large groups first, small/accessory last).
  // 'cardiovascular system' leads so cardio-focus days open with conditioning.
  // Drives display order (via musclesForFocus → _muscleFocusIndex); the
  // _focusMuscleMap lists themselves are membership-only.
  static const List<String> _muscleSizeOrder = [
    'cardiovascular system',
    'quads', 'glutes', 'hamstrings', 'abductors', // legs / hips (largest)
    'pectorals', // chest
    'lats', 'upper back', // back
    'delts', // shoulders
    'biceps', 'triceps', 'forearms', // arms
    'calves',
    'abs', 'spine', // core (smallest / accessory)
  ];

  /// Public, reusable focus→muscle resolver (ExerciseDB `targetMuscles`
  /// vocabulary). PlansScreen's picker/gap-fill/volume-debt paths call this so
  /// they resolve muscles in the same vocabulary the generator scores against —
  /// preventing the two from drifting (e.g. 'chest' vs 'pectorals'). Returns the
  /// focus's muscles sorted big→small ([_muscleSizeOrder]) so every multi-muscle
  /// day displays large groups first (display-only; membership is unchanged).
  static List<String> musclesForFocus(String focus) {
    final muscles = List<String>.from(
      _focusMuscleMap[focus] ??
          const ['pectorals', 'lats', 'quads', 'glutes', 'abs', 'delts'],
    );
    int rank(String m) {
      final i = _muscleSizeOrder.indexOf(m);
      return i >= 0 ? i : _muscleSizeOrder.length; // unknown → last
    }

    muscles.sort((a, b) => rank(a).compareTo(rank(b)));
    return muscles;
  }

  /// Human-facing label for a stored [focus] key. DISPLAY ONLY — the raw focus
  /// string stays the [_focusMuscleMap] key and the persisted value, so this must
  /// NEVER be used where focus is a lookup/equality key. Adds the split ROLE
  /// (Push/Pull/…) to muscle-only labels so a PPL day reads "Pull (Back &
  /// Biceps)" instead of a bare "Back & Biceps". Labels that already read as a
  /// role (Full Body, Upper/Lower Body, Legs, Arms, Core, Rest Day) pass through.
  static String focusLabel(String focus) =>
      const {
        'Chest & Triceps': 'Push (Chest & Triceps)',
        'Back & Biceps': 'Pull (Back & Biceps)',
        'Shoulders & Arms': 'Push (Shoulders & Arms)', // legacy Bro/Body-Part
        'Cardio': 'Conditioning (Cardio)',
        'Full Body Cardio': 'Full Body Conditioning',
      }[focus] ??
      focus;

  //  HELPERS
  static String _goalKey(String goal) {
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

  // Physical-limitation prescription modifier (Asthma / High Blood Pressure).
  // A conservative dosing layer on top of the goal — informed by ACSM
  // hypertension guidance + rest-interval literature (see
  // physical_limitations.dart), not a verbatim prescribed protocol.
  static const int _kLimitationSetReduction = 1; // −1 set
  static const int _kLimitationSetFloor = 2; // never below 2 working sets
  static const int _kLimitationRestBonus = 45; // +45 s rest
  static const int _kLimitationRestCeiling = 210; // extended rest clamp (s)

  // Age prescription modifier (older adults, age >= kOlderAdultAge). A
  // conservative dosing layer on top of the goal — informed by ACSM older-adult
  // resistance-training guidance (see age_prescription.dart), not a verbatim
  // protocol. Stacks additively with the limitation modifier above; both share
  // the same 2-set floor and the extended _kLimitationRestCeiling (210 s). Reps
  // are untouched (older-adult guidance favours higher reps at moderate load).
  static const int _kAgeSetReduction = 1; // −1 set
  static const int _kAgeRestBonus = 30; // +30 s rest (gentler than the medical +45)

  /// Public view of the per-set rest this profile trains at (real prescription,
  /// focus + limitation applied). Mirrors [setsForDifficulty]; used by tests.
  int restSecondsForProfile(UserProfile profile) => _getRestSeconds(profile);

  int _getSets(
    UserProfile profile,
    String difficultyBias, {
    bool applyLimitation = true,
  }) {
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
    sets = sets.clamp(lo, hi);
    // Physical-limitation modifier (Asthma / High Blood Pressure): slightly fewer
    // sets, layered ON TOP of the goal — never below 2 working sets (a real
    // stimulus). Reps are untouched. Supports conservative resistance volume per
    // ACSM hypertension guidance (see physical_limitations.dart). Skipped for the
    // session-fit COUNT budget (applyLimitation:false) so exercise count is
    // unchanged — only the real prescription is dosed down.
    if (applyLimitation &&
        limitationsReduceIntensity(profile.physicalLimitations)) {
      sets = (sets - _kLimitationSetReduction).clamp(_kLimitationSetFloor, hi);
    }
    // Age modifier (older adults): a further conservative set reduction on top of
    // the goal, floored at 2 working sets. Stacks with the limitation modifier
    // above (both re-clamp to the floor, so combined they never drop below a real
    // stimulus). Skipped for the session-fit COUNT budget (applyLimitation:false)
    // so exercise count is unchanged — only the real prescription is dosed down.
    if (applyLimitation && ageReducesIntensity(profile.age)) {
      sets = (sets - _kAgeSetReduction).clamp(_kLimitationSetFloor, hi);
    }
    return sets;
  }

  /// Reps — the TRAINING-FOCUS prescription. Driven by the resolved Training
  /// Focus ([UserProfile.effectiveTrainingFocus]) × fitness goal × per-exercise
  /// [role], within NSCA goal-loading ranges (Essentials of S&C, 4th ed.):
  /// hypertrophy 6–12, muscular endurance ≥12, general 8–15, strength-leaning
  /// 4–8. Training Focus never changes WHICH exercise is picked — only how it is
  /// dosed here.
  ///   • heavy    → lower reps everywhere (main 4–6, secondary 6–8, iso 8–10)
  ///   • high     → higher reps everywhere (compounds 10–12, isolation 12–15)
  ///   • balanced → goal-dependent mix by role ([_balancedReps]); e.g. Muscle
  ///                Gain opens heavy on the main compound and finishes higher-rep
  /// Cardio + conditioning splits stay timed/circuit and ignore focus/role.
  String _getReps(UserProfile profile, String category, _ExerciseRole role) {
    final split = profile.workoutSplit;
    if (split == 'HIIT + Strength Split' || split == 'Circuit Training Split') {
      return category == 'cardio' ? '60 sec' : '15-20';
    }
    if (category == 'cardio') return '45 sec';
    return switch (profile.effectiveTrainingFocus) {
      'heavy' => switch (role) {
        _ExerciseRole.mainCompound => '4-6',
        _ExerciseRole.secondaryCompound => '6-8',
        _ExerciseRole.isolation => '8-10',
      },
      'high' => role == _ExerciseRole.isolation ? '12-15' : '10-12',
      _ => _balancedReps(profile.fitnessGoal, role), // 'balanced'
    };
  }

  /// Balanced prescription — a goal-dependent MIX of rep ranges by exercise
  /// role, so "Balanced" is never a flat 8–12: the main compound trains at the
  /// goal's heavier end, isolation at its higher-rep end. Stays inside the NSCA
  /// ranges the app already uses per goal.
  String _balancedReps(String goal, _ExerciseRole role) => switch (goal) {
    'Muscle Gain' => switch (role) {
      _ExerciseRole.mainCompound => '4-8',
      _ExerciseRole.secondaryCompound => '8-12',
      _ExerciseRole.isolation => '10-15',
    },
    'Weight Loss' => switch (role) {
      _ExerciseRole.mainCompound => '8-12',
      _ExerciseRole.secondaryCompound => '10-12',
      _ExerciseRole.isolation => '12-15',
    },
    'Endurance' => switch (role) {
      _ExerciseRole.mainCompound => '10-12',
      _ExerciseRole.secondaryCompound => '12-15',
      _ExerciseRole.isolation => '15-20',
    },
    _ => switch (role) {
      // General Fitness — moderate mixture.
      _ExerciseRole.mainCompound => '8-10',
      _ExerciseRole.secondaryCompound => '10-12',
      _ExerciseRole.isolation => '12-15',
    },
  };

  /// FOCUS-INDEPENDENT representative rep range per goal, used ONLY to size the
  /// session-fit exercise COUNT ([_fitExerciseCount]). Keeping it independent of
  /// Training Focus is what guarantees that changing focus changes the reps but
  /// never the number of exercises. Mirrors the legacy goal-based rep bands so
  /// counts are unchanged from before this refactor.
  String _countBudgetReps(UserProfile profile) {
    if (profile.fitnessGoal == 'Muscle Gain') return '8-12';
    if (profile.fitnessGoal == 'Weight Loss' ||
        profile.fitnessGoal == 'Endurance') {
      return '15-20';
    }
    return '12-15';
  }

  /// Rest seconds — within the NSCA goal-loading rest ranges (Essentials of S&C,
  /// 4th ed.): hypertrophy 30 s–1.5 min, muscular endurance ≤30 s (circuit
  /// tolerance up to ~45 s for weight loss), strength 2–5 min; conditioning-style
  /// splits get the shortest rests. A modest Training-Focus nudge (heavy → longer
  /// rest, high → shorter) keeps the loading coherent (heavy 4–6-rep work needs
  /// more recovery), clamped to a NSCA-reasonable [30, 180] s.
  ///
  /// [applyFocus] is false when sizing the exercise COUNT ([_fitExerciseCount]),
  /// so that changing Training Focus never changes how many exercises fit — only
  /// the prescription. It is true (default) for the actual per-set prescription.
  int _getRestSeconds(UserProfile profile, {bool applyFocus = true}) {
    final split = profile.workoutSplit;
    int base;
    if (split == 'HIIT + Strength Split' || split == 'Circuit Training Split') {
      base = 30; // NSCA endurance / circuit
    } else if (split == 'Strength + Conditioning Split') {
      base = 60;
    } else if (profile.fitnessGoal == 'Muscle Gain') {
      base = 90; // NSCA hypertrophy max
    } else if (profile.fitnessGoal == 'Weight Loss' ||
        profile.fitnessGoal == 'Endurance') {
      base = 45; // NSCA endurance baseline (≤30 s) + circuit tolerance
    } else {
      base = 60; // general
    }
    if (applyFocus) {
      switch (profile.effectiveTrainingFocus) {
        case 'heavy':
          base += 30;
          break;
        case 'high':
          base -= 15;
          break;
      }
      // Conservative rest extensions layered on top of the goal/focus rest, for
      // fuller recovery. Both the physical-limitation modifier (Asthma / High
      // Blood Pressure) and the age modifier (older adults) apply here and STACK;
      // either one widens the ceiling to _kLimitationRestCeiling (210 s). Supports
      // longer recovery intervals per ACSM hypertension guidance + the
      // rest-interval literature (see physical_limitations.dart) and ACSM
      // older-adult guidance (see age_prescription.dart). Only applied with the
      // focus (real prescription) — the count budget uses applyFocus:false, so
      // exercise count is unchanged.
      var extended = false;
      if (limitationsReduceIntensity(profile.physicalLimitations)) {
        base += _kLimitationRestBonus;
        extended = true;
      }
      if (ageReducesIntensity(profile.age)) {
        base += _kAgeRestBonus;
        extended = true;
      }
      if (extended) return base.clamp(30, _kLimitationRestCeiling);
    }
    return base.clamp(30, 180);
  }

  String _dayName(int index, {int anchorWeekday = 1}) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[(anchorWeekday - 1 + index) % 7];
  }
}
