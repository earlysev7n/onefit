import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/meal_ingredient.dart';
import '../models/food_item.dart';
import '../services/firestore_service.dart';
import '../services/openai_service.dart';
import '../app_clock.dart';

class RecipeScreen extends StatefulWidget {
  final Meal meal;
  final String mealLabel;

  const RecipeScreen({super.key, required this.meal, required this.mealLabel});

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  bool _isLoading = true;
  String? _error;
  _RecipeResult? _recipe;
  bool _isSaved = false;
  bool _isSaving = false;

  final Set<int> _addedExtras = {};
  final Set<int> _addingExtras = {};

  String get _mealType => widget.mealLabel.toLowerCase();
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadSavedOrFetch();
  }

  Future<void> _loadSavedOrFetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (_uid == null) {
        await _fetchRecipe(freshSearch: true);
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('saved_recipes')
          .doc(_mealType)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final steps = (data['steps'] as List? ?? [])
            .map(
              (s) => _RecipeStep(
                number: s['number'],
                instruction: s['instruction'],
              ),
            )
            .toList();
        final missing = (data['missingIngredients'] as List? ?? [])
            .map(
              (m) => _MissingIngredient(name: m['name'], amount: m['amount']),
            )
            .toList();
        setState(() {
          _recipe = _RecipeResult(
            title: data['title'] ?? '',
            image: data['image'] ?? '',
            steps: steps,
            readyInMinutes: data['readyInMinutes'] ?? 0,
            servings: data['servings'] ?? 1,
            sourceUrl: data['sourceUrl'] ?? '',
            missingIngredients: missing,
          );
          _isSaved = true;
          _isLoading = false;
        });
      } else {
        await _fetchRecipe(freshSearch: true);
      }
    } catch (e) {
      await _fetchRecipe(freshSearch: true);
    }
  }

  Future<void> _fetchRecipe({bool freshSearch = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Pass the Genetic-Algorithm ingredients (with gram portions) to OpenAI,
      // which writes the step-by-step cooking instructions.
      final ingredients = widget.meal.items
          .map((i) => '${i.portionGrams.round()}g ${i.ingredient.name}')
          .toList();
      if (ingredients.isEmpty) {
        throw Exception('No ingredients to build a recipe from.');
      }

      final generated = await OpenAIService().generateRecipe(
        ingredients: ingredients,
        mealType: _mealType,
      );

      final steps = generated.steps
          .asMap()
          .entries
          .map((e) => _RecipeStep(number: e.key + 1, instruction: e.value))
          .toList();

      setState(() {
        _recipe = _RecipeResult(
          title: generated.title,
          image: '', // OpenAI returns no image — the card simply omits it
          steps: steps,
          readyInMinutes: generated.readyInMinutes,
          servings: generated.servings,
          sourceUrl: '',
          missingIngredients: const [],
        );
        _isSaved = false;
        _addedExtras.clear();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleSave() async {
    if (_recipe == null || _uid == null) return;
    setState(() => _isSaving = true);
    try {
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('saved_recipes')
          .doc(_mealType);

      if (_isSaved) {
        await ref.delete();
        setState(() {
          _isSaved = false;
          _isSaving = false;
        });
        _showSnack('Recipe removed', const Color(0xFF888888));
      } else {
        await ref.set({
          'title': _recipe!.title,
          'image': _recipe!.image,
          'readyInMinutes': _recipe!.readyInMinutes,
          'servings': _recipe!.servings,
          'sourceUrl': _recipe!.sourceUrl,
          'mealType': _mealType,
          'savedAt': FieldValue.serverTimestamp(),
          'steps': _recipe!.steps
              .map((s) => {'number': s.number, 'instruction': s.instruction})
              .toList(),
          'missingIngredients': _recipe!.missingIngredients
              .map((m) => {'name': m.name, 'amount': m.amount})
              .toList(),
        });
        setState(() {
          _isSaved = true;
          _isSaving = false;
        });
        _showSnack('Recipe saved!', const Color(0xFF00C97B));
      }
    } catch (e) {
      setState(() => _isSaving = false);
      _showSnack('Error: $e', Colors.redAccent);
    }
  }

  Future<void> _addExtraToMealPlan(int index) async {
    if (_uid == null) return;
    final extra = _recipe!.missingIngredients[index];
    setState(() => _addingExtras.add(index));
    try {
      final parts = extra.amount.trim().split(' ');
      final qty = double.tryParse(parts.first) ?? 1.0;

      final foodItem = FoodItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: _uid!,
        name: extra.name,
        barcode: '',
        servingSize: qty,
        servingSizeUnit: parts.length > 1
            ? parts.sublist(1).join(' ')
            : 'serving',
        calories: 0,
        protein: 0,
        carbs: 0,
        fat: 0,
        fiber: 0,
        sugar: 0,
        sodium: 0,
        loggedAt: appNow(),
        mealType: _mealType,
        quantity: 1.0,
      );
      await FirestoreService().logFoodItem(foodItem);
      setState(() {
        _addedExtras.add(index);
        _addingExtras.remove(index);
      });
      _showSnack(
        '${extra.name} added to ${widget.mealLabel}',
        const Color(0xFF00C97B),
      );
    } catch (e) {
      setState(() => _addingExtras.remove(index));
      _showSnack('Error: $e', Colors.redAccent);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        title: Text(
          '${widget.mealLabel} Recipe',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (!_isLoading && _recipe != null)
            _isSaving
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Color(0xFF00C97B),
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : IconButton(
                    icon: Icon(
                      _isSaved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: _isSaved
                          ? const Color(0xFF00C97B)
                          : const Color(0xFF888888),
                    ),
                    onPressed: _toggleSave,
                    tooltip: _isSaved ? 'Unsave recipe' : 'Save recipe',
                  ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00C97B)),
            onPressed: () => _fetchRecipe(freshSearch: false),
            tooltip: 'Try another recipe',
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoading()
          : _error != null
          ? _buildError()
          : _buildRecipe(),
    );
  }

  Widget _buildLoading() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: Color(0xFF00C97B)),
        const SizedBox(height: 16),
        Text(
          'Writing your recipe...',
          style: GoogleFonts.inter(color: const Color(0xFF888888)),
        ),
        const SizedBox(height: 4),
        Text(
          'Powered by OpenAI',
          style: GoogleFonts.inter(
            color: const Color(0xFF444444),
            fontSize: 12,
          ),
        ),
      ],
    ),
  );

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.restaurant_menu_rounded,
            color: Color(0xFF444444),
            size: 56,
          ),
          const SizedBox(height: 16),
          Text(
            'Could not load recipe',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            style: GoogleFonts.inter(color: const Color(0xFF888888)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _fetchRecipe(freshSearch: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C97B),
              foregroundColor: Colors.black,
            ),
            child: Text(
              'Try Again',
              style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildRecipe() {
    final recipe = _recipe!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Saved banner
          if (_isSaved) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF00C97B).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF00C97B).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.bookmark_rounded,
                    color: Color(0xFF00C97B),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Saved recipe — tap bookmark to remove',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF00C97B),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Recipe image
          if (recipe.image.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                recipe.image,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Title
          Text(
            recipe.title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),

          // Meta
          Row(
            children: [
              _metaChip(
                Icons.timer_rounded,
                '${recipe.readyInMinutes} min',
                const Color(0xFF00C97B),
              ),
              const SizedBox(width: 8),
              _metaChip(
                Icons.people_rounded,
                '${recipe.servings} servings',
                const Color(0xFF6C63FF),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Ingredients from meal
          Text(
            'Ingredients from your meal',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: widget.meal.items
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00C97B),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.ingredient.name,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            '${item.portionGrams.round()}g',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF888888),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),

          // Missing extras
          if (recipe.missingIngredients.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  "You'll also need",
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD60A).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${recipe.missingIngredients.length} extra',
                    style: GoogleFonts.inter(
                      color: const Color(0xFFFFD60A),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFFFD60A).withOpacity(0.3),
                ),
              ),
              child: Column(
                children: recipe.missingIngredients.asMap().entries.map((
                  entry,
                ) {
                  final i = entry.key;
                  final ing = entry.value;
                  final isAdded = _addedExtras.contains(i);
                  final isAdding = _addingExtras.contains(i);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFD60A),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ing.name,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                ing.amount,
                                style: GoogleFonts.inter(
                                  color: const Color(0xFF888888),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: isAdded || isAdding
                              ? null
                              : () => _addExtraToMealPlan(i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isAdded
                                  ? const Color(0xFF00C97B).withOpacity(0.15)
                                  : const Color(0xFFFFD60A).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isAdded
                                    ? const Color(0xFF00C97B).withOpacity(0.4)
                                    : const Color(0xFFFFD60A).withOpacity(0.4),
                              ),
                            ),
                            child: isAdding
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      color: Color(0xFFFFD60A),
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isAdded
                                            ? Icons.check_rounded
                                            : Icons.add_rounded,
                                        color: isAdded
                                            ? const Color(0xFF00C97B)
                                            : const Color(0xFFFFD60A),
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isAdded ? 'Added' : 'Add',
                                        style: GoogleFonts.inter(
                                          color: isAdded
                                              ? const Color(0xFF00C97B)
                                              : const Color(0xFFFFD60A),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Instructions
          Text(
            'Cooking Instructions',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          if (recipe.steps.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'No instructions available for this recipe.',
                style: GoogleFonts.inter(color: const Color(0xFF888888)),
              ),
            )
          else
            ...recipe.steps.map(
              (step) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C97B).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${step.number}',
                          style: GoogleFonts.spaceGrotesk(
                            color: const Color(0xFF00C97B),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        step.instruction,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),

          // Nutrition summary
          Text(
            'Nutrition Summary',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                _nutriRow(
                  'Calories',
                  '${widget.meal.totalCalories.round()} kcal',
                  const Color(0xFFFF6B35),
                ),
                _nutriRow(
                  'Protein',
                  '${widget.meal.totalProtein.round()}g',
                  const Color(0xFF00C97B),
                ),
                _nutriRow(
                  'Carbohydrates',
                  '${widget.meal.totalCarbs.round()}g',
                  const Color(0xFF6C63FF),
                ),
                _nutriRow(
                  'Fat',
                  '${widget.meal.totalFat.round()}g',
                  const Color(0xFFFFD60A),
                ),
                _nutriRow(
                  'Fiber',
                  '${widget.meal.totalFiber.round()}g',
                  const Color(0xFF00B4D8),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Try another recipe
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _fetchRecipe(freshSearch: false),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(
                'Try Another Recipe',
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00C97B),
                side: const BorderSide(color: Color(0xFF00C97B)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );

  Widget _nutriRow(String label, String value, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.inter(color: const Color(0xFF888888)),
            ),
          ],
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

// Models
class _RecipeResult {
  final String title, image, sourceUrl;
  final List<_RecipeStep> steps;
  final List<_MissingIngredient> missingIngredients;
  final int readyInMinutes, servings;

  _RecipeResult({
    required this.title,
    required this.image,
    required this.steps,
    required this.readyInMinutes,
    required this.servings,
    required this.sourceUrl,
    required this.missingIngredients,
  });
}

class _RecipeStep {
  final int number;
  final String instruction;
  _RecipeStep({required this.number, required this.instruction});
}

class _MissingIngredient {
  final String name, amount;
  _MissingIngredient({required this.name, required this.amount});
}
