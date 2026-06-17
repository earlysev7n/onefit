# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run on Android (emulator must be running)
flutter run

# Run on Windows desktop
flutter run -d windows

# Analyze for type errors and lint warnings
flutter analyze

# Install/update packages
flutter pub get

# Deploy Firestore rules and indexes
firebase deploy --only firestore --project onefit-392b8
```

There are no automated tests in this project.

## Architecture

**OneFit** is a Flutter gym app using Firebase Auth + Cloud Firestore, Provider state management, and free external APIs for exercise and meal data.

### State management

Four `ChangeNotifier` providers registered in `main.dart`:
- `ThemeProvider` — dark/light mode toggle
- `PlanProvider` — in-memory workout and meal plan for the current session; exposes per-day edit methods (`replaceExercise`, `removeExercise`, `addExercise`, `updateExerciseParams`) that each persist to Firestore immediately; also holds `setMeal(mealType, meal, saveToFirestore: true)` → `_saveMealToFirestore` which writes each `MealIngredient` item as its own `FoodItem` (scaled to grams)
- `ProgressProvider` — aggregates all weekly stats (food logs, workout logs, weight logs) for the Progress screen; call `loadAll(userId, {UserProfile? profile})` to refresh (pass the `ProfileProvider` profile to skip a redundant read); exposes `plannedWorkoutDays` (from `UserProfile.workoutDaysPerWeek`) and `weeklyWorkoutCompletion` using the real planned-days denominator
- `ProfileProvider` (`lib/providers/profile_provider.dart`) — **single reactive source of truth for the current user's `UserProfile`**. `load(uid)` fetches once and caches (no-op if already loaded); `refresh(uid)` force-refetches; `save(p)` persists + notifies (used by onboarding and the edit screen); `updateWeight(kg)` and `applyCalorieAdjustment(biasKcal)` are `copyWith`+`save` helpers. Home, Nutrition, Plans (`_WorkoutTab`/`_MealTab`) and Profile read it instead of fetching the profile independently, so a profile edit, a weight log, or a weekly calorie adaptation updates every screen reactively. Home calls `load(uid)` in `initState`; consumers `watch` it.

### Navigation

No named routes. All navigation is `Navigator.push(MaterialPageRoute(...))`. The `AuthGate` in `main.dart` listens to `FirebaseAuth.authStateChanges` and routes to `LoginScreen`, `ProfileInputScreen`, or `HomeScreen`. `HomeScreen` is a `BottomNavigationBar` with 4 tabs: Home, Plans, Nutrition, Progress.

### Data layer

`FirestoreService` is a plain class (not a singleton) — instantiate it anywhere with `FirestoreService()`. Firestore structure:

```
users/{uid}                         ← UserProfile doc
  food_logs/{logId}                 ← FoodItem per logged meal/food
  workout_logs/{logId}              ← WorkoutLog when user marks a day done
  weight_logs/{logId}               ← WeightLog (one per day, doc ID = date string)
  exercise_stats/{exerciseId}       ← ExerciseStat (per-exercise last/PR top set; doc ID = exerciseId)
  workout_plans/{weekId}            ← persisted WorkoutDay list for that ISO week
  weekly_summaries/{weekId}         ← WeeklySummary (planned, not yet wired fully)
