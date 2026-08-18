import '../models/exercise.dart';

/// A specific movement mapped to a [PhysicalLimitation]. When the parent area is
/// selected these are always excluded (they used to be an opt-in checklist).
/// [keywords] are lowercase exercise-name substrings to block. [common] is
/// retained for back-compat but no longer drives any UI.
class AvoidableMovement {
  final String id; // display label, e.g. 'Barbell Squat'
  final List<String> keywords; // lowercase name substrings to block
  final bool common; // legacy: previously surfaced in the picker sheet

  const AvoidableMovement(this.id, this.keywords, {this.common = false});
}

/// A common, user-selectable physical limitation / affected area and the
/// exercise patterns it contraindicates. Pure data + matching logic — no
/// Flutter/Firebase — so both the greedy generator and the profiling UI can
/// import it.
///
/// **One always-on layer.** Selecting an area blocks its full mapping — the
/// auto-block set ([categories]/[muscles]/[keywords]) **and** every mapped
/// [movements] entry (previously an opt-in checklist, now always applied). This
/// is a hard filter during generation ("won't generate these"); the exercise
/// picker instead surfaces a soft **"Add Anyway"** warning so the user can
/// override for a specific move. Movement-heavy areas (Knee/Lower-Back/Hip) can
/// therefore thin a training day — accepted, since the generator degrades
/// gracefully (assist-mover + bodyweight fallback) and never empties a day.
///
/// This is a conservative auto-filter, **not medical advice**.
class PhysicalLimitation {
  final String id; // stored value + chip label, e.g. 'Shoulder Pain'
  final String note; // short rationale (reference only)
  final Set<String> categories; // exercise.category values to block (lowercase)
  final Set<String> muscles; // primaryMuscle strings to block (lowercase)
  final List<String> keywords; // auto-block exercise-name substrings (lowercase)
  final List<AvoidableMovement> movements; // opt-in checklist
  // When true, the area is not only a hard EXCLUSION filter but also a
  // conservative PRESCRIPTION modifier layered on top of the fitness goal:
  // slightly fewer sets, longer rest, and no high-intensity conditioning
  // finisher. Reps are never touched (they stay goal-driven). See
  // [limitationsReduceIntensity] and greedy_algorithm `_getSets`/`_getRestSeconds`.
  final bool intensityCaution;

  const PhysicalLimitation({
    required this.id,
    required this.note,
    this.categories = const {},
    this.muscles = const {},
    this.keywords = const [],
    this.movements = const [],
    this.intensityCaution = false,
  });
}

/// The supported set of common limitations. Order = chip display order.
const List<PhysicalLimitation> kPhysicalLimitations = [
  PhysicalLimitation(
    id: 'Asthma',
    note:
        'Avoids sustained high-intensity cardio, which can trigger '
        'exercise-induced bronchoconstriction. Also flagged for conservative '
        'dosing (fewer sets, longer rest, no high-intensity finisher) so effort '
        'stays sustainable.',
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
    intensityCaution: true,
  ),
  PhysicalLimitation(
    id: 'High Blood Pressure',
    // Beyond excluding Valsalva-heavy work, this area also drives a conservative
    // prescription modifier (slightly fewer sets, longer rest between sets, and
    // no high-intensity conditioning finisher; reps stay goal-driven). This
    // dosing is OUR conservative implementation choice informed by — not a
    // verbatim protocol prescribed by — the following, which collectively support
    // conservative progression, appropriate resistance-training volume, and
    // longer recovery intervals for hypertensive trainees:
    //   • ACSM Hypertension FITT recommendations:
    //     https://www.acsm.org/wp-content/uploads/2025/01/fitt-recommendations-for-hypertension_update.pdf
    //   • ACSM — Exercise for the Prevention and Treatment of Hypertension:
    //     https://acsm.org/exercise-for-the-prevention-and-treatment-of-hypertension/
    //   • Rest-interval study (PubMed): https://pubmed.ncbi.nlm.nih.gov/36196336/
    note:
        'Avoids sustained isometric holds and max-effort straining that spike '
        'blood pressure (Valsalva). Also flagged for conservative dosing '
        '(fewer sets, longer rest, no high-intensity finisher).',
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
    intensityCaution: true,
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

/// True if any selected area warrants conservative dosing (slightly fewer sets,
/// longer rest, no high-intensity finisher) layered ON TOP of the fitness goal.
/// Currently Asthma + High Blood Pressure. Reps are never modified here.
bool limitationsReduceIntensity(List<String> areaIds) {
  for (final id in areaIds) {
    if (limitationById(id)?.intensityCaution ?? false) return true;
  }
  return false;
}

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

/// True if [e] is contraindicated by any of the user's selected areas
/// ([areaIds]). Each selected area blocks its auto-block set
/// (`categories`/`muscles`/`keywords`) **and** every one of its mapped
/// `movements` — the whole limitation, always on. Empty [areaIds] → false (no
/// filtering, i.e. every existing user is unaffected).
bool exerciseBlockedByLimitations(Exercise e, List<String> areaIds) {
  return _blockingArea(e, areaIds) != null;
}

/// Returns the id of the first selected area that contraindicates [e] (e.g.
/// `'Shoulder Pain'`), or null if none — used for the "Add Anyway" warning copy.
String? limitationReasonFor(Exercise e, List<String> areaIds) =>
    _blockingArea(e, areaIds);

/// Shared matcher: the id of the first area in [areaIds] whose auto-block set or
/// mapped movements match [e]; null if none.
String? _blockingArea(Exercise e, List<String> areaIds) {
  if (areaIds.isEmpty) return null;
  final name = e.name.toLowerCase();
  final cat = e.category.toLowerCase();
  final primary = e.primaryMuscles.map((m) => m.toLowerCase()).toList();

  for (final id in areaIds) {
    final lim = limitationById(id);
    if (lim == null) continue;
    if (lim.categories.contains(cat)) return id;
    if (primary.any(lim.muscles.contains)) return id;
    if (lim.keywords.any(name.contains)) return id;
    // Movements are now always-on for a selected area (no longer opt-in).
    for (final mv in lim.movements) {
      if (mv.keywords.any(name.contains)) return id;
    }
  }
  return null;
}
