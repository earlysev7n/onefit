import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../algorithms/greedy_algorithm.dart';
import '../models/exercise.dart';
import '../models/meal_ingredient.dart';
import '../models/food_item.dart';
import '../models/edamam_recipe.dart';
import '../services/firestore_service.dart';
import '../app_clock.dart';

class PlanProvider extends ChangeNotifier {
  final _firestoreService = FirestoreService();

  // Workout plan
  List<WorkoutDay> _workoutPlan = [];
  List<WorkoutDay> get workoutPlan => _workoutPlan;

  // Meal plan — per meal type for today
  Meal? _breakfast;
  Meal? _lunch;
  Meal? _dinner;
  Meal? _snack;

  Meal? get breakfast => _breakfast;
  Meal? get lunch => _lunch;
  Meal? get dinner => _dinner;
  Meal? get snack => _snack;

  // Get today's workout day
  WorkoutDay? get todayWorkout {
    if (_workoutPlan.isEmpty) return null;
    final weekday = appNow().weekday;
    final index = weekday - 1;
    if (index >= _workoutPlan.length) return null;
    return _workoutPlan[index];
  }

  double get todayCalories =>
      (_breakfast?.totalCalories ?? 0) +
      (_lunch?.totalCalories ?? 0) +
      (_dinner?.totalCalories ?? 0) +
      (_snack?.totalCalories ?? 0);

  double get todayProtein =>
      (_breakfast?.totalProtein ?? 0) +
      (_lunch?.totalProtein ?? 0) +
      (_dinner?.totalProtein ?? 0) +
      (_snack?.totalProtein ?? 0);

  double get todayCarbs =>
      (_breakfast?.totalCarbs ?? 0) +
      (_lunch?.totalCarbs ?? 0) +
      (_dinner?.totalCarbs ?? 0) +
      (_snack?.totalCarbs ?? 0);

  double get todayFat =>
      (_breakfast?.totalFat ?? 0) +
      (_lunch?.totalFat ?? 0) +
      (_dinner?.totalFat ?? 0) +
      (_snack?.totalFat ?? 0);

  void setWorkoutPlan(List<WorkoutDay> plan) {
    _workoutPlan = plan;
    notifyListeners();
  }

  // ── Persist workout plan to / load from Firestore ──────────────────────────

  Future<void> persistWorkoutPlan(String userId, String weekId) async {
    if (_workoutPlan.isEmpty) return;
    // Refuse to persist a plan where every training day has 0 exercises —
    // that would lock the user into a broken state across restarts.
    final hasExercises = _workoutPlan.any((d) => !d.isRest && d.exercises.isNotEmpty);
    if (!hasExercises) return;
    await _firestoreService.saveWeeklyWorkoutPlan(userId, weekId, _workoutPlan);
  }

  Future<bool> loadWorkoutPlan(String userId, String weekId) async {
    final saved = await _firestoreService.loadWeeklyWorkoutPlan(userId, weekId);
    if (saved == null || saved.isEmpty) return false;
    // Reject plans where every training day is empty — they were persisted in
    // a broken state and should be regenerated from scratch.
    final hasExercises = saved.any((d) => !d.isRest && d.exercises.isNotEmpty);
    if (!hasExercises) return false;
    _workoutPlan = saved;
    notifyListeners();
    return true;
  }

  /// Clear the in-memory plan and delete its Firestore document.
  /// Called by the force-regenerate flow so _generate() finds no plan and
  /// builds a fresh one.
  Future<void> clearAndDeleteWorkoutPlan(String userId, String weekId) async {
    _workoutPlan = [];
    notifyListeners();
    await _firestoreService.deleteWeeklyWorkoutPlan(userId, weekId);
  }

  // ── Per-day edit methods (each persists immediately) ──────────────────────

  Future<void> replaceExercise(
    String userId,
    String weekId,
    int dayIdx,
    int exIdx,
    Exercise newExercise, {
    int? sets,
    String? reps,
    int? restSeconds,
  }) async {
    if (dayIdx >= _workoutPlan.length) return;
    final day = _workoutPlan[dayIdx];
    if (exIdx >= day.exercises.length) return;
    final old = day.exercises[exIdx];
    final updated = List<WorkoutExercise>.from(day.exercises);
    updated[exIdx] = WorkoutExercise(
      exercise: newExercise,
      sets: sets ?? old.sets,
      reps: reps ?? old.reps,
      restSeconds: restSeconds ?? old.restSeconds,
    );
    _workoutPlan[dayIdx] = WorkoutDay(
      dayName: day.dayName,
      focus: day.focus,
      isRest: day.isRest,
      exercises: updated,
    );
    notifyListeners();
    await persistWorkoutPlan(userId, weekId);
  }

  Future<void> removeExercise(
    String userId,
    String weekId,
    int dayIdx,
    int exIdx,
  ) async {
    if (dayIdx >= _workoutPlan.length) return;
    final day = _workoutPlan[dayIdx];
    if (exIdx >= day.exercises.length) return;
    final updated = List<WorkoutExercise>.from(day.exercises)..removeAt(exIdx);
    _workoutPlan[dayIdx] = WorkoutDay(
      dayName: day.dayName,
      focus: day.focus,
      isRest: day.isRest,
      exercises: updated,
    );
    notifyListeners();
    await persistWorkoutPlan(userId, weekId);
  }

