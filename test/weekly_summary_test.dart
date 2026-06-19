// Verifies the WeeklySummary snapshot model: toMap/fromMap round-trip and the
// adjustmentBadge derivation used by the Weekly Review history list.
//
// Pure Dart aside from the Timestamp wrapper, so it runs with
// `flutter test test/weekly_summary_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/models/weekly_summary.dart';

WeeklySummary make({
  int calorieBias = 0,
  String difficultyBias = 'same',
  bool volumeChanged = false,
  int oldProtein = 150,
  int newProtein = 150,
}) =>
    WeeklySummary(
      weekId: 'week_2026_25',
      generatedAt: DateTime(2026, 6, 15, 8),
      weekStart: DateTime(2026, 6, 15),
      weekEnd: DateTime(2026, 6, 21),
      calorieAdherence: 82.5,
      proteinAdherence: 70.0,
      workoutsCompleted: 4,
      workoutsPlanned: 5,
      avgRating: 2.0,
      daysLogged: 6,
      calorieBias: calorieBias,
      oldCalorieGoal: 2238,
      newCalorieGoal: 2238 + calorieBias,
      oldProtein: oldProtein,
      newProtein: newProtein,
      oldCarbs: 250,
      newCarbs: 270,
      oldFat: 70,
      newFat: 72,
      difficultyBias: difficultyBias,
      volumeChanged: volumeChanged,
      notes: 'Test reasoning.',
    );

void main() {
  group('toMap / fromMap round-trip', () {
    test('preserves all fields including nullables', () {
      final s = make(calorieBias: 100, difficultyBias: 'up', volumeChanged: true);
      final r = WeeklySummary.fromMap(s.toMap(), s.weekId);

      expect(r.weekId, s.weekId);
      expect(r.weekStart, s.weekStart);
      expect(r.weekEnd, s.weekEnd);
      expect(r.calorieAdherence, s.calorieAdherence);
      expect(r.proteinAdherence, s.proteinAdherence);
      expect(r.workoutsCompleted, s.workoutsCompleted);
      expect(r.workoutsPlanned, s.workoutsPlanned);
      expect(r.avgRating, s.avgRating);
      expect(r.daysLogged, s.daysLogged);
      expect(r.calorieBias, s.calorieBias);
      expect(r.newCalorieGoal, s.newCalorieGoal);
      expect(r.difficultyBias, s.difficultyBias);
      expect(r.volumeChanged, s.volumeChanged);
      expect(r.notes, s.notes);
    });

    test('null proteinAdherence / avgRating survive', () {
      final s = WeeklySummary(
        weekId: 'week_2026_26',
        generatedAt: DateTime(2026, 6, 22),
        weekStart: DateTime(2026, 6, 22),
        weekEnd: DateTime(2026, 6, 28),
        calorieAdherence: 0,
        proteinAdherence: null,
        workoutsCompleted: 0,
        workoutsPlanned: 3,
        avgRating: null,
        daysLogged: 0,
        calorieBias: 0,
        oldCalorieGoal: 2000,
        newCalorieGoal: 2000,
        oldProtein: 150,
        newProtein: 150,
        oldCarbs: 200,
        newCarbs: 200,
        oldFat: 60,
        newFat: 60,
        difficultyBias: 'same',
        volumeChanged: false,
        notes: '',
      );
      final r = WeeklySummary.fromMap(s.toMap(), s.weekId);
      expect(r.proteinAdherence, isNull);
      expect(r.avgRating, isNull);
    });
  });

  group('adjustmentBadge', () {
    test('calorie increase wins', () {
      expect(make(calorieBias: 100).adjustmentBadge, 'Increased Calories');
    });

    test('calorie decrease wins', () {
      expect(make(calorieBias: -100).adjustmentBadge, 'Reduced Calories');
    });

    test('intensity up only when volume actually changed', () {
      expect(
        make(difficultyBias: 'up', volumeChanged: true).adjustmentBadge,
        'Increased Intensity',
      );
      // Clamp-absorbed step (no real change) → Stable, not Increased Intensity.
      expect(
        make(difficultyBias: 'up', volumeChanged: false).adjustmentBadge,
        'Stable',
      );
    });

    test('intensity down when volume changed', () {
      expect(
        make(difficultyBias: 'down', volumeChanged: true).adjustmentBadge,
        'Reduced Intensity',
      );
    });

    test('calorie change takes priority over intensity', () {
      expect(
        make(calorieBias: 100, difficultyBias: 'down', volumeChanged: true)
            .adjustmentBadge,
        'Increased Calories',
      );
    });

    test('no change → Stable', () {
      expect(make().adjustmentBadge, 'Stable');
    });
  });

  group('macro deltas', () {
    test('derived from old/new', () {
      final s = make(oldProtein: 150, newProtein: 160);
      expect(s.proteinDelta, 10);
      expect(s.carbsDelta, 20);
      expect(s.fatDelta, 2);
    });
  });
}
