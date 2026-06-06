import 'dart:math';
import '../models/meal_ingredient.dart';
import '../models/user_profile.dart';

class GeneticAlgorithm {
  final Random _random = Random();

  static const int populationSize = 20;
  static const int generations = 100;
  static const double mutationRate = 0.15;
  static const int tournamentSize = 4;

  static const double breakfastRatio = 0.25;
  static const double lunchRatio = 0.35;
  static const double dinnerRatio = 0.30;
  static const double snackRatio = 0.10;

  // BLACKLISTS
  // condiments/seasonings only
  static const List<String> _condiments = [
    'vinegar',
    'soy sauce',
    'fish sauce',
    'patis',
    'ginger',
    'garlic',
    'coconut oil',
    'olive oil',
    'honey',
    'hot sauce',
    'lemon juice',
    'lemon',
    'salt',
    'pepper',
    'fish sauce',
  ];

  bool _isCondiment(MealIngredient i) =>
      _condiments.any((c) => i.name.toLowerCase().contains(c));

  bool _isSnackAppropriate(MealIngredient ing) {
    final name = ing.name.toLowerCase();

    // Strict match
    bool matchesAny(List<String> list) => list.any(
      (term) =>
          name == term || name.startsWith('$term ') || name.contains(' $term'),
    );

    return matchesAny([
          'banana',
          'apple',
          'mango',
          'papaya',
          'strawberry',
          'blueberry',
          'orange',
          'saba',
        ]) ||
        matchesAny([
          'yogurt',
          'cottage cheese',
          'whole milk',
          'skim milk',
          'almond milk',
          'low-fat milk',
        ]) ||
        matchesAny([
          'almond',
          'walnut',
          'peanut',
          'cashew',
          'chia seed',
          'flaxseed',
          'sunflower seed',
          'pumpkin seed',
        ]) ||
        matchesAny(['whey protein', 'protein bar', 'protein powder']) ||
        matchesAny([
          'oatmeal',
          'rolled oats',
          'oat',
          'bread',
          'pandesal',
          'rice cake',
        ]);
  }

  //  MAIN
  List<DayMealPlan> generatePlan({
    required List<MealIngredient> allIngredients,
    required UserProfile profile,
    String cuisine = 'any',
  }) {
    final filtered = _filterIngredients(allIngredients, profile, cuisine);
    final pool = filtered.isEmpty ? allIngredients : filtered;

    // Breakfast-specific pools
    final breakfastProteins = pool.where((i) {
      final n = i.name.toLowerCase();
      return n.contains('egg') ||
          n.contains('yogurt') ||
          n.contains('cottage') ||
          n.contains('whey') ||
          n == 'whole milk' ||
          n.contains('almond milk') ||
          n.contains('skim milk') ||
          (n.contains('milk') && !n.contains('fish'));
    }).toList();
    final breakfastCarbs = pool.where((i) {
      final n = i.name.toLowerCase();
      return [
        'oat',
        'bread',
        'pandesal',
        'banana',
        'saba',
        'apple',
        'mango',
        'strawberry',
        'blueberry',
        'papaya',
      ].any((b) => n.contains(b));
    }).toList();

    // Lunch/Dinner pools
    final proteins = pool
        .where((i) => i.protein >= 8 && !_isCondiment(i))
        .toList();
    final carbs = pool
        .where((i) => i.carbs >= 15 && i.protein < 8 && !_isCondiment(i))
        .toList();
    final veggies = pool
        .where((i) => i.calories <= 60 && i.carbs < 15 && !_isCondiment(i))
        .toList();
    final fats = pool
        .where((i) => i.fat >= 8 && i.carbs < 10 && !_isCondiment(i))
        .toList();

    // Snack pool
    final snackPool = allIngredients.where((i) => _isSnackAppropriate(i)).where(
      (i) {
        for (final r in profile.dietaryRestrictions) {
          if (!i.dietaryTags
              .map((t) => t.toLowerCase())
              .contains(r.toLowerCase()))
            return false;
        }
        return true;
      },
    ).toList();

    // Fallbacks
    if (breakfastProteins.isEmpty)
      breakfastProteins.addAll(proteins.take(3).toList());
    if (breakfastCarbs.isEmpty) breakfastCarbs.addAll(carbs.take(3).toList());
    if (proteins.isEmpty) proteins.addAll(pool.take(5).toList());
    if (carbs.isEmpty) carbs.addAll(pool.take(5).toList());
    if (veggies.isEmpty) veggies.addAll(pool.take(5).toList());

    var population = List.generate(
      populationSize,
      (_) => _randomChromosome(
        breakfastProteins,
        breakfastCarbs,
        proteins,
        carbs,
        veggies,
        fats,
        snackPool,
        profile,
      ),
    );

    for (int gen = 0; gen < generations; gen++) {
      final scored =
          population
              .map((plan) => MapEntry(plan, _fitness(plan, profile)))
              .toList()
            ..sort((a, b) => b.value.compareTo(a.value));

      final nextGen = <List<DayMealPlan>>[scored[0].key, scored[1].key];
      while (nextGen.length < populationSize) {
        final p1 = _tournamentSelect(scored);
        final p2 = _tournamentSelect(scored);
        var child = _crossover(p1, p2);
        child = _mutate(
          child,
          breakfastProteins,
          breakfastCarbs,
          proteins,
          carbs,
          veggies,
          fats,
          snackPool,
          profile,
        );
        nextGen.add(child);
      }
      population = nextGen;
    }

    final best =
        population
            .map((plan) => MapEntry(plan, _fitness(plan, profile)))
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return _normalizePlan(best.first.key, profile);
  }

