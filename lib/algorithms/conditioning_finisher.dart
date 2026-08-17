import '../models/exercise.dart';
import '../models/user_profile.dart';
import 'greedy_algorithm.dart';

/// Appends a single conditioning "finisher" as the LAST exercise of each
/// training day for the metabolic goals (Weight Loss / Endurance).
///
/// This is a **post-generation** layer deliberately kept OUTSIDE
/// [GreedyAlgorithm]: the greedy scorer/selection is untouched, and this only
/// reuses the public eligibility gates ([GreedyAlgorithm.isEligibleForUser] /
/// [GreedyAlgorithm.difficultyAllowed]) so the finisher honours the same hard
/// constraints as generation (physical limitations, equipment, location,
/// experience). It exists because the goal barely differentiates *selection*
/// otherwise — a metabolic goal now visibly ends each day with conditioning.
class ConditioningFinisher {
  const ConditioningFinisher._();

  static const _metabolicGoals = {'Weight Loss', 'Endurance'};

  /// Built-in treadmill used as the Gym finisher when the ExerciseDB catalog has
  /// no treadmill exercise. The gif is a verified asset on the same jsDelivr CDN
  /// (`JahelCuadrado/ExerciseGymGifsDB@v1.2.0`) that `ExerciseDBService` streams
  /// all exercise gifs from, so it renders through the existing `_gifImage`
  /// network path with no extra wiring.
  static final Exercise _builtInTreadmill = Exercise(
    id: 'onefit_treadmill',
    name: 'Treadmill',
    category: 'cardio',
    primaryMuscles: const ['cardiovascular system'],
    secondaryMuscles: const [],
    equipment: const ['gym'],
    difficulty: 'beginner',
    goals: const ['endurance', 'weight_loss'],
    locations: const ['gym'],
    instructions:
        'Steady-state incline treadmill walk/jog at a comfortable, sustainable '
        'pace for the full duration.',
    gifUrl:
        'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.2.0/'
        'cardio/walking-on-incline-treadmill.gif',
  );

  /// Returns a new plan with one conditioning finisher appended (last) to each
  /// non-rest, non-cardio training day — only for metabolic goals. For every
  /// other goal (or an empty pool / no eligible conditioning move) the plan is
  /// returned unchanged. Pure; never mutates the input days.
  static List<WorkoutDay> apply(
    List<WorkoutDay> plan,
    UserProfile profile,
    List<Exercise> pool,
  ) {
    if (!_metabolicGoals.contains(profile.fitnessGoal) || pool.isEmpty) {
      return plan;
    }

    bool eligible(Exercise e) =>
        GreedyAlgorithm.isEligibleForUser(e, profile) &&
        GreedyAlgorithm.difficultyAllowed(
          e.difficulty,
          profile.experienceLevel,
        );

    // Gym users get a single steady-state treadmill finisher (15 min) on every
    // training day. Reuse whatever treadmill is already in the ExerciseDB cache
    // (its gif is cache-verified) rather than seeding one. Home users fall
    // through to the bodyweight conditioning pool below (a gym-located treadmill
    // is not eligible for them anyway).
    Exercise? treadmill;
    if (profile.workoutLocation == 'Gym') {
      for (final e in pool) {
        if (e.name.toLowerCase().contains('treadmill') && eligible(e)) {
          treadmill = e;
          break;
        }
      }
      // The ExerciseDB catalog has no treadmill entry, so fall back to a built-in
      // one whose gif is a verified asset on the SAME jsDelivr CDN the app already
      // streams every gif from — no reseed, no external host. Still gated by
      // eligibility so limitations (e.g. asthma cardio-avoidance) can exclude it.
      treadmill ??= eligible(_builtInTreadmill) ? _builtInTreadmill : null;
    }
    if (treadmill != null) {
      final out = <WorkoutDay>[];
      for (final day in plan) {
        if (day.isRest ||
            _isConditioningFocus(day.focus) ||
            day.exercises.any((w) => w.exercise.id == treadmill!.id)) {
          out.add(day);
          continue;
        }
        out.add(
          WorkoutDay(
            dayName: day.dayName,
            focus: day.focus,
            isRest: day.isRest,
            exercises: [...day.exercises, _treadmillFinisher(treadmill)],
          ),
        );
      }
      return out;
    }

    // Eligible conditioning pool. The `endurance` goal-tag is added by
    // _inferGoals ONLY for cardio/run/jump moves (not abs/calves), so it is a
    // precise metabolic filter; `category == 'cardio'` catches the rest. Gated
    // by the same hard eligibility as generation, so limitations (e.g. knee
    // pain → no jump/plyo finisher) are respected automatically.
    final conditioning =
        pool
            .where(
              (e) =>
                  (e.category.toLowerCase() == 'cardio' ||
                      e.goals.contains('endurance')) &&
                  eligible(e),
            )
            .toList()
          // Deterministic order for a stable, varied round-robin across days.
          ..sort((a, b) => a.id.compareTo(b.id));

    if (conditioning.isEmpty) return plan;

    var cursor = 0;
    final out = <WorkoutDay>[];
    for (final day in plan) {
      if (day.isRest || _isConditioningFocus(day.focus)) {
        out.add(day);
        continue;
      }
      final present = day.exercises.map((w) => w.exercise.id).toSet();

      // Round-robin from the cursor to the next move not already in the day, so
      // finishers vary across the week without repeating within a day.
      Exercise? pick;
      for (int i = 0; i < conditioning.length; i++) {
        final cand = conditioning[(cursor + i) % conditioning.length];
        if (!present.contains(cand.id)) {
          pick = cand;
          cursor = (cursor + i + 1) % conditioning.length;
          break;
        }
      }
      if (pick == null) {
        out.add(day); // every conditioning move already present — leave as-is
        continue;
      }

      out.add(
        WorkoutDay(
          dayName: day.dayName,
          focus: day.focus,
          isRest: day.isRest,
          exercises: [...day.exercises, _finisherFor(pick)],
        ),
      );
    }
    return out;
  }

  static bool _isConditioningFocus(String focus) {
    final f = focus.toLowerCase();
    return f.contains('cardio') || f.contains('conditioning');
  }

  /// A conditioning prescription: timed for cardio moves, high-rep otherwise.
  static WorkoutExercise _finisherFor(Exercise e) {
    final timed = e.category.toLowerCase() == 'cardio';
    return WorkoutExercise(
      exercise: e,
      sets: 3,
      reps: timed ? '45 sec' : '15-20',
      restSeconds: 45,
      timePerSetSeconds: 45,
    );
  }

  /// The Gym treadmill finisher — one continuous 15-minute steady-state block.
  static WorkoutExercise _treadmillFinisher(Exercise e) => WorkoutExercise(
    exercise: e,
    sets: 1,
    reps: '15 min',
    restSeconds: 0,
    timePerSetSeconds: 900, // 15-minute work timer
  );
}