exercises/{exerciseId}              ← ExerciseDB API cache (30-day TTL)
```

`workout_plans/{weekId}` is written by `FirestoreService.saveWeeklyWorkoutPlan` and read by `loadWeeklyWorkoutPlan`. The weekId is produced by `FirestoreService.weekIdFor(date)` → `week_YYYY_N` (normalised to Monday of that week, stable for the whole Mon–Sun range). `deleteWeeklyWorkoutPlan` removes the doc; used by the force-regenerate flow.

`UserProfile` stores all body stats and preferences. It computes `calorieGoal`, `tdee`, and `macroGoals` (macro gram targets) derived from Mifflin-St Jeor BMR + Harris-Benedict activity multiplier.

**UserProfile scheduling & recovery fields** (added in Phase 1/2; all have safe defaults for backward-compatible Firestore reads):

| Field | Type | Default | Role |
|---|---|---|---|
| `activityLevel` | String | `'Moderately Active'` | Drives `activityMultiplier` → TDEE → calorie goal |
| `workoutDaysPerWeek` | int | `3` | How many training days to place in the 7-day schedule |
| `sessionMinutes` | int | `45` | Drives `_exercisesPerDay` count (30→3, 45→5, 60→6, 90→8) |
| `workoutSplit` | String | `'Full Body Training'` | Maps to a focus-cycle sequence in `_splitFocusSequence()` |
| `avgHoursSlept` | double | `7.0` | Powers `recoveryScore` (< 6h → 0.7, 6–7h → 0.85, ≥ 7h → 1.0) |
| `calorieAdjustment` | int | `0` | Accumulated weekly calorie-goal bias, added on top of the goal-derived base in `calorieGoal` then clamped to the 1200 floor; fed by `AdaptationEngine.calorieBiasKcal` once per new `weekId` and clamped to ±500 by `ProfileProvider.applyCalorieAdjustment` |

`activityMultiplier` is now a real Harris-Benedict 5-tier lookup from `activityLevel` (not an experience+location proxy). Gender is stored as `'Male'` or `'Female'` only — no "Other" option; both Mifflin-St Jeor paths are used.

`UserProfile.pinnedExercises` (`Map<String,List<String>>`, focus → exercise ids, default `{}`) holds anchor lifts the user wants guaranteed in a given day focus; the greedy generator force-includes them first (see below). `UserProfile` is immutable; use `copyWith(...)` for edits (preserves `uid` and `calorieAdjustment`). The `calorieGoal` getter computes a goal-derived base (`tdee − 500` / `+ 300` / `+ 200` / `tdee`), adds `calorieAdjustment`, then clamps to `[1200, 99999]`; `macroGoals` reads `calorieGoal`, so macros scale automatically.

**Weight is a single reactive value.** `UserProfile.weight` drives BMR/TDEE/`calorieGoal`/BMI; logging today's weight on the Progress screen calls `ProfileProvider.updateWeight(kg)` (persists + notifies → Home/Nutrition rings recompute) **and** `ProgressProvider.logWeight(uid, kg)` (saves the `weight_logs` entry + reloads Progress). The two stores no longer drift.

Weight and height are always stored in metric (kg/cm) internally; display conversion happens in `UserProfile.weightDisplay` / `heightDisplay`.

### Algorithms

- `GreedyAlgorithm` (`lib/algorithms/greedy_algorithm.dart`) — generates a 7-day `List<WorkoutDay>` from a `List<Exercise>` and `UserProfile`. `_getSchedule(profile)` places exactly `workoutDaysPerWeek` training days using evenly-spaced positions and cycles through the split's focus sequence (`_splitFocusSequence`). **`workoutDaysPerWeek` is a hard constraint** — adaptation never adds or removes training days. `_exercisesPerDay(profile, bias)` scales from `sessionMinutes` ± experience nudge − recovery penalty − 1 when `difficultyBias == 'down'`. `_getSets(profile, bias)` shaves a set when `recoveryScore < 0.8`, and applies ±1 for `difficultyBias` `'up'`/`'down'` (clamped 2–6). `generatePlan` accepts optional `difficultyBias` (`'up'`/`'down'`/`'same'`) only — it has **no** `calorieBiasKcal` parameter. The weekly `AdaptationEngine.calorieBiasKcal` is applied to the calorie goal via `ProfileProvider.applyCalorieAdjustment` in `_generate()`'s fresh-generation branch (runs at most once per `weekId` because the persisted-plan branch returns early), not passed into the workout generator. `_generate()` only runs the `AdaptationEngine` when last week has real history (a persisted plan or ≥1 workout log) — otherwise a new user's empty week reads as 0% completion and wrongly triggers `'down'`.
  - **Hard constraints** live in `static GreedyAlgorithm.isEligibleForUser(Exercise, UserProfile)`: gender-tagged demo variants (`\bmale\b`/`\bfemale\b` name filter — the regex does not match "female" when looking for "male"), location (Gym → all equipment available; Home → exercise must list `home` and intersect the user's equipment, bodyweight always allowed), and the **bench rule** (Home: free-weight `incline|decline|bench` moves are excluded — no bench equipment option exists; bodyweight variants stay). The strict experience gate is `static difficultyAllowed(difficulty, level)`. **PlansScreen's picker/gap-fill/volume-debt paths must filter through both** (see `_usableByUser` in plans_screen.dart) so manual edits can't inject ineligible exercises.
  - **Selection is incremental greedy** (`_selectExercisesForDay`): pick best, update day-local muscle hits, re-score, repeat — plus a per-muscle-per-day cap (`ceil(count/targets)` clamped ≥2). Score weights: focus +50 (dominant), goal +15, **staple-compound +12** (`static isStapleCompound` — multi-joint name keywords or ≥2 secondary muscles; keeps it below focus so the day's focus still dominates), exact-tier difficulty +10, day-local muscle penalty −25/hit, weekly −15/hit. Do NOT raise the goal/compound weights above the focus bonus — that recreates the "whole day is one muscle" bug. Compound-first holds on day 1 (no weekly hits); later days may lead with an isolation on a fresh muscle (by design — variety/balance).
  - **Pinned anchor lifts:** `_selectExercisesForDay` takes `dayFocus` and, before the greedy loop, force-includes (first) each `UserProfile.pinnedExercises[dayFocus]` id that is still in the eligible pool — so an ineligible pin (e.g. a Home user who pinned a barbell lift) is silently skipped. Capped at `count-1` when `count > 1` so a generated slot remains for variety. Pins live on the profile, so they survive regeneration.
  - **Splits:** 5 selectable (Full Body, Upper/Lower, PPL, Functional, Strength + Conditioning). `_splitFocusSequence` keeps legacy arms (Bro/Body Part/Hybrid/HIIT/Circuit) so pre-reduction profiles still generate; ProfileInputScreen falls back to Full Body when editing such a profile.
- `WorkoutDay` / `WorkoutExercise` (defined in `greedy_algorithm.dart`) — both have `toMap()`/`fromMap()` for Firestore round-trips.
- `AdaptationEngine` (`lib/algorithms/adaptation_engine.dart`) — pure Dart, no Flutter/Firebase. Takes last week's calorie adherence, workout completion rate, and optional `avgHoursSlept` → returns `AdaptationResult` with `calorieBiasKcal` and `difficultyBias`. Difficulty order: completion `< 0.5` → `'down'` **first** (a struggling user is eased off even when under-rested); otherwise under-slept users (< 6.5h) are held at `'same'` (poor sleep blocks a step-**up** but never an easing-off); otherwise completion `≥ 0.8` (non-Advanced) → `'up'`. An optional `lastWeekAvgRating` (1 too easy … 5 too hard, averaged from last week's `WorkoutLog.rating`) is a **modifier**: a hard week (≥4) blocks a step-up; an easy week (≤2) bumps a mid-completion week up — but it never overrides the struggling `'down'` or the sleep hold. `_generate()` aggregates last week's ratings and passes them in.
- `GeneticAlgorithm` (`lib/algorithms/genetic_algorithm.dart`) — **the meal generator** (per the capstone objective). `generatePlan({allIngredients, profile, cuisine})` evolves combinations of `MealIngredient`s (the USDA-seeded `ingredients` collection) into a 7-day `List<DayMealPlan>`, scored by a fitness function on the user's calorie/macro targets; filters by cuisine (`any`/`filipino`/`western`/`asian`) and dietary restrictions. Wired into the Plans → Meal tab's Generate / Generate All. Ingredients are loaded via `FirestoreService.getIngredients()` (in-memory cached) and seeded with `SeedData.seedIngredients()` (Profile screen button, gated by `kShowSeedTools`).

### External APIs

| Service | File | Notes |
|---|---|---|
| ExerciseDB | `lib/services/exercise_db_service.dart` | `https://oss.exercisedb.dev/api/v1` (AscendAPI free tier; old `exercisedb-api.vercel.app` host is retired/402) — no key. Cursor-paginated (`?after=<meta.nextCursor>`, fixed 25/page); GIFs served from `static.exercisedb.dev`. Results cached in Firestore `exercises` collection; bump `_cacheVersion` to force a one-time re-fetch when the host/shape changes. During the cache build, `_keepExercisesWithWorkingGifs` HEAD-checks every `gifUrl` and drops the ~7% that 404 on `static.exercisedb.dev` (only definitive 404s are dropped; timeouts/5xx/429 are kept; if < 50% survive the catalog is kept whole) so every cached exercise has a working demo. Before that, `_isLikelyAutoGenerated` drops auto-generated junk names (style-prefix `\b[a-z-]+ style `, the word `gentle`, or a dangling `with <adjective>` like "with classic") — precision-tuned, so plain `" with "` and `"(...)"` names are kept. The API has no difficulty field — difficulty is inferred by `lib/services/difficulty_inference.dart` (pure Dart; default-to-beginner, keyword/equipment promotion; bump `_cacheVersion` after changing it) |
| ~~TheMealDB~~ | `lib/services/meal_service.dart` | **No longer used.** Meal generation now runs the `GeneticAlgorithm` over the USDA-seeded `ingredients` collection. The file is left orphaned (no importers) for reference; safe to delete. |
| Edamam | `lib/services/edamam_service.dart` | Hardcoded credentials are for Meal Planner plan, **not** Recipe Search — 401s if called against `/api/recipes/v2` |
| OpenFoodFacts | `lib/services/openfoodfacts_service.dart` | Barcode scanning lookups |
| USDA FDC | (inside food log screen) | Manual food search |