  // NORMALIZATION
  List<DayMealPlan> _normalizePlan(
    List<DayMealPlan> plan,
    UserProfile profile,
  ) {
    final target = profile.calorieGoal.toDouble();
    return plan.map((day) {
      var breakfast = day.breakfast.scaleToCalories(target * breakfastRatio);
      var lunch = day.lunch.scaleToCalories(target * lunchRatio);
      var dinner = day.dinner.scaleToCalories(target * dinnerRatio);
      var snack = day.snack.scaleToCalories(target * snackRatio);

      // Fine-tune: adjust dinner's first item to close remaining gap
      final total =
          breakfast.totalCalories +
          lunch.totalCalories +
          dinner.totalCalories +
          snack.totalCalories;
      final diff = target - total;

      if (dinner.items.isNotEmpty && diff.abs() > 5) {
        final item = dinner.items.first;
        if (item.ingredient.calories > 0) {
          final gramsNeeded = (diff / item.ingredient.calories) * 100;
          final newGrams = (item.portionGrams + gramsNeeded).clamp(30.0, 400.0);
          final adjustedItems = List<MealItem>.from(dinner.items);
          adjustedItems[0] = item.copyWith(portionGrams: newGrams);
          dinner = Meal(mealType: 'dinner', items: adjustedItems);
        }
      }

      return DayMealPlan(
        dayName: day.dayName,
        breakfast: breakfast,
        lunch: lunch,
        dinner: dinner,
        snack: snack,
      );
    }).toList();
  }

  // FITNESS
  double _fitness(List<DayMealPlan> plan, UserProfile profile) {
    final calorieTarget = profile.calorieGoal.toDouble();
    final proteinTarget = profile.macroGoals['protein']!.toDouble();
    final carbsTarget = profile.macroGoals['carbs']!.toDouble();
    final fatTarget = profile.macroGoals['fat']!.toDouble();

    double totalScore = 0;
    for (final day in plan) {
      // Calorie error — 40 pts
      final calErr = (day.totalCalories - calorieTarget) / calorieTarget;
      final calScore = max(0.0, 40.0 - (calErr * calErr) * 400);

      // Protein bumped from 20 → 35 pts; tighter penalty curve
      final protErr = (day.totalProtein - proteinTarget) / proteinTarget;
      final protScore = max(0.0, 35.0 - (protErr * protErr) * 350);

      // Carbs/fat reduced to 15 pts to rebalance total
      final carbErr = (day.totalCarbs - carbsTarget) / carbsTarget;
      final carbScore = max(0.0, 15.0 - (carbErr * carbErr) * 150);

      final fatErr = (day.totalFat - fatTarget) / fatTarget;
      final fatScore = max(0.0, 15.0 - (fatErr * fatErr) * 150);

      totalScore += calScore + protScore + carbScore + fatScore;
    }
    return totalScore / plan.length;
  }

