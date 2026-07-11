/// Denylist-based dietary filter for free-text food names (USDA FDC search).
///
/// USDA `/foods/search` returns only a free-text `description` — there is no
/// structured "is-vegetarian"/"contains-pork" field. So unlike the meal
/// generator's *inclusion-tag* model ([GeneticAlgorithm._passesRestrictions],
/// where an ingredient must carry e.g. the `halal` tag), search filtering must
/// be the inverse: a **denylist** that hides results whose name matches a
/// forbidden keyword.
///
/// This *hides obvious conflicts* — it does not *certify compliance*. Halal in
/// particular has no slaughter-method data in any nutrition DB, so the Halal
/// rule means "hide pork / lard / gelatin / alcohol", nothing more.
///
/// Pure Dart, no Flutter/Firebase imports — unit-tested in
/// `test/dietary_filter_test.dart`. Keyword lists mirror the intelligence in
/// `SeedData._deriveAllergensAndCategory()`, including its guards (`milkfish`
/// is not dairy/milk, plant-milks are not dairy, `eggplant` is not egg).
class DietaryFilter {
  // Meat / poultry / seafood. Hidden for Vegetarian and Vegan.
  static const List<String> _meat = [
    'chicken', 'beef', 'pork', 'turkey', 'lamb', 'veal', 'mutton', 'goat',
    'bacon', 'ham', 'sausage', 'prosciutto', 'pepperoni', 'chorizo',
    'pancetta', 'salami', 'meatball', 'steak', 'brisket',
    'salmon', 'tuna', 'shrimp', 'prawn', 'tilapia', 'bangus', 'milkfish',
    'scad', 'sardine', 'mackerel', 'cod', 'squid', 'octopus', 'crab',
    'lobster', 'clam', 'mussel', 'oyster', 'anchovy', 'herring', 'trout',
    'liver', 'fish', 'seafood', 'gelatin',
  ];

  // Land meat only (no fish/seafood). Hidden for Pescatarian.
  static const List<String> _landMeat = [
    'chicken', 'beef', 'pork', 'turkey', 'lamb', 'veal', 'mutton', 'goat',
    'bacon', 'ham', 'sausage', 'prosciutto', 'pepperoni', 'chorizo',
    'pancetta', 'salami', 'meatball', 'steak', 'brisket', 'liver', 'gelatin',
  ];

  // Pork & alcohol — non-halal. Hidden for Halal.
  static const List<String> _haram = [
    'pork', 'bacon', 'ham', 'lard', 'gelatin', 'prosciutto', 'pepperoni',
    'chorizo', 'pancetta', 'salami',
    'wine', 'beer', 'rum', 'liquor', 'vodka', 'brandy', 'whiskey', 'whisky',
    'tequila', 'bourbon', 'cognac', 'sake', 'alcohol',
  ];

  // Pork + shellfish — non-kosher (simplified; no meat-dairy mixing check).
  static const List<String> _nonKosher = [
    'pork', 'bacon', 'ham', 'lard', 'prosciutto', 'pepperoni', 'chorizo',
    'pancetta', 'salami',
  ];

  // Dairy. Hidden for Dairy-Free and Vegan. `milk`/plant-milk guarded
  // separately in [matchesDairy].
  static const List<String> _dairyPlain = [
    'cheese', 'yogurt', 'yoghurt', 'whey', 'cream', 'butter', 'custard',
    'ghee', 'casein',
  ];

  static const List<String> _plantMilks = [
    'almond milk', 'soy milk', 'coconut milk', 'oat milk', 'rice milk',
    'cashew milk', 'pea milk',
  ];

  // Shellfish. Hidden for Kosher and Shellfish allergy.
  static const List<String> _shellfish = [
    'shrimp', 'prawn', 'crab', 'lobster', 'clam', 'mussel', 'oyster',
    'squid', 'octopus', 'scallop', 'crawfish', 'crayfish', 'shellfish',
  ];

  // Tree nuts (peanuts excluded — separate allergy). Hidden for Tree Nuts allergy.
  // 'nut' catches generic names like "Mixed nuts", "Nut butter"; coconut guarded
  // at call site (not a tree nut under FDA allergen rules).
  static const List<String> _treeNuts = [
    'almond', 'walnut', 'cashew', 'pecan', 'pistachio', 'macadamia',
    'hazelnut', 'brazil nut', 'pine nut', 'nut',
  ];

  // Tree nuts + peanut, treated together for Nut-free intent. Coconut is not a
  // nut here (common allergy practice); guarded at call site.
  static const List<String> _nuts = [
    'almond', 'walnut', 'cashew', 'pecan', 'pistachio', 'macadamia',
    'peanut', 'hazelnut', 'brazil nut', 'pine nut', 'nut',
  ];

  // Soy products. Hidden for Soy allergy.
  static const List<String> _soy = [
    'tofu', 'tempeh', 'edamame', 'miso', 'soy', 'soybean', 'soya',
  ];

