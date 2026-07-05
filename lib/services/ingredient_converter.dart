import '../models/food_item.dart';
import '../models/meal_ingredient.dart';
import 'dietary_filter.dart';

/// Converts user-picked foods (USDA FDC search results, OpenFoodFacts barcode
/// products, 30-day history [FoodItem]s) into per-100g [MealIngredient]
/// records the Genetic Algorithm can portion (Meal Planning Option A: "Use
/// Available Ingredients").
///
/// [MealIngredient] nutrition is always per 100 g; picked foods describe their
/// values per [servingSize] [servingUnit]. When the unit is grams (or ml,
/// treated 1:1) values are rescaled by `100 / servingSize`. Any other unit
/// ("serving", "bar", ...) has no reliable gram equivalent, so the serving is
/// treated as 100 g — a documented best-effort fallback that can misstate
/// grams for such items.
///
/// Pure Dart, no Flutter/Firebase imports — unit-tested in
/// `test/ingredient_converter_test.dart`.
class IngredientConverter {
  /// Builds a per-100g [MealIngredient] from per-serving nutrition values.
  static MealIngredient fromPerServing({
    required String id,
    required String name,
    required double servingSize,
    required String servingUnit,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    double fiber = 0,
    double sugar = 0,
    double sodium = 0,
    double vitaminA = 0,
    double vitaminC = 0,
    double vitaminD = 0,
    double vitaminE = 0,
    double vitaminK = 0,
    double vitaminB6 = 0,
    double vitaminB12 = 0,
    double folate = 0,
    double iron = 0,
    double calcium = 0,
    double magnesium = 0,
    double potassium = 0,
    double zinc = 0,
    double phosphorus = 0,
  }) {
    final unit = servingUnit.toLowerCase().trim();
    final factor = (unit == 'g' || unit == 'ml') && servingSize > 0
        ? 100 / servingSize
        : 1.0;
    final cal100 = calories * factor;
    final protein100 = protein * factor;
    final carbs100 = carbs * factor;
    final fat100 = fat * factor;
    return MealIngredient(
      id: id,
      name: name,
      calories: cal100,
      protein: protein100,
      carbs: carbs100,
      fat: fat100,
      fiber: fiber * factor,
      sugar: sugar * factor,
      sodium: sodium * factor,
      dietaryTags: const [],
      cuisine: 'universal',
      vitaminA: vitaminA * factor,
      vitaminC: vitaminC * factor,
      vitaminD: vitaminD * factor,
      vitaminE: vitaminE * factor,
      vitaminK: vitaminK * factor,
      vitaminB6: vitaminB6 * factor,
      vitaminB12: vitaminB12 * factor,
      folate: folate * factor,
      iron: iron * factor,
      calcium: calcium * factor,
      magnesium: magnesium * factor,
      potassium: potassium * factor,
      zinc: zinc * factor,
      phosphorus: phosphorus * factor,
      allergens: deriveAllergens(name),
      category: inferCategory(
        name: name,
        caloriesPer100: cal100,
        proteinPer100: protein100,
        carbsPer100: carbs100,
        fatPer100: fat100,
      ),
    );
  }

  /// History/barcode path: [FoodItem] values describe one serving of
  /// [FoodItem.servingSize] [FoodItem.servingSizeUnit]; the logged `quantity`
  /// multiplier is irrelevant here (the GA re-decides all grams).
  static MealIngredient fromFoodItem(FoodItem f) => fromPerServing(
    id: 'picked_${f.barcode.isNotEmpty ? f.barcode : f.id}',
    name: f.name,
    servingSize: f.servingSize,
    servingUnit: f.servingSizeUnit,
    calories: f.calories,
    protein: f.protein,
    carbs: f.carbs,
    fat: f.fat,
    fiber: f.fiber,
    sugar: f.sugar,
    sodium: f.sodium,
    vitaminA: f.vitaminA,
    vitaminC: f.vitaminC,
    vitaminD: f.vitaminD,
    vitaminE: f.vitaminE,
    vitaminK: f.vitaminK,
    vitaminB6: f.vitaminB6,
    vitaminB12: f.vitaminB12,
    folate: f.folate,
    iron: f.iron,
    calcium: f.calcium,
    magnesium: f.magnesium,
    potassium: f.potassium,
    zinc: f.zinc,
    phosphorus: f.phosphorus,
  );

  static final RegExp _fruitHints = RegExp(
    r'\b(banana|apple|mango|papaya|strawberry|blueberry|orange|saba|grape|pineapple|watermelon|pear|berry|kiwi)\b',
  );
  static final RegExp _dairyProteinHints = RegExp(
    r'\b(milk|yogurt|yoghurt|cheese|cottage|whey)\b',
  );

  /// Coarse food group from name hints + macro thresholds — the same cuts the
  /// GA uses to build its slot pools. Callers with per-serving values (a
  /// logged [FoodItem]) may pass them directly; the thresholds assume a
  /// roughly 100 g serving, matching the historical heuristic.
  static String inferCategory({
    required String name,
    required double caloriesPer100,
    required double proteinPer100,
    required double carbsPer100,
    required double fatPer100,
  }) {
    final n = name.toLowerCase();
    if (_fruitHints.hasMatch(n)) return 'fruit';
    if (_dairyProteinHints.hasMatch(n) && !n.contains('milkfish')) {
      return 'protein';
    }
    if (proteinPer100 >= 8) return 'protein';
    if (fatPer100 >= 8 && carbsPer100 < 10) return 'fat';
    if (carbsPer100 >= 15 && proteinPer100 < 8) return 'grain';
    if (caloriesPer100 <= 60 && carbsPer100 < 15) return 'vegetable';
    return 'other'; // unknown → blocks no slot
  }

  /// Allergen flags from the food name, sharing [DietaryFilter]'s guarded
  /// matchers (`milkfish`/plant-milk are not dairy; coconut is not a nut).
  static List<String> deriveAllergens(String name) {
    final n = name.toLowerCase();
    return [
      if (DietaryFilter.matchesDairy(n)) 'dairy',
      if (DietaryFilter.matchesNuts(n)) 'nuts',
    ];
  }
}