  // CHROMOSOME
  List<DayMealPlan> _randomChromosome(
    List<MealIngredient> bfProteins,
    List<MealIngredient> bfCarbs,
    List<MealIngredient> proteins,
    List<MealIngredient> carbs,
    List<MealIngredient> veggies,
    List<MealIngredient> fats,
    List<MealIngredient> snackPool,
    UserProfile profile,
  ) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days
        .map(
          (day) => DayMealPlan(
            dayName: day,
            breakfast: _randomMeal(
              'breakfast',
              bfProteins,
              bfCarbs,
              veggies,
              fats,
              profile,
            ),
            lunch: _randomMeal(
              'lunch',
              proteins,
              carbs,
              veggies,
              fats,
              profile,
            ),
            dinner: _randomMeal(
              'dinner',
              proteins,
              carbs,
              veggies,
              fats,
              profile,
            ),
            snack: _randomSnack(snackPool, profile),
          ),
        )
        .toList();
  }

  Meal _randomMeal(
    String type,
    List<MealIngredient> proteins,
    List<MealIngredient> carbs,
    List<MealIngredient> veggies,
    List<MealIngredient> fats,
    UserProfile profile,
  ) {
    final ratio = type == 'breakfast'
        ? breakfastRatio
        : type == 'lunch'
        ? lunchRatio
        : dinnerRatio;
    final targetCals = profile.calorieGoal * ratio;
    final items = <MealItem>[];

    if (proteins.isNotEmpty) {
      final ing = proteins[_random.nextInt(proteins.length)];
      items.add(
        MealItem(
          ingredient: ing,
          portionGrams: _portionFor(ing, targetCals * 0.50),
        ),
      );
    }
    if (carbs.isNotEmpty) {
      final ing = carbs[_random.nextInt(carbs.length)];
      items.add(
        MealItem(
          ingredient: ing,
          portionGrams: _portionFor(ing, targetCals * 0.35),
        ),
      );
    }
    if (veggies.isNotEmpty) {
      final ing = veggies[_random.nextInt(veggies.length)];
      items.add(
        MealItem(
          ingredient: ing,
          portionGrams: _portionFor(ing, targetCals * 0.15),
        ),
      );
    }
    // Only add fat for lunch/dinner, not breakfast
    if (type != 'breakfast' && fats.isNotEmpty && _random.nextBool()) {
      final ing = fats[_random.nextInt(fats.length)];
      items.add(MealItem(ingredient: ing, portionGrams: 15));
    }
    return Meal(mealType: type, items: items);
  }

  Meal _randomSnack(List<MealIngredient> snackPool, UserProfile profile) {
    final targetCals = profile.calorieGoal * snackRatio;
    if (snackPool.isEmpty) return Meal(mealType: 'snack', items: []);
    final ing = snackPool[_random.nextInt(snackPool.length)];
    return Meal(
      mealType: 'snack',
      items: [
        MealItem(ingredient: ing, portionGrams: _portionFor(ing, targetCals)),
      ],
    );
  }

  double _portionFor(MealIngredient ing, double targetCals) {
    if (ing.calories <= 0) return 100;
    return ((targetCals / ing.calories) * 100).clamp(30.0, 400.0);
  }

  //  SELECTION
  List<DayMealPlan> _tournamentSelect(
    List<MapEntry<List<DayMealPlan>, double>> scored,
  ) {
    final t = List.generate(
      tournamentSize,
      (_) => scored[_random.nextInt(scored.length)],
    );
    t.sort((a, b) => b.value.compareTo(a.value));
    return t.first.key;
  }

  //  CROSSOVER
  List<DayMealPlan> _crossover(List<DayMealPlan> p1, List<DayMealPlan> p2) {
    final point = _random.nextInt(7);
    return [...p1.sublist(0, point), ...p2.sublist(point)];
  }

  //  MUTATION
  List<DayMealPlan> _mutate(
    List<DayMealPlan> plan,
    List<MealIngredient> bfProteins,
    List<MealIngredient> bfCarbs,
    List<MealIngredient> proteins,
    List<MealIngredient> carbs,
    List<MealIngredient> veggies,
    List<MealIngredient> fats,
    List<MealIngredient> snackPool,
    UserProfile profile,
  ) {
    if (_random.nextDouble() > mutationRate) return plan;
    final mutated = List<DayMealPlan>.from(plan);
    final dayIdx = _random.nextInt(7);
    final day = mutated[dayIdx];
    final mealType = [
      'breakfast',
      'lunch',
      'dinner',
      'snack',
    ][_random.nextInt(4)];

    Meal newMeal;
    if (mealType == 'snack') {
      newMeal = _randomSnack(snackPool, profile);
    } else if (mealType == 'breakfast') {
      newMeal = _randomMeal(
        'breakfast',
        bfProteins,
        bfCarbs,
        veggies,
        fats,
        profile,
      );
    } else {
      newMeal = _randomMeal(mealType, proteins, carbs, veggies, fats, profile);
    }

    mutated[dayIdx] = mealType == 'breakfast'
        ? day.copyWith(breakfast: newMeal)
        : mealType == 'lunch'
        ? day.copyWith(lunch: newMeal)
        : mealType == 'dinner'
        ? day.copyWith(dinner: newMeal)
        : day.copyWith(snack: newMeal);
    return mutated;
  }

  //  HELPERS
  List<MealIngredient> _filterIngredients(
    List<MealIngredient> all,
    UserProfile profile,
    String cuisine,
  ) {
    return all.where((ing) {
      if (_isCondiment(ing)) return false;
      for (final r in profile.dietaryRestrictions) {
        if (!ing.dietaryTags
            .map((t) => t.toLowerCase())
            .contains(r.toLowerCase()))
          return false;
      }
      if (cuisine != 'any')
        return ing.cuisine == cuisine || ing.cuisine == 'universal';
      return true;
    }).toList();
  }
}
