import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';
import '../models/food_item.dart';
import '../models/workout_log.dart';
import '../models/exercise_stat.dart';
import '../models/meal_ingredient.dart';
import '../models/weekly_summary.dart';
import '../algorithms/greedy_algorithm.dart' show WorkoutDay;
import '../app_clock.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Issues a Firestore write WITHOUT awaiting the server ack. Firestore applies
  /// the write to the on-device cache immediately and queues it durably, so the
  /// UI must never block on the returned Future — offline it does not resolve
  /// until the device reconnects (that was the "delete/regenerate/add hangs
  /// offline" bug). Rare async failures (e.g. permission errors) are logged, not
  /// thrown. Reads (`.get()`) must still be awaited — offline they read cache.
  void _fireWrite(Future<void> write, String op) {
    unawaited(
      write.catchError((Object e) {
        debugPrint('Firestore write failed ($op): $e');
      }),
    );
  }

  // ========================================
  // USER PROFILE METHODS
  // ========================================

  /// Non-blocking (see [_fireWrite]) so profile edits, weight syncs and the
  /// weekly calorie adaptation persist offline without hanging.
  Future<void> saveUserProfile(UserProfile profile) async {
    _fireWrite(
      _db.collection('users').doc(profile.uid).set(profile.toMap()),
      'saveUserProfile',
    );
  }

  Future<UserProfile?> loadUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) return UserProfile.fromMap(doc.data()!);
    return null;
  }

  Future<bool> profileExists(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.exists;
  }

  Future<UserProfile?> getUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromMap(doc.data()!);
  }

  // ========================================
  // INGREDIENT METHODS
  // ========================================

  /// In-memory cache of the seeded USDA ingredient database. Loaded once per
  /// session — it's static reference data, so no TTL is needed.
  static List<MealIngredient>? _ingredientCache;

  /// Reads the pre-seeded `ingredients` collection (USDA FoodData Central)
  /// that the Genetic Algorithm draws on for meal generation. Returns an empty
  /// list if the collection hasn't been seeded yet (see SeedData).
  Future<List<MealIngredient>> getIngredients() async {
    if (_ingredientCache != null) return _ingredientCache!;
    final snap = await _db.collection('ingredients').get();
    final list = snap.docs
        .map((d) => MealIngredient.fromMap(d.data()))
        .toList();
    if (list.isNotEmpty) _ingredientCache = list;
    return list;
  }

  /// Clears the in-memory ingredient cache so the next [getIngredients] call
  /// re-reads from Firestore. Call after re-seeding so newly added fields
  /// (allergens / category) are picked up without an app restart.
  static void clearIngredientCache() => _ingredientCache = null;

  // ========================================
  // NUTRITION LOGGING METHODS
  // ========================================

  /// Log a food item for a user. Returns the new doc id synchronously (Firestore
  /// ids are client-generated) and fires the write without awaiting the server
  /// ack, so logging never blocks the UI — offline the item is cached + queued
  /// immediately and surfaces through the food-log streams right away.
  Future<String> logFoodItem(FoodItem foodItem) async {
    final docRef = _db
        .collection('users')
        .doc(foodItem.userId)
        .collection('food_logs')
        .doc();
    _fireWrite(docRef.set(foodItem.toMap()), 'logFoodItem');
    return docRef.id;
  }

  /// Get all food logs for a specific date
  Future<List<FoodItem>> getFoodLogsForDate(
    String userId,
    DateTime date,
  ) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final snapshot = await _db
        .collection('users')
        .doc(userId)
        .collection('food_logs')
        .where(
          'loggedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where('loggedAt', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('loggedAt', descending: false)
        .get();

    return snapshot.docs
        .map((doc) => FoodItem.fromMap(doc.data(), doc.id))
        .toList();
  }

  /// Get food logs for a date range (for weekly view)
  Future<List<FoodItem>> getFoodLogsForDateRange(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final snapshot = await _db
        .collection('users')
        .doc(userId)
        .collection('food_logs')
        .where(
          'loggedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        )
        // Exclusive end, matching getWorkoutLogsForDateRange — callers pass
        // the next window's start (e.g. next Monday 00:00, or today to
        // exclude today), so an inclusive bound would double-count a
        // midnight-stamped log into two windows.
        .where('loggedAt', isLessThan: Timestamp.fromDate(endDate))
        .orderBy('loggedAt', descending: false)
        .get();

    return snapshot.docs
        .map((doc) => FoodItem.fromMap(doc.data(), doc.id))
        .toList();
  }

  /// Delete a food log entry. Non-blocking (see [_fireWrite]) so deleting works
  /// offline immediately.
  Future<void> deleteFoodLog(String userId, String foodLogId) async {
    _fireWrite(
      _db
          .collection('users')
          .doc(userId)
          .collection('food_logs')
          .doc(foodLogId)
          .delete(),
      'deleteFoodLog',
    );
  }

  /// Update a food log entry (e.g., change quantity or meal type). Non-blocking.
  Future<void> updateFoodLog(
    String userId,
    String foodLogId,
    Map<String, dynamic> updates,
  ) async {
    _fireWrite(
      _db
          .collection('users')
          .doc(userId)
          .collection('food_logs')
          .doc(foodLogId)
          .update(updates),
      'updateFoodLog',
    );
  }

  /// Get total nutrition for today
  Future<Map<String, double>> getTodayNutrition(String userId) async {
    final today = appNow();
    final foodLogs = await getFoodLogsForDate(userId, today);

    double totalCalories = 0;
    double totalProtein = 0;
    double totalCarbs = 0;
    double totalFat = 0;
    double totalFiber = 0;
    double totalSugar = 0;
    double totalSodium = 0;

    for (var food in foodLogs) {
      totalCalories += food.totalCalories;
      totalProtein += food.totalProtein;
      totalCarbs += food.totalCarbs;
      totalFat += food.totalFat;
      totalFiber += food.totalFiber;
      totalSugar += food.totalSugar;
      totalSodium += food.totalSodium;
    }

    return {
      'calories': totalCalories,
      'protein': totalProtein,
      'carbs': totalCarbs,
      'fat': totalFat,
      'fiber': totalFiber,
      'sugar': totalSugar,
      'sodium': totalSodium,
    };
  }

  /// Get nutrition breakdown by meal type for a specific date
  Future<Map<String, Map<String, double>>> getNutritionByMealType(
    String userId,
    DateTime date,
  ) async {
    final foodLogs = await getFoodLogsForDate(userId, date);

    Map<String, Map<String, double>> mealBreakdown = {
      'breakfast': {'calories': 0, 'protein': 0, 'carbs': 0, 'fat': 0},
      'lunch': {'calories': 0, 'protein': 0, 'carbs': 0, 'fat': 0},
      'dinner': {'calories': 0, 'protein': 0, 'carbs': 0, 'fat': 0},
      'snack': {'calories': 0, 'protein': 0, 'carbs': 0, 'fat': 0},
    };

    for (var food in foodLogs) {
      final mealType = food.mealType.toLowerCase();
      if (mealBreakdown.containsKey(mealType)) {
        mealBreakdown[mealType]!['calories'] =
            (mealBreakdown[mealType]!['calories'] ?? 0) + food.totalCalories;
        mealBreakdown[mealType]!['protein'] =
            (mealBreakdown[mealType]!['protein'] ?? 0) + food.totalProtein;
        mealBreakdown[mealType]!['carbs'] =
            (mealBreakdown[mealType]!['carbs'] ?? 0) + food.totalCarbs;
        mealBreakdown[mealType]!['fat'] =
            (mealBreakdown[mealType]!['fat'] ?? 0) + food.totalFat;
      }
    }

    return mealBreakdown;
  }

  /// Stream food logs for real-time updates (for dashboard)
  Stream<List<FoodItem>> streamTodayFoodLogs(String userId) {
    final today = appNow();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _db
        .collection('users')
        .doc(userId)
        .collection('food_logs')
        .where(
          'loggedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where('loggedAt', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('loggedAt', descending: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => FoodItem.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  /// Stream food logs for a specific date (for nutrition screen)
  Stream<List<FoodItem>> streamFoodLogsForDate(String userId, DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _db
        .collection('users')
        .doc(userId)
        .collection('food_logs')
        .where(
          'loggedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where('loggedAt', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('loggedAt', descending: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => FoodItem.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  /// Get weekly nutrition summary (for adaptive system)
  Future<Map<String, dynamic>> getWeeklyNutritionSummary(
    String userId,
    DateTime weekStart,
  ) async {
    final weekEnd = weekStart.add(const Duration(days: 7));
    final foodLogs = await getFoodLogsForDateRange(userId, weekStart, weekEnd);

    if (foodLogs.isEmpty) {
      return {
        'avgCalories': 0.0,
        'avgProtein': 0.0,
        'avgCarbs': 0.0,
        'avgFat': 0.0,
        'daysLogged': 0,
        'totalLogs': 0,
        'dailyCalories': <double>[],
      };
    }

    // Group by date
    Map<String, List<FoodItem>> dailyLogs = {};
    for (var food in foodLogs) {
      final dateKey =
          '${food.loggedAt.year}-${food.loggedAt.month}-${food.loggedAt.day}';
      dailyLogs[dateKey] = [...(dailyLogs[dateKey] ?? []), food];
    }

    // Calculate daily totals
    List<double> dailyCalories = [];
    List<double> dailyProtein = [];
    List<double> dailyCarbs = [];
    List<double> dailyFat = [];

    for (var dayLogs in dailyLogs.values) {
      double dayCalories = 0;
      double dayProtein = 0;
      double dayCarbs = 0;
      double dayFat = 0;

      for (var food in dayLogs) {
        dayCalories += food.totalCalories;
        dayProtein += food.totalProtein;
        dayCarbs += food.totalCarbs;
        dayFat += food.totalFat;
      }

      dailyCalories.add(dayCalories);
      dailyProtein.add(dayProtein);
      dailyCarbs.add(dayCarbs);
      dailyFat.add(dayFat);
    }

    // Calculate averages
    final daysLogged = dailyLogs.length;
    return {
      'avgCalories': dailyCalories.reduce((a, b) => a + b) / daysLogged,
      'avgProtein': dailyProtein.reduce((a, b) => a + b) / daysLogged,
      'avgCarbs': dailyCarbs.reduce((a, b) => a + b) / daysLogged,
      'avgFat': dailyFat.reduce((a, b) => a + b) / daysLogged,
      'daysLogged': daysLogged,
      'totalLogs': foodLogs.length,
      // Per-day totals so callers can tally days inside the ±5% tolerance band
      // (the weekly average alone hides how the week was distributed).
      'dailyCalories': dailyCalories,
    };
  }

  // ========================================
  // WORKOUT PLAN METHODS
  // ========================================

  /// Save a typed 7-day workout plan for the given ISO week. Non-blocking (see
  /// [_fireWrite]) so plan edits/regeneration apply offline immediately. No
  /// caller reads back `savedAt`, so not awaiting the serverTimestamp is safe.
  Future<void> saveWeeklyWorkoutPlan(
    String userId,
    String weekId,
    List<WorkoutDay> plan,
  ) async {
    _fireWrite(
      _db
          .collection('users')
          .doc(userId)
          .collection('workout_plans')
          .doc(weekId)
          .set({
            'days': plan.map((d) => d.toMap()).toList(),
            'savedAt': FieldValue.serverTimestamp(),
          }),
      'saveWeeklyWorkoutPlan',
    );
  }

  /// Delete the persisted workout plan for a given ISO week. Non-blocking so the
  /// force-regenerate flow proceeds immediately offline (the local delete is
  /// reflected in the subsequent cache read).
  Future<void> deleteWeeklyWorkoutPlan(String userId, String weekId) async {
    _fireWrite(
      _db
          .collection('users')
          .doc(userId)
          .collection('workout_plans')
          .doc(weekId)
          .delete(),
      'deleteWeeklyWorkoutPlan',
    );
  }

  /// Deletes every document from every user-history subcollection.
  /// Used by the dev-mode "Reset to Day One" tool to wipe a test account clean.
  Future<void> deleteAllUserData(String uid) async {
    const subcollections = [
      'food_logs',
      'workout_logs',
      'exercise_stats',
      'weight_logs',
      'workout_plans',
      'weekly_summaries',
      'saved_recipes',
      'saved_meals',
    ];
    final user = _db.collection('users').doc(uid);
    for (final col in subcollections) {
      final snap = await user.collection(col).get();
      for (final doc in snap.docs) {
        await doc.reference.delete();
      }
    }
  }

  /// Load the typed workout plan for a given ISO week. Returns null if not found.
  Future<List<WorkoutDay>?> loadWeeklyWorkoutPlan(
    String userId,
    String weekId,
  ) async {
    final doc = await _db
        .collection('users')
        .doc(userId)
        .collection('workout_plans')
        .doc(weekId)
        .get();
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    final days = data['days'] as List?;
    if (days == null) return null;
    return days
        .map((d) => WorkoutDay.fromMap(d as Map<String, dynamic>))
        .toList();
  }

  // ========================================
  // WEEKLY SUMMARY METHODS (adaptive report)
  // ========================================

  /// Persist one weekly adaptation snapshot at `weekly_summaries/{weekId}`.
  /// Written once per week by the adaptation flow (idempotent on the weekId).
  /// Non-blocking so the generate/adaptation flow completes offline; the doc-id
  /// is the weekId, so a re-sync never duplicates it.
  Future<void> saveWeeklySummary(String userId, WeeklySummary summary) async {
    _fireWrite(
      _db
          .collection('users')
          .doc(userId)
          .collection('weekly_summaries')
          .doc(summary.weekId)
          .set(summary.toMap()),
      'saveWeeklySummary',
    );
  }

  /// Read a single week's summary (e.g. the current week). Null if not found.
  Future<WeeklySummary?> getWeeklySummary(String userId, String weekId) async {
    final doc = await _db
        .collection('users')
        .doc(userId)
        .collection('weekly_summaries')
        .doc(weekId)
        .get();
    if (!doc.exists || doc.data() == null) return null;
    return WeeklySummary.fromMap(doc.data()!, doc.id);
  }

  /// List recent weekly summaries, newest first. Single-field order → no
  /// composite index needed.
  Future<List<WeeklySummary>> getWeeklySummaries(
    String userId, {
    int limit = 12,
  }) async {
    final snap = await _db
        .collection('users')
        .doc(userId)
        .collection('weekly_summaries')
        .orderBy('generatedAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => WeeklySummary.fromMap(d.data(), d.id)).toList();
  }

  // ========================================
  // WORKOUT LOG METHODS
  // ========================================

  static String weekIdFor(DateTime date, {int anchorWeekday = 1}) {
    final offset = (date.weekday - anchorWeekday + 7) % 7;
    final weekStart = date.subtract(Duration(days: offset));
    final y = weekStart.year;
    final week = ((weekStart.difference(DateTime(y)).inDays) / 7).ceil() + 1;
    return 'week_${y}_$week';
  }

  /// Returns the start of the week containing [date], anchored to
  /// [anchorWeekday] (1 = Monday … 7 = Sunday). Defaults to Monday.
  static DateTime weekStartFor(DateTime date, {int anchorWeekday = 1}) {
    final offset = (date.weekday - anchorWeekday + 7) % 7;
    return date.subtract(Duration(days: offset));
  }

  /// Saves a completed workout. Returns the client-generated id synchronously
  /// and fires the write without awaiting the ack, so "Mark as Done" works
  /// offline immediately (surfaces through [streamWorkoutLogForDate]).
  Future<String> saveWorkoutLog(WorkoutLog log) async {
    final docRef = _db
        .collection('users')
        .doc(log.userId)
        .collection('workout_logs')
        .doc();
    _fireWrite(docRef.set(log.toMap()), 'saveWorkoutLog');
    return docRef.id;
  }

  Stream<WorkoutLog?> streamWorkoutLogForDate(String userId, DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return _db
        .collection('users')
        .doc(userId)
        .collection('workout_logs')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .limit(1)
        .snapshots()
        .map(
          (snap) => snap.docs.isEmpty
              ? null
              : WorkoutLog.fromMap(snap.docs.first.data(), snap.docs.first.id),
        );
  }

  Future<List<WorkoutLog>> getWorkoutLogsForDateRange(
    String userId,
    DateTime start,
    DateTime end,
  ) async {
    final snap = await _db
        .collection('users')
        .doc(userId)
        .collection('workout_logs')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .orderBy('date')
        .get();
    return snap.docs.map((d) => WorkoutLog.fromMap(d.data(), d.id)).toList();
  }

  Future<int> getWorkoutsCompletedCount(
    String userId,
    DateTime weekStart,
  ) async {
    final end = weekStart.add(const Duration(days: 7));
    final logs = await getWorkoutLogsForDateRange(userId, weekStart, end);
    return logs.length;
  }

  // ========================================
  // WEIGHT LOG METHODS
  // ========================================

  /// Logs today's weight (doc-id = date, so re-logging overwrites). Non-blocking
  /// so weight logging works offline immediately.
  Future<void> saveWeightLog(String userId, double weightKg) async {
    final now = appNow();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _fireWrite(
      _db
          .collection('users')
          .doc(userId)
          .collection('weight_logs')
          .doc(dateKey)
          .set({
            'userId': userId,
            'date': Timestamp.fromDate(DateTime(now.year, now.month, now.day)),
            'weight': weightKg,
            'loggedAt': FieldValue.serverTimestamp(),
          }),
      'saveWeightLog',
    );
  }

  Future<List<Map<String, dynamic>>> getWeightLogs(
    String userId, {
    int limit = 30,
  }) async {
    final snap = await _db
        .collection('users')
        .doc(userId)
        .collection('weight_logs')
        .orderBy('date', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => d.data()).toList();
  }

  // ========================================
  // EXERCISE PERFORMANCE STATS (per-exercise last/PR for progressive overload)
  // ========================================

  static String _statDocId(String exerciseId) =>
      exerciseId.replaceAll(RegExp(r'[/\\.#\[\]*?]'), '_');

  /// Upserts the per-exercise stat: `last*` always updates; `best*` only when
  /// the new top-set weight is heavier. Mirrors the doc-id-by-key pattern of
  /// [saveWeightLog].
  Future<void> saveExerciseStat({
    required String userId,
    required String exerciseId,
    required String name,
    required double weightKg,
    int? reps,
    List<SetEntry> lastSets = const [],
  }) async {
    final now = appNow();
    final date = DateTime(now.year, now.month, now.day);
    final ref = _db
        .collection('users')
        .doc(userId)
        .collection('exercise_stats')
        .doc(_statDocId(exerciseId));
    final snap = await ref.get();
    double bestWeight = weightKg;
    DateTime bestDate = date;
    if (snap.exists) {
      final prevBest = (snap.data()?['bestWeightKg'] as num?)?.toDouble() ?? 0;
      if (prevBest >= weightKg) {
        bestWeight = prevBest;
        final bd = snap.data()?['bestDate'];
        bestDate = bd is Timestamp ? bd.toDate() : date;
      }
    }
    // Read-before-write: the `.get()` above resolves from cache offline; the
    // `.set()` is fired non-blocking so saving stats never hangs offline.
    _fireWrite(
      ref.set({
        'exerciseId': exerciseId,
        'name': name,
        'lastWeightKg': weightKg,
        'lastReps': reps,
        'lastDate': Timestamp.fromDate(date),
        'bestWeightKg': bestWeight,
        'bestDate': Timestamp.fromDate(bestDate),
        'lastSets': lastSets.map((s) => s.toMap()).toList(),
      }, SetOptions(merge: true)),
      'saveExerciseStat',
    );
  }

  /// Batch-reads per-exercise stats for [exerciseIds] → keyed by exerciseId.
  /// Uses `whereIn` on the document id, chunked to Firestore's 10-id limit.
  Future<Map<String, ExerciseStat>> getExerciseStats(
    String userId,
    List<String> exerciseIds,
  ) async {
    final result = <String, ExerciseStat>{};
    final docIds = exerciseIds.map(_statDocId).toSet().toList();
    final col = _db
        .collection('users')
        .doc(userId)
        .collection('exercise_stats');
    for (int i = 0; i < docIds.length; i += 10) {
      final chunk = docIds.sublist(i, (i + 10).clamp(0, docIds.length));
      if (chunk.isEmpty) continue;
      final snap = await col.where(FieldPath.documentId, whereIn: chunk).get();
      for (final d in snap.docs) {
        final stat = ExerciseStat.fromMap(d.data());
        result[stat.exerciseId] = stat;
      }
    }
    return result;
  }

  // ========================================
  // DAILY CALORIE TOTALS (for progress charts)
  // ========================================

  Future<Map<String, double>> getDailyCalorieTotals(
    String userId,
    DateTime weekStart,
  ) async {
    final weekEnd = weekStart.add(const Duration(days: 7));
    final logs = await getFoodLogsForDateRange(userId, weekStart, weekEnd);

    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final totals = <String, double>{for (final d in dayNames) d: 0.0};

    for (final food in logs) {
      final dayIndex = food.loggedAt.weekday - 1;
      if (dayIndex >= 0 && dayIndex < 7) {
        totals[dayNames[dayIndex]] =
            (totals[dayNames[dayIndex]] ?? 0) + food.totalCalories;
      }
    }
    return totals;
  }

  // ========================================
  // SAVED MEALS
  // ========================================

  String saveMeal(String uid, Meal meal, String recipeName) {
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('saved_meals')
        .doc();
    _fireWrite(
      ref.set({
        ...meal.toMap(),
        'recipeName': recipeName,
        'totalCalories': meal.totalCalories,
        'totalProtein': meal.totalProtein,
        'totalCarbs': meal.totalCarbs,
        'totalFat': meal.totalFat,
        'savedAt': FieldValue.serverTimestamp(),
      }),
      'saveMeal',
    );
    return ref.id;
  }

  Future<List<SavedMealDoc>> getSavedMeals(String uid, {String? mealType}) async {
    Query<Map<String, dynamic>> q = _db
        .collection('users')
        .doc(uid)
        .collection('saved_meals')
        .orderBy('savedAt', descending: true);
    if (mealType != null) {
      q = q.where('mealType', isEqualTo: mealType);
    }
    final snap = await q.get();
    return snap.docs.map((doc) {
      final data = doc.data();
      return SavedMealDoc(
        id: doc.id,
        mealType: data['mealType'] as String? ?? '',
        recipeName: data['recipeName'] as String? ?? '',
        meal: Meal.fromMap(data),
        totalCalories: (data['totalCalories'] as num?)?.toDouble() ?? 0,
        totalProtein: (data['totalProtein'] as num?)?.toDouble() ?? 0,
        totalCarbs: (data['totalCarbs'] as num?)?.toDouble() ?? 0,
        totalFat: (data['totalFat'] as num?)?.toDouble() ?? 0,
        savedAt: (data['savedAt'] as Timestamp?)?.toDate(),
      );
    }).toList();
  }

  void deleteSavedMeal(String uid, String docId) {
    _fireWrite(
      _db
          .collection('users')
          .doc(uid)
          .collection('saved_meals')
          .doc(docId)
          .delete(),
      'deleteSavedMeal',
    );
  }

  Future<SavedMealDoc?> findSavedMealByRecipeName(
      String uid, String recipeName) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('saved_meals')
        .where('recipeName', isEqualTo: recipeName)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    final data = doc.data();
    return SavedMealDoc(
      id: doc.id,
      mealType: data['mealType'] as String? ?? '',
      recipeName: data['recipeName'] as String? ?? '',
      meal: Meal.fromMap(data),
      totalCalories: (data['totalCalories'] as num?)?.toDouble() ?? 0,
      totalProtein: (data['totalProtein'] as num?)?.toDouble() ?? 0,
      totalCarbs: (data['totalCarbs'] as num?)?.toDouble() ?? 0,
      totalFat: (data['totalFat'] as num?)?.toDouble() ?? 0,
      savedAt: (data['savedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class SavedMealDoc {
  final String id;
  final String mealType;
  final String recipeName;
  final Meal meal;
  final double totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;
  final DateTime? savedAt;

  const SavedMealDoc({
    required this.id,
    required this.mealType,
    required this.recipeName,
    required this.meal,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
    this.savedAt,
  });
}