  // Sesame products. Hidden for Sesame allergy.
  static const List<String> _sesame = ['sesame', 'tahini'];

  // Gluten-containing foods. Hidden for Gluten-Free.
  static const List<String> _gluten = [
    'wheat', 'barley', 'rye', 'bread', 'pasta', 'flour', 'noodle',
    'cracker', 'biscuit', 'cereal', 'oat', 'beer', 'malt', 'couscous',
    'pita', 'tortilla', 'pretzel', 'bagel', 'muffin', 'cake', 'cookie',
    'pastry', 'donut', 'waffle', 'pancake', 'semolina', 'spelt',
  ];

  // Fish (not shellfish). Hidden for Fish allergy.
  static const List<String> _fish = [
    'salmon', 'tuna', 'tilapia', 'bangus', 'milkfish', 'scad', 'sardine',
    'mackerel', 'cod', 'anchovy', 'herring', 'trout', 'fish', 'seafood',
  ];

  static bool _matchesAny(String name, List<String> keywords) =>
      keywords.any(name.contains);

  /// Dairy match with the `milkfish`/plant-milk guards from seed derivation.
  /// Public so [IngredientConverter.deriveAllergens] shares the same
  /// intelligence. Expects a lowercased name.
  static bool matchesDairy(String name) {
    if (_matchesAny(name, _dairyPlain)) return true;
    final isPlantMilk = _matchesAny(name, _plantMilks);
    return name.contains('milk') &&
        !name.contains('milkfish') &&
        !isPlantMilk;
  }

  /// Tree-nut/peanut match (same list the Nut-free rule uses). Expects a
  /// lowercased name.
  static bool matchesNuts(String name) => _matchesAny(name, _nuts);

  /// Egg match, guarded against `eggplant`.
  static bool _matchesEgg(String name) =>
      name.contains('egg') && !name.contains('eggplant');

  /// Returns true if [foodName] violates ANY of the given [restrictions].
  ///
  /// Diet styles (high-protein/low-carb/keto/paleo/balanced) and any
  /// unrecognized value are ignored — they reshape macro targets, not food pools.
  static bool violates(String foodName, List<String> restrictions) {
    if (restrictions.isEmpty) return false;
    final name = foodName.toLowerCase();
    for (final raw in restrictions) {
      switch (raw.toLowerCase().trim()) {
        case 'vegetarian':
          if (_matchesAny(name, _meat)) return true;
          break;
        case 'vegan':
          if (_matchesAny(name, _meat) ||
              matchesDairy(name) ||
              _matchesEgg(name) ||
              name.contains('honey')) {
            return true;
          }
          break;
        case 'pescatarian':
          if (_matchesAny(name, _landMeat)) return true;
          break;
        case 'halal':
          if (_matchesAny(name, _haram)) return true;
          break;
        case 'kosher':
          if (_matchesAny(name, _nonKosher) || _matchesAny(name, _shellfish)) {
            return true;
          }
          break;
        case 'gluten-free':
          if (_matchesAny(name, _gluten)) return true;
          break;
        case 'lactose-intolerant':
        case 'dairy-free':
          if (matchesDairy(name)) return true;
          break;
        case 'nut-free':
          if (_matchesAny(name, _nuts) && !name.contains('coconut')) return true;
          break;
        // macro styles / paleo / keto / low carb / unknown → no name filtering
      }
    }
    return false;
  }

  /// Returns true if [foodName] violates ANY of the given [allergies].
  static bool violatesAllergies(String foodName, List<String> allergies) {
    if (allergies.isEmpty) return false;
    final name = foodName.toLowerCase();
    for (final raw in allergies) {
      switch (raw.toLowerCase().trim()) {
        case 'peanuts':
          if (name.contains('peanut')) return true;
          break;
        case 'tree nuts':
          if (_matchesAny(name, _treeNuts) && !name.contains('coconut')) return true;
          break;
        case 'eggs':
          if (_matchesEgg(name)) return true;
          break;
        case 'soy':
          if (_matchesAny(name, _soy)) return true;
          break;
        case 'fish':
          if (_matchesAny(name, _fish)) return true;
          break;
        case 'shellfish':
          if (_matchesAny(name, _shellfish)) return true;
          break;
        case 'sesame':
          if (_matchesAny(name, _sesame)) return true;
          break;
      }
    }
    return false;
  }

  /// Returns only the items whose name passes all [restrictions] and [allergies].
  static List<T> filter<T>(
    List<T> items,
    List<String> restrictions,
    String Function(T) nameOf, {
    List<String> allergies = const [],
  }) {
    if (restrictions.isEmpty && allergies.isEmpty) return items;
    return items
        .where((e) {
          final name = nameOf(e);
          return !violates(name, restrictions) &&
              !violatesAllergies(name, allergies);
        })
        .toList();
  }
}
