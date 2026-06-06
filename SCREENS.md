# OneFit — Screen & Architecture Reference

> **How to read this file:** every screen has a Purpose, a State section, a Key Functions section, and a Connections section that links it to providers, services, and other screens. Algorithms and providers are also documented. This file is updated after every development phase.

---

## Table of Contents
1. [App Entry & Navigation Shell](#1-app-entry--navigation-shell)
2. [Auth Screens](#2-auth-screens)
   - [LoginScreen](#loginscreen)
   - [RegisterScreen](#registerscreen)
3. [Onboarding](#3-onboarding)
   - [ProfileInputScreen](#profileinputscreen)
4. [Main Shell — HomeScreen](#4-main-shell--homescreen)
5. [Plans Tab — PlansScreen](#5-plans-tab--plansscreen)
6. [Nutrition Tab — NutritionScreen](#6-nutrition-tab--nutritionscreen)
7. [Progress Tab — ProgressScreen](#7-progress-tab--progressscreen)
8. [Profile Tab — ProfileScreen](#8-profile-tab--profilescreen)
9. [Supporting Screens](#9-supporting-screens)
   - [FoodLogScreen](#foodlogscreen)
   - [BarcodeScanScreen](#barcodescanscreen)
   - [RecipeScreen](#recipescreen)
10. [Providers](#10-providers)
    - [ProfileProvider](#profileprovider)
    - [PlanProvider](#planprovider)
    - [ProgressProvider](#processprovider)
    - [ThemeProvider](#themeprovider)
11. [Algorithms](#11-algorithms)
    - [GreedyAlgorithm](#greedyalgorithm)
    - [AdaptationEngine](#adaptationengine)
12. [Services](#12-services)
13. [Data Model Quick-Reference](#13-data-model-quick-reference)
14. [Change Log by Phase](#14-change-log-by-phase)

---

## 1. App Entry & Navigation Shell

**File:** `lib/main.dart`

### AuthGate
The root widget. Listens to `FirebaseAuth.authStateChanges` and routes the user to one of three screens:

| Auth state | Has Firestore profile? | Routed to |
|---|---|---|
| Signed out | — | `LoginScreen` |
| Signed in | No | `ProfileInputScreen` |
| Signed in | Yes | `HomeScreen` |

Navigation uses `navigatorKey` (a global `GlobalKey<NavigatorState>`) with `pushAndRemoveUntil` so the back-stack is always clean after a route change.

**`_DEBUG_FORCE_LOGOUT`** — set `true` in `main.dart` to force sign-out on every hot-restart during auth testing. Must be `false` before any real build.

---

## 2. Auth Screens

### LoginScreen
**File:** `lib/screens/login_screen.dart`

**Purpose:** Authenticates an existing user.

**State:** `_emailController`, `_passwordController`, `_isLoading`.

**Key functions:**
- Submit button → calls `AuthService().signIn(email, password)` → on success, `AuthGate` re-routes automatically via the auth stream.
- "Create account" link → `Navigator.push` to `RegisterScreen`.

**Connections:**
- `AuthService.signIn` → Firebase Auth.
- On success: `AuthGate` stream fires → `HomeScreen` (if profile exists) or `ProfileInputScreen`.

---

### RegisterScreen
**File:** `lib/screens/register_screen.dart`

**Purpose:** Creates a new Firebase Auth account. Collects **email**, **password**, and **confirm password only** — no name (collected later in onboarding).

**State:** `_emailController`, `_passwordController`, `_confirmPasswordController`, `_isLoading`.

**Key functions:**
- **Validation** (runs before any Firebase call):
  - Email must contain `@`.
  - Password must be ≥ 6 characters.
  - Password and confirm-password must match → SnackBar error if they don't.
- Submit → `AuthService().register(email, password)` → `Navigator.pop` → `AuthGate` routes to `ProfileInputScreen`.

**Connections:**
- `AuthService.register` → Firebase Auth.
- On success: `AuthGate` stream fires → `ProfileInputScreen` (no Firestore profile yet).

> **Phase 1 change:** removed the old "Full Name" field (it was collected but never used); added Confirm Password field + the three-rule validation block.

---

## 3. Onboarding

### ProfileInputScreen
**File:** `lib/screens/profile_input_screen.dart`

**Purpose:** Dual-mode 3-step wizard that collects all user body stats and fitness preferences.
- **Onboarding mode** (`ProfileInputScreen()`, `existing == null`) — first-run flow; writes a fresh `UserProfile` and lands the user on `HomeScreen`.
- **Edit mode** (`ProfileInputScreen(existing: profile)`) — launched from the Profile tab's "Edit Profile" button. `initState` prefills every field from `existing` (weight/height converted back to the user's unit system; DOB reconstructed from the stored age). Saving uses `existing.copyWith(...)` so `uid` and the accumulated `calorieAdjustment` survive, and pops back to the Profile screen instead of replacing the stack. The CTA reads "Save Changes" instead of "Get Started".

**Structure:** `PageView` with 3 pages navigated by Next/Back buttons; a progress bar of 3 segments at the top fills as the user advances.

---

#### Step 1 — About You
| Field | Widget | Notes |
|---|---|---|
| Unit system | Toggle chips (Metric / Imperial) | Changes weight/height labels live |
| Full name | `TextField` | Stored in `UserProfile.name` |
| Date of birth | Tap-to-open `DatePicker` tile | **Age auto-calculated** from DOB — no manual entry |
| Weight | `TextField` (number) | Stored in kg internally; converts on save if imperial |
| Height | `TextField` (number) | Stored in cm internally; converts on save if imperial |
| Gender | Toggle chips (Male / Female) | Only Male/Female — used for Mifflin-St Jeor BMR formula |
| Average hours slept | `Slider` 3–12 h | Drives `recoveryScore`; label shows live value |

---

#### Step 2 — Your Fitness
| Field | Widget | Notes |
|---|---|---|
| Fitness goal | Chip group | Weight Loss / Muscle Gain / Endurance / General Fitness |
| Experience level | Chip group | Beginner / Intermediate / Advanced |
| Workout location | Toggle chip | Home / Gym — drives equipment filter |
| Equipment available | Multi-chip (Home only) | Dumbbells, Kettlebells, Resistance Bands, Pull-up Bar, Bodyweight |
| Activity level | **Dropdown + "?" info** | Sedentary → Extra Active; drives `activityMultiplier` → TDEE → calorie goal |
| Workout days/week | 1–7 number chips | Exact number of training days placed in the 7-day schedule |
| Time per session | Chip group 30/45/60/90 min | Drives exercises-per-day in the greedy algorithm |
| Workout split | **10 selectable description cards** | Determines the weekly focus cycle (PPL, Bro Split, etc.) |

**"?" help-hint pattern:** every complex field has a small `Icons.help_outline` button beside its label. Tapping opens a styled bottom sheet listing each option with a plain-English description. Implemented via `_buildLabelWithHelp(title, Map<String,String> helpMap)`.

**Incompatibility validation:** `_splitDaysError()` checks whether `_workoutDays` meets the minimum required for `_workoutSplit`:
- Bro Split / Body Part Split → min 5 days
- PPL → min 3 days
- Upper/Lower / HIIT+Strength / Strength+Conditioning → min 2 days

Two feedback layers: a **live red banner** inside Step 2 that appears as soon as the user makes an impossible selection, and an **AlertDialog with a full explanation** that blocks "Next" until fixed.

---

#### Step 3 — Your Diet
| Field | Widget |
|---|---|
| Common restrictions | Multi-chip (Halal, Gluten-free, Vegan, Vegetarian, Dairy-free, Nut-free, Egg-free, Soy-free, Lactose-intolerant) |
| Diet styles | Multi-chip (Keto, Paleo, Low-carb, High-protein, Mediterranean, Diabetic-friendly, Pescatarian) |

All selected values are stored together in `UserProfile.dietaryRestrictions`. The meal service reads this list to **hard-constrain which recipe categories are fetched** (e.g. High-protein → only chicken/beef/seafood, never pasta).

---

**Save flow:** `_saveProfile()` builds the profile (`existing.copyWith(...)` in edit mode, a fresh `UserProfile(...)` in onboarding) and saves through `context.read<ProfileProvider>().save(profile)` — persisting to Firestore *and* updating the shared cache so every screen recomputes reactively. Onboarding then `pushAndRemoveUntil(HomeScreen)`; edit `Navigator.pop()`s.

**Connections:**
- `ProfileProvider.save` → `FirestoreService.saveUserProfile` writes `users/{uid}` + notifies listeners.
- Onboarding: `navigatorKey` sets `HomeScreen` as the stack base. Edit: pops back to the Profile tab (which watches `ProfileProvider`).
- `UserProfile.activityMultiplier` now reads `activityLevel` → flows into `tdee` → `calorieGoal` → `macroGoals` on the Profile and Progress screens.

> **Phase 1 change:** all 5 new fields (activityLevel, workoutDaysPerWeek, sessionMinutes, workoutSplit, avgHoursSlept) collected here for the first time. DOB picker added. "Other" gender option removed. "?" help pattern introduced. Split incompatibility guard added.

---

## 4. Main Shell — HomeScreen

**File:** `lib/screens/home_screen.dart`

**Purpose:** The persistent 5-tab shell. Owns the `BottomNavigationBar` and the global `plansScreenKey`. Loads `UserProfile` once on init and passes it down to child screens that need it.

**State:** `_currentIndex` (active tab), `_profile` (loaded once), `_isLoading`, `_lastBackPressTime` (for double-back-to-exit).

**Tabs:**

| Index | Screen | Key |
|---|---|---|
| 0 | `_HomeDashboard` | — |
| 1 | `PlansScreen` | `plansScreenKey` |
| 2 | _(centre FAB — no screen)_ | — |
| 3 | `ProgressScreen` | — |
| 4 | `ProfileScreen` | — |

**Centre FAB (index 2):** opens `_showAddSheet()` — a bottom sheet with three options:
- **Log Workout** → switches to Plans tab (`_currentIndex = 1`).
- **Log Meal** → `_showMealTypeSelector()` → `FoodLogScreen`.
- **Scan Barcode** → `_showMealTypeSelector(autoScan: true)` → `FoodLogScreen` with camera auto-launched.

**`plansScreenKey`:** A `GlobalKey<PlansScreenState>` defined at the top of this file. Other code can call `plansScreenKey.currentState?.switchToMealTab()` to programmatically switch the Plans screen to the Meal tab.

**Back-press behaviour:** First press on the home tab shows a "Press back again to exit" snackbar. Second press within 2 seconds exits the app.

**Connections:**
- Calls `ProfileProvider.load(uid)` in `initState`; `watch`es `ProfileProvider.profile` in `build` (no local profile state).
- Passes the watched profile + derived loading flag into `_HomeDashboard`; `ProfileScreen` reads `ProfileProvider` itself.
- Passes `onGoToPlans` callback to `_HomeDashboard`.

---

### _HomeDashboard (private widget inside HomeScreen)

Shown on tab 0. A scrollable dashboard with:
- **Greeting card** — "Good morning/afternoon/evening, {name}".
- **Calorie ring** — today's logged calories vs goal (from `FirestoreService.streamTodayFoodLogs`).
- **Workout card** — streams today's `WorkoutLog` via `FirestoreService.streamWorkoutLogForDate`; shows the day's exercises if a plan exists in `PlanProvider`.
- **Quick-action chips** — Log Food / View Plan / Nutrition.

---

## 5. Plans Tab — PlansScreen

**File:** `lib/screens/plans_screen.dart`

**Purpose:** The most complex screen. Shows the 7-day workout plan, runs the active workout flow (set-by-set with rest timers), generates and persists the AI plan, and renders the meal plan for the week.

**Structure:** Two-tab layout inside a `TabController` (length 2):
- **Tab 0 — Workout**
- **Tab 1 — Meal**

Switching tabs programmatically:
- Via route arguments `{'mealType': '<type>'}` — `didChangeDependencies` picks this up.
- Via `plansScreenKey.currentState?.switchToMealTab()` from `HomeScreen`.

---

### Workout Tab

**Plan generation — `_generate()`:**

1. Loads user profile from Firestore.
2. Computes the current ISO week ID via `FirestoreService.weekIdFor(now)`.
3. **Tries to load a persisted plan** for this week from `PlanProvider.loadWorkoutPlan(uid, weekId)`. If found → uses it (edits survive restarts).
4. If no persisted plan: fetches all exercises from `ExerciseDBService`, runs `AdaptationEngine.compute(...)` with last week's nutrition adherence, workout completion, and the user's `avgHoursSlept`, then calls `GreedyAlgorithm.generatePlan(...)`.
5. Saves the new plan via `PlanProvider.persistWorkoutPlan(uid, weekId)`.

**Plan shape:** `List<WorkoutDay>` — 7 entries, Mon–Sun. Days marked `isRest: true` show a rest card; training days show their exercises.

**Workout flow (set-by-set):**

| State variable | Meaning |
|---|---|
| `_activeExerciseIndex` | Index of the exercise currently being performed (−1 if not started) |
| `_activeSetNumber` | Which set the user is on (1-indexed) |
| `_inRest` | Whether the rest timer is running |
| `_restRemaining / _restTotal` | Countdown seconds |
| `_waitingForReady` | Showing the "Up Next / I'm Ready!" card between exercises |
| `_completedExercises` | Set of finished exercise indices |
| `_elapsedSeconds` | Total workout time (driven by a periodic `Timer`) |

When the user taps **Start Workout**: `_startWorkout()` sets `_activeExerciseIndex = 0`.

Each set completion: `_doneSet(we)` → if more sets remain, starts the rest countdown; when rest ends, moves to the next set. When the last set of the last exercise is done, `_autoComplete()` is called → `_saveWorkoutLog()` → `FirestoreService.saveWorkoutLog()`.

**Edit mode:**

Toggle the "Edit session" button (visible before a workout starts). While editing:
- Each exercise card gets a **× delete button** (top-right corner) → `PlanProvider.removeExercise`.
- An **"Edit params"** button (bottom-right) → opens a bottom sheet with ±steppers for sets and rest seconds, and a text field for reps/duration → `PlanProvider.updateExerciseParams`.
- An **"Add exercise"** button at the bottom of the day → `_showExercisePicker()` — a `DraggableScrollableSheet` listing all exercises filtered by that day's muscle focus → `PlanProvider.addExercise`.
- All edits call `PlanProvider.persistWorkoutPlan` immediately so they're durable.

**State:**
`_plan`, `_profile`, `_isLoading`, `_error`, `_selectedDay`, `_todayLog`, `_weekDone`, `_editMode`, `_allExercises` (cached from last generate for the picker), meal state (`_pending`, `_edamamRecipes`, `_loggedFoods`, `_loadingMeals`).

**Connections:**
- `PlanProvider` — in-memory plan, persist/load, edit methods.
- `FirestoreService` — `saveWeeklyWorkoutPlan`, `loadWeeklyWorkoutPlan`, `saveWorkoutLog`, `getWorkoutsCompletedCount`, `getWorkoutLogsForDateRange`.
- `ExerciseDBService` — fetches all exercises (Firestore-cached 30 days).
- `GreedyAlgorithm` — generates the plan.
- `AdaptationEngine` — computes `difficultyBias` and `calorieBiasKcal`.
- `GeneticAlgorithm` — generates meals from ingredients (see Meal Tab below).

---

### Meal Tab (inside PlansScreen)

Shows generated meal cards for Breakfast, Lunch, Dinner, Snack. Each card can be:
- **Generated** via `_generateMeal(mealType)` or **all at once** via `_generateAll()` — both run the **Genetic Algorithm** over the USDA-seeded ingredient pool.
- **Logged** via `_logPendingMeal(mealType)` → `PlanProvider.setMeal(saveToFirestore: true)` → `_saveMealToFirestore` writes each ingredient as its own `FoodItem` (`barcode: 'ai_generated'`).
- **Viewed** in `RecipeScreen`.

Meal generation flow (Genetic Algorithm — `_generateMeal` / `_generateAll`):
1. `_allIngredients` is loaded once via `FirestoreService.getIngredients()` (reads the `ingredients` collection; seed it with the Profile → "Seed Ingredients" button, gated by `kShowSeedTools`). An empty pool surfaces a "not seeded" SnackBar.
2. `_runGeneticPlan()` calls `GeneticAlgorithm().generatePlan(allIngredients, profile, cuisine: _cuisine)` and takes one optimized `DayMealPlan` (random day → variety on regenerate). The GA filters the pool by the selected cuisine (`any`/`filipino`/`western`/`asian`) + dietary restrictions and evolves ingredient combinations against a calorie/macro fitness function.
3. The chosen slot's `Meal` is `scaleToCalories(_mealTargetCals(...))` and set as the pending meal; the card renders the ingredient list (name + grams + per-item kcal) and a macro summary row.
4. `_generateAll()` runs the GA **once** and fills every not-already-logged slot from that single day so the day's macros are jointly optimized.

Calorie split: Breakfast 25%, Lunch 35%, Dinner 30%, Snack 10% of `profile.calorieGoal`.

---

## 6. Nutrition Tab — NutritionScreen

**File:** `lib/screens/nutrition_screen.dart`

**Purpose:** Shows logged food for any selected date across two sub-tabs.

**State:** `_selectedDate` (defaults to today).

**Sub-tabs:**
- **Calories** — pulls `FoodItem` logs for `_selectedDate` from Firestore; shows total calories vs goal, macro bar chart breakdown (protein/carbs/fat), and a per-meal expandable list.
- **Nutrients** — shows the 14 vitamin/mineral fields aggregated from the same day's logs.

**Date navigation:** chevron arrows + an `IconButton` opening `showDatePicker`. The "Today" label appears when the selected date is the current day.

**Connections:**
- `FirestoreService.getFoodLogsForDate(uid, date)` — queries `food_logs` by `loggedAt` timestamp range.
- Both sub-tabs `watch` `ProfileProvider.profile` for the calorie goal / macro targets (falling back to literals when null) instead of fetching the profile per build.
- Tapping a food item → details sheet (inline, not a separate route).

---

## 7. Progress Tab — ProgressScreen

**File:** `lib/screens/progress_screen.dart`

**Purpose:** Aggregates and visualises the current week's performance. Driven entirely by `ProgressProvider`.

**Load trigger:** `ProgressProvider.loadAll(uid, profile: context.read<ProfileProvider>().profile)` called in `initState` and again on pull-to-refresh — the shared profile is passed in so no redundant profile read is fired.

**Sections:**

| Widget | What it shows |
|---|---|
| `_TodaySnapshot` | Calorie ring + protein bar for today |
| `_WeeklyAchievements` | Workout streak, calorie adherence %, protein consistency %, weekly completion |
| `_CalorieTrendChart` | `fl_chart` `BarChart` of daily calories Mon–Sun vs goal line |
| `_MacroTrendChart` | Stacked bar chart of protein/carbs/fat per day |
| `_WeightSection` | Latest weight, weight change from first log, line chart of `WeightLog` entries; inline weight logging |
| `_MilestonesSection` | Badges / milestones unlocked based on streaks and adherence |

**Key computed values from `ProgressProvider`:**

| Getter | Source |
|---|---|
| `calorieGoal` | `profile.calorieGoal` (derived from `activityLevel` → TDEE) |
| `proteinGoal` | `profile.macroGoals['protein']` |
| `calorieAdherence` | avg weekly calories / `calorieGoal` × 100 |
| `workoutStreak` | consecutive days with a `WorkoutLog` (up to 30 days back) |
| `proteinConsistency` | % of week days where protein ≥ 90% of goal |
| `plannedWorkoutDays` | `profile.workoutDaysPerWeek` (real input, not guessed) |
| `weeklyWorkoutCompletion` | completed logs / `plannedWorkoutDays`, clamped 0–1 |

**Connections:**
- `ProgressProvider.loadAll` — fires 5 parallel Firestore queries (today's logs, weekly calorie totals, workout logs, weight logs, weekly food logs); the profile is taken from the passed-in `ProfileProvider` value, or fetched only if none was passed.
- **Weight sync:** the "Log Today's Weight" Save handler calls `ProfileProvider.updateWeight(kg)` (recomputes BMR/TDEE/`calorieGoal`/BMI → Home & Nutrition rings update reactively) **then** `ProgressProvider.logWeight(uid, kg)` (saves the `weight_logs` entry + reloads Progress so its own BMI/TDEE card reflects the new weight).
- `ProgressProvider` is also the source of `calorieAdherence` and `weeklyWorkoutCompletion` fed into `AdaptationEngine` on the next plan generation.

> **Phase 2 change:** `plannedWorkoutDays` and `weeklyWorkoutCompletion` now use `profile.workoutDaysPerWeek` as the real denominator instead of a hardcoded estimate.

---

## 8. Profile Tab — ProfileScreen

**File:** `lib/screens/profile_screen.dart`

**Purpose:** Displays the user's stats and calculated targets, with an **Edit Profile** button that reopens `ProfileInputScreen` in edit mode.

**Sections:**
- Avatar + name + email.
- **Daily Targets card** — calorie goal (big number), macro targets (protein/carbs/fat/fiber), BMR, TDEE, BMI.
- **Biometrics card** — age, weight (unit-aware), height, gender, unit system, avg sleep.
- **Fitness card** — goal, experience level, activity level, location, workout split, days/week, session length, equipment.
- **Diet card** — dietary restrictions, sugar limit, sodium limit.
- **Edit Profile** button → `Navigator.push(ProfileInputScreen(existing: profile))` (disabled while the profile is null).
- **Sign Out** button.

**Connections:**
- `watch`es `ProfileProvider.profile`, so it refreshes automatically when an edit saves and pops back.
- All displayed numbers (`calorieGoal`, `tdee`, `bmr`, `bmiDisplay`, `macroGoals`) are computed getters on `UserProfile` — they reflect the real `activityLevel`, the latest synced `weight`, and the accumulated `calorieAdjustment`.
- Sign out → `AuthService.signOut()` → `navigatorKey` routes to `LoginScreen`.

> **Phase 1 change:** Biometrics card now shows `avgHoursSlept`; Fitness card now shows `activityLevel`, `workoutSplit`, `workoutDaysPerWeek`, `sessionMinutes`.

---

## 9. Supporting Screens

### FoodLogScreen
**File:** `lib/screens/food_log_screen.dart`

**Purpose:** Lets the user log food for a specific meal type. Three entry paths:
1. **Text search** — queries USDA FoodData Central API (`/foods/search`) by keyword; returns `_USDAFoodItem` list with full macro data.
2. **Barcode scan** — if `autoScan: true` (or tapping the scan icon), launches `BarcodeScanScreen` → scans EAN/UPC → queries `OpenFoodFactsService` by barcode → pre-fills the food detail form.
3. **History** — shows the user's last 20 unique entries for this meal type (last 30 days) for quick re-logging.

**Save flow:** selecting any food item → "Add" button → `FirestoreService.logFoodItem(FoodItem)` → `users/{uid}/food_logs/{logId}`.

**State:** `_results` (USDA search), `_history`, `_isLoading`, `_hasSearched`, `_loggingIds` (tracks in-flight logs to disable buttons).

**Connections:**
- `FirestoreService.logFoodItem`, `getFoodLogsForDateRange`.
- `OpenFoodFactsService` — barcode lookup.
- USDA FDC API — text search.
- `BarcodeScanScreen` — camera, returns barcode string via `Navigator.pop`.
- Launched from: `HomeScreen._showMealTypeSelector`, `NutritionScreen` (via add button).

---

### BarcodeScanScreen
**File:** `lib/screens/barcode_scan_screen.dart`

**Purpose:** Thin camera wrapper. Renders a full-screen `MobileScanner` with a custom overlay frame. On the first valid barcode detection, calls `Navigator.pop(context, barcode.rawValue)` — the barcode string is returned to the caller (`FoodLogScreen`).

**State:** `_isProcessing` — prevents double-firing on rapid detection.

**Connections:**
- Called by `FoodLogScreen._scanBarcode()` via `Navigator.push` → `await` the result.
- Uses `mobile_scanner` package (no API key).

---

### RecipeScreen
**File:** `lib/screens/recipe_screen.dart`

**Purpose:** Shows step-by-step cooking instructions for a generated meal, plus the meal's ingredient list and nutritional summary. The GA meal's ingredients (with gram portions) are sent to **OpenAI** (`OpenAIService.generateRecipe`) which writes the recipe — the "Transformer" natural-language layer from the capstone objective.

**State:** `_recipe`, `_isLoading`, `_error`, `_isSaved`, `_addedExtras`.

**Key functions:**
- `_loadSavedOrFetch()` — checks Firestore for a previously saved recipe for this meal type before generating, to avoid redundant API calls.
- `_fetchRecipe()` — sends the meal's ingredients to `OpenAIService.generateRecipe`, maps the returned steps into the existing `_RecipeResult` (no image/missing-ingredients). The refresh button regenerates (OpenAI temperature gives variety).
- Save button → saves the recipe's ingredients as `FoodItem` entries to `food_logs` via `FirestoreService`.

**Connections:**
- `OpenAIService` (`lib/services/openai_service.dart`) — generates the recipe text (hardcoded key constant; needs OpenAI account credits).
- `FirestoreService.logFoodItem` — saves individual ingredients.
- Launched from: `PlansScreen` Meal tab → recipe card tap.

---

## 10. Providers

### ProfileProvider
**File:** `lib/providers/profile_provider.dart`

**Purpose:** Single reactive source of truth for the current user's `UserProfile`. Replaces the six independent profile fetches that previously lived in Home, Nutrition (×2), Progress, and the two Plans tabs — so a profile edit, a weight log, or a weekly calorie adaptation propagates to every screen with no restart.

| Method | What it does |
|---|---|
| `load(uid)` | Fetches once via `FirestoreService.getUserProfile` and caches; **no-op if already loaded** — safe to call from any `initState` |
| `refresh(uid)` | Force re-fetch, replacing the cache |
| `save(p)` | `saveUserProfile(p)` + update cache + `notifyListeners` (used by onboarding and the edit screen) |
| `updateWeight(kg)` | `save(profile.copyWith(weight: kg))` — called by the Progress weight-log Save handler |
| `applyCalorieAdjustment(biasKcal)` | `save(profile.copyWith(calorieAdjustment: (current + biasKcal).clamp(-500, 500)))` — called once per new `weekId` from `PlansScreen._generate()` |

`HomeScreen` calls `load(uid)` in `initState`; Home, Nutrition, Plans, and Profile `watch`/`read` it instead of querying Firestore.

---

### PlanProvider
**File:** `lib/providers/plan_provider.dart`

**Purpose:** In-memory + Firestore-backed store for the current week's workout plan and today's meal plan. The central coordinator between the greedy algorithm and the Plans screen.

**Workout plan state:** `_workoutPlan: List<WorkoutDay>` — 7 days for the current week.

| Method | What it does |
|---|---|
| `setWorkoutPlan(plan)` | Stores the plan in memory, notifies listeners |
| `persistWorkoutPlan(uid, weekId)` | Serialises the plan and writes to `users/{uid}/workout_plans/{weekId}` |
| `loadWorkoutPlan(uid, weekId)` | Loads from Firestore; returns `true` if found, populates `_workoutPlan` |
| `replaceExercise(uid, weekId, dayIdx, exIdx, newExercise)` | Swaps one exercise, persists immediately |
| `removeExercise(uid, weekId, dayIdx, exIdx)` | Removes an exercise, persists immediately |
| `addExercise(uid, weekId, dayIdx, workoutExercise)` | Appends an exercise, persists immediately |
| `updateExerciseParams(uid, weekId, dayIdx, exIdx, {sets, reps, restSeconds})` | Updates volume params, persists immediately |

**Meal plan state:** `_breakfast / _lunch / _dinner / _snack: Meal?` — in-memory only (not persisted to Firestore until `saveToFirestore: true` is passed to `setMeal`).

**Two save paths for meals:**
1. `setMeal(mealType, meal, saveToFirestore: true)` → `_saveMealToFirestore` — saves each `MealIngredient` as a separate `FoodItem` (no micronutrients).
2. `logEdamamRecipe(recipe, mealType)` → saves the whole `EdamamRecipe` as a single `FoodItem` with full macro + 14 micro fields. This is the path used by the Plans screen meal generation.

`_clearTodayGeneratedMeals(uid)` — deletes all today's `food_logs` where `barcode == 'ai_generated'` before saving a regenerated plan.

**Computed getters:** `todayCalories`, `todayProtein`, `todayCarbs`, `todayFat` — summed across all four meals.

**`todayWorkout`** — returns the `WorkoutDay` for today's weekday index (Monday = 0).

---

### ProgressProvider
**File:** `lib/providers/progress_provider.dart`

**Purpose:** Aggregates all weekly fitness data for the Progress screen and feeds the `AdaptationEngine`.

**`loadAll(userId, {UserProfile? profile})`** — uses the passed-in `profile` (from `ProfileProvider`) when provided, else fetches it; runs 5 parallel Firestore queries for the rest:
1. `getFoodLogsForDate(today)` — today's logged foods.
2. `getDailyCalorieTotals(monday)` — daily calorie sums for the week.
3. `getWorkoutLogsForDateRange(monday, +7)` — this week's completed workouts.
4. `getWeightLogs` — all weight entries (for the weight chart).
5. `getFoodLogsForDateRange(monday, +7)` — week's food logs for macro breakdown.

`logWeight(uid, kg)` saves a `weight_logs` entry then calls `loadAll(uid)` (no profile passed → re-fetches, picking up any weight just synced via `ProfileProvider.updateWeight`).

**Key computed getters:**

| Getter | Formula |
|---|---|
| `calorieGoal` | `profile.calorieGoal` |
| `proteinGoal` | `profile.macroGoals['protein']` |
| `calorieAdherence` | avg(weeklyCalories.values) / calorieGoal × 100 |
| `workoutStreak` | consecutive days with a workout log (30-day lookback) |
| `proteinConsistency` | % of week-days where protein ≥ 90% of goal |
| `plannedWorkoutDays` | `profile.workoutDaysPerWeek` ← real user input |
| `weeklyWorkoutCompletion` | `weekWorkoutLogs.length / plannedWorkoutDays` (clamped 0–1) |

`weeklyWorkoutCompletion` is passed to `AdaptationEngine.compute()` when `_generate()` runs in `PlansScreen`.

---

### ThemeProvider
**File:** `lib/providers/theme_provider.dart`

**Purpose:** Toggles between dark and light `ThemeMode`. Registered in `MultiProvider` in `main.dart`; consumed by the root `MaterialApp`.

---

## 11. Algorithms

### GreedyAlgorithm
**File:** `lib/algorithms/greedy_algorithm.dart`

**Purpose:** Generates a 7-day `List<WorkoutDay>` from a `List<Exercise>` + `UserProfile`. Pure Dart — no Flutter or Firebase.

**Entry point:** `generatePlan(allExercises, profile, difficultyBias)`

**Pipeline:**

```
allExercises
  │  Filter: goal match + location match + equipment match
  ↓
filtered exercises
  │
  ├─ _getSchedule(profile)
  │    Uses: workoutSplit → focus cycle sequence
  │           workoutDaysPerWeek → how many training days to place
  │           → 7-element list e.g. ['Full Body', 'Rest', 'Full Body', ...]
  │
  └─ For each training day:
       _selectExercisesForDay(filtered, targetMuscles, profile, muscleHitCount, count)
         │  Score each exercise: goal+30, location+30, equipment+20, difficulty+10,
         │                        target muscle bonus +25, muscle-repetition penalty −15/hit
         │  Difficulty filter: matches level (+ one tier up if difficultyBias='up')
         │  Take top N unique by score
         └─ Wrap each in WorkoutExercise(sets, reps, restSeconds)
```

**Volume decisions — all profile-driven:**

| Decision | Driver |
|---|---|
| Training day positions (which of Mon–Sun) | `workoutDaysPerWeek` (evenly spaced) |
| Focus per day | `workoutSplit` → cycles through split's sequence |
| Exercises per day | `sessionMinutes` (30→3, 45→5, 60→6, 90→8) ± experience ± `recoveryScore` |
| Sets | Goal + experience; −1 if `recoveryScore < 0.8` |
| Reps / duration | Goal + split style (HIIT/Circuit → timed; Muscle Gain → 8–12 heavy) |
| Rest seconds | Goal + split style (HIIT → 30 s; Muscle Gain → 90 s) |

**`difficultyBias`** (from `AdaptationEngine`):
- `'up'` — allows exercises one tier above the user's level.
- `'down'` — converts the last training day to Rest.
- `'same'` — no change.

**Serialisation:** `WorkoutDay.toMap()`/`fromMap()` and `WorkoutExercise.toMap()`/`fromMap()` — used for Firestore persistence.

---

### AdaptationEngine
**File:** `lib/algorithms/adaptation_engine.dart`

**Purpose:** Pure-Dart engine that analyses last week's data and returns adjustment signals for this week's plan.

**Inputs:**

| Parameter | Source in PlansScreen |
|---|---|
| `lastWeekCalorieAdherence` | `avgCalories / profile.calorieGoal × 100` |
| `lastWeekWorkoutCompletion` | `completedWorkouts / profile.workoutDaysPerWeek` |
| `currentExperienceLevel` | `profile.experienceLevel` |
| `avgHoursSlept` | `profile.avgHoursSlept` |

**Output:** `AdaptationResult { calorieBiasKcal, difficultyBias, notes }`

**Logic:**

```
Calorie:
  adherence < 85%  → calorieBias = +100 kcal
  adherence > 110% → calorieBias = −100 kcal

Difficulty:
  sleep < 6.5 h → difficultyBias = 'same' (recovery override — no step-up even if workouts were great)
  completion ≥ 80% AND not Advanced → 'up'
  completion < 50% → 'down'
  otherwise → 'same'
```

`difficultyBias` is passed directly to `GreedyAlgorithm.generatePlan` (which has no `calorieBiasKcal` parameter). `calorieBiasKcal` is applied to the calorie goal via `ProfileProvider.applyCalorieAdjustment` in `_generate()`'s fresh-generation branch (clamped to ±500, once per new `weekId`) — it is **not** passed into the workout generator.

---

## 12. Services

| Service | File | Purpose |
|---|---|---|
| `AuthService` | `lib/services/auth_service.dart` | Firebase Auth wrapper: `signIn`, `register`, `signOut`, `authStateChanges`, `currentUser` |
| `FirestoreService` | `lib/services/firestore_service.dart` | All Firestore reads/writes. Plain class — instantiate anywhere with `FirestoreService()` |
| `ExerciseDBService` | `lib/services/exercise_db_service.dart` | Fetches from `oss.exercisedb.dev` (AscendAPI free tier, cursor-paginated 25/page; GIFs on `static.exercisedb.dev`); caches ~1 500 exercises in Firestore for 30 days |
| ~~`MealService`~~ | `lib/services/meal_service.dart` | **No longer used** — meal generation now runs the `GeneticAlgorithm` over USDA ingredients. File is orphaned; safe to delete. |
| `EdamamService` | `lib/services/edamam_service.dart` | Edamam Meal Planner integration; kept for future recipe features |
| `OpenFoodFactsService` | `lib/services/openfoodfacts_service.dart` | Barcode → product lookup |

### FirestoreService — key methods added in Phase 2

| Method | Collection path | Purpose |
|---|---|---|
| `saveWeeklyWorkoutPlan(uid, weekId, plan)` | `users/{uid}/workout_plans/{weekId}` | Serialises full `List<WorkoutDay>` to Firestore |
| `loadWeeklyWorkoutPlan(uid, weekId)` | `users/{uid}/workout_plans/{weekId}` | Deserialises back to `List<WorkoutDay>`; returns `null` if not found |
| `weekIdFor(date)` (static) | — | Returns ISO-week string like `week_2025_23` |
| `getIngredients()` | `ingredients/{id}` | Reads USDA ingredient pool for the Genetic Algorithm; in-memory cached per session |

### FirestoreService.getIngredients()

Reads the pre-seeded `ingredients` Firestore collection and maps each doc to `MealIngredient` via `MealIngredient.fromMap`. The result is cached in a static field for the app session. The collection is populated by running `SeedData.seedIngredients()` (Profile screen → "Seed Ingredients" button, only visible when `kShowSeedTools = true` in `lib/data/seed_data.dart`).

`scaleToCalories(recipe, targetCals)` — proportionally scales every macro and micronutrient so the returned recipe matches the per-meal calorie target. Physically models a larger portion, which also brings protein up proportionally.

---

## 13. Data Model Quick-Reference

### UserProfile
| Field | Type | Drives |
|---|---|---|
| `activityLevel` | String | `activityMultiplier` → `tdee` → `calorieGoal` → `macroGoals` |
| `workoutDaysPerWeek` | int | `GreedyAlgorithm` schedule + `ProgressProvider` completion denominator |
| `sessionMinutes` | int | `_exercisesPerDay` in `GreedyAlgorithm` |
| `workoutSplit` | String | `_getSchedule` focus cycle + reps/rest style |
| `avgHoursSlept` | double | `recoveryScore` → volume/sets reduction; `AdaptationEngine` difficulty gate |
| `recoveryScore` | double (getter) | `< 0.8` → −1 exercise/day, −1 set |
| `activityMultiplier` | double (getter) | Maps `activityLevel` to Harris-Benedict multiplier |
| `weight` | double (kg) | BMR → TDEE → `calorieGoal` → `macroGoals`, and BMI; synced by `ProfileProvider.updateWeight` when a weight is logged |
| `calorieAdjustment` | int | Added to the goal-derived base in `calorieGoal` (then clamped to 1200 floor); fed by `AdaptationEngine.calorieBiasKcal`, clamped to ±500 |

### Firestore Collections
```
users/{uid}
  food_logs/{logId}           FoodItem (full macro + 14 micro)
  workout_logs/{logId}        WorkoutLog (completed session)
  workout_plans/{weekId}      Serialised List<WorkoutDay> (persisted editable plan)
  weight_logs/{logId}         WeightLog
  meal_plans/{planId}         (legacy stub, not fully wired)
  weekly_summaries/{weekId}   (planned, not yet used)

exercises/{exerciseId}        ExerciseDB cache (30-day TTL)
```

---

## 14. Change Log by Phase

### Phase 1 — User Profiling

**Goal:** Collect richer inputs; fix registration; accuracy of calorie math.

| File | Change |
|---|---|
| `register_screen.dart` | Removed Full Name field; added Confirm Password + 3-rule validation |
| `user_profile.dart` | +5 fields (activityLevel, workoutDaysPerWeek, sessionMinutes, workoutSplit, avgHoursSlept); `activityMultiplier` now reads `activityLevel`; added `recoveryScore` getter |
| `profile_input_screen.dart` | DOB picker (auto-calculates age); avg sleep slider (Step 1); activity dropdown + "?" hint, days/week picker, session chips, 10 split cards (Step 2); `_buildLabelWithHelp` reusable helper; split/days incompatibility validation (live banner + AlertDialog); removed "Other" gender |
| `profile_screen.dart` | Displays new fields in Biometrics and Fitness cards |

### Phase 2 — Connect Profiling to Engine

**Goal:** Wire every Phase 1 field into the algorithm, persistence, and progress logic.

| File | Change |
|---|---|
| `greedy_algorithm.dart` | `_getSchedule` replaced with split+days-driven version (`_splitFocusSequence` + even spread); `_exercisesPerDay` uses `sessionMinutes` + `recoveryScore`; `_getSets` uses `recoveryScore`; `_getReps`/`_getRestSeconds` aware of split style; `WorkoutDay`/`WorkoutExercise` gained `toMap()`/`fromMap()` |
| `adaptation_engine.dart` | New `avgHoursSlept` param; sleep < 6.5 h blocks difficulty step-up |
| `firestore_service.dart` | `saveWeeklyWorkoutPlan` + `loadWeeklyWorkoutPlan` (typed) |
| `plan_provider.dart` | `persistWorkoutPlan`, `loadWorkoutPlan`, `replaceExercise`, `removeExercise`, `addExercise`, `updateExerciseParams` |
| `plans_screen.dart` | `_generate()` loads persisted plan first; caches `_allExercises` for picker; edit-mode toggle + delete/params-editor/add-exercise UI |
| `progress_provider.dart` | `plannedWorkoutDays` + `weeklyWorkoutCompletion` use real `profile.workoutDaysPerWeek` |
| `meal_service.dart` | `_categoriesForMealType` handles all 10 diet styles as hard constraints; `scaleToCalories`; `_score` doubles protein weight when target > 30 g |

### Fixes (between phases)

| File | Fix |
|---|---|
| `profile_input_screen.dart` | DOB picker instead of age text field |
| `profile_input_screen.dart` | Split/days incompatibility guard (live warning + dialog) |
| `profile_input_screen.dart` | Removed "Other" gender (irrelevant to BMR formula) |
| `meal_service.dart` | High-protein and all other diet styles now hard-constrain category selection |
| `plans_screen.dart` | `scaleToCalories` applied after `pickBest` so meals hit calorie targets and protein scales proportionally |

### Post-Phase 2 fixes

| File | Fix |
|---|---|
| `plans_screen.dart` | **GIF display** — treat empty-string `gifUrl` same as null; add `gaplessPlayback: true` (required for GIF animation in Flutter); add `User-Agent` header; add per-exercise `ValueKey` to prevent stale widget state. Applied to exercise card, ready card, and GIF dialog. |
| `plans_screen.dart` | **Edit 50% cap** — `_editModeOriginalCount` captured on edit entry; delete button checks `currentCount > ceil(originalCount / 2)` before allowing removal; SnackBar explains the limit. |
| `plans_screen.dart` | **Done-editing guard** — `_toggleEditMode` blocks exit if 0 exercises remain; if exercises were removed, an `AlertDialog` asks "Fill the gap" (algo adds matching exercises from the cached pool) or "Leave shorter" (triggers volume-debt penalty). |
| `plans_screen.dart` | **Volume-debt penalty** — `_applyVolumeDebt(n)` adds 1 extra exercise to each of the next `n` (max 3) upcoming workout days, compensating for today's skipped volume. |
| `plans_screen.dart` | **Empty-day Start guard** — Start Workout button only shown when `day.exercises.isNotEmpty`; `_startWorkout()` has a hard guard that shows a SnackBar and aborts if the day is empty. |

### Exercise cache & corrupt plan fixes (post-Phase 2, round 2)

| File | Fix | Root cause |
|---|---|---|
| `plans_screen.dart` | **Always fetch exercises** — `ExerciseDBService().getExercises()` moved to run before the persisted-plan check in `_generate()`, so `_allExercises` is populated on both the load-from-Firestore and generate-fresh paths. | `_allExercises` was only set in the non-persisted branch; exercise picker always showed "No matching exercises found" when a plan was loaded from Firestore. |
| `plans_screen.dart` | **Background exercise fetch in `initState`** — when the in-memory plan is already present (hot-restart), a background `getExercises().then(...)` populates `_allExercises` without blocking the UI. | Same root cause, on the `initState` path. |
| `plans_screen.dart` | **Force-regenerate** — new `_forceRegenerate()` method: deletes the Firestore plan doc, clears the in-memory plan, then calls `_generate()`. The refresh `↺` button now calls this instead of `_generate()` directly. | Refresh button re-called `_generate()` which found the broken (0-exercise) Firestore plan and loaded it again — no way to escape. |
| `plan_provider.dart` | **Load validation** — `loadWorkoutPlan` now rejects any saved plan where every training day has 0 exercises (returns `false`, triggering fresh generation). | A 7-day plan with 0 exercises passes the `saved.isEmpty` check (list length = 7); the broken plan would be loaded and displayed forever. |
| `plan_provider.dart` | **Persist guard** — `persistWorkoutPlan` now checks `any(d => !isRest && exercises.isNotEmpty)` before writing to Firestore. | Broken plans (all days empty) were re-persisted, perpetuating the corrupt state. |
| `plan_provider.dart` | **`clearAndDeleteWorkoutPlan(uid, weekId)`** — new method that clears `_workoutPlan = []` in memory and deletes the Firestore document. Used by force-regenerate. | No API existed to escape a persisted plan. |
| `firestore_service.dart` | **`deleteWeeklyWorkoutPlan(uid, weekId)`** — new method, deletes `users/{uid}/workout_plans/{weekId}`. | Supporting the force-regenerate flow. |

### Phase 3 — Central profile, weight sync, calorie adaptation, edit screen

**Goal:** Make `UserProfile` a single reactive source of truth; let weight and weekly adaptation feed back into the calorie goal; let users edit their profile after onboarding.

| File | Change |
|---|---|
| `user_profile.dart` | +`calorieAdjustment` field (default 0; in `toMap`/`fromMap`); `calorieGoal` getter now adds it to a goal-derived base then clamps to `[1200, 99999]`; added full `copyWith(...)` |
| `profile_provider.dart` | **New** `ProfileProvider` — `load`/`refresh`/`save`/`updateWeight`/`applyCalorieAdjustment`; registered in `main.dart` |
| `home_screen.dart` | `load(uid)` in `initState`, `watch`es provider in `build`; removed local `_profile`/`_isLoading`/`_loadProfile` |
| `nutrition_screen.dart` | Both tabs `watch` the provider; deleted `_getUserGoals`/`_getUserMacroGoals` `FutureBuilder`s |
| `plans_screen.dart` | `_WorkoutTab._generate` + `_MealTab._loadProfile` read the provider; `_generate` applies `applyCalorieAdjustment(adaptation.calorieBiasKcal)` once per new `weekId` |
| `progress_provider.dart` | `loadAll(uid, {UserProfile? profile})` — uses the passed profile or fetches |
| `progress_screen.dart` | Passes the shared profile into `loadAll`; weight Save handler calls `updateWeight(kg)` + `logWeight(uid, kg)` |
| `profile_input_screen.dart` | Dual-mode (`existing` param): prefill in `initState`, `copyWith` on save, pop vs `pushAndRemoveUntil`, "Save Changes" CTA; saves via `ProfileProvider.save` |
| `profile_screen.dart` | `watch`es the provider; added **Edit Profile** button → `ProfileInputScreen(existing: profile)` |
