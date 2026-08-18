class UserProfile {
  final String uid;
  final String name;
  final String gender;
  final int age;
  final double weight; // always stored in kg internally
  final double height; // always stored in cm internally
  final String fitnessGoal;
  final String experienceLevel;
  final String workoutLocation;
  final List<String> equipment;
  final List<String> dietaryRestrictions;
  final List<String> foodAllergies;

  /// Common physical limitations the user reports (e.g. 'Asthma', 'Knee
  /// injury/pain'). Each maps to a set of contraindicated exercise patterns in
  /// [kPhysicalLimitations]; the greedy generator hard-excludes matching moves
  /// via [exerciseBlockedByLimitations]. Defaults empty for backward-compatible
  /// Firestore reads. This is a conservative auto-filter, not medical advice.
  final List<String> physicalLimitations;

  /// Specific movements the user opted to avoid within a selected limitation
  /// area (e.g. 'Barbell Squat', 'Lateral Raise'). Each maps to an
  /// [AvoidableMovement] in [kPhysicalLimitations]; the greedy generator
  /// hard-excludes matching moves via [exerciseBlockedByLimitations]. Distinct
  /// from [physicalLimitations] (the always-on auto-block layer). Defaults empty
  /// for backward-compatible Firestore reads.
  final List<String> avoidedMovements;

  final String unitSystem; // 'metric' or 'imperial'

  // Profiling — workload, recovery & scheduling inputs
  final String
  activityLevel; // Sedentary | Lightly Active | Moderately Active | Very Active | Extra Active
  final int workoutDaysPerWeek; // 1–7
  final int sessionMinutes; // 30 | 45 | 60 | 90
  final String
  workoutSplit; // weekly split style (see ProfileInputScreen split cards)

  /// Training prescription bias — 'heavy' | 'balanced' | 'high' | '' (default).
  ///
  /// This is a PRESCRIPTION preference, not a selection one: it never changes
  /// which exercises the greedy generator picks, only how the SELECTED exercises
  /// are dosed (rep ranges, and a small rest nudge). Empty means "use the
  /// fitness-goal default" — see [effectiveTrainingFocus]. Kept separate from
  /// [goalPriorities] (which now only ranks Compound vs Isolation for selection)
  /// so the two axes can't stack into one misleading score. Defaults empty for
  /// backward-compatible Firestore reads; legacy profiles therefore fall back to
  /// the goal default, which reproduces the old goal-only rep behaviour.
  final String trainingFocus;

  /// Accumulated weekly calorie-goal adaptation (kcal). Added on top of the
  /// goal-derived base in [calorieGoal]; fed by [AdaptationEngine] each new
  /// week and by manual edits. Clamped to ±500 by the provider to prevent drift.
  final int calorieAdjustment;

  /// The `weekId` (e.g. `week_2026_25`) of the last week the [AdaptationEngine]
  /// adapted this profile. Guards the weekly calorie nudge so it applies once
  /// per week even when the plan is force-regenerated (which deletes the plan
  /// doc and re-enters the fresh-generation branch). Empty until first adapted.
  final String lastAdaptationWeekId;

  /// Anchor lifts the user wants guaranteed in a given day focus, keyed by the
  /// split focus name (e.g. "Upper Body" → ["<exerciseId>"]). The generator
  /// force-includes these first (still gated by eligibility) so a key lift like
  /// bench press is always present, which is what makes progressive overload
  /// trackable. Defaults empty for backward-compatible Firestore reads.
  final Map<String, List<String>> pinnedExercises;

  /// Exercise IDs the user has opted to never see again. Filtered out of all
  /// automatic plan generation and smart replacement candidates. Defaults
  /// empty for backward-compatible Firestore reads.
  final List<String> blockedExercises;

  /// Stored ranking of the greedy scorer's exercise "features" (`compound`,
  /// `isolation`, `heavyLift`, `fullBody`, `highRep`). After the three-axis
  /// refactor the scorer reads **only the Compound-vs-Isolation order** from this
  /// list (preferred type → +2, other → +1, a small tie-breaker via
  /// [GreedyAlgorithm]._exerciseTypePoints); the remaining keys are retained for
  /// backward-compatible storage but no longer affect selection (Heavy Lift /
  /// High Rep moved to [trainingFocus] as prescription; Full Body is workout
  /// coverage, enforced structurally, not scored). Empty (the default) → the
  /// goal's built-in order via [GreedyAlgorithm.defaultGoalPriorities], so legacy
  /// profiles are unchanged. Edited in the profile screen as a 2-item Compound /
  /// Isolation drag list (reconstructed to the full 5-item shape on save).
  final List<String> goalPriorities;

  /// When the account was created. Anchors the adaptive "week" so days **before**
  /// the account existed aren't read as under-eaten (which would inflate the
  /// daily goal) or as a completed training week. Nullable for backward-compatible
  /// Firestore reads — legacy profiles fall back to the calendar week / auth
  /// creation time.
  final DateTime? createdAt;

  UserProfile({
    required this.uid,
    required this.name,
    required this.gender,
    required this.age,
    required this.weight,
    required this.height,
    required this.fitnessGoal,
    required this.experienceLevel,
    required this.workoutLocation,
    required this.equipment,
    required this.dietaryRestrictions,
    this.foodAllergies = const [],
    this.physicalLimitations = const [],
    this.avoidedMovements = const [],
    this.unitSystem = 'metric',
    this.activityLevel = 'Moderately Active',
    this.workoutDaysPerWeek = 3,
    this.sessionMinutes = 45,
    this.workoutSplit = 'Full Body Training',
    this.trainingFocus = '',
    this.calorieAdjustment = 0,
    this.lastAdaptationWeekId = '',
    this.pinnedExercises = const {},
    this.blockedExercises = const [],
    this.goalPriorities = const [],
    this.createdAt,
  });

  /// Resolved training focus: the explicit [trainingFocus] when set, otherwise
  /// the fitness-goal default. This is the single value the greedy prescription
  /// reads, so a legacy profile (empty [trainingFocus]) behaves exactly like a
  /// fresh profile on that goal. The user's explicit choice always wins over the
  /// default (e.g. Weight Loss + 'heavy' stays heavy — the goal never locks it).
  String get effectiveTrainingFocus {
    if (trainingFocus == 'heavy' ||
        trainingFocus == 'balanced' ||
        trainingFocus == 'high') {
      return trainingFocus;
    }
    switch (fitnessGoal) {
      case 'Weight Loss':
      case 'Endurance':
        return 'high';
      case 'Muscle Gain':
      default:
        return 'balanced'; // Muscle Gain + General Fitness
    }
  }

  /// Stable fingerprint of the profile fields that drive WORKOUT generation.
  /// Compared before/after a profile edit to decide whether the persisted plan
  /// must be regenerated (see ProfileInputScreen._saveProfile). Set-like fields
  /// are sorted so reordering isn't a false change; [goalPriorities] order is
  /// significant (selection tie-break) so it is kept as-is.
  String get workoutGenerationSignature => [
    fitnessGoal,
    experienceLevel,
    workoutLocation,
    workoutDaysPerWeek,
    sessionMinutes,
    workoutSplit,
    trainingFocus,
    ([...equipment]..sort()).join(','),
    ([...physicalLimitations]..sort()).join(','),
    goalPriorities.join(','),
  ].join('|');

  // Mifflin-St Jeor Formula
  int get bmr {
    if (gender == 'Male') {
      return (10 * weight + 6.25 * height - 5 * age + 5).round();
    } else {
      return (10 * weight + 6.25 * height - 5 * age - 161).round();
    }
  }

  double get activityMultiplier {
    // Harris-Benedict Activity Scale, driven by the user's activity level
    switch (activityLevel) {
      case 'Sedentary':
        return 1.2;
      case 'Lightly Active':
        return 1.375;
      case 'Very Active':
        return 1.725;
      case 'Extra Active':
        return 1.9;
      case 'Moderately Active':
      default:
        return 1.55;
    }
  }

  int get tdee => (bmr * activityMultiplier).round();

  int get calorieGoal {
    //Energy Balance Principle
    final int base;
    switch (fitnessGoal) {
      case 'Weight Loss':
        base = tdee - 500;
        break;
      case 'Muscle Gain':
        base = tdee + 300;
        break;
      case 'Endurance':
        base = tdee + 200;
        break;
      default:
        base = tdee; // General Fitness
    }
    // Apply the accumulated weekly calorie adaptation, then clamp to a safe floor.
    return (base + calorieAdjustment).clamp(1200, 99999);
  }

  //  Macro targets in grams
  Map<String, int> get macroGoals {
    final kcal = calorieGoal;
    switch (fitnessGoal) {
      case 'Muscle Gain':
        // High protein: 30% protein, 45% carbs, 25% fat
        return {
          'protein': ((kcal * 0.30) / 4).round(),
          'carbs': ((kcal * 0.45) / 4).round(),
          'fat': ((kcal * 0.25) / 9).round(),
          'fiber': 30,
          'sugar': 50,
          'sodium': 2300,
        };
      case 'Weight Loss':
        // Higher protein to preserve muscle: 35% protein, 40% carbs, 25% fat
        return {
          'protein': ((kcal * 0.35) / 4).round(),
          'carbs': ((kcal * 0.40) / 4).round(),
          'fat': ((kcal * 0.25) / 9).round(),
          'fiber': 35,
          'sugar': 30,
          'sodium': 2000,
        };
      case 'Endurance':
        // High carbs: 20% protein, 55% carbs, 25% fat
        return {
          'protein': ((kcal * 0.20) / 4).round(),
          'carbs': ((kcal * 0.55) / 4).round(),
          'fat': ((kcal * 0.25) / 9).round(),
          'fiber': 38,
          'sugar': 60,
          'sodium': 2500,
        };
      default:
        // General Fitness: 25% protein, 50% carbs, 25% fat
        return {
          'protein': ((kcal * 0.25) / 4).round(),
          'carbs': ((kcal * 0.50) / 4).round(),
          'fat': ((kcal * 0.25) / 9).round(),
          'fiber': 30,
          'sugar': 50,
          'sodium': 2300,
        };
    }
  }

  // --- Display helpers ---
  String get weightDisplay => unitSystem == 'imperial'
      ? '${(weight * 2.20462).toStringAsFixed(1)} lbs'
      : '${weight.toStringAsFixed(1)} kg';

  String get heightDisplay => unitSystem == 'imperial'
      ? '${(height / 30.48).floor()}\' ${((height % 30.48) / 2.54).round()}"'
      : '${height.toStringAsFixed(0)} cm';

  String get bmiDisplay {
    final bmi = weight / ((height / 100) * (height / 100));
    String category;
    if (bmi < 18.5) {
      category = 'Underweight';
    } else if (bmi < 25)
      category = 'Normal';
    else if (bmi < 30)
      category = 'Overweight';
    else
      category = 'Obese';
    return '${bmi.toStringAsFixed(1)} ($category)';
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      gender: map['gender'] ?? 'Male',
      age: map['age'] ?? 0,
      weight: (map['weight'] ?? 0).toDouble(),
      height: (map['height'] ?? 0).toDouble(),
      fitnessGoal: map['fitnessGoal'] ?? 'General Fitness',
      experienceLevel: map['experienceLevel'] ?? 'Beginner',
      workoutLocation: map['workoutLocation'] ?? 'Home',
      equipment: List<String>.from(map['equipment'] ?? []),
      dietaryRestrictions: List<String>.from(map['dietaryRestrictions'] ?? []),
      foodAllergies: List<String>.from(map['foodAllergies'] ?? []),
      physicalLimitations: List<String>.from(
        map['physicalLimitations'] ?? [],
      ),
      avoidedMovements: List<String>.from(map['avoidedMovements'] ?? []),
      unitSystem: map['unitSystem'] ?? 'metric',
      activityLevel: map['activityLevel'] ?? 'Moderately Active',
      workoutDaysPerWeek: map['workoutDaysPerWeek'] ?? 3,
      sessionMinutes: map['sessionMinutes'] ?? 45,
      workoutSplit: map['workoutSplit'] ?? 'Full Body Training',
      trainingFocus: map['trainingFocus'] ?? '',
      calorieAdjustment: map['calorieAdjustment'] ?? 0,
      lastAdaptationWeekId: map['lastAdaptationWeekId'] ?? '',
      pinnedExercises:
          (map['pinnedExercises'] as Map?)?.map(
            (k, v) => MapEntry(k as String, List<String>.from(v ?? const [])),
          ) ??
          const {},
      blockedExercises: List<String>.from(map['blockedExercises'] ?? const []),
      goalPriorities: List<String>.from(map['goalPriorities'] ?? const []),
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'gender': gender,
      'age': age,
      'weight': weight,
      'height': height,
      'fitnessGoal': fitnessGoal,
      'experienceLevel': experienceLevel,
      'workoutLocation': workoutLocation,
      'equipment': equipment,
      'dietaryRestrictions': dietaryRestrictions,
      'foodAllergies': foodAllergies,
      'physicalLimitations': physicalLimitations,
      'avoidedMovements': avoidedMovements,
      'unitSystem': unitSystem,
      'activityLevel': activityLevel,
      'workoutDaysPerWeek': workoutDaysPerWeek,
      'sessionMinutes': sessionMinutes,
      'workoutSplit': workoutSplit,
      'trainingFocus': trainingFocus,
      'calorieAdjustment': calorieAdjustment,
      'lastAdaptationWeekId': lastAdaptationWeekId,
      'pinnedExercises': pinnedExercises,
      'blockedExercises': blockedExercises,
      'goalPriorities': goalPriorities,
      'createdAt': createdAt?.millisecondsSinceEpoch,
    };
  }

  UserProfile copyWith({
    String? uid,
    String? name,
    String? gender,
    int? age,
    double? weight,
    double? height,
    String? fitnessGoal,
    String? experienceLevel,
    String? workoutLocation,
    List<String>? equipment,
    List<String>? dietaryRestrictions,
    List<String>? foodAllergies,
    List<String>? physicalLimitations,
    List<String>? avoidedMovements,
    String? unitSystem,
    String? activityLevel,
    int? workoutDaysPerWeek,
    int? sessionMinutes,
    String? workoutSplit,
    String? trainingFocus,
    int? calorieAdjustment,
    String? lastAdaptationWeekId,
    Map<String, List<String>>? pinnedExercises,
    List<String>? blockedExercises,
    List<String>? goalPriorities,
    DateTime? createdAt,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      weight: weight ?? this.weight,
      height: height ?? this.height,
      fitnessGoal: fitnessGoal ?? this.fitnessGoal,
      experienceLevel: experienceLevel ?? this.experienceLevel,
      workoutLocation: workoutLocation ?? this.workoutLocation,
      equipment: equipment ?? this.equipment,
      dietaryRestrictions: dietaryRestrictions ?? this.dietaryRestrictions,
      foodAllergies: foodAllergies ?? this.foodAllergies,
      physicalLimitations: physicalLimitations ?? this.physicalLimitations,
      avoidedMovements: avoidedMovements ?? this.avoidedMovements,
      unitSystem: unitSystem ?? this.unitSystem,
      activityLevel: activityLevel ?? this.activityLevel,
      workoutDaysPerWeek: workoutDaysPerWeek ?? this.workoutDaysPerWeek,
      sessionMinutes: sessionMinutes ?? this.sessionMinutes,
      workoutSplit: workoutSplit ?? this.workoutSplit,
      trainingFocus: trainingFocus ?? this.trainingFocus,
      calorieAdjustment: calorieAdjustment ?? this.calorieAdjustment,
      lastAdaptationWeekId: lastAdaptationWeekId ?? this.lastAdaptationWeekId,
      pinnedExercises: pinnedExercises ?? this.pinnedExercises,
      blockedExercises: blockedExercises ?? this.blockedExercises,
      goalPriorities: goalPriorities ?? this.goalPriorities,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
