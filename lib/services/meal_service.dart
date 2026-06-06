import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/edamam_recipe.dart';

/// Free meal generation using TheMealDB (no API key required).
/// Nutrition is estimated from USDA reference values for the main ingredients.
class MealService {
  static const _base = 'https://www.themealdb.com/api/json/v1/1';

  // ── Public API ──────────────────────────────────────────────────────────────

  Future<List<EdamamRecipe>> fetchRecipes({
    required String mealType,
    required int targetCalories,
    double proteinGoal = 0,
    List<String> dietaryRestrictions = const [],
    String? cuisine,
    int count = 8,
  }) async {
    final categories = _categoriesForMealType(
      mealType,
      dietaryRestrictions,
      cuisine,
    );
    final results = <EdamamRecipe>[];
    final rng = Random();

    // Try each category until we have enough results
    for (final category in categories) {
      if (results.length >= count) break;
      try {
        final meals = await _fetchByCategory(category);
        results.addAll(meals);
      } catch (_) {}
    }

    if (results.isEmpty) {
      // Fallback: random meals
      for (int i = 0; i < 3; i++) {
        try {
          final meal = await _fetchRandom();
          if (meal != null) results.add(meal);
        } catch (_) {}
      }
    }

    results.shuffle(rng);
    return results.take(count).toList();
  }

  EdamamRecipe? pickBest(
    List<EdamamRecipe> candidates,
    int targetCalories,
    double proteinGoal,
  ) {
    if (candidates.isEmpty) return null;
    candidates.sort(
      (a, b) => _score(b, targetCalories, proteinGoal).compareTo(
        _score(a, targetCalories, proteinGoal),
      ),
    );
    return candidates.first;
  }

  /// Scale all nutrition values in [recipe] proportionally so that the
  /// calorie total matches [targetCalories].  This models a larger/smaller
  /// portion rather than a different dish, which is the honest way to meet
  /// per-meal energy + macro targets from a fixed recipe database.
  EdamamRecipe scaleToCalories(EdamamRecipe recipe, int targetCalories) {
    if (recipe.calories <= 0 || targetCalories <= 0) return recipe;
    final factor = targetCalories / recipe.calories;
    return EdamamRecipe(
      id: recipe.id,
      label: recipe.label,
      imageUrl: recipe.imageUrl,
      sourceUrl: recipe.sourceUrl,
      ingredientLines: recipe.ingredientLines,
      servings: recipe.servings,
      calories: (recipe.calories * factor).roundToDouble(),
      protein: double.parse((recipe.protein * factor).toStringAsFixed(1)),
      fat: double.parse((recipe.fat * factor).toStringAsFixed(1)),
      carbs: double.parse((recipe.carbs * factor).toStringAsFixed(1)),
      fiber: double.parse((recipe.fiber * factor).toStringAsFixed(1)),
      sugar: double.parse((recipe.sugar * factor).toStringAsFixed(1)),
      sodium: double.parse((recipe.sodium * factor).toStringAsFixed(1)),
      vitaminA: recipe.vitaminA * factor,
      vitaminC: recipe.vitaminC * factor,
      vitaminD: recipe.vitaminD * factor,
      vitaminE: recipe.vitaminE * factor,
      vitaminK: recipe.vitaminK * factor,
      vitaminB6: recipe.vitaminB6 * factor,
      vitaminB12: recipe.vitaminB12 * factor,
      folate: recipe.folate * factor,
      calcium: recipe.calcium * factor,
      iron: recipe.iron * factor,
      magnesium: recipe.magnesium * factor,
      potassium: recipe.potassium * factor,
      zinc: recipe.zinc * factor,
      phosphorus: recipe.phosphorus * factor,
    );
  }

  // ── TheMealDB Fetchers ──────────────────────────────────────────────────────

