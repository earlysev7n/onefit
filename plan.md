# OneFit — Profiling & Personalization Overhaul

## Context

The onboarding profile is shallow and partly broken: the register screen collects a full name it throws away, "activity level" is faked by reusing `experienceLevel + workoutLocation`, and the greedy algorithm ignores how many days a user can train, how long a session is, what split they want, and how well-recovered they are. Plans are in-memory only, so nothing a user changes survives a restart.

This plan adds real profiling inputs and wires them end-to-end into the greedy algorithm, the plans UI (now editable + persisted), and the progress/adaptation loop.

**Decisions (confirmed with user):**
- "Workout style" = **weekly split**, chosen from **10 styles** (see 1.3) rendered as **selectable description cards**, driving the 7-day schedule.
- **Activity level** uses a **dropdown + "?" info button**; a reusable "?" help-hint pattern is added beside choice inputs app-wide. Activity level explicitly drives **TDEE → calorie goal**.
- Editable sessions = **full edit** (swap / add / remove exercises + change sets/reps/rest).
- Workout days & session minutes = **explicit user inputs**; activity level + sleep drive recovery/workload.
- Plans are **persisted to Firestore** so edits stick.

**Execution order:** Phase 1 (profiling) ships first and is self-contained — it only **collects + stores** the new inputs and fixes registration. Phase 2 is the **connection/integration phase**: it wires every stored field into the systems that consume it (greedy algorithm, plans UI, calories, progress, adaptation) so nothing is collected-but-ignored. No new user-facing inputs are added in Phase 2 — it makes Phase 1's data actually *do* something.

---

## Phase 1 — User Profiling

### 1.1 Fix register screen — `lib/screens/register_screen.dart`
- Remove `_nameController` (line 13) and the **Full Name** `TextField` (lines 45–58). Registration becomes auth-only; the name is still collected later in onboarding Step 1.
- Add `_confirmPasswordController` + a **Confirm Password** field (obscureText, mirrors the password field styling).
- Add validation in the submit handler (lines 94–109) before `AuthService().register(...)`:
  - email non-empty + contains `@`,
  - password length ≥ 6,
  - `password == confirmPassword` (else SnackBar "Passwords do not match" and abort).
- Keep the existing `AuthService().register(email, password)` call and `Navigator.pop` flow unchanged.

### 1.2 Extend the data model — `lib/models/user_profile.dart`
Add fields (with safe defaults so existing Firestore docs keep loading):
| Field | Type | Default | Values |
|---|---|---|---|
| `activityLevel` | String | `'Moderately Active'` | Sedentary, Lightly Active, Moderately Active, Very Active, Extra Active |
| `workoutDaysPerWeek` | int | `3` | 1–7 |
| `sessionMinutes` | int | `45` | 30 / 45 / 60 / 90 |
| `workoutSplit` | String | `'Full Body Training'` | 10 styles — see 1.3 split cards |
| `avgHoursSlept` | double | `7.0` | ~3–12 |

- Constructor: add the params with the defaults above.
- `fromMap` (lines 134–149) / `toMap` (lines 151–166): read/write the 5 new keys.
- **Replace `activityMultiplier` (lines 39–46)** — drop the experience+location proxy; map from `activityLevel`: Sedentary 1.2, Lightly Active 1.375, Moderately Active 1.55, Very Active 1.725, Extra Active 1.9.
  - **Explicit TDEE chain (user requirement):** `activityLevel` → `activityMultiplier` → `tdee` (`bmr * activityMultiplier`, line 48) → `calorieGoal` (line 50) → `macroGoals`. These getters already chain, so the only edit is the multiplier source; Home/Progress (`progress_provider.dart` reads `calorieGoal`) then reflect activity level automatically. Verify by changing activity level and watching the calorie goal move.
- Add `double get recoveryScore` — a 0–1 factor from `avgHoursSlept` (e.g. <6h → 0.7, 6–7h → 0.85, ≥7h → 1.0). Consumed by the greedy algorithm in Phase 2.

### 1.3 Collect the new inputs — `lib/screens/profile_input_screen.dart`
Existing 3-step `PageView` (About You / Your Fitness / Your Diet). Add state vars `_activityLevel`, `_workoutDays`, `_sessionMinutes`, `_workoutSplit`, `_avgSleep` and option lists.

**Reusable "?" help-hint widget (build once, use everywhere):** add a small helper `_LabelWithHelp(title, {Map<String,String> options})` that renders the field's section label with an `Icons.help_outline` "?" button on the right; tapping opens a styled bottom sheet listing each option name + a one-line description. Use it beside every choice input the user might not understand (activity level, split, session length, goals, experience). This satisfies the user's "small question-mark button… short summary of what each selection is" request consistently.

