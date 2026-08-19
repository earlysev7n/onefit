// Pins GeneticAlgorithm.singleMealBudget — the compensating budget used when
// generating ONE meal at a time. Generating the day's empty meals one-by-one
// must converge on the calorie goal (matching the "All" button) while leaving a
// manually-logged meal untouched.

import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/genetic_algorithm.dart';

void main() {
  const goal = 3098.0;
  const meals = ['breakfast', 'lunch', 'dinner', 'snack'];

  double budget(String meal, Map<String, double> logged) =>
      GeneticAlgorithm.singleMealBudget(
        goal: goal,
        mealType: meal,
        loggedCalsByMeal: logged,
      );

  group('singleMealBudget convergence', () {
    test('lunch logged under-share → dinner/snack/breakfast reach the goal', () {
      // Screenshot scenario: lunch logged manually at 553, rest empty.
      final logged = {'breakfast': 0.0, 'lunch': 553.0, 'dinner': 0.0, 'snack': 0.0};

      // Generate the empty meals one-by-one, feeding each budget back as logged.
      final dinner = budget('dinner', logged);
      logged['dinner'] = dinner;
      final snack = budget('snack', logged);
      logged['snack'] = snack;
      final breakfast = budget('breakfast', logged);
      logged['breakfast'] = breakfast;

      // Dinner compensates (more than its bare 30% share of 3098 = 929).
      expect(dinner, greaterThan(1000));

      final total = meals.fold(0.0, (s, m) => s + logged[m]!);
      expect(total, closeTo(goal, 1.0));
      // The manually-logged lunch was never changed.
      expect(logged['lunch'], 553.0);
    });

    test('all-empty day: four sequential budgets sum to the goal', () {
      final logged = {for (final m in meals) m: 0.0};
      var total = 0.0;
      for (final m in ['breakfast', 'lunch', 'dinner', 'snack']) {
        final b = budget(m, logged);
        logged[m] = b;
        total += b;
      }
      expect(total, closeTo(goal, 1.0));
    });

    test('a single generated meal claims its share of the remaining budget', () {
      // Only dinner generated, everything else empty: remaining 3098 split over
      // the fill set {b,l,d,s} by ratio → dinner gets 0.30/1.0 * 3098.
      final logged = {for (final m in meals) m: 0.0};
      expect(budget('dinner', logged), closeTo(3098 * 0.30, 1.0));
    });
  });

  group('edge cases', () {
    test('day already at/over goal → 0', () {
      final logged = {
        'breakfast': 800.0,
        'lunch': 1100.0,
        'dinner': 900.0,
        'snack': 400.0,
      }; // sums to 3200 > goal
      expect(budget('dinner', logged), 0.0);
    });

    test('all meals logged, regenerating one gets the whole remainder', () {
      // Every meal has food but the day is under goal by 298; regenerating
      // dinner (its own fill set = {dinner}) claims the full remainder.
      final logged = {
        'breakfast': 700.0,
        'lunch': 1000.0,
        'dinner': 800.0,
        'snack': 300.0,
      }; // sums to 2800, remaining 298
      expect(budget('dinner', logged), closeTo(298, 1.0));
    });
  });
}
