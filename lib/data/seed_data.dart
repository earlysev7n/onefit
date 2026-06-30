import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Dev-only switch. Set `true` to expose the "Seed Ingredients" button on the
/// Profile screen, run it once to populate the Firestore `ingredients`
/// collection from USDA FoodData Central, then set back to `false`.
/// MUST be `false` for any build intended for real use.
const bool kShowSeedTools = false;

class SeedData {
  static const String _apiKey = 'Fte86dAfeHdSgs4PI68EdVN3LevdLEebYFiDM6fZ';
  static const String _baseUrl = 'https://api.nal.usda.gov/fdc/v1';

  static Future<void> seedAll() async {
    await seedExercises();
    await seedIngredients();
    print('Seeding complete!');
  }

  // ── USDA nutrient fetch ────────────────────────────────────────────────────

  /// Searches USDA for [query], returns a nutrition map for the top result.
  /// Returns `null` when the API fails after retries or the record carries no
  /// usable calorie value — so the caller can skip it rather than persist an
  /// all-zero record (which is what produced the "0 kcal ingredient" bug).
  static Future<Map<String, double>?> _fetchNutrition(String query) async {
    try {
      final uri = Uri.parse('$_baseUrl/foods/search').replace(
        queryParameters: {
          'query': query,
          'api_key': _apiKey,
          'pageSize': '1',
          'dataType': 'SR Legacy,Foundation,Survey (FNDDS)',
        },
      );

      // Retry with exponential backoff — the API rate-limits (HTTP 429) under
      // the ~150 rapid sequential seed calls, which previously fell straight
      // through to an all-zero record.
      http.Response? response;
      for (var attempt = 0; attempt < 3; attempt++) {
        response = await http.get(uri);
        if (response.statusCode == 200) break;
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
      if (response == null || response.statusCode != 200) {
        throw Exception('HTTP ${response?.statusCode}');
      }

      final foods = (jsonDecode(response.body)['foods'] as List?) ?? [];
      if (foods.isEmpty) throw Exception('No results for "$query"');

      final nutrients = (foods.first['foodNutrients'] as List?) ?? [];

      double getN(int id) {
        final n = nutrients.firstWhere(
          (n) => n['nutrientId'] == id || n['nutrientNumber'] == id.toString(),
          orElse: () => {},
        );
        return ((n['value'] ?? n['amount'] ?? 0) as num).toDouble();
      }

      // Energy: SR Legacy reports it as 1008 ("Energy", kcal), but Foundation
      // Foods often report it only as Atwater energy (2048 specific / 2047
      // general). Fall back so those top hits don't seed as 0 kcal.
      var calories = getN(1008);
      if (calories == 0) calories = getN(2048);
      if (calories == 0) calories = getN(2047);

      // No usable energy value → treat as a miss so the caller skips it.
      if (calories == 0) throw Exception('No calorie data for "$query"');

      return {
        'calories': calories,
        'protein': getN(1003),
        'carbs': getN(1005),
        'fat': getN(1004),
        'fiber': getN(1079),
        'sugar': getN(1063),
        'sodium': getN(1093),
        'vitaminA': getN(1106),
        'vitaminC': getN(1162),
        'vitaminD': getN(1114),
        'vitaminE': getN(1109),
        'vitaminK': getN(1185),
        'vitaminB6': getN(1175),
        'vitaminB12': getN(1178),
        'folate': getN(1177),
        'iron': getN(1089),
        'calcium': getN(1087),
        'magnesium': getN(1090),
        'potassium': getN(1092),
        'zinc': getN(1095),
        'phosphorus': getN(1091),
      };
    } catch (e) {
      print('  ⚠ USDA fetch failed for "$query": $e — skipping');
      return null;
    }
  }

  // ── Exercises ──────────────────────────────────────────────────────────────

  static Future<void> seedExercises() async {
    final db = FirebaseFirestore.instance;
    final chunks = <List<Map<String, dynamic>>>[];
    for (var i = 0; i < exercises.length; i += 400) {
      chunks.add(
        exercises.sublist(
          i,
          i + 400 > exercises.length ? exercises.length : i + 400,
        ),
      );
    }
    for (final chunk in chunks) {
      final batch = db.batch();
      for (final e in chunk) {
        batch.set(db.collection('exercises').doc(e['id'] as String), e);
      }
      await batch.commit();
    }
    print('${exercises.length} exercises seeded!');
  }

  // ── Ingredients ────────────────────────────────────────────────────────────

  /// Fetches nutrition from USDA for each ingredient, then writes to Firestore.
  /// Only the id, name, dietaryTags, and cuisine are hardcoded here —
  /// all nutrition values come live from the API.
  static Future<void> seedIngredients() async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    int count = 0;
    final failed = <String>[];

    for (final stub in _ingredientStubs) {
      print('Fetching: ${stub['name']}...');
      final nutrition = await _fetchNutrition(stub['name'] as String);

      // Throttle to stay under the USDA rate limit across ~150 calls.
      await Future.delayed(const Duration(milliseconds: 250));

      // Skip rather than write a 0-kcal record — leaves any previously-good
      // value untouched and surfaces the gap in the printed summary.
      if (nutrition == null) {
        failed.add(stub['name'] as String);
        continue;
      }

      final derived = _deriveAllergensAndCategory(stub['name'] as String);

      final doc = {
        'id': stub['id'],
        'name': stub['name'],
        'dietaryTags': stub['dietaryTags'],
        'cuisine': stub['cuisine'],
        'allergens': derived['allergens'],
        'category': derived['category'],
        ...nutrition, // calories, protein, carbs, fat + all micros
      };

      batch.set(db.collection('ingredients').doc(stub['id'] as String), doc);
      count++;

      // Firestore batches cap at 500 — flush every 400 to be safe
      if (count % 400 == 0) await batch.commit();
    }

    await batch.commit();
    print('$count ingredients seeded with live USDA nutrition!');
    if (failed.isNotEmpty) {
      print('⚠ ${failed.length} skipped (no USDA data — re-run to retry): '
          '${failed.join(', ')}');
    }
  }