`MealService.fetchRecipes()` and `EdamamService.fetchRecipes()` share the same signature and both return `List<EdamamRecipe>` — they are drop-in replaceable. `MealService._categoriesForMealType()` hard-constrains meal categories by diet style (high-protein/keto → only meat/seafood; Mediterranean → seafood/chicken/veg; etc.). `scaleToCalories(recipe, targetCals)` proportionally scales all 26 nutrition fields to hit a per-meal calorie target. `PlanProvider.logEdamamRecipe()` saves an `EdamamRecipe` as a `FoodItem` with `barcode: 'ai_generated'` and full vitamin/mineral fields.

### Key model relationships

- `FoodItem` — a single logged food entry; holds full macro + 14 vitamin/mineral fields; `barcode: 'ai_generated'` means it came from meal generation
- `EdamamRecipe` — the recipe model returned by `EdamamService`; `PlanProvider.logEdamamRecipe()` remains in place (unused by current meal-tab flow, available for future recipe features)
- `WorkoutLog` / `WorkoutLogExercise` — saved when user taps "Mark as Done" on the Plans screen; streamed to Home screen workout card via `FirestoreService.streamWorkoutLogForDate()`. `WorkoutLog.rating` (1–5, optional) is the post-workout perceived-difficulty rating (feeds `AdaptationEngine`). `WorkoutLogExercise.weightKg`/`repsDone` (optional) are the *performed* top set entered live during the session — distinct from the *prescribed* `sets`/`reps`.
- `ExerciseStat` (`lib/models/exercise_stat.dart`) — denormalized per-exercise `last*`/`best*` top set at `users/{uid}/exercise_stats/{exerciseId}`, upserted by `FirestoreService.saveExerciseStat` on each workout save (last always; best only if heavier). Powers the inline "Last: X · PR Y" target and PR badge; read in bulk via `getExerciseStats` (`whereIn` on doc id, chunked by 10 — no composite index).
- `Exercise.gifUrl` — populated from ExerciseDB API; rendered with `gaplessPlayback: true`, a `User-Agent` header, and an empty-string guard — all three are required for GIF animation to work

