// Verifies that completeMeal lands close to its calorie budget across a range
// of ingredient densities — exercising the scaleToCalories + closeResidual
// recovery path. Pools use one ingredient per category so selection is
// deterministic. Pure Dart — `flutter test test/meal_accuracy_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/genetic_algorithm.dart';
import 'package:onefit/models/meal_ingredient.dart';
import 'package:onefit/models/user_profile.dart';

MealIngredient _ing({
  required String id,
  required String name,
  required double calories,
  required double protein,
  required double carbs,
  required double fat,
  String category = 'other',
}) => MealIngredient(
  id: id,
  name: name,
  calories: calories,
  protein: protein,
  carbs: carbs,
  fat: fat,
  fiber: 0,
  sugar: 0,
  sodium: 0,
  dietaryTags: const ['vegan', 'vegetarian', 'halal'],
  cuisine: 'universal',
  category: category,
);

UserProfile _profile() => UserProfile(
  uid: 'test',
  name: 'Test',
  gender: 'Male',
  age: 30,
  weight: 75,
  height: 175,
  fitnessGoal: 'Endurance',
  experienceLevel: 'Intermediate',
  workoutLocation: 'Home',
  equipment: const ['Bodyweight'],
  dietaryRestrictions: const ['Balanced'],
);

// Low-density across every slot category — the case that used to truncate at
// the 350g clamp with no recovery.
final _lowDensity = <MealIngredient>[
  _ing(id: 'tofu', name: 'Tofu', calories: 144, protein: 15, carbs: 3, fat: 9, category: 'protein'),
  _ing(id: 'potato', name: 'Boiled Potato', calories: 87, protein: 2, carbs: 20, fat: 0, category: 'grain'),
  _ing(id: 'broccoli', name: 'Broccoli', calories: 34, protein: 2.8, carbs: 7, fat: 0.4, category: 'vegetable'),
  _ing(id: 'avocado', name: 'Avocado', calories: 160, protein: 2, carbs: 9, fat: 15, category: 'fat'),
  _ing(id: 'berry', name: 'Strawberry', calories: 32, protein: 0.7, carbs: 8, fat: 0.3, category: 'fruit'),
];

// High-density across every slot — items hit the 30g LOWER clamp; scaling down
// is the stress here.
final _highDensity = <MealIngredient>[
  _ing(id: 'pb', name: 'Peanut Butter', calories: 588, protein: 25, carbs: 20, fat: 50, category: 'protein'),
  _ing(id: 'granola', name: 'Granola', calories: 489, protein: 10, carbs: 64, fat: 20, category: 'grain'),
  _ing(id: 'oil', name: 'Olive Oil', calories: 884, protein: 0, carbs: 0, fat: 100, category: 'fat'),
  _ing(id: 'raisin', name: 'Raisins', calories: 299, protein: 3, carbs: 79, fat: 0.5, category: 'fruit'),
  _ing(id: 'kale', name: 'Kale', calories: 49, protein: 4, carbs: 9, fat: 0.9, category: 'vegetable'),
];

void main() {
  final ga = GeneticAlgorithm();

  group('completeMeal calorie accuracy', () {
    test('all-low-density lunch lands within ±75 of a 700 budget', () {
      final meal = ga.completeMeal(
        allIngredients: _lowDensity,
        profile: _profile(),
        mealType: 'lunch',
        calorieBudget: 700,
      );
      expect(meal.totalCalories, closeTo(700, 75));
    });

    test('all-high-density breakfast lands within ±75 of a 500 budget', () {
      final meal = ga.completeMeal(
        allIngredients: _highDensity,
        profile: _profile(),
        mealType: 'breakfast',
        calorieBudget: 500,
      );
      expect(meal.totalCalories, closeTo(500, 75));
    });

    test('every meal type at its natural 2000-cal-day budget is within ±75', () {
      final cases = {
        'breakfast': 500.0, // 0.25
        'lunch': 700.0, // 0.35
        'dinner': 600.0, // 0.30
      };
      cases.forEach((mealType, budget) {
        final meal = ga.completeMeal(
          allIngredients: _lowDensity,
          profile: _profile(),
          mealType: mealType,
          calorieBudget: budget,
        );
        expect(meal.totalCalories, closeTo(budget, 75),
            reason: '$mealType budget $budget');
      });
    });

    test('single-item snack with moderate density is within ±30', () {
      // Banana-like fruit (89 cal/100g) at a 200-cal snack budget → ~225g,
      // well inside the 400g clamp.
      final pool = [
        _ing(id: 'banana', name: 'Banana', calories: 89, protein: 1.1, carbs: 23, fat: 0.3, category: 'fruit'),
      ];
      final meal = ga.completeMeal(
        allIngredients: pool,
        profile: _profile(),
        mealType: 'snack',
        calorieBudget: 200,
      );
      expect(meal.totalCalories, closeTo(200, 30));
    });

    test('single-item snack with very-low-density food hits the physical limit', () {
      // Broccoli (34 cal/100g) would need ~588g for a 200-cal snack; the 400g
      // clamp caps it at ~136 cal. A single low-density item cannot reach a high
      // budget — documented limitation (real snack pools include denser options).
      final pool = [
        _ing(id: 'broccoli', name: 'Broccoli', calories: 34, protein: 2.8, carbs: 7, fat: 0.4, category: 'vegetable'),
      ];
      final meal = ga.completeMeal(
        allIngredients: pool,
        profile: _profile(),
        mealType: 'snack',
        calorieBudget: 200,
      );
      expect(meal.totalCalories, closeTo(136, 10)); // 400g * 0.34
    });
  });

  group('Meal.closeResidual', () {
    test('recovers a clamp-truncated scale-up to within tolerance', () {
      // A single low-density item scaled toward a high target would clamp at
      // 350/400g; closeResidual cannot exceed the 400g ceiling, but a multi-item
      // meal redistributes the gap. Build a 2-item meal under target and close it.
      final meal = Meal(mealType: 'lunch', items: [
        MealItem(ingredient: _lowDensity[0], portionGrams: 100), // tofu 144
        MealItem(ingredient: _lowDensity[1], portionGrams: 100), // potato 87
      ]);
      // current total = 231; close toward 600.
      final closed = meal.closeResidual(600);
      expect(closed.totalCalories, closeTo(600, 30));
    });

    test('leaves a meal already on target untouched', () {
      final meal = Meal(mealType: 'snack', items: [
        MealItem(ingredient: _lowDensity[0], portionGrams: 100), // 144 cal
      ]);
      final closed = meal.closeResidual(144);
      expect(closed.totalCalories, closeTo(144, 1));
    });
  });
}
