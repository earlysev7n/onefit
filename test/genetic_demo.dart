// Genetic Algorithm — Interactive Demo
// Run: dart run test/genetic_demo.dart

import 'dart:io';
import 'dart:math';
import 'package:onefit/algorithms/genetic_algorithm.dart';
import 'package:onefit/models/meal_ingredient.dart';
import 'package:onefit/models/user_profile.dart';

void main() {
  print('');
  print('GENETIC ALGORITHM — MEAL OPTIMISATION DEMO');
  print('');

  final calorieGoal = _number('Daily calorie goal (kcal)', 1200, 5000);

  final mealTypeDisplay = _menu('Meal type', const [
    'Breakfast (25% of daily goal)',
    'Lunch     (35% of daily goal)',
    'Dinner    (30% of daily goal)',
  ]);
  final mealType = mealTypeDisplay.startsWith('Breakfast')
      ? 'breakfast'
      : mealTypeDisplay.startsWith('Lunch')
          ? 'lunch'
          : 'dinner';
  final mealRatio = mealType == 'breakfast'
      ? 0.25
      : mealType == 'lunch'
          ? 0.35
          : 0.30;

  final dietStyle = _menu('Diet style', const [
    'Balanced      (macro split from fitness goal)',
    'High-protein  (40% P / 35% C / 25% F)',
    'Low-carb      (35% P / 20% C / 45% F)',
  ]);
  final dietTag = dietStyle.startsWith('High-protein')
      ? 'high-protein'
      : dietStyle.startsWith('Low-carb')
          ? 'low-carb'
          : '';

  final fitnessGoal = _menu('Fitness goal', const [
    'Muscle Gain', 'Weight Loss', 'Endurance', 'General Fitness',
  ]);

  // Pin calorieGoal to the user's entered value via calorieAdjustment
  final baseProfile = UserProfile(
    uid: 'demo', name: 'Demo User', gender: 'Male', age: 25,
    weight: 80.0, height: 178.0, fitnessGoal: fitnessGoal,
    experienceLevel: 'Intermediate', workoutLocation: 'Gym',
    equipment: [], dietaryRestrictions: dietTag.isEmpty ? [] : [dietTag],
    workoutDaysPerWeek: 3, sessionMinutes: 45,
    workoutSplit: 'Full Body Training', calorieAdjustment: 0,
  );
  final bias = calorieGoal - baseProfile.calorieGoal;
  final profile = baseProfile.copyWith(calorieAdjustment: bias);

  final calorieBudget = (calorieGoal * mealRatio).roundToDouble();
  final ingredients = _buildIngredients();
  final ga = GeneticAlgorithm();

  final dailyTargets = ga.macroTargetsFor(profile);
  final proteinTarget = dailyTargets['protein']! * mealRatio;
  final carbsTarget   = dailyTargets['carbs']!   * mealRatio;
  final fatTarget     = dailyTargets['fat']!      * mealRatio;

  print('');
  print('=== PROFILE ===');
  print('Fitness Goal : $fitnessGoal');
  print('Calorie Goal : $calorieGoal kcal/day');
  print('Diet Style   : ${dietTag.isEmpty ? 'Balanced' : dietTag}');
  print('Meal Type    : ${mealType[0].toUpperCase()}${mealType.substring(1)}');
  print('Meal Budget  : ${calorieBudget.toInt()} kcal  (${(mealRatio * 100).toInt()}% of $calorieGoal kcal)');

  print('');
  print('=== MACRO TARGETS FOR THIS MEAL ===');
  print('  (computed by GeneticAlgorithm.macroTargetsFor, scaled to meal ratio)');
  print('Protein : ${proteinTarget.toStringAsFixed(1)} g');
  print('Carbs   : ${carbsTarget.toStringAsFixed(1)} g');
  print('Fat     : ${fatTarget.toStringAsFixed(1)} g');

  print('');
  print('=== ALGORITHM PARAMETERS ===');
  print('Population size : ${GeneticAlgorithm.populationSize} meal chromosomes');
  print('Generations     : ${GeneticAlgorithm.mealGenerations}');
  print('Mutation rate   : ${(GeneticAlgorithm.mutationRate * 100).toInt()}%  (single-gene gram jitter x0.6-1.4, re-clamped to 30-400 g)');
  print('Tournament size : ${GeneticAlgorithm.tournamentSize}  (winner-takes-all selection)');
  print('Elitism         : top 2 individuals survive unchanged each generation');
  print('Crossover       : single-point across the ingredient-slot chromosome');

  print('');
  print('=== FITNESS FUNCTION  (max 105 pts) ===');
  print('Each macro scored independently, then summed:');
  print('  Calories : max(0, 40 - err^2 x 400)   where err = (actual - target) / target');
  print('  Protein  : max(0, 35 - err^2 x 350)');
  print('  Carbs    : max(0, 15 - err^2 x 150)');
  print('  Fat      : max(0, 15 - err^2 x 150)');
  print('  Maximum  : 40 + 35 + 15 + 15 = 105 pts');

  print('');
  print('Running 3 independent GA runs...');
  print('');

  final results = List.generate(3, (_) {
    return ga.evolveMeal(
      allIngredients: ingredients,
      profile: profile,
      mealType: mealType,
      calorieBudget: calorieBudget,
    );
  });

  final fitnessScores = results
      .map((r) => _fitness(
            r.meal.totalCalories, calorieBudget,
            r.meal.totalProtein,  proteinTarget,
            r.meal.totalCarbs,    carbsTarget,
            r.meal.totalFat,      fatTarget,
          ))
      .toList();

  print('=== TOP 3 SOLUTIONS ===');
  print('(3 independent runs — stochastic, each explores a different random search path)');
  print('');
  print('  Run  Score      Calories   Protein   Carbs    Fat     Ingredients');
  print('  ---  ---------  --------   -------   ------   ------  -----------');
  for (int i = 0; i < 3; i++) {
    final m = results[i].meal;
    final items = m.items.map((it) => it.ingredient.name.split(' ').first).join(' / ');
    print('   ${i + 1}   ${fitnessScores[i].toStringAsFixed(1).padLeft(5)} pts  '
        '${m.totalCalories.toStringAsFixed(0).padLeft(7)} kcal  '
        '${m.totalProtein.toStringAsFixed(1).padLeft(6)} g  '
        '${m.totalCarbs.toStringAsFixed(1).padLeft(5)} g  '
        '${m.totalFat.toStringAsFixed(1).padLeft(5)} g  '
        '$items');
  }

  final bestIdx = fitnessScores.indexOf(fitnessScores.reduce(max));
  final bestResult = results[bestIdx];
  final bestTrace  = bestResult.fitnessTrace;

  print('');
  print('Best run: Run ${bestIdx + 1} (${fitnessScores[bestIdx].toStringAsFixed(1)} pts)');

  print('');
  print('=== EVOLUTION TRACE (best run) ===');
  print('Generation  Fitness / 105');
  print('----------  -------------');
  final printGens = <int>{};
  for (int g = 0; g < bestTrace.length; g += 10) printGens.add(g);
  printGens.add(bestTrace.length - 1);
  for (final g in printGens.toList()..sort()) {
    print('  Gen ${g.toString().padLeft(2)}      ${bestTrace[g].toStringAsFixed(1).padLeft(5)}');
  }

  final totCal  = bestResult.meal.totalCalories;
  final totProt = bestResult.meal.totalProtein;
  final totCarb = bestResult.meal.totalCarbs;
  final totFat  = bestResult.meal.totalFat;
  final totGrams = bestResult.meal.items.fold(0.0, (s, i) => s + i.portionGrams);

  print('');
  print('=== FINAL MEAL PLAN — ${mealType[0].toUpperCase()}${mealType.substring(1)} (Run ${bestIdx + 1}) ===');
  print('');
  print('  #   Ingredient              Grams   Calories   Protein   Carbs    Fat');
  print('  --  ----------------------  -----   --------   -------   ------   -----');
  for (int i = 0; i < bestResult.meal.items.length; i++) {
    final item = bestResult.meal.items[i];
    final nm = item.ingredient.name.length > 22
        ? item.ingredient.name.substring(0, 21) + '.'
        : item.ingredient.name.padRight(22);
    print('  ${(i + 1).toString().padLeft(2)}  $nm  '
        '${item.portionGrams.toStringAsFixed(0).padLeft(5)}g  '
        '${item.calories.toStringAsFixed(1).padLeft(8)}  '
        '${item.protein.toStringAsFixed(1).padLeft(7)} g  '
        '${item.carbs.toStringAsFixed(1).padLeft(5)} g  '
        '${item.fat.toStringAsFixed(1).padLeft(4)} g');
  }
  print('  --  ----------------------  -----   --------   -------   ------   -----');
  print('  Total                       ${totGrams.toStringAsFixed(0).padLeft(5)}g  '
      '${totCal.toStringAsFixed(1).padLeft(8)}  '
      '${totProt.toStringAsFixed(1).padLeft(7)} g  '
      '${totCarb.toStringAsFixed(1).padLeft(5)} g  '
      '${totFat.toStringAsFixed(1).padLeft(4)} g');
  print('  Target                             '
      '${calorieBudget.toStringAsFixed(1).padLeft(8)}  '
      '${proteinTarget.toStringAsFixed(1).padLeft(7)} g  '
      '${carbsTarget.toStringAsFixed(1).padLeft(5)} g  '
      '${fatTarget.toStringAsFixed(1).padLeft(4)} g');

  final calErr  = (totCal  - calorieBudget) / calorieBudget;
  final protErr = (totProt - proteinTarget) / max(proteinTarget, 1);
  final carbErr = (totCarb - carbsTarget)   / max(carbsTarget,   1);
  final fatErr  = (totFat  - fatTarget)     / max(fatTarget,     1);

  final calScore  = max(0.0, 40.0 - calErr  * calErr  * 400);
  final protScore = max(0.0, 35.0 - protErr * protErr * 350);
  final carbScore = max(0.0, 15.0 - carbErr * carbErr * 150);
  final fatScore  = max(0.0, 15.0 - fatErr  * fatErr  * 150);
  final totalScore = calScore + protScore + carbScore + fatScore;

  print('');
  print('=== FITNESS SCORE BREAKDOWN ===');
  print('err = (actual - target) / target');
  print('');
  _scoreRow('Calories', calorieBudget, totCal,  calErr,  40.0, 400.0, calScore);
  _scoreRow('Protein ', proteinTarget, totProt, protErr, 35.0, 350.0, protScore);
  _scoreRow('Carbs   ', carbsTarget,   totCarb, carbErr, 15.0, 150.0, carbScore);
  _scoreRow('Fat     ', fatTarget,     totFat,  fatErr,  15.0, 150.0, fatScore);
  print('');
  print('Final score : ${totalScore.toStringAsFixed(2)} / 105.0 pts');
  print('');
}