- **Step 1 (`_buildStep1`)**: add **Average hours slept** — slider 3–12 (reuse existing dark slider styling), label shows the live value.
- **Step 2 (`_buildStep2`)** additions:
  - **Activity Level** — a **dropdown** (`DropdownButtonFormField`, dark-themed) with the 5 levels, plus the **"?" help button** beside the label whose sheet explains each: Sedentary (little/no exercise, desk job), Lightly Active (light exercise 1–3 d/wk), Moderately Active (moderate 3–5 d/wk), Very Active (hard 6–7 d/wk), Extra Active (very hard + physical job). Drives TDEE per 1.2.
  - **Workout Split** — a **vertical list of selectable cards** (not chips). Each card shows the split name + a one-line description and highlights green when selected (reuse the `0xFF00C97B` accent / `0xFF1A1A1A` surface tokens). The 10 options + descriptions:
    1. **Full Body Training** — every session trains the whole body; best at 2–3 days/week.
    2. **Upper / Lower Split** — alternate upper- and lower-body days; balanced for ~4 days/week.
    3. **Push / Pull / Legs (PPL)** — push, pull, then legs; ideal at 3 or 6 days/week.
    4. **Bro Split** — one muscle group per day (chest, back, legs, shoulders, arms); 5 days.
    5. **Hybrid Split** — mixes full-body and upper/lower work; flexible schedules.
    6. **HIIT + Strength Split** — alternates strength days with high-intensity interval days.
    7. **Body Part Split** — focused single-region days with finer targeting.
    8. **Functional Training Split** — compound, movement-pattern full-body sessions.
    9. **Strength + Conditioning Split** — heavy strength days paired with conditioning/cardio.
    10. **Circuit Training Split** — full-body circuits, minimal rest, time-efficient.
  - **Time per session** — chip selector 30 / 45 / 60 / 90 min (with "?" hint: drives how many exercises per day).
  - **Days per week** — 1–7 selector (chips or slider).
- Update `_saveProfile()` (lines 105–123) to pass the 5 new fields into the `UserProfile(...)` constructor.

### 1.4 Mirror fields in profile editing — `lib/screens/profile_screen.dart`
The post-onboarding "edit profile" form must show/edit the same 5 new fields (reusing the dropdown, split cards, sliders, and the `_LabelWithHelp` widget) and re-save via `FirestoreService().saveUserProfile(...)`, so users can change them later.

**Phase 1 is shippable here:** richer profile saved to Firestore, accurate calories from real activity level, fixed register screen. Nothing downstream breaks because defaults cover old docs.

---

## Phase 2 — Connect everything (wire profiling into the engine)

> **Goal of this phase: integration only.** Every field added in Phase 1 gets connected to what uses it. The checklist below maps each input to its consumer so nothing is left dangling:
> - `activityLevel` → `activityMultiplier` → TDEE → calorie/macro goals (2.1 model already done in 1.2; surfaces in Progress 2.4)
> - `workoutSplit` + `workoutDaysPerWeek` → `_getSchedule` (2.1)
> - `sessionMinutes` → `_exercisesPerDay`; `avgHoursSlept`/`recoveryScore` → exercise count + `_getSets` (2.1)
> - editable + persisted plans → PlanProvider + Firestore + Plans UI (2.2)
> - `avgHoursSlept` → adaptation engine (2.3); `workoutDaysPerWeek` → real progress completion % (2.4)

### 2.1 Greedy algorithm — `lib/algorithms/greedy_algorithm.dart`
- **Schedule from split + days** — refactor `_getSchedule(level, goal)` (lines 195–327) into `_getSchedule(profile)`. Map each of the 10 `workoutSplit` styles to a repeating training-day focus *sequence*:
    - Full Body Training → `['Full Body']`
    - Upper / Lower Split → `Upper Body` / `Lower Body`
    - Push / Pull / Legs (PPL) → `Chest & Triceps` / `Back & Biceps` / `Legs`
    - Bro Split → `Chest & Triceps` / `Back & Biceps` / `Legs` / `Shoulders & Arms` / `Arms`
    - Body Part Split → same per-region sequence as Bro Split (finer single-region days)
    - Hybrid Split → `Full Body` / `Upper Body` / `Lower Body` interleave
    - Functional Training Split → `['Full Body']` (compound/movement focus)
    - HIIT + Strength Split → alternate `Full Body` strength days with `Cardio` days
    - Strength + Conditioning Split → alternate `Full Body` strength with `Cardio` conditioning
    - Circuit Training Split → `['Full Body']` circuits
  - Place exactly `profile.workoutDaysPerWeek` training days, spreading rest days evenly across the 7-day week; fill the rest with `'Rest'`.
  - Ensure every focus string (incl. `Cardio`) has a `_focusToMuscles` mapping (add any missing).
  - **Style intensity profile:** because exercises carry no true modality tag, the conditioning-flavored styles (HIIT, Circuit, Functional, Strength+Conditioning) express their character through reps/rest rather than special exercises — pass the split into `_getReps`/`_getRestSeconds` to shorten rest and raise reps for those styles, and bias selection toward `category == 'cardio'` / `goals` containing `endurance` on their cardio days. (A future enhancement could add real modality tags to `Exercise`; out of scope here.)
  - Keep the `difficultyBias == 'down'` rest-conversion (lines 84–90).
