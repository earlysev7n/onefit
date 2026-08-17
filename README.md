# OneFit

A Flutter fitness app that generates **personalized, adaptive workout and meal plans** from a user's body stats, goals, equipment, schedule, and dietary restrictions — then adapts both week over week based on what the user actually did.

Built with Firebase (Auth + Cloud Firestore), Provider state management, and free external APIs for exercise and nutrition data.

## Features

- **Workout plan generation (Greedy Algorithm)** — builds a 7-day schedule honoring the user's split, training days per week, session duration, experience level, location, and home equipment. Sets/reps/rest are pinned to NSCA goal-loading ranges; pinned "anchor lifts" are guaranteed a slot.
- **Meal generation (Genetic Algorithm)** — evolves ingredient portions over a USDA-seeded pool to hit per-meal calorie budgets and goal-derived macro splits, with hard dietary-restriction guarantees (Vegetarian/Vegan/Halal/Lactose-intolerant/Nut-free). Generates from your own picked ingredients (Option A) or automatically (Option B), with OpenAI-generated cooking instructions for review before logging.
- **Weekly adaptation (Adaptation Engine)** — reviews last week's calorie adherence, workout completion, per-session effort ratings, and weight trend; nudges the calorie goal (±100 kcal, once per week) and steps workout difficulty up/down with safety brakes. Each adaptation is snapshotted as a Weekly Adaptive Report.
- **Daily adaptive goal** — spreads the week's remaining calorie budget over the remaining days (clamped ±10%) so one heavy day doesn't derail the week.
- **Nutrition tracking** — USDA food search, barcode scanning (OpenFoodFacts), full macro + micronutrient logging, dietary-restriction filtering.
- **Per-set workout logging & progression** — logs actual sets/reps/weight, tracks last/PR top sets per exercise, and prefills next-session targets via double progression.
- **Progress dashboard** — calorie/weight/workout trends, streaks, weekly report history.

## Tech stack

| Layer | Choice |
|---|---|
| UI | Flutter (Android + Windows desktop), dark/light theme |
| State | Provider (`ThemeProvider`, `PlanProvider`, `ProgressProvider`, `ProfileProvider`) |
| Backend | Firebase Auth + Cloud Firestore |
| Algorithms | Pure-Dart Greedy (workouts), Genetic (meals), rule-based Adaptation Engine |
| APIs | ExerciseDB (exercises + GIFs), USDA FoodData Central, OpenFoodFacts, OpenAI (recipe text), Edamam |

## Getting started

1. **Install dependencies**
   ```bash
   flutter pub get
   ```
2. **Configure API keys** — create a `.env` file in the project root (gitignored) with:
   - `OPENAI_API_KEY` — recipe instruction generation
   - `USDA_API_KEY` — food search / ingredient seeding (free at fdc.nal.usda.gov)
   - `EDAMAM_APP_ID` / `EDAMAM_APP_KEY` — optional, future recipe features
3. **Firebase** — the project is wired to the `onefit-392b8` Firebase project (`lib/firebase_options.dart`). Deploy rules/indexes with:
   ```bash
   firebase deploy --only firestore --project onefit-392b8
   ```
4. **Run**
   ```bash
   flutter run              # Android (emulator running)
   flutter run -d windows   # Windows desktop
   ```

## Quality gates

```bash
flutter analyze   # must be free of errors/warnings
flutter test      # pure-Dart algorithm/model suites — must stay green
```

## Documentation

- `CLAUDE.md` — architecture reference (providers, algorithms, data layer, invariants)
- `SCREENS.md` — per-screen responsibilities, provider connections, and data flows
