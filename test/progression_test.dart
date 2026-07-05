// Per-set progression suggester (double progression generalized to the full
// set list), plus the legacy single-target `nextTarget` it builds on.
//
// Pure Dart — runs with `flutter test test/progression_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/algorithms/progression.dart';
import 'package:onefit/models/workout_log.dart';

void main() {
  group('nextSetTargets — loaded (double progression)', () {
    test('every set at top of range → add load, reset reps to min', () {
      final out = nextSetTargets(
        lastSets: const [
          SetEntry(weightKg: 40, reps: 12),
          SetEntry(weightKg: 40, reps: 12),
        ],
        repRange: '8-12',
        isLowerOrCompound: false, // isolation → +2.5
      );
      expect(out.length, 2);
      expect(out.every((s) => s.weightKg == 42.5), isTrue);
      expect(out.every((s) => s.reps == 8), isTrue);
    });

    test('compound lift steps load by +5', () {
      final out = nextSetTargets(
        lastSets: const [SetEntry(weightKg: 100, reps: 12)],
        repRange: '8-12',
        isLowerOrCompound: true,
      );
      expect(out.single.weightKg, 105);
      expect(out.single.reps, 8);
    });

    test('a missed set holds the weight and nudges reps up', () {
      final out = nextSetTargets(
        lastSets: const [
          SetEntry(weightKg: 40, reps: 12),
          SetEntry(weightKg: 40, reps: 10), // missed the top → no load bump
        ],
        repRange: '8-12',
        isLowerOrCompound: false,
      );
      expect(out.every((s) => s.weightKg == 40), isTrue);
      expect(out[0].reps, 12); // already at top, stays clamped
      expect(out[1].reps, 11); // +1 toward the top
    });
  });

  group('nextSetTargets — bodyweight (reps only)', () {
    test('progresses reps toward the cap', () {
      final out = nextSetTargets(
        lastSets: const [SetEntry(reps: 15), SetEntry(reps: 15)],
        repRange: '10-20',
        isLowerOrCompound: false,
      );
      expect(out.length, 2);
      expect(out.every((s) => s.weightKg == null), isTrue);
      expect(out.every((s) => s.reps == 16), isTrue);
    });

    test('at the rep cap → add a set', () {
      final out = nextSetTargets(
        lastSets: const [SetEntry(reps: 20), SetEntry(reps: 20)],
        repRange: '10-20',
        isLowerOrCompound: false,
        bodyweightRepCap: 20,
      );
      expect(out.length, 3); // extra set added
      expect(out.last.reps, 10); // new set starts at range min
    });
  });

  group('nextSetTargets — timed', () {
    test('non-numeric prescription progresses seconds', () {
      final out = nextSetTargets(
        lastSets: const [SetEntry(seconds: 30)],
        repRange: '30 sec',
        isLowerOrCompound: false,
      );
      expect(out.single.seconds, 35);
    });

    test('respects the time cap', () {
      final out = nextSetTargets(
        lastSets: const [SetEntry(seconds: 90)],
        repRange: 'AMRAP',
        isLowerOrCompound: false,
        timedCap: 90,
      );
      expect(out.single.seconds, 90);
    });
  });

  test('no history → empty (Week 1 leaves inputs blank)', () {
    expect(
      nextSetTargets(lastSets: const [], repRange: '8-12', isLowerOrCompound: true),
      isEmpty,
    );
  });
}