List<MealIngredient> _buildIngredients() => [
      _ing(id: 'chicken_breast', name: 'Chicken Breast',
          cal: 165, prot: 31.0, carb: 0.0, fat: 3.6, category: 'protein'),
      _ing(id: 'eggs', name: 'Whole Eggs',
          cal: 155, prot: 13.0, carb: 1.1, fat: 11.0, category: 'protein'),
      _ing(id: 'greek_yogurt', name: 'Greek Yogurt',
          cal: 59, prot: 10.0, carb: 3.6, fat: 0.4, category: 'dairy'),
      _ing(id: 'tuna', name: 'Tuna (canned)',
          cal: 116, prot: 26.0, carb: 0.0, fat: 1.0, category: 'protein'),
      _ing(id: 'cottage_cheese', name: 'Cottage Cheese',
          cal: 98, prot: 11.0, carb: 3.4, fat: 4.3, category: 'dairy'),
      _ing(id: 'brown_rice', name: 'Brown Rice',
          cal: 123, prot: 2.7, carb: 25.8, fat: 1.0, category: 'grain'),
      _ing(id: 'oats', name: 'Rolled Oats',
          cal: 389, prot: 17.0, carb: 66.0, fat: 7.0, category: 'grain'),
      _ing(id: 'whole_wheat_bread', name: 'Whole Wheat Bread',
          cal: 247, prot: 13.0, carb: 41.0, fat: 3.4, category: 'grain'),
      _ing(id: 'quinoa', name: 'Quinoa (cooked)',
          cal: 120, prot: 4.4, carb: 21.3, fat: 1.9, category: 'grain'),
      _ing(id: 'broccoli', name: 'Broccoli',
          cal: 34, prot: 2.8, carb: 6.6, fat: 0.4, category: 'vegetable'),
      _ing(id: 'spinach', name: 'Spinach',
          cal: 23, prot: 2.9, carb: 3.6, fat: 0.4, category: 'vegetable'),
      _ing(id: 'sweet_potato', name: 'Sweet Potato',
          cal: 86, prot: 1.6, carb: 20.0, fat: 0.1, category: 'vegetable'),
      _ing(id: 'carrots', name: 'Carrots',
          cal: 41, prot: 0.9, carb: 10.0, fat: 0.2, category: 'vegetable'),
      _ing(id: 'apple', name: 'Apple',
          cal: 52, prot: 0.3, carb: 14.0, fat: 0.2, category: 'fruit'),
      _ing(id: 'banana', name: 'Banana',
          cal: 89, prot: 1.1, carb: 23.0, fat: 0.3, category: 'fruit'),
      _ing(id: 'blueberries', name: 'Blueberries',
          cal: 57, prot: 0.7, carb: 14.0, fat: 0.3, category: 'fruit'),
      _ing(id: 'olive_oil', name: 'Olive Oil',
          cal: 884, prot: 0.0, carb: 0.0, fat: 100.0, category: 'fat'),
      _ing(id: 'almonds', name: 'Almonds',
          cal: 579, prot: 21.0, carb: 22.0, fat: 50.0, category: 'fat'),
      _ing(id: 'avocado', name: 'Avocado',
          cal: 160, prot: 2.0, carb: 9.0, fat: 15.0, category: 'fat'),
      _ing(id: 'black_beans', name: 'Black Beans (cooked)',
          cal: 132, prot: 8.9, carb: 24.0, fat: 0.5, category: 'legume'),
      _ing(id: 'lentils', name: 'Lentils (cooked)',
          cal: 116, prot: 9.0, carb: 20.0, fat: 0.4, category: 'legume'),
    ];

