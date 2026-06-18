// Panelist-style verification of the meal-generation dietary matrix:
// inclusion tags × exclusion allergens × diet-style macro targets, plus the
// fail-safe behaviour when nothing matches.
//
// GeneticAlgorithm.generatePlan is pure Dart over plain MealIngredient /
// UserProfile objects (no Firebase), so the whole matrix can be asserted with
// `flutter test test/meal_restriction_matrix_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/genetic_algorithm.dart';
import 'package:onefit/models/meal_ingredient.dart';
import 'package:onefit/models/user_profile.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

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

UserProfile _profile({
  List<String> diet = const ['Balanced'],
  String goal = 'Endurance', // high-carb / low-protein baseline for contrast
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

// A broad catalog covering every meal pool for vegan/vegetarian/halal users.
final _catalog = <MealIngredient>[
  // Animal proteins
  _ing(id: 'chicken', name: 'Chicken Breast', calories: 165, protein: 31, carbs: 0, fat: 4, tags: ['halal'], category: 'protein'),
  _ing(id: 'salmon', name: 'Salmon', calories: 208, protein: 20, carbs: 0, fat: 13, tags: ['halal'], category: 'protein'),
  _ing(id: 'egg', name: 'Whole Egg', calories: 143, protein: 13, carbs: 1, fat: 10, tags: ['vegetarian'], category: 'protein'),
  // Dairy (allergen: dairy)
  _ing(id: 'whey', name: 'Whey Protein', calories: 400, protein: 80, carbs: 8, fat: 5, tags: ['vegetarian'], allergens: ['dairy'], category: 'dairy'),
  _ing(id: 'milk', name: 'Whole Milk', calories: 60, protein: 3, carbs: 5, fat: 3, tags: ['vegetarian'], allergens: ['dairy'], category: 'dairy'),
  _ing(id: 'cheese', name: 'Cheddar Cheese', calories: 400, protein: 25, carbs: 1, fat: 33, tags: ['vegetarian'], allergens: ['dairy'], category: 'dairy'),
  // Plant proteins (vegan)
  _ing(id: 'tofu', name: 'Tofu', calories: 144, protein: 15, carbs: 3, fat: 9, tags: ['vegan', 'vegetarian', 'halal'], category: 'legume'),
  _ing(id: 'lentils', name: 'Lentils', calories: 116, protein: 9, carbs: 20, fat: 0, tags: ['vegan', 'vegetarian', 'halal'], category: 'legume'),
  _ing(id: 'peapro', name: 'Pea Protein Powder', calories: 380, protein: 80, carbs: 5, fat: 6, tags: ['vegan', 'vegetarian', 'halal'], category: 'protein'),
  // Carbs
  _ing(id: 'rice', name: 'White Rice', calories: 130, protein: 2.7, carbs: 28, fat: 0.3, tags: ['vegan', 'vegetarian', 'halal'], category: 'grain'),
  _ing(id: 'bread', name: 'Bread', calories: 265, protein: 9, carbs: 49, fat: 3, tags: ['vegetarian', 'halal'], category: 'grain'),
  // Vegetables
  _ing(id: 'broccoli', name: 'Broccoli', calories: 34, protein: 2.8, carbs: 7, fat: 0.4, tags: ['vegan', 'vegetarian', 'halal'], category: 'vegetable'),
  _ing(id: 'spinach', name: 'Spinach', calories: 23, protein: 2.9, carbs: 3.6, fat: 0.4, tags: ['vegan', 'vegetarian', 'halal'], category: 'vegetable'),
  // Fats (almonds carry a nut allergen)
  _ing(id: 'almonds', name: 'Almonds', calories: 579, protein: 21, carbs: 22, fat: 50, tags: ['vegan', 'vegetarian', 'halal'], allergens: ['nuts'], category: 'fat'),
  _ing(id: 'avocado', name: 'Avocado', calories: 160, protein: 2, carbs: 9, fat: 15, tags: ['vegan', 'vegetarian', 'halal'], category: 'fat'),
  // Fruit (snack)
  _ing(id: 'banana', name: 'Banana', calories: 89, protein: 1.1, carbs: 23, fat: 0.3, tags: ['vegan', 'vegetarian', 'halal'], category: 'fruit'),
  _ing(id: 'apple', name: 'Apple', calories: 52, protein: 0.3, carbs: 14, fat: 0.2, tags: ['vegan', 'vegetarian', 'halal'], category: 'fruit'),
];

Iterable<MealIngredient> _used(DayMealPlan d) => [
  ...d.breakfast.items,
  ...d.lunch.items,
  ...d.dinner.items,
  ...d.snack.items,
].map((i) => i.ingredient);

List<MealIngredient> _allUsed(List<DayMealPlan> plan) =>
    plan.expand(_used).toList();

void main() {
  final ga = GeneticAlgorithm();

  group('Inclusion tags — produced meals carry the required tag', () {
    void expectAllTagged(String restriction, String tag) {
      final plan = ga.generatePlan(
        allIngredients: _catalog,
        profile: _profile(diet: [restriction]),
      );
      expect(plan, isNotEmpty, reason: '$restriction should be satisfiable');
      for (final ing in _allUsed(plan)) {
        expect(
          ing.dietaryTags.map((t) => t.toLowerCase()),
          contains(tag),
          reason: '${ing.name} lacks "$tag" but was served to a $restriction user',
        );
      }
    }

    test('Vegan', () => expectAllTagged('Vegan', 'vegan'));
    test('Vegetarian', () => expectAllTagged('Vegetarian', 'vegetarian'));
    test('Halal', () => expectAllTagged('Halal', 'halal'));
  });

  group('Exclusion allergens — produced meals never contain the allergen', () {
    void expectNoAllergen(String restriction, String allergen) {
      final plan = ga.generatePlan(
        allIngredients: _catalog,
        profile: _profile(diet: [restriction]),
      );
      expect(plan, isNotEmpty);
      for (final ing in _allUsed(plan)) {
        expect(
          ing.allergens.map((a) => a.toLowerCase()),
          isNot(contains(allergen)),
          reason: '${ing.name} contains "$allergen" but was served to a $restriction user',
        );
      }
    }

    test('Nut-free excludes nuts', () => expectNoAllergen('Nut-free', 'nuts'));
    test('Lactose-intolerant excludes dairy',
        () => expectNoAllergen('Lactose-intolerant', 'dairy'));
  });

  group('Cross-selections honour every restriction at once', () {
    test('Vegan + Nut-free', () {
      final plan = ga.generatePlan(
        allIngredients: _catalog,
        profile: _profile(diet: ['Vegan', 'Nut-free']),
      );
      expect(plan, isNotEmpty);
      for (final ing in _allUsed(plan)) {
        expect(ing.dietaryTags, contains('vegan'));
        expect(ing.allergens, isNot(contains('nuts')));
      }
    });

    test('Vegan + Lactose-intolerant', () {
      final plan = ga.generatePlan(
        allIngredients: _catalog,
        profile: _profile(diet: ['Vegan', 'Lactose-intolerant']),
      );
      expect(plan, isNotEmpty);
      for (final ing in _allUsed(plan)) {
        expect(ing.dietaryTags, contains('vegan'));
        expect(ing.allergens, isNot(contains('dairy')));
      }
    });

    test('Vegetarian + Halal', () {
      final plan = ga.generatePlan(
        allIngredients: _catalog,
        profile: _profile(diet: ['Vegetarian', 'Halal']),
      );
      expect(plan, isNotEmpty);
      for (final ing in _allUsed(plan)) {
        expect(ing.dietaryTags, containsAll(['vegetarian', 'halal']));
      }
    });
  });

  group('Diet styles reshape macro targets', () {
    double avgProtein(List<DayMealPlan> p) =>
        p.map((d) => d.totalProtein).reduce((a, b) => a + b) / p.length;
    double avgCarbs(List<DayMealPlan> p) =>
        p.map((d) => d.totalCarbs).reduce((a, b) => a + b) / p.length;

    test('High-protein yields more protein than Balanced', () {
      final balanced = ga.generatePlan(
        allIngredients: _catalog,
        profile: _profile(diet: ['Vegan', 'Balanced']),
      );
      final highProtein = ga.generatePlan(
        allIngredients: _catalog,
        profile: _profile(diet: ['Vegan', 'High-protein']),
      );
      expect(avgProtein(highProtein), greaterThan(avgProtein(balanced)));
    });

    test('Low-carb yields fewer carbs than Balanced', () {
      final balanced = ga.generatePlan(
        allIngredients: _catalog,
        profile: _profile(diet: ['Vegan', 'Balanced']),
      );
      final lowCarb = ga.generatePlan(
        allIngredients: _catalog,
        profile: _profile(diet: ['Vegan', 'Low-carb']),
      );
      expect(avgCarbs(lowCarb), lessThan(avgCarbs(balanced)));
    });
  });

  group('Fail-safe — never serve violating food', () {
    test('An impossible restriction returns an empty plan, not a fallback', () {
      // A catalog with no vegan items at all. The generator must return an
      // empty plan (sentinel) so the UI can warn — it must NOT fall back to the
      // unfiltered catalog and serve meat to a vegan.
      final nonVegan = [
        _ing(id: 'chicken', name: 'Chicken', calories: 165, protein: 31, carbs: 0, fat: 4, tags: ['halal'], category: 'protein'),
        _ing(id: 'rice', name: 'White Rice', calories: 130, protein: 2.7, carbs: 28, fat: 0.3, tags: ['halal'], category: 'grain'),
        _ing(id: 'broccoli', name: 'Broccoli', calories: 34, protein: 2.8, carbs: 7, fat: 0.4, tags: ['halal'], category: 'vegetable'),
      ];
      final plan = ga.generatePlan(
        allIngredients: nonVegan,
        profile: _profile(diet: ['Vegan']),
      );
      expect(plan, isEmpty);
    });
  });
}