### Meal saving — one path in PlanProvider

**GA-generated meals** (`setMeal → _saveMealToFirestore`): Each `MealIngredient` inside a `Meal` is saved as its own `FoodItem` (scaled to the actual portion grams, `barcode: 'ai_generated'`). This is the sole meal-generation save path — the GA produces the ingredient list; logging it writes each ingredient individually. `logEdamamRecipe` remains in the codebase for future use (e.g. a recipe feature) but is not called by the current meal-tab generate flow.

### PlansScreen — exercise cache pattern

`PlansScreen` keeps a `List<Exercise> _allExercises` state variable used by the exercise picker and gap-fill logic. **This must be populated on every code path:**
- `_generate()` always fetches exercises via `ExerciseDBService().getExercises()` **before** checking for a persisted plan, so both the load-from-Firestore and generate-fresh branches have `_allExercises` set.
- `initState` kicks off a background `getExercises().then(...)` for the hot-restart path (in-memory plan already present, `_generate()` not called).

Failing to follow this pattern results in "No matching exercises found" in the picker.

### PlansScreen — plan persistence & force-regenerate

Plans are persisted per ISO week to `users/{uid}/workout_plans/{weekId}`. The refresh `↺` button calls `_forceRegenerate()`, which deletes the Firestore doc via `PlanProvider.clearAndDeleteWorkoutPlan()`, then calls `_generate()`. This is the escape route from a corrupted plan.