  /// Derives `allergens` (for exclusion restrictions like Lactose-intolerant /
  /// Nut-free) and a coarse `category` (for robust meal-pool classification)
  /// from an ingredient name. Authoring-time only — the result is written to
  /// Firestore so the runtime Genetic Algorithm reads concrete fields, never
  /// ingredient names. `category` ∈ {protein, dairy, grain, legume, vegetable,
  /// fruit, fat, condiment, other}.
  static Map<String, dynamic> _deriveAllergensAndCategory(String rawName) {
    final n = rawName.toLowerCase();
    bool has(String s) => n.contains(s);
    bool hasAny(List<String> xs) => xs.any(n.contains);

    // ── Allergens ──
    final allergens = <String>[];
    // Plant "milks" are NOT dairy; "milkfish" is a fish, not milk.
    final isPlantMilk = hasAny([
      'almond milk',
      'soy milk',
      'coconut milk',
      'oat milk',
      'rice milk',
    ]);
    final dairy =
        hasAny(['cheese', 'yogurt', 'whey', 'cream']) ||
        (has('milk') && !has('milkfish') && !isPlantMilk);
    if (dairy) allergens.add('dairy');
    // Tree nuts + peanut (treated together for Nut-free intent). Almond milk is
    // nut-derived; coconut is not treated as a nut here (common allergy practice).
    if (hasAny([
      'almond',
      'walnut',
      'cashew',
      'pecan',
      'pistachio',
      'macadamia',
      'peanut',
    ])) {
      allergens.add('nuts');
    }

    // ── Category (first match wins) ──
    String category;
    if (hasAny(['soy sauce', 'fish sauce', 'vinegar', 'honey', 'ginger'])) {
      category = 'condiment';
    } else if (has('milk') && !has('milkfish') ||
        hasAny(['cheese', 'yogurt', 'whey', 'cream'])) {
      category = 'dairy';
    } else if (hasAny([
      'oil',
      'avocado',
      'almond',
      'walnut',
      'cashew',
      'pecan',
      'pistachio',
      'macadamia',
      'peanut',
      'seed',
      'chia',
      'flax',
      'coconut',
    ])) {
      category = 'fat';
    } else if (hasAny([
          'chicken',
          'beef',
          'pork',
          'turkey',
          'salmon',
          'tuna',
          'shrimp',
          'tilapia',
          'bangus',
          'milkfish',
          'scad',
          'sardine',
          'mackerel',
          'cod',
          'squid',
          'liver',
          'fish',
        ]) ||
        (has('egg') && !has('eggplant'))) {
      category = 'protein';
    } else if (hasAny([
      'bean',
      'lentil',
      'chickpea',
      'hummus',
      'pea',
      'mung',
      'edamame',
      'tofu',
      'tempeh',
    ])) {
      category = 'legume';
    } else if (hasAny([
      'rice',
      'bread',
      'oat',
      'pasta',
      'noodle',
      'quinoa',
      'couscous',
      'bagel',
      'granola',
      'cornflake',
      'roll',
      'potato',
      'cassava',
      'taro',
      'yam',
      'corn',
      'plantain',
      'wheat',
    ])) {
      category = 'grain';
    } else if (hasAny([
      'apple',
      'banana',
      'mango',
      'papaya',
      'berr',
      'orange',
      'pineapple',
      'watermelon',
      'pear',
      'kiwi',
      'grape',
      'cantaloupe',
      'raisin',
      'date',
    ])) {
      category = 'fruit';
    } else if (hasAny([
      'broccoli',
      'spinach',
      'pepper',
      'carrot',
      'tomato',
      'cucumber',
      'mushroom',
      'onion',
      'garlic',
      'kale',
      'zucchini',
      'cauliflower',
      'kangkong',
      'gourd',
      'moringa',
      'chayote',
      'eggplant',
      'bok choy',
      'radish',
      'okra',
      'squash',
      'jute',
      'lettuce',
      'cabbage',
      'celery',
      'asparagus',
      'brussels',
      'beet',
      'pumpkin',
      'seaweed',
      'nori',
      'sprout',
      'napa',
      'shiitake',
    ])) {
      category = 'vegetable';
    } else {
      category = 'other';
    }

    return {'allergens': allergens, 'category': category};
  }

  // ── Ingredient stubs ───────────────────────────────────────────────────────
  // Only identity + tags here. Nutrition is fetched from USDA at seed time.
  // cuisine: filipino | western | asian | universal

