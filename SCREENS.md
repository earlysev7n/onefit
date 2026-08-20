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
   - [SettingsScreen](#settingsscreen)
   - [WeeklyReviewScreen](#weeklyreviewscreen--weekly-adaptive-report)
10. [Providers](#10-providers)
    - [ProfileProvider](#profileprovider)
    - [PlanProvider](#planprovider)
    - [ProgressProvider](#progressprovider)
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

**Step 1 required-field validation:** `_validateStep1()` blocks **Next** until name (non-empty), DOB (selected), weight (valid, ~30–300 kg) and height (valid, ~100–250 cm) are all provided. Errors render inline (red `errorText` under each field / red border + helper text under the DOB tile) and clear live on edit. This guards the nutrition engine — without it `_dob == null` yields `age == 0`, corrupting BMR/TDEE/`calorieGoal`.

---

#### Step 2 — Your Fitness
| Field | Widget | Notes |
|---|---|---|
| Fitness goal | Chip group | Weight Loss / Muscle Gain / Endurance / General Fitness. Changing it re-seeds **both** the Exercise Preference order **and** the Training Focus default. |
| Exercise preference | **Drag-to-rank list (2 items) + "?" info** | Reorderable Compound / Isolation ranking — the **only** selection-relevant type preference. The order (top = preferred) is a small tie-breaker: preferred type +2, other +1 (`_exerciseTypePoints`), deliberately far below the +50 focus / −25/−15 balance anchors. No point badges — the order alone is the signal. Stored as the 2-item Compound/Isolation order in `UserProfile.goalPriorities` (legacy 5-item lists still read fine); `_scoreExercise` reads only the Compound-vs-Isolation order. Heavy Lift / High Rep / Full Body are **no longer** ranked here (Heavy/High moved to Training Focus; Full Body is workout coverage). |
| Training focus | **3-way selector (Heavy Lift / Balanced / High Rep) + "?" info** | The **prescription** bias — decides reps/rest for the SELECTED exercises, never which are picked. Saved to `UserProfile.trainingFocus` (`'heavy'|'balanced'|'high'`); read by `_getReps`/`_getRestSeconds` as focus × goal × per-exercise role. Seeded from the goal default (`effectiveTrainingFocus`: Weight Loss/Endurance → high, Muscle Gain/General → balanced) but user-overridable (Weight Loss + Heavy Lift is valid). Legacy profiles (empty) fall back to the goal default, reproducing the old goal-only reps. |
| Experience level | Chip group | Beginner / Intermediate / Advanced |
| Workout location | Toggle chip | Home / Gym — drives equipment filter |
| Equipment available | Multi-chip (Home only) | Bodyweight (locked/always-on), Dumbbells, Kettlebells, Resistance Bands, Pull-up Bar, Barbell, Bench, Home Gym. Bodyweight can't be deselected — it's the guaranteed baseline and is always saved (`{'Bodyweight', ...selected}`). Selecting **Home Gym** (= squat/power rack) auto-adds Barbell + Bench. Gym saves `[]` (all equipment assumed). The rack flag (`Home Gym`) is what unlocks barbell squat/bench-press; a bare Barbell chip only unlocks floor-start barbell lifts (deadlift/row/OHP). |
| Activity level | **Dropdown + "?" info** | Sedentary → Extra Active; drives `activityMultiplier` → TDEE → calorie goal |
| Workout days/week | 1–7 number chips | Exact number of training days placed in the 7-day schedule |
| Time per session | Chip group 30/45/60/90 min + "?" info | Drives **how many** exercises per day (`_fitExerciseCount`) only — it does **not** affect which exercises are picked (that's Exercise Preference + Experience). The count budget uses focus-independent reps/rest, so changing Training Focus never changes the exercise count. |
| Workout split | **5 selectable description cards** | Full Body, Upper/Lower, PPL, Functional, Strength + Conditioning — determines the weekly focus cycle. (Reduced from 10; profiles holding a removed split fall back to Full Body on edit/generation.) |
| Physical limitations | **Affected-area toggle chips** | 10 areas from `kPhysicalLimitations` (Asthma, High Blood Pressure, Shoulder/Knee/Lower Back/Wrist/Elbow/Hip/Ankle/Neck Pain). Tapping a chip simply toggles the area on/off (no sheet, no per-movement checklist). Selecting an area makes the generator hard-exclude its **full mapping** (auto-block set + all mapped movements) via `exerciseBlockedByLimitations(e, physicalLimitations)` in `isEligibleForUser`. It's a broad, safe exclusion; the user can still add a specific limited move back via the **Plans exercise picker's "Add Anyway"** warning. `avoidedMovements` is vestigial (written as `[]`). A muted disclaimer ("not medical advice") sits under the chips. Empty by default → no filtering. |

**"?" help-hint pattern:** every complex field has a small `Icons.help_outline` button beside its label. Tapping opens a styled bottom sheet listing each option with a plain-English description. Implemented via `_buildLabelWithHelp(title, Map<String,String> helpMap)`.

**Incompatibility validation:** `_splitDaysError()` checks whether `_workoutDays` meets the minimum required for `_workoutSplit`:
- PPL → min 3 days
- Upper/Lower / Strength+Conditioning → min 2 days

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
- **Calorie ring** — today's logged calories vs goal (from `FirestoreService.streamTodayFoodLogs`), with `Goal / Eaten / Remaining / Protein` rows beside it. No on-target label: `Goal` sits directly beside `Eaten`, so over/under is already legible. The Goal row carries the card's single affordance, a tappable **`+195` pill** (`_goalAdjustBadge`, number only) whenever `dailyEffectiveGoal != profile.calorieGoal`.
- **"Today's Goal Adjusted" dialog** — the top-level `showGoalAdjustmentDialog(context, pp, {force})`. Auto path (`_maybeShowGoalDialog`, after the profile/goal load) fires when `CalorieTolerance.shouldAnnounceGoalShift` says a **day breached the band** and today's goal actually moved — deliberately *not* gated on the size of the nudge, which is small by construction after redistribution. Then gated by the `hideGoalAdjustmentPopup` "Don't show again" flag and a once-per-day `goalAdjustmentLastShown` stamp in `SharedPreferences`. Tapping the `+195` badge calls it with `force: true`, skipping all three guards, so the explanation is always retrievable. Copy quotes `ProfileProvider.lastBreachKcal`.
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
4. If no persisted plan: fetches all exercises from `ExerciseDBService`, then — **only when last week has real history** (a persisted `workout_plans/{lastWeekId}` doc or ≥1 workout log; otherwise a new user's empty week reads as 0% completion and would wrongly trigger `'down'`) — runs `AdaptationEngine.compute(...)` with last week's nutrition adherence, workout completion, and the user's `avgHoursSlept`. With no history it uses a neutral result (`'same'`, 0 kcal). Then calls `GreedyAlgorithm.generatePlan(...)`.
5. Saves the new plan via `PlanProvider.persistWorkoutPlan(uid, weekId)`.

**Plan shape:** `List<WorkoutDay>` — 7 entries, Mon–Sun. Days marked `isRest: true` show a rest card; training days show their exercises. **PPL scheduling:** for Push/Pull/Legs (a 3-focus split) `_generate()` passes a `weekIndex` (weeks since `createdAt`) into `generatePlan`; the schedule inserts a rest after each completed Push/Pull/Legs triple, caps at 6 training days (a 7-day selection trains 6), and **rotates the partial extra day** (4–5-day plans) across weeks — wk0 Push, wk1 Pull, wk2 Legs. **Upper/Lower scheduling:** paired ("connected") — Upper+Lower back-to-back then a rest after each pair (`Upper, Lower, Rest, Upper, Lower, Rest, Rest` for 4 days); an odd trailing day is always Upper (fixed, no rotation). Other splits (Full Body, S+C) keep the even-spread schedule.

**Focus labels:** the day-focus subtitle on each workout card/header (and the Home today/completed cards) renders `GreedyAlgorithm.focusLabel(day.focus)`, which prefixes the split role onto muscle-only focuses — e.g. "Pull (Back & Biceps)", "Push (Chest & Triceps)". Display-only; the stored `focus` string is unchanged.

**Conditioning finisher:** for **Weight Loss / Endurance** goals, `_generate()` runs `ConditioningFinisher.apply(...)` after `generatePlan` (a post-generation step outside the greedy scorer) so each training day ends with a conditioning move. **Gym** users get a **treadmill · 15 min** finisher (a built-in treadmill whose gif comes from the same CDN the app streams all gifs from, since the ExerciseDB catalog has no treadmill entry); **Home** users get a bodyweight conditioning move (cardio/endurance, respecting limitations). Muscle Gain / General get none — this is how the fitness goal visibly changes the plan.

**Week strip navigation:** the 7-day strip (`_buildWeekDayStrip`) is **horizontally swipeable** — a swipe jumps ±1 week (same weekday preserved) via `_onWorkoutDateChanged(_selectedDate ± 7d)`, with a slide-in animation (`AnimatedSwitcher` keyed by `weekStart`, direction from `_weekSlideDir`). The `< date >` navigator arrows still move ±1 day, and tapping a day / the date picker still work. Everything re-derives from `_selectedDate`, so the header label (Today/Tomorrow/date) updates with the swipe.

**Workout flow (set-by-set):**

| State variable | Meaning |
|---|---|
| `_activeExerciseIndex` | Index of the exercise currently being performed (−1 if not started) |
| `_activeSetNumber` | Which set the user is on (1-indexed) |
| `_inRest` | Whether the rest timer is running |
| `_restRemaining / _restTotal` | Countdown seconds |
| `_setRunning` | Whether the per-set work timer is counting down (vs. the kg/reps logging sub-phase) |
| `_setRemaining / _setTotal` | Work-timer countdown seconds (total = `WorkoutExercise.timePerSetSeconds`) |
| `_waitingForReady` | Showing the "Up Next / I'm Ready!" card between exercises |
| `_completedExercises` | Set of finished exercise indices |
| `_elapsedSeconds` | Total workout time (driven by a periodic `Timer`) |

When the user taps **Start Workout**: `_startWorkout()` sets `_activeExerciseIndex = 0`.

Each set runs as two sub-phases: **logging** (enter kg/reps, then tap **Start Set** — the "ready" gate) → **working** (`_startSet(we)` runs a per-set work timer of `WorkoutExercise.timePerSetSeconds`, sized to fit `sessionMinutes`; the user taps **Done** to end early, or the timer reaching 0 auto-advances). Either path calls `_finishSet(we)` → `_doneSet(we)`: if more sets remain, starts the rest countdown; when rest ends, moves to the next set (back to the logging sub-phase via `_setRunning=false`). When the last set of the last exercise is done, `_autoComplete()` is called → `_saveWorkoutLog()` → `FirestoreService.saveWorkoutLog()`.

**Edit mode:**

Toggle the "Edit session" button (visible before a workout starts). While editing:
- The day's exercises render in a `ReorderableListView` (`_buildReorderableExerciseList`) with a **drag handle** (`ReorderableDragStartListener`) beside each card → `PlanProvider.reorderExercises` (persists immediately). Edit mode is force-exited at the top of `_startWorkout` so the list is unmounted before the session UI replaces it.
- Each exercise card gets a **× delete button** (top-right corner) → `PlanProvider.removeExercise`.
- An **"Edit params"** button (bottom-right) → opens a bottom sheet with ±steppers for sets and rest seconds, and a text field for reps/duration → `PlanProvider.updateExerciseParams`.
- An **"Add exercise"** button at the bottom of the day → `_showExercisePicker()` — a `DraggableScrollableSheet` with a live **search bar** (filters by name/muscle) listing exercises for that day's muscle focus. The focus→muscle map is `GreedyAlgorithm.musclesForFocus` (single source of truth shared with the generator, ExerciseDB `targetMuscles` vocabulary — `pectorals`/`lats`/`delts`…). The picker filters by `_pickableByUser` (= `GreedyAlgorithm.isEligibleForUser` only — gender/location/equipment/bench), i.e. **without** the experience gate, so the user may add an above-tier move; each row shows a difficulty badge and an above-tier pick triggers an "Above your level — add anyway?" confirm. The automatic `_fillExerciseGap` / `_applyVolumeDebt` paths still use the strict `_usableByUser` (eligibility **+** `difficultyAllowed`) → `PlanProvider.addExercise`.
- All edits call `PlanProvider.persistWorkoutPlan` immediately so they're durable.
- **Live load tracking (progressive overload):** the active exercise card shows a working-weight + reps input (unit-aware via `UserProfile.unitSystem`), pre-hinted with the last logged top set ("Last: 60 kg × 8 · PR 70 kg") from `_exerciseStats`. Captured on each "Done Set"; on completion folded into `WorkoutLogExercise.weightKg/repsDone` and upserted to `exercise_stats` (`saveExerciseStat`), with a PR snackbar when a best is beaten. Non-active cards show a "Last/PR" caption.
- **Progression prescription (`lib/algorithms/progression.dart`, pure Dart):** `nextTarget()` turns the last top set into a **double-progression** target (add a rep within the prescribed range; once the top of the range is hit, add weight — +5 kg compound/lower, +2.5 kg isolation, decided by `isStapleCompound` or a lower-body primary muscle). The active card shows a green **"Target: X × R"** line (↑ when load steps up) and the weight/reps inputs are **auto-pre-filled** with it (`_prefillTargetFor` on start / "I'm ready"); falls back to the plain prompt when there's no history or a timed rep prescription.
- **Warm-up (general phase only, all `plans_screen.dart`; never logged/persisted):**
  - **Compound-first ordering** — `GreedyAlgorithm._selectExercisesForDay` 3-tier stable-sorts each day: barbell/dumbbell big lifts (`isHeavyCompound`, by `_bigLiftKeywords`) → bodyweight compounds (`isStapleCompound`) → isolations, so the big lifts always lead. The same `isHeavyCompound` predicate also adds a +8 lead bonus in scoring so a foundational lift is *selected* first, not just sorted first.
  - **General warm-up phase (gated, `_buildGeneralWarmup`)** — pressing **Start Workout** sets `_sessionStarted` and enters a warm-up phase *before* the lifts; the exercise cards are shown but **locked/greyed** (`IgnorePointer` + 0.4 opacity) until the warm-up finishes/skips (`_warmupComplete`). The warm-up card has two states: an **intro** (`_buildWarmupIntro`) listing the moves with a **Start warm-up** button, and an **active** full-size card (`_buildActiveWarmupCard`) showing the current move's GIF + an **auto-advancing countdown** (`_warmupTimer`), with **Next move** / **Skip warm-up**. Moves are resolved by `_resolveWarmupMoves` — up to 3 bodyweight `category=='cardio'` moves (60 s each) with GIFs, the **same for Gym and Home**. `_finishWarmup` unlocks the lifts and starts the exercise flow (`_activeExerciseIndex=0`, `_prefillTargetFor(0)`). All warm-up state resets in `_resetWorkoutState`; never logged. (There is **no** per-compound load ramp / working-weight prompt — removed; the active card goes straight to the weight/reps input.)
  - **Expandable steps (`_buildStepsExpander`)** — each exercise card (active and non-active) shows a collapsed **"Steps"** toggle that expands the move's `instructions`; expansion state in `_expandedSteps` (keyed by exercise index), cleared on reset. Keeps cards compact.
- **Pin anchor lifts:** a pin icon on each (non-active) exercise card toggles `UserProfile.pinnedExercises[focus]` via `ProfileProvider.save`; the generator force-includes pinned lifts first on that focus's days (survives regeneration).
- **Post-workout rating:** finishing a workout opens a 1–5 perceived-difficulty sheet (`_askWorkoutRating`); stored on `WorkoutLog.rating` and averaged into next week's `AdaptationEngine` autoregulation.

**State:**
`_plan`, `_profile`, `_isLoading`, `_error`, `_selectedDay`, `_todayLog`, `_weekDone`, `_editMode`, `_allExercises` (cached from last generate for the picker), load-tracking state (`_topSetKg`, `_topSetReps`, `_exerciseStats`, `_weightController`, `_repsController`), meal state (`_pending`, `_edamamRecipes`, `_loggedFoods`, `_loadingMeals`).

**Connections:**
- `PlanProvider` — in-memory plan, persist/load, edit methods.
- `ProfileProvider` — reads/saves the profile, including `pinnedExercises`.
- `FirestoreService` — `saveWeeklyWorkoutPlan`, `loadWeeklyWorkoutPlan`, `saveWorkoutLog`, `getWorkoutLogsForDateRange`, `saveExerciseStat`/`getExerciseStats` (per-exercise last/PR).
- `ExerciseDBService` — fetches all exercises (Firestore-cached 30 days).
- `GreedyAlgorithm` — generates the plan.
- `AdaptationEngine` — computes `difficultyBias` and `calorieBiasKcal`.
- `GeneticAlgorithm` — generates meals from ingredients (see Meal Tab below).

---

### Meal Tab (inside PlansScreen)

Shows meal cards for Breakfast, Lunch, Dinner, Snack. The tab is split into two modules (thesis architecture):

**Module 1 — Meal Planning (Generate Meal, before eating):**
1. A card's **Generate** button → `_startGenerateFlow(mealType, label)` → option bottom sheet (`_chooseGenerateOption`): **Use Available Ingredients** (Option A) or **Generate Automatically** (Option B).
2. **Option A** pushes `FoodLogScreen(pickerMode: true)` — the user multi-selects available foods (USDA search / barcode / history, *no grams asked*); picks come back as per-100g `MealIngredient`s (`IngredientConverter`). After a `DietaryFilter.violates` pre-screen, `GeneticAlgorithm.optimizeMealPortions` evolves the **gram vector** over the fixed picked set. **Option B** runs `evolveMeal` over the seeded `ingredients` pool (loaded once via `FirestoreService.getIngredients()`; empty pool surfaces a "not seeded" SnackBar) with `presentCategories` + cuisine + `avoidIds`.
3. Both options size to the meal's *remaining* budget: `ratio·dailyEffectiveGoal − loggedCals(meal)` (≤ 30 kcal → info SnackBar, no generation).
4. The result opens the **accept-mode `RecipeScreen`** (`_reviewAndAccept` loop): fresh OpenAI recipe + ingredients with GA grams + expandable macro/micro nutrition summary + **Accept / Regenerate**. Accept-mode pops a `RecipeReviewResult(action, recipeTitle)`; on `'accept'` → `PlanProvider.setMeal(saveToFirestore: true, recipeName: title)` → `_saveMealToFirestore` writes each ingredient as its own `FoodItem` (`barcode: 'ai_generated'`), **stamping the OpenAI recipe title onto every one via `FoodItem.recipeName`** → `_loadTodayLogs()` + `recomputeGoal`. Regenerate re-runs the same option (A keeps the picked pool; B avoids the shown ingredient ids). Back = discard. ("Accept Without Recipe" on OpenAI failure → empty title → no sub-header.)

**AI recipe name on the card:** when a meal has a non-empty recipe name — on its logged foods' `FoodItem.recipeName` (accepted meals) **or** on `_pendingRecipeName[mealType]` (Generate-All staged meals) — `_buildFilledCard` renders a tappable **recipe-name sub-header** (`_recipeSubHeader`) below the meal-type title; it toggles `_expandedIngredients[mealType]` to collapse/expand the ingredient rows — **both** the logged (orange) and pending (green) rows — (**collapsed by default**, mirroring the `_expandedMacros` chevron idiom). The macro-summary row (totals) and the **Recipe** button are unchanged. Manually-logged meals carry no name → no sub-header, ingredients shown inline as before. The logged name is per-`FoodItem`, so it stays correct across days and after reload (unlike the single-slot `saved_recipes/{mealType}` doc, which still backs only the view-mode Recipe screen).
5. The top-bar **All** button (`_generateAll`) still uses the **pending staging**: `GeneticAlgorithm.mealBudgets(goal, loggedCalsByMeal)` splits the day's remaining budget across meals; results become green *pending* rows and **"Log Additions"** persists only the new items (no double-save). After staging, `_generateAll` fetches an **OpenAI recipe title per meal in parallel** (`_recipeTitleFor`, best-effort — failure leaves the meal nameless) and holds them in `_pendingRecipeName[mealType]`; the staged card shows the recipe-name sub-header, and `_logPendingMeal` passes `recipeName:` through `setMeal` so the logged FoodItems carry it (same as the Accept flow).

**Module 2 — Nutrition Tracking (what was actually eaten):**
- **Log Food / Add food** buttons open the regular `FoodLogScreen` (USDA search, barcode, history) — logging never triggers generation; daily totals/remaining update reactively through the providers.
- **Tap any logged row** → `_showEditLoggedFood` bottom sheet: edit grams (gram-based items, incl. accepted `ai_generated` ones) or servings, or delete — writes only the `quantity` multiplier via `FirestoreService.updateFoodLog`.

**Fail-safe:** empty pool / no match / restriction-emptied pool → `_showNoMatchMessage()` ("No ingredients match your dietary restrictions"); a meal/day at-or-over its calorie share → info SnackBar (never overloads). No day selector — meals are always for *today*. `completeMeal` and the 7-day `generatePlan` are retained for tests but no longer driven by the Meal tab.

Calorie split: Breakfast 25%, Lunch 35%, Dinner 30%, Snack 10% of the daily effective goal.

---

## 6. Nutrition Tab — NutritionScreen

**File:** `lib/screens/nutrition_screen.dart`

**Purpose:** Shows logged food for any selected date across two sub-tabs.

**State:** `_selectedDate` (defaults to today).

**Sub-tabs:**
- **Calories** — pulls `FoodItem` logs for `_selectedDate` from Firestore; shows the "N kcal left" ring, `Goal / Eaten / Remaining` cards, macro bar chart breakdown (protein/carbs/fat), and a per-meal expandable list. No on-target label — the ring and those three cards already state it.
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
| `_WeeklyReportCard` | Entry point (NEW badge) → `WeeklyReviewScreen` (Weekly Adaptive Report). No data of its own |
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
- **Fitness card** — goal, experience level, activity level, location, workout split, days/week, session length, equipment, physical limitations (shown only when any are set).
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

### WeeklyReviewScreen — Weekly Adaptive Report
**File:** `lib/screens/weekly_review_screen.dart`

**Purpose:** Surfaces the weekly adaptation the engine already computes — what changed in the plan and why — plus a history of past weeks. Reads `WeeklySummary` snapshots from `users/{uid}/weekly_summaries/{weekId}` (self-contained, like PlansScreen; no provider).

**Reached from:** the Progress-screen `_WeeklyReportCard`, and the post-generation **"Weekly plan updated based on your progress"** snackbar's *View Summary* action (`plans_screen.dart`). The snackbar (once per week, with a ✕ close icon) replaced the old raw adaptation-notes snackbar.

**Load:** `initState` runs `FirestoreService.getWeeklySummary(uid, weekIdFor(appNow()))` (current week) + `getWeeklySummaries(uid)` (history) in parallel.

**Tabs (TabController):**
- **Current Week** — `_SummaryDetailView` for this week's summary, else an empty state ("No adaptive report yet — adapts at the start of each week once you have history").
- **History** — `ListView` of past summaries (newest first), each row = date range + `Week N` + colored `adjustmentBadge` chip; tap → `_HistoryDetailScreen` reusing `_SummaryDetailView`. Empty state until weeks accumulate (no backfill).

**`_SummaryDetailView` (shared body):** header "Week of {range}" (+ Current Week chip); **Performance Summary** (Calories %, **Days on Target** `n / m logged` with a Consistent/Mixed/Off Target tag, Protein %, Workouts done/planned, Workout Feedback avg as emoji+Easy/Moderate/Hard — all from the *reviewed* prior week); **AI Adjustments** (Calories ±/new target, then **derived** Protein/Carbs/Fat ±/new targets only when calories moved, Workout Intensity Increased/Reduced/Maintained — intensity only flagged a change when `volumeChanged`); **Why These Changes?** = the summary `notes`.

**Honest-data notes:** macros are derived from the calorie goal (engine tunes calories only), so the "Increased Protein" badge from the mockup is intentionally absent. Framing is "last week reviewed → change active this week," matching when the engine actually runs. The Calories tag uses the shared ±5% `CalorieTolerance` band (95–105% = "On Goal") — the same band the engine decides on — so the tag can never read "On Goal" beside a ±100 kcal adjustment; Protein keeps its looser 90/110 tag. The card footer states the tolerance ("Intake within ±5% of your target counts as on target"). `daysInTolerance` is 0 on summaries written before the tolerance shipped (no backfill).

---

### FoodLogScreen
**File:** `lib/screens/food_log_screen.dart`

**Purpose:** Lets the user log food for a specific meal type. Three entry paths:
1. **Text search** — queries USDA FoodData Central API (`/foods/search`) by keyword; returns `_USDAFoodItem` list with full macro data.
2. **Barcode scan** — if `autoScan: true` (or tapping the scan icon), launches `BarcodeScanScreen` → scans EAN/UPC → queries `OpenFoodFactsService` by barcode → pre-fills the food detail form.
3. **History** — shows the user's last 20 unique entries for this meal type (last 30 days) for quick re-logging.

**Save flow:** selecting any food item → "Add" button → `FirestoreService.logFoodItem(FoodItem)` → `users/{uid}/food_logs/{logId}`.

**Picker mode (`pickerMode: true`)** — the Meal-Planning ingredient picker (Module 1, Option A). Same three paths, but nothing is logged and **no grams are asked** (the GA decides portions): each selection is converted to a per-100g `MealIngredient` (`IngredientConverter`) and collected in a bottom chip basket; the AppBar "Done (N)" pops the `List<MealIngredient>` back to `_startGenerateFlow`. Dietary restrictions are **blocking** here: search results are filtered (as always), history is filtered too, a conflicting barcode scan is rejected with a message, and `_addPicked` re-checks `DietaryFilter.violates`. History swipe-to-delete is disabled in picker mode.

**State:** `_results` (USDA search), `_history`, `_isLoading`, `_hasSearched`, `_loggingIds` (tracks in-flight logs to disable buttons), `_picked` (picker-mode basket).

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

**Purpose:** Shows step-by-step cooking instructions for a generated meal, plus the meal's ingredient list and expandable macro/micro nutritional summary. The GA meal's ingredients (with gram portions) are sent to **OpenAI** (`OpenAIService.generateRecipe`) which writes the recipe — OpenAI never changes quantities; the GA is the nutrition source of truth.

Two modes:
- **View mode** (default) — the Recipe button on a meal card. Loads the cached `saved_recipes/{mealType}` doc first; bookmark toggles save/unsave; refresh regenerates wording.
- **Accept mode** (`acceptMode: true`) — the Module-1 review step pushed by `_reviewAndAccept`. Always fetches a fresh recipe (a cached one wouldn't match the just-optimized grams), hides bookmark/refresh, and shows **Regenerate** / **Accept Meal** buttons (plus a "Rewrite recipe" text button — same grams, new wording). Pops a `RecipeReviewResult(action, recipeTitle)` — `action` is `'accept'` (after best-effort `_saveRecipeDoc()`, carrying the OpenAI title so `_reviewAndAccept` can stamp it onto the logged `FoodItem`s) or `'regenerate'`; null = back (discard). An OpenAI failure still offers **Accept Without Recipe** (empty title) and **Regenerate Meal** so the user is never trapped.

**State:** `_recipe`, `_isLoading`, `_error`, `_isSaved`, `_addedExtras`.

**Key functions:**
- `_loadSavedOrFetch()` — checks Firestore for a previously saved recipe for this meal type before generating (skipped in accept mode).
- `_fetchRecipe()` — sends the meal's ingredients (`'${grams}g ${name}'`) to `OpenAIService.generateRecipe`, maps the returned steps into `_RecipeResult`.
- `_saveRecipeDoc()` — persists the recipe to `users/{uid}/saved_recipes/{mealType}` (shared by the bookmark toggle and Accept).

**Connections:**
- `OpenAIService` (`lib/services/openai_service.dart`) — generates the recipe text (hardcoded key constant; needs OpenAI account credits).
- `FirestoreService.logFoodItem` — saves individual "You'll also need" extras.
- Launched from: `PlansScreen` Meal tab → Recipe button (view mode) or `_reviewAndAccept` (accept mode).

---

### SettingsScreen
**File:** `lib/screens/settings_screen.dart`

**Purpose:** Preferences (dark mode, units, goal-adjustment notification) and Account actions (edit profile, change password, log out). Reached from the Profile tab.

**Developer section (demo tooling):** a **Developer Mode** `Switch` (persisted to `SharedPreferences` `developerMode`, toggling `developerModeEnabled`) reveals, when on, a set of adaptive-system demo controls — see the CLAUDE.md "Debug flags" section for the full behaviour:
- **Change Day** switch → `devDayChangerEnabled` (shows the floating date pill).
- **Demo Scenario** `ChoiceChip`s → `devScenario` (`Level up` / `Ease off` / `Realistic`).
- **Auto-Complete Today's Workout** → `DevTools.autoCompleteToday` (logs today's plan as done).
- **Skip to Next Week** → `DevTools.simulateWeekAndAdvance` (seeds this week's workout + food logs per scenario, then jumps the clock +7 so opening Plans fires the weekly adaptation and writes a `WeeklySummary`).

Turning Developer Mode off resets `devDayChangerEnabled` and `debugDayOffset` so a real user is never left on a shifted day.

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

`_computeDailyGoal(uid)` (run on `load`/`refresh`/`save`/`recomputeGoal`) buckets this week's food logs **per day** and feeds `CalorieTolerance.effectiveWeekConsumed(dayTotals, base)` into `WeeklyAdaptiveGoal.adjust`, so a day inside the ±5% band counts as exactly on target and only meaningful deviations are redistributed into `dailyEffectiveGoal`. `daysElapsed` is the count of **logged** days (a day with no logs is missing data, not a zero-calorie day, and used to read as a full shortfall). Macros keep raw sums. It also exposes `daysInToleranceThisWeek` / `daysLoggedThisWeek`.

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

### ConnectivityProvider
**File:** `lib/providers/connectivity_provider.dart`

**Purpose:** Single source of truth for `isOffline` — real connection loss (`connectivity_plus`) OR the Developer-Mode `forceOfflineEnabled` switch. Drives the offline banner (`_OfflineBanner` in `main.dart`'s builder Stack) and the network-feature guards in `lib/widgets/offline.dart` (`isOffline`, `showOfflineSnack`, `OfflineNotice`).

**Key behavior:** The dev switch calls Firestore `disableNetwork()`/`enableNetwork()` for a real cached-reads/queued-writes test; real connectivity is left to the SDK. On each offline→online transition (after the queue flushes) it fires `addReconnectListener` callbacks — `HomeScreen` registers `ProfileProvider.recomputeGoal(uid)` so the daily adaptive goal re-syncs. Never re-runs the weekly `AdaptationEngine` (guarded by `lastAdaptationWeekId`). Firestore persistence is made explicit in `main.dart` so all Firestore-backed screens work offline from cache. See CLAUDE.md **Offline mode**.

---

## 11. Algorithms

### GreedyAlgorithm
**File:** `lib/algorithms/greedy_algorithm.dart`

**Purpose:** Generates a 7-day `List<WorkoutDay>` from a `List<Exercise>` + `UserProfile`. Pure Dart — no Flutter or Firebase.

**Entry point:** `generatePlan(allExercises, profile, difficultyBias)`

**Pipeline:**

```
allExercises
  │  HARD FILTER — static isEligibleForUser(e, profile):
  │    gender-tagged variants (no "(male)" moves for Female users & vice versa)
  │    Gym → all equipment available (gym profiles store equipment: [])
  │    Home → must list 'home' + intersect user's equipment (bodyweight always OK)
  │    Home rack rule → barbell squat/bench-press need the 'Home Gym' (rack) chip
  │    Home bench rule → free-weight incline/decline/bench moves need the 'Bench' chip
  ↓
filtered exercises
  │
  ├─ _getSchedule(profile)
  │    Uses: workoutSplit → focus cycle sequence
  │           workoutDaysPerWeek → how many training days to place
  │           → 7-element list e.g. ['Full Body', 'Rest', 'Full Body', ...]
  │
  └─ For each training day:
       _selectExercisesForDay(filtered, targetMuscles, profile, muscleHitCount, count, difficultyBias)
         │  STRICT difficulty gate (static difficultyAllowed): Beginner → beginner
         │    only; Intermediate → beginner+intermediate; Advanced → all
         │  HARD FOCUS POOL: primaryPool (primary muscle in targetMuscles) →
         │    assistPool (focus as secondary mover) only to reach count; never
         │    off-focus (shorter day instead) — fixes "wrist curl on Leg day"
         │  INCREMENTAL GREEDY: pick best → update day-local muscle hits →
         │    re-score → repeat (prevents one muscle sweeping a whole day)
         │  Per-muscle/day cap: ceil(count / targetMuscles.length), min 2
         │  Score (orders WITHIN the focus pool): goal +15, staple-compound +12,
         │         exact-tier +10, day-local penalty −25/hit, weekly −15/hit
         └─ Wrap each in WorkoutExercise(sets, reps, restSeconds, timePerSetSeconds)
```

**Volume decisions — all profile-driven:**

| Decision | Driver |
|---|---|
| Training day positions (which of Mon–Sun) | `workoutDaysPerWeek` (evenly spaced) — **hard constraint, never reduced by adaptation** |
| Focus per day | `workoutSplit` → cycles through split's sequence |
| **Exercises per day** | **`sessionMinutes` (session-duration fit — Objective 4).** `_fitExerciseCount` picks the largest count whose `count*sets*work + (count*sets−1)*rest` fits `sessionMinutes*60 − 180 s` warm-up; capped at 6 (≤5 at ≥5 days/wk). Never schedules **over** target; NSCA-bounded volume that can't fill a long session undershoots (accepted). |
| Sets | Goal + experience, **clamped to the goal's NSCA set range** (hypertrophy 3–5, endurance 2–3, general 2–4); −1 if `recoveryScore < 0.8`; ±1 for `difficultyBias` 'up'/'down' (re-clamped to range) |
| Reps / duration | Goal + split style within NSCA rep ranges (hypertrophy 6–12, endurance ≥12; HIIT/Circuit → timed) |
| Rest seconds | Goal + split style within NSCA rest ranges (HIIT → 30 s; endurance → 45 s; Muscle Gain → 90 s) |
| Time per set (work timer) | `_estimateWorkSeconds(reps)` — ~3 s/rep + setup (timed moves use their value), clamped 30–75 s. The live per-set countdown only; **not** an NSCA loading parameter. |

**NSCA grounding** — every reps/sets/rest number follows the NSCA goal-loading table (Sheppard & Triplett, *Program Design for Resistance Training*, in **Essentials of Strength Training and Conditioning, 4th ed.**, Baechle & Earle):

| App goal | NSCA category | Reps | Sets | Rest |
|---|---|---|---|---|
| Muscle Gain | Hypertrophy | 6–12 | 3–6 (capped 5) | 30 s–1.5 min |
| Weight Loss / Endurance | Muscular endurance | ≥12 | 2–3 | ≤30 s (circuit, ~45 s) |
| Strength + Conditioning | Strength/conditioning hybrid | ≤8 | 2–5 | up to ~2 min |
| General / Maintenance | Hypertrophy–endurance blend | 8–15 | 2–4 | 30–90 s |

Session duration is honored by **exercise count** (the Greedy selection lever); per-set loading stays inside these ranges and is never inflated to pad time.

**`difficultyBias`** (from `AdaptationEngine`) — modulates **sets per exercise only** (re-clamped to the goal's NSCA set range); the exercise count is duration-driven, and the user's selected training days are never added or removed:
- `'up'` — +1 set per exercise (within the NSCA range).
- `'down'` — −1 set per exercise (within the NSCA range).
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
Calorie (dead zone = the shared ±5% CalorieTolerance band):
  adherence < 95%  → calorieBias = +100 kcal
  95%–105%         → calorieBias = 0 (measurement noise, no action)
  adherence > 105% → calorieBias = −100 kcal
                     (skipped for a Weight-Loss user who is actually losing)

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
| `EdamamService` | `lib/services/edamam_service.dart` | Edamam Meal Planner integration; kept for future recipe features. (The old TheMealDB `MealService` has been deleted — meal generation runs the `GeneticAlgorithm` over USDA ingredients.) |
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
| `sessionMinutes` | int | `_fitExerciseCount` (exercise-count session-duration fit) in `GreedyAlgorithm` |
| `workoutSplit` | String | `_getSchedule` focus cycle + reps/rest style |
| `avgHoursSlept` | double | `recoveryScore` → sets reduction; `AdaptationEngine` difficulty gate |
| `recoveryScore` | double (getter) | `< 0.8` → −1 set (within NSCA range) |
| `activityMultiplier` | double (getter) | Maps `activityLevel` to Harris-Benedict multiplier |
| `weight` | double (kg) | BMR → TDEE → `calorieGoal` → `macroGoals`, and BMI; synced by `ProfileProvider.updateWeight` when a weight is logged |
| `calorieAdjustment` | int | Added to the goal-derived base in `calorieGoal` (then clamped to 1200 floor); fed by `AdaptationEngine.calorieBiasKcal`, clamped to ±500 |

### Firestore Collections
```
users/{uid}
  food_logs/{logId}           FoodItem (full macro + 14 micro)
  workout_logs/{logId}        WorkoutLog (completed session)
  workout_plans/{weekId}      Serialised List<WorkoutDay> (persisted editable plan)
  weight_logs/{logId}         WeightLog (doc ID = YYYY-MM-DD)
  exercise_stats/{exerciseId} ExerciseStat (last/PR top set + last session sets)
  weekly_summaries/{weekId}   WeeklySummary (weekly adaptive report snapshot)
  saved_recipes/{mealType}    Cached OpenAI recipe per meal card

exercises/{exerciseId}        ExerciseDB cache (30-day TTL)
ingredients/{id}              USDA-seeded MealIngredient pool (Genetic Algorithm)
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
| `meal_service.dart` | `_categoriesForMealType` handled diet styles as hard constraints (historical — file since deleted with the move to the Genetic Algorithm) |

### Fixes (between phases)

| File | Fix |
|---|---|
| `profile_input_screen.dart` | DOB picker instead of age text field |
| `profile_input_screen.dart` | Split/days incompatibility guard (live warning + dialog) |
| `profile_input_screen.dart` | Removed "Other" gender (irrelevant to BMR formula) |
| `meal_service.dart` | High-protein and other diet styles hard-constrained category selection (historical — file since deleted) |
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
