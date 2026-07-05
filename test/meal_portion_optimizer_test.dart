// Verifies GeneticAlgorithm.optimizeMealPortions — the Meal Planning
// Option A path where the user fixes the ingredient SET and the GA evolves
// the GRAM vector. Pure Dart over plain MealIngredient / UserProfile — run
// with `flutter test test/meal_portion_optimizer_test.dart`.
import 'dart:math';

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
  List<String> allergens = const [],
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
  // Picked ingredients (converter output) carry NO dietaryTags — that is the
  // scenario this method exists for.
  dietaryTags: const [],
  allergens: allergens,
  category: category,
  cuisine: 'universal',
);

UserProfile _profile({List<String> diet = const ['Balanced']}) => UserProfile(
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
  dietaryRestrictions: diet,
);

final _chicken = _ing(id: 'chicken', name: 'Chicken Breast', calories: 165, protein: 31, carbs: 0, fat: 4, category: 'protein');
final _rice = _ing(id: 'rice', name: 'White Rice', calories: 130, protein: 2.7, carbs: 28, fat: 0.3, category: 'grain');
final _broccoli = _ing(id: 'broccoli', name: 'Broccoli', calories: 34, protein: 2.8, carbs: 7, fat: 0.4, category: 'vegetable');
final _oil = _ing(id: 'oil', name: 'Olive Oil', calories: 884, protein: 0, carbs: 0, fat: 100, category: 'fat');
final _cheese = _ing(id: 'cheese', name: 'Cheddar Cheese', calories: 403, protein: 25, carbs: 1.3, fat: 33, allergens: ['dairy'], category: 'dairy');
final _almonds = _ing(id: 'almonds', name: 'Almonds', calories: 579, protein: 21, carbs: 22, fat: 50, allergens: ['nuts'], category: 'fat');
final _water = _ing(id: 'water', name: 'Water', calories: 0, protein: 0, carbs: 0, fat: 0);

GeneticAlgorithm _ga() => GeneticAlgorithm(random: Random(42));

