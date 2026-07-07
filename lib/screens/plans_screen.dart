import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/meal_ingredient.dart';
import '../models/user_profile.dart';
import '../models/exercise.dart';
import '../algorithms/greedy_algorithm.dart';
import '../algorithms/genetic_algorithm.dart';
import '../services/firestore_service.dart';
import '../services/exercise_db_service.dart';
import '../services/dietary_filter.dart';
import '../services/ingredient_converter.dart';
import '../models/workout_log.dart';
import '../models/exercise_stat.dart';
import '../models/weight_log.dart';
import '../models/weekly_summary.dart';
import '../algorithms/adaptation_engine.dart';
import '../algorithms/progression.dart';
import 'recipe_screen.dart';
import 'food_log_screen.dart';
import 'weekly_review_screen.dart';
import 'package:provider/provider.dart';
import '../providers/plan_provider.dart';
import '../providers/profile_provider.dart';
import '../models/food_item.dart';
import '../app_clock.dart';
import '../theme/app_colors.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({Key? key}) : super(key: key);

  @override
  PlansScreenState createState() => PlansScreenState();
}

class PlansScreenState extends State<PlansScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['mealType'] != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tabController.animateTo(1);
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void switchToMealTab() => _tabController.animateTo(1);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final args = ModalRoute.of(context)?.settings.arguments;
    final String? focusMealType = (args is Map)
        ? args['mealType'] as String?
        : null;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text(
                'My Plans',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: c.onBackground,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: c.onPrimary,
                unselectedLabelColor: c.muted,
                labelStyle: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.w500,
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Workout'),
                  Tab(text: 'Meal'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  const _WorkoutTab(),
                  _MealTab(focusMealType: focusMealType),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── WORKOUT TAB ──────────────────────────────────────────────────────────────
class _WorkoutTab extends StatefulWidget {
  const _WorkoutTab();
  @override
  State<_WorkoutTab> createState() => _WorkoutTabState();
}

class _WorkoutTabState extends State<_WorkoutTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ── Plan & profile ─────────────────────────────────────────────────────────
  List<WorkoutDay> _plan = [];
  bool _isLoading = true;
  String? _error;
  UserProfile? _profile;
  int _selectedDay = 0;
  WorkoutLog? _todayLog;
  Map<String, bool> _weekDone = {};

  // ── Workout flow ───────────────────────────────────────────────────────────
  int _activeExerciseIndex = -1;
  int _activeSetNumber = 0;
  bool _inRest = false;
  int _restRemaining = 0;
  int _restTotal = 0;
  Timer? _restTimer;
  VoidCallback? _pendingRestCallback;
  bool _waitingForReady = false;

  // ── Per-set work timer ───────────────────────────────────────────────────────
  // After logging kg/reps the user taps "Start Set" → a work timer counts down
  // (duration = WorkoutExercise.timePerSetSeconds, session-budget fit). Pressing
  // "Done" ends the set early; reaching 0 auto-advances to the rest phase.
  bool _setRunning = false;
  int _setRemaining = 0;
  int _setTotal = 0;
  Timer? _setTimer;

  // ── Warm-up phase ──────────────────────────────────────────────────────────
  // The session enters a gated warm-up phase before the exercise flow: exercises
  // stay locked/greyed until the warm-up finishes or is skipped.
  bool _sessionStarted =
      false; // Start Workout pressed (covers warm-up + lifts)
  bool _warmupComplete = false; // warm-up done/skipped → exercises unlocked
  bool _warmupRunning = false; // a warm-up move is actively counting down
  int _activeWarmupIndex = -1;
  // Resolved per session: Home → 3 bodyweight cardio moves; Gym → 1 treadmill.
  List<({Exercise? exercise, String label, int seconds})> _warmupMoves = [];
  int _warmupRemaining = 0;
  int _warmupTotal = 0;
  Timer? _warmupTimer;

  // Exercise indices whose step-by-step instructions are expanded on the card.
  final Set<int> _expandedSteps = {};

  // ── Elapsed timer ──────────────────────────────────────────────────────────
  DateTime? _workoutStartedAt;
  Timer? _workoutTimer;
  int _elapsedSeconds = 0;

  // ── Completion tracking ────────────────────────────────────────────────────
  final Set<int> _completedExercises = {};
  final GlobalKey _activeKey = GlobalKey();

  // ── Load tracking (progressive overload) ────────────────────────────────────
  // Every set the user logged this session, keyed by exercise index — the
  // source of truth folded into the workout log + exercise_stats on completion.
  final Map<int, List<SetEntry>> _loggedSets = {};
  // Exercises the user explicitly skipped this session (index) — logged as
  // skipped, not counted as completed volume, and not progressed.
  final Set<int> _skippedExercises = {};
  // Per-exercise last/PR summary (keyed by exercise id) for the inline target.
  Map<String, ExerciseStat> _exerciseStats = {};
  // Persistent controllers for the active-card inputs (survive the 1 Hz rebuild).
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _repsController = TextEditingController();

  // ── Edit mode ──────────────────────────────────────────────────────────────
  bool _editMode = false;
  List<Exercise> _allExercises = []; // cached for the exercise picker
  // Tracks the exercise count at the moment the user entered edit mode,
  // used to enforce the 50% removal cap and detect deletions on exit.
  int _editModeOriginalCount = 0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    final provider = context.read<PlanProvider>();
    final currentDayIndex = appNow().weekday - 1;
    if (provider.workoutPlan.isNotEmpty) {
      setState(() {
        _plan = provider.workoutPlan;
        _isLoading = false;
        _selectedDay = currentDayIndex.clamp(
          0,
          provider.workoutPlan.length - 1,
        );
      });
      _loadWeekDone();
      _loadExerciseStats();
      // Populate exercise cache in background so the picker works after a
      // hot-restart (when _generate() is skipped because the plan is in memory).
      ExerciseDBService().getExercises().then((ex) {
        if (mounted && ex.isNotEmpty) setState(() => _allExercises = ex);
      });
      // _generate() is skipped on this path, so the local _profile (which the
      // header chips + picker eligibility read) would stay null and the chips
      // would vanish until a reload. Populate it from ProfileProvider.
      final pp = context.read<ProfileProvider>();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (pp.profile != null) {
        _profile = pp.profile;
      } else if (uid != null) {
        pp.load(uid).then((_) {
          if (mounted) setState(() => _profile = pp.profile);
        });
      }
    } else {
      _generate();
    }
    _subscribeToTodayLog();
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _setTimer?.cancel();
    _workoutTimer?.cancel();
    _warmupTimer?.cancel();
    _weightController.dispose();
    _repsController.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────────
  void _subscribeToTodayLog() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirestoreService().streamWorkoutLogForDate(uid, appNow()).listen((log) {
      if (mounted) setState(() => _todayLog = log);
    });
  }

  Future<void> _loadWeekDone() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final now = appNow();
    // Floor to midnight so the range aligns with midnight-stored log dates.
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    try {
      final logs = await FirestoreService().getWorkoutLogsForDateRange(
        uid,
        weekStart,
        weekEnd,
      );
      if (mounted)
        setState(() => _weekDone = {for (final l in logs) l.dayName: true});
    } catch (_) {}
  }

  /// Deletes the persisted plan for this week and regenerates from scratch.
  /// Used by the refresh button — guarantees escape from any broken/empty plan.
  Future<void> _forceRegenerate() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await context.read<PlanProvider>().clearAndDeleteWorkoutPlan(
      uid,
      _currentWeekId,
    );
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final fs = FirestoreService();
      final profileProvider = context.read<ProfileProvider>();
      await profileProvider.load(uid);
      final profile = profileProvider.profile;
      if (profile == null) throw Exception('Profile not found');

      final now = appNow();
      // Floor to midnight so weekly date ranges line up with logs (stored at
      // midnight). Using the timed `now` would drop a boundary day's Monday
      // log and leak this week's Monday into last week's aggregates.
      final today = DateTime(now.year, now.month, now.day);
      final weekId = FirestoreService.weekIdFor(now);
      if (!mounted) return;
      final planProvider = context.read<PlanProvider>();

      // ── Always fetch exercises first so the picker works on every path ────────
      final exercises = await ExerciseDBService().getExercises();
      if (exercises.isEmpty)
        throw Exception('Could not load exercises. Check your connection.');
      _allExercises = exercises; // cache for edit-mode picker

      // ── Try to load persisted plan for this week first ──────────────────────
      final loaded = await planProvider.loadWorkoutPlan(uid, weekId);
      if (loaded) {
        // Rehydrate each WorkoutExercise with fresh API data. The gifUrls
        // stored in the plan doc may point at a retired host; _allExercises
        // has current URLs. Falls back to name-match in case IDs changed
        // between API versions (old numeric IDs vs new alphanumeric IDs).
        final exerciseById = {for (final ex in exercises) ex.id: ex};
        final exerciseByName = {
          for (final ex in exercises) ex.name.toLowerCase(): ex,
        };
        final rehydrated = planProvider.workoutPlan.map((day) {
          if (day.isRest) return day;
          return WorkoutDay(
            dayName: day.dayName,
            focus: day.focus,
            isRest: day.isRest,
            exercises: day.exercises.map((we) {
              final fresh =
                  exerciseById[we.exercise.id] ??
                  exerciseByName[we.exercise.name.toLowerCase()];
              return fresh != null
                  ? WorkoutExercise(
                      exercise: fresh,
                      sets: we.sets,
                      reps: we.reps,
                      restSeconds: we.restSeconds,
                    )
                  : we;
            }).toList(),
          );
        }).toList();

        // Re-filter the saved plan against the CURRENT profile. A plan saved
        // under Gym (or different equipment/level) would otherwise keep its
        // gym/barbell/machine moves after the user switched to Home. Drop the
        // now-ineligible exercises and refill each day with eligible ones
        // (bodyweight is always eligible, so days never end up empty).
        final sanitized = _sanitizePlanForProfile(rehydrated, profile);
        planProvider.setWorkoutPlan(sanitized.plan);
        if (sanitized.changed) {
          await planProvider.persistWorkoutPlan(uid, weekId);
        }

        final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
        final thisWeekEnd = thisWeekStart.add(const Duration(days: 7));
        final weekLogs = await fs.getWorkoutLogsForDateRange(
          uid,
          thisWeekStart,
          thisWeekEnd,
        );
        setState(() {
          _profile = profile;
          _plan = planProvider.workoutPlan;
          _isLoading = false;
          _selectedDay = _plan.indexWhere((d) => !d.isRest);
          if (_selectedDay == -1) _selectedDay = 0;
          _weekDone = {for (final l in weekLogs) l.dayName: true};
        });
        _loadExerciseStats();
        return;
      }

      // ── No persisted plan — generate a fresh one ─────────────────────────────

      final weekStart = today.subtract(Duration(days: today.weekday - 1 + 7));
      final lastWeekNutrition = await fs.getWeeklyNutritionSummary(
        uid,
        weekStart,
      );
      final lastWeekLogs = await fs.getWorkoutLogsForDateRange(
        uid,
        weekStart,
        weekStart.add(const Duration(days: 7)),
      );
      final lastWeekWorkouts = lastWeekLogs.length;
      // Average perceived-difficulty rating from last week → autoregulation.
      final lastWeekRatings = lastWeekLogs
          .map((l) => l.rating)
          .whereType<int>()
          .toList();
      final lastWeekAvgRating = lastWeekRatings.isEmpty
          ? null
          : lastWeekRatings.reduce((a, b) => a + b) / lastWeekRatings.length;

      // Adaptation only applies when last week actually happened in the app —
      // a plan existed or at least one workout was logged. Without this guard
      // a brand-new user reads as 0% completion and gets a reduced first plan.
      final lastWeekId = FirestoreService.weekIdFor(weekStart);
      final hadLastWeekPlan =
          await fs.loadWeeklyWorkoutPlan(uid, lastWeekId) != null;
      // Anchor the weekly engine to account creation too: a "last week" that
      // ended on/before the account existed is not real history, so never adapt
      // off it. (The plan/log check below already covers this in practice; this
      // makes the "week starts at account creation" rule explicit and robust.)
      final createdAt = profile.createdAt;
      final reviewedWeekEnd = weekStart.add(const Duration(days: 7));
      final weekStartedBeforeAccount =
          createdAt != null && !reviewedWeekEnd.isAfter(createdAt);
      final hasHistory =
          (hadLastWeekPlan || lastWeekWorkouts > 0) && !weekStartedBeforeAccount;

      // Weight-trend signal — net change across last week's weigh-ins.
      final weightLogsRaw = await fs.getWeightLogs(uid);
      final lastWeekWeights =
          weightLogsRaw
              .map((m) => WeightLog.fromMap(m, ''))
              .where(
                (w) =>
                    !w.date.isBefore(weekStart) &&
                    w.date.isBefore(weekStart.add(const Duration(days: 7))),
              )
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
      final weightChangeKg = lastWeekWeights.length >= 2
          ? lastWeekWeights.last.weight - lastWeekWeights.first.weight
          : null; // <2 weigh-ins → no weight signal

      // Use real planned days from profile for the completion denominator
      final plannedDays = profile.workoutDaysPerWeek;

      // A1: only trust calorie/protein adherence with enough logged days —
      // sparse logging (avg over `daysLogged`, not 7) otherwise reads as
      // on-target and suppresses real adjustments. <4 days → neutral / no signal.
      final daysLogged = lastWeekNutrition['daysLogged'] as int;
      final hasEnoughNutritionDays = daysLogged >= 4;
      final calorieAdherence = hasEnoughNutritionDays
          ? (lastWeekNutrition['avgCalories'] as double) /
                profile.calorieGoal *
                100
          : 100.0;
      // N1: protein adherence drives a low-protein note when calories are met.
      final proteinGoal = profile.macroGoals['protein'] ?? 0;
      final proteinAdherence = (hasEnoughNutritionDays && proteinGoal > 0)
          ? (lastWeekNutrition['avgProtein'] as double) / proteinGoal * 100
          : null;

      final adaptation = hasHistory
          ? AdaptationEngine().compute(
              lastWeekCalorieAdherence: calorieAdherence,
              lastWeekWorkoutCompletion: plannedDays > 0
                  ? lastWeekWorkouts / plannedDays
                  : 1.0,
              currentExperienceLevel: profile.experienceLevel,
              lastWeekRatings: lastWeekRatings,
              weightChangeKg: weightChangeKg,
              fitnessGoal: profile.fitnessGoal,
              lastWeekProteinAdherence: proteinAdherence,
            )
          : const AdaptationResult(
              calorieBiasKcal: 0,
              difficultyBias: 'same',
              notes: '',
            );

      final greedy = GreedyAlgorithm();
      final plan = greedy.generatePlan(
        allExercises: exercises,
        profile: profile,
        difficultyBias: adaptation.difficultyBias,
      );

      // W2: an 'up'/'down' that the NSCA set-range clamp fully absorbs makes no
      // real volume change — the "stepped" message would mislead. Detect it and
      // swap that sentence for an accurate ceiling/floor nudge (the clamp itself
      // is correct NSCA behaviour; only the wording is fixed).
      final volumeChanged =
          adaptation.difficultyBias != 'same' &&
          greedy.setsForDifficulty(profile, adaptation.difficultyBias) !=
              greedy.setsForDifficulty(profile, 'same');
      var adaptationNotes = adaptation.notes;
      if (!volumeChanged && adaptation.difficultyBias == 'up') {
        adaptationNotes = adaptationNotes
            .replaceAll(
              AdaptationEngine.noteStepUp,
              AdaptationEngine.noteAtSetCeiling,
            )
            .replaceAll(
              AdaptationEngine.noteStepUpEasy,
              AdaptationEngine.noteAtSetCeiling,
            );
      } else if (!volumeChanged && adaptation.difficultyBias == 'down') {
        adaptationNotes = adaptationNotes
            .replaceAll(
              AdaptationEngine.noteVolumeDownSchedule,
              AdaptationEngine.noteAtSetFloor,
            )
            .replaceAll(
              AdaptationEngine.noteVolumeDownHard,
              AdaptationEngine.noteAtSetFloor,
            );
      }

      // Persist and store in provider
      planProvider.setWorkoutPlan(plan);
      await planProvider.persistWorkoutPlan(uid, weekId);

      // Feed the weekly calorie bias back into the profile so the calorie goal
      // adapts week-over-week (clamped to ±500 by the provider). Guarded by an
      // explicit per-week stamp so it adapts ONCE per weekId even across force-
      // regenerations (force-regenerate deletes the plan doc and re-enters this
      // branch, which would otherwise re-add the bias and stack the drift).
      // Difficulty is recomputed every time but is idempotent on identical
      // last-week data, so a regenerated plan keeps the same difficulty.
      final alreadyAdaptedThisWeek = profile.lastAdaptationWeekId == weekId;
      if (hasHistory && !alreadyAdaptedThisWeek && mounted) {
        // Capture the pre-adjustment goal + macro targets, apply the calorie
        // bias, then read the post-clamp profile back so the summary records the
        // real new targets (macros follow the calorie goal).
        final oldGoal = profile.calorieGoal;
        final oldMacros = profile.macroGoals;
        // Reuse the provider captured before the await (line ~301) — avoids
        // touching `context` across the async gap.
        await profileProvider.applyCalorieAdjustment(
          adaptation.calorieBiasKcal,
          markWeekId: weekId,
        );
        final newProfile = profileProvider.profile ?? profile;
        final newMacros = newProfile.macroGoals;

        // Persist a snapshot of this week's adaptation for the Weekly Review
        // screen (current week + history). Same guard as the calorie bias, so
        // exactly one snapshot per weekId — no stacking on force-regenerate.
        final activeWeekStart = today.subtract(
          Duration(days: today.weekday - 1),
        );
        final summary = WeeklySummary(
          weekId: weekId,
          generatedAt: appNow(),
          weekStart: activeWeekStart,
          weekEnd: activeWeekStart.add(const Duration(days: 6)),
          calorieAdherence: calorieAdherence,
          proteinAdherence: proteinAdherence,
          workoutsCompleted: lastWeekWorkouts,
          workoutsPlanned: plannedDays,
          avgRating: lastWeekAvgRating,
          daysLogged: daysLogged,
          calorieBias: adaptation.calorieBiasKcal,
          oldCalorieGoal: oldGoal,
          newCalorieGoal: newProfile.calorieGoal,
          oldProtein: oldMacros['protein'] ?? 0,
          newProtein: newMacros['protein'] ?? 0,
          oldCarbs: oldMacros['carbs'] ?? 0,
          newCarbs: newMacros['carbs'] ?? 0,
          oldFat: oldMacros['fat'] ?? 0,
          newFat: newMacros['fat'] ?? 0,
          difficultyBias: adaptation.difficultyBias,
          volumeChanged: volumeChanged,
          notes: adaptationNotes,
        );
        await fs.saveWeeklySummary(uid, summary);
      }

      final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
      final thisWeekEnd = thisWeekStart.add(const Duration(days: 7));
      final weekLogs = await fs.getWorkoutLogsForDateRange(
        uid,
        thisWeekStart,
        thisWeekEnd,
      );

      setState(() {
        _profile = profile;
        _plan = plan;
        _isLoading = false;
        _selectedDay = plan.indexWhere((d) => !d.isRest);
        if (_selectedDay == -1) _selectedDay = 0;
        _weekDone = {for (final l in weekLogs) l.dayName: true};
      });
      _loadExerciseStats();

      // Announce the weekly adaptation — once per week, on the first generation
      // only (silent on force-regenerations). The full reasoning + history now
      // lives in the Weekly Review screen; this is just the entry point.
      if (mounted && !alreadyAdaptedThisWeek && adaptationNotes.isNotEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Weekly plan updated based on your progress',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: context.colors.onBackground,
                ),
              ),
              backgroundColor: context.colors.surface,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 8),
              showCloseIcon: true,
              closeIconColor: context.colors.muted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              action: SnackBarAction(
                label: 'View Summary',
                textColor: AppColors.primary,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WeeklyReviewScreen(),
                    ),
                  );
                },
              ),
            ),
          );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Batch-loads per-exercise last/PR stats for every exercise in the plan so
  /// each card can show a "Last: X" target and PR badge.
  Future<void> _loadExerciseStats() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ids = <String>{
      for (final d in _plan)
        for (final we in d.exercises) we.exercise.id,
    }.toList();
    if (ids.isEmpty) return;
    try {
      final stats = await FirestoreService().getExerciseStats(uid, ids);
      if (mounted) setState(() => _exerciseStats = stats);
    } catch (_) {
      /* non-fatal: cards just won't show a target */
    }
  }

  // ── Load tracking helpers ───────────────────────────────────────────────────
  bool get _imperial => _profile?.unitSystem == 'imperial';
  String get _weightUnit => _imperial ? 'lbs' : 'kg';
  double _toKg(double v) => _imperial ? v / 2.20462 : v;
  double _fromKg(double kg) => _imperial ? kg * 2.20462 : kg;
  String _fmtWeight(double kg) {
    final v = _fromKg(kg);
    return '${v.toStringAsFixed(v % 1 == 0 ? 0 : 1)} $_weightUnit';
  }

  /// Appends the currently-typed weight/reps as one logged set for the active
  /// exercise. Called on every "Done Set", so each set is recorded as performed
  /// (a missed rep = a lower logged number; no separate prompt needed). Weight
  /// is omitted for bodyweight moves.
  void _captureActiveInput() {
    if (_activeExerciseIndex < 0) return;
    final w = double.tryParse(_weightController.text.trim());
    final r = int.tryParse(_repsController.text.trim());
    final entry = SetEntry(
      weightKg: (w != null && w > 0) ? _toKg(w) : null,
      reps: (r != null && r > 0) ? r : null,
    );
    if (entry.weightKg == null && entry.reps == null) return;
    (_loggedSets[_activeExerciseIndex] ??= []).add(entry);
  }

  static const _lowerBodyMuscles = {'quads', 'glutes', 'hamstrings', 'calves'};

  /// Next prescribed working set for [we] via double progression, derived from
  /// the last logged top set. Null when there's no baseline or a timed/bodyweight
  /// rep prescription.
  ProgressionTarget? _targetFor(WorkoutExercise we) {
    final stat = _exerciseStats[we.exercise.id];
    if (stat == null) return null;
    final isLowerOrCompound =
        GreedyAlgorithm.isStapleCompound(we.exercise) ||
        we.exercise.primaryMuscles.any(_lowerBodyMuscles.contains);
    return nextTarget(
      lastWeightKg: stat.lastWeightKg,
      lastReps: stat.lastReps,
      repRange: we.reps,
      isLowerOrCompound: isLowerOrCompound,
    );
  }

  /// Pre-fills the working-weight/reps inputs with the progression target for the
  /// exercise at [exIdx] (display units), so the user just confirms. Clears when
  /// there is no target.
  void _prefillTargetFor(int exIdx) {
    if (_selectedDay < 0 || _selectedDay >= _plan.length) return;
    final day = _plan[_selectedDay];
    if (exIdx < 0 || exIdx >= day.exercises.length) return;
    final we = day.exercises[exIdx];
    final stat = _exerciseStats[we.exercise.id];

    void setWeight(double? kg) {
      if (kg == null) {
        _weightController.clear();
      } else {
        final w = _fromKg(kg);
        _weightController.text = w % 1 == 0
            ? w.toStringAsFixed(0)
            : w.toStringAsFixed(1);
      }
    }

    // Week 2+: pre-fill the first set from the full last session run through the
    // per-set suggester (later sets inherit whatever the user logs for set 1).
    if (stat != null && stat.lastSets.isNotEmpty) {
      final isLowerOrCompound =
          GreedyAlgorithm.isStapleCompound(we.exercise) ||
          we.exercise.primaryMuscles.any(_lowerBodyMuscles.contains);
      final targets = nextSetTargets(
        lastSets: stat.lastSets,
        repRange: we.reps,
        isLowerOrCompound: isLowerOrCompound,
      );
      if (targets.isNotEmpty) {
        setWeight(targets.first.weightKg);
        _repsController.text = targets.first.reps?.toString() ?? '';
        return;
      }
    }

    // Fallback: single-target double progression from the legacy top set.
    final target = _targetFor(we);
    if (target == null) {
      _weightController.clear();
      _repsController.clear();
      return;
    }
    setWeight(target.weightKg);
    _repsController.text = target.reps.toString();
  }

  Future<void> _togglePin(String focus, Exercise ex) async {
    final profile = _profile;
    if (profile == null) return;
    final map = {
      for (final e in profile.pinnedExercises.entries)
        e.key: List<String>.from(e.value),
    };
    final list = map[focus] ?? <String>[];
    final wasPinned = list.contains(ex.id);
    wasPinned ? list.remove(ex.id) : list.add(ex.id);
    if (list.isEmpty) {
      map.remove(focus);
    } else {
      map[focus] = list;
    }
    final updated = profile.copyWith(pinnedExercises: map);
    await context.read<ProfileProvider>().save(updated);
    if (!mounted) return;
    setState(() => _profile = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasPinned
              ? '${ex.name} unpinned from $focus'
              : '${ex.name} pinned always included in $focus workouts',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Post-workout perceived-difficulty rating (1 too easy … 5 too hard).
  Future<int?> _askWorkoutRating() {
    const labels = ['Too easy', 'Easy', 'Just right', 'Hard', 'Too hard'];
    final c = context.colors;
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How did that feel?',
                style: GoogleFonts.spaceGrotesk(
                  color: c.onBackground,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Tunes next week's difficulty.",
                style: GoogleFonts.inter(color: c.muted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ...List.generate(
                5,
                (i) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text(
                    '${i + 1}',
                    style: GoogleFonts.spaceGrotesk(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  title: Text(
                    labels[i],
                    style: GoogleFonts.inter(color: c.onBackground),
                  ),
                  onTap: () => Navigator.pop(ctx, i + 1),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('Skip', style: GoogleFonts.inter(color: c.muted)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pinButton(String focus, Exercise ex) {
    final pinned = (_profile?.pinnedExercises[focus] ?? const <String>[])
        .contains(ex.id);
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: () => _togglePin(focus, ex),
      tooltip: pinned ? 'Unpin from $focus' : 'Always include in $focus',
      icon: Icon(
        pinned ? Icons.star : Icons.star_outline,
        color: pinned ? AppColors.primary : context.colors.disabled,
        size: 20,
      ),
    );
  }

  /// Inline working-weight + reps input shown on the active exercise card,
  /// pre-hinted with the last logged top set as the progressive-overload target.
  Widget _buildWeightInput(WorkoutExercise we) {
    final c = context.colors;
    final stat = _exerciseStats[we.exercise.id];
    final hint = (stat != null && stat.lastWeightKg > 0)
        ? 'Last: ${_fmtWeight(stat.lastWeightKg)}'
              '${stat.lastReps != null ? ' × ${stat.lastReps}' : ''}'
              '   ·   PR ${_fmtWeight(stat.bestWeightKg)}'
        : 'Log your working weight to track progress';
    InputDecoration deco(String h) => InputDecoration(
      hintText: h,
      hintStyle: GoogleFonts.inter(color: c.disabled, fontSize: 13),
      filled: true,
      fillColor: c.inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
    final target = _targetFor(we);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(hint, style: GoogleFonts.inter(color: c.muted, fontSize: 12)),
        if (target != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                target.isIncrease
                    ? Icons.trending_up_rounded
                    : Icons.flag_rounded,
                color: AppColors.primary,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                'Target: ${_fmtWeight(target.weightKg)} × ${target.reps}',
                style: GoogleFonts.inter(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _weightController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: GoogleFonts.spaceGrotesk(
                  color: c.onBackground,
                  fontWeight: FontWeight.w600,
                ),
                decoration: deco('Weight ($_weightUnit)'),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 88,
              child: TextField(
                controller: _repsController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.spaceGrotesk(
                  color: c.onBackground,
                  fontWeight: FontWeight.w600,
                ),
                decoration: deco('Reps'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Resolves the session's warm-up moves from the cache (NSCA general warm-up):
  /// up to 3 bodyweight cardio moves (~1 min each), the same for Gym and Home.
  List<({Exercise? exercise, String label, int seconds})>
  _resolveWarmupMoves() {
    final cardio = _allExercises
        .where((e) => e.category.toLowerCase() == 'cardio')
        .toList();
    // Both Gym and Home get the same bodyweight dynamic warm-up.
    final bodyweight =
        cardio
            .where(
              (e) =>
                  e.equipment.isEmpty ||
                  e.equipment.any((q) => q.toLowerCase() == 'bodyweight'),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return [
      for (final e in bodyweight.take(3))
        (exercise: e, label: e.name, seconds: 60),
    ];
  }

  String _fmtWarmupDuration(int seconds) =>
      seconds % 60 == 0 ? '${seconds ~/ 60} min' : '${seconds}s';

  void _startWarmupPhase() {
    if (_warmupMoves.isEmpty) {
      _finishWarmup();
      return;
    }
    setState(() {
      _warmupRunning = true;
      _activeWarmupIndex = 0;
    });
    _startWarmupTimer(_warmupMoves[0].seconds);
    _scrollToActive();
  }

  void _startWarmupTimer(int seconds) {
    _warmupTimer?.cancel();
    setState(() {
      _warmupTotal = seconds;
      _warmupRemaining = seconds;
    });
    _warmupTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_warmupRemaining <= 1) {
        t.cancel();
        _advanceWarmup();
      } else {
        setState(() => _warmupRemaining--);
      }
    });
  }

  void _advanceWarmup() {
    _warmupTimer?.cancel();
    if (_activeWarmupIndex + 1 < _warmupMoves.length) {
      setState(() => _activeWarmupIndex++);
      _startWarmupTimer(_warmupMoves[_activeWarmupIndex].seconds);
    } else {
      _finishWarmup();
    }
  }

  /// Ends the warm-up phase (finished or skipped) and unlocks the exercise flow.
  void _finishWarmup() {
    _warmupTimer?.cancel();
    setState(() {
      _warmupRunning = false;
      _warmupComplete = true;
      _activeWarmupIndex = -1;
      _activeExerciseIndex = 0;
      _activeSetNumber = 1;
    });
    _prefillTargetFor(0);
    _scrollToActive();
  }

  /// Warm-up block at the top of the active day. Before Start it lists the moves
  /// with a Start button; once running it shows the active move as a full-size
  /// card with an auto-advancing countdown. Skippable — never a gate.
  Widget _buildGeneralWarmup() {
    if (_warmupComplete || _warmupMoves.isEmpty) return const SizedBox.shrink();
    return _warmupRunning ? _buildActiveWarmupCard() : _buildWarmupIntro();
  }

  Widget _buildWarmupIntro() {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surfaceAlt),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.whatshot_rounded, color: AppColors.amber, size: 16),
              const SizedBox(width: 6),
              Text(
                'Warm-up first',
                style: GoogleFonts.spaceGrotesk(
                  color: c.onBackground,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _finishWarmup,
                child: Text(
                  'Skip',
                  style: GoogleFonts.inter(
                    color: c.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final m in _warmupMoves)
            _warmupMoveRow(m.exercise, m.label, _fmtWarmupDuration(m.seconds)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startWarmupPhase,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(
                'Start warm-up',
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: c.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveWarmupCard() {
    final c = context.colors;
    final m = _warmupMoves[_activeWarmupIndex];
    final ex = m.exercise;
    final gifUrl = (ex?.gifUrl != null && ex!.gifUrl!.isNotEmpty)
        ? ex.gifUrl
        : null;
    final isLast = _activeWarmupIndex + 1 >= _warmupMoves.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.amber.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.whatshot_rounded, color: AppColors.amber, size: 16),
              const SizedBox(width: 6),
              Text(
                'Warm-up ${_activeWarmupIndex + 1} of ${_warmupMoves.length}',
                style: GoogleFonts.inter(
                  color: AppColors.amber,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _finishWarmup,
                child: Text(
                  'Skip warm-up',
                  style: GoogleFonts.inter(
                    color: c.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            m.label,
            style: GoogleFonts.spaceGrotesk(
              color: c.onBackground,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: gifUrl != null
                ? _gifImage(
                    gifUrl,
                    key: ValueKey('gif_warmup_${ex!.id}'),
                    height: 200,
                    width: double.infinity,
                    loading: _gifPlaceholder(loading: true, height: 200),
                  )
                : _gifPlaceholder(height: 200),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _formatCountdown(_warmupRemaining),
              style: GoogleFonts.spaceGrotesk(
                color: c.onBackground,
                fontSize: 44,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _warmupTotal > 0 ? _warmupRemaining / _warmupTotal : 0,
              backgroundColor: c.border,
              valueColor: AlwaysStoppedAnimation(AppColors.amber),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _advanceWarmup,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isLast ? 'Finish warm-up' : 'Next move',
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One row in the general warm-up: a small GIF thumbnail (if available) +
  /// move name + suggested duration.
  Widget _warmupMoveRow(Exercise? ex, String label, String duration) {
    final c = context.colors;
    final hasGif = ex?.gifUrl?.isNotEmpty == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: hasGif
                ? _gifImage(ex!.gifUrl!, width: 44, height: 44)
                : Container(
                    width: 44,
                    height: 44,
                    color: c.inputFill,
                    child: Icon(
                      Icons.directions_run_rounded,
                      color: c.muted,
                      size: 20,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: c.onBackground,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            duration,
            style: GoogleFonts.inter(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// Small "Last / PR" caption under the stat boxes on the normal card.
  Widget _lastPrLine(Exercise ex) {
    final c = context.colors;
    final stat = _exerciseStats[ex.id];
    if (stat == null || stat.lastWeightKg <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.history_rounded, color: c.muted, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Last: ${_fmtWeight(stat.lastWeightKg)}'
              '${stat.lastReps != null ? ' × ${stat.lastReps}' : ''}'
              '   ·   PR ${_fmtWeight(stat.bestWeightKg)}',
              style: GoogleFonts.inter(color: c.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveWorkoutLog(
    WorkoutDay day,
    int durationMinutes, {
    int? rating,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final now = appNow();
    final logExercises = [
      for (int i = 0; i < day.exercises.length; i++)
        WorkoutLogExercise(
          name: day.exercises[i].exercise.name,
          sets: day.exercises[i].sets,
          reps: day.exercises[i].reps,
          restSeconds: day.exercises[i].restSeconds,
          primaryMuscles: day.exercises[i].exercise.primaryMuscles,
          loggedSets: _loggedSets[i] ?? const [],
          skipped: _skippedExercises.contains(i),
        ),
    ];
    final log = WorkoutLog(
      id: '',
      userId: uid,
      date: DateTime(now.year, now.month, now.day),
      weekId: FirestoreService.weekIdFor(now),
      dayName: day.dayName,
      focus: day.focus,
      durationMinutes: durationMinutes,
      completedAt: now,
      rating: rating,
      exercises: logExercises,
    );
    final fs = FirestoreService();
    await fs.saveWorkoutLog(log);

    // Persist per-exercise sets + top-set PR (skipped exercises don't progress).
    final prs = <String>[];
    for (int i = 0; i < day.exercises.length; i++) {
      if (_skippedExercises.contains(i)) continue;
      final logged = _loggedSets[i] ?? const [];
      if (logged.isEmpty) continue;
      final top = logExercises[i].topSet;
      final kg = top?.weightKg;
      if (kg == null || kg <= 0) continue; // bodyweight/timed → no weight PR
      final ex = day.exercises[i].exercise;
      final prevBest = _exerciseStats[ex.id]?.bestWeightKg ?? 0;
      if (kg > prevBest) prs.add(ex.name);
      await fs.saveExerciseStat(
        userId: uid,
        exerciseId: ex.id,
        name: ex.name,
        weightKg: kg,
        reps: top?.reps,
        lastSets: logged,
      );
    }
    _loadExerciseStats(); // refresh last/PR cache for the cards

    if (mounted) {
      final msg = prs.isNotEmpty
          ? '🏆 New PR: ${prs.first}'
                '${prs.length > 1 ? ' +${prs.length - 1} more' : ''}!'
          : 'All done! ${day.focus} logged · ${durationMinutes}m';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  // ── Workout flow methods ───────────────────────────────────────────────────
  void _resetWorkoutState() {
    _restTimer?.cancel();
    _setTimer?.cancel();
    _workoutTimer?.cancel();
    _warmupTimer?.cancel();
    _pendingRestCallback = null;
    _activeExerciseIndex = -1;
    _activeSetNumber = 0;
    _inRest = false;
    _restRemaining = 0;
    _restTotal = 0;
    _setRunning = false;
    _setRemaining = 0;
    _setTotal = 0;
    _waitingForReady = false;
    _workoutStartedAt = null;
    _elapsedSeconds = 0;
    _completedExercises.clear();
    _loggedSets.clear();
    _skippedExercises.clear();
    _sessionStarted = false;
    _warmupComplete = false;
    _warmupRunning = false;
    _activeWarmupIndex = -1;
    _warmupMoves = [];
    _warmupRemaining = 0;
    _warmupTotal = 0;
    _expandedSteps.clear();
    _weightController.clear();
    _repsController.clear();
  }

  Future<void> _startWorkout() async {
    // Exit edit mode first so the ReorderableListView is fully unmounted before
    // the session UI replaces it.
    if (_editMode) setState(() => _editMode = false);
    // Safety guard: never start if the selected day has no exercises
    if (_selectedDay >= _plan.length || _plan[_selectedDay].exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Add at least one exercise before starting.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }
    // Resolve the warm-up so the gated warm-up phase can run before the lifts.
    final warmups = _resolveWarmupMoves();
    setState(() {
      _sessionStarted = true;
      _workoutStartedAt = DateTime.now();
      _elapsedSeconds = 0;
      _loggedSets.clear();
      _skippedExercises.clear();
      _weightController.clear();
      _repsController.clear();
      _warmupMoves = warmups;
      _warmupRunning = false;
      _activeWarmupIndex = -1;
      _setRunning = false;
      if (warmups.isEmpty) {
        // No warm-up available — go straight into the exercise flow.
        _warmupComplete = true;
        _activeExerciseIndex = 0;
        _activeSetNumber = 1;
      } else {
        // Lock exercises until the warm-up is finished/skipped.
        _warmupComplete = false;
        _activeExerciseIndex = -1;
      }
    });
    if (warmups.isEmpty) _prefillTargetFor(0);
    _workoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
    _scrollToActive();
  }

  // The "I'm ready" gate: starts the per-set work timer after kg/reps are logged.
  void _startSet(WorkoutExercise we) {
    _setTimer?.cancel();
    final secs = we.timePerSetSeconds;
    setState(() {
      _setRunning = true;
      _setRemaining = secs;
      _setTotal = secs;
    });
    _setTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _setRemaining--);
      if (_setRemaining <= 0) {
        t.cancel();
        _finishSet(we); // reaching 0 auto-advances to rest
      }
    });
  }

  // Ends the current set (early "Done" tap or timer reaching 0) → rest phase.
  void _finishSet(WorkoutExercise we) {
    _setTimer?.cancel();
    if (mounted) setState(() => _setRunning = false);
    _doneSet(we);
  }

  /// Skips the active exercise: flags it, discards any partial sets, and
  /// advances (no rest) to the next exercise — or ends the session if it was
  /// the last. Skipped exercises are logged as skipped and never progressed.
  void _skipExercise(WorkoutExercise we) {
    final idx = _activeExerciseIndex;
    if (idx < 0) return;
    _setTimer?.cancel();
    _restTimer?.cancel();
    final day = _plan[_selectedDay];
    _loggedSets.remove(idx);
    _skippedExercises.add(idx);
    if (idx + 1 < day.exercises.length) {
      setState(() {
        _completedExercises.add(idx);
        _inRest = false;
        _setRunning = false;
        _waitingForReady = true;
      });
      _scrollToActive();
    } else {
      setState(() {
        _completedExercises.add(idx);
        _inRest = false;
        _setRunning = false;
      });
      _autoComplete(day);
    }
  }

  void _doneSet(WorkoutExercise we) {
    // Capture the typed working weight/reps as this exercise's top set.
    _captureActiveInput();
    if (_activeSetNumber < we.sets) {
      _startRestTimer(
        we.restSeconds,
        onComplete: () {
          if (mounted)
            setState(() {
              _activeSetNumber++;
              _inRest = false;
              _setRunning = false;
            });
        },
      );
    } else {
      final day = _plan[_selectedDay];
      final completedIndex = _activeExerciseIndex;
      if (_activeExerciseIndex + 1 < day.exercises.length) {
        _startRestTimer(
          we.restSeconds,
          onComplete: () {
            if (mounted) {
              setState(() {
                _completedExercises.add(completedIndex);
                _inRest = false;
                _waitingForReady = true;
              });
              _scrollToActive();
            }
          },
        );
      } else {
        _startRestTimer(
          0,
          onComplete: () {
            if (mounted)
              setState(() => _completedExercises.add(completedIndex));
            _autoComplete(day);
          },
        );
      }
    }
  }

  void _iAmReady() {
    setState(() {
      _waitingForReady = false;
      _activeExerciseIndex++;
      _activeSetNumber = 1;
      _setRunning = false;
    });
    // Pre-fill the next exercise with its own progression target (clears when
    // there is none).
    _prefillTargetFor(_activeExerciseIndex);
    _scrollToActive();
  }

  void _startRestTimer(int seconds, {required VoidCallback onComplete}) {
    _restTimer?.cancel();
    _pendingRestCallback = onComplete;
    if (seconds == 0) {
      onComplete();
      return;
    }
    setState(() {
      _inRest = true;
      _restRemaining = seconds;
      _restTotal = seconds;
    });
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _restRemaining--);
      if (_restRemaining <= 0) {
        t.cancel();
        onComplete();
      }
    });
  }

  void _skipRest() {
    _restTimer?.cancel();
    final cb = _pendingRestCallback;
    setState(() {
      _inRest = false;
      _pendingRestCallback = null;
    });
    cb?.call();
  }

  Future<void> _autoComplete(WorkoutDay day) async {
    _workoutTimer?.cancel();
    final mins = _workoutStartedAt != null
        ? DateTime.now().difference(_workoutStartedAt!).inMinutes.clamp(1, 999)
        : 45;
    if (mounted)
      setState(() {
        _weekDone[day.dayName] = true;
        _inRest = false;
        _waitingForReady = false;
      });
    final rating = mounted ? await _askWorkoutRating() : null;
    await _saveWorkoutLog(day, mins, rating: rating);
  }

  Future<void> _debugAutoCompleteDay(WorkoutDay day) async {
    final profile = context.read<ProfileProvider>().profile;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final now = appNow();
    final log = WorkoutLog(
      id: '',
      userId: uid,
      date: DateTime(now.year, now.month, now.day),
      weekId: FirestoreService.weekIdFor(now),
      dayName: day.dayName,
      focus: day.focus,
      durationMinutes: profile?.sessionMinutes ?? 45,
      completedAt: now,
      rating: 3,
      exercises: day.exercises
          .map(
            (e) => WorkoutLogExercise(
              name: e.exercise.name,
              sets: e.sets,
              reps: e.reps,
              restSeconds: e.restSeconds,
              primaryMuscles: e.exercise.primaryMuscles,
              loggedSets: const [],
              skipped: false,
            ),
          )
          .toList(),
    );
    await FirestoreService().saveWorkoutLog(log);
    if (mounted) setState(() => _weekDone[day.dayName] = true);
  }

  void _scrollToActive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          alignment: 0.1,
        );
      }
    });
  }

  String _formatElapsed(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  String _formatCountdown(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return m > 0 ? '$m:${sec.toString().padLeft(2, '0')}' : '${s}s';
  }

  // Read-only "<weight> <unit> · <reps> reps" shown above the work timer, built
  // from whatever the user typed in the logging sub-phase (each part optional).
  String _loggedSetSummary() {
    final w = _weightController.text.trim();
    final r = _repsController.text.trim();
    final parts = <String>[];
    if (w.isNotEmpty) parts.add('$w $_weightUnit');
    if (r.isNotEmpty) parts.add('$r reps');
    return parts.join(' · ');
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading)
      return _buildLoading('Generating workout plan...', ctx: context);
    if (_error != null) return _buildError(_error!, _generate, ctx: context);
    return _buildPlan();
  }

  Widget _buildPlan() {
    final c = context.colors;
    final day = _plan.isNotEmpty ? _plan[_selectedDay] : null;
    // Fall back to the provider profile so the chips never vanish even if the
    // local _profile hasn't been populated on this code path yet.
    final headerProfile = _profile ?? context.watch<ProfileProvider>().profile;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (headerProfile != null) ...[
                _chip(headerProfile.fitnessGoal, AppColors.primary),
                const SizedBox(width: 6),
                _chip(headerProfile.experienceLevel, AppColors.purple),
                const SizedBox(width: 6),
                _chip(headerProfile.workoutLocation, AppColors.orange),
              ],
              const Spacer(),
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: AppColors.primary),
                onPressed: _forceRegenerate,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Day selector with completion dots
        SizedBox(
          height: 70,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _plan.length,
            itemBuilder: (context, i) {
              final d = _plan[i];
              final isSelected = i == _selectedDay;
              final isRest = d.isRest;
              return GestureDetector(
                onTap: () {
                  if (i != _selectedDay) {
                    setState(() {
                      _resetWorkoutState();
                      _selectedDay = i;
                    });
                  }
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 56,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isRest ? c.subtle : AppColors.primary)
                            : c.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: isSelected ? null : Border.all(color: c.border),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            d.dayName.substring(0, 3),
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? (isRest ? c.onBackground : c.onPrimary)
                                  : c.onBackground,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Icon(
                            isRest
                                ? Icons.bedtime_rounded
                                : Icons.fitness_center_rounded,
                            size: 14,
                            color: isSelected
                                ? (isRest ? Colors.white70 : c.shadow)
                                : c.muted,
                          ),
                        ],
                      ),
                    ),
                    if (_weekDone[d.dayName] == true)
                      Positioned(
                        top: -3,
                        right: 5,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.onPrimary, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: day == null
              ? const SizedBox()
              : day.isRest
              ? _buildRestDay()
              : _buildWorkoutDay(day),
        ),
      ],
    );
  }

  // ── Edit-mode helpers ──────────────────────────────────────────────────────

  String get _currentWeekId => FirestoreService.weekIdFor(appNow());

  /// Enter / exit edit mode. On exit, guards against 0 exercises and prompts
  /// the user if they removed exercises without replacing them.
  void _toggleEditMode(WorkoutDay day) {
    if (!_editMode) {
      // Entering edit mode — snapshot the current count
      setState(() {
        _editMode = true;
        _editModeOriginalCount = day.exercises.length;
      });
      return;
    }

    // Exiting edit mode ─────────────────────────────────────────────────────
    final current = day.exercises.length;

    // Hard block: cannot finish editing with 0 exercises
    if (current == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Add at least one exercise before finishing.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return; // stay in edit mode
    }

    // Soft prompt: exercises were removed but not replaced
    if (current < _editModeOriginalCount) {
      final removed = _editModeOriginalCount - current;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) {
          final c = context.colors;
          return AlertDialog(
            backgroundColor: c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Session is shorter',
              style: GoogleFonts.spaceGrotesk(
                color: c.onBackground,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Text(
              'You removed $removed exercise${removed == 1 ? '' : 's'}. '
              'The algorithm can fill the gap with matching exercises, or you can '
              'leave the session shorter — skipped volume will be added to your '
              'next workout day${removed > 1 ? 's' : ''}.',
              style: GoogleFonts.inter(
                color: c.muted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _fillExerciseGap(day, removed);
                  setState(() => _editMode = false);
                },
                child: Text(
                  'Fill the gap',
                  style: GoogleFonts.inter(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _applyVolumeDebt(removed); // penalise upcoming days
                  setState(() => _editMode = false);
                },
                child: Text(
                  'Leave shorter',
                  style: GoogleFonts.inter(
                    color: c.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      );
      return; // wait for dialog result
    }

    setState(() => _editMode = false);
  }

  /// Same hard constraints as plan generation (gender variant, location,
  /// equipment, bench, experience level) so the picker/gap-fill/volume-debt
  /// paths can't inject exercises the user can't perform. Permissive only
  /// while the profile hasn't loaded yet.
  bool _usableByUser(Exercise e) {
    final p = _profile;
    if (p == null) return true;
    return GreedyAlgorithm.isEligibleForUser(e, p) &&
        GreedyAlgorithm.difficultyAllowed(e.difficulty, p.experienceLevel);
  }

  /// Reorders auto-refill candidates so exercises WITH a demo GIF come first
  /// (shuffled within each tier). Callers take from the front, so no-GIF
  /// exercises are only used when the GIF-having pool is exhausted — mirroring
  /// the generator's gif-first preference. The manual picker does NOT use this.
  List<Exercise> _gifPreferred(List<Exercise> candidates) {
    final shuffled = [...candidates]..shuffle();
    bool hasGif(Exercise e) => e.gifUrl?.isNotEmpty ?? false;
    return [...shuffled.where(hasGif), ...shuffled.where((e) => !hasGif(e))];
  }

  /// All restrictions [e] fails for the current profile, as warn-then-allow
  /// messages: equipment/location (via [GreedyAlgorithm.equipmentRestrictions])
  /// plus the experience-tier note. Empty when the user can perform it freely.
  /// The picker shows every exercise and surfaces these on add — the automatic
  /// generation / gap-fill / volume-debt paths keep the full [_usableByUser]
  /// gate so the algorithm never auto-injects restricted moves.
  List<String> _restrictionsFor(Exercise e) {
    final p = _profile;
    if (p == null) return const [];
    final reasons = GreedyAlgorithm.equipmentRestrictions(e, p);
    if (_isAboveUserTier(e)) {
      reasons.add(
        'Rated ${e.difficulty}, above your ${p.experienceLevel} level.',
      );
    }
    return reasons;
  }

  /// True when [e] is above the user's experience tier (informational badge +
  /// confirm in the picker).
  bool _isAboveUserTier(Exercise e) {
    final p = _profile;
    if (p == null) return false;
    return !GreedyAlgorithm.difficultyAllowed(e.difficulty, p.experienceLevel);
  }

  /// Small difficulty chip for picker rows. Amber when the move is above the
  /// user's tier, muted green when it's at or below.
  Widget _difficultyBadge(String difficulty, bool aboveTier) {
    final color = aboveTier ? AppColors.amber : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        difficulty[0].toUpperCase() + difficulty.substring(1),
        style: GoogleFonts.inter(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Informed-consent confirm when the user picks an above-tier exercise.
  Future<bool?> _confirmRestrictions(Exercise e, List<String> reasons) {
    final c = context.colors;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Check before adding',
          style: GoogleFonts.spaceGrotesk(
            color: c.onBackground,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${e.name}" has the following restrictions for your profile:',
              style: GoogleFonts.inter(color: c.muted, fontSize: 14),
            ),
            const SizedBox(height: 10),
            ...reasons.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '•  ',
                      style: GoogleFonts.inter(
                        color: AppColors.amber,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        r,
                        style: GoogleFonts.inter(
                          color: c.onBackground,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add it anyway?',
              style: GoogleFonts.inter(color: c.muted, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: c.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Add anyway',
              style: GoogleFonts.inter(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Re-filters a (rehydrated) plan against [profile]'s hard constraints +
  /// experience gate, dropping exercises the user can no longer perform and
  /// refilling each day back to its original size from the eligible pool
  /// (`_allExercises`). Bodyweight is always eligible at Home, so a day never
  /// ends up empty. Pure/in-memory — returns the new plan and whether anything
  /// changed (so the caller can re-persist only when needed).
  ({List<WorkoutDay> plan, bool changed}) _sanitizePlanForProfile(
    List<WorkoutDay> plan,
    UserProfile profile,
  ) {
    bool eligible(Exercise e) =>
        GreedyAlgorithm.isEligibleForUser(e, profile) &&
        GreedyAlgorithm.difficultyAllowed(
          e.difficulty,
          profile.experienceLevel,
        );

    bool changed = false;
    final newPlan = <WorkoutDay>[];

    for (final day in plan) {
      if (day.isRest) {
        newPlan.add(day);
        continue;
      }
      final originalCount = day.exercises.length;
      final kept = day.exercises.where((we) => eligible(we.exercise)).toList();
      if (kept.length != originalCount) changed = true;

      // Refill back to the original count with eligible, on-focus, non-duplicate
      // exercises so the day keeps its planned volume.
      if (kept.length < originalCount) {
        final targets = _focusToMuscles(day.focus);
        final existingIds = kept.map((e) => e.exercise.id).toSet();
        final candidates = _gifPreferred(_allExercises.where((e) {
          if (existingIds.contains(e.id)) return false;
          if (!eligible(e)) return false;
          return targets.isEmpty || e.primaryMuscles.any(targets.contains);
        }).toList());

        for (final ex in candidates) {
          if (kept.length >= originalCount) break;
          kept.add(
            WorkoutExercise(
              exercise: ex,
              sets: 3,
              reps: '10-12',
              restSeconds: 60,
            ),
          );
          existingIds.add(ex.id);
        }
      }

      newPlan.add(
        WorkoutDay(
          dayName: day.dayName,
          focus: day.focus,
          isRest: day.isRest,
          exercises: kept,
        ),
      );
    }

    return (plan: newPlan, changed: changed);
  }

  /// Fills the gap left by removed exercises by pulling exercises from
  /// [_allExercises] that target the day's muscle groups.
  void _fillExerciseGap(WorkoutDay day, int count) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final targets = _focusToMuscles(day.focus);
    final existingIds = day.exercises.map((e) => e.exercise.id).toSet();

    final candidates = _gifPreferred(_allExercises.where((e) {
      if (existingIds.contains(e.id)) return false;
      if (!_usableByUser(e)) return false;
      return targets.isEmpty || e.primaryMuscles.any(targets.contains);
    }).toList());

    int added = 0;
    for (final ex in candidates) {
      if (added >= count) break;
      context.read<PlanProvider>().addExercise(
        uid,
        _currentWeekId,
        _selectedDay,
        WorkoutExercise(exercise: ex, sets: 3, reps: '10-12', restSeconds: 60),
      );
      added++;
    }
    setState(() => _plan = context.read<PlanProvider>().workoutPlan);
  }

  /// Adds 1 extra exercise to each of the next [debt] upcoming workout days
  /// to compensate for today's skipped volume.
  void _applyVolumeDebt(int debt) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    int debtLeft = debt.clamp(0, 3); // cap at 3 days of compensation

    for (int i = _selectedDay + 1; i < _plan.length && debtLeft > 0; i++) {
      final nextDay = _plan[i];
      if (nextDay.isRest) continue;

      final targets = _focusToMuscles(nextDay.focus);
      final existingIds = nextDay.exercises.map((e) => e.exercise.id).toSet();
      final candidates = _gifPreferred(_allExercises.where((e) {
        if (existingIds.contains(e.id)) return false;
        if (!_usableByUser(e)) return false;
        return targets.isEmpty || e.primaryMuscles.any(targets.contains);
      }).toList());

      if (candidates.isNotEmpty) {
        final ex = candidates.first;
        context.read<PlanProvider>().addExercise(
          uid,
          _currentWeekId,
          i,
          WorkoutExercise(
            exercise: ex,
            sets: 3,
            reps: '12-15',
            restSeconds: 60,
          ),
        );
        debtLeft--;
      }
    }
    setState(() => _plan = context.read<PlanProvider>().workoutPlan);
  }

  Widget _wrapWithEditControls(
    Widget card,
    WorkoutDay day,
    int exIdx,
    WorkoutExercise we,
  ) {
    final c = context.colors;
    final dayIdx = _selectedDay;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        // Delete button (top-right)
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () async {
              // 50% removal cap: can't go below half of the original count
              final currentCount = day.exercises.length;
              final minAllowed = (_editModeOriginalCount / 2).ceil();
              if (currentCount <= minAllowed) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'You can only remove up to 50% of exercises. '
                      'Add a replacement before removing more.',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: Colors.redAccent,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
                return;
              }
              await context.read<PlanProvider>().removeExercise(
                uid,
                _currentWeekId,
                dayIdx,
                exIdx,
              );
              setState(() => _plan = context.read<PlanProvider>().workoutPlan);
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
        // Edit sets/reps/rest button (bottom-right)
        Positioned(
          bottom: 16,
          right: 8,
          child: GestureDetector(
            onTap: () => _showParamsEditor(dayIdx, exIdx, we),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.borderLight),
              ),
              child: Text(
                'Edit',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReorderableExerciseList(WorkoutDay day) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: day.exercises.length,
      itemBuilder: (context, idx) {
        final we = day.exercises[idx];
        final card = _buildExerciseCard(
          we,
          idx + 1,
          isToday: false,
          isActive: false,
          isDone: false,
          workoutStarted: false,
        );
        final wrapped = _wrapWithEditControls(card, day, idx, we);
        return KeyedSubtree(
          key: ValueKey('reorder_${we.exercise.id}'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: wrapped),
              ReorderableDragStartListener(
                index: idx,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 20,
                  ),
                  child: Icon(Icons.drag_handle, color: context.colors.muted),
                ),
              ),
            ],
          ),
        );
      },
      onReorder: (oldIdx, newIdx) {
        context.read<PlanProvider>().reorderExercises(
          uid,
          _currentWeekId,
          _selectedDay,
          oldIdx,
          newIdx,
        );
        setState(() => _plan = context.read<PlanProvider>().workoutPlan);
      },
    );
  }

  Widget _buildAddExerciseButton(WorkoutDay day) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: GestureDetector(
        onTap: () => _showExercisePicker(day),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.4),
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, color: AppColors.primary, size: 18),
              const SizedBox(width: 6),
              Text(
                'Add exercise',
                style: GoogleFonts.inter(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showParamsEditor(int dayIdx, int exIdx, WorkoutExercise we) {
    int sets = we.sets;
    String reps = we.reps;
    int rest = we.restSeconds;
    final repsCtrl = TextEditingController(text: reps);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final c = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSt) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                we.exercise.name,
                style: GoogleFonts.spaceGrotesk(
                  color: c.onBackground,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 20),
              // Sets
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Sets', style: GoogleFonts.inter(color: c.muted)),
                  Row(
                    children: [
                      _paramBtn(
                        Icons.remove,
                        () => setSt(() => sets = (sets - 1).clamp(1, 10)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '$sets',
                          style: GoogleFonts.spaceGrotesk(
                            color: c.onBackground,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      _paramBtn(
                        Icons.add,
                        () => setSt(() => sets = (sets + 1).clamp(1, 10)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Reps
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Reps / Duration',
                    style: GoogleFonts.inter(color: c.muted),
                  ),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: repsCtrl,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(color: c.onBackground),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: c.inputFill,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (v) => reps = v,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Rest
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Rest (sec)', style: GoogleFonts.inter(color: c.muted)),
                  Row(
                    children: [
                      _paramBtn(
                        Icons.remove,
                        () => setSt(() => rest = (rest - 15).clamp(0, 300)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '${rest}s',
                          style: GoogleFonts.spaceGrotesk(
                            color: c.onBackground,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      _paramBtn(
                        Icons.add,
                        () => setSt(() => rest = (rest + 15).clamp(0, 300)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    // Close the keyboard before popping (see picker onTap) so
                    // the sheet unmount doesn't race the IME teardown.
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.pop(ctx);
                    await context.read<PlanProvider>().updateExerciseParams(
                      uid,
                      _currentWeekId,
                      dayIdx,
                      exIdx,
                      sets: sets,
                      reps: reps.isEmpty ? we.reps : reps,
                      restSeconds: rest,
                    );
                    setState(
                      () => _plan = context.read<PlanProvider>().workoutPlan,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: c.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Save',
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      // Defer to a post-frame callback so the sheet fully unmounts before the
      // reps controller is disposed (same crash class as the exercise picker).
      WidgetsBinding.instance.addPostFrameCallback((_) => repsCtrl.dispose());
    });
  }

  Widget _paramBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: context.colors.inputFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: context.colors.onBackground),
    ),
  );

  void _showExercisePicker(WorkoutDay day) {
    final targetMuscles = day.focus == 'Rest Day'
        ? <String>[]
        : _focusToMuscles(day.focus);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final planProvider = context.read<PlanProvider>();
    // Use cached exercises from the last generated plan's full list.
    // The picker shows EVERY exercise for the day's focus — including ones the
    // user lacks equipment for or that are above their tier — and surfaces any
    // restrictions as a warn-then-allow dialog on tap (see _restrictionsFor).
    final allEx = _allExercises;
    final relevant = allEx.where((e) {
      if (targetMuscles.isEmpty) return true;
      return e.primaryMuscles.any((m) => targetMuscles.contains(m));
    }).toList()..sort((a, b) => a.name.compareTo(b.name));

    final searchController = TextEditingController();

    final c = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (_, sc) => StatefulBuilder(
            builder: (context, setSheetState) {
              final query = searchController.text.trim().toLowerCase();
              final filtered = query.isEmpty
                  ? relevant
                  : relevant.where((e) {
                      if (e.name.toLowerCase().contains(query)) return true;
                      return e.primaryMuscles.any(
                        (m) => m.toLowerCase().contains(query),
                      );
                    }).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                    child: Text(
                      'Add exercise — ${day.focus}',
                      style: GoogleFonts.spaceGrotesk(
                        color: c.onBackground,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: searchController,
                      onChanged: (_) => setSheetState(() {}),
                      style: GoogleFonts.inter(color: c.onBackground),
                      cursorColor: AppColors.primary,
                      decoration: InputDecoration(
                        hintText: 'Search exercises',
                        hintStyle: GoogleFonts.inter(color: c.muted),
                        prefixIcon: Icon(Icons.search, color: c.muted),
                        suffixIcon: searchController.text.isEmpty
                            ? null
                            : IconButton(
                                icon: Icon(Icons.close, color: c.muted),
                                onPressed: () => setSheetState(
                                  () => searchController.clear(),
                                ),
                              ),
                        filled: true,
                        fillColor: c.background,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.primary),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No matching exercises found.',
                              style: GoogleFonts.inter(color: c.muted),
                            ),
                          )
                        : ListView.builder(
                            controller: sc,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final ex = filtered[i];
                              final aboveTier = _isAboveUserTier(ex);
                              // Already in this day → block re-adding (a duplicate
                              // id crashes the reorderable list). Show it disabled
                              // with an "Added" marker instead of the + affordance.
                              final alreadyAdded = day.exercises.any(
                                (w) => w.exercise.id == ex.id,
                              );
                              final equipReasons = _profile == null
                                  ? const <String>[]
                                  : GreedyAlgorithm.equipmentRestrictions(
                                      ex,
                                      _profile!,
                                    );
                              return ListTile(
                                enabled: !alreadyAdded,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                title: Text(
                                  ex.name,
                                  style: GoogleFonts.inter(
                                    color: alreadyAdded
                                        ? c.muted
                                        : c.onBackground,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        ex.primaryMuscles.join(', '),
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          color: c.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    if (ex.difficulty.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      _difficultyBadge(
                                        ex.difficulty,
                                        aboveTier,
                                      ),
                                    ],
                                    if (equipReasons.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        size: 16,
                                        color: AppColors.amber,
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: alreadyAdded
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.check_circle,
                                            size: 18,
                                            color: c.muted,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Added',
                                            style: GoogleFonts.inter(
                                              color: c.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Icon(
                                        Icons.add_circle_outline,
                                        color: AppColors.primary,
                                      ),
                                onTap: alreadyAdded
                                    ? null
                                    : () async {
                                        // If the keyboard is open, dismiss it first and
                                        // wait for its close animation (~300 ms) before
                                        // popping the sheet. Running both animations
                                        // simultaneously thrashes viewInsets and causes
                                        // a RenderFlex overflow crash on real devices.
                                        // Read viewInsets BEFORE unfocus() — unfocus()
                                        // clears the value immediately.
                                        final keyboardVisible =
                                            MediaQuery.of(
                                              ctx,
                                            ).viewInsets.bottom >
                                            0;
                                        FocusManager.instance.primaryFocus
                                            ?.unfocus();
                                        if (keyboardVisible) {
                                          await Future.delayed(
                                            const Duration(milliseconds: 300),
                                          );
                                        }
                                        if (!ctx.mounted) return;
                                        Navigator.pop(ctx);
                                        final reasons = _restrictionsFor(ex);
                                        if (reasons.isNotEmpty) {
                                          final ok = await _confirmRestrictions(
                                            ex,
                                            reasons,
                                          );
                                          if (ok != true) return;
                                        }
                                        final we = WorkoutExercise(
                                          exercise: ex,
                                          sets: 3,
                                          reps: '10-12',
                                          restSeconds: 60,
                                        );
                                        await planProvider.addExercise(
                                          uid,
                                          _currentWeekId,
                                          _selectedDay,
                                          we,
                                        );
                                        if (!mounted) return;
                                        setState(
                                          () =>
                                              _plan = planProvider.workoutPlan,
                                        );
                                      },
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ).whenComplete(() {
      // Defer disposing the search controller by one frame. Disposing it
      // synchronously as the sheet route completes races the focused
      // TextField's own teardown ("used after disposed") and corrupts the
      // Overlay unmount → framework '_dependents.isEmpty' crash on add. A
      // post-frame callback lets the sheet fully unmount first.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => searchController.dispose(),
      );
    });
  }

  /// Muscle targets for a focus string (used by exercise picker, gap-fill and
  /// volume-debt). Delegates to [GreedyAlgorithm.musclesForFocus] so it resolves
  /// muscles in the same ExerciseDB `targetMuscles` vocabulary the generator
  /// uses — otherwise the picker filters for 'chest' while exercises are tagged
  /// 'pectorals' and nothing matches.
  List<String> _focusToMuscles(String focus) =>
      GreedyAlgorithm.musclesForFocus(focus);

  Widget _buildRestDay() {
    final c = context.colors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bedtime_rounded, size: 64, color: c.subtle),
          const SizedBox(height: 16),
          Text(
            'Rest Day',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: c.onBackground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Recovery is part of the plan.',
            style: GoogleFonts.inter(color: c.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutDay(WorkoutDay day) {
    final c = context.colors;
    final isToday = _selectedDay == appNow().weekday - 1;
    final isCompleted = _todayLog != null && isToday;
    // The session covers the warm-up phase + the lifts; exercises stay locked
    // until the warm-up finishes/skips.
    final workoutStarted = _sessionStarted;
    final exercisesLocked = _sessionStarted && !_warmupComplete;

    // Build per-exercise cards (not used in edit mode — handled by
    // _buildReorderableExerciseList for drag-to-reorder support).
    final exerciseCards = <Widget>[];
    if (!_editMode || workoutStarted) {
      for (int i = 0; i < day.exercises.length; i++) {
        final we = day.exercises[i];
        final bool isActive = (i == _activeExerciseIndex) && !_waitingForReady;
        final bool isDone = _completedExercises.contains(i);
        final bool isReadySlot =
            _waitingForReady && (i == _activeExerciseIndex + 1);
        final bool needsKey = isActive || isReadySlot;

        final Widget card = isReadySlot
            ? _buildReadyCard(we)
            : _buildExerciseCard(
                we,
                i + 1,
                isToday: isToday && !isCompleted,
                isActive: isActive,
                isDone: isDone,
                workoutStarted: workoutStarted,
              );

        exerciseCards.add(
          Container(
            key: needsKey ? _activeKey : ValueKey('ex_$i'),
            child: card,
          ),
        );
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      day.dayName,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: c.onBackground,
                      ),
                    ),
                    Text(
                      day.focus,
                      style: GoogleFonts.inter(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (isToday && isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.primary,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Completed · ${_todayLog!.durationMinutes} min',
                        style: GoogleFonts.inter(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${day.exercises.length} exercises',
                    style: GoogleFonts.inter(color: c.muted, fontSize: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Edit session toggle (only when workout hasn't started)
          if (!workoutStarted && !isCompleted)
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => _toggleEditMode(day),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _editMode
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : c.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _editMode ? AppColors.primary : c.borderLight,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _editMode ? Icons.check_rounded : Icons.edit_rounded,
                        size: 14,
                        color: _editMode ? AppColors.primary : c.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _editMode ? 'Done editing' : 'Edit session',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _editMode ? AppColors.primary : c.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!workoutStarted && !isCompleted) const SizedBox(height: 8),

          // Live progress bar (while workout is in progress)
          if (workoutStarted && !isCompleted) ...[
            Row(
              children: [
                Text(
                  '${_completedExercises.length} / ${day.exercises.length}',
                  style: GoogleFonts.spaceGrotesk(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: day.exercises.isEmpty
                          ? 0
                          : _completedExercises.length / day.exercises.length,
                      backgroundColor: c.border,
                      valueColor: AlwaysStoppedAnimation(AppColors.primary),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _formatElapsed(_elapsedSeconds),
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Start Workout button (today, not completed, not yet started, has exercises)
          if (isToday &&
              !isCompleted &&
              !workoutStarted &&
              day.exercises.isNotEmpty) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startWorkout,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  'Start Workout',
                  style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: c.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Debug: one-tap auto-complete (only when kDebugAutoFinishWorkout = true)
          if (kDebugAutoFinishWorkout &&
              !isCompleted &&
              day.exercises.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _debugAutoCompleteDay(day),
                icon: const Icon(Icons.bolt, size: 16, color: Colors.amber),
                label: Text(
                  'Auto-Complete',
                  style: GoogleFonts.inter(color: Colors.red, fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // General (cardio) warm-up — top of the active day, skippable.
          if (workoutStarted && !isCompleted) _buildGeneralWarmup(),

          // Exercise cards
          if (_editMode && !workoutStarted) ...[
            // Drag-to-reorder list with edit controls + drag handles
            _buildReorderableExerciseList(day),
            _buildAddExerciseButton(day),
          ] else if (exercisesLocked)
            IgnorePointer(
              child: Opacity(
                opacity: 0.4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: exerciseCards,
                ),
              ),
            )
          else
            ...exerciseCards,
        ],
      ),
    );
  }

  // "Up Next / I'm Ready!" card shown between exercises
  Widget _buildReadyCard(WorkoutExercise we) {
    final c = context.colors;
    final ex = we.exercise;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Up Next',
            style: GoogleFonts.inter(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ex.name,
            style: GoogleFonts.spaceGrotesk(
              color: c.onBackground,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '${ex.primaryMuscles.join(', ')} · ${we.sets} sets · ${we.reps} reps · ${we.restSeconds}s rest · ${we.timePerSetSeconds}s/set',
            style: GoogleFonts.inter(color: c.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: (ex.gifUrl?.isNotEmpty == true)
                ? () => _showGifDialog(context, ex.gifUrl!, ex.name)
                : null,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: (ex.gifUrl?.isNotEmpty == true)
                      ? _gifImage(
                          ex.gifUrl!,
                          key: ValueKey('gif_ready_${ex.id}'),
                          height: 140,
                          width: double.infinity,
                          loading: _gifPlaceholder(loading: true, height: 140),
                        )
                      : _gifPlaceholder(height: 140),
                ),
                if (ex.gifUrl?.isNotEmpty == true)
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.shadow,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: c.onBackground,
                      size: 26,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _iAmReady,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: c.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                "I'm Ready!",
                style: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Collapsible step-by-step instructions on an exercise card. Collapsed by
  /// default (keeps cards compact); tap to reveal. Available on active and
  /// non-active cards, keyed by exercise index.
  Widget _buildStepsExpander(Exercise ex, int exIndex) {
    final c = context.colors;
    final expanded = _expandedSteps.contains(exIndex);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            if (expanded) {
              _expandedSteps.remove(exIndex);
            } else {
              _expandedSteps.add(exIndex);
            }
          }),
          child: Row(
            children: [
              Icon(Icons.menu_book_rounded, color: c.muted, size: 14),
              const SizedBox(width: 6),
              Text(
                'Steps',
                style: GoogleFonts.inter(
                  color: c.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: c.muted,
                size: 18,
              ),
            ],
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              ex.instructions,
              style: GoogleFonts.inter(
                color: c.muted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildExerciseCard(
    WorkoutExercise we,
    int number, {
    required bool isToday,
    required bool isActive,
    required bool isDone,
    required bool workoutStarted,
  }) {
    final c = context.colors;
    final ex = we.exercise;
    final String focus = _selectedDay < _plan.length
        ? _plan[_selectedDay].focus
        : '';
    final double gifHeight = isActive ? 200 : 160;

    // Number circle: checkmark when done, number otherwise
    Widget numberCircle = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isDone ? AppColors.primary : AppColors.primary.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: isDone
            ? Icon(Icons.check_rounded, color: c.onPrimary, size: 16)
            : Text(
                '$number',
                style: GoogleFonts.spaceGrotesk(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );

    // Treat empty-string gifUrl the same as null — empty string passes != null
    // but Image.network("") fails silently and never renders the animation.
    final String? gifUrl = (ex.gifUrl != null && ex.gifUrl!.isNotEmpty)
        ? ex.gifUrl
        : null;

    // GIF section
    Widget gifSection = GestureDetector(
      onTap: gifUrl != null
          ? () => _showGifDialog(context, gifUrl, ex.name)
          : null,
      child: isActive
          // Active: plain GIF (no overlay — they're using it)
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: gifUrl != null
                  ? _gifImage(
                      gifUrl,
                      key: ValueKey('gif_active_${ex.id}'),
                      height: gifHeight,
                      width: double.infinity,
                      loading: _gifPlaceholder(
                        loading: true,
                        height: gifHeight,
                      ),
                    )
                  : _gifPlaceholder(height: gifHeight),
            )
          // Normal/done: GIF with play button overlay
          : Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: gifUrl != null
                      ? _gifImage(
                          gifUrl,
                          key: ValueKey('gif_idle_${ex.id}'),
                          height: gifHeight,
                          width: double.infinity,
                          loading: _gifPlaceholder(
                            loading: true,
                            height: gifHeight,
                          ),
                        )
                      : _gifPlaceholder(height: gifHeight),
                ),
                if (gifUrl != null)
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.shadow,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: c.onBackground,
                      size: 26,
                    ),
                  ),
              ],
            ),
    );

    // Opacity: done = 55%, upcoming-while-workout-started = 65%, otherwise 100%
    final double opacity = isDone
        ? 0.55
        : (workoutStarted && !isActive ? 0.65 : 1.0);

    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 300),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? AppColors.primary.withOpacity(0.6) : c.border,
            width: isActive ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: number circle + name/muscle + difficulty badge
            Row(
              children: [
                numberCircle,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ex.name,
                        style: GoogleFonts.spaceGrotesk(
                          color: c.onBackground,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        ex.primaryMuscles.join(', '),
                        style: GoogleFonts.inter(color: c.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (!isActive && focus.isNotEmpty) _pinButton(focus, ex),
                _diffBadge(ex.difficulty),
              ],
            ),

            if (isActive) ...[
              // ── Active card ──────────────────────────────────────────────
              const SizedBox(height: 12),
              gifSection,
              if (ex.instructions.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildStepsExpander(ex, number - 1),
              ],
              const SizedBox(height: 16),

              if (_inRest) ...[
                // Rest phase
                Text(
                  'Rest',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white54,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatCountdown(_restRemaining),
                  style: GoogleFonts.spaceGrotesk(
                    color: c.onBackground,
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _restTotal > 0 ? _restRemaining / _restTotal : 0,
                    backgroundColor: c.border,
                    valueColor: AlwaysStoppedAnimation(AppColors.primary),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _skipRest,
                    child: Text(
                      'Skip Rest',
                      style: GoogleFonts.inter(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // Set phase
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ...List.generate(
                      we.sets,
                      (i) => Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _activeSetNumber
                              ? AppColors.primary
                              : c.border,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Set $_activeSetNumber of ${we.sets}',
                      style: GoogleFonts.spaceGrotesk(
                        color: c.onBackground,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!_setRunning) ...[
                  // Logging sub-phase: enter kg/reps, then "Start Set" (ready gate).
                  _buildWeightInput(we),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _startSet(we),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: Text(
                        'Start Set',
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: c.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _skipExercise(we),
                      icon: const Icon(Icons.skip_next_rounded, size: 18),
                      label: Text(
                        'Skip exercise',
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                      style: TextButton.styleFrom(foregroundColor: c.muted),
                    ),
                  ),
                ] else ...[
                  // Working sub-phase: per-set work timer counting down.
                  if (_loggedSetSummary().isNotEmpty)
                    Text(
                      _loggedSetSummary(),
                      style: GoogleFonts.inter(color: c.muted, fontSize: 13),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Work',
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatCountdown(_setRemaining),
                    style: GoogleFonts.spaceGrotesk(
                      color: c.onBackground,
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _setTotal > 0 ? _setRemaining / _setTotal : 0,
                      backgroundColor: c.border,
                      valueColor: AlwaysStoppedAnimation(AppColors.primary),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _finishSet(we),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        'Done',
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: c.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ] else ...[
              // ── Normal / done card ───────────────────────────────────────
              const SizedBox(height: 12),
              Row(
                children: [
                  _statBox('Sets', '${we.sets}', AppColors.primary),
                  const SizedBox(width: 8),
                  _statBox('Reps', we.reps, AppColors.purple),
                  const SizedBox(width: 8),
                  _statBox('Rest', '${we.restSeconds}s', AppColors.orange),
                  const SizedBox(width: 8),
                  _statBox(
                    'Time/set',
                    '${we.timePerSetSeconds}s',
                    AppColors.cyan,
                  ),
                ],
              ),
              _lastPrLine(ex),
              if (ex.instructions.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildStepsExpander(ex, number - 1),
              ],
              const SizedBox(height: 12),
              gifSection,
            ],
          ],
        ),
      ),
    );
  }

  /// Demo GIF via the [CachedNetworkImage] widget: each GIF downloads once, then
  /// renders instantly (and offline) from the disk cache on every later view.
  /// Placeholder/error are driven by the widget (via OctoImage), NOT by Image's
  /// frameBuilder — the frameBuilder approach is the one that gets stuck on the
  /// spinner forever (flutter/flutter#71290: the builder isn't re-invoked once
  /// the decoded frame arrives). The widget still animates GIFs on Android/
  /// Windows via MultiImageStreamCompleter.
  Widget _gifImage(
    String url, {
    Key? key,
    double? height,
    double? width,
    BoxFit fit = BoxFit.cover,
    Widget? loading,
    Widget? error,
  }) {
    return CachedNetworkImage(
      key: key,
      imageUrl: url,
      httpHeaders: const {'User-Agent': 'OneFit/1.0'},
      height: height,
      width: width,
      fit: fit,
      fadeInDuration: Duration.zero,
      useOldImageOnUrlChange: true, // gaplessPlayback-like: hold prior GIF
      placeholder: (_, _) =>
          loading ?? _gifPlaceholder(loading: true, height: height ?? 160),
      errorWidget: (_, _, _) =>
          error ?? _gifPlaceholder(height: height ?? 160),
    );
  }

  Widget _gifPlaceholder({bool loading = false, double height = 160}) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      height: height,
      color: c.inputFill,
      child: loading
          ? Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.play_circle_outline_rounded,
                  color: c.subtle,
                  size: 48,
                ),
                const SizedBox(height: 10),
                Text(
                  'Exercise Demo',
                  style: GoogleFonts.inter(
                    color: c.subtle,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
    );
  }

  void _showGifDialog(BuildContext context, String gifUrl, String name) {
    final c = context.colors;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: c.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: GoogleFonts.spaceGrotesk(
                  color: c.onBackground,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _gifImage(
                  gifUrl,
                  fit: BoxFit.contain,
                  loading: _gifPlaceholder(loading: true, height: 200),
                  error: Icon(Icons.broken_image, color: c.subtle, size: 60),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Close',
                  style: GoogleFonts.inter(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statBox(String label, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color.withOpacity(0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _diffBadge(String d) {
    final c = d == 'beginner'
        ? AppColors.primary
        : d == 'intermediate'
        ? AppColors.orange
        : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        d,
        style: GoogleFonts.inter(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── MEAL TAB ─────────────────────────────────────────────────────────────────
class _MealTab extends StatefulWidget {
  /// When non-null, the tab will auto-scroll to this meal card on first build.
  final String? focusMealType;

  const _MealTab({this.focusMealType});

  @override
  State<_MealTab> createState() => _MealTabState();
}

class _MealTabState extends State<_MealTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Meal? _pendingBreakfast;
  Meal? _pendingLunch;
  Meal? _pendingDinner;
  Meal? _pendingSnack;

  final Set<String> _loadingMeals = {};

  // Meal types whose nutrition summary is expanded to show full macros + micros.
  final Set<String> _expandedMacros = {};

  // USDA ingredient pool the Genetic Algorithm draws on (loaded once).
  List<MealIngredient> _allIngredients = [];

  UserProfile? _profile;
  bool _isInitializing = true;
  String _cuisine = 'any';

  Map<String, List<FoodItem>> _loggedFoods = {
    'breakfast': [],
    'lunch': [],
    'dinner': [],
    'snack': [],
  };

  // ── Scroll keys — one per meal card so we can jump to any of them ──────────
  final Map<String, GlobalKey> _mealKeys = {
    'breakfast': GlobalKey(),
    'lunch': GlobalKey(),
    'dinner': GlobalKey(),
    'snack': GlobalKey(),
  };

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadTodayLogs().then((_) {
      if (widget.focusMealType != null) {
        _scrollToMeal(widget.focusMealType!);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Scrolls the meal list so the card for [mealType] is visible.
  void _scrollToMeal(String mealType) {
    final key = _mealKeys[mealType];
    if (key == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = key.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.1, // show the card near the top with a little padding
        );
      }
    });
  }

  Future<void> _loadProfile() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final profileProvider = context.read<ProfileProvider>();
      await profileProvider.load(uid);
      // Load the USDA ingredient pool for the Genetic Algorithm (cached).
      final ingredients = await FirestoreService().getIngredients();
      if (mounted)
        setState(() {
          _profile = profileProvider.profile;
          _allIngredients = ingredients;
          _isInitializing = false;
        });
    } catch (e) {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _loadTodayLogs() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final logs = await FirestoreService().getFoodLogsForDate(uid, appNow());
      final grouped = <String, List<FoodItem>>{
        'breakfast': [],
        'lunch': [],
        'dinner': [],
        'snack': [],
      };
      for (final log in logs) {
        grouped[log.mealType.toLowerCase()]?.add(log);
      }
      if (mounted) setState(() => _loggedFoods = grouped);
    } catch (_) {}
  }

  double _totalCals() {
    double total = 0;
    for (final foods in _loggedFoods.values) {
      for (final f in foods) total += f.totalCalories;
    }
    total +=
        (_pendingBreakfast?.totalCalories ?? 0) +
        (_pendingLunch?.totalCalories ?? 0) +
        (_pendingDinner?.totalCalories ?? 0) +
        (_pendingSnack?.totalCalories ?? 0);
    return total;
  }

  Meal? _pending(String mealType) => mealType == 'breakfast'
      ? _pendingBreakfast
      : mealType == 'lunch'
      ? _pendingLunch
      : mealType == 'dinner'
      ? _pendingDinner
      : _pendingSnack;

  void _setPending(String mealType, Meal? meal) {
    setState(() {
      if (mealType == 'breakfast') _pendingBreakfast = meal;
      if (mealType == 'lunch') _pendingLunch = meal;
      if (mealType == 'dinner') _pendingDinner = meal;
      if (mealType == 'snack') _pendingSnack = meal;
    });
  }

  // ── Generation (budget-aware meal completion over USDA ingredients) ─────────

  /// Daily calorie share for [mealType] (GA's fixed meal ratios).
  double _ratioFor(String mealType) => switch (mealType) {
    'breakfast' => GeneticAlgorithm.breakfastRatio,
    'lunch' => GeneticAlgorithm.lunchRatio,
    'dinner' => GeneticAlgorithm.dinnerRatio,
    _ => GeneticAlgorithm.snackRatio,
  };

  /// Calories already logged into [mealType] today.
  double _loggedCals(String mealType) =>
      (_loggedFoods[mealType] ?? []).fold(0.0, (s, f) => s + f.totalCalories);

  /// Food groups already present in [mealType] (so completion complements them
  /// instead of repeating). Mirrors the GA's own pool partitioning thresholds.
  Set<String> _presentCategories(String mealType) =>
      (_loggedFoods[mealType] ?? []).map(_inferCategory).toSet();

  /// Coarse food group of a logged [FoodItem]: protein/grain/vegetable/fruit/fat.
  /// FoodItems carry no category, so infer it from name hints + macro
  /// thresholds via the shared [IngredientConverter] heuristic (per-serving
  /// values are passed directly — same absolute cuts as always).
  String _inferCategory(FoodItem f) => IngredientConverter.inferCategory(
    name: f.name,
    caloriesPer100: f.calories,
    proteinPer100: f.protein,
    carbsPer100: f.carbs,
    fatPer100: f.fat,
  );

  void _showNoMatchMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No ingredients match your dietary restrictions.'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: context.colors.surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// True when the ingredient pool hasn't been seeded; surfaces a hint instead
  /// of silently producing empty meals.
  bool _guardIngredients() {
    if (_allIngredients.isNotEmpty) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingredient database not seeded yet.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return false;
  }

  // ── Meal Planning (Module 1): Generate Meal → GA → review → accept ────────

  /// Entry point for the meal-card **Generate** button. The user picks how to
  /// plan (Option A: their available ingredients; Option B: automatic from the
  /// seeded pool), the GA optimizes all grams against the meal's remaining
  /// calorie budget, and the result is reviewed on the accept-mode
  /// RecipeScreen before anything is logged.
  Future<void> _startGenerateFlow(String mealType, String label) async {
    if (_profile == null) return;
    final goal = context.read<ProfileProvider>().dailyEffectiveGoal.toDouble();
    final budget = (_ratioFor(mealType) * goal - _loggedCals(mealType)).clamp(
      0.0,
      double.infinity,
    );
    final hasLogged = (_loggedFoods[mealType] ?? []).isNotEmpty;
    if (budget <= 30) {
      _showInfo(
        hasLogged
            ? 'This meal already meets its calorie share.'
            : 'No calories left for this meal today.',
      );
      return;
    }

    final option = await _chooseGenerateOption();
    if (option == null || !mounted) return;

    List<MealIngredient>? pickedPool;
    if (option == 'available') {
      pickedPool = await Navigator.push<List<MealIngredient>>(
        context,
        MaterialPageRoute(
          builder: (_) => FoodLogScreen(mealType: mealType, pickerMode: true),
        ),
      );
      if (pickedPool == null || pickedPool.isEmpty || !mounted) return;
      // Defense in depth: the picker already blocks restricted foods, but the
      // pool must never reach the GA with a violating name.
      final restrictions = _profile!.dietaryRestrictions;
      pickedPool = pickedPool
          .where((i) => !DietaryFilter.violates(i.name, restrictions))
          .toList();
      if (pickedPool.isEmpty) {
        _showNoMatchMessage();
        return;
      }
    } else if (!_guardIngredients()) {
      return;
    }

    // One closure serves both first generation and every Regenerate, keeping
    // the chosen option (and Option A's picked pool) fixed for the session.
    // Option A ignores avoidIds — all picked ingredients must stay; a fresh
    // RNG explores different gram vectors instead.
    Meal? run({Set<String> avoidIds = const {}}) {
      final result = option == 'available'
          ? GeneticAlgorithm().optimizeMealPortions(
              ingredients: pickedPool!,
              profile: _profile!,
              mealType: mealType,
              calorieBudget: budget,
            )
          : GeneticAlgorithm().evolveMeal(
              allIngredients: _allIngredients,
              profile: _profile!,
              mealType: mealType,
              calorieBudget: budget,
              presentCategories: _presentCategories(mealType),
              cuisine: _cuisine,
              avoidIds: avoidIds,
            );
      return result.meal.items.isEmpty ? null : result.meal;
    }

    setState(() => _loadingMeals.add(mealType));
    Meal? meal;
    try {
      meal = run();
    } finally {
      if (mounted) setState(() => _loadingMeals.remove(mealType));
    }
    if (!mounted) return;
    if (meal == null) {
      _showNoMatchMessage();
      return;
    }
    await _reviewAndAccept(mealType, label, meal, run);
  }

  /// Option chooser: 'available' (Option A) | 'auto' (Option B) | null.
  Future<String?> _chooseGenerateOption() {
    final c = context.colors;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SingleChildScrollView(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                child: Text(
                  'Generate Meal',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: c.onBackground,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.kitchen_rounded,
                  color: AppColors.primary,
                ),
                title: Text(
                  'Use My Ingredients',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: c.onBackground,
                  ),
                ),
                subtitle: Text(
                  'Pick the ingredients you have and AI decides the amounts',
                  style: GoogleFonts.inter(fontSize: 12, color: c.muted),
                ),
                onTap: () => Navigator.pop(sheetCtx, 'available'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.purple,
                ),
                title: Text(
                  'Generate Automatically',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: c.onBackground,
                  ),
                ),
                subtitle: Text(
                  'AI picks foods and amounts from the ingredient database',
                  style: GoogleFonts.inter(fontSize: 12, color: c.muted),
                ),
                onTap: () => Navigator.pop(sheetCtx, 'auto'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Accept/Regenerate loop over the accept-mode [RecipeScreen]. Accept logs
  /// the meal through the standard `ai_generated` FoodItem path, after which
  /// it behaves like any logged meal (editable, deletable). Back = discard.
  Future<void> _reviewAndAccept(
    String mealType,
    String label,
    Meal meal,
    Meal? Function({Set<String> avoidIds}) regenerate,
  ) async {
    var current = meal;
    while (mounted) {
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              RecipeScreen(meal: current, mealLabel: label, acceptMode: true),
        ),
      );
      if (!mounted) return;
      if (result == 'accept') {
        try {
          // Same persistence path as staged meals: one 'ai_generated'
          // FoodItem per ingredient — accepted food IS logged food.
          await context.read<PlanProvider>().setMeal(
            mealType,
            current,
            saveToFirestore: true,
          );
          await _loadTodayLogs();
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null && mounted) {
            context.read<ProfileProvider>().recomputeGoal(uid).ignore();
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$label added to your day!'),
                backgroundColor: AppColors.primary,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: $e'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        }
        return;
      }
      if (result == 'regenerate') {
        final avoid = current.items.map((i) => i.ingredient.id).toSet();
        setState(() => _loadingMeals.add(mealType));
        Meal? next;
        try {
          next = regenerate(avoidIds: avoid);
        } finally {
          if (mounted) setState(() => _loadingMeals.remove(mealType));
        }
        if (!mounted) return;
        if (next == null) {
          _showNoMatchMessage();
          return;
        }
        current = next;
        continue;
      }
      return; // back button — discard silently
    }
  }

  Future<void> _generateAll() async {
    if (_profile == null || !_guardIngredients()) return;
    const allMeals = ['breakfast', 'lunch', 'dinner', 'snack'];

    setState(() => _loadingMeals.addAll(allMeals));
    try {
      final goal = context
          .read<ProfileProvider>()
          .dailyEffectiveGoal
          .toDouble();
      // Distribute the day's *remaining* budget across meals so logged +
      // generated ≈ goal. Logged meals get a proportionally smaller addition
      // (and are completed, not skipped).
      final budgets = GeneticAlgorithm.mealBudgets(
        goal: goal,
        loggedCalsByMeal: {for (final m in allMeals) m: _loggedCals(m)},
      );
      if (budgets.values.every((b) => b <= 30)) {
        _showInfo("Today's meals already meet your calorie goal.");
        return;
      }

      bool anyMatchFailure = false;
      // Ingredients already used by earlier meals today — evolveMeal penalises
      // (not excludes) repeats so the generated day stays varied.
      final usedIds = <String>{};
      for (final mealType in allMeals) {
        final budget = budgets[mealType] ?? 0;
        if (budget <= 30) continue; // meal already at/over its share
        final meal = GeneticAlgorithm()
            .evolveMeal(
              allIngredients: _allIngredients,
              profile: _profile!,
              mealType: mealType,
              calorieBudget: budget,
              presentCategories: _presentCategories(mealType),
              cuisine: _cuisine,
              avoidIds: usedIds,
            )
            .meal;
        if (meal.items.isEmpty) {
          anyMatchFailure = true;
          continue;
        }
        usedIds.addAll(meal.items.map((i) => i.ingredient.id));
        _setPending(mealType, meal);
        context.read<PlanProvider>().setMeal(
          mealType,
          meal,
          saveToFirestore: false,
        );
      }
      if (anyMatchFailure) _showNoMatchMessage();
    } finally {
      if (mounted) setState(() => _loadingMeals.clear());
    }
  }

  Future<void> _logPendingMeal(String mealType) async {
    final meal = _pending(mealType);
    if (meal == null) return;
    try {
      // GA meals are ingredient lists — each ingredient is saved as its own
      // FoodItem (scaled to grams) via _saveMealToFirestore.
      await context.read<PlanProvider>().setMeal(
        mealType,
        meal,
        saveToFirestore: true,
      );
      _setPending(mealType, null);
      await _loadTodayLogs();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && mounted) {
        context.read<ProfileProvider>().recomputeGoal(uid).ignore();
      }
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_capitalize(mealType)} logged!'),
            backgroundColor: AppColors.primary,
            duration: const Duration(seconds: 2),
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
    }
  }

  Future<void> _clearAll(String mealType) async {
    _setPending(mealType, null);
    context.read<PlanProvider>().setMeal(mealType, null);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      for (final log in (_loggedFoods[mealType] ?? [])) {
        await FirestoreService().deleteFoodLog(user.uid, log.id);
      }
      await _loadTodayLogs();
    }
  }

  /// Nutrition Tracking (Module 2): edit the consumed amount of a logged item
  /// (grams for gram-based items — covers ai_generated and USDA logs — or a
  /// servings multiplier otherwise), or delete it. Editing writes only the
  /// `quantity` multiplier, so nutrition rescales without recomputation.
  Meal _mealFromLoggedFoods(String mealType, List<FoodItem> foods) {
    final items = foods
        .map(
          (f) => MealItem(
            ingredient: IngredientConverter.fromFoodItem(f),
            portionGrams: f.servingSize * f.quantity,
          ),
        )
        .toList();
    return Meal(mealType: mealType, items: items);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isInitializing) return _buildLoading('Loading...', ctx: context);
    return _buildPlan();
  }

  Widget _buildPlan() {
    final c = context.colors;
    final totalCals = _totalCals();
    final targetCal = context.watch<ProfileProvider>().dailyEffectiveGoal;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (_profile != null) ...[
                _chip(_profile!.fitnessGoal, AppColors.primary),
                const SizedBox(width: 6),
                _chip('$targetCal kcal', AppColors.orange),
              ],
              const Spacer(),
              PopupMenuButton<String>(
                color: c.surface,
                icon: Icon(
                  Icons.restaurant_menu_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
                onSelected: (val) => setState(() => _cuisine = val),
                itemBuilder: (_) => [
                  _menuItem('any', 'Any Cuisine'),
                  _menuItem('filipino', '🇵🇭 Filipino'),
                  _menuItem('western', '🌎 Western'),
                  _menuItem('asian', '🌏 Asian'),
                ],
              ),
              TextButton.icon(
                onPressed: _generateAll,
                icon: Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                label: Text(
                  'All',
                  style: GoogleFonts.inter(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(
                  '${totalCals.round()} / $targetCal kcal',
                  style: GoogleFonts.spaceGrotesk(
                    color: c.onBackground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (totalCals / targetCal).clamp(0.0, 1.1),
                      backgroundColor: c.border,
                      valueColor: AlwaysStoppedAnimation(
                        totalCals > targetCal * 1.05
                            ? Colors.redAccent
                            : AppColors.primary,
                      ),
                      minHeight: 6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: c.surface,
            onRefresh: _loadTodayLogs,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                children: [
                  // Each card receives its GlobalKey so _scrollToMeal can find it.
                  _buildMealCard(
                    'breakfast',
                    '🌅',
                    'Breakfast',
                    key: _mealKeys['breakfast']!,
                  ),
                  const SizedBox(height: 12),
                  _buildMealCard(
                    'lunch',
                    '☀️',
                    'Lunch',
                    key: _mealKeys['lunch']!,
                  ),
                  const SizedBox(height: 12),
                  _buildMealCard(
                    'dinner',
                    '🌙',
                    'Dinner',
                    key: _mealKeys['dinner']!,
                  ),
                  const SizedBox(height: 12),
                  _buildMealCard(
                    'snack',
                    '🍎',
                    'Snack',
                    key: _mealKeys['snack']!,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Added `key` parameter so each card can be scrolled to.
  Widget _buildMealCard(
    String mealType,
    String emoji,
    String label, {
    Key? key,
  }) {
    final isLoading = _loadingMeals.contains(mealType);
    final loggedFoods = _loggedFoods[mealType] ?? [];
    final pendingMeal = _pending(mealType);
    final hasManual = loggedFoods.isNotEmpty;
    final hasContent = hasManual || pendingMeal != null;

    // Highlight the focused card with a green border accent
    final isFocused = widget.focusMealType == mealType;

    double cardCals = loggedFoods.fold(0.0, (s, f) => s + f.totalCalories);
    if (pendingMeal != null) cardCals += pendingMeal.totalCalories;

    final c = context.colors;
    return Container(
      key: key,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          // Green border for the card the user tapped from Nutrition screen
          color: isFocused ? AppColors.primary : c.border,
          width: isFocused ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  color: c.onBackground,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              if (hasContent) ...[
                Text(
                  '${cardCals.round()} kcal',
                  style: GoogleFonts.inter(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _clearAll(mealType),
                  child: Icon(Icons.close_rounded, color: c.inactive, size: 18),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: c.border, height: 1),
          const SizedBox(height: 12),
          if (isLoading)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2,
                ),
              ),
            )
          else if (!hasContent)
            _buildEmptyCard(mealType, label)
          else
            _buildFilledCard(
              mealType,
              label,
              loggedFoods,
              pendingMeal,
              hasManual,
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String mealType, String label) {
    final c = context.colors;
    return Column(
      children: [
        Row(
          children: [
            Icon(
              Icons.add_circle_outline_rounded,
              color: c.borderLight,
              size: 32,
            ),
            const SizedBox(width: 12),
            Text(
              'No $label added yet',
              style: GoogleFonts.inter(color: c.inactive),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _startGenerateFlow(mealType, label),
                icon: const Icon(Icons.auto_awesome_rounded, size: 15),
                label: Text(
                  'Generate',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: c.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FoodLogScreen(mealType: mealType),
                    ),
                  );
                  _loadTodayLogs();
                },
                icon: const Icon(Icons.search_rounded, size: 15),
                label: Text(
                  'Log Food',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.orange,
                  side: BorderSide(color: AppColors.orange),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilledCard(
    String mealType,
    String label,
    List<FoodItem> loggedFoods,
    Meal? pendingMeal,
    bool hasManual,
  ) {
    // Recipe sees the whole meal: logged items + any generated additions.
    final Meal mealForRecipe;
    if (pendingMeal != null && hasManual) {
      mealForRecipe = Meal(
        mealType: mealType,
        items: [
          ..._mealFromLoggedFoods(mealType, loggedFoods).items,
          ...pendingMeal.items,
        ],
      );
    } else {
      mealForRecipe =
          pendingMeal ?? _mealFromLoggedFoods(mealType, loggedFoods);
    }

    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...loggedFoods.map(
          (food) => Dismissible(
            key: ValueKey(food.id),
            direction: DismissDirection.endToStart,
            background: _deleteBg(),
            onDismissed: (_) async {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) return;
              await FirestoreService().deleteFoodLog(uid, food.id);
              await _loadTodayLogs();
              if (mounted) {
                context.read<ProfileProvider>().recomputeGoal(uid).ignore();
              }
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      food.name,
                      style: GoogleFonts.inter(
                        color: c.onBackground,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    food.servingSizeUnit == 'g'
                        ? '${(food.servingSize * food.quantity).round()}g'
                        : '${food.quantity.toStringAsFixed(1)}× ${food.servingSize.round()}${food.servingSizeUnit}',
                    style: GoogleFonts.inter(color: c.muted, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${food.totalCalories.round()} kcal',
                    style: GoogleFonts.inter(color: c.subtle, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (pendingMeal != null) ...[
          // Generated additions (green) — shown alongside any logged items
          // (orange) above when completing a partially-logged meal.
          ...pendingMeal.items.map(
            (item) => Dismissible(
              key: ValueKey(item.ingredient.id),
              direction: DismissDirection.endToStart,
              background: _deleteBg(),
              onDismissed: (_) {
                final remaining = pendingMeal.items
                    .where((i) => i != item)
                    .toList();
                _setPending(
                  mealType,
                  remaining.isEmpty
                      ? null
                      : Meal(mealType: mealType, items: remaining),
                );
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.ingredient.name,
                        style: GoogleFonts.inter(
                          color: c.onBackground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '${item.portionGrams.round()}g',
                      style: GoogleFonts.inter(color: c.muted, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${item.calories.round()} kcal',
                      style: GoogleFonts.inter(color: c.subtle, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: GestureDetector(
              onTap: () async {
                // Full USDA search, same as Log Food — the picked food is
                // logged to this meal and shows alongside the generated items.
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FoodLogScreen(mealType: mealType),
                  ),
                );
                _loadTodayLogs();
              },
              child: Row(
                children: [
                  Icon(
                    Icons.add_circle_outline_rounded,
                    color: AppColors.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Add ingredient',
                    style: GoogleFonts.inter(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        _macroSummaryRow(mealType, loggedFoods, pendingMeal, hasManual),
        const SizedBox(height: 12),
        Divider(color: c.border, height: 1),
        const SizedBox(height: 12),
        if (hasManual && pendingMeal != null)
          // Completed meal: logged items kept, generated additions pending.
          // "Log Additions" persists ONLY the new items (logged ones are
          // already saved), so there's no double-save.
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RecipeScreen(meal: mealForRecipe, mealLabel: label),
                    ),
                  ),
                  icon: const Icon(Icons.menu_book_rounded, size: 15),
                  label: Text(
                    'Recipe',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _logPendingMeal(mealType),
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 15,
                  ),
                  label: Text(
                    'Log Additions',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: c.onBackground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          )
        else if (hasManual)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RecipeScreen(meal: mealForRecipe, mealLabel: label),
                    ),
                  ),
                  icon: const Icon(Icons.menu_book_rounded, size: 15),
                  label: Text(
                    'Recipe',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FoodLogScreen(mealType: mealType),
                      ),
                    );
                    _loadTodayLogs();
                  },
                  icon: const Icon(Icons.add_rounded, size: 15),
                  label: Text(
                    'Add food',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.orange,
                    side: BorderSide(color: AppColors.orange),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RecipeScreen(meal: mealForRecipe, mealLabel: label),
                    ),
                  ),
                  icon: const Icon(Icons.menu_book_rounded, size: 15),
                  label: Text(
                    'Recipe',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _logPendingMeal(mealType),
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 15,
                  ),
                  label: Text(
                    'Log Food',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: c.onBackground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _deleteBg() => Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 16),
    decoration: BoxDecoration(
      color: Colors.red.shade800,
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Icon(
      Icons.delete_outline_rounded,
      color: Colors.white,
      size: 18,
    ),
  );

  Widget _macroSummaryRow(
    String mealType,
    List<FoodItem> loggedFoods,
    Meal? pendingMeal,
    bool hasManual,
  ) {
    double p = loggedFoods.fold(0.0, (s, f) => s + f.totalProtein);
    double c = loggedFoods.fold(0.0, (s, f) => s + f.totalCarbs);
    double fat = loggedFoods.fold(0.0, (s, f) => s + f.totalFat);
    double fib = loggedFoods.fold(0.0, (s, f) => s + f.totalFiber);
    if (pendingMeal != null) {
      p += pendingMeal.totalProtein;
      c += pendingMeal.totalCarbs;
      fat += pendingMeal.totalFat;
      fib += pendingMeal.totalFiber;
    }
    final expanded = _expandedMacros.contains(mealType);
    final clr = context.colors;
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() {
            expanded
                ? _expandedMacros.remove(mealType)
                : _expandedMacros.add(mealType);
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                _miniMacro('P', '${p.round()}g', AppColors.primary),
                _miniMacro('C', '${c.round()}g', AppColors.purple),
                _miniMacro('F', '${fat.round()}g', AppColors.orange),
                _miniMacro('Fiber', '${fib.round()}g', AppColors.cyan),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: clr.muted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (expanded) _macroMicroDetail(loggedFoods, pendingMeal),
      ],
    );
  }

  /// Full macro + micronutrient breakdown shown when the summary row is tapped.
  /// Aggregates logged foods (FoodItem) and generated additions (Meal) so the
  /// numbers match the combined card. Micros come from the USDA-seeded fields
  /// now carried on MealIngredient.
  Widget _macroMicroDetail(List<FoodItem> loggedFoods, Meal? pendingMeal) {
    final clr = context.colors;
    double sum(
      double Function(FoodItem) fromFood,
      double Function(Meal) fromMeal,
    ) {
      var v = loggedFoods.fold(0.0, (s, f) => s + fromFood(f));
      if (pendingMeal != null) v += fromMeal(pendingMeal);
      return v;
    }

    final rows = <Widget>[
      _nutrientDetailRow(
        'Calories',
        sum((f) => f.totalCalories, (m) => m.totalCalories),
        'kcal',
      ),
      _nutrientDetailRow(
        'Sugar',
        sum((f) => f.totalSugar, (m) => m.totalSugar),
        'g',
      ),
      _nutrientDetailRow(
        'Sodium',
        sum((f) => f.totalSodium, (m) => m.totalSodium),
        'mg',
      ),
      _nutrientDetailRow(
        'Vitamin A',
        sum((f) => f.totalVitaminA, (m) => m.totalVitaminA),
        'mcg',
      ),
      _nutrientDetailRow(
        'Vitamin C',
        sum((f) => f.totalVitaminC, (m) => m.totalVitaminC),
        'mg',
      ),
      _nutrientDetailRow(
        'Vitamin D',
        sum((f) => f.totalVitaminD, (m) => m.totalVitaminD),
        'mcg',
      ),
      _nutrientDetailRow(
        'Vitamin E',
        sum((f) => f.totalVitaminE, (m) => m.totalVitaminE),
        'mg',
      ),
      _nutrientDetailRow(
        'Vitamin K',
        sum((f) => f.totalVitaminK, (m) => m.totalVitaminK),
        'mcg',
      ),
      _nutrientDetailRow(
        'Vitamin B6',
        sum((f) => f.totalVitaminB6, (m) => m.totalVitaminB6),
        'mg',
      ),
      _nutrientDetailRow(
        'Vitamin B12',
        sum((f) => f.totalVitaminB12, (m) => m.totalVitaminB12),
        'mcg',
      ),
      _nutrientDetailRow(
        'Folate',
        sum((f) => f.totalFolate, (m) => m.totalFolate),
        'mcg',
      ),
      _nutrientDetailRow(
        'Iron',
        sum((f) => f.totalIron, (m) => m.totalIron),
        'mg',
      ),
      _nutrientDetailRow(
        'Calcium',
        sum((f) => f.totalCalcium, (m) => m.totalCalcium),
        'mg',
      ),
      _nutrientDetailRow(
        'Magnesium',
        sum((f) => f.totalMagnesium, (m) => m.totalMagnesium),
        'mg',
      ),
      _nutrientDetailRow(
        'Potassium',
        sum((f) => f.totalPotassium, (m) => m.totalPotassium),
        'mg',
      ),
      _nutrientDetailRow(
        'Zinc',
        sum((f) => f.totalZinc, (m) => m.totalZinc),
        'mg',
      ),
      _nutrientDetailRow(
        'Phosphorus',
        sum((f) => f.totalPhosphorus, (m) => m.totalPhosphorus),
        'mg',
      ),
    ];

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: clr.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: clr.border),
      ),
      child: Column(children: rows),
    );
  }

  Widget _nutrientDetailRow(String label, double value, String unit) {
    final clr = context.colors;
    final text = value >= 100
        ? value.round().toString()
        : value.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(color: clr.muted, fontSize: 12.5),
          ),
          Text(
            '$text $unit',
            style: GoogleFonts.inter(
              color: clr.onBackground,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, String label) => PopupMenuItem(
    value: value,
    child: Text(
      label,
      style: GoogleFonts.inter(
        color: _cuisine == value
            ? AppColors.primary
            : context.colors.onBackground,
        fontWeight: _cuisine == value ? FontWeight.w700 : FontWeight.normal,
      ),
    ),
  );

  Widget _miniMacro(String label, String value, Color color) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: GoogleFonts.inter(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(
            color: context.colors.disabled,
            fontSize: 10,
          ),
        ),
      ],
    ),
  );

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ─── SHARED HELPERS ───────────────────────────────────────────────────────────
Widget _buildLoading(String message, {BuildContext? ctx}) {
  final c = ctx?.colors;
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 16),
        Text(
          message,
          style: GoogleFonts.inter(
            color: c?.muted ?? const Color(0xFF888888),
            height: 1.6,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

Widget _buildError(String error, VoidCallback onRetry, {BuildContext? ctx}) {
  final c = ctx?.colors;
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          Text(
            error,
            style: GoogleFonts.inter(color: c?.onBackground ?? Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: c?.onPrimary ?? Colors.black,
            ),
            child: Text(
              'Retry',
              style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _chip(String label, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  decoration: BoxDecoration(
    color: color.withOpacity(0.15),
    borderRadius: BorderRadius.circular(20),
  ),
  child: Text(
    label,
    style: GoogleFonts.inter(
      color: color,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
  ),
);
