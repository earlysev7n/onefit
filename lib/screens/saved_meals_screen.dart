import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../algorithms/genetic_algorithm.dart';
import '../providers/plan_provider.dart';
import '../providers/profile_provider.dart';
import '../services/firestore_service.dart';
import '../theme/app_colors.dart';

class SavedMealsScreen extends StatefulWidget {
  const SavedMealsScreen({
    super.key,
    this.loggedCalsByMeal = const {},
  });

  final Map<String, double> loggedCalsByMeal;

  @override
  State<SavedMealsScreen> createState() => _SavedMealsScreenState();
}

class _SavedMealsScreenState extends State<SavedMealsScreen> {
  List<SavedMealDoc> _meals = [];
  bool _loading = true;
  String _filter = 'all';

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final meals = await FirestoreService().getSavedMeals(uid);
      if (!mounted) return;
      setState(() => _meals = meals);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<SavedMealDoc> get _filtered =>
      _filter == 'all' ? _meals : _meals.where((m) => m.mealType == _filter).toList();

  Future<void> _delete(SavedMealDoc meal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          'Delete saved meal?',
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          meal.recipeName.isNotEmpty
              ? meal.recipeName
              : '${meal.totalCalories.round()} kcal meal',
          style: GoogleFonts.inter(color: const Color(0xFF888888)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: const Color(0xFF888888))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style: GoogleFonts.inter(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final uid = _uid;
    if (uid == null) return;
    FirestoreService().deleteSavedMeal(uid, meal.id);
    setState(() => _meals.removeWhere((m) => m.id == meal.id));
  }

  Future<void> _addToSlot(SavedMealDoc doc) async {
    final slot = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text(
                'Add to meal slot',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            for (final entry in const {
              'breakfast': 'Breakfast',
              'lunch': 'Lunch',
              'dinner': 'Dinner',
              'snack': 'Snack',
            }.entries)
              ListTile(
                title: Text(
                  entry.value,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, entry.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (slot == null || !mounted) return;

    final hasExisting = (widget.loggedCalsByMeal[slot] ?? 0) > 0;

    if (hasExisting && mounted) {
      final slotLabel = '${slot[0].toUpperCase()}${slot.substring(1)}';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            'Replace $slotLabel?',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'You already have a $slotLabel meal planned. Replace it with this one?',
            style: GoogleFonts.inter(
              color: const Color(0xFF888888),
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Keep current',
                  style: GoogleFonts.inter(color: const Color(0xFF888888))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Replace',
                  style: GoogleFonts.inter(color: AppColors.primary)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final goal =
        context.read<ProfileProvider>().dailyEffectiveGoal.toDouble();
    final budget = GeneticAlgorithm.singleMealBudget(
      goal: goal,
      mealType: slot,
      loggedCalsByMeal: widget.loggedCalsByMeal,
    );

    final scaled = doc.meal
        .copyWith(mealType: slot)
        .scaleToCalories(budget)
        .closeResidual(budget);

    if (!mounted) return;
    await context.read<PlanProvider>().setMeal(
          slot,
          scaled,
          saveToFirestore: true,
          recipeName: doc.recipeName,
        );

    final uid = _uid;
    if (uid != null) {
      FirestoreService().deleteCachedRecipe(uid, slot);
    }

    if (!mounted) return;
    final label =
        '${slot[0].toUpperCase()}${slot.substring(1)}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added to $label'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        title: Text(
          'Saved Meals',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700,
            color: c.onBackground,
          ),
        ),
        iconTheme: IconThemeData(color: c.onBackground),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                for (final t in ['all', 'breakfast', 'lunch', 'dinner', 'snack'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        t == 'all'
                            ? 'All'
                            : '${t[0].toUpperCase()}${t.substring(1)}',
                      ),
                      selected: _filter == t,
                      selectedColor: AppColors.primary,
                      backgroundColor: c.surface,
                      labelStyle: GoogleFonts.inter(
                        fontSize: 12,
                        color: _filter == t ? Colors.black : c.onBackground,
                      ),
                      onSelected: (_) => setState(() => _filter = t),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bookmark_border_rounded,
                                size: 48, color: c.muted),
                            const SizedBox(height: 12),
                            Text(
                              _filter == 'all'
                                  ? 'No saved meals yet'
                                  : 'No saved $_filter meals',
                              style: GoogleFonts.inter(
                                  color: c.muted, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Bookmark a recipe to save it here',
                              style: GoogleFonts.inter(
                                  color: c.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemBuilder: (_, i) => _mealCard(filtered[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _mealCard(SavedMealDoc meal) {
    final name = meal.recipeName.isNotEmpty
        ? meal.recipeName
        : meal.meal.items.map((i) => i.ingredient.name).take(3).join(', ');
    final dateStr = meal.savedAt != null
        ? '${meal.savedAt!.day}/${meal.savedAt!.month}/${meal.savedAt!.year}'
        : '';
    final ingredientNames =
        meal.meal.items.map((i) => i.ingredient.name).toList();

    return Dismissible(
      key: ValueKey(meal.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        await _delete(meal);
        return false;
      },
      child: Card(
        color: const Color(0xFF1A1A1A),
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${meal.mealType[0].toUpperCase()}${meal.mealType.substring(1)}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => _addToSlot(meal),
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      size: 22,
                      color: AppColors.primary,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    tooltip: 'Add to meal slot',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${meal.totalCalories.round()} kcal  ·  '
                'P ${meal.totalProtein.round()}g  '
                'C ${meal.totalCarbs.round()}g  '
                'F ${meal.totalFat.round()}g',
                style: GoogleFonts.inter(
                    fontSize: 13, color: const Color(0xFF888888)),
              ),
              const SizedBox(height: 6),
              Text(
                '${ingredientNames.length} ingredient${ingredientNames.length == 1 ? '' : 's'}: '
                '${ingredientNames.take(4).join(', ')}'
                '${ingredientNames.length > 4 ? '...' : ''}',
                style: GoogleFonts.inter(
                    fontSize: 12, color: const Color(0xFF666666)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (dateStr.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Saved $dateStr',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: const Color(0xFF555555)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