MealIngredient _ing({
  required String id, required String name,
  required double cal, required double prot,
  required double carb, required double fat,
  required String category,
}) =>
    MealIngredient(
      id: id, name: name, calories: cal, protein: prot,
      carbs: carb, fat: fat, fiber: 0, sugar: 0, sodium: 0,
      dietaryTags: [], cuisine: 'universal', allergens: [], category: category,
    );

double _fitness(
  double cal,  double calTarget,
  double prot, double protTarget,
  double carb, double carbTarget,
  double fat,  double fatTarget,
) {
  double err(double a, double t) => t > 0 ? (a - t) / t : 0.0;
  return max(0.0, 40.0 - err(cal,  calTarget)  * err(cal,  calTarget)  * 400) +
         max(0.0, 35.0 - err(prot, protTarget) * err(prot, protTarget) * 350) +
         max(0.0, 15.0 - err(carb, carbTarget) * err(carb, carbTarget) * 150) +
         max(0.0, 15.0 - err(fat,  fatTarget)  * err(fat,  fatTarget)  * 150);
}

void _scoreRow(String label, double target, double actual, double err,
    double weight, double penalty, double score) {
  final errStr = err.abs().toStringAsFixed(4);
  print('  $label : max(0, $weight - $errStr^2 x $penalty) = ${score.toStringAsFixed(2)} pts'
      '  (target ${target.toStringAsFixed(1)}, actual ${actual.toStringAsFixed(1)})');
}

String _menu(String prompt, List<String> options) {
  print('');
  print('$prompt:');
  for (int i = 0; i < options.length; i++) {
    print('  ${i + 1}. ${options[i]}');
  }
  while (true) {
    stdout.write('Enter choice (1-${options.length}): ');
    final line = stdin.readLineSync()?.trim() ?? '';
    final n = int.tryParse(line);
    if (n != null && n >= 1 && n <= options.length) return options[n - 1];
    print('Invalid — enter a number between 1 and ${options.length}');
  }
}

int _number(String prompt, int min, int max) {
  while (true) {
    stdout.write('$prompt ($min-$max): ');
    final line = stdin.readLineSync()?.trim() ?? '';
    final n = int.tryParse(line);
    if (n != null && n >= min && n <= max) return n;
    print('Invalid — enter a number between $min and $max');
  }
}
