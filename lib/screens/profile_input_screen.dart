import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../algorithms/greedy_algorithm.dart';
import '../app_clock.dart';
import '../data/age_prescription.dart';
import '../data/physical_limitations.dart';
import '../models/user_profile.dart';
import '../providers/plan_provider.dart';
import '../providers/profile_provider.dart';
import '../services/firestore_service.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
import '../main.dart';

/// The age "safety bracket" an entered age falls into, or null if none:
/// `'senior'` (≥ [kOlderAdultAge]) or `'youth'` (< [kMinAdultAge]). Age 0 means
/// "not entered yet" and never triggers. Drives the Step-1 safety acknowledgement
/// (see `_confirmAgeSafety`).
String? ageSafetyBracket(int age) {
  if (age >= kOlderAdultAge) return 'senior';
  if (age > 0 && age < kMinAdultAge) return 'youth';
  return null;
}

class ProfileInputScreen extends StatefulWidget {
  /// When non-null, the screen runs in *edit* mode: every field is prefilled
  /// from this profile.
  final UserProfile? existing;

  /// When true, render as an inline collapsible editor (no Scaffold/header/back)
  /// for embedding under the Settings "Edit Profile" row. Onboarding leaves this
  /// false and shows the full-screen wizard.
  final bool embedded;

  /// When set (0–3), render a single section full-screen (About You / Your
  /// Fitness / Your Schedule / Your Diet) — opened from the embedded section list.
  final int? sectionIndex;

  const ProfileInputScreen({
    super.key,
    this.existing,
    this.embedded = false,
    this.sectionIndex,
  });

  @override
  State<ProfileInputScreen> createState() => _ProfileInputScreenState();
}

