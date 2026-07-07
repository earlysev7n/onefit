import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../app_clock.dart';
import '../models/user_profile.dart';
import '../providers/profile_provider.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
import '../main.dart';

class ProfileInputScreen extends StatefulWidget {
  /// When non-null, the screen runs in *edit* mode: every field is prefilled
  /// from this profile, the CTA reads "Save Changes", and saving pops back
  /// instead of replacing the navigation stack with HomeScreen.
  final UserProfile? existing;

  const ProfileInputScreen({super.key, this.existing});

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

  // Step 3 — Diet. Defaults to the Balanced style (no macro override).
  List<String> _dietaryRestrictions = ['Balanced'];

  // Activity levels + descriptions (shown in the "?" help sheet)
  final Map<String, String> _activityLevels = {
    'Sedentary': 'Little or no exercise, desk job.',
    'Lightly Active': 'Light exercise 1–3 days/week.',
    'Moderately Active': 'Moderate exercise 3–5 days/week.',
    'Very Active': 'Hard exercise 6–7 days/week.',
    'Extra Active': 'Very hard exercise + a physical job.',
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
  // Only options the meal generator actually honours are offered. Restrictions
  // are multi-select; diet styles are single-select (they reshape macro
  // targets, so they cannot be combined).
  final List<String> _restrictionOptions = [
    'None',
    'Vegetarian',
    'Vegan',
    'Halal',
    'Lactose-intolerant',
    'Nut-free',
  ];
  final List<String> _dietStyleOptions = [
    'High-protein',
    'Low-carb',
    'Balanced',
  ];

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
      // Drop options no longer offered (e.g. Keto/Gluten-free from older
      // profiles); they would otherwise show no selected chip and confuse edits.
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

  void _nextPage() {
    // Validate Step 1 (biometrics) before advancing
    if (_currentPage == 0) {
      bool ok = false;
      setState(() => ok = _validateStep1());
      if (!ok) return; // block progression; inline errors now visible
    }
    // Validate Step 2 before advancing
    if (_currentPage == 1) {
      final err = _splitDaysError();
      if (err != null) {
        final c = context.colors;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Incompatible schedule',
              style: GoogleFonts.spaceGrotesk(
                color: c.onBackground,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Text(
              err,
              style: GoogleFonts.inter(
                color: c.muted,
                fontSize: 14,
                height: 1.5,
              ),
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
        return; // block progression
      }
    }
    if (_currentPage < 2) {
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
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage--);
    }
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
              unitSystem: _unitSystem,
              activityLevel: _activityLevel,
              workoutDaysPerWeek: _workoutDays,
              sessionMinutes: _sessionMinutes,
              workoutSplit: _workoutSplit,
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
              unitSystem: _unitSystem,
              activityLevel: _activityLevel,
              workoutDaysPerWeek: _workoutDays,
              sessionMinutes: _sessionMinutes,
              workoutSplit: _workoutSplit,
              createdAt: appNow(),
            );
      await profileProvider.save(profile);
      if (mounted) {
        if (existing != null) {
          // Edit — just return to the Profile screen (which watches the provider).
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
                  3,
                  (i) => Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
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
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [_buildStep1(), _buildStep2(), _buildStep3()],
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
                              _currentPage == 2
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

  Widget _buildStep1() {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          _buildLabel('Unit System'),
          const SizedBox(height: 8),
          Row(
            children: ['metric', 'imperial']
                .map(
                  (u) => Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _unitSystem = u;
                        _weightController.clear();
                        _heightController.clear();
                      }),
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
                              color: _gender == g
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
        ],
      ),
    );
  }

  Widget _buildStep2() {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          _buildLabel('Fitness Goal'),
          const SizedBox(height: 8),
          _buildChipGroup(
            _goals,
            _fitnessGoal,
            (v) => setState(() => _fitnessGoal = v),
          ),
          const SizedBox(height: 24),
          _buildLabel('Experience Level'),
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
                'How many days each week you can train. Your plan places exactly '
                'this many training days and spreads rest days evenly.',
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
          _buildLabelWithHelp('Time per Session', {
            '30 min': 'Short — fewer exercises per day.',
            '45 min': 'Standard session length.',
            '60 min': 'Longer — more exercises per day.',
            '90 min': 'Extended — maximum volume per day.',
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
      ),
    );
  }

  Widget _buildStep3() {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            'Any dietary restrictions?',
            style: GoogleFonts.inter(color: c.muted),
          ),
          const SizedBox(height: 24),
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
          const SizedBox(height: 16),
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
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool isNumber = false,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    final c = context.colors;
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: c.onBackground),
      onChanged: onChanged,
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Text(
    text,
    style: GoogleFonts.inter(color: context.colors.muted, fontSize: 14),
  );

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
