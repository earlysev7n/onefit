import 'dart:math';
import '../models/meal_ingredient.dart';
import '../models/user_profile.dart';

class GeneticAlgorithm {
  final Random _random;

  /// [random] is injectable for reproducible tests; defaults to a fresh RNG.
  GeneticAlgorithm({Random? random}) : _random = random ?? Random();

  static const int populationSize = 20;
  static const int generations = 100;

  /// Generations for the per-meal evolutionary path ([evolveMeal]). A single
  /// meal is a much smaller search space than a 7-day plan, so it converges
  /// well before the full [generations].
  static const int mealGenerations = 60;
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

  // ── Dietary restriction model ──────────────────────────────────────────────
  // Restrictions fall into three kinds; only the first two filter the pool.
  //
  //  1. Inclusion tags  — the ingredient MUST carry the matching dietaryTag.
  //  2. Exclusion allergens — the ingredient MUST NOT carry the mapped allergen.
  //  3. Macro styles  — do not filter the pool; they reshape macro targets
  //     (see [_macroTargetsFor]).

  /// Restrictions satisfied by a positive `dietaryTags` entry. `gluten-free` is
  /// kept for backward-compatibility with profiles saved before the trim.
  static const Set<String> _inclusionTags = {
    'vegetarian',
    'vegan',
    'halal',
    'gluten-free',
  };

  /// Restriction → allergen that must be absent from `ingredient.allergens`.
  static const Map<String, String> _exclusionAllergens = {
    'lactose-intolerant': 'dairy',
    'dairy-free': 'dairy',
    'nut-free': 'nuts',
  };

  /// Diet-style restrictions that reshape macro targets instead of filtering.
  static const Set<String> _macroStyles = {
    'high-protein',
    'low-carb',
    'balanced',
  };

  /// True when [ing] satisfies every dietary restriction on [profile]. Inclusion
  /// tags require the tag; exclusion allergens reject the allergen; macro styles
  /// and unrecognised values have no pool effect.
  bool _passesRestrictions(MealIngredient ing, UserProfile profile) {
    final tags = ing.dietaryTags.map((t) => t.toLowerCase()).toSet();
    final allergens = ing.allergens.map((a) => a.toLowerCase()).toSet();
    for (final raw in profile.dietaryRestrictions) {
      final r = raw.toLowerCase();
      if (_inclusionTags.contains(r)) {
        if (!tags.contains(r)) return false;
      } else if (_exclusionAllergens.containsKey(r)) {
        if (allergens.contains(_exclusionAllergens[r])) return false;
      }
      // macro styles / unknown → no filtering
    }
    return true;
  }

  /// Public, side-effect-free accessor for the diet-style-aware daily macro gram
  /// targets — used by the meal-completion UI to compute remaining budgets
  /// consistently with how the GA itself scores macros.
  Map<String, double> macroTargetsFor(UserProfile profile) =>
      _macroTargetsFor(profile);

  /// Macro gram targets for the fitness function. A selected diet style overrides
  /// the `fitnessGoal`-derived split; otherwise (Balanced / none) the profile's
  /// own `macroGoals` are used unchanged.
  Map<String, double> _macroTargetsFor(UserProfile profile) {
    final styles = profile.dietaryRestrictions
        .map((e) => e.toLowerCase())
        .where(_macroStyles.contains)
        .toSet();
    final kcal = profile.calorieGoal.toDouble();
    double? p, c, f; // ratios of total calories
    if (styles.contains('high-protein')) {
      p = 0.40;
      c = 0.35;
      f = 0.25;
    } else if (styles.contains('low-carb')) {
      p = 0.35;
      c = 0.20;
      f = 0.45;
    }
    if (p == null) {
      // Balanced or no style → keep the fitnessGoal-derived targets.
      return {
        'protein': profile.macroGoals['protein']!.toDouble(),
        'carbs': profile.macroGoals['carbs']!.toDouble(),
        'fat': profile.macroGoals['fat']!.toDouble(),
      };
    }
    return {
      'protein': kcal * p / 4,
      'carbs': kcal * c! / 4,
      'fat': kcal * f! / 9,
    };
  }