  static const List<Map<String, dynamic>> _ingredientStubs = [
    // Proteins · Universal / Western
    {
      'id': 'ing001',
      'name': 'Chicken Breast',
      'dietaryTags': ['halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing002',
      'name': 'Chicken Thigh',
      'dietaryTags': ['halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing003',
      'name': 'Ground Beef Lean',
      'dietaryTags': ['halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing004',
      'name': 'Beef Sirloin',
      'dietaryTags': ['halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing005',
      'name': 'Salmon raw',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'western',
    },
    {
      'id': 'ing006',
      'name': 'Canned Tuna in water',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing007',
      'name': 'Shrimp raw',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing008',
      'name': 'Whole egg raw',
      'dietaryTags': ['vegetarian', 'gluten-free'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing009',
      'name': 'Egg white raw',
      'dietaryTags': ['vegetarian', 'gluten-free'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing010',
      'name': 'Greek yogurt plain',
      'dietaryTags': ['vegetarian', 'gluten-free'],
      'cuisine': 'western',
    },
    {
      'id': 'ing011',
      'name': 'Cottage cheese lowfat',
      'dietaryTags': ['vegetarian', 'gluten-free'],
      'cuisine': 'western',
    },
    {
      'id': 'ing012',
      'name': 'Tofu firm',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free'],
      'cuisine': 'asian',
    },
    {
      'id': 'ing013',
      'name': 'Pork loin raw',
      'dietaryTags': ['gluten-free'],
      'cuisine': 'western',
    },
    {
      'id': 'ing014',
      'name': 'Turkey breast raw',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'western',
    },
    {
      'id': 'ing015',
      'name': 'Whey protein powder',
      'dietaryTags': ['vegetarian', 'gluten-free'],
      'cuisine': 'universal',
    },
    // Proteins · Filipino
    {
      'id': 'ing016',
      'name': 'Milkfish bangus raw',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing017',
      'name': 'Tilapia raw',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing018',
      'name': 'Pork belly raw',
      'dietaryTags': ['gluten-free'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing019',
      'name': 'Chicken drumstick raw',
      'dietaryTags': ['halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing020',
      'name': 'Round scad fish raw',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing021',
      'name': 'Dried salted fish',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing022',
      'name': 'Mung beans raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    // Carbs · Western / Universal
    {
      'id': 'ing023',
      'name': 'Oats dry',
      'dietaryTags': ['vegan', 'vegetarian', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing024',
      'name': 'Whole wheat bread',
      'dietaryTags': ['vegetarian', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing025',
      'name': 'Sweet potato raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing026',
      'name': 'Quinoa cooked',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing027',
      'name': 'Pasta cooked',
      'dietaryTags': ['vegetarian', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing028',
      'name': 'Brown bread',
      'dietaryTags': ['vegetarian', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing029',
      'name': 'Banana raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    // Carbs · Filipino
    {
      'id': 'ing030',
      'name': 'White rice cooked',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing031',
      'name': 'Brown rice cooked',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing032',
      'name': 'Sweet potato kamote raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing033',
      'name': 'Plantain banana raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing034',
      'name': 'Bread roll plain',
      'dietaryTags': ['vegetarian', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing035',
      'name': 'Cassava raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    // Vegetables · Universal / Western
    {
      'id': 'ing036',
      'name': 'Broccoli raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing037',
      'name': 'Spinach raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing038',
      'name': 'Bell pepper raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing039',
      'name': 'Carrot raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing040',
      'name': 'Tomato raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing041',
      'name': 'Cucumber raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing042',
      'name': 'Mushroom raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing043',
      'name': 'Onion raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing044',
      'name': 'Garlic raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing045',
      'name': 'Kale raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing046',
      'name': 'Zucchini raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing047',
      'name': 'Cauliflower raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    // Vegetables · Filipino
    {
      'id': 'ing048',
      'name': 'Water spinach kangkong',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing049',
      'name': 'Bitter gourd raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing050',
      'name': 'Moringa leaves raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing051',
      'name': 'Chayote raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing052',
      'name': 'Eggplant raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing053',
      'name': 'String beans raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing054',
      'name': 'Bok choy raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing055',
      'name': 'Radish raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    // Fats
    {
      'id': 'ing056',
      'name': 'Avocado raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing057',
      'name': 'Olive oil',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing058',
      'name': 'Coconut oil',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing059',
      'name': 'Peanut butter',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing060',
      'name': 'Almonds raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing061',
      'name': 'Chia seeds',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing062',
      'name': 'Coconut milk canned',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing063',
      'name': 'Walnuts raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    // Legumes
    {
      'id': 'ing064',
      'name': 'Black beans cooked',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing065',
      'name': 'Chickpeas cooked',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing066',
      'name': 'Lentils cooked',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing067',
      'name': 'Edamame cooked',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'asian',
    },
    // Dairy
    {
      'id': 'ing068',
      'name': 'Whole milk',
      'dietaryTags': ['vegetarian', 'gluten-free'],
      'cuisine': 'western',
    },
    {
      'id': 'ing069',
      'name': 'Cheddar cheese',
      'dietaryTags': ['vegetarian', 'gluten-free'],
      'cuisine': 'western',
    },
    {
      'id': 'ing070',
      'name': 'Almond milk unsweetened',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    // Fruits
    {
      'id': 'ing071',
      'name': 'Apple raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing072',
      'name': 'Blueberries raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing073',
      'name': 'Mango raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing074',
      'name': 'Papaya raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing075',
      'name': 'Strawberries raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    // Condiments
    {
      'id': 'ing076',
      'name': 'Soy sauce',
      'dietaryTags': ['vegan', 'vegetarian', 'halal'],
      'cuisine': 'asian',
    },
    {
      'id': 'ing077',
      'name': 'Vinegar',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing078',
      'name': 'Fish sauce',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing079',
      'name': 'Ginger root raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing080',
      'name': 'Honey',
      'dietaryTags': ['vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    // ── Expansion (ing081+) — fuller per-cuisine / per-role coverage ──────────
    // Asian
    {
      'id': 'ing081',
      'name': 'Jasmine rice cooked',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'asian',
    },
    {
      'id': 'ing082',
      'name': 'Soba noodles cooked',
      'dietaryTags': ['vegan', 'vegetarian', 'halal'],
      'cuisine': 'asian',
    },
    {
      'id': 'ing083',
      'name': 'Rice noodles cooked',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'asian',
    },
    {
      'id': 'ing084',
      'name': 'Tempeh',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free'],
      'cuisine': 'asian',
    },
    {
      'id': 'ing085',
      'name': 'Silken tofu',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free'],
      'cuisine': 'asian',
    },
    {
      'id': 'ing086',
      'name': 'Seaweed nori',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'asian',
    },
    {
      'id': 'ing087',
      'name': 'Shiitake mushroom raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'asian',
    },
    {
      'id': 'ing088',
      'name': 'Napa cabbage raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'asian',
    },
    {
      'id': 'ing089',
      'name': 'Bean sprouts raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'asian',
    },
    {
      'id': 'ing090',
      'name': 'Mackerel raw',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'asian',
    },
    {
      'id': 'ing091',
      'name': 'Squid raw',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'asian',
    },
    {
      'id': 'ing092',
      'name': 'Sesame oil',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'asian',
    },
    {
      'id': 'ing093',
      'name': 'Soy milk',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'asian',
    },
    // Filipino
    {
      'id': 'ing094',
      'name': 'Okra raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing095',
      'name': 'Squash raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing096',
      'name': 'Taro root raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing097',
      'name': 'Purple yam raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing098',
      'name': 'Jute leaves raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing099',
      'name': 'Coconut meat raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing100',
      'name': 'Smoked fish',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing101',
      'name': 'Pork shoulder raw',
      'dietaryTags': ['gluten-free'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing102',
      'name': 'Chicken wings raw',
      'dietaryTags': ['halal'],
      'cuisine': 'filipino',
    },
    {
      'id': 'ing103',
      'name': 'Pineapple raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'filipino',
    },
    // Western
    {
      'id': 'ing104',
      'name': 'Cod raw',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'western',
    },
    {
      'id': 'ing105',
      'name': 'Ground turkey raw',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'western',
    },
    {
      'id': 'ing106',
      'name': 'Pork tenderloin raw',
      'dietaryTags': ['gluten-free'],
      'cuisine': 'western',
    },
    {
      'id': 'ing107',
      'name': 'Mozzarella cheese',
      'dietaryTags': ['vegetarian', 'gluten-free'],
      'cuisine': 'western',
    },
    {
      'id': 'ing108',
      'name': 'Feta cheese',
      'dietaryTags': ['vegetarian', 'gluten-free'],
      'cuisine': 'western',
    },
    {
      'id': 'ing109',
      'name': 'Couscous cooked',
      'dietaryTags': ['vegetarian', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing110',
      'name': 'Bagel plain',
      'dietaryTags': ['vegetarian', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing111',
      'name': 'Green peas',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing112',
      'name': 'Asparagus raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing113',
      'name': 'Brussels sprouts raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing114',
      'name': 'Green beans raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing115',
      'name': 'Cashews raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing116',
      'name': 'Pecans raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing117',
      'name': 'Pistachios raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing118',
      'name': 'Hummus',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing119',
      'name': 'Granola',
      'dietaryTags': ['vegetarian', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing120',
      'name': 'Cornflakes',
      'dietaryTags': ['vegetarian', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing121',
      'name': 'Whole wheat pasta cooked',
      'dietaryTags': ['vegetarian', 'halal'],
      'cuisine': 'western',
    },
    {
      'id': 'ing122',
      'name': 'Macadamia nuts raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'western',
    },
    // Universal — proteins / carbs / veg / fruit / snack
    {
      'id': 'ing123',
      'name': 'White potato raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing124',
      'name': 'Corn raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing125',
      'name': 'Lettuce raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing126',
      'name': 'Cabbage raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing127',
      'name': 'Celery raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing128',
      'name': 'Sardines canned',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing129',
      'name': 'Mackerel canned',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing130',
      'name': 'Pinto beans cooked',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing131',
      'name': 'Kidney beans cooked',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing132',
      'name': 'Orange raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing133',
      'name': 'Watermelon raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing134',
      'name': 'Pear raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing135',
      'name': 'Kiwi raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing136',
      'name': 'Grapes raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing137',
      'name': 'Cantaloupe raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing138',
      'name': 'Raisins',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing139',
      'name': 'Dates',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing140',
      'name': 'Sunflower seeds',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing141',
      'name': 'Pumpkin seeds',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing142',
      'name': 'Flaxseed',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing143',
      'name': 'Rice cake',
      'dietaryTags': ['vegan', 'vegetarian', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing144',
      'name': 'Skim milk',
      'dietaryTags': ['vegetarian', 'gluten-free'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing145',
      'name': 'Pork chop raw',
      'dietaryTags': ['gluten-free'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing146',
      'name': 'Beef liver raw',
      'dietaryTags': ['halal', 'gluten-free'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing147',
      'name': 'Cherry tomatoes raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing148',
      'name': 'Beetroot raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing149',
      'name': 'Pumpkin raw',
      'dietaryTags': ['vegan', 'vegetarian', 'gluten-free', 'halal'],
      'cuisine': 'universal',
    },
    {
      'id': 'ing150',
      'name': 'Cottage cheese',
      'dietaryTags': ['vegetarian', 'gluten-free'],
      'cuisine': 'universal',
    },
  ];

  // ── Exercises (unchanged) ─────────────────────────────────────────────────
  static const List<Map<String, dynamic>> exercises = [
    {
      'id': 'ex001',
      'name': 'Burpee',
      'category': 'full body',
      'primaryMuscles': ['chest', 'quads', 'core'],
      'secondaryMuscles': ['shoulders', 'triceps'],
      'equipment': ['bodyweight'],
      'difficulty': 'intermediate',
      'goals': ['weight_loss', 'endurance', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'From standing, drop to push-up position, perform a push-up, jump feet to hands, then jump up with arms overhead.',
    },
    {
      'id': 'ex002',
      'name': 'Jumping Jacks',
      'category': 'cardio',
      'primaryMuscles': ['full body'],
      'secondaryMuscles': [],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['weight_loss', 'endurance', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Stand with feet together, jump feet apart while raising arms overhead, return to start.',
    },
    {
      'id': 'ex003',
      'name': 'High Knees',
      'category': 'cardio',
      'primaryMuscles': ['hip flexors', 'core'],
      'secondaryMuscles': ['quads', 'calves'],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['weight_loss', 'endurance'],
      'locations': ['home', 'gym'],
      'instructions':
          'Run in place, driving knees up to hip height alternately as fast as possible.',
    },
    {
      'id': 'ex004',
      'name': 'Mountain Climbers',
      'category': 'cardio',
      'primaryMuscles': ['core', 'shoulders'],
      'secondaryMuscles': ['hip flexors', 'quads'],
      'equipment': ['bodyweight'],
      'difficulty': 'intermediate',
      'goals': ['weight_loss', 'endurance', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Start in push-up position, alternate driving knees toward chest rapidly.',
    },
    {
      'id': 'ex005',
      'name': 'Jump Squat',
      'category': 'legs',
      'primaryMuscles': ['quads', 'glutes'],
      'secondaryMuscles': ['calves', 'core'],
      'equipment': ['bodyweight'],
      'difficulty': 'intermediate',
      'goals': ['weight_loss', 'endurance'],
      'locations': ['home', 'gym'],
      'instructions':
          'Squat down until thighs are parallel, then explode upward jumping off the ground. Land softly.',
    },
    {
      'id': 'ex006',
      'name': 'Skater Hop',
      'category': 'cardio',
      'primaryMuscles': ['glutes', 'quads'],
      'secondaryMuscles': ['calves', 'core'],
      'equipment': ['bodyweight'],
      'difficulty': 'intermediate',
      'goals': ['weight_loss', 'endurance'],
      'locations': ['home', 'gym'],
      'instructions':
          'Leap laterally from one foot to the other, mimicking a speed skater motion.',
    },
    {
      'id': 'ex007',
      'name': 'Jump Lunge',
      'category': 'legs',
      'primaryMuscles': ['quads', 'glutes'],
      'secondaryMuscles': ['hamstrings', 'calves'],
      'equipment': ['bodyweight'],
      'difficulty': 'intermediate',
      'goals': ['weight_loss', 'endurance'],
      'locations': ['home', 'gym'],
      'instructions':
          'Start in lunge position, jump and switch legs mid-air, landing in opposite lunge.',
    },
    {
      'id': 'ex008',
      'name': 'Box Jump',
      'category': 'full body',
      'primaryMuscles': ['quads', 'glutes'],
      'secondaryMuscles': ['calves', 'core'],
      'equipment': ['bodyweight'],
      'difficulty': 'advanced',
      'goals': ['weight_loss', 'endurance'],
      'locations': ['home', 'gym'],
      'instructions':
          'Jump onto a raised surface landing softly with bent knees, step back down.',
    },
    {
      'id': 'ex009',
      'name': 'Bear Crawl',
      'category': 'full body',
      'primaryMuscles': ['core', 'shoulders'],
      'secondaryMuscles': ['quads', 'triceps'],
      'equipment': ['bodyweight'],
      'difficulty': 'intermediate',
      'goals': ['weight_loss', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'On hands and feet with knees hovering, crawl forward keeping hips low.',
    },
    {
      'id': 'ex010',
      'name': 'Plank to Downward Dog',
      'category': 'core',
      'primaryMuscles': ['core', 'shoulders'],
      'secondaryMuscles': ['hamstrings'],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['weight_loss', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'From plank, push hips up into downward dog, return to plank. Repeat.',
    },
    {
      'id': 'ex011',
      'name': 'Push-Up',
      'category': 'chest',
      'primaryMuscles': ['chest'],
      'secondaryMuscles': ['triceps', 'shoulders'],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Start in plank position, lower chest to floor, push back up keeping body straight.',
    },
    {
      'id': 'ex012',
      'name': 'Wide Push-Up',
      'category': 'chest',
      'primaryMuscles': ['chest'],
      'secondaryMuscles': ['triceps'],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home'],
      'instructions':
          'Place hands wider than shoulder-width. Lower chest to floor and push up.',
    },
    {
      'id': 'ex013',
      'name': 'Diamond Push-Up',
      'category': 'arms',
      'primaryMuscles': ['triceps', 'chest'],
      'secondaryMuscles': ['shoulders'],
      'equipment': ['bodyweight'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain'],
      'locations': ['home', 'gym'],
      'instructions':
          'Form a diamond shape with hands under chest. Lower and push up.',
    },
    {
      'id': 'ex014',
      'name': 'Archer Push-Up',
      'category': 'chest',
      'primaryMuscles': ['chest', 'triceps'],
      'secondaryMuscles': ['shoulders'],
      'equipment': ['bodyweight'],
      'difficulty': 'advanced',
      'goals': ['muscle_gain'],
      'locations': ['home'],
      'instructions':
          'Wide push-up position, shift weight to one arm at a time while the other stays straight.',
    },
    {
      'id': 'ex015',
      'name': 'Pike Push-Up',
      'category': 'shoulders',
      'primaryMuscles': ['shoulders'],
      'secondaryMuscles': ['triceps'],
      'equipment': ['bodyweight'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home'],
      'instructions':
          'Form inverted V with hips high, lower head toward floor by bending elbows.',
    },
    {
      'id': 'ex016',
      'name': 'Tricep Dip',
      'category': 'arms',
      'primaryMuscles': ['triceps'],
      'secondaryMuscles': ['chest', 'shoulders'],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Hands on chair behind you, lower body by bending elbows, press back up.',
    },
    {
      'id': 'ex017',
      'name': 'Inverted Row',
      'category': 'back',
      'primaryMuscles': ['upper back'],
      'secondaryMuscles': ['biceps'],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home'],
      'instructions':
          'Lie under a table, grip edge, pull chest up to it keeping body straight.',
    },
    {
      'id': 'ex018',
      'name': 'Pull-Up',
      'category': 'back',
      'primaryMuscles': ['lats', 'upper back'],
      'secondaryMuscles': ['biceps'],
      'equipment': ['pull-up bar'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Hang with overhand grip, pull until chin is above bar, lower controlled.',
    },
    {
      'id': 'ex019',
      'name': 'Chin-Up',
      'category': 'back',
      'primaryMuscles': ['lats', 'biceps'],
      'secondaryMuscles': ['upper back'],
      'equipment': ['pull-up bar'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain'],
      'locations': ['home', 'gym'],
      'instructions':
          'Hang with underhand grip, pull until chin is above bar, lower controlled.',
    },
    {
      'id': 'ex020',
      'name': 'Superman Hold',
      'category': 'back',
      'primaryMuscles': ['lower back'],
      'secondaryMuscles': ['glutes'],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Lie face down, simultaneously lift arms and legs off floor, hold 2 seconds.',
    },
    {
      'id': 'ex021',
      'name': 'Glute Bridge',
      'category': 'legs',
      'primaryMuscles': ['glutes'],
      'secondaryMuscles': ['hamstrings'],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Lie on back, feet flat, drive hips up squeezing glutes at top, lower slowly.',
    },
    {
      'id': 'ex022',
      'name': 'Single Leg Glute Bridge',
      'category': 'legs',
      'primaryMuscles': ['glutes'],
      'secondaryMuscles': ['hamstrings', 'core'],
      'equipment': ['bodyweight'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Same as glute bridge but extend one leg straight, drive hips up with single leg.',
    },
    {
      'id': 'ex023',
      'name': 'Pistol Squat',
      'category': 'legs',
      'primaryMuscles': ['quads', 'glutes'],
      'secondaryMuscles': ['core'],
      'equipment': ['bodyweight'],
      'difficulty': 'advanced',
      'goals': ['muscle_gain'],
      'locations': ['home', 'gym'],
      'instructions':
          'Balance on one leg, squat down extending other leg forward, drive back up.',
    },
    {
      'id': 'ex024',
      'name': 'Dumbbell Bicep Curl',
      'category': 'arms',
      'primaryMuscles': ['biceps'],
      'secondaryMuscles': ['forearms'],
      'equipment': ['dumbbells'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain'],
      'locations': ['home', 'gym'],
      'instructions':
          'Curl dumbbells from hips to shoulders keeping elbows fixed at sides.',
    },
    {
      'id': 'ex025',
      'name': 'Hammer Curl',
      'category': 'arms',
      'primaryMuscles': ['biceps', 'forearms'],
      'secondaryMuscles': [],
      'equipment': ['dumbbells'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain'],
      'locations': ['home', 'gym'],
      'instructions':
          'Curl with neutral grip (thumbs up) from hips to shoulders.',
    },
    {
      'id': 'ex026',
      'name': 'Overhead Tricep Extension',
      'category': 'arms',
      'primaryMuscles': ['triceps'],
      'secondaryMuscles': [],
      'equipment': ['dumbbells'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain'],
      'locations': ['home', 'gym'],
      'instructions':
          'Hold dumbbell overhead with both hands, lower behind head, extend back up.',
    },
    {
      'id': 'ex027',
      'name': 'Dumbbell Shoulder Press',
      'category': 'shoulders',
      'primaryMuscles': ['shoulders'],
      'secondaryMuscles': ['triceps'],
      'equipment': ['dumbbells'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Press dumbbells from shoulder height to overhead, lower controlled.',
    },
    {
      'id': 'ex028',
      'name': 'Dumbbell Lateral Raise',
      'category': 'shoulders',
      'primaryMuscles': ['shoulders'],
      'secondaryMuscles': [],
      'equipment': ['dumbbells'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain'],
      'locations': ['home', 'gym'],
      'instructions':
          'Raise dumbbells out to sides until parallel with floor, lower slowly.',
    },
    {
      'id': 'ex029',
      'name': 'Dumbbell Row',
      'category': 'back',
      'primaryMuscles': ['lats', 'upper back'],
      'secondaryMuscles': ['biceps'],
      'equipment': ['dumbbells'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Hinge forward, row dumbbell to hip squeezing back, lower controlled.',
    },
    {
      'id': 'ex030',
      'name': 'Dumbbell Squat',
      'category': 'legs',
      'primaryMuscles': ['quads', 'glutes'],
      'secondaryMuscles': ['hamstrings'],
      'equipment': ['dumbbells'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Hold dumbbells at sides, squat until thighs parallel, drive up.',
    },
    {
      'id': 'ex031',
      'name': 'Dumbbell Lunge',
      'category': 'legs',
      'primaryMuscles': ['quads', 'glutes'],
      'secondaryMuscles': ['hamstrings'],
      'equipment': ['dumbbells'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Hold dumbbells, step forward into lunge, lower back knee, drive back up.',
    },
    {
      'id': 'ex032',
      'name': 'Romanian Deadlift',
      'category': 'legs',
      'primaryMuscles': ['hamstrings', 'glutes'],
      'secondaryMuscles': ['lower back'],
      'equipment': ['dumbbells'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain'],
      'locations': ['home', 'gym'],
      'instructions':
          'Hinge at hips lowering dumbbells along legs, feel hamstring stretch, drive hips forward.',
    },
    {
      'id': 'ex033',
      'name': 'Dumbbell Bench Press',
      'category': 'chest',
      'primaryMuscles': ['chest'],
      'secondaryMuscles': ['triceps', 'shoulders'],
      'equipment': ['dumbbells'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain'],
      'locations': ['home', 'gym'],
      'instructions':
          'Lie on back, press dumbbells from chest to full extension, lower controlled.',
    },
    {
      'id': 'ex034',
      'name': 'Kettlebell Swing',
      'category': 'full body',
      'primaryMuscles': ['glutes', 'hamstrings'],
      'secondaryMuscles': ['core', 'shoulders'],
      'equipment': ['kettlebells'],
      'difficulty': 'intermediate',
      'goals': ['weight_loss', 'endurance', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Hinge at hips, swing kettlebell forward to shoulder height using explosive hip drive.',
    },
    {
      'id': 'ex035',
      'name': 'Kettlebell Goblet Squat',
      'category': 'legs',
      'primaryMuscles': ['quads', 'glutes'],
      'secondaryMuscles': ['core'],
      'equipment': ['kettlebells'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Hold kettlebell at chest, squat deep keeping torso upright, drive up.',
    },
    {
      'id': 'ex036',
      'name': 'Resistance Band Row',
      'category': 'back',
      'primaryMuscles': ['upper back'],
      'secondaryMuscles': ['biceps'],
      'equipment': ['resistance bands'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home'],
      'instructions':
          'Anchor band, pull handles to sides of torso squeezing shoulder blades together.',
    },
    {
      'id': 'ex037',
      'name': 'Resistance Band Squat',
      'category': 'legs',
      'primaryMuscles': ['quads', 'glutes'],
      'secondaryMuscles': [],
      'equipment': ['resistance bands'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home'],
      'instructions':
          'Stand on band, hold handles at shoulders, perform squat.',
    },
    {
      'id': 'ex038',
      'name': 'Band Pull Apart',
      'category': 'shoulders',
      'primaryMuscles': ['rear delts', 'upper back'],
      'secondaryMuscles': [],
      'equipment': ['resistance bands'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Hold band in front at shoulder height, pull apart horizontally squeezing rear delts.',
    },
    {
      'id': 'ex039',
      'name': 'Resistance Band Curl',
      'category': 'arms',
      'primaryMuscles': ['biceps'],
      'secondaryMuscles': [],
      'equipment': ['resistance bands'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home'],
      'instructions': 'Stand on band, curl handles up to shoulders.',
    },
    {
      'id': 'ex040',
      'name': 'Plank',
      'category': 'core',
      'primaryMuscles': ['core'],
      'secondaryMuscles': ['shoulders'],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['weight_loss', 'muscle_gain', 'endurance', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Hold push-up position on forearms, keep body in straight line, breathe steadily.',
    },
    {
      'id': 'ex041',
      'name': 'Crunches',
      'category': 'core',
      'primaryMuscles': ['abs'],
      'secondaryMuscles': [],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['weight_loss', 'muscle_gain', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Lie on back, curl upper body toward knees using abs, lower controlled.',
    },
    {
      'id': 'ex042',
      'name': 'Bicycle Crunch',
      'category': 'core',
      'primaryMuscles': ['abs', 'obliques'],
      'secondaryMuscles': [],
      'equipment': ['bodyweight'],
      'difficulty': 'intermediate',
      'goals': ['weight_loss', 'muscle_gain', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Alternate touching elbow to opposite knee in a cycling motion.',
    },
    {
      'id': 'ex043',
      'name': 'Leg Raise',
      'category': 'core',
      'primaryMuscles': ['lower abs'],
      'secondaryMuscles': ['hip flexors'],
      'equipment': ['bodyweight'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Lie on back, raise straight legs to 90 degrees, lower slowly without touching floor.',
    },
    {
      'id': 'ex044',
      'name': 'Russian Twist',
      'category': 'core',
      'primaryMuscles': ['obliques'],
      'secondaryMuscles': ['abs'],
      'equipment': ['bodyweight'],
      'difficulty': 'intermediate',
      'goals': ['weight_loss', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Sit with knees bent, lean back slightly, rotate torso side to side.',
    },
    {
      'id': 'ex045',
      'name': 'Dead Bug',
      'category': 'core',
      'primaryMuscles': ['core'],
      'secondaryMuscles': [],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['general', 'muscle_gain'],
      'locations': ['home', 'gym'],
      'instructions':
          'Lie on back, extend opposite arm and leg simultaneously, keep lower back pressed to floor.',
    },
    {
      'id': 'ex046',
      'name': 'Bodyweight Squat',
      'category': 'legs',
      'primaryMuscles': ['quads', 'glutes'],
      'secondaryMuscles': ['hamstrings'],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['endurance', 'general', 'weight_loss'],
      'locations': ['home', 'gym'],
      'instructions':
          'Stand feet shoulder-width, squat until thighs parallel to floor, drive up.',
    },
    {
      'id': 'ex047',
      'name': 'Lunge',
      'category': 'legs',
      'primaryMuscles': ['quads', 'glutes'],
      'secondaryMuscles': ['hamstrings'],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['endurance', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Step forward, lower back knee toward floor, push back to starting position.',
    },
    {
      'id': 'ex048',
      'name': 'Wall Sit',
      'category': 'legs',
      'primaryMuscles': ['quads'],
      'secondaryMuscles': ['glutes'],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['endurance', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Back against wall, lower until thighs parallel, hold position for time.',
    },
    {
      'id': 'ex049',
      'name': 'Calf Raise',
      'category': 'legs',
      'primaryMuscles': ['calves'],
      'secondaryMuscles': [],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['endurance', 'general'],
      'locations': ['home', 'gym'],
      'instructions':
          'Stand on edge of step, raise heels as high as possible, lower slowly.',
    },
    {
      'id': 'ex050',
      'name': 'Lateral Shuffle',
      'category': 'cardio',
      'primaryMuscles': ['quads', 'glutes'],
      'secondaryMuscles': ['calves'],
      'equipment': ['bodyweight'],
      'difficulty': 'beginner',
      'goals': ['endurance', 'weight_loss'],
      'locations': ['home', 'gym'],
      'instructions':
          'Shuffle laterally in athletic stance, touch floor on each side.',
    },
    {
      'id': 'ex051',
      'name': 'Barbell Bench Press',
      'category': 'chest',
      'primaryMuscles': ['chest'],
      'secondaryMuscles': ['triceps', 'shoulders'],
      'equipment': ['gym'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain'],
      'locations': ['gym'],
      'instructions':
          'Lower barbell to chest, press to full extension, keep feet flat and back slightly arched.',
    },
    {
      'id': 'ex052',
      'name': 'Incline Barbell Press',
      'category': 'chest',
      'primaryMuscles': ['upper chest'],
      'secondaryMuscles': ['triceps', 'shoulders'],
      'equipment': ['gym'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain'],
      'locations': ['gym'],
      'instructions': 'On incline bench, lower bar to upper chest, press up.',
    },
    {
      'id': 'ex053',
      'name': 'Cable Fly',
      'category': 'chest',
      'primaryMuscles': ['chest'],
      'secondaryMuscles': [],
      'equipment': ['gym'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain'],
      'locations': ['gym'],
      'instructions':
          'Set cables at shoulder height, bring handles together in arc motion.',
    },
    {
      'id': 'ex054',
      'name': 'Barbell Squat',
      'category': 'legs',
      'primaryMuscles': ['quads', 'glutes'],
      'secondaryMuscles': ['hamstrings', 'core'],
      'equipment': ['gym'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain'],
      'locations': ['gym'],
      'instructions':
          'Bar on upper back, squat until thighs parallel, drive through heels.',
    },
    {
      'id': 'ex055',
      'name': 'Leg Press',
      'category': 'legs',
      'primaryMuscles': ['quads', 'glutes'],
      'secondaryMuscles': ['hamstrings'],
      'equipment': ['gym'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain', 'general'],
      'locations': ['gym'],
      'instructions':
          'Push platform away extending legs, lower controlled without locking knees.',
    },
    {
      'id': 'ex056',
      'name': 'Leg Curl',
      'category': 'legs',
      'primaryMuscles': ['hamstrings'],
      'secondaryMuscles': [],
      'equipment': ['gym'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain'],
      'locations': ['gym'],
      'instructions':
          'Lie on machine, curl legs toward glutes, lower controlled.',
    },
    {
      'id': 'ex057',
      'name': 'Barbell Deadlift',
      'category': 'back',
      'primaryMuscles': ['hamstrings', 'glutes', 'lower back'],
      'secondaryMuscles': ['traps', 'core'],
      'equipment': ['gym'],
      'difficulty': 'advanced',
      'goals': ['muscle_gain'],
      'locations': ['gym'],
      'instructions':
          'Grip bar, hinge to floor keeping back flat, drive through floor to standing.',
    },
    {
      'id': 'ex058',
      'name': 'Lat Pulldown',
      'category': 'back',
      'primaryMuscles': ['lats'],
      'secondaryMuscles': ['biceps'],
      'equipment': ['gym'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain', 'general'],
      'locations': ['gym'],
      'instructions':
          'Pull bar to upper chest leaning slightly back, control return.',
    },
    {
      'id': 'ex059',
      'name': 'Cable Row',
      'category': 'back',
      'primaryMuscles': ['upper back'],
      'secondaryMuscles': ['biceps'],
      'equipment': ['gym'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain', 'general'],
      'locations': ['gym'],
      'instructions':
          'Pull cable handle to abdomen squeezing shoulder blades, control return.',
    },
    {
      'id': 'ex060',
      'name': 'Tricep Pushdown',
      'category': 'arms',
      'primaryMuscles': ['triceps'],
      'secondaryMuscles': [],
      'equipment': ['gym'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain'],
      'locations': ['gym'],
      'instructions':
          'Push cable bar down extending elbows fully, control return.',
    },
    {
      'id': 'ex061',
      'name': 'Barbell Curl',
      'category': 'arms',
      'primaryMuscles': ['biceps'],
      'secondaryMuscles': ['forearms'],
      'equipment': ['gym'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain'],
      'locations': ['gym'],
      'instructions':
          'Curl barbell from hips to shoulders keeping elbows fixed.',
    },
    {
      'id': 'ex062',
      'name': 'Overhead Press (Barbell)',
      'category': 'shoulders',
      'primaryMuscles': ['shoulders'],
      'secondaryMuscles': ['triceps', 'core'],
      'equipment': ['gym'],
      'difficulty': 'intermediate',
      'goals': ['muscle_gain'],
      'locations': ['gym'],
      'instructions':
          'Press barbell from shoulder height to overhead, lower controlled.',
    },
    {
      'id': 'ex063',
      'name': 'Face Pull',
      'category': 'shoulders',
      'primaryMuscles': ['rear delts', 'upper back'],
      'secondaryMuscles': [],
      'equipment': ['gym'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain', 'general'],
      'locations': ['gym'],
      'instructions':
          'Pull rope attachment toward face, flare elbows out, squeeze rear delts.',
    },
    {
      'id': 'ex064',
      'name': 'Machine Chest Fly',
      'category': 'chest',
      'primaryMuscles': ['chest'],
      'secondaryMuscles': [],
      'equipment': ['gym'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain'],
      'locations': ['gym'],
      'instructions':
          'Sit at machine, bring arms together in front squeezing chest.',
    },
    {
      'id': 'ex065',
      'name': 'Leg Extension',
      'category': 'legs',
      'primaryMuscles': ['quads'],
      'secondaryMuscles': [],
      'equipment': ['gym'],
      'difficulty': 'beginner',
      'goals': ['muscle_gain'],
      'locations': ['gym'],
      'instructions':
          'Sit at machine, extend legs to full extension, lower controlled.',
    },
    {
      'id': 'ex066',
      'name': 'Treadmill Run',
      'category': 'cardio',
      'primaryMuscles': ['full body'],
      'secondaryMuscles': [],
      'equipment': ['gym'],
      'difficulty': 'beginner',
      'goals': ['endurance', 'weight_loss'],
      'locations': ['gym'],
      'instructions':
          'Run at steady pace on treadmill, maintain consistent breathing.',
    },
    {
      'id': 'ex067',
      'name': 'Rowing Machine',
      'category': 'cardio',
      'primaryMuscles': ['back', 'legs'],
      'secondaryMuscles': ['core', 'arms'],
      'equipment': ['gym'],
      'difficulty': 'intermediate',
      'goals': ['endurance', 'weight_loss'],
      'locations': ['gym'],
      'instructions':
          'Drive with legs, lean back, pull handle to lower chest, reverse motion.',
    },
    {
      'id': 'ex068',
      'name': 'Stationary Bike',
      'category': 'cardio',
      'primaryMuscles': ['quads', 'calves'],
      'secondaryMuscles': ['glutes'],
      'equipment': ['gym'],
      'difficulty': 'beginner',
      'goals': ['endurance', 'weight_loss'],
      'locations': ['gym'],
      'instructions':
          'Cycle at moderate to high resistance for sustained cardio.',
    },
    {
      'id': 'ex069',
      'name': 'Stair Climber',
      'category': 'cardio',
      'primaryMuscles': ['glutes', 'quads'],
      'secondaryMuscles': ['calves'],
      'equipment': ['gym'],
      'difficulty': 'intermediate',
      'goals': ['endurance', 'weight_loss'],
      'locations': ['gym'],
      'instructions': 'Step continuously at steady pace, keep upright posture.',
    },
    {
      'id': 'ex070',
      'name': 'Battle Ropes',
      'category': 'cardio',
      'primaryMuscles': ['shoulders', 'core'],
      'secondaryMuscles': ['arms'],
      'equipment': ['gym'],
      'difficulty': 'intermediate',
      'goals': ['endurance', 'weight_loss'],
      'locations': ['gym'],
      'instructions': 'Alternate waving ropes rapidly for timed intervals.',
    },
  ];
}
