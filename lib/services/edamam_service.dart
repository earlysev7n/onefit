import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/edamam_recipe.dart';

class EdamamService {
  // Register free at developer.edamam.com → Recipe Search API
  // Add your own keys here or load from environment
  static const _appId = '1d4b0e1d';
  static const _appKey = 'efab9f7189efaf76423e7102e116985d';
  static const _base = 'https://api.edamam.com/api/recipes/v2';

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Fetch recipe candidates for a meal type, filtered by user preferences.
  Future<List<EdamamRecipe>> fetchRecipes({
    required String mealType,
    required int targetCalories,
    List<String> dietaryRestrictions = const [],
    String? cuisine,
    int count = 10,
  }) async {
    final calMin = (targetCalories * 0.75).round();
    final calMax = (targetCalories * 1.25).round();

    final params = <String, String>{
      'type': 'public',
      'q': _buildQuery(mealType, cuisine),
      'app_id': _appId,
      'app_key': _appKey,
      'mealType': _toEdamamMealType(mealType),
      'calories': '$calMin-$calMax',
      'to': '$count',
      'random': 'true',
      'field': 'uri,label,image,url,yield,ingredientLines,totalNutrients',
    };

    // Add diet label
    final dietLabel = _toDietLabel(dietaryRestrictions);
    if (dietLabel != null) params['diet'] = dietLabel;

    // Build URI manually so repeated 'health' params are preserved
    // (Uri.replace collapses duplicate keys — we need ?health=x&health=y)
    final healthLabels = _toHealthLabels(dietaryRestrictions);
    final baseUri = Uri.parse(_base).replace(queryParameters: params);
    final healthQuery = healthLabels.map((h) => 'health=${Uri.encodeComponent(h)}').join('&');
    final fullUrl = healthLabels.isEmpty
        ? baseUri.toString()
        : '${baseUri.toString()}&$healthQuery';

    try {
      final response = await http.get(Uri.parse(fullUrl)).timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        throw Exception(
          'Edamam API key not configured. Add your app_id and app_key to EdamamService.',
        );
      }
      if (response.statusCode != 200) {
        throw Exception('Edamam API error ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final hits = json['hits'] as List? ?? [];
      return hits
          .cast<Map<String, dynamic>>()
          .map((h) => EdamamRecipe.fromJson(h))
          .where((r) => r.calories > 0)
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch meals: $e');
    }
  }

  /// Score and pick the best recipe from a list for a calorie target.
  EdamamRecipe? pickBest(
    List<EdamamRecipe> candidates,
    int targetCalories,
    double proteinGoal,
  ) {
    if (candidates.isEmpty) return null;
    candidates.sort(
      (a, b) => _score(
        b,
        targetCalories,
        proteinGoal,
      ).compareTo(_score(a, targetCalories, proteinGoal)),
    );
    return candidates.first;
  }

  double _score(EdamamRecipe r, int targetCal, double proteinGoal) {
    final calErr = ((r.calories - targetCal) / targetCal).abs();
    final protErr = proteinGoal > 0
        ? ((r.protein - proteinGoal) / proteinGoal).abs()
        : 0.0;
    return 100 - (calErr * 40) - (protErr * 35);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _buildQuery(String mealType, String? cuisine) {
    final base = switch (mealType) {
      'breakfast' => 'breakfast',
      'lunch' => 'lunch',
      'dinner' => 'dinner',
      _ => 'snack',
    };
    if (cuisine == null || cuisine == 'any') return base;
    return '$cuisine $base';
  }

  String _toEdamamMealType(String mealType) => switch (mealType) {
    'breakfast' => 'Breakfast',
    'lunch' => 'Lunch',
    'dinner' => 'Dinner',
    _ => 'Snack',
  };

  List<String> _toHealthLabels(List<String> restrictions) {
    const map = {
      'halal': 'halal',
      'gluten-free': 'gluten-free',
      'vegan': 'vegan',
      'vegetarian': 'vegetarian',
      'keto': 'keto-friendly',
      'paleo': 'paleo',
      'dairy-free': 'dairy-free',
      'lactose-intolerant': 'dairy-free',
      'nut-free': 'tree-nut-free',
      'egg-free': 'egg-free',
      'soy-free': 'soy-free',
      'pescatarian': 'pescatarian',
    };
    return restrictions
        .map((r) => map[r.toLowerCase()])
        .whereType<String>()
        .toList();
  }

  String? _toDietLabel(List<String> restrictions) {
    final lower = restrictions.map((r) => r.toLowerCase()).toSet();
    if (lower.contains('keto') || lower.contains('low-carb')) return 'low-carb';
    if (lower.contains('high-protein')) return 'high-protein';
    if (lower.contains('mediterranean')) return 'balanced';
    if (lower.contains('diabetic-friendly')) return 'low-sugar';
    return null;
  }
}
