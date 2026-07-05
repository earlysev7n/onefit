// Verifies IngredientConverter — per-100g normalization of user-picked foods
// (USDA search / barcode / history) plus the shared category and allergen
// inference. Pure Dart — run with `flutter test test/ingredient_converter_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/models/food_item.dart';
import 'package:onefit/services/ingredient_converter.dart';

void main() {
  group('fromPerServing — normalization', () {
    test('50 g serving → every nutrient doubled to per-100g', () {
      final ing = IngredientConverter.fromPerServing(
        id: 'usda_1',
        name: 'Granola',
        servingSize: 50,
        servingUnit: 'g',
        calories: 100,
        protein: 5,
        carbs: 30,
        fat: 4,
        fiber: 2,
        sugar: 10,
        sodium: 60,
        vitaminC: 3,
        iron: 1.5,
      );
      expect(ing.calories, closeTo(200, 0.001));
      expect(ing.protein, closeTo(10, 0.001));
      expect(ing.carbs, closeTo(60, 0.001));
      expect(ing.fat, closeTo(8, 0.001));
      expect(ing.fiber, closeTo(4, 0.001));
      expect(ing.sugar, closeTo(20, 0.001));
      expect(ing.sodium, closeTo(120, 0.001));
      expect(ing.vitaminC, closeTo(6, 0.001));
      expect(ing.iron, closeTo(3, 0.001));
    });

    test('100 g serving → identity', () {
      final ing = IngredientConverter.fromPerServing(
        id: 'usda_2',
        name: 'White Rice',
        servingSize: 100,
        servingUnit: 'g',
        calories: 130,
        protein: 2.7,
        carbs: 28,
        fat: 0.3,
      );
      expect(ing.calories, closeTo(130, 0.001));
      expect(ing.carbs, closeTo(28, 0.001));
    });

    test('non-gram unit → values passed through (100 g fallback)', () {
      final ing = IngredientConverter.fromPerServing(
        id: 'off_3',
        name: 'Protein Bar',
        servingSize: 1,
        servingUnit: 'bar',
        calories: 220,
        protein: 20,
        carbs: 22,
        fat: 8,
      );
      expect(ing.calories, closeTo(220, 0.001));
      expect(ing.protein, closeTo(20, 0.001));
    });

    test('ml serving treated 1:1 with grams', () {
      final ing = IngredientConverter.fromPerServing(
        id: 'off_4',
        name: 'Oat Drink',
        servingSize: 250,
        servingUnit: 'ml',
        calories: 115,
        protein: 2.5,
        carbs: 16,
        fat: 3.5,
      );
      expect(ing.calories, closeTo(46, 0.01)); // 115 × 100/250
    });
  });

  group('fromFoodItem', () {
    test('uses per-serving base and ignores the logged quantity', () {
      final food = FoodItem(
        id: 'log1',
        userId: 'u',
        name: 'Chicken Breast',
        barcode: '12345',
        servingSize: 50,
        servingSizeUnit: 'g',
        calories: 82.5,
        protein: 15.5,
        carbs: 0,
        fat: 2,
        loggedAt: DateTime(2026, 1, 1),
        mealType: 'lunch',
        quantity: 3.0, // must be irrelevant — the GA re-decides grams
      );
      final ing = IngredientConverter.fromFoodItem(food);
      expect(ing.id, 'picked_12345');
      expect(ing.calories, closeTo(165, 0.01)); // 82.5 × 100/50
      expect(ing.protein, closeTo(31, 0.01));
    });

    test('falls back to the log id when barcode is empty', () {
      final food = FoodItem(
        id: 'log2',
        userId: 'u',
        name: 'Oats',
        barcode: '',
        servingSize: 100,
        servingSizeUnit: 'g',
        calories: 150,
        protein: 5,
        carbs: 27,
        fat: 3,
        loggedAt: DateTime(2026, 1, 1),
        mealType: 'breakfast',
      );
      expect(IngredientConverter.fromFoodItem(food).id, 'picked_log2');
    });
  });

  group('inferCategory', () {
    String cat({
      required String name,
      double cal = 0,
      double p = 0,
      double c = 0,
      double f = 0,
    }) => IngredientConverter.inferCategory(
      name: name,
      caloriesPer100: cal,
      proteinPer100: p,
      carbsPer100: c,
      fatPer100: f,
    );

    test('macro thresholds', () {
      expect(cat(name: 'Chicken Breast', cal: 165, p: 31, f: 4), 'protein');
      expect(cat(name: 'White Rice', cal: 130, p: 2.7, c: 28, f: 0.3), 'grain');
      expect(cat(name: 'Spinach', cal: 23, p: 2.9, c: 3.6, f: 0.4), 'vegetable');
      expect(cat(name: 'Olive Oil', cal: 884, f: 100), 'fat');
    });

    test('name hints beat macros', () {
      expect(cat(name: 'Banana', cal: 89, c: 23), 'fruit');
      expect(cat(name: 'Greek Yogurt', cal: 59, p: 10), 'protein');
      expect(cat(name: 'Milkfish', cal: 148, p: 20, f: 7), 'protein'); // via macros, not dairy hint
    });
  });

  group('deriveAllergens', () {
    test('dairy and nuts with the DietaryFilter guards', () {
      expect(IngredientConverter.deriveAllergens('Cheddar Cheese'), ['dairy']);
      // 'butter' is a dairy keyword in DietaryFilter, so nut butters carry
      // both flags — the same conservative false positive the USDA search
      // filter has always had (hides more than strictly needed, never less).
      expect(
        IngredientConverter.deriveAllergens('Almond Butter'),
        ['dairy', 'nuts'],
      );
      expect(IngredientConverter.deriveAllergens('Milkfish'), isEmpty);
      expect(IngredientConverter.deriveAllergens('Almond Milk'), ['nuts']);
      expect(IngredientConverter.deriveAllergens('Whole Milk'), ['dairy']);
      expect(IngredientConverter.deriveAllergens('White Rice'), isEmpty);
    });
  });
}
