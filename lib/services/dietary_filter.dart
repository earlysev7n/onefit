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

  // Pork & alcohol — non-halal. Hidden for Halal.
  static const List<String> _haram = [
    'pork', 'bacon', 'ham', 'lard', 'gelatin', 'prosciutto', 'pepperoni',
    'chorizo', 'pancetta', 'salami',
    'wine', 'beer', 'rum', 'liquor', 'vodka', 'brandy', 'whiskey', 'whisky',
    'tequila', 'bourbon', 'cognac', 'sake', 'alcohol',
  ];

  // Dairy. Hidden for Lactose-intolerant and Vegan. `milk`/plant-milk guarded
  // separately in [matchesDairy].
  static const List<String> _dairyPlain = [
    'cheese', 'yogurt', 'yoghurt', 'whey', 'cream', 'butter', 'custard',
    'ghee', 'casein',
  ];

  static const List<String> _plantMilks = [
    'almond milk', 'soy milk', 'coconut milk', 'oat milk', 'rice milk',
    'cashew milk', 'pea milk',
  ];

  // Tree nuts + peanut, treated together for Nut-free intent. Coconut is not a
  // nut here (common allergy practice).
  static const List<String> _nuts = [
    'almond', 'walnut', 'cashew', 'pecan', 'pistachio', 'macadamia',
    'peanut', 'hazelnut', 'brazil nut', 'pine nut',
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
  /// Diet styles (high-protein/low-carb/balanced) and any unrecognized value
  /// are ignored — they reshape macro targets, they don't filter foods.
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
        case 'halal':
          if (_matchesAny(name, _haram)) return true;
          break;
        case 'lactose-intolerant':
        case 'dairy-free':
          if (matchesDairy(name)) return true;
          break;
        case 'nut-free':
          if (_matchesAny(name, _nuts)) return true;
          break;
        // macro styles / unknown → no filtering
      }
    }
    return false;
  }

  /// Returns only the items whose name passes all [restrictions].
  static List<T> filter<T>(
    List<T> items,
    List<String> restrictions,
    String Function(T) nameOf,
  ) {
    if (restrictions.isEmpty) return items;
    return items.where((e) => !violates(nameOf(e), restrictions)).toList();
  }
}
