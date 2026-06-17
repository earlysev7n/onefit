import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/meal_ingredient.dart';
import '../models/user_profile.dart';
import '../models/exercise.dart';
import '../algorithms/greedy_algorithm.dart';
import '../algorithms/genetic_algorithm.dart';
import '../services/firestore_service.dart';
import '../services/exercise_db_service.dart';
import '../models/workout_log.dart';
import '../models/exercise_stat.dart';
import '../algorithms/adaptation_engine.dart';
import 'recipe_screen.dart';
import 'food_log_screen.dart';
import 'package:provider/provider.dart';
import '../providers/plan_provider.dart';
import '../providers/profile_provider.dart';
import '../models/food_item.dart';
import '../app_clock.dart';

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
    final args = ModalRoute.of(context)?.settings.arguments;
    final String? focusMealType = (args is Map)
        ? args['mealType'] as String?
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
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
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: const Color(0xFF00C97B),
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.black,
                unselectedLabelColor: const Color(0xFF888888),
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

  // ── Elapsed timer ──────────────────────────────────────────────────────────
  DateTime? _workoutStartedAt;
  Timer? _workoutTimer;
  int _elapsedSeconds = 0;

  // ── Completion tracking ────────────────────────────────────────────────────
  final Set<int> _completedExercises = {};
  final GlobalKey _activeKey = GlobalKey();

  // ── Load tracking (progressive overload) ────────────────────────────────────
  // Top-set weight (kg) / reps the user entered this session, keyed by exercise
  // index. Folded into the workout log + exercise_stats on completion.
  final Map<int, double> _topSetKg = {};
  final Map<int, int> _topSetReps = {};
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
    } else {
      _generate();
    }
    _subscribeToTodayLog();
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _workoutTimer?.cancel();
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
        planProvider.setWorkoutPlan(rehydrated);

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
      final hasHistory = hadLastWeekPlan || lastWeekWorkouts > 0;

      // Use real planned days from profile for the completion denominator
      final plannedDays = profile.workoutDaysPerWeek;
      final adaptation = hasHistory
          ? AdaptationEngine().compute(
              lastWeekCalorieAdherence:
                  (lastWeekNutrition['daysLogged'] as int) > 0
                  ? ((lastWeekNutrition['avgCalories'] as double) /
                        profile.calorieGoal *
                        100)
                  : 100.0,
              lastWeekWorkoutCompletion: plannedDays > 0
                  ? lastWeekWorkouts / plannedDays
                  : 1.0,
              currentExperienceLevel: profile.experienceLevel,
              avgHoursSlept: profile.avgHoursSlept,
              lastWeekAvgRating: lastWeekAvgRating,
            )
          : const AdaptationResult(
              calorieBiasKcal: 0,
              difficultyBias: 'same',
              notes: '',
            );

      final plan = GreedyAlgorithm().generatePlan(
        allExercises: exercises,
        profile: profile,
        difficultyBias: adaptation.difficultyBias,
      );

      // Persist and store in provider
      planProvider.setWorkoutPlan(plan);
      await planProvider.persistWorkoutPlan(uid, weekId);

      // Feed the weekly calorie bias back into the profile so the calorie goal
      // adapts week-over-week (clamped to ±500 by the provider). Applied only
      // after the plan is durably persisted — the persisted-plan branch above
      // returns early on future loads, so this runs at most once per weekId.
      if (adaptation.calorieBiasKcal != 0 && mounted) {
        await context.read<ProfileProvider>().applyCalorieAdjustment(
          adaptation.calorieBiasKcal,
        );
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

  /// Stores whatever weight/reps are currently typed for the active exercise.
  /// Called on every "Done Set" so the latest entry becomes the logged top set.
  void _captureActiveInput() {
    if (_activeExerciseIndex < 0) return;
    final w = double.tryParse(_weightController.text.trim());
    if (w != null && w > 0) _topSetKg[_activeExerciseIndex] = _toKg(w);
    final r = int.tryParse(_repsController.text.trim());
    if (r != null && r > 0) _topSetReps[_activeExerciseIndex] = r;
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
        backgroundColor: const Color(0xFF00C97B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Post-workout perceived-difficulty rating (1 too easy … 5 too hard).
  Future<int?> _askWorkoutRating() {
    const labels = ['Too easy', 'Easy', 'Just right', 'Hard', 'Too hard'];
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How did that feel?',
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Tunes next week's difficulty.",
              style: GoogleFonts.inter(
                color: const Color(0xFF888888),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(
              5,
              (i) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(
                  '${i + 1}',
                  style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF00C97B),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                title: Text(
                  labels[i],
                  style: GoogleFonts.inter(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, i + 1),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: Text(
                  'Skip',
                  style: GoogleFonts.inter(color: const Color(0xFF888888)),
                ),
              ),
            ),
          ],
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
        color: pinned ? const Color(0xFF00C97B) : const Color(0xFF666666),
        size: 20,
      ),
    );
  }

  /// Inline working-weight + reps input shown on the active exercise card,
  /// pre-hinted with the last logged top set as the progressive-overload target.
  Widget _buildWeightInput(WorkoutExercise we) {
    final stat = _exerciseStats[we.exercise.id];
    final hint = (stat != null && stat.lastWeightKg > 0)
        ? 'Last: ${_fmtWeight(stat.lastWeightKg)}'
              '${stat.lastReps != null ? ' × ${stat.lastReps}' : ''}'
              '   ·   PR ${_fmtWeight(stat.bestWeightKg)}'
        : 'Log your working weight to track progress';
    InputDecoration deco(String h) => InputDecoration(
      hintText: h,
      hintStyle: GoogleFonts.inter(
        color: const Color(0xFF666666),
        fontSize: 13,
      ),
      filled: true,
      fillColor: const Color(0xFF222222),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hint,
          style: GoogleFonts.inter(
            color: const Color(0xFF888888),
            fontSize: 12,
          ),
        ),
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
                  color: Colors.white,
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
                  color: Colors.white,
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

  /// Small "Last / PR" caption under the stat boxes on the normal card.
  Widget _lastPrLine(Exercise ex) {
    final stat = _exerciseStats[ex.id];
    if (stat == null || stat.lastWeightKg <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, color: Color(0xFF888888), size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Last: ${_fmtWeight(stat.lastWeightKg)}'
              '${stat.lastReps != null ? ' × ${stat.lastReps}' : ''}'
              '   ·   PR ${_fmtWeight(stat.bestWeightKg)}',
              style: GoogleFonts.inter(
                color: const Color(0xFF888888),
                fontSize: 12,
              ),
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
      exercises: [
        for (int i = 0; i < day.exercises.length; i++)
          WorkoutLogExercise(
            name: day.exercises[i].exercise.name,
            sets: day.exercises[i].sets,
            reps: day.exercises[i].reps,
            restSeconds: day.exercises[i].restSeconds,
            primaryMuscles: day.exercises[i].exercise.primaryMuscles,
            weightKg: _topSetKg[i],
            repsDone: _topSetReps[i],
          ),
      ],
    );
    final fs = FirestoreService();
    await fs.saveWorkoutLog(log);

    // Persist per-exercise top sets and detect PRs against the cached bests.
    final prs = <String>[];
    for (int i = 0; i < day.exercises.length; i++) {
      final kg = _topSetKg[i];
      if (kg == null) continue;
      final ex = day.exercises[i].exercise;
      final prevBest = _exerciseStats[ex.id]?.bestWeightKg ?? 0;
      if (kg > prevBest) prs.add(ex.name);
      await fs.saveExerciseStat(
        userId: uid,
        exerciseId: ex.id,
        name: ex.name,
        weightKg: kg,
        reps: _topSetReps[i],
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
          backgroundColor: const Color(0xFF00C97B),
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
    _workoutTimer?.cancel();
    _pendingRestCallback = null;
    _activeExerciseIndex = -1;
    _activeSetNumber = 0;
    _inRest = false;
    _restRemaining = 0;
    _restTotal = 0;
    _waitingForReady = false;
    _workoutStartedAt = null;
    _elapsedSeconds = 0;
    _completedExercises.clear();
    _topSetKg.clear();
    _topSetReps.clear();
    _weightController.clear();
    _repsController.clear();
  }

  void _startWorkout() {
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
    setState(() {
      _activeExerciseIndex = 0;
      _activeSetNumber = 1;
      _workoutStartedAt = DateTime.now();
      _elapsedSeconds = 0;
      _topSetKg.clear();
      _topSetReps.clear();
      _weightController.clear();
      _repsController.clear();
    });
    _workoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
    _scrollToActive();
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
    // Clear the inputs so the next exercise starts blank with its own target.
    _weightController.clear();
    _repsController.clear();
    setState(() {
      _waitingForReady = false;
      _activeExerciseIndex++;
      _activeSetNumber = 1;
    });
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

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return _buildLoading('Generating workout plan...');
    if (_error != null) return _buildError(_error!, _generate);
    return _buildPlan();
  }

  Widget _buildPlan() {
    final day = _plan.isNotEmpty ? _plan[_selectedDay] : null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (_profile != null) ...[
                _chip(_profile!.fitnessGoal, const Color(0xFF00C97B)),
                const SizedBox(width: 6),
                _chip(_profile!.experienceLevel, const Color(0xFF6C63FF)),
                const SizedBox(width: 6),
                _chip(_profile!.workoutLocation, const Color(0xFFFF6B35)),
              ],
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFF00C97B),
                ),
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
                            ? (isRest
                                  ? const Color(0xFF444444)
                                  : const Color(0xFF00C97B))
                            : const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(14),
                        border: isSelected
                            ? null
                            : Border.all(color: const Color(0xFF2E2E2E)),
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
                                  ? (isRest ? Colors.white : Colors.black)
                                  : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Icon(
                            isRest
                                ? Icons.bedtime_rounded
                                : Icons.fitness_center_rounded,
                            size: 14,
                            color: isSelected
                                ? (isRest ? Colors.white70 : Colors.black54)
                                : const Color(0xFF888888),
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
                            color: const Color(0xFF00C97B),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 1.5),
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
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Session is shorter',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'You removed $removed exercise${removed == 1 ? '' : 's'}. '
            'The algorithm can fill the gap with matching exercises, or you can '
            'leave the session shorter — skipped volume will be added to your '
            'next workout day${removed > 1 ? 's' : ''}.',
            style: GoogleFonts.inter(
              color: const Color(0xFF888888),
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
                  color: const Color(0xFF00C97B),
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
                  color: const Color(0xFF888888),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
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

  /// Manual-picker eligibility: hard constraints only (gender / location /
  /// equipment / Home bench rule), WITHOUT the strict experience gate. The user
  /// may deliberately add an above-tier exercise from the picker (with a
  /// warning) — the automatic generation / gap-fill / volume-debt paths keep the
  /// full [_usableByUser] gate so the algorithm never auto-injects above-tier
  /// moves.
  bool _pickableByUser(Exercise e) {
    final p = _profile;
    if (p == null) return true;
    return GreedyAlgorithm.isEligibleForUser(e, p);
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
    final color = aboveTier ? const Color(0xFFFFA726) : const Color(0xFF00C97B);
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
  Future<bool?> _confirmAboveTier(Exercise e) {
    final level = _profile?.experienceLevel ?? 'your';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Above your level',
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '"${e.name}" is rated ${e.difficulty}, above your '
          '$level level. Make sure you can perform it safely — add it anyway?',
          style: GoogleFonts.inter(color: const Color(0xFFBBBBBB), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: const Color(0xFF888888)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Add anyway',
              style: GoogleFonts.inter(
                color: const Color(0xFF00C97B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Fills the gap left by removed exercises by pulling exercises from
  /// [_allExercises] that target the day's muscle groups.
  void _fillExerciseGap(WorkoutDay day, int count) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final targets = _focusToMuscles(day.focus);
    final existingIds = day.exercises.map((e) => e.exercise.id).toSet();

    final candidates = _allExercises.where((e) {
      if (existingIds.contains(e.id)) return false;
      if (!_usableByUser(e)) return false;
      return targets.isEmpty || e.primaryMuscles.any(targets.contains);
    }).toList();
    candidates.shuffle();

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
      final candidates = _allExercises.where((e) {
        if (existingIds.contains(e.id)) return false;
        if (!_usableByUser(e)) return false;
        return targets.isEmpty || e.primaryMuscles.any(targets.contains);
      }).toList();
      candidates.shuffle();

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
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF333333)),
              ),
              child: Text(
                'Edit params',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFF00C97B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
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
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF00C97B).withValues(alpha: 0.4),
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_rounded, color: Color(0xFF00C97B), size: 18),
              const SizedBox(width: 6),
              Text(
                'Add exercise',
                style: GoogleFonts.inter(
                  color: const Color(0xFF00C97B),
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

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
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
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 20),
              // Sets
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sets',
                    style: GoogleFonts.inter(color: const Color(0xFF888888)),
                  ),
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
                            color: Colors.white,
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
                    style: GoogleFonts.inter(color: const Color(0xFF888888)),
                  ),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: repsCtrl,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF222222),
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
                  Text(
                    'Rest (sec)',
                    style: GoogleFonts.inter(color: const Color(0xFF888888)),
                  ),
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
                            color: Colors.white,
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
                    backgroundColor: const Color(0xFF00C97B),
                    foregroundColor: Colors.black,
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
    );
  }

  Widget _paramBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    ),
  );

  void _showExercisePicker(WorkoutDay day) {
    final targetMuscles = day.focus == 'Rest Day'
        ? <String>[]
        : _focusToMuscles(day.focus);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final planProvider = context.read<PlanProvider>();
    // Use cached exercises from the last generated plan's full list;
    // fallback to exercises already in the plan if cache is unavailable.
    // _pickableByUser applies hard constraints only (no experience gate) so the
    // user may deliberately add an above-tier move, with a warning on tap.
    final allEx = _allExercises;
    final relevant = allEx.where((e) {
      if (!_pickableByUser(e)) return false;
      if (targetMuscles.isEmpty) return true;
      return e.primaryMuscles.any((m) => targetMuscles.contains(m));
    }).toList()..sort((a, b) => a.name.compareTo(b.name));

    final searchController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
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
                    return e.primaryMuscles
                        .any((m) => m.toLowerCase().contains(query));
                  }).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Text(
                    'Add exercise — ${day.focus}',
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
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
                    style: GoogleFonts.inter(color: Colors.white),
                    cursorColor: const Color(0xFF00C97B),
                    decoration: InputDecoration(
                      hintText: 'Search exercises',
                      hintStyle: GoogleFonts.inter(
                        color: const Color(0xFF888888),
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Color(0xFF888888),
                      ),
                      suffixIcon: searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Color(0xFF888888),
                              ),
                              onPressed: () => setSheetState(
                                () => searchController.clear(),
                              ),
                            ),
                      filled: true,
                      fillColor: const Color(0xFF0D0D0D),
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
                        borderSide: const BorderSide(
                          color: Color(0xFF00C97B),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No matching exercises found.',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF888888),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: sc,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final ex = filtered[i];
                            final aboveTier = _isAboveUserTier(ex);
                            return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          title: Text(
                            ex.name,
                            style: GoogleFonts.inter(
                              color: Colors.white,
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
                                    color: const Color(0xFF888888),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              if (ex.difficulty.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                _difficultyBadge(ex.difficulty, aboveTier),
                              ],
                            ],
                          ),
                          trailing: const Icon(
                            Icons.add_circle_outline,
                            color: Color(0xFF00C97B),
                          ),
                          onTap: () async {
                            Navigator.pop(ctx);
                            if (aboveTier) {
                              final ok = await _confirmAboveTier(ex);
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
                              () => _plan = planProvider.workoutPlan,
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
    ).whenComplete(searchController.dispose);
  }

  /// Muscle targets for a focus string (used by exercise picker, gap-fill and
  /// volume-debt). Delegates to [GreedyAlgorithm.musclesForFocus] so it resolves
  /// muscles in the same ExerciseDB `targetMuscles` vocabulary the generator
  /// uses — otherwise the picker filters for 'chest' while exercises are tagged
  /// 'pectorals' and nothing matches.
  List<String> _focusToMuscles(String focus) =>
      GreedyAlgorithm.musclesForFocus(focus);

  Widget _buildRestDay() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.bedtime_rounded, size: 64, color: Color(0xFF444444)),
        const SizedBox(height: 16),
        Text(
          'Rest Day',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Recovery is part of the plan.',
          style: GoogleFonts.inter(color: const Color(0xFF888888)),
        ),
      ],
    ),
  );

  Widget _buildWorkoutDay(WorkoutDay day) {
    final isToday = _selectedDay == appNow().weekday - 1;
    final isCompleted = _todayLog != null && isToday;
    final workoutStarted = _activeExerciseIndex >= 0;

    // Build per-exercise cards
    final exerciseCards = <Widget>[];
    for (int i = 0; i < day.exercises.length; i++) {
      final we = day.exercises[i];
      final bool isActive = (i == _activeExerciseIndex) && !_waitingForReady;
      final bool isDone = _completedExercises.contains(i);
      final bool isReadySlot =
          _waitingForReady && (i == _activeExerciseIndex + 1);
      final bool needsKey = isActive || isReadySlot;

      Widget card = isReadySlot
          ? _buildReadyCard(we)
          : _buildExerciseCard(
              we,
              i + 1,
              isToday: isToday && !isCompleted,
              isActive: isActive,
              isDone: isDone,
              workoutStarted: workoutStarted,
            );

      // Wrap with edit controls when in edit mode
      if (_editMode && !workoutStarted) {
        card = _wrapWithEditControls(card, day, i, we);
      }

      exerciseCards.add(
        Container(key: needsKey ? _activeKey : ValueKey('ex_$i'), child: card),
      );
    }

    // "Add exercise" button at the bottom when editing
    if (_editMode && !workoutStarted) {
      exerciseCards.add(_buildAddExerciseButton(day));
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
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      day.focus,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF00C97B),
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
                    color: const Color(0xFF00C97B).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF00C97B).withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF00C97B),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Completed · ${_todayLog!.durationMinutes} min',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF00C97B),
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
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${day.exercises.length} exercises',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF888888),
                      fontSize: 13,
                    ),
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
                        ? const Color(0xFF00C97B).withValues(alpha: 0.15)
                        : const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _editMode
                          ? const Color(0xFF00C97B)
                          : const Color(0xFF333333),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _editMode ? Icons.check_rounded : Icons.edit_rounded,
                        size: 14,
                        color: _editMode
                            ? const Color(0xFF00C97B)
                            : const Color(0xFF888888),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _editMode ? 'Done editing' : 'Edit session',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _editMode
                              ? const Color(0xFF00C97B)
                              : const Color(0xFF888888),
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
                    color: const Color(0xFF00C97B),
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
                      backgroundColor: const Color(0xFF2E2E2E),
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFF00C97B),
                      ),
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
                  backgroundColor: const Color(0xFF00C97B),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Exercise cards
          ...exerciseCards,
        ],
      ),
    );
  }

  // "Up Next / I'm Ready!" card shown between exercises
  Widget _buildReadyCard(WorkoutExercise we) {
    final ex = we.exercise;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00C97B).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Up Next',
            style: GoogleFonts.inter(
              color: const Color(0xFF00C97B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ex.name,
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '${ex.primaryMuscles.join(', ')} · ${we.sets} sets · ${we.reps} reps · ${we.restSeconds}s rest',
            style: GoogleFonts.inter(
              color: const Color(0xFF888888),
              fontSize: 13,
            ),
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
                      ? Image.network(
                          ex.gifUrl!,
                          key: ValueKey('gif_ready_${ex.id}'),
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          headers: const {'User-Agent': 'OneFit/1.0'},
                          loadingBuilder: (_, child, p) => p == null
                              ? child
                              : _gifPlaceholder(loading: true, height: 140),
                          errorBuilder: (_, __, ___) =>
                              _gifPlaceholder(height: 140),
                        )
                      : _gifPlaceholder(height: 140),
                ),
                if (ex.gifUrl?.isNotEmpty == true)
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
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
                backgroundColor: const Color(0xFF00C97B),
                foregroundColor: Colors.black,
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

  Widget _buildExerciseCard(
    WorkoutExercise we,
    int number, {
    required bool isToday,
    required bool isActive,
    required bool isDone,
    required bool workoutStarted,
  }) {
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
        color: isDone
            ? const Color(0xFF00C97B)
            : const Color(0xFF00C97B).withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: isDone
            ? const Icon(Icons.check_rounded, color: Colors.black, size: 16)
            : Text(
                '$number',
                style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF00C97B),
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
                  ? Image.network(
                      gifUrl,
                      key: ValueKey('gif_active_${ex.id}'),
                      height: gifHeight,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      headers: const {'User-Agent': 'OneFit/1.0'},
                      loadingBuilder: (_, child, p) => p == null
                          ? child
                          : _gifPlaceholder(loading: true, height: gifHeight),
                      errorBuilder: (_, __, ___) =>
                          _gifPlaceholder(height: gifHeight),
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
                      ? Image.network(
                          gifUrl,
                          key: ValueKey('gif_idle_${ex.id}'),
                          height: gifHeight,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          headers: const {'User-Agent': 'OneFit/1.0'},
                          loadingBuilder: (_, child, p) => p == null
                              ? child
                              : _gifPlaceholder(
                                  loading: true,
                                  height: gifHeight,
                                ),
                          errorBuilder: (_, __, ___) =>
                              _gifPlaceholder(height: gifHeight),
                        )
                      : _gifPlaceholder(height: gifHeight),
                ),
                if (gifUrl != null)
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
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
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? const Color(0xFF00C97B).withOpacity(0.6)
                : const Color(0xFF2E2E2E),
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
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        ex.primaryMuscles.join(', '),
                        style: GoogleFonts.inter(
                          color: const Color(0xFF888888),
                          fontSize: 12,
                        ),
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
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _restTotal > 0 ? _restRemaining / _restTotal : 0,
                    backgroundColor: const Color(0xFF2E2E2E),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF00C97B)),
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
                        color: const Color(0xFF00C97B),
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
                              ? const Color(0xFF00C97B)
                              : const Color(0xFF2E2E2E),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Set $_activeSetNumber of ${we.sets}',
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildWeightInput(we),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _doneSet(we),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(
                      'Done Set',
                      style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C97B),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ] else ...[
              // ── Normal / done card ───────────────────────────────────────
              const SizedBox(height: 12),
              Row(
                children: [
                  _statBox('Sets', '${we.sets}', const Color(0xFF00C97B)),
                  const SizedBox(width: 8),
                  _statBox('Reps', we.reps, const Color(0xFF6C63FF)),
                  const SizedBox(width: 8),
                  _statBox(
                    'Rest',
                    '${we.restSeconds}s',
                    const Color(0xFFFF6B35),
                  ),
                ],
              ),
              _lastPrLine(ex),
              const SizedBox(height: 12),
              Text(
                ex.instructions,
                style: GoogleFonts.inter(
                  color: const Color(0xFF888888),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              gifSection,
            ],
          ],
        ),
      ),
    );
  }

  Widget _gifPlaceholder({bool loading = false, double height = 160}) =>
      Container(
        width: double.infinity,
        height: height,
        color: const Color(0xFF222222),
        child: loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF00C97B),
                  strokeWidth: 2,
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.play_circle_outline_rounded,
                    color: Color(0xFF444444),
                    size: 48,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Exercise Demo',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF444444),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      );

  void _showGifDialog(BuildContext context, String gifUrl, String name) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  gifUrl,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  headers: const {'User-Agent': 'OneFit/1.0'},
                  loadingBuilder: (_, child, p) => p == null
                      ? child
                      : _gifPlaceholder(loading: true, height: 200),
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image,
                    color: Color(0xFF444444),
                    size: 60,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Close',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF00C97B),
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
        ? const Color(0xFF00C97B)
        : d == 'intermediate'
        ? const Color(0xFFFF6B35)
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

  // USDA ingredient pool the Genetic Algorithm draws on (loaded once).
  List<MealIngredient> _allIngredients = [];

  UserProfile? _profile;
  bool _isInitializing = true;
  String _cuisine = 'any';
  int _selectedDay = 0;

  final List<String> _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

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
    _selectedDay = appNow().weekday - 1;
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

  // ── Edamam helpers ────────────────────────────────────────────────────────

  int _mealTargetCals(String mealType) {
    final goal = _profile?.calorieGoal ?? 2000;
    return switch (mealType) {
      'breakfast' => (goal * 0.25).round(),
      'lunch' => (goal * 0.35).round(),
      'dinner' => (goal * 0.30).round(),
      _ => (goal * 0.10).round(),
    };
  }

  // ── Generation (Genetic Algorithm over USDA ingredients) ───────────────────

  /// Runs the Genetic Algorithm against the loaded ingredient pool, filtered by
  /// the selected cuisine and the user's dietary restrictions. Returns one
  /// optimized day; a random day is chosen so regenerating yields variety.
  DayMealPlan _runGeneticPlan() {
    final plan = GeneticAlgorithm().generatePlan(
      allIngredients: _allIngredients,
      profile: _profile!,
      cuisine: _cuisine, // 'any' | 'filipino' | 'western' | 'asian'
    );
    return plan[Random().nextInt(plan.length)];
  }

  Meal _slotOf(DayMealPlan day, String mealType) => switch (mealType) {
    'breakfast' => day.breakfast,
    'lunch' => day.lunch,
    'dinner' => day.dinner,
    _ => day.snack,
  };

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

  Future<void> _generateMeal(String mealType) async {
    if (_profile == null || !_guardIngredients()) return;
    setState(() => _loadingMeals.add(mealType));
    try {
      final meal = _slotOf(
        _runGeneticPlan(),
        mealType,
      ).scaleToCalories(_mealTargetCals(mealType).toDouble());
      _setPending(mealType, meal);
      context.read<PlanProvider>().setMeal(
        mealType,
        meal,
        saveToFirestore: false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not generate $mealType: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMeals.remove(mealType));
    }
  }

  Future<void> _generateAll() async {
    if (_profile == null || !_guardIngredients()) return;
    final toGenerate = [
      'breakfast',
      'lunch',
      'dinner',
      'snack',
    ].where((m) => (_loggedFoods[m] ?? []).isEmpty).toList();
    if (toGenerate.isEmpty) return;

    setState(() => _loadingMeals.addAll(toGenerate));
    try {
      // One GA run optimizes the whole day's macros jointly; pull each slot.
      final day = _runGeneticPlan();
      for (final mealType in toGenerate) {
        final meal = _slotOf(
          day,
          mealType,
        ).scaleToCalories(_mealTargetCals(mealType).toDouble());
        _setPending(mealType, meal);
        context.read<PlanProvider>().setMeal(
          mealType,
          meal,
          saveToFirestore: false,
        );
      }
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_capitalize(mealType)} logged!'),
            backgroundColor: const Color(0xFF00C97B),
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

  Meal _mealFromLoggedFoods(String mealType, List<FoodItem> foods) {
    final items = foods.map((f) {
      final ing = MealIngredient(
        id: f.id,
        name: f.name,
        calories: f.calories,
        protein: f.protein,
        carbs: f.carbs,
        fat: f.fat,
        fiber: f.fiber,
        sugar: f.sugar,
        sodium: f.sodium,
        cuisine: 'universal',
        dietaryTags: const [],
      );
      return MealItem(
        ingredient: ing,
        portionGrams: f.servingSize * f.quantity,
      );
    }).toList();
    return Meal(mealType: mealType, items: items);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isInitializing) return _buildLoading('Loading...');
    return _buildPlan();
  }

  Widget _buildPlan() {
    final totalCals = _totalCals();
    final targetCal = _profile?.calorieGoal ?? 2000;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (_profile != null) ...[
                _chip(_profile!.fitnessGoal, const Color(0xFF00C97B)),
                const SizedBox(width: 6),
                _chip('$targetCal kcal', const Color(0xFFFF6B35)),
              ],
              const Spacer(),
              PopupMenuButton<String>(
                color: const Color(0xFF1A1A1A),
                icon: const Icon(
                  Icons.restaurant_menu_rounded,
                  color: Color(0xFF00C97B),
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
                icon: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: Color(0xFF00C97B),
                ),
                label: Text(
                  'All',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF00C97B),
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
        SizedBox(
          height: 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _days.length,
            itemBuilder: (context, i) {
              final isSelected = i == _selectedDay;
              return GestureDetector(
                onTap: () => setState(() => _selectedDay = i),
                child: Container(
                  width: 52,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF00C97B)
                        : const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? null
                        : Border.all(color: const Color(0xFF2E2E2E)),
                  ),
                  child: Center(
                    child: Text(
                      _days[i],
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(
                  '${totalCals.round()} / $targetCal kcal',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (totalCals / targetCal).clamp(0.0, 1.1),
                      backgroundColor: const Color(0xFF2E2E2E),
                      valueColor: AlwaysStoppedAnimation(
                        totalCals > targetCal * 1.05
                            ? Colors.redAccent
                            : const Color(0xFF00C97B),
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
            color: const Color(0xFF00C97B),
            backgroundColor: const Color(0xFF1A1A1A),
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

    return Container(
      key: key,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          // Green border for the card the user tapped from Nutrition screen
          color: isFocused ? const Color(0xFF00C97B) : const Color(0xFF2E2E2E),
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
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              if (hasContent) ...[
                Text(
                  '${cardCals.round()} kcal',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF00C97B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _clearAll(mealType),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF555555),
                    size: 18,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF2E2E2E), height: 1),
          const SizedBox(height: 12),
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(
                  color: Color(0xFF00C97B),
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
    return Column(
      children: [
        Row(
          children: [
            const Icon(
              Icons.add_circle_outline_rounded,
              color: Color(0xFF333333),
              size: 32,
            ),
            const SizedBox(width: 12),
            Text(
              'No $label added yet',
              style: GoogleFonts.inter(color: const Color(0xFF555555)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _generateMeal(mealType),
                icon: const Icon(Icons.auto_awesome_rounded, size: 15),
                label: Text(
                  'Generate',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C97B),
                  foregroundColor: Colors.black,
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
                  foregroundColor: const Color(0xFFFF6B35),
                  side: const BorderSide(color: Color(0xFFFF6B35)),
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
    final mealForRecipe =
        pendingMeal ?? _mealFromLoggedFoods(mealType, loggedFoods);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...loggedFoods.map(
          (food) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF6B35),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    food.name,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '${food.quantity.toStringAsFixed(1)}× ${food.servingSize.round()}${food.servingSizeUnit}',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF888888),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${food.totalCalories.round()} kcal',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF444444),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (pendingMeal != null && !hasManual) ...[
          // Genetic-Algorithm meal: ingredient list with gram portions + kcal
          ...pendingMeal.items.map(
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
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${item.calories.round()} kcal',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF444444),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        _macroSummaryRow(loggedFoods, pendingMeal, hasManual),
        const SizedBox(height: 12),
        const Divider(color: Color(0xFF2E2E2E), height: 1),
        const SizedBox(height: 12),
        if (hasManual)
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
                    foregroundColor: const Color(0xFF00C97B),
                    side: const BorderSide(color: Color(0xFF00C97B)),
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
                    'Log Food',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6B35),
                    side: const BorderSide(color: Color(0xFFFF6B35)),
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
                    foregroundColor: const Color(0xFF00C97B),
                    side: const BorderSide(color: Color(0xFF00C97B)),
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
                    backgroundColor: const Color(0xFFFF6B35),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _generateMeal(mealType),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6C63FF),
                  side: const BorderSide(color: Color(0xFF6C63FF)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  minimumSize: Size.zero,
                ),
                child: const Icon(Icons.refresh_rounded, size: 16),
              ),
            ],
          ),
      ],
    );
  }

  Widget _macroSummaryRow(
    List<FoodItem> loggedFoods,
    Meal? pendingMeal,
    bool hasManual,
  ) {
    double p = loggedFoods.fold(0.0, (s, f) => s + f.totalProtein);
    double c = loggedFoods.fold(0.0, (s, f) => s + f.totalCarbs);
    double fat = loggedFoods.fold(0.0, (s, f) => s + f.totalFat);
    double fib = loggedFoods.fold(0.0, (s, f) => s + f.totalFiber);
    if (pendingMeal != null && !hasManual) {
      p += pendingMeal.totalProtein;
      c += pendingMeal.totalCarbs;
      fat += pendingMeal.totalFat;
      fib += pendingMeal.totalFiber;
    }
    return Row(
      children: [
        _miniMacro('P', '${p.round()}g', const Color(0xFF00C97B)),
        _miniMacro('C', '${c.round()}g', const Color(0xFF6C63FF)),
        _miniMacro('F', '${fat.round()}g', const Color(0xFFFF6B35)),
        _miniMacro('Fiber', '${fib.round()}g', const Color(0xFF00B4D8)),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, String label) => PopupMenuItem(
    value: value,
    child: Text(
      label,
      style: GoogleFonts.inter(
        color: _cuisine == value ? const Color(0xFF00C97B) : Colors.white,
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
            color: const Color(0xFF666666),
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
Widget _buildLoading(String message) => Center(
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const CircularProgressIndicator(color: Color(0xFF00C97B)),
      const SizedBox(height: 16),
      Text(
        message,
        style: GoogleFonts.inter(color: const Color(0xFF888888), height: 1.6),
        textAlign: TextAlign.center,
      ),
    ],
  ),
);

Widget _buildError(String error, VoidCallback onRetry) => Center(
  child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
        const SizedBox(height: 16),
        Text(
          error,
          style: GoogleFonts.inter(color: Colors.white),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: onRetry,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00C97B),
            foregroundColor: Colors.black,
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
