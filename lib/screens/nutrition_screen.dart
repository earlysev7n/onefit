import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../services/firestore_service.dart';
import '../providers/profile_provider.dart';
import '../models/food_item.dart';
import '../app_clock.dart';
import '../theme/app_colors.dart';
import '../theme/responsive.dart';
import 'food_log_screen.dart';

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  DateTime _selectedDate = appNow();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        foregroundColor: c.onBackground,
        title: Text(
          'Nutrition',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today, size: 20),
            onPressed: () => _selectDate(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildDateSelector(),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      indicator: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: c.onPrimary,
                      unselectedLabelColor: c.muted,
                      labelStyle: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      tabs: const [
                        Tab(text: 'Calories'),
                        Tab(text: 'Nutrients'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _CaloriesTab(
                          selectedDate: _selectedDate,
                          key: ValueKey('cal_$_selectedDate'),
                        ),
                        _NutrientsTab(
                          selectedDate: _selectedDate,
                          key: ValueKey('nutrients_$_selectedDate'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    final now = appNow();
    final today = DateTime(now.year, now.month, now.day);
    final selected = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final isToday = selected == today;

    final c = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, color: c.onBackground),
            onPressed: () {
              setState(() {
                _selectedDate = _selectedDate.subtract(const Duration(days: 1));
              });
            },
          ),
          Text(
            _formatDate(_selectedDate),
            style: GoogleFonts.spaceGrotesk(
              color: c.onBackground,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          if (!isToday)
            IconButton(
              icon: Icon(Icons.chevron_right, color: c.onBackground),
              onPressed: () {
                setState(() {
                  final tomorrow = _selectedDate.add(const Duration(days: 1));
                  if (tomorrow.isBefore(
                    appNow().add(const Duration(days: 1)),
                  )) {
                    _selectedDate = tomorrow;
                  }
                });
              },
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = appNow();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final selected = DateTime(date.year, date.month, date.day);

    if (selected == today) return 'Today';
    if (selected == yesterday) return 'Yesterday';

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: appNow().subtract(const Duration(days: 365)),
      lastDate: appNow(),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final base = isDark ? ThemeData.dark() : ThemeData.light();
        final c = context.colors;
        return Theme(
          data: base.copyWith(
            colorScheme:
                (isDark ? const ColorScheme.dark() : const ColorScheme.light())
                    .copyWith(primary: AppColors.primary, surface: c.surface),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }
}

// ─── CALORIES TAB ─────────────────────────────────────────────────────────────
class _CaloriesTab extends StatefulWidget {
  final DateTime selectedDate;
  const _CaloriesTab({super.key, required this.selectedDate});

  @override
  State<_CaloriesTab> createState() => _CaloriesTabState();
}

class _CaloriesTabState extends State<_CaloriesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => false;

  void _navigateToMealPlan(BuildContext context, String mealType) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FoodLogScreen(mealType: mealType)),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.colors;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Center(
        child: Text('Not logged in', style: TextStyle(color: c.onBackground)),
      );
    }

    return StreamBuilder<List<FoodItem>>(
      stream: FirestoreService().streamFoodLogsForDate(
        user.uid,
        widget.selectedDate,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final foodLogs = snapshot.data ?? [];
        final totals = _calculateTotals(foodLogs);

        final profileProvider = context.watch<ProfileProvider>();
        final calorieGoal = profileProvider.dailyEffectiveGoal;
        final eaten = totals['calories'] ?? 0;
        final remaining = calorieGoal - eaten;

        return ResponsiveBody(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 20),
                SizedBox(
                  width: 180,
                  height: 180,
                  child: CustomPaint(
                    painter: _RingPainter(
                      eaten / calorieGoal,
                      AppColors.primary,
                      ringBackground: c.inputFill,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${remaining.clamp(0, calorieGoal)}',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              color: c.onBackground,
                            ),
                          ),
                          Text(
                            'kcal left',
                            style: GoogleFonts.inter(color: c.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    _buildCalCard('Goal', '$calorieGoal', c.inactive),
                    const SizedBox(width: 12),
                    _buildCalCard('Eaten', '$eaten', AppColors.orange),
                    const SizedBox(width: 12),
                    _buildCalCard(
                      'Remaining',
                      '${remaining.clamp(0, calorieGoal)}',
                      AppColors.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildMealRow(
                  context,
                  label: 'Breakfast',
                  mealType: 'breakfast',
                  calories: totals['breakfast'] ?? 0,
                ),
                const SizedBox(height: 8),
                _buildMealRow(
                  context,
                  label: 'Lunch',
                  mealType: 'lunch',
                  calories: totals['lunch'] ?? 0,
                ),
                const SizedBox(height: 8),
                _buildMealRow(
                  context,
                  label: 'Dinner',
                  mealType: 'dinner',
                  calories: totals['dinner'] ?? 0,
                ),
                const SizedBox(height: 8),
                _buildMealRow(
                  context,
                  label: 'Snacks',
                  mealType: 'snack',
                  calories: totals['snack'] ?? 0,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Map<String, int> _calculateTotals(List<FoodItem> logs) {
    int totalCalories = 0, breakfast = 0, lunch = 0, dinner = 0, snack = 0;
    for (var food in logs) {
      final cal = food.totalCalories.round();
      totalCalories += cal;
      switch (food.mealType.toLowerCase()) {
        case 'breakfast':
          breakfast += cal;
          break;
        case 'lunch':
          lunch += cal;
          break;
        case 'dinner':
          dinner += cal;
          break;
        default:
          snack += cal;
      }
    }
    return {
      'calories': totalCalories,
      'breakfast': breakfast,
      'lunch': lunch,
      'dinner': dinner,
      'snack': snack,
    };
  }

  Widget _buildCalCard(String label, String value, Color color) {
    final c = context.colors;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(label, style: GoogleFonts.inter(color: c.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildMealRow(
    BuildContext context, {
    required String label,
    required String mealType,
    required int calories,
  }) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _navigateToMealPlan(context, mealType),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  color: c.onBackground,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text('$calories kcal', style: GoogleFonts.inter(color: c.muted)),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: c.inactive, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── NUTRIENTS TAB ────────────────────────────────────────────────────────────
class _NutrientsTab extends StatefulWidget {
  final DateTime selectedDate;
  const _NutrientsTab({super.key, required this.selectedDate});

  @override
  State<_NutrientsTab> createState() => _NutrientsTabState();
}

class _NutrientsTabState extends State<_NutrientsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => false;

  // ── RDA reference values ────────────────────────────────────────────────────
  // Based on average adult daily values (FDA / WHO)
  // ignore: unused_field
  static const Map<String, Map<String, dynamic>> _rdas = {
    // Macros
    'protein': {'goal': 50, 'unit': 'g', 'color': 0xFF00C97B, 'isLimit': false},
    'carbs': {'goal': 275, 'unit': 'g', 'color': 0xFF6C63FF, 'isLimit': false},
    'fat': {'goal': 78, 'unit': 'g', 'color': 0xFFFF6B35, 'isLimit': false},
    // Fiber & Sugars
    'fiber': {'goal': 28, 'unit': 'g', 'color': 0xFF00B4D8, 'isLimit': false},
    'sugar': {'goal': 50, 'unit': 'g', 'color': 0xFFFFD60A, 'isLimit': true},
    // Minerals
    'sodium': {
      'goal': 2300,
      'unit': 'mg',
      'color': 0xFFFF4D6D,
      'isLimit': true,
    },
    'calcium': {
      'goal': 1000,
      'unit': 'mg',
      'color': 0xFF4CC9F0,
      'isLimit': false,
    },
    'iron': {'goal': 18, 'unit': 'mg', 'color': 0xFFE07A5F, 'isLimit': false},
    'magnesium': {
      'goal': 400,
      'unit': 'mg',
      'color': 0xFF81B29A,
      'isLimit': false,
    },
    'potassium': {
      'goal': 4700,
      'unit': 'mg',
      'color': 0xFFF2CC8F,
      'isLimit': false,
    },
    'zinc': {'goal': 11, 'unit': 'mg', 'color': 0xFF9B8EA0, 'isLimit': false},
    'phosphorus': {
      'goal': 700,
      'unit': 'mg',
      'color': 0xFF7EC8E3,
      'isLimit': false,
    },
    // Vitamins
    'vitaminA': {
      'goal': 900,
      'unit': 'mcg',
      'color': 0xFFFF9F1C,
      'isLimit': false,
    },
    'vitaminC': {
      'goal': 90,
      'unit': 'mg',
      'color': 0xFFFFBF00,
      'isLimit': false,
    },
    'vitaminD': {
      'goal': 20,
      'unit': 'mcg',
      'color': 0xFFFFC300,
      'isLimit': false,
    },
    'vitaminE': {
      'goal': 15,
      'unit': 'mg',
      'color': 0xFFCB9CF2,
      'isLimit': false,
    },
    'vitaminK': {
      'goal': 120,
      'unit': 'mcg',
      'color': 0xFF80ED99,
      'isLimit': false,
    },
    'vitaminB6': {
      'goal': 1.7,
      'unit': 'mg',
      'color': 0xFFA8DADC,
      'isLimit': false,
    },
    'vitaminB12': {
      'goal': 2.4,
      'unit': 'mcg',
      'color': 0xFFB5838D,
      'isLimit': false,
    },
    'folate': {
      'goal': 400,
      'unit': 'mcg',
      'color': 0xFF52B788,
      'isLimit': false,
    },
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.colors;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Center(
        child: Text('Not logged in', style: TextStyle(color: c.onBackground)),
      );
    }

    return StreamBuilder<List<FoodItem>>(
      stream: FirestoreService().streamFoodLogsForDate(
        user.uid,
        widget.selectedDate,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }

        final foodLogs = snapshot.data ?? [];
        final n = _sumNutrients(foodLogs);

        final profileProvider = context.watch<ProfileProvider>();
        final effectiveMacros = profileProvider.effectiveMacroGoals;
        final macroGoals = effectiveMacros.isEmpty
            ? <String, int>{}
            : {
                'protein': effectiveMacros['protein'] ?? 50,
                'carbs': effectiveMacros['carbs'] ?? 275,
                'fat': effectiveMacros['fat'] ?? 78,
                'fiber': effectiveMacros['fiber'] ?? 28,
                'sugar': effectiveMacros['sugar'] ?? 50,
                'sodium': effectiveMacros['sodium'] ?? 2300,
              };

        // Merge profile macro goals into RDA map for macros only
        int macroGoal(String key, int rdaFallback) =>
            macroGoals[key] ?? rdaFallback;

        return ResponsiveBody(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Macronutrients ────────────────────────────────────────
                _sectionHeader('Macronutrients'),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Protein',
                  desc: 'Builds & repairs muscle tissue',
                  current: n['protein']!,
                  goal: macroGoal('protein', 50).toDouble(),
                  unit: 'g',
                  color: AppColors.protein,
                ),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Carbohydrates',
                  desc: 'Primary energy source',
                  current: n['carbs']!,
                  goal: macroGoal('carbs', 275).toDouble(),
                  unit: 'g',
                  color: AppColors.carbs,
                ),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Fat',
                  desc: 'Hormones & fat-soluble vitamins',
                  current: n['fat']!,
                  goal: macroGoal('fat', 78).toDouble(),
                  unit: 'g',
                  color: AppColors.fat,
                ),

                // ── Fiber & Sugars ────────────────────────────────────────
                const SizedBox(height: 24),
                _sectionHeader('Fiber & Sugars'),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Dietary Fiber',
                  desc: 'Gut health & blood sugar control',
                  current: n['fiber']!,
                  goal: macroGoal('fiber', 28).toDouble(),
                  unit: 'g',
                  color: AppColors.fiber,
                ),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Sugar',
                  desc: 'Keep below daily limit',
                  current: n['sugar']!,
                  goal: macroGoal('sugar', 50).toDouble(),
                  unit: 'g',
                  color: AppColors.warning,
                  isLimit: true,
                ),

                // ── Minerals ─────────────────────────────────────────────
                const SizedBox(height: 24),
                _sectionHeader('Minerals'),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Sodium',
                  desc: 'Fluid balance & nerve function',
                  current: n['sodium']!,
                  goal: macroGoal('sodium', 2300).toDouble(),
                  unit: 'mg',
                  color: const Color(0xFFFF4D6D),
                  isLimit: true,
                ),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Calcium',
                  desc: 'Bone & teeth strength',
                  current: n['calcium']!,
                  goal: 1000,
                  unit: 'mg',
                  color: const Color(0xFF4CC9F0),
                ),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Iron',
                  desc: 'Oxygen transport in blood',
                  current: n['iron']!,
                  goal: 18,
                  unit: 'mg',
                  color: const Color(0xFFE07A5F),
                ),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Magnesium',
                  desc: 'Muscle & nerve function',
                  current: n['magnesium']!,
                  goal: 400,
                  unit: 'mg',
                  color: const Color(0xFF81B29A),
                ),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Potassium',
                  desc: 'Heart & muscle contractions',
                  current: n['potassium']!,
                  goal: 4700,
                  unit: 'mg',
                  color: const Color(0xFFF2CC8F),
                ),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Zinc',
                  desc: 'Immune system & wound healing',
                  current: n['zinc']!,
                  goal: 11,
                  unit: 'mg',
                  color: const Color(0xFF9B8EA0),
                ),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Phosphorus',
                  desc: 'Bone formation & energy production',
                  current: n['phosphorus']!,
                  goal: 700,
                  unit: 'mg',
                  color: const Color(0xFF7EC8E3),
                ),

                // Vitamins
                const SizedBox(height: 24),
                _sectionHeader('Vitamins'),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Vitamin A',
                  desc: 'Vision, immunity & skin health',
                  current: n['vitaminA']!,
                  goal: 900,
                  unit: 'mcg',
                  color: const Color(0xFFFF9F1C),
                ),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Vitamin C',
                  desc: 'Antioxidant & collagen synthesis',
                  current: n['vitaminC']!,
                  goal: 90,
                  unit: 'mg',
                  color: const Color(0xFFFFBF00),
                ),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Vitamin D',
                  desc: 'Calcium absorption & bone health',
                  current: n['vitaminD']!,
                  goal: 20,
                  unit: 'mcg',
                  color: const Color(0xFFFFC300),
                ),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Vitamin E',
                  desc: 'Antioxidant & cell protection',
                  current: n['vitaminE']!,
                  goal: 15,
                  unit: 'mg',
                  color: const Color(0xFFCB9CF2),
                ),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Vitamin K',
                  desc: 'Blood clotting & bone metabolism',
                  current: n['vitaminK']!,
                  goal: 120,
                  unit: 'mcg',
                  color: const Color(0xFF80ED99),
                ),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Vitamin B6',
                  desc: 'Protein metabolism & brain function',
                  current: n['vitaminB6']!,
                  goal: 1.7,
                  unit: 'mg',
                  color: const Color(0xFFA8DADC),
                ),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Vitamin B12',
                  desc: 'Nerve function & red blood cells',
                  current: n['vitaminB12']!,
                  goal: 2.4,
                  unit: 'mcg',
                  color: const Color(0xFFB5838D),
                ),
                const SizedBox(height: 10),
                _nutrientCard(
                  name: 'Folate',
                  desc: 'DNA synthesis & cell division',
                  current: n['folate']!,
                  goal: 400,
                  unit: 'mcg',
                  color: const Color(0xFF52B788),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Map<String, double> _sumNutrients(List<FoodItem> logs) {
    double protein = 0, carbs = 0, fat = 0, fiber = 0, sugar = 0;
    double sodium = 0, calcium = 0, iron = 0, magnesium = 0;
    double potassium = 0, zinc = 0, phosphorus = 0;
    double vitaminA = 0, vitaminC = 0, vitaminD = 0, vitaminE = 0;
    double vitaminK = 0, vitaminB6 = 0, vitaminB12 = 0, folate = 0;

    for (var f in logs) {
      protein += f.totalProtein;
      carbs += f.totalCarbs;
      fat += f.totalFat;
      fiber += f.totalFiber;
      sugar += f.totalSugar;
      sodium += f.totalSodium;
      calcium += f.totalCalcium;
      iron += f.totalIron;
      magnesium += f.totalMagnesium;
      potassium += f.totalPotassium;
      zinc += f.totalZinc;
      phosphorus += f.totalPhosphorus;
      vitaminA += f.totalVitaminA;
      vitaminC += f.totalVitaminC;
      vitaminD += f.totalVitaminD;
      vitaminE += f.totalVitaminE;
      vitaminK += f.totalVitaminK;
      vitaminB6 += f.totalVitaminB6;
      vitaminB12 += f.totalVitaminB12;
      folate += f.totalFolate;
    }

    return {
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'fiber': fiber,
      'sugar': sugar,
      'sodium': sodium,
      'calcium': calcium,
      'iron': iron,
      'magnesium': magnesium,
      'potassium': potassium,
      'zinc': zinc,
      'phosphorus': phosphorus,
      'vitaminA': vitaminA,
      'vitaminC': vitaminC,
      'vitaminD': vitaminD,
      'vitaminE': vitaminE,
      'vitaminK': vitaminK,
      'vitaminB6': vitaminB6,
      'vitaminB12': vitaminB12,
      'folate': folate,
    };
  }

  Widget _sectionHeader(String title) {
    final c = context.colors;
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.spaceGrotesk(
        color: c.muted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }

  /// Formats a double value: shows 1 decimal if < 10, else integer
  String _fmt(double v, String unit) {
    if (unit == 'g' || unit == 'mg' || unit == 'mcg') {
      if (v < 10) return v.toStringAsFixed(1);
      return v.round().toString();
    }
    return v.toStringAsFixed(1);
  }

  Widget _nutrientCard({
    required String name,
    required String desc,
    required double current,
    required double goal,
    required String unit,
    required Color color,
    bool isLimit = false,
  }) {
    final c = context.colors;
    final progress = goal > 0 ? (current / goal).clamp(0.0, 1.0) : 0.0;
    final isOver = isLimit && current > goal;
    final barColor = isOver ? AppColors.overTarget : color;

    String statusText;
    if (isLimit) {
      if (isOver) {
        statusText = 'Over by ${_fmt(current - goal, unit)}$unit';
      } else {
        statusText = '${_fmt(goal - current, unit)}$unit under limit';
      }
    } else {
      statusText = '${(progress * 100).round()}%';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.spaceGrotesk(
                        color: c.onBackground,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      style: GoogleFonts.inter(color: c.inactive, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: _fmt(current, unit),
                          style: GoogleFonts.spaceGrotesk(
                            color: isOver
                                ? AppColors.overTarget
                                : c.onBackground,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        TextSpan(
                          text: ' / ${_fmt(goal, unit)}$unit',
                          style: GoogleFonts.inter(
                            color: c.inactive,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusText,
                    style: GoogleFonts.inter(
                      color: isOver ? AppColors.overTarget : barColor,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: c.inputFill,
              valueColor: AlwaysStoppedAnimation(barColor),
              minHeight: 7,
            ),
          ),
        ],
      ),
    );
  }
}

//  RING PAINTER
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color ringBackground;
  _RingPainter(
    this.progress,
    this.color, {
    this.ringBackground = const Color(0xFF222222),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    final bg = Paint()
      ..color = ringBackground
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bg);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.ringBackground != ringBackground;
}