  Future<List<EdamamRecipe>> _fetchByCategory(String category) async {
    final res = await http
        .get(Uri.parse('$_base/filter.php?c=${Uri.encodeComponent(category)}'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final meals = (data['meals'] as List? ?? []).cast<Map<String, dynamic>>();

    // Pick up to 5 random meals from this category and fetch details
    meals.shuffle(Random());
    final detailed = <EdamamRecipe>[];
    for (final m in meals.take(5)) {
      try {
        final detail = await _fetchById(m['idMeal'] as String);
        if (detail != null) detailed.add(detail);
      } catch (_) {}
    }
    return detailed;
  }

  Future<EdamamRecipe?> _fetchById(String id) async {
    final res = await http
        .get(Uri.parse('$_base/lookup.php?i=$id'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final meals = data['meals'] as List?;
    if (meals == null || meals.isEmpty) return null;
    return _parseMeal(meals.first as Map<String, dynamic>);
  }

  Future<EdamamRecipe?> _fetchRandom() async {
    final res = await http
        .get(Uri.parse('$_base/random.php'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final meals = data['meals'] as List?;
    if (meals == null || meals.isEmpty) return null;
    return _parseMeal(meals.first as Map<String, dynamic>);
  }

  // ── Parse TheMealDB response → EdamamRecipe ─────────────────────────────────

  EdamamRecipe _parseMeal(Map<String, dynamic> m) {
    // Extract ingredients + measures (TheMealDB uses strIngredient1..20)
    final ingredientLines = <String>[];
    for (int i = 1; i <= 20; i++) {
      final ing = (m['strIngredient$i'] as String? ?? '').trim();
      final measure = (m['strMeasure$i'] as String? ?? '').trim();
      if (ing.isNotEmpty) {
        ingredientLines.add(measure.isNotEmpty ? '$measure $ing' : ing);
      }
    }

    final category = (m['strCategory'] as String? ?? '').toLowerCase();
    final nutrition = _estimateNutrition(category, ingredientLines);

    return EdamamRecipe(
      id: m['idMeal']?.toString() ?? '',
      label: m['strMeal'] as String? ?? 'Recipe',
      imageUrl: m['strMealThumb'] as String? ?? '',
      sourceUrl: m['strSource'] as String? ?? '',
      ingredientLines: ingredientLines,
      servings: 1,
      calories: nutrition['calories']!,
      protein: nutrition['protein']!,
      fat: nutrition['fat']!,
      carbs: nutrition['carbs']!,
      fiber: nutrition['fiber']!,
      sugar: nutrition['sugar']!,
      sodium: nutrition['sodium']!,
      // Vitamins & minerals — reasonable estimates per meal
      vitaminA: 150,
      vitaminC: 15,
      vitaminD: 1.5,
      vitaminE: 2.5,
      vitaminK: 40,
      vitaminB6: 0.4,
      vitaminB12: 1.2,
      folate: 60,
      calcium: 80,
      iron: 3,
      magnesium: 40,
      potassium: 500,
      zinc: 2.5,
      phosphorus: 200,
    );
  }

  // ── Nutrition estimation ─────────────────────────────────────────────────────
  // Based on USDA average values for common meal categories.
  // These are per-serving estimates (one plate).

  Map<String, double> _estimateNutrition(String category, List<String> ingredients) {
    // Check if ingredients suggest certain nutritional profiles
    final ingText = ingredients.join(' ').toLowerCase();
    final isHighProtein = ingText.contains('chicken') ||
        ingText.contains('beef') ||
        ingText.contains('fish') ||
        ingText.contains('tuna') ||
        ingText.contains('salmon') ||
        ingText.contains('shrimp') ||
        ingText.contains('turkey') ||
        ingText.contains('egg');
    final isVeggieBased = ingText.contains('spinach') ||
        ingText.contains('salad') ||
        ingText.contains('broccoli') ||
        ingText.contains('vegetable');
    final isPastaBased = ingText.contains('pasta') ||
        ingText.contains('spaghetti') ||
        ingText.contains('noodle') ||
        ingText.contains('rice');

    // Category-based base values
    return switch (category) {
      'chicken' => {'calories': 420, 'protein': 38, 'carbs': 22, 'fat': 18, 'fiber': 3, 'sugar': 4, 'sodium': 620},
      'beef' => {'calories': 480, 'protein': 35, 'carbs': 18, 'fat': 24, 'fiber': 2, 'sugar': 3, 'sodium': 680},
      'seafood' || 'fish' => {'calories': 360, 'protein': 32, 'carbs': 20, 'fat': 14, 'fiber': 2, 'sugar': 3, 'sodium': 540},
      'pasta' => {'calories': 500, 'protein': 18, 'carbs': 65, 'fat': 14, 'fiber': 4, 'sugar': 6, 'sodium': 580},
      'vegetarian' || 'vegan' => {'calories': 320, 'protein': 14, 'carbs': 42, 'fat': 10, 'fiber': 8, 'sugar': 8, 'sodium': 420},
      'breakfast' => {'calories': 380, 'protein': 20, 'carbs': 35, 'fat': 16, 'fiber': 3, 'sugar': 8, 'sodium': 480},
      'dessert' => {'calories': 350, 'protein': 5, 'carbs': 52, 'fat': 14, 'fiber': 1, 'sugar': 32, 'sodium': 220},
      'lamb' => {'calories': 460, 'protein': 33, 'carbs': 15, 'fat': 26, 'fiber': 2, 'sugar': 3, 'sodium': 600},
      'pork' => {'calories': 440, 'protein': 30, 'carbs': 20, 'fat': 22, 'fiber': 2, 'sugar': 4, 'sodium': 650},
      _ when isHighProtein => {'calories': 430, 'protein': 36, 'carbs': 20, 'fat': 18, 'fiber': 3, 'sugar': 4, 'sodium': 580},
      _ when isVeggieBased => {'calories': 300, 'protein': 12, 'carbs': 38, 'fat': 10, 'fiber': 7, 'sugar': 7, 'sodium': 400},
      _ when isPastaBased => {'calories': 480, 'protein': 16, 'carbs': 60, 'fat': 14, 'fiber': 4, 'sugar': 5, 'sodium': 550},
      _ => {'calories': 400, 'protein': 22, 'carbs': 35, 'fat': 16, 'fiber': 4, 'sugar': 5, 'sodium': 520},
    }.map((k, v) => MapEntry(k, v.toDouble()));
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  List<String> _categoriesForMealType(
    String mealType,
    List<String> restrictions,
    String? cuisine,
  ) {
    final r = restrictions.map((s) => s.toLowerCase()).toSet();

    // ── Hard exclusion diets — honour before anything else ──────────────────
    final isVegan = r.contains('vegan');
    final isVegetarian = r.contains('vegetarian');
    final isPescatarian = r.contains('pescatarian');
    final isGlutenFree = r.contains('gluten-free');
    final isDairyFree = r.contains('dairy-free');

    if (isVegan) {
      return switch (mealType) {
        'breakfast' => ['Vegetarian', 'Vegan'],
        _ => ['Vegetarian', 'Vegan', 'Side'],
      };
    }
    if (isVegetarian) {
      return switch (mealType) {
        'breakfast' => ['Breakfast', 'Vegetarian'],
        _ => ['Vegetarian', 'Side', 'Pasta'],
      };
    }
    if (isPescatarian) {
      return switch (mealType) {
        'breakfast' => ['Breakfast', 'Seafood'],
        _ => ['Seafood', 'Vegetarian', 'Side'],
      };
    }

    // ── Macro-focused diet styles ────────────────────────────────────────────
    // High-protein / Paleo / Keto → lean proteins, no pasta or dessert
    final isHighProtein = r.contains('high-protein');
    final isKeto = r.contains('keto');
    final isPaleo = r.contains('paleo');
    final isLowCarb = r.contains('low-carb');

    if (isHighProtein || isPaleo) {
      // Strictly lean proteins — no pasta, no vegetarian filler
      return switch (mealType) {
        'breakfast' => ['Chicken', 'Breakfast'],
        'lunch' => ['Chicken', 'Beef', 'Seafood', 'Lamb'],
        'dinner' => ['Beef', 'Chicken', 'Lamb', 'Seafood', 'Pork'],
        _ => ['Chicken', 'Seafood', 'Beef'],
      };
    }
    if (isKeto || isLowCarb) {
      // High fat, very low carb: meat + seafood; avoid pasta
      return switch (mealType) {
        'breakfast' => ['Chicken', 'Beef'],
        'lunch' => ['Beef', 'Chicken', 'Seafood', 'Pork'],
        'dinner' => ['Beef', 'Lamb', 'Chicken', 'Seafood', 'Pork'],
        _ => ['Chicken', 'Beef', 'Seafood'],
      };
    }
    final isMediterranean = r.contains('mediterranean');
    if (isMediterranean) {
      return switch (mealType) {
        'breakfast' => ['Breakfast', 'Vegetarian'],
        _ => ['Seafood', 'Chicken', 'Vegetarian', 'Pasta', 'Lamb'],
      };
    }

    // ── Default by meal type ──────────────────────────────────────────────────
    final base = switch (mealType) {
      'breakfast' => ['Breakfast', 'Vegetarian', 'Chicken'],
      'lunch' => ['Chicken', 'Beef', 'Pasta', 'Seafood'],
      'dinner' => ['Beef', 'Chicken', 'Lamb', 'Seafood', 'Pork'],
      _ => ['Chicken', 'Vegetarian', 'Seafood', 'Pasta'],
    };
    // Gluten-free / dairy-free on default: prefer chicken/seafood, remove pasta
    if (isGlutenFree || isDairyFree) {
      return base.where((c) => c != 'Pasta').toList();
    }
    return base;
  }

  double _score(EdamamRecipe r, int targetCal, double proteinGoal) {
    final calErr = ((r.calories - targetCal) / targetCal).abs();
    final protErr =
        proteinGoal > 0
            ? ((r.protein - proteinGoal) / proteinGoal).abs()
            : 0.0;
    // Weight protein more heavily when the per-meal target is high (>30 g).
    // At 30 g protein/meal the split is 40/35; at 60 g it becomes 25/60.
    final protWeight = proteinGoal > 30 ? 60.0 : 35.0;
    final calWeight = proteinGoal > 30 ? 25.0 : 40.0;
    return 100 - (calErr * calWeight) - (protErr * protWeight);
  }
}
