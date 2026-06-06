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
  final String unitSystem; // 'metric' or 'imperial'

  // Profiling — workload, recovery & scheduling inputs
  final String
  activityLevel; // Sedentary | Lightly Active | Moderately Active | Very Active | Extra Active
  final int workoutDaysPerWeek; // 1–7
  final int sessionMinutes; // 30 | 45 | 60 | 90
  final String
  workoutSplit; // weekly split style (see ProfileInputScreen split cards)
  final double avgHoursSlept; // average nightly sleep, drives recovery

  /// Accumulated weekly calorie-goal adaptation (kcal). Added on top of the
  /// goal-derived base in [calorieGoal]; fed by [AdaptationEngine] each new
  /// week and by manual edits. Clamped to ±500 by the provider to prevent drift.
  final int calorieAdjustment;

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
    this.unitSystem = 'metric',
    this.activityLevel = 'Moderately Active',
    this.workoutDaysPerWeek = 3,
    this.sessionMinutes = 45,
    this.workoutSplit = 'Full Body Training',
    this.avgHoursSlept = 7.0,
    this.calorieAdjustment = 0,
  });

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

  /// Recovery factor (0–1) derived from average sleep. Lower sleep → less
  /// recovery → the greedy algorithm trims volume. See greedy_algorithm.dart.
  double get recoveryScore {
    if (avgHoursSlept < 6) return 0.7;
    if (avgHoursSlept < 7) return 0.85;
    return 1.0;
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
    if (bmi < 18.5)
      category = 'Underweight';
    else if (bmi < 25)
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
      unitSystem: map['unitSystem'] ?? 'metric',
      activityLevel: map['activityLevel'] ?? 'Moderately Active',
      workoutDaysPerWeek: map['workoutDaysPerWeek'] ?? 3,
      sessionMinutes: map['sessionMinutes'] ?? 45,
      workoutSplit: map['workoutSplit'] ?? 'Full Body Training',
      avgHoursSlept: (map['avgHoursSlept'] ?? 7.0).toDouble(),
      calorieAdjustment: map['calorieAdjustment'] ?? 0,
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
      'unitSystem': unitSystem,
      'activityLevel': activityLevel,
      'workoutDaysPerWeek': workoutDaysPerWeek,
      'sessionMinutes': sessionMinutes,
      'workoutSplit': workoutSplit,
      'avgHoursSlept': avgHoursSlept,
      'calorieAdjustment': calorieAdjustment,
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
    String? unitSystem,
    String? activityLevel,
    int? workoutDaysPerWeek,
    int? sessionMinutes,
    String? workoutSplit,
    double? avgHoursSlept,
    int? calorieAdjustment,
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
      unitSystem: unitSystem ?? this.unitSystem,
      activityLevel: activityLevel ?? this.activityLevel,
      workoutDaysPerWeek: workoutDaysPerWeek ?? this.workoutDaysPerWeek,
      sessionMinutes: sessionMinutes ?? this.sessionMinutes,
      workoutSplit: workoutSplit ?? this.workoutSplit,
      avgHoursSlept: avgHoursSlept ?? this.avgHoursSlept,
      calorieAdjustment: calorieAdjustment ?? this.calorieAdjustment,
    );
  }
}
