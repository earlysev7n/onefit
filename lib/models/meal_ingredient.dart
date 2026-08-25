class MealIngredient {
  final String id;
  final String name;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final double sugar;
  final double sodium;
  // Micronutrients (mirrors FoodItem; units: A mcg RAE, C mg, D mcg, E mg,
  // K mcg, B6 mg, B12 mcg, folate mcg DFE, minerals mg). Seeded to Firestore by
  // SeedData but historically dropped at load — now read so meals can show them.
  final double vitaminA;
  final double vitaminC;
  final double vitaminD;
  final double vitaminE;
  final double vitaminK;
  final double vitaminB6;
  final double vitaminB12;
  final double folate;
  final double iron;
  final double calcium;
  final double magnesium;
  final double potassium;
  final double zinc;
  final double phosphorus;
  final List<String> dietaryTags;
  final String cuisine;

  /// Allergen flags used for exclusion-based restrictions (e.g. `dairy`,
  /// `nuts`). An ingredient is rejected when the user's restriction maps to an
  /// allergen present here. Empty by default for backward-compatible reads.
  final List<String> allergens;

  /// Coarse food group used to classify the meal pools robustly instead of
  /// matching ingredient names. One of: protein, dairy, grain, legume,
  /// vegetable, fruit, fat, condiment. Defaults to `other`.
  final String category;

  MealIngredient({
    required this.id,
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
    required this.sugar,
    required this.sodium,
    required this.dietaryTags,
    required this.cuisine,
    this.vitaminA = 0,
    this.vitaminC = 0,
    this.vitaminD = 0,
    this.vitaminE = 0,
    this.vitaminK = 0,
    this.vitaminB6 = 0,
    this.vitaminB12 = 0,
    this.folate = 0,
    this.iron = 0,
    this.calcium = 0,
    this.magnesium = 0,
    this.potassium = 0,
    this.zinc = 0,
    this.phosphorus = 0,
    this.allergens = const [],
    this.category = 'other',
  });

  double caloriesFor(double grams) => (calories * grams) / 100;
  double proteinFor(double grams) => (protein * grams) / 100;
  double carbsFor(double grams) => (carbs * grams) / 100;
  double fatFor(double grams) => (fat * grams) / 100;
  double fiberFor(double grams) => (fiber * grams) / 100;
  double sugarFor(double grams) => (sugar * grams) / 100;
  double sodiumFor(double grams) => (sodium * grams) / 100;
  double vitaminAFor(double grams) => (vitaminA * grams) / 100;
  double vitaminCFor(double grams) => (vitaminC * grams) / 100;
  double vitaminDFor(double grams) => (vitaminD * grams) / 100;
  double vitaminEFor(double grams) => (vitaminE * grams) / 100;
  double vitaminKFor(double grams) => (vitaminK * grams) / 100;
  double vitaminB6For(double grams) => (vitaminB6 * grams) / 100;
  double vitaminB12For(double grams) => (vitaminB12 * grams) / 100;
  double folateFor(double grams) => (folate * grams) / 100;
  double ironFor(double grams) => (iron * grams) / 100;
  double calciumFor(double grams) => (calcium * grams) / 100;
  double magnesiumFor(double grams) => (magnesium * grams) / 100;
  double potassiumFor(double grams) => (potassium * grams) / 100;
  double zincFor(double grams) => (zinc * grams) / 100;
  double phosphorusFor(double grams) => (phosphorus * grams) / 100;

  factory MealIngredient.fromMap(Map<String, dynamic> map) {
    return MealIngredient(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      calories: (map['calories'] ?? 0).toDouble(),
      protein: (map['protein'] ?? 0).toDouble(),
      carbs: (map['carbs'] ?? 0).toDouble(),
      fat: (map['fat'] ?? 0).toDouble(),
      fiber: (map['fiber'] ?? 0).toDouble(),
      sugar: (map['sugar'] ?? 0).toDouble(),
      sodium: (map['sodium'] ?? 0).toDouble(),
      dietaryTags: List<String>.from(map['dietaryTags'] ?? []),
      cuisine: map['cuisine'] ?? 'universal',
      vitaminA: (map['vitaminA'] ?? 0).toDouble(),
      vitaminC: (map['vitaminC'] ?? 0).toDouble(),
      vitaminD: (map['vitaminD'] ?? 0).toDouble(),
      vitaminE: (map['vitaminE'] ?? 0).toDouble(),
      vitaminK: (map['vitaminK'] ?? 0).toDouble(),
      vitaminB6: (map['vitaminB6'] ?? 0).toDouble(),
      vitaminB12: (map['vitaminB12'] ?? 0).toDouble(),
      folate: (map['folate'] ?? 0).toDouble(),
      iron: (map['iron'] ?? 0).toDouble(),
      calcium: (map['calcium'] ?? 0).toDouble(),
      magnesium: (map['magnesium'] ?? 0).toDouble(),
      potassium: (map['potassium'] ?? 0).toDouble(),
      zinc: (map['zinc'] ?? 0).toDouble(),
      phosphorus: (map['phosphorus'] ?? 0).toDouble(),
      allergens: List<String>.from(map['allergens'] ?? []),
      category: map['category'] ?? 'other',
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'calories': calories,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'fiber': fiber,
    'sugar': sugar,
    'sodium': sodium,
    'dietaryTags': dietaryTags,
    'cuisine': cuisine,
    'vitaminA': vitaminA,
    'vitaminC': vitaminC,
    'vitaminD': vitaminD,
    'vitaminE': vitaminE,
    'vitaminK': vitaminK,
    'vitaminB6': vitaminB6,
    'vitaminB12': vitaminB12,
    'folate': folate,
    'iron': iron,
    'calcium': calcium,
    'magnesium': magnesium,
    'potassium': potassium,
    'zinc': zinc,
    'phosphorus': phosphorus,
    'allergens': allergens,
    'category': category,
  };
}

class MealItem {
  final MealIngredient ingredient;
  final double portionGrams;

  MealItem({required this.ingredient, required this.portionGrams});

  double get calories => ingredient.caloriesFor(portionGrams);
  double get protein => ingredient.proteinFor(portionGrams);
  double get carbs => ingredient.carbsFor(portionGrams);
  double get fat => ingredient.fatFor(portionGrams);
  double get fiber => ingredient.fiberFor(portionGrams);
  double get sugar => ingredient.sugarFor(portionGrams);
  double get sodium => ingredient.sodiumFor(portionGrams);
  double get vitaminA => ingredient.vitaminAFor(portionGrams);
  double get vitaminC => ingredient.vitaminCFor(portionGrams);
  double get vitaminD => ingredient.vitaminDFor(portionGrams);
  double get vitaminE => ingredient.vitaminEFor(portionGrams);
  double get vitaminK => ingredient.vitaminKFor(portionGrams);
  double get vitaminB6 => ingredient.vitaminB6For(portionGrams);
  double get vitaminB12 => ingredient.vitaminB12For(portionGrams);
  double get folate => ingredient.folateFor(portionGrams);
  double get iron => ingredient.ironFor(portionGrams);
  double get calcium => ingredient.calciumFor(portionGrams);
  double get magnesium => ingredient.magnesiumFor(portionGrams);
  double get potassium => ingredient.potassiumFor(portionGrams);
  double get zinc => ingredient.zincFor(portionGrams);
  double get phosphorus => ingredient.phosphorusFor(portionGrams);

  MealItem copyWith({double? portionGrams}) => MealItem(
    ingredient: ingredient,
    portionGrams: portionGrams ?? this.portionGrams,
  );

  Map<String, dynamic> toMap() => {
    'ingredient': ingredient.toMap(),
    'portionGrams': portionGrams,
  };

  factory MealItem.fromMap(Map<String, dynamic> map) => MealItem(
    ingredient: MealIngredient.fromMap(map['ingredient'] as Map<String, dynamic>),
    portionGrams: (map['portionGrams'] as num?)?.toDouble() ?? 100.0,
  );
}

class Meal {
  final String mealType; // breakfast | lunch | dinner | snack
  final List<MealItem> items;

  Meal({required this.mealType, required this.items});

  double get totalCalories => items.fold(0, (sum, i) => sum + i.calories);
  double get totalProtein => items.fold(0, (sum, i) => sum + i.protein);
  double get totalCarbs => items.fold(0, (sum, i) => sum + i.carbs);
  double get totalFat => items.fold(0, (sum, i) => sum + i.fat);
  double get totalFiber => items.fold(0, (sum, i) => sum + i.fiber);
  double get totalSugar => items.fold(0, (sum, i) => sum + i.sugar);
  double get totalSodium => items.fold(0, (sum, i) => sum + i.sodium);
  double get totalVitaminA => items.fold(0, (sum, i) => sum + i.vitaminA);
  double get totalVitaminC => items.fold(0, (sum, i) => sum + i.vitaminC);
  double get totalVitaminD => items.fold(0, (sum, i) => sum + i.vitaminD);
  double get totalVitaminE => items.fold(0, (sum, i) => sum + i.vitaminE);
  double get totalVitaminK => items.fold(0, (sum, i) => sum + i.vitaminK);
  double get totalVitaminB6 => items.fold(0, (sum, i) => sum + i.vitaminB6);
  double get totalVitaminB12 => items.fold(0, (sum, i) => sum + i.vitaminB12);
  double get totalFolate => items.fold(0, (sum, i) => sum + i.folate);
  double get totalIron => items.fold(0, (sum, i) => sum + i.iron);
  double get totalCalcium => items.fold(0, (sum, i) => sum + i.calcium);
  double get totalMagnesium => items.fold(0, (sum, i) => sum + i.magnesium);
  double get totalPotassium => items.fold(0, (sum, i) => sum + i.potassium);
  double get totalZinc => items.fold(0, (sum, i) => sum + i.zinc);
  double get totalPhosphorus => items.fold(0, (sum, i) => sum + i.phosphorus);

  String get name => items.map((i) => i.ingredient.name).join(' + ');

  // Scale all portions by a factor to hit a calorie target. The 400g ceiling
  // matches GeneticAlgorithm._portionFor so scaling never silently truncates a
  // portion that the initial sizing was allowed to produce.
  Meal scaleToCalories(double targetCalories) {
    if (totalCalories <= 0) return this;
    final scale = targetCalories / totalCalories;
    return Meal(
      mealType: mealType,
      items: items.map((item) {
        final newGrams = (item.portionGrams * scale).clamp(30.0, 400.0);
        return item.copyWith(portionGrams: newGrams);
      }).toList(),
    );
  }

  /// Closes the residual gap left after [scaleToCalories] when the per-item
  /// portion clamp truncates a scale-up (e.g. a low-density vegetable that would
  /// need >400g to hit its share). Distributes the gap across items densest-first
  /// — the densest item needs the fewest extra grams, keeping portions natural —
  /// re-clamping each to 30–400g and accounting for what the clamp actually
  /// absorbed, over a few passes. A residual within [tolerance] is left as-is.
  ///
  /// Generalises the old `_normalizePlan` dinner-only fine-tune to any meal.
  Meal closeResidual(
    double targetCalories, {
    double tolerance = 30.0,
    int maxPasses = 3,
  }) {
    var current = this;
    for (int pass = 0; pass < maxPasses; pass++) {
      var remaining = targetCalories - current.totalCalories;
      if (remaining.abs() <= tolerance) break;

      // Indices ordered by calorie density (cals per 100g), densest first.
      final order = List<int>.generate(current.items.length, (i) => i)
        ..sort((a, b) => current.items[b].ingredient.calories
            .compareTo(current.items[a].ingredient.calories));

      final adjusted = List<MealItem>.from(current.items);
      var changed = false;
      for (final idx in order) {
        if (remaining.abs() <= tolerance) break;
        final item = adjusted[idx];
        if (item.ingredient.calories <= 0) continue;
        final gramsNeeded = (remaining / item.ingredient.calories) * 100;
        final newGrams = (item.portionGrams + gramsNeeded).clamp(30.0, 400.0);
        if (newGrams == item.portionGrams) continue; // already at a clamp edge
        final before = item.calories;
        final updated = item.copyWith(portionGrams: newGrams);
        remaining -= (updated.calories - before);
        adjusted[idx] = updated;
        changed = true;
      }
      if (!changed) break; // every item pinned at a clamp edge — physical limit
      current = Meal(mealType: current.mealType, items: adjusted);
    }
    return current;
  }

  Meal copyWith({String? mealType, List<MealItem>? items}) =>
      Meal(mealType: mealType ?? this.mealType, items: items ?? this.items);

  Map<String, dynamic> toMap() => {
    'mealType': mealType,
    'items': items.map((i) => i.toMap()).toList(),
  };

  factory Meal.fromMap(Map<String, dynamic> map) => Meal(
    mealType: map['mealType'] as String? ?? '',
    items: (map['items'] as List<dynamic>? ?? [])
        .map((i) => MealItem.fromMap(i as Map<String, dynamic>))
        .toList(),
  );
}

class DayMealPlan {
  final String dayName;
  final Meal breakfast;
  final Meal lunch;
  final Meal dinner;
  final Meal snack;

  DayMealPlan({
    required this.dayName,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
    required this.snack,
  });

  double get totalCalories =>
      breakfast.totalCalories +
      lunch.totalCalories +
      dinner.totalCalories +
      snack.totalCalories;
  double get totalProtein =>
      breakfast.totalProtein +
      lunch.totalProtein +
      dinner.totalProtein +
      snack.totalProtein;
  double get totalCarbs =>
      breakfast.totalCarbs +
      lunch.totalCarbs +
      dinner.totalCarbs +
      snack.totalCarbs;
  double get totalFat =>
      breakfast.totalFat + lunch.totalFat + dinner.totalFat + snack.totalFat;

  DayMealPlan copyWith({
    Meal? breakfast,
    Meal? lunch,
    Meal? dinner,
    Meal? snack,
  }) => DayMealPlan(
    dayName: dayName,
    breakfast: breakfast ?? this.breakfast,
    lunch: lunch ?? this.lunch,
    dinner: dinner ?? this.dinner,
    snack: snack ?? this.snack,
  );
}
