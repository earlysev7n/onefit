// Verifies the evolutionary meal path (GeneticAlgorithm.evolveMeal): fitness
// convergence, superiority over random slot-filling, restriction compliance,
// calorie accuracy, cross-meal variety, and seeded reproducibility. Pure Dart —
// run with `flutter test test/genetic_algorithm_test.dart`.
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
  List<String> tags = const ['vegan', 'vegetarian', 'halal'],
  List<String> allergens = const [],
  String category = 'other',
  String cuisine = 'universal',
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
  dietaryTags: tags,
  allergens: allergens,
  category: category,
  cuisine: cuisine,
);

UserProfile _profile({
  List<String> diet = const ['Balanced'],
  String goal = 'Muscle Gain',
}) => UserProfile(
  uid: 'test',
  name: 'Test',
  gender: 'Male',
  age: 30,
  weight: 75,
  height: 175,
  fitnessGoal: goal,
  experienceLevel: 'Intermediate',
  workoutLocation: 'Home',
  equipment: const ['Bodyweight'],
  dietaryRestrictions: diet,
);

// A varied catalog: several options per slot with very different macro
// profiles, so evolution has real choices to optimise over.
final _catalog = <MealIngredient>[
  // Proteins — lean → fatty spectrum.
  _ing(id: 'chicken', name: 'Chicken Breast', calories: 165, protein: 31, carbs: 0, fat: 4, tags: const ['halal'], category: 'protein'),
  _ing(id: 'salmon', name: 'Salmon', calories: 208, protein: 20, carbs: 0, fat: 13, tags: const ['halal'], category: 'protein'),
  _ing(id: 'egg', name: 'Whole Egg', calories: 143, protein: 13, carbs: 1, fat: 10, tags: const ['vegetarian'], category: 'protein'),
  _ing(id: 'tofu', name: 'Tofu', calories: 144, protein: 15, carbs: 3, fat: 9, category: 'legume'),
  _ing(id: 'lentils', name: 'Lentils', calories: 116, protein: 9, carbs: 20, fat: 0.4, category: 'legume'),
  // Grains — protein-poor → protein-rich spectrum.
  _ing(id: 'rice', name: 'White Rice', calories: 130, protein: 2.7, carbs: 28, fat: 0.3, category: 'grain'),
  _ing(id: 'oats', name: 'Oats', calories: 150, protein: 5, carbs: 27, fat: 3, category: 'grain'),
  _ing(id: 'quinoa', name: 'Quinoa', calories: 120, protein: 4.4, carbs: 21, fat: 1.9, category: 'grain'),
  _ing(id: 'bread', name: 'Wheat Bread', calories: 247, protein: 13, carbs: 41, fat: 3.4, category: 'grain'),
  // Vegetables.
  _ing(id: 'broccoli', name: 'Broccoli', calories: 34, protein: 2.8, carbs: 7, fat: 0.4, category: 'vegetable'),
  _ing(id: 'spinach', name: 'Spinach', calories: 23, protein: 2.9, carbs: 3.6, fat: 0.4, category: 'vegetable'),
  _ing(id: 'carrots', name: 'Carrots', calories: 41, protein: 0.9, carbs: 10, fat: 0.2, category: 'vegetable'),
  // Fats.
  _ing(id: 'avocado', name: 'Avocado', calories: 160, protein: 2, carbs: 9, fat: 15, category: 'fat'),
  _ing(id: 'almonds', name: 'Almonds', calories: 579, protein: 21, carbs: 22, fat: 50, allergens: const ['nuts'], category: 'fat'),
  _ing(id: 'oliveoil2', name: 'Peanut Butter', calories: 588, protein: 25, carbs: 20, fat: 50, allergens: const ['nuts'], category: 'fat'),
  // Fruits.
  _ing(id: 'banana', name: 'Banana', calories: 89, protein: 1.1, carbs: 23, fat: 0.3, category: 'fruit'),
  _ing(id: 'apple', name: 'Apple', calories: 52, protein: 0.3, carbs: 14, fat: 0.2, category: 'fruit'),
  _ing(id: 'mango', name: 'Mango', calories: 60, protein: 0.8, carbs: 15, fat: 0.4, category: 'fruit'),
  // Two macro-identical dairy snacks — used by the avoidIds variety test.
  _ing(id: 'yogurtA', name: 'Greek Yogurt', calories: 59, protein: 10, carbs: 3.6, fat: 0.4, tags: const ['vegetarian', 'halal'], allergens: const ['dairy'], category: 'dairy'),
  _ing(id: 'yogurtB', name: 'Skyr Yogurt', calories: 59, protein: 10, carbs: 3.6, fat: 0.4, tags: const ['vegetarian', 'halal'], allergens: const ['dairy'], category: 'dairy'),
];

/// Sum of relative macro errors vs the meal's fair share of the daily
/// diet-style-aware targets — lower is a better macro fit.
double _macroError(
  Meal m,
  GeneticAlgorithm ga,
  UserProfile profile,
  double budget,
) {
  final daily = ga.macroTargetsFor(profile);
  final macroCals =
      daily['protein']! * 4 + daily['carbs']! * 4 + daily['fat']! * 9;
  final share = budget / macroCals;
  double err(double actual, double target) =>
      target > 0 ? ((actual - target) / target).abs() : 0;
  return err(m.totalProtein, daily['protein']! * share) +
      err(m.totalCarbs, daily['carbs']! * share) +
      err(m.totalFat, daily['fat']! * share);
}

