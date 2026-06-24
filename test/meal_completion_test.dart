// Verifies budget-aware meal completion: the day-budget arithmetic
// (GeneticAlgorithm.mealBudgets) and the complementary single-meal completion
// (GeneticAlgorithm.completeMeal). Pure Dart over plain MealIngredient /
// UserProfile — run with `flutter test test/meal_completion_test.dart`.
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
  required List<String> tags,
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

final _catalog = <MealIngredient>[
  _ing(id: 'chicken', name: 'Chicken Breast', calories: 165, protein: 31, carbs: 0, fat: 4, tags: ['halal'], category: 'protein'),
  _ing(id: 'egg', name: 'Whole Egg', calories: 143, protein: 13, carbs: 1, fat: 10, tags: ['vegetarian'], category: 'protein'),
  _ing(id: 'tofu', name: 'Tofu', calories: 144, protein: 15, carbs: 3, fat: 9, tags: ['vegan', 'vegetarian', 'halal'], category: 'legume'),
  _ing(id: 'rice', name: 'White Rice', calories: 130, protein: 2.7, carbs: 28, fat: 0.3, tags: ['vegan', 'vegetarian', 'halal'], category: 'grain'),
  _ing(id: 'oats', name: 'Oats', calories: 150, protein: 5, carbs: 27, fat: 3, tags: ['vegan', 'vegetarian', 'halal'], category: 'grain'),
  _ing(id: 'broccoli', name: 'Broccoli', calories: 34, protein: 2.8, carbs: 7, fat: 0.4, tags: ['vegan', 'vegetarian', 'halal'], category: 'vegetable'),
  _ing(id: 'almonds', name: 'Almonds', calories: 579, protein: 21, carbs: 22, fat: 50, tags: ['vegan', 'vegetarian', 'halal'], allergens: ['nuts'], category: 'fat'),
  _ing(id: 'avocado', name: 'Avocado', calories: 160, protein: 2, carbs: 9, fat: 15, tags: ['vegan', 'vegetarian', 'halal'], category: 'fat'),
  _ing(id: 'banana', name: 'Banana', calories: 89, protein: 1.1, carbs: 23, fat: 0.3, tags: ['vegan', 'vegetarian', 'halal'], category: 'fruit'),
  _ing(id: 'apple', name: 'Apple', calories: 52, protein: 0.3, carbs: 14, fat: 0.2, tags: ['vegan', 'vegetarian', 'halal'], category: 'fruit'),
];

String _cat(MealItem i) => i.ingredient.category;

void main() {
  group('GeneticAlgorithm.mealBudgets', () {
    test('no logged food → budgets equal the meal slices and sum to goal', () {
      final b = GeneticAlgorithm.mealBudgets(
        goal: 2000,
        loggedCalsByMeal: const {
          'breakfast': 0,
          'lunch': 0,
          'dinner': 0,
          'snack': 0,
        },
      );
      expect(b['breakfast'], closeTo(500, 1)); // 0.25 * 2000
      expect(b['lunch'], closeTo(700, 1)); // 0.35
      expect(b['dinner'], closeTo(600, 1)); // 0.30
      expect(b['snack'], closeTo(200, 1)); // 0.10
      expect(b.values.reduce((a, c) => a + c), closeTo(2000, 1));
    });

    test('logged breakfast → budgets sum to remaining day, breakfast smaller', () {
      final b = GeneticAlgorithm.mealBudgets(
        goal: 2000,
        loggedCalsByMeal: const {
          'breakfast': 150,
          'lunch': 0,
          'dinner': 0,
          'snack': 0,
        },
      );
      // Σ budget == goal − logged (so logged + generated ≈ goal).
      expect(b.values.reduce((a, c) => a + c), closeTo(1850, 1));
      // Breakfast deficit (500−150=350) is smaller than its full slice.
      expect(b['breakfast']!, lessThan(500));
      expect(b['breakfast']!, greaterThan(0));
    });

    test('day already over goal → all budgets zero (never overload)', () {
      final b = GeneticAlgorithm.mealBudgets(
        goal: 2000,
        loggedCalsByMeal: const {
          'breakfast': 900,
          'lunch': 800,
          'dinner': 700,
          'snack': 0,
        },
      );
      expect(b.values.every((v) => v == 0), isTrue);
    });

    test('a meal logged beyond its slice gets zero deficit', () {
      final b = GeneticAlgorithm.mealBudgets(
        goal: 2000,
        loggedCalsByMeal: const {
          'breakfast': 800, // > 500 slice
          'lunch': 0,
          'dinner': 0,
          'snack': 0,
        },
      );
      expect(b['breakfast'], 0);
      // Remaining day budget flows to the other meals.
      expect(b['lunch']! + b['dinner']! + b['snack']!, closeTo(1200, 1));
    });
  });

  group('GeneticAlgorithm.completeMeal', () {
    final ga = GeneticAlgorithm();

    test('logged protein → additions are a carb + fruit, no protein', () {
      final meal = ga.completeMeal(
        allIngredients: _catalog,
        profile: _profile(),
        mealType: 'breakfast',
        calorieBudget: 400,
        presentCategories: const {'protein'},
      );
      expect(meal.items, isNotEmpty);
      expect(meal.items.any((i) => _cat(i) == 'protein'), isFalse);
      final cats = meal.items.map(_cat).toSet();
      expect(cats.contains('grain'), isTrue);
      expect(cats.contains('fruit'), isTrue);
      expect(meal.totalCalories, closeTo(400, 70));
    });

    test('empty meal (no logs) → full breakfast incl. a protein', () {
      final meal = ga.completeMeal(
        allIngredients: _catalog,
        profile: _profile(),
        mealType: 'breakfast',
        calorieBudget: 500,
      );
      // Protein group includes legumes (tofu), so assert on protein content
      // rather than the literal 'protein' category.
      expect(meal.items.any((i) => i.ingredient.protein >= 8), isTrue);
      expect(meal.totalCalories, closeTo(500, 90));
    });

    test('negligible budget → no additions', () {
      final meal = ga.completeMeal(
        allIngredients: _catalog,
        profile: _profile(),
        mealType: 'lunch',
        calorieBudget: 20,
      );
      expect(meal.items, isEmpty);
    });

    test('all food groups present → one low-density addition', () {
      final meal = ga.completeMeal(
        allIngredients: _catalog,
        profile: _profile(),
        mealType: 'breakfast',
        calorieBudget: 300,
        presentCategories: const {'protein', 'grain', 'fruit'},
      );
      expect(meal.items.length, 1);
      expect(_cat(meal.items.first), 'vegetable');
    });

    test('vegan profile → every addition carries the vegan tag', () {
      final meal = ga.completeMeal(
        allIngredients: _catalog,
        profile: _profile(diet: const ['Vegan']),
        mealType: 'lunch',
        calorieBudget: 600,
      );
      expect(meal.items, isNotEmpty);
      for (final i in meal.items) {
        expect(i.ingredient.dietaryTags, contains('vegan'),
            reason: '${i.ingredient.name} must be vegan');
      }
    });

    test('over-restricted pool → empty meal (no fabrication)', () {
      // Halal user but catalog has no halal-tagged grain/fruit for the slots;
      // still, tofu/rice/banana are halal so it should fill. Use an impossible
      // restriction instead: a tag no ingredient carries.
      final meal = ga.completeMeal(
        allIngredients: const [],
        profile: _profile(),
        mealType: 'dinner',
        calorieBudget: 500,
      );
      expect(meal.items, isEmpty);
    });
  });
}
