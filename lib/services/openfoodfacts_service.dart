import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/food_item.dart';
import '../app_clock.dart';

class OpenFoodFactsService {
  static const String _baseUrl = 'https://world.openfoodfacts.org/api/v2';

  /// Fetch product by barcode
  Future<Map<String, dynamic>?> getProductByBarcode(String barcode) async {
    try {
      final url = Uri.parse('$_baseUrl/product/$barcode.json');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 1) return data['product'];
      }
      return null;
    } catch (e) {
      print('Error fetching product: $e');
      return null;
    }
  }

  /// Convert Open Food Facts product to FoodItem
  FoodItem? parseProductToFoodItem({
    required Map<String, dynamic> product,
    required String userId,
    required String barcode,
    String mealType = 'snack',
  }) {
    try {
      final name =
          product['product_name'] ??
          product['product_name_en'] ??
          'Unknown Product';

      final nutriments = product['nutriments'] as Map<String, dynamic>? ?? {};

      // Helper: read _100g key first, then bare key, default 0
      double n(String key) =>
          ((nutriments['${key}_100g'] ?? nutriments[key] ?? 0) as num)
              .toDouble();

      final servingSize = (product['serving_quantity'] ?? 100).toDouble();
      final servingSizeUnit = product['serving_quantity_unit'] ?? 'g';
      final m = servingSize / 100.0; // per-serving multiplier

      return FoodItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: userId,
        name: name,
        barcode: barcode,
        servingSize: servingSize,
        servingSizeUnit: servingSizeUnit,
        // Macros (scaled to serving)
        calories: (n('energy-kcal')) * m,
        protein: n('proteins') * m,
        carbs: n('carbohydrates') * m,
        fat: n('fat') * m,
        fiber: n('fiber') * m,
        sugar: n('sugars') * m,
        sodium: n('sodium') * 1000 * m, // OFF stores sodium in g, convert to mg
        // Vitamins (scaled to serving)
        vitaminA: n('vitamin-a') * m,
        vitaminC: n('vitamin-c') * m,
        vitaminD: n('vitamin-d') * m,
        vitaminE: n('vitamin-e') * m,
        vitaminK: n('vitamin-k') * m,
        vitaminB6: n('vitamin-b6') * m,
        vitaminB12: n('vitamin-b12') * m,
        folate: n('folate') * m,
        // Minerals (scaled to serving)
        iron: n('iron') * 1000 * m, // OFF in g → mg
        calcium: n('calcium') * 1000 * m, // OFF in g → mg
        magnesium: n('magnesium') * 1000 * m,
        potassium: n('potassium') * 1000 * m,
        zinc: n('zinc') * 1000 * m,
        phosphorus: n('phosphorus') * 1000 * m,
        loggedAt: appNow(),
        mealType: mealType,
        quantity: 1.0,
      );
    } catch (e) {
      print('Error parsing product: $e');
      return null;
    }
  }

  /// Get product image URL
  String? getProductImageUrl(Map<String, dynamic> product) {
    return product['image_front_url'] ??
        product['image_url'] ??
        product['image_front_small_url'];
  }
}
