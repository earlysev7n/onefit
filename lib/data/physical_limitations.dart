import '../models/exercise.dart';

/// A specific movement a user can opt to avoid for a given [PhysicalLimitation].
/// [keywords] are lowercase exercise-name substrings; [common] surfaces the
/// movement in the sheet's first ("Commonly Affected") tier.
class AvoidableMovement {
  final String id; // display label + stored value, e.g. 'Barbell Squat'
  final List<String> keywords; // lowercase name substrings to block
  final bool common; // shown before the "Show All Exercises" expander

  const AvoidableMovement(this.id, this.keywords, {this.common = false});
}

/// A common, user-selectable physical limitation / affected area and the
/// exercise patterns it contraindicates. Pure data + matching logic — no
/// Flutter/Firebase — so both the greedy generator and the profiling UI can
/// import it.
///
/// Two blocking layers:
///  1. **Auto-block** ([categories]/[muscles]/[keywords]) — always on when the
///     area is selected; a small set of unambiguously high-risk movements.
///  2. **Opt-in** ([movements]) — ambiguous movements the user personally
///     chooses to avoid via the profiling sheet; matched only when their id is
///     in the profile's `avoidedMovements`.
///
/// Blocks are intentionally **narrow** (specific movements, matched by category,
/// primary muscle, or name keyword) so selecting a limitation never empties a
/// whole training day — it removes higher-risk moves, not entire muscle groups.
///
/// This is a conservative auto-filter, **not medical advice**.
class PhysicalLimitation {
  final String id; // stored value + chip label, e.g. 'Shoulder Pain'
  final String note; // short rationale (reference only)
  final Set<String> categories; // exercise.category values to block (lowercase)
  final Set<String> muscles; // primaryMuscle strings to block (lowercase)
  final List<String> keywords; // auto-block exercise-name substrings (lowercase)
  final List<AvoidableMovement> movements; // opt-in checklist

  const PhysicalLimitation({
    required this.id,
    required this.note,
    this.categories = const {},
    this.muscles = const {},
    this.keywords = const [],
    this.movements = const [],
  });
}

