/// Difficulty inference for ExerciseDB exercises.
///
/// Pure Dart — no Flutter/Firebase imports — so it can be exercised by a
/// standalone `dart run` script as well as by ExerciseDBService.
///
/// The ExerciseDB OSS API exposes no difficulty field (verified live:
/// `GET /api/v1/exercises` returns only exerciseId/name/gifUrl/bodyParts/
/// equipments/targetMuscles/secondaryMuscles/instructions), so difficulty is
/// inferred from the exercise name + equipment.
///
/// Policy: **default to 'beginner'** — most catalogued moves are
/// beginner-accessible, and the default keeps the beginner pool healthy under
/// GreedyAlgorithm's strict experience gate (tiers are nested:
/// beginner ⊂ intermediate ⊂ advanced, so only beginners could ever starve).
/// Genuinely harder movements are promoted up. Tier boundaries follow ACSM
/// progression guidance (Ratamess et al. 2009): novices → machines,
/// bodyweight, simple dumbbell moves; intermediates → free-weight compound
/// lifts and ballistic/plyometric work; advanced → olympic lifts and
/// high-skill gymnastic strength moves.
String inferExerciseDifficulty(String rawName, List<String> equipments) {
  // Normalise: lowercase, hyphens → spaces so 'pull-up' and 'pull up' match
  // the same keyword.
  final name = rawName.toLowerCase().replaceAll('-', ' ');
  final eq = equipments.map((e) => e.toLowerCase()).toList();

  bool has(String kw) => RegExp('\\b${RegExp.escape(kw)}').hasMatch(name);
  bool hasAny(List<String> kws) => kws.any(has);

  // Machine-assisted variants (assisted pull up, assisted dip, …) take most
  // of the load off — beginner-accessible by design. The name check matters
  // too: e.g. "lever assisted chin-up" carries 'leverage machine' equipment.
  if (eq.contains('assisted') || has('assisted')) return 'beginner';

  // Stretches are flexibility work, accessible at any level — even ones named
  // after hard strength moves ("iron cross stretch"). Exact word only, so
  // "stretched full planche push-up" still classifies as a strength move.
  if (RegExp(r'\bstretch\b').hasMatch(name)) return 'beginner';

  // Names that contain a promotion keyword below but are genuinely easy.
  const beginnerOverrides = ['jumping jack', 'jump rope'];
  if (hasAny(beginnerOverrides)) return 'beginner';

  // High-skill gymnastic strength + olympic lifts. Note: 'front lever' /
  // 'back lever' are spelled out — a bare 'lever' keyword would swallow the
  // catalog's many 'lever …' (leverage machine) exercises, which are among
  // the most beginner-friendly moves available.
  const advanced = [
    'muscle up', 'pistol', 'handstand', 'planche', 'front lever',
    'back lever', 'human flag', 'dragon', 'impossible', 'plyo', 'explosive',
    'clap', 'archer', 'typewriter', 'l sit', 'iron cross', '90 degree',
    'aztec', 'superman push', 'nordic', 'skin the cat', 'maltese', 'v sit',
    'victorian', 'sissy squat', 'shrimp squat', 'freestanding', 'kipping',
    'korean dip',
  ];
  if (hasAny(advanced)) return 'advanced';

  // Olympic lifts: with a barbell they're the most technical lifts there are;
  // the dumbbell/kettlebell variants are common conditioning moves.
  if (has('snatch') || has('jerk')) {
    return (eq.contains('barbell') || eq.contains('ez barbell'))
        ? 'advanced'
        : 'intermediate';
  }

  // One-arm variations of bodyweight push/pull skills are elite moves;
  // one-arm rows / presses / curls are everyday dumbbell staples and fall
  // through to the rules below.
  const unilateral = ['one arm', 'single arm'];
  const skillContext = [
    'push up', 'pushup', 'pull up', 'pullup', 'chin up', 'chinup', 'dip',
    'handstand',
  ];
  if (hasAny(unilateral) && hasAny(skillContext)) return 'advanced';

  // Technical free-weight lifts, bodyweight strength prerequisites, and
  // ballistic / plyometric work.
  const intermediate = [
    'deadlift', 'clean', 'thruster', 'bulgarian', 'pull up', 'pullup',
    'chin up', 'chinup', 'dip', 'front squat', 'romanian', 'overhead press',
    'push press', 'pike push', 'diamond push', 'decline push', 'burpee',
    'jump', 'hop', 'bound', 'sprint', 'turkish get', 'windmill', 'renegade',
    'man maker', 'copenhagen', 'good morning', 'zercher', 'landmine',
    'split squat',
  ];
  if (hasAny(intermediate)) return 'intermediate';

  // Barbell work is more technical → at least intermediate.
  if (eq.contains('barbell') || eq.contains('ez barbell')) {
    return 'intermediate';
  }

  return 'beginner';
}
