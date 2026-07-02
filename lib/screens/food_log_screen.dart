import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../services/openfoodfacts_service.dart';
import '../services/firestore_service.dart';
import '../services/dietary_filter.dart';
import '../providers/profile_provider.dart';
import '../models/food_item.dart';
import '../app_clock.dart';
import 'barcode_scan_screen.dart';
import '../theme/app_colors.dart';

class FoodLogScreen extends StatefulWidget {
  final String mealType;
  final bool autoScan;
  const FoodLogScreen({
    super.key,
    required this.mealType,
    this.autoScan = false,
  });

  @override
  State<FoodLogScreen> createState() => _FoodLogScreenState();
}

class _FoodLogScreenState extends State<FoodLogScreen> {
  final _searchController = TextEditingController();
  final _openFoodFacts = OpenFoodFactsService();
  final _firestore = FirestoreService();

  List<_USDAFoodItem> _results = [];
  List<FoodItem> _history = [];
  bool _isLoading = false;
  bool _isLoadingHistory = true;
  bool _hasSearched = false;
  int _hiddenCount = 0;
  String? _error;

  final Set<String> _loggingIds = {};

  static const String _apiKey = 'Fte86dAfeHdSgs4PI68EdVN3LevdLEebYFiDM6fZ';
  static const String _baseUrl = 'https://api.nal.usda.gov/fdc/v1';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    if (widget.autoScan) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scanBarcode());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── History ──────────────────────────────────────────────────────────────────

  Future<void> _loadHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final end = appNow();
      final start = end.subtract(const Duration(days: 30));
      final all = await _firestore.getFoodLogsForDateRange(uid, start, end);

      final seen = <String>{};
      final history = <FoodItem>[];
      for (final item in all.reversed) {
        if (item.mealType.toLowerCase() == widget.mealType.toLowerCase() &&
            seen.add(item.name.toLowerCase())) {
          history.add(item);
          if (history.length >= 20) break;
        }
      }

      if (mounted)
        setState(() {
          _history = history;
          _isLoadingHistory = false;
        });
    } catch (e) {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _quickAddHistory(FoodItem original) async {
    final key = original.id;
    setState(() => _loggingIds.add(key));
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final relogged = original.copyWith(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: uid,
        loggedAt: appNow(),
        mealType: widget.mealType,
      );
      await _firestore.logFoodItem(relogged);
      if (mounted) {
        context.read<ProfileProvider>().recomputeGoal(uid).ignore();
      }
      _showSuccessSnackbar(original.name);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loggingIds.remove(key));
    }
  }

  // ── Barcode ──────────────────────────────────────────────────────────────────

  Future<void> _scanBarcode() async {
    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (barcode == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final product = await _openFoodFacts.getProductByBarcode(barcode);
      if (product == null) {
        setState(() {
          _error = 'Product not found. Try manual search.';
          _isLoading = false;
        });
        return;
      }
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final foodItem = _openFoodFacts.parseProductToFoodItem(
        product: product,
        userId: uid,
        barcode: barcode,
        mealType: widget.mealType,
      );
      if (foodItem == null) {
        setState(() {
          _error = 'Could not read nutrition data.';
          _isLoading = false;
        });
        return;
      }
      setState(() => _isLoading = false);
      final confirmed = await _showBarcodeConfirmation(foodItem, product);
      if (confirmed == true) {
        _showSuccessSnackbar(foodItem.name);
        _loadHistory();
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && mounted) {
          context.read<ProfileProvider>().recomputeGoal(uid).ignore();
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Scanner error: $e';
        _isLoading = false;
      });
    }
  }

  Future<bool?> _showBarcodeConfirmation(
    FoodItem foodItem,
    Map<String, dynamic> product,
  ) async {
    double quantity = 1.0;
    final c = context.colors;
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_openFoodFacts.getProductImageUrl(product) != null)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      _openFoodFacts.getProductImageUrl(product)!,
                      height: 100,
                      width: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.fastfood,
                        size: 60,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                foodItem.name,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: c.onBackground,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              Text(
                'Per serving: ${foodItem.servingSize.toStringAsFixed(0)}${foodItem.servingSizeUnit}',
                style: GoogleFonts.inter(color: c.muted),
              ),
              const SizedBox(height: 12),
              _macroRow(
                foodItem.calories * quantity,
                foodItem.protein * quantity,
                foodItem.carbs * quantity,
                foodItem.fat * quantity,
              ),
              const SizedBox(height: 12),
              Text(
                'Servings: ${quantity.toStringAsFixed(1)}',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: c.onBackground,
                ),
              ),
              Slider(
                value: quantity,
                min: 0.5,
                max: 5.0,
                divisions: 18,
                activeColor: AppColors.primary,
                inactiveColor: c.borderLight,
                label: quantity.toStringAsFixed(1),
                onChanged: (v) => setModalState(() => quantity = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: c.subtle),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await _firestore.logFoodItem(
                          foodItem.copyWith(quantity: quantity),
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: c.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Log Food',
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── USDA Search ──────────────────────────────────────────────────────────────

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    // Capture before the async gap — don't touch context after an await.
    final restrictions =
        context.read<ProfileProvider>().profile?.dietaryRestrictions ??
            const <String>[];
    setState(() {
      _isLoading = true;
      _error = null;
      _hasSearched = true;
      _hiddenCount = 0;
    });
    try {
      final uri = Uri.parse('$_baseUrl/foods/search').replace(
        queryParameters: {
          'query': query,
          'api_key': _apiKey,
          'pageSize': '20',
          'dataType': 'Survey (FNDDS),SR Legacy,Foundation',
        },
      );
      final response = await http.get(uri);
      if (response.statusCode != 200)
        throw Exception('API error ${response.statusCode}');

      final data = jsonDecode(response.body);
      final foods = data['foods'] as List? ?? [];

      final results = foods
          .map((f) {
            final nutrients = (f['foodNutrients'] as List? ?? []);

            // Returns value for a given USDA nutrient ID
            double getN(int id) {
              final n = nutrients.firstWhere(
                (n) =>
                    n['nutrientId'] == id ||
                    n['nutrientNumber'] == id.toString(),
                orElse: () => {},
              );
              return ((n['value'] ?? n['amount'] ?? 0) as num).toDouble();
            }

            return _USDAFoodItem(
              fdcId: f['fdcId']?.toString() ?? '',
              name: f['description'] ?? 'Unknown',
              brandOwner: f['brandOwner'] ?? f['brandName'] ?? '',
              servingSize: (f['servingSize'] ?? 100).toDouble(),
              servingUnit: f['servingSizeUnit'] ?? 'g',
              // Macros
              calories: getN(1008),
              protein: getN(1003),
              carbs: getN(1005),
              fat: getN(1004),
              fiber: getN(1079),
              sugar: getN(1063),
              sodium: getN(1093),
              // Vitamins
              vitaminA: getN(1106),
              vitaminC: getN(1162),
              vitaminD: getN(1114),
              vitaminE: getN(1109),
              vitaminK: getN(1185),
              vitaminB6: getN(1175),
              vitaminB12: getN(1178),
              folate: getN(1177),
              // Minerals
              iron: getN(1089),
              calcium: getN(1087),
              magnesium: getN(1090),
              potassium: getN(1092),
              zinc: getN(1095),
              phosphorus: getN(1091),
            );
          })
          .where((f) => f.calories > 0)
          .toList();

      // Hide results that conflict with the user's dietary restrictions.
      // USDA has no dietary tags, so this is a name-keyword denylist — it hides
      // obvious conflicts (pork for Halal, meat for Vegetarian, …) but cannot
      // certify compliance. See DietaryFilter.
      final compliant = DietaryFilter.filter(
        results,
        restrictions,
        (f) => '${f.name} ${f.brandOwner}',
      );

      setState(() {
        _results = compliant;
        _hiddenCount = results.length - compliant.length;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _quickAddUSDA(_USDAFoodItem food) async {
    await _showPortionDialog(food);
  }

  Future<void> _logUSDAFood(_USDAFoodItem food, double portionGrams) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ratio = portionGrams / food.servingSize;
    final foodItem = FoodItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: uid,
      name: food.name,
      barcode: food.fdcId,
      servingSize: food.servingSize,
      servingSizeUnit: food.servingUnit,
      calories: food.calories,
      protein: food.protein,
      carbs: food.carbs,
      fat: food.fat,
      fiber: food.fiber,
      sugar: food.sugar,
      sodium: food.sodium,
      vitaminA: food.vitaminA,
      vitaminC: food.vitaminC,
      vitaminD: food.vitaminD,
      vitaminE: food.vitaminE,
      vitaminK: food.vitaminK,
      vitaminB6: food.vitaminB6,
      vitaminB12: food.vitaminB12,
      folate: food.folate,
      iron: food.iron,
      calcium: food.calcium,
      magnesium: food.magnesium,
      potassium: food.potassium,
      zinc: food.zinc,
      phosphorus: food.phosphorus,
      loggedAt: appNow(),
      mealType: widget.mealType,
      quantity: ratio,
    );
    await _firestore.logFoodItem(foodItem);
    if (mounted) {
      context.read<ProfileProvider>().recomputeGoal(uid).ignore();
    }
    _showSuccessSnackbar(food.name);
    _loadHistory();
  }

  void _showSuccessSnackbar(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$name logged to ${_capitalize(widget.mealType)}',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        foregroundColor: c.onBackground,
        title: Text(
          'Log ${_capitalize(widget.mealType)}',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scanBarcode,
            tooltip: 'Scan Barcode',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: c.onBackground),
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Search foods, brands, flavors...',
                hintStyle: GoogleFonts.inter(color: c.inactive),
                prefixIcon: Icon(Icons.search, color: c.inactive),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: c.inactive),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _results = [];
                            _hasSearched = false;
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _scanBarcode,
                icon: const Icon(Icons.qr_code_scanner, size: 20),
                label: Text(
                  'Scan Barcode',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _error != null
                ? _buildError()
                : _hasSearched
                ? _buildSearchResults()
                : _buildDefaultView(),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.orange, size: 48),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: GoogleFonts.inter(color: c.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _error = null),
              child: Text(
                'Dismiss',
                style: GoogleFonts.inter(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultView() {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'History',
              style: GoogleFonts.spaceGrotesk(
                color: c.onBackground,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            TextButton.icon(
              onPressed: _loadHistory,
              icon: Icon(
                Icons.refresh,
                color: c.muted,
                size: 14,
              ),
              label: Text(
                'Refresh',
                style: GoogleFonts.inter(
                  color: c.muted,
                  fontSize: 12,
                ),
              ),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoadingHistory)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ),
          )
        else if (_history.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.history, color: c.borderLight, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'No history yet',
                    style: GoogleFonts.inter(color: c.inactive),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Search for foods above to get started',
                    style: GoogleFonts.inter(
                      color: c.borderLight,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ..._history.map((food) => _buildHistoryCard(food)),
      ],
    );
  }

  Widget _buildHistoryCard(FoodItem food) {
    final c = context.colors;
    final isLogging = _loggingIds.contains(food.id);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Dismissible(
      key: Key('hist_${food.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) async {
        setState(() => _history.remove(food));
        if (uid != null) {
          await _firestore.deleteFoodLog(uid, food.id);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    food.name,
                    style: GoogleFonts.inter(
                      color: c.onBackground,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${food.totalCalories.round()} kcal · ${food.quantity.toStringAsFixed(0)} × ${food.servingSize.round()}${food.servingSizeUnit}',
                    style: GoogleFonts.inter(
                      color: c.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    children: [
                      _macroTag(
                        'P: ${food.totalProtein.round()}g',
                        AppColors.primary,
                      ),
                      _macroTag(
                        'C: ${food.totalCarbs.round()}g',
                        AppColors.purple,
                      ),
                      _macroTag(
                        'F: ${food.totalFat.round()}g',
                        AppColors.orange,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: isLogging ? null : () => _quickAddHistory(food),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(isLogging ? 0.05 : 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(isLogging ? 0.2 : 0.4),
                  ),
                ),
                child: isLogging
                    ? const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.add,
                        color: AppColors.primary,
                        size: 20,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_results.isEmpty) {
      final c = context.colors;
      // Surface the hidden-count notice even on an empty list, so a fully
      // filtered-out result set isn't mysterious.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _hiddenCount > 0
                ? 'No results match your dietary preferences.'
                : 'No results found.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: c.inactive),
          ),
        ),
      );
    }
    final hasBanner = _hiddenCount > 0;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _results.length + (hasBanner ? 1 : 0),
      itemBuilder: (context, i) {
        if (hasBanner && i == 0) return _buildHiddenNotice();
        return _buildSearchCard(_results[i - (hasBanner ? 1 : 0)]);
      },
    );
  }

  Widget _buildHiddenNotice() {
    final c = context.colors;
    final plural = _hiddenCount == 1 ? 'item' : 'items';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 2),
      child: Row(
        children: [
          Icon(Icons.filter_alt_outlined,
              size: 14, color: c.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$_hiddenCount $plural hidden by your dietary preferences',
              style: GoogleFonts.inter(
                color: c.muted,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchCard(_USDAFoodItem food) {
    final c = context.colors;
    return GestureDetector(
      onTap: () => _quickAddUSDA(food),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    food.name,
                    style: GoogleFonts.inter(
                      color: c.onBackground,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (food.brandOwner.isNotEmpty)
                    Text(
                      food.brandOwner,
                      style: GoogleFonts.inter(
                        color: c.inactive,
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      _macroTag(
                        '${food.calories.round()} kcal',
                        AppColors.orange,
                      ),
                      _macroTag(
                        'P: ${food.protein.round()}g',
                        AppColors.primary,
                      ),
                      _macroTag(
                        'C: ${food.carbs.round()}g',
                        AppColors.purple,
                      ),
                      _macroTag(
                        'F: ${food.fat.round()}g',
                        AppColors.yellow,
                      ),
                    ],
                  ),
                  Text(
                    'per ${food.servingSize.round()}${food.servingUnit}',
                    style: GoogleFonts.inter(
                      color: c.subtle,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add, color: AppColors.primary, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPortionDialog(_USDAFoodItem food) async {
    final c = context.colors;
    final portionController = TextEditingController(
      text: food.servingSize.round().toString(),
    );
    double portion = food.servingSize;
    await showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  food.name,
                  style: GoogleFonts.spaceGrotesk(
                    color: c.onBackground,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Text(
                  'Portion (g)',
                  style: GoogleFonts.inter(color: c.muted),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: portionController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: c.onBackground),
                  onChanged: (v) => setModalState(
                    () => portion = double.tryParse(v) ?? food.servingSize,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: c.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    suffixText: 'g',
                    suffixStyle: GoogleFonts.inter(
                      color: c.muted,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _macroRow(
                  food.calories * portion / food.servingSize,
                  food.protein * portion / food.servingSize,
                  food.carbs * portion / food.servingSize,
                  food.fat * portion / food.servingSize,
                  fiber: food.fiber * portion / food.servingSize,
                  sodium: food.sodium * portion / food.servingSize,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _logUSDAFood(food, portion);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: c.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Log to ${_capitalize(widget.mealType)}',
                      style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Shared widgets ───────────────────────────────────────────────────────────

  Widget _macroRow(
    double cal,
    double protein,
    double carbs,
    double fat, {
    double fiber = 0,
    double sodium = 0,
  }) {
    final c = context.colors;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.inputFill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _nutriPreview(
                'Calories',
                '${cal.round()}',
                AppColors.orange,
              ),
              _nutriPreview(
                'Protein',
                '${protein.round()}g',
                AppColors.primary,
              ),
              _nutriPreview(
                'Carbs',
                '${carbs.round()}g',
                AppColors.purple,
              ),
              _nutriPreview('Fat', '${fat.round()}g', AppColors.yellow),
            ],
          ),
        ),
        if (fiber > 0 || sodium > 0) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.inputFill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _nutriPreview(
                  'Fiber',
                  '${fiber.round()}g',
                  AppColors.cyan,
                ),
                _nutriPreview(
                  'Sodium',
                  '${sodium.round()}mg',
                  AppColors.orange,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _macroTag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: GoogleFonts.inter(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _nutriPreview(String label, String value, Color color) => Column(
    children: [
      Text(
        value,
        style: GoogleFonts.spaceGrotesk(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      Text(
        label,
        style: GoogleFonts.inter(color: context.colors.disabled, fontSize: 10),
      ),
    ],
  );

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── USDA model ────────────────────────────────────────────────────────────────

class _USDAFoodItem {
  final String fdcId;
  final String name;
  final String brandOwner;
  final double servingSize;
  final String servingUnit;
  // Macros
  final double calories, protein, carbs, fat, fiber, sugar, sodium;
  // Vitamins
  final double vitaminA, vitaminC, vitaminD, vitaminE, vitaminK;
  final double vitaminB6, vitaminB12, folate;
  // Minerals
  final double iron, calcium, magnesium, potassium, zinc, phosphorus;

  _USDAFoodItem({
    required this.fdcId,
    required this.name,
    required this.brandOwner,
    required this.servingSize,
    required this.servingUnit,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
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
    required this.iron,
    required this.calcium,
    required this.magnesium,
    required this.potassium,
    required this.zinc,
    required this.phosphorus,
  });
}