  Future<void> addExercise(
    String userId,
    String weekId,
    int dayIdx,
    WorkoutExercise exercise,
  ) async {
    if (dayIdx >= _workoutPlan.length) return;
    final day = _workoutPlan[dayIdx];
    final updated = List<WorkoutExercise>.from(day.exercises)..add(exercise);
    _workoutPlan[dayIdx] = WorkoutDay(
      dayName: day.dayName,
      focus: day.focus,
      isRest: day.isRest,
      exercises: updated,
    );
    notifyListeners();
    await persistWorkoutPlan(userId, weekId);
  }

  Future<void> updateExerciseParams(
    String userId,
    String weekId,
    int dayIdx,
    int exIdx, {
    int? sets,
    String? reps,
    int? restSeconds,
  }) async {
    if (dayIdx >= _workoutPlan.length) return;
    final day = _workoutPlan[dayIdx];
    if (exIdx >= day.exercises.length) return;
    final old = day.exercises[exIdx];
    final updated = List<WorkoutExercise>.from(day.exercises);
    updated[exIdx] = WorkoutExercise(
      exercise: old.exercise,
      sets: sets ?? old.sets,
      reps: reps ?? old.reps,
      restSeconds: restSeconds ?? old.restSeconds,
    );
    _workoutPlan[dayIdx] = WorkoutDay(
      dayName: day.dayName,
      focus: day.focus,
      isRest: day.isRest,
      exercises: updated,
    );
    notifyListeners();
    await persistWorkoutPlan(userId, weekId);
  }

  Future<void> setMeal(
    String mealType,
    Meal? meal, {
    bool saveToFirestore = false,
  }) async {
    switch (mealType) {
      case 'breakfast':
        _breakfast = meal;
        break;
      case 'lunch':
        _lunch = meal;
        break;
      case 'dinner':
        _dinner = meal;
        break;
      case 'snack':
        _snack = meal;
        break;
    }

    if (saveToFirestore && meal != null) {
      await _saveMealToFirestore(mealType, meal);
    }

    notifyListeners();
  }

  Future<void> setAllMeals(
    Meal? breakfast,
    Meal? lunch,
    Meal? dinner,
    Meal? snack, {
    bool saveToFirestore = false,
  }) async {
    _breakfast = breakfast;
    _lunch = lunch;
    _dinner = dinner;
    _snack = snack;

    if (saveToFirestore) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _clearTodayGeneratedMeals(user.uid);
        if (breakfast != null)
          await _saveMealToFirestore('breakfast', breakfast);
        if (lunch != null) await _saveMealToFirestore('lunch', lunch);
        if (dinner != null) await _saveMealToFirestore('dinner', dinner);
        if (snack != null) await _saveMealToFirestore('snack', snack);
      }
    }

    notifyListeners();
  }

  void clearMeals() {
    _breakfast = null;
    _lunch = null;
    _dinner = null;
    _snack = null;
    notifyListeners();
  }

  /// Save each ingredient in the meal as its own FoodItem so they
  /// reload correctly from Firestore with all ingredients intact.
  Future<void> _saveMealToFirestore(String mealType, Meal meal) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = appNow();

    for (int i = 0; i < meal.items.length; i++) {
      final item = meal.items[i];
      final ing = item.ingredient;
      final grams = item.portionGrams;

      // Scale nutrition values to the actual portion
      final scale = grams / 100;

      final foodItem = FoodItem(
        id: '${now.millisecondsSinceEpoch}_${mealType}_$i',
        userId: user.uid,
        name: ing.name,
        barcode: 'ai_generated',
        servingSize: grams,
        servingSizeUnit: 'g',
        calories: ing.calories * scale,
        protein: ing.protein * scale,
        carbs: ing.carbs * scale,
        fat: ing.fat * scale,
        fiber: ing.fiber * scale,
        sugar: ing.sugar * scale,
        sodium: ing.sodium * scale,
        loggedAt: now,
        mealType: mealType,
        quantity: 1.0,
      );

      await _firestoreService.logFoodItem(foodItem);
    }
  }

  Future<void> _clearTodayGeneratedMeals(String userId) async {
    final today = appNow();
    final todayLogs = await _firestoreService.getFoodLogsForDate(userId, today);
    for (var log in todayLogs) {
      if (log.barcode == 'ai_generated') {
        await _firestoreService.deleteFoodLog(userId, log.id);
      }
    }
  }

  /// Log a generated Edamam recipe as a food item with full macro + micro data.
  Future<void> logEdamamRecipe(EdamamRecipe recipe, String mealType) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = appNow();
    final foodItem = FoodItem(
      id: '${now.millisecondsSinceEpoch}_${mealType}_edamam',
      userId: user.uid,
      name: recipe.label,
      barcode: 'ai_generated',
      servingSize: 1,
      servingSizeUnit: 'serving',
      calories: recipe.calories,
      protein: recipe.protein,
      carbs: recipe.carbs,
      fat: recipe.fat,
      fiber: recipe.fiber,
      sugar: recipe.sugar,
      sodium: recipe.sodium,
      vitaminA: recipe.vitaminA,
      vitaminC: recipe.vitaminC,
      vitaminD: recipe.vitaminD,
      vitaminE: recipe.vitaminE,
      vitaminK: recipe.vitaminK,
      vitaminB6: recipe.vitaminB6,
      vitaminB12: recipe.vitaminB12,
      folate: recipe.folate,
      calcium: recipe.calcium,
      iron: recipe.iron,
      magnesium: recipe.magnesium,
      potassium: recipe.potassium,
      zinc: recipe.zinc,
      phosphorus: recipe.phosphorus,
      loggedAt: now,
      mealType: mealType,
      quantity: 1.0,
    );

    await _firestoreService.logFoodItem(foodItem);
  }

  // ignore: unused_element
  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