/// The supported set of common limitations. Order = chip display order.
const List<PhysicalLimitation> kPhysicalLimitations = [
  PhysicalLimitation(
    id: 'Asthma',
    note:
        'Avoids sustained high-intensity cardio, which can trigger '
        'exercise-induced bronchoconstriction.',
    categories: {'cardio'},
    muscles: {'cardiovascular system'},
    keywords: [
      'burpee',
      'sprint',
      'jump rope',
      'jumping jack',
      'mountain climber',
      'high knee',
    ],
    movements: [
      AvoidableMovement('Battle Ropes', ['battle rope'], common: true),
      AvoidableMovement('Shuttle Run', ['shuttle run']),
    ],
  ),
  PhysicalLimitation(
    id: 'High Blood Pressure',
    note:
        'Avoids sustained isometric holds and max-effort straining that spike '
        'blood pressure (Valsalva).',
    keywords: [
      'isometric',
      'plank',
      'wall sit',
      'wall-sit',
      'dead hang',
      'static hold',
      'iso hold',
      'l-sit',
      'hollow hold',
      'superman hold',
    ],
    movements: [
      AvoidableMovement('Deadlift', ['deadlift'], common: true),
      AvoidableMovement("Farmer's Carry", ['farmer'], common: true),
      AvoidableMovement('Overhead Press', ['overhead press', 'military press']),
    ],
  ),
  PhysicalLimitation(
    id: 'Shoulder Pain',
    note: 'Avoids overhead pressing and impingement-prone positions.',
    keywords: [
      'overhead press',
      'military press',
      'shoulder press',
      'seated press',
      'push press',
      'upright row',
      'behind the neck',
      'behind neck',
      'arnold press',
      'pike push',
      'handstand',
      'triceps dip',
      'bench dip',
      'chest dip',
    ],
    movements: [
      AvoidableMovement('Lateral Raise', ['lateral raise'], common: true),
      AvoidableMovement('Front Raise', ['front raise'], common: true),
      AvoidableMovement(
        'Overhead Tricep Extension',
        ['overhead tricep', 'overhead triceps'],
      ),
      AvoidableMovement('Incline Press', ['incline press', 'incline bench']),
    ],
  ),
  PhysicalLimitation(
    id: 'Knee Pain',
    note:
        'Avoids high-impact and deep-knee-flexion moves that spike joint load.',
    keywords: [
      'jump',
      'plyo',
      'box jump',
      'pistol squat',
      'jumping lunge',
      'depth jump',
      'tuck jump',
      'sprint',
      'burpee',
    ],
    movements: [
      AvoidableMovement('Barbell Squat', ['barbell squat', 'back squat'],
          common: true),
      AvoidableMovement('Lunge', ['lunge'], common: true),
      AvoidableMovement('Leg Extension', ['leg extension'], common: true),
      AvoidableMovement('Front Squat', ['front squat']),
      AvoidableMovement('Bulgarian Split Squat', ['bulgarian split squat']),
      AvoidableMovement('Hack Squat', ['hack squat']),
      AvoidableMovement('Step-Up', ['step-up', 'step up']),
      AvoidableMovement('Sissy Squat', ['sissy squat']),
      AvoidableMovement('Wall Sit', ['wall sit', 'wall-sit']),
    ],
  ),
  PhysicalLimitation(
    id: 'Lower Back Pain',
    note: 'Avoids heavy axial spinal loading and end-range flexion.',
    keywords: [
      'sit-up',
      'situp',
      'russian twist',
      'toe touch',
    ],
    movements: [
      AvoidableMovement('Deadlift', ['deadlift'], common: true),
      AvoidableMovement('Barbell Squat', ['barbell squat', 'back squat'],
          common: true),
      AvoidableMovement('Good Morning', ['good morning', 'good-morning'],
          common: true),
      AvoidableMovement('Romanian Deadlift', ['romanian deadlift', 'rdl']),
      AvoidableMovement('Bent-Over Row', ['bent over', 'bent-over']),
      AvoidableMovement('Back Extension', ['back extension']),
      AvoidableMovement('Hyperextension', ['hyperextension']),
    ],
  ),
  PhysicalLimitation(
    id: 'Wrist Pain',
    note: 'Avoids loaded wrist extension and weight-bearing on the hands.',
    movements: [
      AvoidableMovement('Push-Up', ['push-up', 'push up'], common: true),
      AvoidableMovement('Barbell Curl', ['barbell curl'], common: true),
      AvoidableMovement('Plank', ['plank'], common: true),
      AvoidableMovement('Front Squat', ['front squat']),
      AvoidableMovement('Handstand Push-Up', ['handstand']),
      AvoidableMovement('Bench Press', ['bench press']),
    ],
  ),
  PhysicalLimitation(
    id: 'Elbow Pain',
    note: 'Avoids repeated elbow flexion/extension under load (epicondylitis).',
    movements: [
      AvoidableMovement('Skullcrusher', ['skullcrusher', 'skull crusher'],
          common: true),
      AvoidableMovement('Barbell Curl', ['barbell curl'], common: true),
      AvoidableMovement('Dips', ['dip'], common: true),
      AvoidableMovement('Close-Grip Bench Press', ['close-grip', 'close grip']),
      AvoidableMovement('Chin-Up', ['chin-up', 'chin up']),
      AvoidableMovement('Tricep Extension', ['tricep extension', 'triceps extension']),
    ],
  ),
  PhysicalLimitation(
    id: 'Hip Pain',
    note: 'Avoids deep hip flexion and heavy hinge loading.',
    movements: [
      AvoidableMovement('Deep Squat', ['deep squat'], common: true),
      AvoidableMovement('Deadlift', ['deadlift'], common: true),
      AvoidableMovement('Lunge', ['lunge'], common: true),
      AvoidableMovement('Bulgarian Split Squat', ['bulgarian split squat']),
      AvoidableMovement('Hip Thrust', ['hip thrust']),
      AvoidableMovement('Leg Press', ['leg press']),
    ],
  ),
  PhysicalLimitation(
    id: 'Ankle Pain',
    note: 'Avoids high-impact landing and loaded plantarflexion.',
    keywords: [
      'jump',
      'plyo',
      'box jump',
      'sprint',
    ],
    movements: [
      AvoidableMovement('Calf Raise', ['calf raise'], common: true),
      AvoidableMovement('Jump Rope', ['jump rope'], common: true),
      AvoidableMovement('Lunge', ['lunge']),
    ],
  ),
  PhysicalLimitation(
    id: 'Neck Pain',
    note: 'Avoids loaded neck extension/shrugging and overhead compression.',
    movements: [
      AvoidableMovement('Barbell Shrug', ['shrug'], common: true),
      AvoidableMovement('Upright Row', ['upright row'], common: true),
      AvoidableMovement('Behind-the-Neck Press',
          ['behind the neck', 'behind neck'], common: true),
      AvoidableMovement('Neck Curl', ['neck curl']),
      AvoidableMovement('Neck Extension', ['neck extension']),
    ],
  ),
];

/// Lookup by [id]; null if not a recognised limitation.
PhysicalLimitation? limitationById(String id) {
  for (final l in kPhysicalLimitations) {
    if (l.id == id) return l;
  }
  return null;
}

/// Lookup an [AvoidableMovement] by its id across every area; null if unknown.
AvoidableMovement? movementById(String id) {
  for (final l in kPhysicalLimitations) {
    for (final m in l.movements) {
      if (m.id == id) return m;
    }
  }
  return null;
}

/// True if [e] is contraindicated by either the user's selected areas
/// ([areaIds], auto-block) or their opted-in movements ([avoidedMovementIds]).
/// Empty inputs → false (no filtering, i.e. every existing user is unaffected).
bool exerciseBlockedByLimitations(
  Exercise e,
  List<String> areaIds,
  List<String> avoidedMovementIds,
) {
  if (areaIds.isEmpty && avoidedMovementIds.isEmpty) return false;
  final name = e.name.toLowerCase();
  final cat = e.category.toLowerCase();
  final primary = e.primaryMuscles.map((m) => m.toLowerCase()).toList();

  // Layer 1 — auto-block for each selected area.
  for (final id in areaIds) {
    final lim = limitationById(id);
    if (lim == null) continue;
    if (lim.categories.contains(cat)) return true;
    if (primary.any(lim.muscles.contains)) return true;
    if (lim.keywords.any(name.contains)) return true;
  }

  // Layer 2 — opt-in movements the user chose to avoid.
  for (final id in avoidedMovementIds) {
    final mv = movementById(id);
    if (mv == null) continue;
    if (mv.keywords.any(name.contains)) return true;
  }

  return false;
}