void main() {
  group('optimizeMealPortions — chromosome contract', () {
    test('every picked ingredient appears exactly once, in order', () {
      final result = _ga().optimizeMealPortions(
        ingredients: [_chicken, _rice, _broccoli, _oil],
        profile: _profile(),
        mealType: 'lunch',
        calorieBudget: 600,
      );
      expect(
        result.meal.items.map((i) => i.ingredient.id).toList(),
        ['chicken', 'rice', 'broccoli', 'oil'],
      );
    });

    test('all portions stay within the 30–400 g clamp', () {
      final result = _ga().optimizeMealPortions(
        ingredients: [_chicken, _rice, _broccoli, _oil],
        profile: _profile(),
        mealType: 'lunch',
        calorieBudget: 600,
      );
      for (final item in result.meal.items) {
        expect(item.portionGrams, greaterThanOrEqualTo(30));
        expect(item.portionGrams, lessThanOrEqualTo(400));
      }
    });

    test('total calories land near the budget (same tolerance as other paths)', () {
      final result = _ga().optimizeMealPortions(
        ingredients: [_chicken, _rice, _broccoli, _oil],
        profile: _profile(),
        mealType: 'lunch',
        calorieBudget: 600,
      );
      expect(result.meal.totalCalories, closeTo(600, 75));
    });

    test('single-ingredient pick works (crossover guard) and stays clamped', () {
      final result = _ga().optimizeMealPortions(
        ingredients: [_chicken],
        profile: _profile(),
        mealType: 'snack',
        calorieBudget: 300,
      );
      expect(result.meal.items.length, 1);
      expect(result.meal.items.first.portionGrams, inInclusiveRange(30, 400));
    });

    test('fitness trace shows evolution (best never regresses to below start)', () {
      final result = _ga().optimizeMealPortions(
        ingredients: [_chicken, _rice, _broccoli, _oil],
        profile: _profile(),
        mealType: 'dinner',
        calorieBudget: 550,
      );
      expect(result.fitnessTrace, isNotEmpty);
      expect(
        result.fitnessTrace.last,
        greaterThanOrEqualTo(result.fitnessTrace.first),
      );
    });
  });

  group('optimizeMealPortions — guards', () {
    test('budget <= 30 → empty meal sentinel', () {
      final result = _ga().optimizeMealPortions(
        ingredients: [_chicken, _rice],
        profile: _profile(),
        mealType: 'snack',
        calorieBudget: 20,
      );
      expect(result.meal.items, isEmpty);
      expect(result.fitnessTrace, isEmpty);
    });

    test('zero-kcal ingredient is dropped, the rest still generate', () {
      final result = _ga().optimizeMealPortions(
        ingredients: [_water, _chicken, _rice],
        profile: _profile(),
        mealType: 'lunch',
        calorieBudget: 500,
      );
      final ids = result.meal.items.map((i) => i.ingredient.id).toList();
      expect(ids, isNot(contains('water')));
      expect(ids, containsAll(['chicken', 'rice']));
    });

    test('empty ingredient list → empty meal sentinel', () {
      final result = _ga().optimizeMealPortions(
        ingredients: const [],
        profile: _profile(),
        mealType: 'lunch',
        calorieBudget: 500,
      );
      expect(result.meal.items, isEmpty);
    });
  });

  group('optimizeMealPortions — dietary restrictions', () {
    test('lactose-intolerant profile excludes dairy-allergen ingredients', () {
      final result = _ga().optimizeMealPortions(
        ingredients: [_chicken, _cheese, _rice],
        profile: _profile(diet: const ['Lactose-intolerant']),
        mealType: 'lunch',
        calorieBudget: 500,
      );
      final ids = result.meal.items.map((i) => i.ingredient.id).toList();
      expect(ids, isNot(contains('cheese')));
      expect(ids, containsAll(['chicken', 'rice']));
    });

    test('nut-free profile excludes nut-allergen ingredients', () {
      final result = _ga().optimizeMealPortions(
        ingredients: [_almonds, _rice, _broccoli],
        profile: _profile(diet: const ['Nut-free']),
        mealType: 'snack',
        calorieBudget: 300,
      );
      final ids = result.meal.items.map((i) => i.ingredient.id).toList();
      expect(ids, isNot(contains('almonds')));
    });

    test('all ingredients restricted → empty sentinel, never a violating meal', () {
      final result = _ga().optimizeMealPortions(
        ingredients: [_cheese],
        profile: _profile(diet: const ['Lactose-intolerant']),
        mealType: 'snack',
        calorieBudget: 300,
      );
      expect(result.meal.items, isEmpty);
    });

    test('vegan profile over tag-less picked pool still generates '
        '(inclusion tags are screened by name upstream, not here)', () {
      final result = _ga().optimizeMealPortions(
        ingredients: [_rice, _broccoli, _oil],
        profile: _profile(diet: const ['Vegan']),
        mealType: 'lunch',
        calorieBudget: 450,
      );
      expect(result.meal.items, isNotEmpty);
    });
  });

  group('optimizeMealPortions — diet styles reshape targets', () {
    test('high-protein profile yields at least as much protein as balanced', () {
      final picked = [_chicken, _rice, _broccoli, _oil];
      final hp = _ga().optimizeMealPortions(
        ingredients: picked,
        profile: _profile(diet: const ['High-protein']),
        mealType: 'lunch',
        calorieBudget: 600,
      );
      final bal = _ga().optimizeMealPortions(
        ingredients: picked,
        profile: _profile(),
        mealType: 'lunch',
        calorieBudget: 600,
      );
      expect(
        hp.meal.totalProtein,
        greaterThanOrEqualTo(bal.meal.totalProtein - 1),
      );
    });
  });
}
