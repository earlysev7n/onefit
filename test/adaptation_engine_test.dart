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
}