`PlanProvider.persistWorkoutPlan` refuses to write if every training day has 0 exercises. `loadWorkoutPlan` refuses to accept such a plan from Firestore. Both guards prevent the "broken plan locked forever" failure mode.

Edit mode enforces a 50% minimum exercise cap (cannot remove more than half the original count). Removing exercises without replacing them triggers an AlertDialog offering either auto-fill (`_fillExerciseGap`) or a volume-debt penalty (`_applyVolumeDebt`) that adds 1 extra exercise to the next 1–3 upcoming workout days.

### PlansScreen tab navigation

`PlansScreen` has two tabs — Workout (index 0) and Meal (index 1). To switch programmatically:
- Pass route arguments `{'mealType': '<type>'}` when pushing `PlansScreen` — `didChangeDependencies` picks this up and animates to the meal tab.
- Call `plansScreenKey.currentState?.switchToMealTab()` directly — `plansScreenKey` is a `GlobalKey<PlansScreenState>` defined in `home_screen.dart`.

### UI design tokens

All screens share a consistent dark theme. Use these constants inline (they are not extracted to a theme file):

| Token | Value | Usage |
|---|---|---|
| Background | `Color(0xFF0D0D0D)` | Scaffold background |
| Surface/card | `Color(0xFF1A1A1A)` | Cards, bottom sheets, tab bars |
| Primary accent | `Color(0xFF00C97B)` | Buttons, progress indicators, active tab |
| Muted text | `Color(0xFF888888)` | Secondary labels |
| Header font | `GoogleFonts.spaceGrotesk` | Titles, headings (`w700`) |
| Body font | `GoogleFonts.inter` | Body copy, labels |

### Firestore security rules and indexes

`firestore.rules` and `firestore.indexes.json` are in the project root. Deploy with `firebase deploy --only firestore --project onefit-392b8`. The only composite index needed is on `workout_logs` (date ASC + userId ASC) — single-field indexes are managed automatically by Firestore. The `workout_plans` subcollection is fetched by doc ID so no composite index is needed.

### Debug flags

`_DEBUG_FORCE_LOGOUT` in `main.dart` — set to `true` to force sign-out on every hot restart during auth testing. Must be `false` before any build intended for real use.

`kDebugDayChanger` in `lib/app_clock.dart` — when `true`, shows a floating ◀ date ▶ pill (wired via `MaterialApp.builder` in `main.dart`) that shifts the app's notion of "today" for testing date-dependent flows (weekId, today's plan/meals, streaks, weekly adaptation, where new logs land). All *logical* date reads go through `appNow()` / `appToday()` from `app_clock.dart` instead of `DateTime.now()`; real-time concerns (cache TTLs, unique IDs, workout-duration timers, `Timestamp` parse fallbacks) intentionally still call `DateTime.now()`. Changing the day re-keys the root navigator, so it returns to `HomeScreen` and re-reads everything for the simulated day. Must be `false` before any real build.

### Misc

- `lib/data/seed_data.dart` — one-off dev utility that seeds exercises and ingredients from USDA FDC into Firestore. Not called at runtime; ignore unless seeding.
- `lib/services/openai_service.dart` — `OpenAIService.generateRecipe({ingredients, mealType})` calls the OpenAI Chat Completions API (`gpt-4o-mini`, JSON response) to turn a GA meal's ingredient list (with gram portions) into step-by-step cooking instructions → `OpenAIRecipe(title, steps, readyInMinutes, servings)`. Wired into `RecipeScreen`. API key is a hardcoded constant (move to env config for production).
- `SCREENS.md` in the project root — living documentation covering every screen's responsibilities, provider connections, and data flows. Update it after any screen-level change.
