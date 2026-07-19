import '../models/exercise.dart';

/// A common, user-selectable physical limitation and the exercise patterns it
/// contraindicates. Pure data + matching logic — no Flutter/Firebase — so both
/// the greedy generator and the profiling UI can import it.
///
/// Blocks are intentionally **narrow** (specific movements, matched by category,
/// primary muscle, or name keyword) so selecting a limitation never empties a
/// whole training day — it removes higher-risk moves, not entire muscle groups.
///
/// This is a conservative auto-filter, **not medical advice**. Each entry cites a
/// review-of-related-literature (RRL) source in [rrlUrl] for traceability; the
/// links are reference-only and are not shown in the app.
class PhysicalLimitation {
  final String id; // stored value + chip label, e.g. 'Asthma'
  final String note; // short rationale (reference only)
  final String rrlUrl; // research citation (reference only, not displayed)
  final Set<String> categories; // exercise.category values to block (lowercase)
  final Set<String> muscles; // primaryMuscle strings to block (lowercase)
  final List<String> keywords; // exercise-name substrings to block (lowercase)

  const PhysicalLimitation({
    required this.id,
    required this.note,
    required this.rrlUrl,
    this.categories = const {},
    this.muscles = const {},
    this.keywords = const [],
  });
}

/// The supported set of common limitations. Order = chip display order.
const List<PhysicalLimitation> kPhysicalLimitations = [
  PhysicalLimitation(
    id: 'Asthma',
    note:
        'Avoids sustained high-intensity cardio, which can trigger '
        'exercise-induced bronchoconstriction.',
    rrlUrl: 'https://pmc.ncbi.nlm.nih.gov/articles/PMC12186601/',
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
  ),
  PhysicalLimitation(
    id: 'Knee injury/pain',
    note:
        'Avoids high-impact and deep-knee-flexion moves that spike joint load.',
    rrlUrl: 'https://pmc.ncbi.nlm.nih.gov/articles/PMC3635671/',
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
  ),
  PhysicalLimitation(
    id: 'Lower-back pain',
    note: 'Avoids heavy axial spinal loading and end-range flexion.',
    rrlUrl: 'https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10687566/',
    keywords: [
      'deadlift',
      'good morning',
      'good-morning',
      'bent over',
      'bent-over',
      'back extension',
      'hyperextension',
      'sit-up',
      'situp',
      'russian twist',
      'toe touch',
    ],
  ),
  PhysicalLimitation(
    id: 'Shoulder injury',
    note: 'Avoids overhead pressing and impingement-prone positions.',
    rrlUrl: 'https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10880378/',
    keywords: [
      'overhead press',
      'military press',
      'shoulder press',
      'upright row',
      'behind the neck',
      'behind neck',
      'arnold press',
      'triceps dip',
      'bench dip',
      'chest dip',
    ],
  ),
  PhysicalLimitation(
    id: 'High blood pressure',
    note:
        'Avoids sustained isometric holds and max-effort straining that spike '
        'blood pressure (Valsalva).',
    rrlUrl: 'https://www.ahajournals.org/doi/10.1161/01.cir.101.7.828',
    keywords: [
      'isometric',
      'plank',
      'wall sit',
      'wall-sit',
      'dead hang',
      'static hold',
      'iso hold',
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

/// True if [e] is contraindicated by any of the user's selected
/// [limitationIds]. Empty list → always false (no filtering, i.e. every
/// existing user is unaffected).
bool exerciseBlockedByLimitations(Exercise e, List<String> limitationIds) {
  if (limitationIds.isEmpty) return false;
  final name = e.name.toLowerCase();
  final cat = e.category.toLowerCase();
  final primary = e.primaryMuscles.map((m) => m.toLowerCase()).toList();
  for (final id in limitationIds) {
    final lim = limitationById(id);
    if (lim == null) continue;
    if (lim.categories.contains(cat)) return true;
    if (primary.any(lim.muscles.contains)) return true;
    if (lim.keywords.any(name.contains)) return true;
  }
  return false;
}
