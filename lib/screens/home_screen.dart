import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/user_profile.dart';
import '../models/food_item.dart';
import '../models/workout_log.dart';
import '../providers/plan_provider.dart';
import '../providers/profile_provider.dart';
import '../app_clock.dart';
import 'plans_screen.dart';
import 'progress_screen.dart';
import 'profile_screen.dart';
import 'nutrition_screen.dart';
import 'food_log_screen.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

final plansScreenKey = GlobalKey<PlansScreenState>();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    final uid = AuthService().currentUser?.uid;
    if (uid != null) {
      context.read<ProfileProvider>().load(uid);
    }
  }

  void _showMealTypeSelector({bool autoScan = false}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              autoScan ? 'Select Meal Type for Barcode' : 'Select Meal Type',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            _buildMealTypeOption('Breakfast', autoScan: autoScan),
            const SizedBox(height: 10),
            _buildMealTypeOption('Lunch', autoScan: autoScan),
            const SizedBox(height: 10),
            _buildMealTypeOption('Dinner', autoScan: autoScan),
            const SizedBox(height: 10),
            _buildMealTypeOption('Snack', autoScan: autoScan),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildMealTypeOption(String mealType, {bool autoScan = false}) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FoodLogScreen(
              mealType: mealType.toLowerCase(),
              autoScan: autoScan,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF222222),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                mealType,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF444444)),
          ],
        ),
      ),
    );
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildAddOption(
                  Icons.fitness_center_rounded,
                  'Log\nWorkout',
                  const Color(0xFF00C97B),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _currentIndex = 1);
                  },
                ),
                _buildAddOption(
                  Icons.restaurant_menu_rounded,
                  'Log\nMeal',
                  const Color(0xFFFF6B35),
                  onTap: () {
                    Navigator.pop(context);
                    _showMealTypeSelector();
                  },
                ),
                _buildAddOption(
                  FontAwesomeIcons.barcode,
                  'Scan\nBarcode',
                  const Color(0xFF6C63FF),
                  onTap: () {
                    Navigator.pop(context);
                    _showMealTypeSelector(autoScan: true);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildAddOption(
    IconData icon,
    String label,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<bool> _onBackPress() async {
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return false;
    } else {
      final now = DateTime.now();
      if (_lastBackPressTime == null ||
          now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
        _lastBackPressTime = now;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Press back again to exit',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: const Color(0xFF00C97B),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        return false;
      } else {
        return true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<ProfileProvider>();
    final profile = profileProvider.profile;
    final isLoading = profileProvider.isLoading && profile == null;
    final screens = [
      _HomeDashboard(
        profile: profile,
        isLoading: isLoading,
        onGoToPlans: () => setState(() => _currentIndex = 1),
      ),
      PlansScreen(key: plansScreenKey),
      const SizedBox(),
      const ProgressScreen(),
      const ProfileScreen(),
    ];

    return WillPopScope(
      onWillPop: _onBackPress,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        body: screens[_currentIndex],
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF111111),
            border: Border(top: BorderSide(color: Color(0xFF222222))),
          ),
          child: SafeArea(
            child: SizedBox(
              height: 60,
              child: Row(
                children: [
                  _buildNavItem(0, Icons.home_rounded, 'Home'),
                  _buildNavItem(1, Icons.calendar_month_rounded, 'Plans'),
                  Expanded(
                    child: GestureDetector(
                      onTap: _showAddSheet,
                      child: Center(
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00C97B),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Colors.black,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _buildNavItem(3, Icons.bar_chart_rounded, 'Progress'),
                  _buildNavItem(4, Icons.person_rounded, 'Profile'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isActive = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentIndex = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive
                  ? const Color(0xFF00C97B)
                  : const Color(0xFF555555),
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: isActive
                    ? const Color(0xFF00C97B)
                    : const Color(0xFF555555),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── HOME DASHBOARD ───────────────────────────────────────────────────────────
class _HomeDashboard extends StatelessWidget {
  final UserProfile? profile;
  final bool isLoading;
  final VoidCallback onGoToPlans;

  const _HomeDashboard({
    required this.profile,
    required this.isLoading,
    required this.onGoToPlans,
  });

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _getDate() {
    final now = appNow();
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
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  String _getDayName() {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[appNow().weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading)
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00C97B)),
      );

    final user = FirebaseAuth.instance.currentUser;
    if (user == null)
      return const Center(
        child: Text('Not logged in', style: TextStyle(color: Colors.white)),
      );

    final planProvider = context.watch<PlanProvider>();
    final calorieGoal = profile?.calorieGoal ?? 2000;
    final macros = profile?.macroGoals ?? {};
    final todayWorkout = planProvider.todayWorkout;
    final todayName = _getDayName();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: StreamBuilder<List<FoodItem>>(
          stream: FirestoreService().streamTodayFoodLogs(user.uid),
          builder: (context, snapshot) {
            final foodLogs = snapshot.data ?? [];

            // Aggregate totals and per-meal calories from Firestore stream
            double caloriesEaten = 0;
            double proteinEaten = 0;
            final mealsMap = <String, double>{
              'breakfast': 0,
              'lunch': 0,
              'dinner': 0,
              'snack': 0,
            };

            for (final food in foodLogs) {
              caloriesEaten += food.totalCalories;
              proteinEaten += food.totalProtein;
              final mt = food.mealType.toLowerCase();
              if (mealsMap.containsKey(mt))
                mealsMap[mt] = mealsMap[mt]! + food.totalCalories;
            }

            final caloriesRemaining = (calorieGoal - caloriesEaten.round())
                .clamp(0, calorieGoal);
            final progress = (caloriesEaten / calorieGoal).clamp(0.0, 1.0);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getGreeting(),
                          style: GoogleFonts.inter(
                            color: const Color(0xFF888888),
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          profile?.name ?? 'Athlete',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _getDate(),
                      style: GoogleFonts.inter(
                        color: const Color(0xFF888888),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Calorie ring card ────────────────────────────────────────
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NutritionScreen()),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 100,
                          height: 100,
                          child: CustomPaint(
                            painter: _CaloriePainter(progress),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$caloriesRemaining',
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    'left',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: const Color(0xFF888888),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            children: [
                              _buildMacroRow(
                                'Goal',
                                '$calorieGoal kcal',
                                const Color(0xFF555555),
                              ),
                              const SizedBox(height: 8),
                              _buildMacroRow(
                                'Eaten',
                                '${caloriesEaten.round()} kcal',
                                const Color(0xFFFF6B35),
                              ),
                              const SizedBox(height: 8),
                              _buildMacroRow(
                                'Remaining',
                                '${caloriesRemaining.round()} kcal',
                                const Color(0xFF00C97B),
                              ),
                              const SizedBox(height: 8),
                              _buildMacroRow(
                                'Protein',
                                '${proteinEaten.round()}g / ${macros['protein'] ?? 0}g',
                                const Color(0xFF00B4D8),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.chevron_right,
                          color: Color(0xFF444444),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Today's Meals — driven by Firestore stream ───────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Today's Meals",
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        onGoToPlans();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          plansScreenKey.currentState?.switchToMealTab();
                        });
                      },
                      child: Text(
                        'See all',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF00C97B),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Breakfast row
                _buildMealRow(
                  context: context,
                  meal: 'Breakfast',
                  mealType: 'breakfast',
                  calories: mealsMap['breakfast']!,
                  icon: Icons.wb_sunny_rounded,
                  color: const Color(0xFFFFD60A),
                  foodLogs: foodLogs
                      .where((f) => f.mealType.toLowerCase() == 'breakfast')
                      .toList(),
                ),
                const SizedBox(height: 8),

                // Lunch row
                _buildMealRow(
                  context: context,
                  meal: 'Lunch',
                  mealType: 'lunch',
                  calories: mealsMap['lunch']!,
                  icon: Icons.lunch_dining_rounded,
                  color: const Color(0xFFFF6B35),
                  foodLogs: foodLogs
                      .where((f) => f.mealType.toLowerCase() == 'lunch')
                      .toList(),
                ),
                const SizedBox(height: 8),

                // Dinner row
                _buildMealRow(
                  context: context,
                  meal: 'Dinner',
                  mealType: 'dinner',
                  calories: mealsMap['dinner']!,
                  icon: Icons.dinner_dining_rounded,
                  color: const Color(0xFF6C63FF),
                  foodLogs: foodLogs
                      .where((f) => f.mealType.toLowerCase() == 'dinner')
                      .toList(),
                ),
                const SizedBox(height: 20),

                // ── Today's Workout ──────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Today's Workout",
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    GestureDetector(
                      onTap: onGoToPlans,
                      child: Text(
                        'See all',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF00C97B),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                StreamBuilder<WorkoutLog?>(
                  stream: FirestoreService().streamWorkoutLogForDate(user.uid, appNow()),
                  builder: (context, workoutSnap) {
                    final workoutLog = workoutSnap.data;
                    return GestureDetector(
                  onTap: onGoToPlans,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(16),
                      border: workoutLog != null
                          ? Border.all(color: const Color(0xFF00C97B).withOpacity(0.4))
                          : null,
                    ),
                    child: todayWorkout == null
                        ? Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF00C97B,
                                  ).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.fitness_center_rounded,
                                  color: Color(0xFF00C97B),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'No workout generated yet',
                                      style: GoogleFonts.spaceGrotesk(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      'Go to Plans to generate',
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFF888888),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Color(0xFF444444),
                              ),
                            ],
                          )
                        : todayWorkout.isRest
                        ? Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF444444,
                                  ).withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.bedtime_rounded,
                                  color: Color(0xFF888888),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Rest Day',
                                      style: GoogleFonts.spaceGrotesk(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      'Recovery is part of the plan',
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFF888888),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF00C97B,
                                      ).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.fitness_center_rounded,
                                      color: Color(0xFF00C97B),
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$todayName — ${todayWorkout.focus}',
                                          style: GoogleFonts.spaceGrotesk(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          '${todayWorkout.exercises.length} exercises',
                                          style: GoogleFonts.inter(
                                            color: const Color(0xFF888888),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  workoutLog != null
                                      ? const Icon(Icons.check_circle_rounded, color: Color(0xFF00C97B), size: 22)
                                      : const Icon(Icons.chevron_right, color: Color(0xFF444444)),
                                ],
                              ),
                              if (workoutLog != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00C97B).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Completed · ${workoutLog.durationMinutes} min · ${workoutLog.focus}',
                                    style: GoogleFonts.inter(
                                      color: const Color(0xFF00C97B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ] else if (todayWorkout.exercises.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                const Divider(
                                  color: Color(0xFF2E2E2E),
                                  height: 1,
                                ),
                                const SizedBox(height: 10),
                                ...todayWorkout.exercises
                                    .take(2)
                                    .map(
                                      (we) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
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
                                                we.exercise.name,
                                                style: GoogleFonts.inter(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${we.sets}×${we.reps}',
                                              style: GoogleFonts.inter(
                                                color: const Color(0xFF888888),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                if (todayWorkout.exercises.length > 2)
                                  Text(
                                    '+${todayWorkout.exercises.length - 2} more exercises',
                                    style: GoogleFonts.inter(
                                      color: const Color(0xFF555555),
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ],
                          ),
                  ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMacroRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: const Color(0xFF888888),
                fontSize: 13,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // FIX: meal row now reads from Firestore stream (foodLogs), not PlanProvider
  Widget _buildMealRow({
    required BuildContext context,
    required String meal,
    required String mealType,
    required double calories,
    required IconData icon,
    required Color color,
    required List<FoodItem> foodLogs,
  }) {
    final hasData = calories > 0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NutritionScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meal,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (hasData && foodLogs.isNotEmpty)
                    Text(
                      // Show first 2 food names as subtitle
                      foodLogs.take(2).map((f) => f.name).join(', ') +
                          (foodLogs.length > 2
                              ? ' +${foodLogs.length - 2} more'
                              : ''),
                      style: GoogleFonts.inter(
                        color: const Color(0xFF888888),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Text(
              hasData ? '${calories.round()} kcal' : '0 kcal',
              style: GoogleFonts.inter(
                color: hasData
                    ? const Color(0xFF00C97B)
                    : const Color(0xFF888888),
                fontSize: 13,
                fontWeight: hasData ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Color(0xFF444444), size: 18),
          ],
        ),
      ),
    );
  }
}

class _CaloriePainter extends CustomPainter {
  final double progress;
  _CaloriePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final bgPaint = Paint()
      ..color = const Color(0xFF222222)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final fgPaint = Paint()
      ..color = const Color(0xFF00C97B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_CaloriePainter old) => old.progress != progress;
}
