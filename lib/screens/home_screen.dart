import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import '../algorithms/calorie_tolerance.dart';
import '../algorithms/greedy_algorithm.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/user_profile.dart';
import '../models/food_item.dart';
import '../models/workout_log.dart';
import '../providers/plan_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/progress_provider.dart';
import '../providers/connectivity_provider.dart';
import '../theme/app_colors.dart';
import '../theme/responsive.dart';
import '../app_clock.dart';
import 'plans_screen.dart';
import 'progress_screen.dart';
import 'profile_screen.dart';
import 'nutrition_screen.dart';
import 'food_log_screen.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

final plansScreenKey = GlobalKey<PlansScreenState>();

/// Explains the weekly-adaptive re-balance of today's calorie goal.
///
/// **Auto path** (`force: false`, from `initState`): shown only when a *day*
/// breached the ±5% band and today's goal actually moved — the breach is the
/// trigger, not the size of the resulting nudge, which is small by construction
/// once spread across the remaining days. Then at most once per day, and never
/// after "Don't show again".
///
/// **Forced path** (`force: true`, from tapping the goal badge or status chip):
/// the user explicitly asked for it, so all three guards are skipped.
Future<void> showGoalAdjustmentDialog(
  BuildContext context,
  ProfileProvider pp, {
  bool force = false,
}) async {
  final profile = pp.profile;
  if (profile == null) return;

  final adjusted = pp.dailyEffectiveGoal;
  final base = profile.calorieGoal;
  if (adjusted == base) return; // nothing was re-balanced — nothing to explain

  if (!force) {
    if (!CalorieTolerance.shouldAnnounceGoalShift(
      daysOutOfTolerance: pp.daysOutOfToleranceThisWeek,
      adjusted: adjusted,
      base: base,
    )) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('hideGoalAdjustmentPopup') ?? false) return;

    final today = appToday().toIso8601String().substring(0, 10);
    if (prefs.getString('goalAdjustmentLastShown') == today) return;
    await prefs.setString('goalAdjustmentLastShown', today);
  }

  if (!context.mounted) return;
  final increased = adjusted > base;
  final diff = (adjusted - base).abs();
  final breach = pp.lastBreachKcal;
  final c = context.colors;

  // Open by reassuring, then give the number to act on. The ±5% rule itself is
  // deliberately absent — a modal should say what to eat today, not explain the
  // threshold that produced it (that lives in the Weekly Review).
  //
  // `lastBreachKcal` is one day's deviation while `increased` reflects the net
  // week, so in a mixed week they can disagree ("you were short" above "we
  // trimmed"). Only lead with the breach when the two agree; otherwise open on
  // the target directly.
  final leadsWithBreach =
      breach != null && (breach < 0) == increased && breach != 0;
  final lead = !leadsWithBreach
      ? ''
      : increased
      ? 'You were ${breach.abs().round()} kcal short earlier this week — '
            'no problem. '
      : 'You went ${breach.abs().round()} kcal over earlier this week — '
            'no problem. ';

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        increased ? "We topped up today's goal" : "We trimmed today's goal",
        style: GoogleFonts.spaceGrotesk(
          color: c.onBackground,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        increased
            ? "${lead}Today's target is $adjusted kcal, $diff more than usual, "
                  "so your week still lands where you planned."
            : "${lead}Today's target is $adjusted kcal, $diff less than usual, "
                  "so your week still lands where you planned.",
        style: GoogleFonts.inter(color: c.muted),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final p = await SharedPreferences.getInstance();
            await p.setBool('hideGoalAdjustmentPopup', true);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: Text(
            "Don't show again",
            style: GoogleFonts.inter(color: c.muted),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: Text(
            'Got it',
            style: GoogleFonts.inter(
              color: c.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  DateTime? _lastBackPressTime;
  ConnectivityProvider? _connectivity;
  ProfileProvider? _profileProvider;

  @override
  void initState() {
    super.initState();
    final uid = AuthService().currentUser?.uid;
    _profileProvider = context.read<ProfileProvider>();
    if (uid != null) {
      // Load workout history for the header streak chip (lightweight — logs only).
      context.read<ProgressProvider>().loadWorkoutLogsForStreak(uid);
      final pp = _profileProvider!;
      if (pp.profile != null) {
        // Profile already cached — recompute daily goal in case the day/week changed
        pp.recomputeGoal(uid).then((_) {
          if (mounted) _maybeShowGoalDialog();
        });
      } else {
        pp.load(uid).then((_) {
          if (mounted) _maybeShowGoalDialog();
        });
      }
    }
    // On reconnect, re-sync the adaptive layer: recompute today's weekly-adaptive
    // goal from the now-synced logs. The weekly AdaptationEngine still runs on
    // the next Plans open, guarded by lastAdaptationWeekId.
    _connectivity = context.read<ConnectivityProvider>()
      ..addReconnectListener(_onReconnect);
  }

  Future<void> _onReconnect() async {
    final uid = AuthService().currentUser?.uid;
    if (uid == null) return;
    await _profileProvider?.recomputeGoal(uid);
  }

  @override
  void dispose() {
    _connectivity?.removeReconnectListener(_onReconnect);
    super.dispose();
  }

  Future<void> _maybeShowGoalDialog() async {
    if (!mounted) return;
    await showGoalAdjustmentDialog(context, context.read<ProfileProvider>());
  }

  void _showMealTypeSelector({bool autoScan = false}) {
    final c = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SingleChildScrollView(
        child: Padding(
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
                  color: c.onBackground,
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
      ),
    );
  }

  Widget _buildMealTypeOption(String mealType, {bool autoScan = false}) {
    final c = context.colors;
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
          color: c.inputFill,
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
                  color: c.onBackground,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: c.subtle),
          ],
        ),
      ),
    );
  }

  void _showAddSheet() {
    final c = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SingleChildScrollView(
        child: Padding(
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
                  color: c.onBackground,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildAddOption(
                    Icons.play_circle_fill_rounded,
                    'Start\nWorkout',
                    AppColors.primary,
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _currentIndex = 1);
                      // Plans mounts fresh on tab switch — start today's session
                      // once it's built.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        plansScreenKey.currentState?.startWorkout();
                      });
                    },
                  ),
                  _buildAddOption(
                    Icons.restaurant_menu_rounded,
                    'Log\nMeal',
                    AppColors.orange,
                    onTap: () {
                      Navigator.pop(context);
                      _showMealTypeSelector();
                    },
                  ),
                  _buildAddOption(
                    FontAwesomeIcons.barcode,
                    'Scan\nBarcode',
                    AppColors.purple,
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
      ),
    );
  }

  Widget _buildAddOption(
    IconData icon,
    String label,
    Color color, {
    VoidCallback? onTap,
  }) {
    final c = context.colors;
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
            style: GoogleFonts.inter(color: c.onBackground, fontSize: 12),
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
            backgroundColor: AppColors.primary,
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
    final c = context.colors;
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
        backgroundColor: c.background,
        body: screens[_currentIndex],
        // Bottom nav is hidden only while a workout session runs AND the Plans
        // tab is showing, so the exercise flow is full-screen. Gating on the tab
        // means a back-press to Home always restores the nav (never trapped).
        bottomNavigationBar: ValueListenableBuilder<bool>(
          valueListenable: workoutSessionActive,
          builder: (context, sessionActive, child) {
            if (sessionActive && _currentIndex == 1) {
              return const SizedBox.shrink();
            }
            return child!;
          },
          child: Container(
            decoration: BoxDecoration(
              color: c.surfaceElevated,
              border: Border(top: BorderSide(color: c.inputFill)),
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
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.add,
                              color: c.onPrimary,
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
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final c = context.colors;
    final isActive = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _currentIndex = index);
          // Returning to Home refreshes the streak so a workout just completed
          // on the Plans tab is reflected right away.
          if (index == 0) {
            final uid = AuthService().currentUser?.uid;
            if (uid != null) {
              context.read<ProgressProvider>().loadWorkoutLogsForStreak(uid);
            }
          }
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive ? AppColors.primary : c.inactive,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: isActive ? AppColors.primary : c.inactive,
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

  /// Streak "thunder" chip: bolt + day count. Lights up in the streak colour
  /// only when [active] (today's workout is done); muted otherwise — the number
  /// still shows.
  Widget _streakChip(BuildContext context, int streak, {required bool active}) {
    final color = active ? AppColors.orange : context.colors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? AppColors.orange.withOpacity(0.12)
            : context.colors.inputFill,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 16, color: color),
          const SizedBox(width: 3),
          Text(
            '$streak ${streak == 1 ? 'day' : 'days'}',
            style: GoogleFonts.spaceGrotesk(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
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
    final c = context.colors;
    final streak = context.watch<ProgressProvider>().streakDaysFor(profile);
    // The streak "fire" lights only once today's workout is completed — not at
    // the start of the day just because the running count is positive.
    final todayWorkoutDone =
        context.watch<ProgressProvider>().todayWorkoutLog != null;
    if (isLoading) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Center(
        child: Text('Not logged in', style: TextStyle(color: c.onBackground)),
      );
    }

    final planProvider = context.watch<PlanProvider>();
    final profileProvider = context.watch<ProfileProvider>();
    final calorieGoal = profileProvider.dailyEffectiveGoal;
    final macros = profileProvider.effectiveMacroGoals;
    final todayWorkout = planProvider.todayWorkout(
      anchorWeekday: profileProvider.profile?.createdAt?.weekday ?? 1,
    );
    final todayName = _getDayName();

    return SafeArea(
      child: ResponsiveBody(
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
                if (mealsMap.containsKey(mt)) {
                  mealsMap[mt] = mealsMap[mt]! + food.totalCalories;
                }
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getGreeting(),
                              style: GoogleFonts.inter(
                                color: c.muted,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              profile?.name ?? 'Athlete',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: c.onBackground,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _getDate(),
                            style: GoogleFonts.inter(
                              color: c.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _streakChip(context, streak, active: todayWorkoutDone),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Calorie ring card ────────────────────────────────────────
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NutritionScreen(),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 100,
                            height: 100,
                            child: CustomPaint(
                              painter: _CaloriePainter(
                                progress,
                                trackColor: c.inputFill,
                                isOverBudget: caloriesEaten > calorieGoal,
                                overflowFraction: caloriesEaten > calorieGoal
                                    ? ((caloriesEaten - calorieGoal) /
                                            calorieGoal)
                                        .clamp(0.0, 0.5)
                                    : 0.0,
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      caloriesEaten > calorieGoal
                                          ? '+${(caloriesEaten.round() - calorieGoal).abs()}'
                                          : '${caloriesEaten.round()}',
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: caloriesEaten > calorieGoal
                                            ? Colors.redAccent
                                            : c.onBackground,
                                      ),
                                    ),
                                    Text(
                                      caloriesEaten > calorieGoal
                                          ? 'kcal over'
                                          : 'kcal',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: caloriesEaten > calorieGoal
                                            ? Colors.redAccent
                                            : c.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // 16 not 24 — the column needs the width for a
                          // 4-digit goal alongside the adjustment badge.
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              children: [
                                _buildMacroRow(
                                  'Goal',
                                  '$calorieGoal kcal',
                                  c.inactive,
                                  colors: c,
                                  // "+35" when the weekly-adaptive re-balance
                                  // moved today's target. Visible before
                                  // anything is logged, and tappable to re-open
                                  // the explanation.
                                  badge: _goalAdjustBadge(
                                    context,
                                    profileProvider,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildMacroRow(
                                  'Eaten',
                                  '${caloriesEaten.round()} kcal',
                                  AppColors.orange,
                                  colors: c,
                                ),
                                const SizedBox(height: 8),
                                _buildMacroRow(
                                  caloriesEaten > calorieGoal
                                      ? 'Over'
                                      : 'Remaining',
                                  caloriesEaten > calorieGoal
                                      ? '+${(caloriesEaten.round() - calorieGoal).abs()} kcal'
                                      : '${caloriesRemaining.round()} kcal',
                                  caloriesEaten > calorieGoal
                                      ? Colors.redAccent
                                      : AppColors.primary,
                                  colors: c,
                                ),
                                const SizedBox(height: 8),
                                _buildMacroRow(
                                  'Protein',
                                  '${proteinEaten.round()}g / ${macros['protein'] ?? 0}g',
                                  AppColors.protein,
                                  colors: c,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right, color: c.subtle),
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
                          color: c.onBackground,
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
                            color: AppColors.primary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (caloriesEaten == 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.restaurant_menu_rounded,
                            size: 15,
                            color: c.muted,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Log your first meal to get started.',
                            style: GoogleFonts.inter(
                              color: c.muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Breakfast row
                  _buildMealRow(
                    context: context,
                    meal: 'Breakfast',
                    mealType: 'breakfast',
                    calories: mealsMap['breakfast']!,
                    icon: Icons.wb_sunny_rounded,
                    color: AppColors.yellow,
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
                    color: AppColors.orange,
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
                    color: AppColors.purple,
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
                          color: c.onBackground,
                        ),
                      ),
                      GestureDetector(
                        onTap: onGoToPlans,
                        child: Text(
                          'See all',
                          style: GoogleFonts.inter(
                            color: AppColors.primary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<WorkoutLog?>(
                    stream: FirestoreService().streamWorkoutLogForDate(
                      user.uid,
                      appNow(),
                    ),
                    builder: (context, workoutSnap) {
                      final workoutLog = workoutSnap.data;
                      return GestureDetector(
                        onTap: onGoToPlans,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: workoutLog != null
                                ? Border.all(
                                    color: AppColors.primary.withOpacity(0.4),
                                  )
                                : null,
                          ),
                          child: todayWorkout == null
                              ? Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(
                                          0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.fitness_center_rounded,
                                        color: AppColors.primary,
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
                                            'No workout generated yet',
                                            style: GoogleFonts.spaceGrotesk(
                                              color: c.onBackground,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            'Go to Plans to generate',
                                            style: GoogleFonts.inter(
                                              color: c.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right, color: c.subtle),
                                  ],
                                )
                              : todayWorkout.isRest
                              ? Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: c.subtle.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.bedtime_rounded,
                                        color: c.muted,
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
                                            'Rest Day',
                                            style: GoogleFonts.spaceGrotesk(
                                              color: c.onBackground,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            'Recovery is part of the plan',
                                            style: GoogleFonts.inter(
                                              color: c.muted,
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
                                            color: AppColors.primary
                                                .withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.fitness_center_rounded,
                                            color: AppColors.primary,
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
                                                '$todayName — ${GreedyAlgorithm.focusLabel(todayWorkout.focus)}',
                                                style: GoogleFonts.spaceGrotesk(
                                                  color: c.onBackground,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                '${todayWorkout.exercises.length} exercises',
                                                style: GoogleFonts.inter(
                                                  color: c.muted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        workoutLog != null
                                            ? const Icon(
                                                Icons.check_circle_rounded,
                                                color: AppColors.primary,
                                                size: 22,
                                              )
                                            : Icon(
                                                Icons.chevron_right,
                                                color: c.subtle,
                                              ),
                                      ],
                                    ),
                                    if (workoutLog != null) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withOpacity(
                                            0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'Completed · ${workoutLog.durationMinutes} min · ${GreedyAlgorithm.focusLabel(workoutLog.focus)}',
                                          style: GoogleFonts.inter(
                                            color: AppColors.primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ] else if (todayWorkout
                                        .exercises
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Divider(color: c.border, height: 1),
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
                                                    decoration:
                                                        const BoxDecoration(
                                                          color:
                                                              AppColors.primary,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      we.exercise.name,
                                                      style: GoogleFonts.inter(
                                                        color: c.onBackground,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    '${we.sets}×${we.reps}',
                                                    style: GoogleFonts.inter(
                                                      color: c.muted,
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
                                            color: c.inactive,
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
      ),
    );
  }

  /// The "+35" pill beside the Goal row when the weekly-adaptive redistribution
  /// moved today's target. Returns null when nothing was re-balanced. Tapping
  /// re-opens the explanation, so the reason survives dismissing the dialog —
  /// or a past "Don't show again".
  Widget? _goalAdjustBadge(BuildContext context, ProfileProvider pp) {
    final base = pp.profile?.calorieGoal;
    if (base == null) return null;
    final adjusted = pp.dailyEffectiveGoal;
    if (adjusted == base) return null;

    final up = adjusted > base;
    final diff = (adjusted - base).abs();
    final color = up ? AppColors.primary : AppColors.orange;

    return GestureDetector(
      onTap: () => showGoalAdjustmentDialog(context, pp, force: true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        // Number only — the column is narrow enough that an extra icon pushed
        // the goal value into an ellipsis ("2493 k…"). The tinted pill carries
        // the affordance on its own.
        child: Text(
          '${up ? '+' : '−'}$diff',
          style: GoogleFonts.inter(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildMacroRow(
    String label,
    String value,
    Color color, {
    required AppColors colors,
    Widget? badge,
  }) {
    final c = colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Label side takes all space the value doesn't need, so "Goal" only
        // ellipsizes on a genuinely tiny width — not because a +N badge shares
        // an equal half. The value (a bounded short numeric) is the point of
        // the row, so it keeps its intrinsic width and stays fully readable.
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: c.muted, fontSize: 13),
                ),
              ),
              if (badge != null) ...[const SizedBox(width: 6), badge],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: c.onBackground,
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
    final c = context.colors;
    final hasData = calories > 0;

    return GestureDetector(
      onTap: () {
        onGoToPlans();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          plansScreenKey.currentState?.switchToMealTab();
        });
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
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
                      color: c.onBackground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (hasData && foodLogs.isNotEmpty)
                    Text(
                      () {
                        final recipeName = foodLogs
                            .map((f) => f.recipeName)
                            .firstWhere((n) => n.isNotEmpty, orElse: () => '');
                        if (recipeName.isNotEmpty) return recipeName;
                        return foodLogs.take(2).map((f) => f.name).join(', ') +
                            (foodLogs.length > 2
                                ? ' +${foodLogs.length - 2} more'
                                : '');
                      }(),
                      style: GoogleFonts.inter(color: c.muted, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Text(
              hasData ? '${calories.round()} kcal' : '0 kcal',
              style: GoogleFonts.inter(
                color: hasData ? AppColors.primary : c.muted,
                fontSize: 13,
                fontWeight: hasData ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: c.subtle, size: 18),
          ],
        ),
      ),
    );
  }
}

class _CaloriePainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final bool isOverBudget;
  final double overflowFraction;
  _CaloriePainter(this.progress,
      {required this.trackColor,
      this.isOverBudget = false,
      this.overflowFraction = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final bgPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final fgPaint = Paint()
      ..color = isOverBudget ? Colors.redAccent : AppColors.primary
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
    if (overflowFraction > 0) {
      final overflowPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * overflowFraction.clamp(0.0, 0.5),
        false,
        overflowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CaloriePainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.isOverBudget != isOverBudget ||
      old.overflowFraction != overflowFraction;
}
