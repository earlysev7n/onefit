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
    this.allergens = const [],
    this.category = 'other',
  });

  double caloriesFor(double grams) => (calories * grams) / 100;
  double proteinFor(double grams) => (protein * grams) / 100;
  double carbsFor(double grams) => (carbs * grams) / 100;
  double fatFor(double grams) => (fat * grams) / 100;
  double fiberFor(double grams) => (fiber * grams) / 100;

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

  MealItem copyWith({double? portionGrams}) => MealItem(
    ingredient: ingredient,
    portionGrams: portionGrams ?? this.portionGrams,
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

  String get name => items.map((i) => i.ingredient.name).join(' + ');

  // Scale all portions by a factor to hit a calorie target
  Meal scaleToCalories(double targetCalories) {
    if (totalCalories <= 0) return this;
    final scale = targetCalories / totalCalories;
    return Meal(
      mealType: mealType,
      items: items.map((item) {
        final newGrams = (item.portionGrams * scale).clamp(30.0, 350.0);
        return item.copyWith(portionGrams: newGrams);
      }).toList(),
    );
  }

  Meal copyWith({List<MealItem>? items}) =>
      Meal(mealType: mealType, items: items ?? this.items);
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