  /// Macro targets for the current [generatePlan] run; set at the top of it.
  Map<String, double> _macroTargets = const {
    'protein': 0,
    'carbs': 0,
    'fat': 0,
  };

  bool _isSnackAppropriate(MealIngredient ing) {
    // Category is the robust primary signal; fruit and dairy are always
    // snack-appropriate. The name checks below cover nuts/seeds, grains and
    // protein supplements that share other categories.
    if (ing.category == 'fruit' || ing.category == 'dairy') return true;

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
    _macroTargets = _macroTargetsFor(profile);

    // Pool selection is fail-SAFE: dietary restrictions are never dropped. If
    // the cuisine narrows the pool to empty we relax the cuisine only; if even
    // that is empty, nothing satisfies the restrictions, so we return an empty
    // plan (sentinel) and let the UI warn — we never serve violating food.
    final pool = buildPool(allIngredients, profile, cuisine);
    if (pool.isEmpty) return const [];

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

    // Snack pool — drawn from the same filtered `pool`, so it honours cuisine,
    // dietary restrictions and the condiment blacklist exactly like main meals.
    final snackPool = pool.where(_isSnackAppropriate).toList();

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
      // Scale each meal to its calorie-ratio share, then close any residual the
      // per-item clamp truncated (all meals, all items — generalises the old
      // dinner-only fine-tune).
      final breakfast = day.breakfast
          .scaleToCalories(target * breakfastRatio)
          .closeResidual(target * breakfastRatio);
      final lunch = day.lunch
          .scaleToCalories(target * lunchRatio)
          .closeResidual(target * lunchRatio);
      final dinner = day.dinner
          .scaleToCalories(target * dinnerRatio)
          .closeResidual(target * dinnerRatio);
      final snack = day.snack
          .scaleToCalories(target * snackRatio)
          .closeResidual(target * snackRatio);

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
    // Macro targets honour the selected diet style (High-protein / Low-carb);
    // Balanced or none falls back to the fitnessGoal-derived split.
    final proteinTarget = _macroTargets['protein']!;
    final carbsTarget = _macroTargets['carbs']!;
    final fatTarget = _macroTargets['fat']!;

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
      if (!_passesRestrictions(ing, profile)) return false;
      if (cuisine != 'any' &&
          ing.cuisine != cuisine &&
          ing.cuisine != 'universal') {
        return false;
      }
      return true;
    }).toList();
  }

  /// Fail-safe ingredient pool: dietary restrictions are never dropped. Tries
  /// the cuisine-filtered pool first, relaxes the cuisine only if empty, and
  /// returns an empty list (sentinel) when nothing satisfies the restrictions.
  /// Shared by [generatePlan], [completeMeal], and [evolveMeal].
  List<MealIngredient> buildPool(
    List<MealIngredient> allIngredients,
    UserProfile profile,
    String cuisine,
  ) {
    // Runtime guard: drop ingredients with no calorie data (a seed-time USDA
    // fetch failure leaves an all-zero doc — see SeedData._fetchNutrition). This
    // keeps such records out of generated meals AND the manual picker until a
    // re-seed repairs them, so a meal never contains a 0-kcal item.
    final usable = allIngredients.where((i) => i.calories > 0).toList();
    final filtered = _filterIngredients(usable, profile, cuisine);
    if (filtered.isNotEmpty) return filtered;
    return _filterIngredients(usable, profile, 'any');
  }

  // ── Meal completion (budget-aware) ─────────────────────────────────────────

  /// Per-meal calorie budgets for the *additions* needed to complete today so
  /// that `logged + generated ≈ daily goal`. Pure & static for testing.
  ///
  /// `remainingDay = goal − Σ logged`; each meal's natural deficit
  /// `d_m = max(0, ratio_m·goal − logged_m)` is scaled by `remainingDay / Σd`,
  /// so the returned budgets sum to `remainingDay` and a partially-logged meal
  /// gets a proportionally smaller addition. Returns all-zero when the day is
  /// already at/over goal (never overloads).
  static Map<String, double> mealBudgets({
    required double goal,
    required Map<String, double> loggedCalsByMeal,
  }) {
    const ratios = {
      'breakfast': breakfastRatio,
      'lunch': lunchRatio,
      'dinner': dinnerRatio,
      'snack': snackRatio,
    };
    double logged(String m) => loggedCalsByMeal[m] ?? 0;
    final loggedDay = ratios.keys.fold(0.0, (s, m) => s + logged(m));
    final remainingDay = (goal - loggedDay).clamp(0.0, double.infinity);

    final deficits = <String, double>{};
    double d = 0;
    ratios.forEach((m, r) {
      final def = (r * goal - logged(m)).clamp(0.0, double.infinity);
      deficits[m] = def;
      d += def;
    });

    if (d <= 0 || remainingDay <= 0) {
      return {for (final m in ratios.keys) m: 0.0};
    }
    final factor = remainingDay / d;
    return {for (final m in ratios.keys) m: deficits[m]! * factor};
  }

  /// Generates the complementary *additions* (NOT including any already-logged
  /// food) to fill [calorieBudget] for [mealType], honouring dietary
  /// restrictions and cuisine. Slots whose food group is in [presentCategories]
  /// are dropped, so a meal that already has a protein gets a carb + fruit/veg
  /// rather than more protein. Returns an empty meal when the budget is
  /// negligible or no ingredient matches.
  Meal completeMeal({
    required List<MealIngredient> allIngredients,
    required UserProfile profile,
    required String mealType,
    required double calorieBudget,
    Set<String> presentCategories = const {},
    String cuisine = 'any',
  }) {
    if (calorieBudget <= 30) return Meal(mealType: mealType, items: const []);
    final pool = buildPool(allIngredients, profile, cuisine);
    if (pool.isEmpty) return Meal(mealType: mealType, items: const []);

    // Snack is a single complementary item from the snack-appropriate pool.
    if (mealType == 'snack') {
      var snackPool = pool.where(_isSnackAppropriate).toList();
      if (snackPool.isEmpty) snackPool = pool;
      // Avoid duplicating a food group already present, if possible.
      final fresh = snackPool
          .where((i) => !presentCategories.contains(_slotCategoryOf(i)))
          .toList();
      final candidates = fresh.isNotEmpty ? fresh : snackPool;
      final ing = candidates[_random.nextInt(candidates.length)];
      return Meal(
        mealType: mealType,
        items: [
          MealItem(ingredient: ing, portionGrams: _portionFor(ing, calorieBudget)),
        ],
      );
    }

    // Slot plan (category, weight) per meal type — mirrors _randomMeal shares.
    final slots = mealType == 'breakfast'
        ? [
            const _Slot('protein', 0.50),
            const _Slot('grain', 0.35),
            const _Slot('fruit', 0.15),
          ]
        : [
            const _Slot('protein', 0.45),
            const _Slot('grain', 0.30),
            const _Slot('vegetable', 0.15),
            const _Slot('fat', 0.10),
          ];

    // Drop slots whose food group is already logged (complement, don't repeat).
    var active =
        slots.where((s) => !presentCategories.contains(s.category)).toList();
    // Everything already present → still add one low-density item for balance.
    if (active.isEmpty) active = [const _Slot('vegetable', 1.0)];

    final totalW = active.fold(0.0, (s, x) => s + x.weight);
    final items = <MealItem>[];
    for (final slot in active) {
      final candidates = _poolForCategory(pool, slot.category);
      if (candidates.isEmpty) continue;
      final ing = candidates[_random.nextInt(candidates.length)];
      final share = slot.weight / totalW;
      items.add(
        MealItem(
          ingredient: ing,
          portionGrams: _portionFor(ing, calorieBudget * share),
        ),
      );
    }
    if (items.isEmpty) return Meal(mealType: mealType, items: const []);
    // Scale to land on the budget regardless of how many slots survived, then
    // close any residual the per-item clamp truncated during the scale-up.
    return Meal(mealType: mealType, items: items)
        .scaleToCalories(calorieBudget)
        .closeResidual(calorieBudget);
  }

  // ── Evolutionary meal completion ────────────────────────────────────────────

  /// Evolves the complementary *additions* for [mealType] instead of drawing
  /// one random item per slot ([completeMeal]). Same contract: same fail-safe
  /// pool, same [presentCategories] complement rule (a hard constraint on the
  /// chromosome, never a fitness trade-off), additions-only result, and the
  /// winner passes through the same `scaleToCalories().closeResidual()`
  /// calorie enforcement — so calorie accuracy is unchanged while macro fit
  /// becomes the best of ~populationSize×mealGenerations evaluated candidates
  /// rather than a single draw.
  ///
  /// Chromosome = one ingredient per open slot. Population is seeded with one
  /// greedy density-based pick (faster convergence); evolution uses the GA's
  /// standard operators: tournament selection (size [tournamentSize]),
  /// single-point crossover across slots, and [mutationRate] same-category
  /// swap mutation, with top-2 elitism.
  ///
  /// [avoidIds] applies a small fitness penalty per ingredient already used in
  /// another meal today (variety across a generated day); it never excludes
  /// anything outright. The returned [MealEvolutionResult.fitnessTrace] is the
  /// best fitness per generation — evidence of convergence for tests/thesis.
  MealEvolutionResult evolveMeal({
    required List<MealIngredient> allIngredients,
    required UserProfile profile,
    required String mealType,
    required double calorieBudget,
    Set<String> presentCategories = const {},
    String cuisine = 'any',
    Set<String> avoidIds = const {},
  }) {
    final empty = MealEvolutionResult(
      Meal(mealType: mealType, items: const []),
      const [],
    );
    if (calorieBudget <= 30) return empty;
    final pool = buildPool(allIngredients, profile, cuisine);
    if (pool.isEmpty) return empty;

    // Slot plan — identical to completeMeal's, with the complement rule
    // applied as a hard constraint before evolution begins.
    List<_Slot> slots;
    List<List<MealIngredient>> candidates;
    if (mealType == 'snack') {
      var snackPool = pool.where(_isSnackAppropriate).toList();
      if (snackPool.isEmpty) snackPool = pool;
      final fresh = snackPool
          .where((i) => !presentCategories.contains(_slotCategoryOf(i)))
          .toList();
      slots = const [_Slot('snack', 1.0)];
      candidates = [fresh.isNotEmpty ? fresh : snackPool];
    } else {
      final defs = mealType == 'breakfast'
          ? [
              const _Slot('protein', 0.50),
              const _Slot('grain', 0.35),
              const _Slot('fruit', 0.15),
            ]
          : [
              const _Slot('protein', 0.45),
              const _Slot('grain', 0.30),
              const _Slot('vegetable', 0.15),
              const _Slot('fat', 0.10),
            ];
      var active =
          defs.where((s) => !presentCategories.contains(s.category)).toList();
      if (active.isEmpty) active = [const _Slot('vegetable', 1.0)];
      slots = active;
      candidates = [
        for (final s in slots) _poolForCategory(pool, s.category),
      ];
      // A slot with no candidates at all (bare pool) is dropped, same as
      // completeMeal's `continue`.
      final kept = <_Slot>[];
      final keptCands = <List<MealIngredient>>[];
      for (int i = 0; i < slots.length; i++) {
        if (candidates[i].isNotEmpty) {
          kept.add(slots[i]);
          keptCands.add(candidates[i]);
        }
      }
      if (kept.isEmpty) return empty;
      slots = kept;
      candidates = keptCands;
    }

    final totalW = slots.fold(0.0, (s, x) => s + x.weight);
    final targets = _mealShareTargets(profile, calorieBudget);

    Meal build(List<MealIngredient> genes) {
      final items = <MealItem>[];
      for (int i = 0; i < slots.length; i++) {
        items.add(
          MealItem(
            ingredient: genes[i],
            portionGrams: _portionFor(
              genes[i],
              calorieBudget * slots[i].weight / totalW,
            ),
          ),
        );
      }
      return Meal(mealType: mealType, items: items)
          .scaleToCalories(calorieBudget);
    }

    double fitness(List<MealIngredient> genes) =>
        _mealFitness(build(genes), targets, calorieBudget, avoidIds);

    List<MealIngredient> randomGenes() => [
      for (final c in candidates) c[_random.nextInt(c.length)],
    ];

    // Seed: greedy per-slot pick by the slot's dominant-macro density — a good
    // starting individual that speeds convergence without constraining it.
    final seed = <MealIngredient>[
      for (int i = 0; i < slots.length; i++)
        _densestForSlot(candidates[i], slots[i].category),
    ];

    var population = <List<MealIngredient>>[
      seed,
      for (int i = 1; i < populationSize; i++) randomGenes(),
    ];
    final trace = <double>[];

    for (int gen = 0; gen < mealGenerations; gen++) {
      final scored =
          population.map((g) => MapEntry(g, fitness(g))).toList()
            ..sort((a, b) => b.value.compareTo(a.value));
      trace.add(scored.first.value);

      final nextGen = <List<MealIngredient>>[scored[0].key, scored[1].key];
      while (nextGen.length < populationSize) {
        final p1 = _tournamentGenes(scored);
        final p2 = _tournamentGenes(scored);
        var child = _crossoverGenes(p1, p2);
        if (_random.nextDouble() < mutationRate) {
          final slot = _random.nextInt(child.length);
          child = List<MealIngredient>.from(child)
            ..[slot] =
                candidates[slot][_random.nextInt(candidates[slot].length)];
        }
        nextGen.add(child);
      }
      population = nextGen;
    }

    final best =
        population.map((g) => MapEntry(g, fitness(g))).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final meal = build(best.first.key).closeResidual(calorieBudget);
    return MealEvolutionResult(meal, trace);
  }

  /// Meal-level macro gram targets: the day's diet-style-aware targets scaled
  /// to this meal's calorie share, so the ratios hold regardless of which
  /// goal (base or carry-adjusted) produced the budget.
  Map<String, double> _mealShareTargets(
    UserProfile profile,
    double calorieBudget,
  ) {
    final daily = _macroTargetsFor(profile);
    final macroCals =
        daily['protein']! * 4 + daily['carbs']! * 4 + daily['fat']! * 9;
    final share = macroCals > 0 ? calorieBudget / macroCals : 0.0;
    return {
      'protein': daily['protein']! * share,
      'carbs': daily['carbs']! * share,
      'fat': daily['fat']! * share,
    };
  }

  /// The exclusion arm of [_passesRestrictions] alone: true when none of the
  /// profile's restrictions maps to an allergen carried by [ing]. Used by
  /// [optimizeMealPortions], where inclusion tags cannot apply (user-picked
  /// foods carry no `dietaryTags`).
  bool _passesAllergens(MealIngredient ing, UserProfile profile) {
    final allergens = ing.allergens.map((a) => a.toLowerCase()).toSet();
    for (final raw in profile.dietaryRestrictions) {
      final mapped = _exclusionAllergens[raw.toLowerCase()];
      if (mapped != null && allergens.contains(mapped)) return false;
    }
    return true;
  }

  // ── Portion optimization over a fixed ingredient set (Option A) ───────────

  /// Meal Planning Option A ("Use Available Ingredients"): the user has fixed
  /// the ingredient SET; the GA determines all GRAMS. Chromosome = gram
  /// vector, one gene per ingredient clamped to 30–400 g — no subset
  /// selection, every usable ingredient appears in the result exactly once.
  ///
  /// Evolution uses the GA's standard operators: tournament selection (size
  /// [tournamentSize]), single-point crossover across genes, and
  /// [mutationRate] single-gene jitter mutation (×0.6–1.4, re-clamped), with
  /// top-2 elitism, over [mealGenerations] generations. Fitness is
  /// [_mealFitness] (40 cal / 35 protein / 15 carb / 15 fat) against
  /// [calorieBudget] + [_mealShareTargets]; the winner passes through the
  /// same `scaleToCalories().closeResidual()` calorie enforcement as every
  /// other meal path.
  ///
  /// Dietary restrictions: picked foods carry no `dietaryTags`, so inclusion
  /// tags are NOT required here — name-level screening happens upstream (the
  /// picker hides/rejects conflicting foods and the caller pre-screens with
  /// `DietaryFilter.violates`). Allergen EXCLUSIONS still apply: ingredients
  /// whose derived `allergens` conflict with the profile are dropped, as are
  /// zero-kcal records (same guard as [buildPool]). If nothing usable
  /// remains, the empty-meal sentinel is returned — restrictions are never
  /// relaxed.
  MealEvolutionResult optimizeMealPortions({
    required List<MealIngredient> ingredients,
    required UserProfile profile,
    required String mealType,
    required double calorieBudget,
  }) {
    final empty = MealEvolutionResult(
      Meal(mealType: mealType, items: const []),
      const [],
    );
    if (calorieBudget <= 30) return empty;
    final usable = ingredients
        .where((i) => i.calories > 0 && _passesAllergens(i, profile))
        .toList();
    if (usable.isEmpty) return empty;

    final targets = _mealShareTargets(profile, calorieBudget);
    final n = usable.length;

    Meal build(List<double> grams) => Meal(
      mealType: mealType,
      items: [
        for (int i = 0; i < n; i++)
          MealItem(ingredient: usable[i], portionGrams: grams[i]),
      ],
    );

    double fitness(List<double> grams) =>
        _mealFitness(build(grams), targets, calorieBudget, const {});

    // Seed: an even calorie split via _portionFor (the greedy baseline);
    // the rest of the population is random uniform in the gram clamp range.
    final seed = [for (final ing in usable) _portionFor(ing, calorieBudget / n)];
    List<double> randomGenes() => [
      for (int i = 0; i < n; i++) 30.0 + _random.nextDouble() * 370.0,
    ];

    var population = <List<double>>[
      seed,
      for (int i = 1; i < populationSize; i++) randomGenes(),
    ];
    final trace = <double>[];

    for (int gen = 0; gen < mealGenerations; gen++) {
      final scored =
          population.map((g) => MapEntry(g, fitness(g))).toList()
            ..sort((a, b) => b.value.compareTo(a.value));
      trace.add(scored.first.value);

      final nextGen = <List<double>>[scored[0].key, scored[1].key];
      while (nextGen.length < populationSize) {
        final p1 = _tournamentGrams(scored);
        final p2 = _tournamentGrams(scored);
        var child = _crossoverGrams(p1, p2);
        if (_random.nextDouble() < mutationRate) {
          final i = _random.nextInt(n);
          child = List<double>.from(child)
            ..[i] = (child[i] * (0.6 + _random.nextDouble() * 0.8)).clamp(
              30.0,
              400.0,
            );
        }
        nextGen.add(child);
      }
      population = nextGen;
    }

    final best =
        population.map((g) => MapEntry(g, fitness(g))).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final meal = build(
      best.first.key,
    ).scaleToCalories(calorieBudget).closeResidual(calorieBudget);
    return MealEvolutionResult(meal, trace);
  }

  List<double> _tournamentGrams(List<MapEntry<List<double>, double>> scored) {
    final t = List.generate(
      tournamentSize,
      (_) => scored[_random.nextInt(scored.length)],
    );
    t.sort((a, b) => b.value.compareTo(a.value));
    return t.first.key;
  }

  List<double> _crossoverGrams(List<double> p1, List<double> p2) {
    if (p1.length <= 1) return List<double>.from(p1);
    final point = _random.nextInt(p1.length);
    return [...p1.sublist(0, point), ...p2.sublist(point)];
  }

  /// Meal-level fitness — mirrors [_fitness]'s 40/35/15/15 weighting at meal
  /// granularity, plus a small variety penalty for [avoidIds] repeats.
  double _mealFitness(
    Meal meal,
    Map<String, double> targets,
    double budget,
    Set<String> avoidIds,
  ) {
    double score = 0;
    final calErr = (meal.totalCalories - budget) / budget;
    score += max(0.0, 40.0 - (calErr * calErr) * 400);
    final p = targets['protein']!;
    if (p > 0) {
      final e = (meal.totalProtein - p) / p;
      score += max(0.0, 35.0 - (e * e) * 350);
    }
    final c = targets['carbs']!;
    if (c > 0) {
      final e = (meal.totalCarbs - c) / c;
      score += max(0.0, 15.0 - (e * e) * 150);
    }
    final f = targets['fat']!;
    if (f > 0) {
      final e = (meal.totalFat - f) / f;
      score += max(0.0, 15.0 - (e * e) * 150);
    }
    score -=
        meal.items.where((i) => avoidIds.contains(i.ingredient.id)).length * 6;
    return score;
  }

  /// Greedy seed pick: the candidate densest in the slot's dominant macro
  /// (per kcal), or lowest-calorie for vegetable slots.
  MealIngredient _densestForSlot(
    List<MealIngredient> candidates,
    String category,
  ) {
    double density(MealIngredient i) {
      if (i.calories <= 0) return 0;
      switch (category) {
        case 'protein':
        case 'snack':
          return i.protein / i.calories;
        case 'grain':
        case 'fruit':
          return i.carbs / i.calories;
        case 'fat':
          return i.fat / i.calories;
        case 'vegetable':
          return 1 / i.calories; // lowest-density wins
      }
      return 0;
    }

    return candidates.reduce((a, b) => density(a) >= density(b) ? a : b);
  }

  List<MealIngredient> _tournamentGenes(
    List<MapEntry<List<MealIngredient>, double>> scored,
  ) {
    final t = List.generate(
      tournamentSize,
      (_) => scored[_random.nextInt(scored.length)],
    );
    t.sort((a, b) => b.value.compareTo(a.value));
    return t.first.key;
  }

  List<MealIngredient> _crossoverGenes(
    List<MealIngredient> p1,
    List<MealIngredient> p2,
  ) {
    if (p1.length <= 1) return List<MealIngredient>.from(p1);
    final point = _random.nextInt(p1.length);
    return [...p1.sublist(0, point), ...p2.sublist(point)];
  }

  /// Coarse slot group for an ingredient: protein/grain/vegetable/fruit/fat.
  /// Uses `category` first (robust), falling back to the GA's macro thresholds.
  String _slotCategoryOf(MealIngredient i) {
    switch (i.category) {
      case 'protein':
      case 'dairy':
      case 'legume':
        return 'protein';
      case 'grain':
        return 'grain';
      case 'vegetable':
        return 'vegetable';
      case 'fruit':
        return 'fruit';
      case 'fat':
        return 'fat';
    }
    if (i.protein >= 8) return 'protein';
    if (i.fat >= 8 && i.carbs < 10) return 'fat';
    if (i.carbs >= 15 && i.protein < 8) return 'grain';
    if (i.calories <= 60 && i.carbs < 15) return 'vegetable';
    return 'grain';
  }

  /// Candidate ingredients for a complementary [slotCategory], with a sensible
  /// non-empty fallback so a slot is only skipped when the whole pool is bare.
  List<MealIngredient> _poolForCategory(
    List<MealIngredient> pool,
    String slotCategory,
  ) {
    final exact =
        pool.where((i) => _slotCategoryOf(i) == slotCategory).toList();
    if (exact.isNotEmpty) return exact;
    // Fallbacks: fruit→grain (sweet carbs), vegetable→grain, else any non-condiment.
    if (slotCategory == 'fruit' || slotCategory == 'vegetable') {
      final grains = pool.where((i) => _slotCategoryOf(i) == 'grain').toList();
      if (grains.isNotEmpty) return grains;
    }
    return pool;
  }
}

/// A complementary slot in a completed meal: a food-group [category] and its
/// relative calorie [weight].
class _Slot {
  final String category;
  final double weight;
  const _Slot(this.category, this.weight);
}

/// Result of an [GeneticAlgorithm.evolveMeal] run: the winning meal plus the
/// best-fitness-per-generation trace (evidence that evolution occurred; used
/// by tests and the thesis evaluation).
class MealEvolutionResult {
  final Meal meal;
  final List<double> fitnessTrace;
  const MealEvolutionResult(this.meal, this.fitnessTrace);
}