class _ProfileInputScreenState extends State<ProfileInputScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;

  // Step 1 — Biometrics
  final _nameController = TextEditingController();
  DateTime? _dob; // date of birth — age auto-calculated
  // The age safety bracket already acknowledged this screen session, so the
  // Step-1 disclaimer isn't re-shown if the user steps back and forward again.
  // Reset per screen instance, so an *edit* session re-shows it once.
  String? _ageSafetyAcked;
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  String _gender = 'Male';
  String _unitSystem = 'metric';
  // Step 1 validation — inline per-field error messages (null = no error)
  String? _nameError;
  String? _dobError;
  String? _weightError;
  String? _heightError;

  // Step 2 — Fitness
  String _fitnessGoal = 'Weight Loss';
  String _experienceLevel = 'Beginner';
  String _workoutLocation = 'Home';
  List<String> _equipment = ['Bodyweight']; // always-on baseline
  String _activityLevel = 'Moderately Active';
  int _workoutDays = 3;
  int _sessionMinutes = 45;
  String _workoutSplit = 'Full Body Training';
  // Exercise PREFERENCE — the user's Compound-vs-Isolation ranking, the only
  // selection-relevant type preference. Stored inside the full 5-item
  // goalPriorities list (reconstructed on save) for back-compat, but the UI only
  // edits these two. Seeded from the goal's default order; re-seeded on goal
  // change. The higher-ranked type scores +2, the other +1.
  List<String> _exerciseTypeOrder = GreedyAlgorithm.defaultGoalPriorities(
    'Weight Loss',
  ).where((k) => k == 'compound' || k == 'isolation').toList();
  // Training FOCUS — the prescription bias ('heavy'|'balanced'|'high'). Decides
  // rep ranges/rest for the SELECTED exercises, never which are selected. Seeded
  // from the fitness goal's default; user can override (e.g. Weight Loss +
  // Heavy Lift is valid).
  String _trainingFocus = 'high'; // Weight Loss default
  // Common physical limitations that hard-exclude contraindicated exercises.
  List<String> _physicalLimitations = [];

  // Step 3 — Diet. Defaults to "None" restriction + the Balanced style (no macro
  // override); allergies default to "None". None is the explicit empty state.
  List<String> _dietaryRestrictions = ['None', 'Balanced'];
  List<String> _foodAllergies = ['None'];

  // Keyboard flow for the Step-1 text fields (Name → Weight → Height).
  final _weightFocus = FocusNode();
  final _heightFocus = FocusNode();

  // Wizard step headings, indexed by _currentPage.
  static const _stepTitles = [
    'About You',
    'Your Fitness',
    'Your Schedule',
    'Your Diet',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _weightFocus.dispose();
    _heightFocus.dispose();
    super.dispose();
  }

  // Activity levels + descriptions (shown in the "?" help sheet)
  final Map<String, String> _activityLevels = {
    'Sedentary': 'Mostly sitting with little movement during the day.',
    'Lightly Active': 'Some walking and light movement during the day.',
    'Moderately Active':
        'Regular walking and movement throughout the day, such as an active '
        'school or work routine.',
    'Very Active':
        'A physically active job or lifestyle with lots of movement throughout '
        'the day.',
    'Extra Active':
        'Very physically demanding work or an extremely active lifestyle with '
        'lots of movement and physical activity.',
  };

  // 5 weekly split styles + one-line descriptions (shown on the cards).
  // Reduced from 10: Bro/Body Part need 5+ days, Hybrid duplicated the
  // others, and HIIT/Circuit need interval logic the generator can't honor.
  // Profiles saved with a removed split fall back to Full Body (see
  // initState and GreedyAlgorithm._splitFocusSequence's default).
  final Map<String, String> _splitOptions = {
    'Full Body Training':
        'Every session trains the whole body; best at 2–3 days/week.',
    'Upper / Lower Split':
        'Alternate upper- and lower-body days; balanced for ~4 days/week.',
    'Push / Pull / Legs (PPL)':
        'Push, pull, then legs; ideal at 3 or 6 days/week.',
    'Functional Training Split':
        'Compound, movement-pattern full-body sessions.',
    'Strength + Conditioning Split':
        'Heavy strength days paired with conditioning/cardio.',
  };

  final List<int> _sessionOptions = [30, 45, 60, 90];

  final List<String> _goals = [
    'Weight Loss',
    'Muscle Gain',
    'Endurance',
    'General Fitness',
  ];
  final List<String> _levels = ['Beginner', 'Intermediate', 'Advanced'];
  // Bodyweight is always first and always on (locked) — every home user can do
  // bodyweight work, so it is the guaranteed baseline. 'Home Gym' means a
  // power/squat rack and implies a Barbell + Bench (auto-selected on toggle).
  final List<String> _equipmentOptions = [
    'Bodyweight',
    'Dumbbells',
    'Kettlebells',
    'Resistance Bands',
    'Pull-up Bar',
    'Barbell',
    'Bench',
    'Home Gym',
  ];
  final List<String> _restrictionOptions = [
    'None',
    'Vegetarian',
    'Vegan',
    'Pescatarian',
    'Halal',
    'Kosher',
    'Gluten-Free',
    'Dairy-Free',
    'Low Carb',
    'Keto',
    'Paleo',
  ];
  final List<String> _dietStyleOptions = [
    'High-protein',
    'Low-carb',
    'Balanced',
  ];
  final List<String> _allergyOptions = [
    'None',
    'Peanuts',
    'Tree Nuts',
    'Eggs',
    'Soy',
    'Fish',
    'Shellfish',
    'Sesame',
  ];
  // Physical-limitation options come from the single source of truth so the
  // chips and the generator's exclusion rules can never drift.
  final List<String> _limitationOptions = kPhysicalLimitations
      .map((l) => l.id)
      .toList();

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    if (p != null) {
      // ── Edit mode — prefill every field from the existing profile ──────────
      _nameController.text = p.name;
      _gender = p.gender;
      _unitSystem = p.unitSystem;
      _fitnessGoal = p.fitnessGoal;
      // Restore the Compound-vs-Isolation order from the saved ranking (whichever
      // appears first is preferred); default compound-first for legacy/partial
      // lists. Restore Training Focus from the saved value, or seed the goal's
      // default when it was never set (legacy profiles).
      _exerciseTypeOrder = _exerciseTypeOrderFrom(
        p.goalPriorities,
        p.fitnessGoal,
      );
      _trainingFocus = p.effectiveTrainingFocus;
      _experienceLevel = p.experienceLevel;
      _workoutLocation = p.workoutLocation;
      // Old Gym profiles store []; ensure Bodyweight is present so the locked
      // baseline chip shows selected when editing.
      _equipment = {'Bodyweight', ...p.equipment}.toList();
      _activityLevel = p.activityLevel;
      _workoutDays = p.workoutDaysPerWeek;
      _sessionMinutes = p.sessionMinutes;
      // Profiles saved before the split list was reduced may hold a removed
      // split — fall back so a selected card actually exists on screen.
      _workoutSplit = _splitOptions.containsKey(p.workoutSplit)
          ? p.workoutSplit
          : 'Full Body Training';
      // Drop options no longer offered so the edit UI only shows current chips.
      _dietaryRestrictions = p.dietaryRestrictions
          .where(
            (r) =>
                _restrictionOptions.contains(r) ||
                _dietStyleOptions.contains(r),
          )
          .toList();
      // Guarantee exactly one diet style is selected (default Balanced).
      if (!_dietaryRestrictions.any(_dietStyleOptions.contains)) {
        _dietaryRestrictions.add('Balanced');
      }
      // Show "None" when no actual restriction is selected (explicit empty state).
      if (!_dietaryRestrictions.any(_restrictionOptions.contains)) {
        _dietaryRestrictions.add('None');
      }
      _foodAllergies = p.foodAllergies.where(_allergyOptions.contains).toList();
      if (_foodAllergies.isEmpty) _foodAllergies.add('None');
      _physicalLimitations = p.physicalLimitations
          .where(_limitationOptions.contains)
          .toList();
      // Weight/height are stored in metric; show in the user's unit system.
      final imperial = p.unitSystem == 'imperial';
      _weightController.text = (imperial ? p.weight / 0.453592 : p.weight)
          .toStringAsFixed(1);
      _heightController.text = (imperial ? p.height / 2.54 : p.height)
          .toStringAsFixed(1);
      // DOB isn't stored — reconstruct a date that yields the same age so the
      // picker shows a sensible value; the user can re-pick if needed.
      _dob = DateTime(DateTime.now().year - p.age, 1, 1);
    }
  }

  /// Age computed from _dob; 0 if not yet set.
  int get _age {
    if (_dob == null) return 0;
    final today = DateTime.now();
    int age = today.year - _dob!.year;
    if (today.month < _dob!.month ||
        (today.month == _dob!.month && today.day < _dob!.day)) {
      age--;
    }
    return age;
  }

  String get _dobDisplay {
    if (_dob == null) return 'Select date of birth';
    final m = _dob!.month.toString().padLeft(2, '0');
    final d = _dob!.day.toString().padLeft(2, '0');
    return '${_dob!.year}-$m-$d  (age $_age)';
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 10),
      builder: (ctx, child) {
        final c = ctx.colors;
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: c.onPrimary,
              surface: c.surface,
              onSurface: c.onBackground,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _dobError = null;
      });
    }
  }

  /// Min days required for the selected split.
  /// Returns null if the combo is valid.
  String? _splitDaysError() {
    const minDays = {
      'Push / Pull / Legs (PPL)': 3,
      'Upper / Lower Split': 2,
      'Strength + Conditioning Split': 2,
    };
    const splitDescriptions = {
      'Push / Pull / Legs (PPL)':
          'PPL cycles through 3 session types (Push, Pull, Legs). With fewer than 3 days you can\'t complete even one full rotation.',
      'Upper / Lower Split':
          'Upper/Lower alternates upper-body and lower-body days — it needs at least 2 training days.',
      'Strength + Conditioning Split':
          'Strength + Conditioning alternates heavy strength days with conditioning work — at least 2 days are needed.',
    };
    final min = minDays[_workoutSplit];
    if (min != null && _workoutDays < min) {
      return '${splitDescriptions[_workoutSplit]}\n\nPlease choose at least $min days/week for $_workoutSplit, or select a different split.';
    }
    return null;
  }

  /// Validates Step 1 (biometrics). Sets inline per-field error messages and
  /// returns true only when name/DOB/weight/height are all present and sane.
  /// Must be called inside setState so the error text renders.
  bool _validateStep1() {
    _nameError = _nameController.text.trim().isEmpty
        ? 'Please enter your name'
        : null;
    _dobError = _dob == null ? 'Please select your date of birth' : null;

    final w = double.tryParse(_weightController.text.trim());
    final weightKg = _getWeightKg();
    _weightError = (w == null || w <= 0 || weightKg < 30 || weightKg > 300)
        ? 'Enter a valid weight'
        : null;

    final h = double.tryParse(_heightController.text.trim());
    final heightCm = _getHeightCm();
    _heightError = (h == null || h <= 0 || heightCm < 100 || heightCm > 250)
        ? 'Enter a valid height'
        : null;

    return _nameError == null &&
        _dobError == null &&
        _weightError == null &&
        _heightError == null;
  }

  /// Safety acknowledgement shown at the point the age is entered — when the user
  /// tries to continue past Step 1 (biometrics) with an age at either extreme.
  /// Non-dismissible with a single **Got it** button, so it must be acknowledged
  /// before continuing (covers both account creation and profile edits). Shown
  /// once per bracket per screen session (`_ageSafetyAcked`).
  ///
  /// **Senior** copy matches the real generator change (fewer sets + longer rest,
  /// reps unchanged — see age_prescription.dart). **Youth** copy is guidance only
  /// (supervision, technique, no maximal lifting); the generator is deliberately
  /// NOT adjusted for under-18s. Not medical advice.
  Future<void> _confirmAgeSafety() async {
    final bracket = ageSafetyBracket(_age);
    if (bracket == null || _ageSafetyAcked == bracket) return;

    final c = context.colors;
    final isYouth = bracket == 'youth';
    final title = isYouth ? 'Train safely' : 'Adjusted for your safety';
    final body = isYouth
        ? "Because you're under 18, train with adult or qualified supervision, "
              "get your technique right before adding weight, and avoid maximal "
              "(very heavy, low-rep) lifting. Your plan is a guide, not a "
              "substitute for coaching.\n\n"
              "This isn't medical advice — check with a doctor or coach before "
              "starting a new program."
        : "Because you're 65 or older, your plan is set up for safer training "
              "and recovery: slightly fewer sets and a little more rest between "
              "them. Your rep ranges are unchanged. Train at a controlled effort "
              "and stop if anything hurts.\n\n"
              "This isn't medical advice — check with your doctor before starting "
              "a new program.";

    await showDialog(
      context: context,
      barrierDismissible:
          false, // must acknowledge — the only way out is "Got it"
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(
          Icons.health_and_safety_outlined,
          color: AppColors.primary,
        ),
        title: Text(
          title,
          style: GoogleFonts.spaceGrotesk(
            color: c.onBackground,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          body,
          style: GoogleFonts.inter(color: c.muted, fontSize: 14, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(
              'Got it',
              style: GoogleFonts.inter(
                color: c.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    _ageSafetyAcked = bracket; // acknowledged (barrier is non-dismissible)
  }

  Future<void> _nextPage() async {
    // Dismiss the soft keyboard so it never lingers onto a later, field-less
    // step (e.g. the chip-only Fitness/Schedule pages).
    FocusScope.of(context).unfocus();
    // Validate Step 1 (biometrics) before advancing
    if (_currentPage == 0) {
      bool ok = false;
      setState(() => ok = _validateStep1());
      if (!ok) return; // block progression; inline errors now visible
      // Age was just entered — require the safety acknowledgement before
      // continuing (older-adult ≥65 or under-18).
      await _confirmAgeSafety();
      if (!mounted) return;
    }
    // Validate the Schedule step (days vs split) before advancing
    if (_currentPage == 2) {
      final err = _splitDaysError();
      if (err != null) {
        _showScheduleError(err);
        return; // block progression
      }
    }
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage++);
    } else {
      _saveProfile();
    }
  }

  void _prevPage() {
    FocusScope.of(context).unfocus();
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage--);
    }
  }

  // Shown when the chosen split needs more days than selected. Shared by the
  // wizard (`_nextPage`) and the edit accordion (`_saveEdit`).
  void _showScheduleError(String err) {
    final c = context.colors;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Incompatible schedule',
          style: GoogleFonts.spaceGrotesk(
            color: c.onBackground,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          err,
          style: GoogleFonts.inter(color: c.muted, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Got it',
              style: GoogleFonts.inter(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  // Save from a single-section edit screen. Only the checks relevant to that
  // section run (biometrics + age-safety for About You; split validity for Your
  // Schedule); other sections just persist. `_saveProfile` then copyWith-saves the
  // whole profile (untouched fields keep their prefilled values) and pops back.
  Future<void> _saveSection(int index) async {
    FocusScope.of(context).unfocus();
    if (index == 0) {
      bool ok = false;
      setState(() => ok = _validateStep1());
      if (!ok) return; // inline errors show on the About You screen
      await _confirmAgeSafety();
      if (!mounted) return;
    } else if (index == 2) {
      final err = _splitDaysError();
      if (err != null) {
        _showScheduleError(err);
        return;
      }
    }
    await _saveProfile();
  }

  // Inline list embedded under the Settings "Edit Profile" row: four tappable
  // rows, one per section. Tapping a row opens that section's own edit screen
  // (see `_buildSectionScreen`) — no inline expansion. `mainAxisSize.min` so it
  // takes only the height it needs inside the Settings column.
  Widget _buildEmbeddedSectionList() {
    final c = context.colors;
    Widget divider() => Divider(height: 1, color: c.border, indent: 60);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // Near-white in light (surfaceVariant #F7F7F2 ≈ the #FFFFFF account card),
        // a touch lighter than the card in dark (#1E1E1E vs #1A1A1A). The subtle
        // border keeps the low-contrast panel delineated against the card.
        color: c.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sectionNavRow(
            0,
            Icons.person_outline,
            'About You',
            'Name, age, weight, height',
          ),
          divider(),
          _sectionNavRow(
            1,
            Icons.fitness_center,
            'Your Fitness',
            'Goal, experience, equipment',
          ),
          divider(),
          _sectionNavRow(
            2,
            Icons.calendar_today_outlined,
            'Your Schedule',
            'Days, split, session length',
          ),
          divider(),
          _sectionNavRow(
            3,
            Icons.restaurant_outlined,
            'Your Diet',
            'Restrictions, allergies',
          ),
        ],
      ),
    );
  }

  // One compact row in the embedded section list → pushes that section's own edit
  // screen. Mirrors the Settings tile (leading icon square + title + subtitle +
  // chevron) but with smaller, minimal type.
  Widget _sectionNavRow(
    int index,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final c = context.colors;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileInputScreen(
            existing: widget.existing,
            sectionIndex: index,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: c.muted.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: c.muted, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.spaceGrotesk(
                      color: c.onBackground,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(color: c.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.subtle, size: 18),
          ],
        ),
      ),
    );
  }

  // Full-screen editor for ONE section (recycles the old edit-profile screen): a
  // header with the section title + that step's fields + a Save button. Opened
  // from the embedded section list; saving persists the whole profile and pops.
  Widget _buildSectionScreen(int index) {
    final c = context.colors;
    const titles = ['About You', 'Your Fitness', 'Your Schedule', 'Your Diet'];
    final body = switch (index) {
      0 => _buildStep1(asSection: true),
      1 => _buildStep2(asSection: true),
      2 => _buildStepSchedule(asSection: true),
      _ => _buildStep3(asSection: true),
    };
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: c.onBackground,
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    titles[index],
                    style: GoogleFonts.spaceGrotesk(
                      color: c.onBackground,
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: body,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : () => _saveSection(index),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: c.onPrimary,
                    minimumSize: const Size(0, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isLoading
                      ? CircularProgressIndicator(color: c.onPrimary)
                      : Text(
                          'Save Changes',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getWeightKg() {
    final val = double.tryParse(_weightController.text) ?? 0;
    return _unitSystem == 'imperial' ? val * 0.453592 : val;
  }

  double _getHeightCm() {
    final val = double.tryParse(_heightController.text) ?? 0;
    return _unitSystem == 'imperial' ? val * 2.54 : val;
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    final profileProvider = context.read<ProfileProvider>();
    final planProvider = context.read<PlanProvider>();
    final existing = widget.existing;
    try {
      // Home always carries 'Bodyweight' (the guaranteed baseline) on top of
      // whatever else was picked, so a home user can never end up without a
      // usable pool. Gym assumes all equipment, so it stores [].
      final equipment = _workoutLocation == 'Home'
          ? <String>{'Bodyweight', ..._equipment}.toList()
          : <String>[];
      // Edit mode copies onto the existing profile so uid and the accumulated
      // calorieAdjustment survive; onboarding builds a fresh profile.
      final profile = existing != null
          ? existing.copyWith(
              name: _nameController.text.trim(),
              gender: _gender,
              age: _age,
              weight: _getWeightKg(),
              height: _getHeightCm(),
              fitnessGoal: _fitnessGoal,
              experienceLevel: _experienceLevel,
              workoutLocation: _workoutLocation,
              equipment: equipment,
              dietaryRestrictions: _dietaryRestrictions,
              foodAllergies: _foodAllergies,
              physicalLimitations: _physicalLimitations,
              avoidedMovements: const [],
              unitSystem: _unitSystem,
              activityLevel: _activityLevel,
              workoutDaysPerWeek: _workoutDays,
              sessionMinutes: _sessionMinutes,
              workoutSplit: _workoutSplit,
              goalPriorities: _reconstructGoalPriorities(),
              trainingFocus: _trainingFocus,
            )
          : UserProfile(
              uid: FirebaseAuth.instance.currentUser!.uid,
              name: _nameController.text.trim(),
              gender: _gender,
              age: _age,
              weight: _getWeightKg(),
              height: _getHeightCm(),
              fitnessGoal: _fitnessGoal,
              experienceLevel: _experienceLevel,
              workoutLocation: _workoutLocation,
              equipment: equipment,
              dietaryRestrictions: _dietaryRestrictions,
              foodAllergies: _foodAllergies,
              physicalLimitations: _physicalLimitations,
              avoidedMovements: const [],
              unitSystem: _unitSystem,
              activityLevel: _activityLevel,
              workoutDaysPerWeek: _workoutDays,
              sessionMinutes: _sessionMinutes,
              workoutSplit: _workoutSplit,
              goalPriorities: _reconstructGoalPriorities(),
              trainingFocus: _trainingFocus,
              createdAt: appNow(),
            );
      await profileProvider.save(profile);
      // If a WORKOUT-relevant field changed on an edit, invalidate this week's
      // plan (same as the manual ↺ refresh) so the next Plans open regenerates
      // from the new profile. Onboarding needs nothing — a new account has no
      // persisted plan and its in-memory state was reset on the prior sign-out.
      if (existing != null &&
          existing.workoutGenerationSignature !=
              profile.workoutGenerationSignature) {
        final weekId = FirestoreService.weekIdFor(
          appNow(),
          anchorWeekday: profile.createdAt?.weekday ?? 1,
        );
        await planProvider.clearAndDeleteWorkoutPlan(profile.uid, weekId);
      }
      if (mounted) {
        if (existing != null) {
          // Edit (single-section screen) — confirm, then pop back to the Settings
          // section list. The snackbar uses the app-level messenger so it survives
          // the pop. (Onboarding takes the else branch.)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile updated'),
              backgroundColor: AppColors.primary,
            ),
          );
          Navigator.pop(context);
        } else {
          // Onboarding — set HomeScreen as the base of the stack.
          navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    // A single section, full-screen (opened from the embedded list).
    if (widget.sectionIndex != null) {
      return _buildSectionScreen(widget.sectionIndex!);
    }
    // Embedded (Settings "Edit Profile"): the inline list of section rows.
    if (widget.embedded) return _buildEmbeddedSectionList();
    // Onboarding: the guided step-by-step wizard.
    return _buildWizardLayout();
  }

  Widget _buildWizardLayout() {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: List.generate(
                  4,
                  (i) => Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: i < 3 ? 8 : 0),
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= _currentPage
                            ? AppColors.primary
                            : c.inputFill,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Step ${_currentPage + 1} of 4 · ${_stepTitles[_currentPage]}',
                  style: GoogleFonts.inter(
                    color: c.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep1(),
                  _buildStep2(),
                  _buildStepSchedule(),
                  _buildStep3(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _prevPage,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.onBackground,
                          side: BorderSide(color: c.subtle),
                          minimumSize: const Size(0, 54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Back',
                          style: GoogleFonts.spaceGrotesk(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (_currentPage > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: c.onPrimary,
                        minimumSize: const Size(0, 54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isLoading
                          ? CircularProgressIndicator(color: c.onPrimary)
                          : Text(
                              _currentPage == 3
                                  ? (widget.existing != null
                                        ? 'Save Changes'
                                        : 'Get Started')
                                  : 'Next',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1({bool asSection = false}) {
    final c = context.colors;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!asSection) ...[
          Text(
            'About You',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: c.onBackground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Let\'s personalize your experience',
            style: GoogleFonts.inter(color: c.muted),
          ),
          const SizedBox(height: 24),
        ],
        _buildLabel('Unit System'),
        const SizedBox(height: 8),
        Row(
          children: ['metric', 'imperial']
              .map(
                (u) => Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (_unitSystem == u) return;
                      setState(() {
                        final currentWeight = double.tryParse(
                          _weightController.text,
                        );
                        final currentHeight = double.tryParse(
                          _heightController.text,
                        );
                        if (u == 'imperial') {
                          if (currentWeight != null) {
                            _weightController.text = (currentWeight * 2.20462)
                                .toStringAsFixed(1);
                          }
                          if (currentHeight != null) {
                            _heightController.text = (currentHeight / 2.54)
                                .toStringAsFixed(1);
                          }
                        } else {
                          if (currentWeight != null) {
                            _weightController.text = (currentWeight * 0.453592)
                                .toStringAsFixed(1);
                          }
                          if (currentHeight != null) {
                            _heightController.text = (currentHeight * 2.54)
                                .toStringAsFixed(1);
                          }
                        }
                        _unitSystem = u;
                      });
                    },
                    child: Container(
                      margin: EdgeInsets.only(right: u == 'metric' ? 8 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _unitSystem == u
                            ? AppColors.primary
                            : c.inputFill,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          u == 'metric'
                              ? 'Metric (kg/cm)'
                              : 'Imperial (lbs/in)',
                          style: GoogleFonts.inter(
                            color: _unitSystem == u
                                ? c.onPrimary
                                : c.onBackground,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        _buildTextField(
          _nameController,
          'Full Name',
          errorText: _nameError,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _weightFocus.requestFocus(),
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
        ),
        const SizedBox(height: 16),
        // DOB picker — age is auto-calculated
        GestureDetector(
          onTap: _pickDob,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: c.inputFill,
              borderRadius: BorderRadius.circular(14),
              border: _dobError != null
                  ? Border.all(color: const Color(0xFFFF6B6B))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Text(
                  _dobDisplay,
                  style: GoogleFonts.inter(
                    color: _dob == null ? c.muted : c.onBackground,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_dobError != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              _dobError!,
              style: GoogleFonts.inter(
                color: const Color(0xFFFF6B6B),
                fontSize: 12,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildTextField(
          _weightController,
          _unitSystem == 'metric' ? 'Weight (kg)' : 'Weight (lbs)',
          isNumber: true,
          errorText: _weightError,
          focusNode: _weightFocus,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _heightFocus.requestFocus(),
          onChanged: (_) {
            if (_weightError != null) setState(() => _weightError = null);
          },
        ),
        const SizedBox(height: 16),
        _buildTextField(
          _heightController,
          _unitSystem == 'metric' ? 'Height (cm)' : 'Height (inches)',
          isNumber: true,
          errorText: _heightError,
          focusNode: _heightFocus,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          onChanged: (_) {
            if (_heightError != null) setState(() => _heightError = null);
          },
        ),
        const SizedBox(height: 20),
        _buildLabel('Gender'),
        const SizedBox(height: 8),
        Row(
          children: ['Male', 'Female']
              .map(
                (g) => Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _gender = g),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _gender == g ? AppColors.primary : c.inputFill,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          g,
                          style: GoogleFonts.inter(
                            color: _gender == g ? c.onPrimary : c.onBackground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
    return asSection
        ? content
        : SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: content,
          );
  }

  Widget _buildStep2({bool asSection = false}) {
    final c = context.colors;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!asSection) ...[
          Text(
            'Your Fitness',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: c.onBackground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tell us about your fitness goals',
            style: GoogleFonts.inter(color: c.muted),
          ),
          const SizedBox(height: 24),
        ],
        _buildLabel('Fitness Goal'),
        const SizedBox(height: 8),
        _buildChipGroup(
          _goals,
          _fitnessGoal,
          // Switching goal re-seeds BOTH the exercise-type order and the
          // Training Focus to that goal's defaults (the user can still override
          // either afterward).
          (v) => setState(() {
            _fitnessGoal = v;
            _exerciseTypeOrder = _exerciseTypeOrderFrom(const [], v);
            _trainingFocus = _defaultTrainingFocusFor(v);
          }),
        ),
        const SizedBox(height: 24),
        _buildLabelWithHelp('Exercise Preference', _exercisePreferenceHelp()),
        const SizedBox(height: 4),
        Text(
          'Tap the exercise TYPE you prefer. When several exercises fit a '
          'slot, the one you pick is favoured.',
          style: GoogleFonts.inter(color: c.muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _buildExerciseTypeList(),
        const SizedBox(height: 24),
        _buildLabelWithHelp('Training Focus', _trainingFocusHelp()),
        const SizedBox(height: 4),
        Text(
          'Sets how your chosen exercises are dosed (reps/rest) — it never '
          'changes which exercises are picked. Seeded from your goal; change '
          'it any time.',
          style: GoogleFonts.inter(color: c.muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _buildTrainingFocusSelector(),
        const SizedBox(height: 24),
        _buildLabelWithHelp('Experience Level', const {
          'How it works':
              'We match exercises to your level. Anything too advanced is left '
              'out, and moves that suit you come first.',
          'Beginner': 'Simple, beginner-friendly moves only.',
          'Intermediate':
              'Beginner and intermediate moves; the tough advanced ones sit '
              'out.',
          'Advanced': 'The full library, with advanced moves up front.',
        }),
        const SizedBox(height: 8),
        _buildChipGroup(
          _levels,
          _experienceLevel,
          (v) => setState(() => _experienceLevel = v),
        ),
        const SizedBox(height: 24),
        _buildLabel('Workout Location'),
        const SizedBox(height: 8),
        Row(
          children: ['Home', 'Gym']
              .map(
                (l) => Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _workoutLocation = l),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _workoutLocation == l
                            ? AppColors.primary
                            : c.inputFill,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          l,
                          style: GoogleFonts.inter(
                            color: _workoutLocation == l
                                ? c.onPrimary
                                : c.onBackground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        if (_workoutLocation == 'Home') ...[
          const SizedBox(height: 24),
          _buildLabel('Equipment Available'),
          const SizedBox(height: 8),
          _buildMultiChipGroup(_equipmentOptions, _equipment, (v) {
            setState(() {
              // Bodyweight is the guaranteed baseline — it can't be removed.
              if (v == 'Bodyweight') return;
              if (_equipment.contains(v)) {
                _equipment.remove(v);
                // Dropping the rack also drops the lifts it unlocked is too
                // aggressive; leave Barbell/Bench so the user keeps them.
              } else {
                _equipment.add(v);
                // A home gym (rack) comes with a barbell + bench — add both so
                // one tap unlocks the full free-weight setup.
                if (v == 'Home Gym') {
                  if (!_equipment.contains('Barbell')) {
                    _equipment.add('Barbell');
                  }
                  if (!_equipment.contains('Bench')) _equipment.add('Bench');
                }
              }
            });
          }),
          const SizedBox(height: 8),
          Text(
            _equipment.contains('Home Gym')
                ? 'Home gym (rack) selected — barbell, bench and racked lifts unlocked.'
                : "Bodyweight is always included. Add 'Home Gym' if you have a squat rack.",
            style: GoogleFonts.inter(
              color: c.muted,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 24),
        _buildLabel('Physical Limitations'),
        const SizedBox(height: 4),
        Text(
          'Tap an area to avoid its higher-risk exercises.',
          style: GoogleFonts.inter(color: c.muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _buildLimitationChips(),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.health_and_safety_outlined, size: 18, color: c.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'We only screen the areas you select and exclude higher-risk '
                      'exercises based on those selections. This does not cover '
                      'complex disabilities or medical conditions.',
                      style: GoogleFonts.inter(
                        color: c.muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: _showSafetySheet,
                      child: Text(
                        'Read safety information',
                        style: GoogleFonts.inter(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return asSection
        ? content
        : SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: content,
          );
  }

  Widget _buildStepSchedule({bool asSection = false}) {
    final c = context.colors;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!asSection) ...[
          Text(
            'Your Schedule',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: c.onBackground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'When and how often you train',
            style: GoogleFonts.inter(color: c.muted),
          ),
          const SizedBox(height: 24),
        ],
        _buildLabelWithHelp('Activity Level', _activityLevels),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: c.inputFill,
            borderRadius: BorderRadius.circular(14),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _activityLevel,
              isExpanded: true,
              dropdownColor: c.surface,
              iconEnabledColor: AppColors.primary,
              style: GoogleFonts.inter(color: c.onBackground),
              items: _activityLevels.keys
                  .map(
                    (k) => DropdownMenuItem(
                      value: k,
                      child: Text(
                        k,
                        style: GoogleFonts.inter(color: c.onBackground),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _activityLevel = v!),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildLabelWithHelp('Workout Days / Week', {
          'Workout Days':
              'How many days a week you can train. We\'ll place exactly that '
              'many training days and spread your rest days evenly.',
        }),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: List.generate(7, (i) {
            final d = i + 1;
            final sel = _workoutDays == d;
            return GestureDetector(
              onTap: () => setState(() => _workoutDays = d),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: sel ? AppColors.primary : c.inputFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '$d',
                    style: GoogleFonts.inter(
                      color: sel ? c.onPrimary : c.onBackground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 24),
        _buildLabelWithHelp('Time per Session', const {
          'How it works':
              'This sets how many exercises you get each day — not which ones. '
              'Those come from your preference and experience level.',
          '30 min': 'Short — fewest exercises per day.',
          '45 min': 'Standard — a few more exercises.',
          '60 min': 'Longer — more exercises per day.',
          '90 min': 'Extended — most exercises per day.',
        }),
        const SizedBox(height: 8),
        _buildChipGroup(
          _sessionOptions.map((m) => '$m min').toList(),
          '$_sessionMinutes min',
          (v) =>
              setState(() => _sessionMinutes = int.parse(v.split(' ').first)),
        ),
        const SizedBox(height: 24),
        _buildLabel('Workout Split'),
        const SizedBox(height: 8),
        ..._splitOptions.entries.map(
          (e) => GestureDetector(
            onTap: () => setState(() => _workoutSplit = e.key),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _workoutSplit == e.key
                      ? AppColors.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _workoutSplit == e.key
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: _workoutSplit == e.key
                        ? AppColors.primary
                        : c.subtle,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.key,
                          style: GoogleFonts.spaceGrotesk(
                            color: c.onBackground,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          e.value,
                          style: GoogleFonts.inter(
                            color: c.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // ── Inline compatibility warning ───────────────────────────────────
        if (_splitDaysError() != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.redAccent,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _splitDaysError()!,
                    style: GoogleFonts.inter(
                      color: Colors.redAccent,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
    return asSection
        ? content
        : SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: content,
          );
  }

  Widget _buildStep3({bool asSection = false}) {
    final c = context.colors;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!asSection) ...[
          Text(
            'Your Diet',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: c.onBackground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Any dietary restrictions or food allergies?',
            style: GoogleFonts.inter(color: c.muted),
          ),
          const SizedBox(height: 24),
        ],
        _buildLabel('Dietary Restrictions'),
        const SizedBox(height: 8),
        _buildMultiChipGroup(
          _restrictionOptions,
          _dietaryRestrictions,
          (v) => setState(() {
            if (v == 'None') {
              _dietaryRestrictions.removeWhere(_restrictionOptions.contains);
              _dietaryRestrictions.add('None');
            } else {
              _dietaryRestrictions.remove('None');
              _dietaryRestrictions.contains(v)
                  ? _dietaryRestrictions.remove(v)
                  : _dietaryRestrictions.add(v);
            }
          }),
        ),
        const SizedBox(height: 20),
        _buildLabel('Food Allergies'),
        const SizedBox(height: 8),
        _buildMultiChipGroup(
          _allergyOptions,
          _foodAllergies,
          (v) => setState(() {
            if (v == 'None') {
              _foodAllergies.removeWhere(_allergyOptions.contains);
              _foodAllergies.add('None');
            } else {
              _foodAllergies.remove('None');
              _foodAllergies.contains(v)
                  ? _foodAllergies.remove(v)
                  : _foodAllergies.add(v);
            }
          }),
        ),
        const SizedBox(height: 20),
        _buildLabel('Diet Style'),
        const SizedBox(height: 8),
        // Single-select: picking one style clears the others (styles reshape
        // macro targets and cannot be combined). Always one stays selected.
        _buildMultiChipGroup(
          _dietStyleOptions,
          _dietaryRestrictions,
          (v) => setState(() {
            _dietaryRestrictions.removeWhere(_dietStyleOptions.contains);
            _dietaryRestrictions.add(v);
          }),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your meal plan will be tailored to your dietary needs and calorie goals.',
                  style: GoogleFonts.inter(color: c.muted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return asSection
        ? content
        : SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: content,
          );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool isNumber = false,
    String? errorText,
    ValueChanged<String>? onChanged,
    FocusNode? focusNode,
    bool autofocus = false,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    final c = context.colors;
    OutlineInputBorder border(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      textInputAction: textInputAction,
      textCapitalization: isNumber
          ? TextCapitalization.none
          : TextCapitalization.words,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: c.onBackground),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: c.muted),
        filled: true,
        fillColor: c.inputFill,
        errorText: errorText,
        errorStyle: GoogleFonts.inter(
          color: const Color(0xFFFF6B6B),
          fontSize: 12,
        ),
        enabledBorder: border(c.border),
        focusedBorder: border(AppColors.primary, width: 1.5),
        errorBorder: border(AppColors.overTarget),
        focusedErrorBorder: border(AppColors.overTarget, width: 1.5),
      ),
    );
  }

  Widget _buildLabel(String text) => Text(
    text,
    style: GoogleFonts.inter(color: context.colors.muted, fontSize: 14),
  );

  // ── Preference/Focus helpers ───────────────────────────────────────────────

  /// The fitness goal's default Training Focus (mirrors
  /// [UserProfile.effectiveTrainingFocus]).
  static String _defaultTrainingFocusFor(String goal) {
    switch (goal) {
      case 'Weight Loss':
      case 'Endurance':
        return 'high';
      default:
        return 'balanced'; // Muscle Gain + General Fitness
    }
  }

  /// Derives the Compound-vs-Isolation order from a saved [goalPriorities] list
  /// (whichever key appears first is preferred). Falls back to the goal's default
  /// order for empty/partial lists so legacy profiles behave sensibly.
  static List<String> _exerciseTypeOrderFrom(
    List<String> goalPriorities,
    String goal,
  ) {
    final ci = goalPriorities.indexOf('compound');
    final ii = goalPriorities.indexOf('isolation');
    if (ci >= 0 && ii >= 0) {
      return ci < ii ? ['compound', 'isolation'] : ['isolation', 'compound'];
    }
    // Legacy/partial — use the goal's built-in ordering.
    return GreedyAlgorithm.defaultGoalPriorities(
      goal,
    ).where((k) => k == 'compound' || k == 'isolation').toList();
  }

  /// The [UserProfile.goalPriorities] to store: the user's chosen
  /// Compound/Isolation order. The greedy scorer reads only this order (preferred
  /// type +2, other +1), so no other keys are needed. Legacy profiles may still
  /// carry extra keys from older versions; those are simply ignored on read.
  List<String> _reconstructGoalPriorities() =>
      List<String>.from(_exerciseTypeOrder);

  /// Help content for the Exercise Preference list. Keyed for [_showHelpSheet].
  Map<String, String> _exercisePreferenceHelp() => {
    'How it works':
        'Pick the kind of training you enjoy most. When two moves could fill '
        'the same spot, we\'ll lean toward your pick — it only changes which '
        'exercises you get, not how hard they are. Your goal and keeping '
        'muscles balanced still matter most.',
    'Compound':
        'Big moves that work several muscles at once — like squats and '
        'rows.',
    'Isolation':
        'Focused moves that target one muscle — like biceps curls or lateral '
        'raises.',
  };

  /// Help content for the Training Focus selector. Keyed for [_showHelpSheet].
  Map<String, String> _trainingFocusHelp() => {
    'How it works':
        'This sets how your exercises are done — the reps and rest — not which '
        'ones you get. We start you with a default that fits your goal, and '
        'you can change it anytime.',
    'Heavy Lift':
        'Fewer reps with heavier weight and longer rests '
        '(around 4–8 reps).',
    'Balanced':
        'A mix — heavier on the big lifts, lighter and higher-rep on the small '
        'ones.',
    'High Rep':
        'More reps with lighter weight and shorter rests '
        '(around 10–15+).',
  };

  /// Tap-to-select of the two exercise TYPES (Compound / Isolation). The tapped
  /// type becomes the priority (index 0 of [_exerciseTypeOrder]) — the order
  /// feeds the Compound/Isolation ranking stored in [UserProfile.goalPriorities],
  /// which the greedy scorer reads as a small selection tie-breaker.
  Widget _buildExerciseTypeList() {
    final c = context.colors;
    const types = ['compound', 'isolation'];
    final selected = _exerciseTypeOrder.isNotEmpty
        ? _exerciseTypeOrder.first
        : 'compound';
    return Column(
      children: [
        for (final key in types)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(
              () =>
                  _exerciseTypeOrder = [key, types.firstWhere((k) => k != key)],
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: selected == key
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : c.inputFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected == key
                      ? AppColors.primary
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      GreedyAlgorithm.goalFeatureLabels[key] ?? key,
                      style: GoogleFonts.inter(
                        color: selected == key
                            ? AppColors.primary
                            : c.onBackground,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (selected == key)
                    const Icon(
                      Icons.check_circle,
                      color: AppColors.primary,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Three-way Training Focus selector (Heavy Lift / Balanced / High Rep).
  /// Stores the code ('heavy'|'balanced'|'high') in [_trainingFocus].
  Widget _buildTrainingFocusSelector() {
    final c = context.colors;
    const options = [
      ('heavy', 'Heavy Lift'),
      ('balanced', 'Balanced'),
      ('high', 'High Rep'),
    ];
    return Row(
      children: [
        for (final (code, label) in options)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _trainingFocus = code),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _trainingFocus == code
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : c.inputFill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _trainingFocus == code
                        ? AppColors.primary
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: _trainingFocus == code
                        ? AppColors.primary
                        : c.onBackground,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Section label with a small "?" info button. Tapping it opens a bottom
  /// sheet that explains each option in [help] (name → one-line description).
  Widget _buildLabelWithHelp(String text, Map<String, String> help) {
    return Row(
      children: [
        _buildLabel(text),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => _showHelpSheet(text, help),
          child: Icon(Icons.help_outline, size: 16, color: AppColors.primary),
        ),
      ],
    );
  }

  void _showHelpSheet(String title, Map<String, String> help) {
    final c = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: c.onBackground,
                ),
              ),
              const SizedBox(height: 16),
              ...help.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.key,
                        style: GoogleFonts.inter(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        e.value,
                        style: GoogleFonts.inter(color: c.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom sheet with the full Physical Limitations safety disclaimer,
  /// opened from the "Read safety information" link.
  void _showSafetySheet() {
    final c = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Safety information',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: c.onBackground,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'We only screen the areas you select above and avoid recommending '
                'their higher-risk exercises. This does not account for disabilities '
                'or more complex conditions — such as limb loss or amputation, '
                'paralysis, or other significant physical or mobility impairments — so '
                'the generated plans may not be suitable or safe for them.',
                style: GoogleFonts.inter(
                  color: c.muted,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This is not medical advice. If you have a disability or any health '
                'condition, please consult a healthcare professional or qualified '
                'trainer before starting.',
                style: GoogleFonts.inter(
                  color: c.muted,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChipGroup(
    List<String> options,
    String selected,
    Function(String) onSelect,
  ) {
    final c = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options
          .map(
            (o) => GestureDetector(
              onTap: () => onSelect(o),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected == o ? AppColors.primary : c.inputFill,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  o,
                  style: GoogleFonts.inter(
                    color: selected == o ? c.onPrimary : c.onBackground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  /// Affected-area chips. Tapping one toggles the whole limitation on/off — the
  /// generator then auto-excludes everything mapped to it. No sub-checklist; a
  /// specific move can still be added later via the picker's "Add Anyway" prompt.
  Widget _buildLimitationChips() {
    final c = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // "None" is the empty state: selected when no limitations are chosen.
        // Tapping it clears any selected areas; selecting any real area below
        // makes the list non-empty, so this deselects automatically.
        GestureDetector(
          onTap: () => setState(_physicalLimitations.clear),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _physicalLimitations.isEmpty
                  ? AppColors.primary
                  : c.inputFill,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'None',
              style: GoogleFonts.inter(
                color: _physicalLimitations.isEmpty
                    ? c.onPrimary
                    : c.onBackground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        ...kPhysicalLimitations.map((lim) {
          final selected = _physicalLimitations.contains(lim.id);
          return GestureDetector(
            onTap: () => setState(() {
              selected
                  ? _physicalLimitations.remove(lim.id)
                  : _physicalLimitations.add(lim.id);
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : c.inputFill,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                lim.id,
                style: GoogleFonts.inter(
                  color: selected ? c.onPrimary : c.onBackground,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMultiChipGroup(
    List<String> options,
    List<String> selected,
    Function(String) onToggle,
  ) {
    final c = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options
          .map(
            (o) => GestureDetector(
              onTap: () => onToggle(o),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected.contains(o) ? AppColors.primary : c.inputFill,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  o,
                  style: GoogleFonts.inter(
                    color: selected.contains(o) ? c.onPrimary : c.onBackground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
