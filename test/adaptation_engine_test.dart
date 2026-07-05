// Verifies the weight-trend modifier added to AdaptationEngine (Option B).
//
// The engine is pure Dart, so this runs with
// `flutter test test/adaptation_engine_test.dart`.
//
// Contract under test:
//  * Weight signal nudges calories ±100 ONLY when adherence didn't already
//    move them (non-stacking) and only for directional goals.
//  * <2 weigh-ins (weightChangeKg == null) leaves behavior unchanged.
import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/adaptation_engine.dart';

void main() {
  final engine = AdaptationEngine();

  // Adherence in the neutral band [85, 110] so it never sets a calorie bias
  // on its own — isolates the weight modifier.
  AdaptationResult run({
    double adherence = 100,
    double completion = 0.7,
    double? weightChangeKg,
    String fitnessGoal = 'General Fitness',
  }) =>
      engine.compute(
        lastWeekCalorieAdherence: adherence,
        lastWeekWorkoutCompletion: completion,
        currentExperienceLevel: 'Intermediate',
        weightChangeKg: weightChangeKg,
        fitnessGoal: fitnessGoal,
      );

  group('weight-trend modifier', () {
    test('Weight Loss + flat weight → −100 kcal', () {
      expect(run(weightChangeKg: 0.0, fitnessGoal: 'Weight Loss').calorieBiasKcal,
          -100);
    });

    test('Weight Loss + losing too fast → +100 kcal (protect muscle)', () {
      expect(
          run(weightChangeKg: -1.5, fitnessGoal: 'Weight Loss').calorieBiasKcal,
          100);
    });

    test('Weight Loss + healthy loss → no change', () {
      expect(
          run(weightChangeKg: -0.5, fitnessGoal: 'Weight Loss').calorieBiasKcal,
          0);
    });

    test('Muscle Gain + flat weight → +100 kcal', () {
      expect(
          run(weightChangeKg: 0.0, fitnessGoal: 'Muscle Gain').calorieBiasKcal,
          100);
    });

    test('Muscle Gain + gaining too fast → −100 kcal (stay lean)', () {
      expect(
          run(weightChangeKg: 1.0, fitnessGoal: 'Muscle Gain').calorieBiasKcal,
          -100);
    });

    test('General Fitness ignores weight (maintenance)', () {
      expect(
          run(weightChangeKg: 2.0, fitnessGoal: 'General Fitness').calorieBiasKcal,
          0);
    });

    test('null weight delta → unchanged behavior', () {
      expect(run(weightChangeKg: null, fitnessGoal: 'Weight Loss').calorieBiasKcal,
          0);
    });

    test('non-stacking: adherence bias suppresses weight signal', () {
      // Under-eating already triggers +100; a flat-weight loss goal would push
      // −100, but must be ignored so the two signals never fight.
      final r = run(
        adherence: 70, // < 85 → adherence sets +100
        weightChangeKg: 0.0, // would otherwise push −100
        fitnessGoal: 'Weight Loss',
      );
      expect(r.calorieBiasKcal, 100);
    });
  });

  // ── W4: over-target but successfully losing → don't cut further ────────────
  group('W4 over-target weight-loss guard', () {
    test('over target + Weight Loss + real loss → no cut (held)', () {
      final r = run(
        adherence: 120, // > 110 → would normally set −100
        weightChangeKg: -0.5, // actually losing
        fitnessGoal: 'Weight Loss',
      );
      expect(r.calorieBiasKcal, 0);
    });

    test('over target + Weight Loss + not losing → still cut −100', () {
      final r = run(
        adherence: 120,
        weightChangeKg: 0.0, // not losing
        fitnessGoal: 'Weight Loss',
      );
      expect(r.calorieBiasKcal, -100);
    });

    test('over target + non-loss goal → still cut −100', () {
      final r = run(
        adherence: 120,
        weightChangeKg: -0.5,
        fitnessGoal: 'General Fitness',
      );
      expect(r.calorieBiasKcal, -100);
    });
  });

  // ── Difficulty / RPE vote aggregation ─────────────────────────────────────
  AdaptationResult diff({
    double completion = 0.7,
    List<int> ratings = const [],
    String level = 'Intermediate',
  }) =>
      engine.compute(
        lastWeekCalorieAdherence: 100, // neutral
        lastWeekWorkoutCompletion: completion,
        currentExperienceLevel: level,
        lastWeekRatings: ratings,
      );

  group('vote aggregation — worked combos (completion 0.7)', () {
    test('[3,4,2,3] → hold', () {
      expect(diff(ratings: [3, 4, 2, 3]).difficultyBias, 'same');
    });
    test('[2,2,3,2] → up', () {
      expect(diff(ratings: [2, 2, 3, 2]).difficultyBias, 'up');
    });
    test('[3,4,4,5] → down', () {
      expect(diff(ratings: [3, 4, 4, 5]).difficultyBias, 'down');
    });
    test('[2,2,5,2] → hold (a single too-hard caps the step-up)', () {
      expect(diff(ratings: [2, 2, 5, 2]).difficultyBias, 'same');
    });
  });

  group('W1 too-hard feedback eases volume', () {
    test('completing fine but week felt hard → down', () {
      expect(diff(completion: 0.6, ratings: [4, 5]).difficultyBias, 'down');
    });

    test('high completion but all-hard → eased down', () {
      // 0.9 completion would step up; a strongly hard week (sum ≤ −2) eases.
      expect(diff(completion: 0.9, ratings: [4, 4, 4]).difficultyBias, 'down');
    });

    test('high completion + one too-hard session → step-up cancelled to same', () {
      // [1,5] nets 0 but the "too hard" (5) safety-blocks the completion step-up.
      expect(diff(completion: 0.9, ratings: [1, 5]).difficultyBias, 'same');
    });

    test('struggling + too hard → stays down', () {
      expect(diff(completion: 0.3, ratings: [5, 5]).difficultyBias, 'down');
    });
  });

  group('W3 easy-rating up-gate tightened to 0.7', () {
    test('partial-skipper (0.6) rated easy → NOT bumped up', () {
      expect(diff(completion: 0.6, ratings: [1, 1]).difficultyBias, 'same');
    });

    test('adhered (0.75) rated easy → bumped up', () {
      expect(diff(completion: 0.75, ratings: [2, 2]).difficultyBias, 'up');
    });

    test('struggling but rated easy → still down (safety wins)', () {
      expect(diff(completion: 0.3, ratings: [1, 1]).difficultyBias, 'down');
    });
  });

  // ── N1: protein shortfall note ────────────────────────────────────────────
  group('N1 low-protein note', () {
    test('calories met but protein low → note emitted', () {
      final r = engine.compute(
        lastWeekCalorieAdherence: 100,
        lastWeekWorkoutCompletion: 0.7,
        currentExperienceLevel: 'Intermediate',
        lastWeekProteinAdherence: 60,
      );
      expect(r.notes.toLowerCase(), contains('protein'));
    });

    test('protein adherence null → no protein note', () {
      final r = engine.compute(
        lastWeekCalorieAdherence: 100,
        lastWeekWorkoutCompletion: 0.7,
        currentExperienceLevel: 'Intermediate',
        lastWeekProteinAdherence: null,
      );
      expect(r.notes.toLowerCase(), isNot(contains('protein')));
    });
  });
}
