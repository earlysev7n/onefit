class EdamamRecipe {
  final String id;
  final String label;
  final String imageUrl;
  final String sourceUrl;
  final List<String> ingredientLines;
  final double servings;
  // Macros (per serving)
  final double calories;
  final double protein;
  final double fat;
  final double carbs;
  final double fiber;
  final double sugar;
  final double sodium;
  // Vitamins (per serving)
  final double vitaminA;
  final double vitaminC;
  final double vitaminD;
  final double vitaminE;
  final double vitaminK;
  final double vitaminB6;
  final double vitaminB12;
  final double folate;
  // Minerals (per serving)
  final double calcium;
  final double iron;
  final double magnesium;
  final double potassium;
  final double zinc;
  final double phosphorus;

  const EdamamRecipe({
    required this.id,
    required this.label,
    required this.imageUrl,
    required this.sourceUrl,
    required this.ingredientLines,
    required this.servings,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.fiber,
    required this.sugar,
    required this.sodium,
    required this.vitaminA,
    required this.vitaminC,
    required this.vitaminD,
    required this.vitaminE,
    required this.vitaminK,
    required this.vitaminB6,
    required this.vitaminB12,
    required this.folate,
    required this.calcium,
    required this.iron,
    required this.magnesium,
    required this.potassium,
    required this.zinc,
    required this.phosphorus,
  });

  factory EdamamRecipe.fromJson(Map<String, dynamic> json) {
    final recipe = json['recipe'] as Map<String, dynamic>? ?? json;
    final servings = (recipe['yield'] as num?)?.toDouble() ?? 1.0;

    double _n(String code) {
      final nutrients = recipe['totalNutrients'] as Map<String, dynamic>? ?? {};
      final entry = nutrients[code] as Map<String, dynamic>?;
      if (entry == null) return 0.0;
      return ((entry['quantity'] as num?)?.toDouble() ?? 0.0) / servings;
    }

    // Extract a stable ID from the URI
    final uri = recipe['uri'] as String? ?? '';
    final id = uri.contains('#recipe_') ? uri.split('#recipe_').last : uri.hashCode.toString();

    return EdamamRecipe(
      id: id,
      label: recipe['label'] as String? ?? 'Unknown Recipe',
      imageUrl: recipe['image'] as String? ?? '',
      sourceUrl: recipe['url'] as String? ?? '',
      ingredientLines: List<String>.from(recipe['ingredientLines'] ?? []),
      servings: servings,
      calories: _n('ENERC_KCAL'),
      protein: _n('PROCNT'),
      fat: _n('FAT'),
      carbs: _n('CHOCDF'),
      fiber: _n('FIBTG'),
      sugar: _n('SUGAR'),
      sodium: _n('NA'),
      vitaminA: _n('VITA_RAE'),
      vitaminC: _n('VITC'),
      vitaminD: _n('VITD'),
      vitaminE: _n('TOCPHA'),
      vitaminK: _n('VITK1'),
      vitaminB6: _n('VITB6A'),
      vitaminB12: _n('VITB12'),
      folate: _n('FOLDFE'),
      calcium: _n('CA'),
      iron: _n('FE'),
      magnesium: _n('MG'),
      potassium: _n('K'),
      zinc: _n('ZN'),
      phosphorus: _n('P'),
    );
  }
}