- **Exercise count from session length** — change `_exercisesPerDay(level)` (lines 387–398) to `_exercisesPerDay(profile)`: derive primarily from `sessionMinutes` (≈ 30→3, 45→5, 60→6, 90→8) with a small ±1 experience nudge, then scale down by `recoveryScore` (under-slept → fewer exercises). Update the call site at line 120.
- **Recovery into volume** — in `_getSets` (lines 400–412) optionally shave one set when `recoveryScore` is low. Keeps "activity level + sleep → workload/recovery" honest.

### 2.2 Persist + edit plans
- **Make plan serializable** — add `toMap()/fromMap()` to `WorkoutDay` and `WorkoutExercise` (in `greedy_algorithm.dart`). `WorkoutExercise` reuses `Exercise.toMap()/fromMap()` plus `sets/reps/restSeconds`.
- **Firestore layer** — `lib/services/firestore_service.dart`: add `saveWorkoutPlan(uid, weekId, List<WorkoutDay>)` and `getWorkoutPlan(uid, weekId)` against a new subcollection `users/{uid}/workout_plans/{weekId}` (one doc per ISO week, keyed like `WorkoutLog.weekId`). Add a matching per-user rule in `firestore.rules` (mirror the existing `food_logs`/`workout_logs` rules). No composite index needed (fetched by doc ID).
- **PlanProvider** — `lib/providers/plan_provider.dart`:
  - `setWorkoutPlan(plan, {persist})` → persist when true.
  - `loadWorkoutPlan(uid, weekId)` → hydrate from Firestore if present.
  - Edit methods that mutate `_workoutPlan`, `notifyListeners()`, and persist: `replaceExercise(dayIdx, exIdx, Exercise)`, `removeExercise(dayIdx, exIdx)`, `addExercise(dayIdx, WorkoutExercise)`, `updateExerciseParams(dayIdx, exIdx, {sets, reps, rest})`.
- **Plans screen UI** — `lib/screens/plans_screen.dart`:
  - In `_generate()` (lines 207–253): first try `loadWorkoutPlan(uid, currentWeekId)`; only generate + persist if none exists.
  - Per day card (`_buildWorkoutDay`, lines 538–666): add an **edit mode** — per-exercise edit (sets/reps/rest dialog) + delete, and an **Add exercise** button opening a picker.
  - Exercise picker: bottom sheet listing the already-loaded exercises filtered by that day's `_focusToMuscles`; selecting calls `PlanProvider.addExercise/replaceExercise`. Reuse the existing exercise-card visuals.

### 2.3 Adaptation engine — `lib/algorithms/adaptation_engine.dart`
- Extend `compute(...)` with an optional `avgHoursSlept` param: when under-slept (e.g. < 6.5h), hold `difficultyBias` at `'same'`/`'down'` even on high completion, and add a recovery note. Backward-compatible via default.

### 2.4 Progress — `lib/providers/progress_provider.dart` (+ `progress_screen.dart`)
- Add `int get plannedWorkoutDays => _profile?.workoutDaysPerWeek ?? 3` and compute `workoutCompletion = completedThisWeek / plannedWorkoutDays` (denominator now real, not guessed). This feeds the adaptation call.
- Optionally surface avg sleep + "days trained vs target" on the progress screen.
- `calorieGoal`/`proteinGoal` getters already read `_profile` — they automatically reflect the new activity-driven calories; no change needed.

---

## Migration / compatibility
Old user docs lack the new keys; `fromMap` defaults cover them. The one behavioral shift: `activityMultiplier` now uses `activityLevel` (default *Moderately Active* = 1.55) instead of the experience proxy, so some existing users' calorie goals move slightly. Acceptable; consider a one-time "review your profile" nudge.

## Verification
- `flutter analyze` — zero new errors after each phase.
- `flutter run -d windows` (fast desktop loop):
  - **Register**: name field gone; mismatched confirm → error; matching → account created.
  - **Onboarding**: 5 new inputs render and save (verify in Firestore console or by reopening profile editor).
  - **Calories**: changing activity level changes the calorie goal on Home/Progress.
  - **Plans**: generate → edit a day (swap / add / remove / change sets) → hot-restart → edits persisted from Firestore.
  - **Schedule**: changing split/days/session-minutes in the profile yields a visibly different weekly plan and per-day exercise count.
  - **Progress**: weekly completion uses the planned-days denominator.
- After Phase 2: `firebase deploy --only firestore --project onefit-392b8` (new `workout_plans` rule).

## Critical files
- `lib/screens/register_screen.dart` — auth-only form + validation
- `lib/models/user_profile.dart` — 5 new fields, activity-driven `activityMultiplier`, `recoveryScore`
- `lib/screens/profile_input_screen.dart` / `lib/screens/profile_screen.dart` — collect/edit new inputs
- `lib/algorithms/greedy_algorithm.dart` — split+days schedule, session-driven exercise count, recovery
- `lib/providers/plan_provider.dart` + `lib/services/firestore_service.dart` — persist + edit plans
- `lib/screens/plans_screen.dart` — editable day UI + exercise picker
- `lib/algorithms/adaptation_engine.dart`, `lib/providers/progress_provider.dart` — sleep/recovery + real completion
- `firestore.rules` — `workout_plans` subcollection rule
