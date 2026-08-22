// Age-based prescription modifier — pure data + gate, no Flutter/Firebase, so
// both the greedy generator and any UI can import it. Mirrors the
// `intensityCaution` prescription layer in `physical_limitations.dart`.
//
// UserProfile.age already drives BMR → TDEE → calorie goal; this file lets it
// also dose the WORKOUT down for older adults: slightly fewer sets and longer
// rest between sets, layered on top of the fitness goal. Reps are deliberately
// NOT touched (they stay goal-driven) — for older adults the guidance points
// toward *higher* reps at *moderate* load, so lowering reps (heavier load) would
// be the wrong direction; only volume and recovery are eased.
//
// The threshold and dosing here are OUR conservative implementation choice
// informed by — not a verbatim protocol prescribed by — the following, which
// collectively support conservative resistance-training volume and longer
// recovery intervals for older adults, and define ~65 as the "older adult" line:
//   • ACSM — Exercise and Physical Activity for Older Adults (Position Stand):
//     https://journals.lww.com/acsm-msse/fulltext/2009/07000/exercise_and_physical_activity_for_older_adults.20.aspx
//   • ACSM's Guidelines for Exercise Testing and Prescription — older-adult FITT
//     (moderate load, adequate recovery, progressive volume).
//   • WHO Guidelines on Physical Activity (older adults, ≥65).
//
// This is a conservative auto-adjustment, not medical advice.

/// The age (years) at or above which a user is treated as an older adult and the
/// conservative workout dosing applies. Matches the common ACSM/WHO ≥65 line.
const int kOlderAdultAge = 65;

/// True when [age] is at or above [kOlderAdultAge], so the greedy generator
/// should apply the conservative age dosing (fewer sets + longer rest). Mirrors
/// `limitationsReduceIntensity` in `physical_limitations.dart`; the two stack.
bool ageReducesIntensity(int age) => age >= kOlderAdultAge;