void main() {
  group('GeneticAlgorithm.evolveMeal — evolution', () {
    test('best fitness is non-decreasing across generations (elitism)', () {
      final result = GeneticAlgorithm(random: Random(42)).evolveMeal(
        allIngredients: _catalog,
        profile: _profile(),
        mealType: 'lunch',
        calorieBudget: 700,
      );
      expect(result.fitnessTrace, isNotEmpty);
      expect(result.fitnessTrace.length, GeneticAlgorithm.mealGenerations);
      for (int i = 1; i < result.fitnessTrace.length; i++) {
        expect(
          result.fitnessTrace[i],
          greaterThanOrEqualTo(result.fitnessTrace[i - 1]),
          reason: 'elitism must never lose the best individual (gen $i)',
        );
      }
    });

    test('evolution actually improves fitness over the first generation', () {
      final result = GeneticAlgorithm(random: Random(7)).evolveMeal(
        allIngredients: _catalog,
        profile: _profile(),
        mealType: 'dinner',
        calorieBudget: 600,
      );
      expect(
        result.fitnessTrace.last,
        greaterThanOrEqualTo(result.fitnessTrace.first),
      );
    });

    test('evolved meal beats the mean macro fit of 20 random slot-fills', () {
      final profile = _profile();
      const budget = 700.0;
      final gaEval = GeneticAlgorithm();

      final evolved = GeneticAlgorithm(random: Random(42)).evolveMeal(
        allIngredients: _catalog,
        profile: profile,
        mealType: 'lunch',
        calorieBudget: budget,
      );
      final evolvedErr = _macroError(evolved.meal, gaEval, profile, budget);

      double sum = 0;
      for (int i = 0; i < 20; i++) {
        final random = GeneticAlgorithm(random: Random(1000 + i)).completeMeal(
          allIngredients: _catalog,
          profile: profile,
          mealType: 'lunch',
          calorieBudget: budget,
        );
        sum += _macroError(random, gaEval, profile, budget);
      }
      final meanRandomErr = sum / 20;

      expect(
        evolvedErr,
        lessThanOrEqualTo(meanRandomErr),
        reason:
            'optimised meal (err $evolvedErr) must not lose to the average '
            'random draw (err $meanRandomErr)',
      );
    });

    test('seeded runs are reproducible (same meal, same trace)', () {
      MealEvolutionResult run() => GeneticAlgorithm(random: Random(99)).evolveMeal(
        allIngredients: _catalog,
        profile: _profile(),
        mealType: 'breakfast',
        calorieBudget: 500,
      );
      final a = run();
      final b = run();
      expect(a.fitnessTrace, b.fitnessTrace);
      expect(
        a.meal.items.map((i) => i.ingredient.id).toList(),
        b.meal.items.map((i) => i.ingredient.id).toList(),
      );
      expect(
        a.meal.items.map((i) => i.portionGrams).toList(),
        b.meal.items.map((i) => i.portionGrams).toList(),
      );
    });
  });

  group('GeneticAlgorithm.evolveMeal — contract parity with completeMeal', () {
    test('calorie accuracy: lands within ±75 kcal of the budget', () {
      for (final budget in const [300.0, 500.0, 700.0]) {
        final result = GeneticAlgorithm(random: Random(5)).evolveMeal(
          allIngredients: _catalog,
          profile: _profile(),
          mealType: 'lunch',
          calorieBudget: budget,
        );
        expect(
          result.meal.totalCalories,
          closeTo(budget, 75),
          reason: 'budget $budget',
        );
      }
    });

    test('logged protein → additions contain no protein-group item', () {
      final result = GeneticAlgorithm(random: Random(3)).evolveMeal(
        allIngredients: _catalog,
        profile: _profile(),
        mealType: 'breakfast',
        calorieBudget: 400,
        presentCategories: const {'protein'},
      );
      expect(result.meal.items, isNotEmpty);
      for (final i in result.meal.items) {
        expect(
          const {'protein', 'dairy', 'legume'}.contains(i.ingredient.category),
          isFalse,
          reason: '${i.ingredient.name} duplicates the logged protein group',
        );
      }
    });

    test('negligible budget → empty meal and empty trace', () {
      final result = GeneticAlgorithm().evolveMeal(
        allIngredients: _catalog,
        profile: _profile(),
        mealType: 'lunch',
        calorieBudget: 20,
      );
      expect(result.meal.items, isEmpty);
      expect(result.fitnessTrace, isEmpty);
    });

    test('empty pool → empty meal (restrictions never relaxed)', () {
      final result = GeneticAlgorithm().evolveMeal(
        allIngredients: const [],
        profile: _profile(),
        mealType: 'dinner',
        calorieBudget: 500,
      );
      expect(result.meal.items, isEmpty);
    });

    test('vegan + nut-free profile → every evolved item complies', () {
      final result = GeneticAlgorithm(random: Random(11)).evolveMeal(
        allIngredients: _catalog,
        profile: _profile(diet: const ['Vegan', 'Nut-free']),
        mealType: 'lunch',
        calorieBudget: 600,
      );
      expect(result.meal.items, isNotEmpty);
      for (final i in result.meal.items) {
        expect(i.ingredient.dietaryTags, contains('vegan'),
            reason: '${i.ingredient.name} must be vegan');
        expect(i.ingredient.allergens, isNot(contains('nuts')),
            reason: '${i.ingredient.name} must be nut-free');
      }
    });
  });

  group('GeneticAlgorithm.evolveMeal — variety (avoidIds)', () {
    test('a macro-identical alternative wins over an avoided ingredient', () {
      // yogurtA and yogurtB are identical; penalising A must make B the
      // single-slot snack winner.
      final result = GeneticAlgorithm(random: Random(2)).evolveMeal(
        allIngredients: _catalog,
        profile: _profile(),
        mealType: 'snack',
        calorieBudget: 200,
        avoidIds: const {'yogurtA'},
      );
      expect(result.meal.items, hasLength(1));
      expect(result.meal.items.single.ingredient.id, isNot('yogurtA'));
    });
  });
}
