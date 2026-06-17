import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../models/user_profile.dart';
import '../providers/profile_provider.dart';
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
  double _avgSleep = 7.0;

  // Step 2 — Fitness
  String _fitnessGoal = 'Weight Loss';
  String _experienceLevel = 'Beginner';
  String _workoutLocation = 'Home';
  List<String> _equipment = [];
  String _activityLevel = 'Moderately Active';
  int _workoutDays = 3;
  int _sessionMinutes = 45;
  String _workoutSplit = 'Full Body Training';

  // Step 3 — Diet
  List<String> _dietaryRestrictions = [];

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
  final List<String> _equipmentOptions = [
    'Dumbbells',
    'Kettlebells',
    'Resistance Bands',
    'Pull-up Bar',
    'Bodyweight',
  ];
  final List<String> _dietOptions = [
    // Common restrictions
    'Halal',
    'Gluten-free',
    'Vegan',
    'Vegetarian',
    'Dairy-free',
    'Nut-free',
    'Egg-free',
    'Soy-free',
    'Lactose-intolerant',
    // Diet styles
    'Keto',
    'Paleo',
    'Low-carb',
    'High-protein',
    'Mediterranean',
    'Diabetic-friendly',
    'Pescatarian',
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
      _avgSleep = p.avgHoursSlept;
      _fitnessGoal = p.fitnessGoal;
      _experienceLevel = p.experienceLevel;
      _workoutLocation = p.workoutLocation;
      _equipment = List<String>.from(p.equipment);
      _activityLevel = p.activityLevel;
      _workoutDays = p.workoutDaysPerWeek;
      _sessionMinutes = p.sessionMinutes;
      // Profiles saved before the split list was reduced may hold a removed
      // split — fall back so a selected card actually exists on screen.
      _workoutSplit = _splitOptions.containsKey(p.workoutSplit)
          ? p.workoutSplit
          : 'Full Body Training';
      _dietaryRestrictions = List<String>.from(p.dietaryRestrictions);
      // Weight/height are stored in metric; show in the user's unit system.
      final imperial = p.unitSystem == 'imperial';
      _weightController.text =
          (imperial ? p.weight / 0.453592 : p.weight).toStringAsFixed(1);
      _heightController.text =
          (imperial ? p.height / 2.54 : p.height).toStringAsFixed(1);
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
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00C97B),
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A1A),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dob = picked);
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

  void _nextPage() {
    // Validate Step 2 before advancing
    if (_currentPage == 1) {
      final err = _splitDaysError();
      if (err != null) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Incompatible schedule',
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Text(
              err,
              style: GoogleFonts.inter(
                color: const Color(0xFF888888),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Got it',
                  style: GoogleFonts.inter(color: const Color(0xFF00C97B)),
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
      // Home with nothing picked = an explicit bodyweight-only plan (stored as
      // ['Bodyweight'] so it's intentional and visible on the Profile screen,
      // not a silent empty list). Gym assumes all equipment, so it stores [].
      final equipment = _workoutLocation == 'Home'
          ? (_equipment.isEmpty ? <String>['Bodyweight'] : _equipment)
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
              avgHoursSlept: _avgSleep,
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
              avgHoursSlept: _avgSleep,
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
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
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
                            ? const Color(0xFF00C97B)
                            : const Color(0xFF222222),
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
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF444444)),
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
                        backgroundColor: const Color(0xFF00C97B),
                        foregroundColor: Colors.black,
                        minimumSize: const Size(0, 54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.black)
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
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Let\'s personalize your experience',
            style: GoogleFonts.inter(color: const Color(0xFF888888)),
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
                              ? const Color(0xFF00C97B)
                              : const Color(0xFF222222),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            u == 'metric'
                                ? 'Metric (kg/cm)'
                                : 'Imperial (lbs/in)',
                            style: GoogleFonts.inter(
                              color: _unitSystem == u
                                  ? Colors.black
                                  : Colors.white,
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
          _buildTextField(_nameController, 'Full Name'),
          const SizedBox(height: 16),
          // DOB picker — age is auto-calculated
          GestureDetector(
            onTap: _pickDob,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF222222),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    color: Color(0xFF00C97B),
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _dobDisplay,
                    style: GoogleFonts.inter(
                      color: _dob == null
                          ? const Color(0xFF888888)
                          : Colors.white,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildTextField(
            _weightController,
            _unitSystem == 'metric' ? 'Weight (kg)' : 'Weight (lbs)',
            isNumber: true,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            _heightController,
            _unitSystem == 'metric' ? 'Height (cm)' : 'Height (inches)',
            isNumber: true,
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
                          color: _gender == g
                              ? const Color(0xFF00C97B)
                              : const Color(0xFF222222),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            g,
                            style: GoogleFonts.inter(
                              color: _gender == g ? Colors.black : Colors.white,
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
          const SizedBox(height: 20),
          _buildLabelWithHelp('Average Hours Slept', {
            'Why we ask':
                'Sleep drives recovery. If you sleep less, we trim training '
                'volume so you don\'t overtrain.',
          }),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF00C97B),
                    inactiveTrackColor: const Color(0xFF222222),
                    thumbColor: const Color(0xFF00C97B),
                    overlayColor: const Color(0x3300C97B),
                  ),
                  child: Slider(
                    value: _avgSleep,
                    min: 3,
                    max: 12,
                    divisions: 18,
                    onChanged: (v) => setState(() => _avgSleep = v),
                  ),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '${_avgSleep.toStringAsFixed(1)} h',
                  textAlign: TextAlign.end,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
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
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tell us about your fitness goals',
            style: GoogleFonts.inter(color: const Color(0xFF888888)),
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
                              ? const Color(0xFF00C97B)
                              : const Color(0xFF222222),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            l,
                            style: GoogleFonts.inter(
                              color: _workoutLocation == l
                                  ? Colors.black
                                  : Colors.white,
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
                if (_equipment.contains(v))
                  _equipment.remove(v);
                else
                  _equipment.add(v);
              });
            }),
            if (_equipment.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                "No equipment selected — we'll build bodyweight-only workouts.",
                style: GoogleFonts.inter(
                  color: const Color(0xFF888888),
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
          const SizedBox(height: 24),
          _buildLabelWithHelp('Activity Level', _activityLevels),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF222222),
              borderRadius: BorderRadius.circular(14),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _activityLevel,
                isExpanded: true,
                dropdownColor: const Color(0xFF1A1A1A),
                iconEnabledColor: const Color(0xFF00C97B),
                style: GoogleFonts.inter(color: Colors.white),
                items: _activityLevels.keys
                    .map(
                      (k) => DropdownMenuItem(
                        value: k,
                        child: Text(
                          k,
                          style: GoogleFonts.inter(color: Colors.white),
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
                    color: sel
                        ? const Color(0xFF00C97B)
                        : const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '$d',
                      style: GoogleFonts.inter(
                        color: sel ? Colors.black : Colors.white,
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
            (v) => setState(
              () => _sessionMinutes = int.parse(v.split(' ').first),
            ),
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
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _workoutSplit == e.key
                        ? const Color(0xFF00C97B)
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
                          ? const Color(0xFF00C97B)
                          : const Color(0xFF444444),
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
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            e.value,
                            style: GoogleFonts.inter(
                              color: const Color(0xFF888888),
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
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Any dietary restrictions?',
            style: GoogleFonts.inter(color: const Color(0xFF888888)),
          ),
          const SizedBox(height: 24),
          _buildLabel('Common Restrictions'),
          const SizedBox(height: 8),
          _buildMultiChipGroup(
            _dietOptions.take(9).toList(),
            _dietaryRestrictions,
            (v) => setState(() {
              _dietaryRestrictions.contains(v)
                  ? _dietaryRestrictions.remove(v)
                  : _dietaryRestrictions.add(v);
            }),
          ),
          const SizedBox(height: 16),
          _buildLabel('Diet Styles'),
          const SizedBox(height: 8),
          _buildMultiChipGroup(
            _dietOptions.skip(9).toList(),
            _dietaryRestrictions,
            (v) => setState(() {
              _dietaryRestrictions.contains(v)
                  ? _dietaryRestrictions.remove(v)
                  : _dietaryRestrictions.add(v);
            }),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Color(0xFF00C97B),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your meal plan will be tailored to your dietary needs and calorie goals.',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF888888),
                      fontSize: 13,
                    ),
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
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: const Color(0xFF888888)),
        filled: true,
        fillColor: const Color(0xFF222222),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Text(
    text,
    style: GoogleFonts.inter(color: const Color(0xFF888888), fontSize: 14),
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
          child: const Icon(
            Icons.help_outline,
            size: 16,
            color: Color(0xFF00C97B),
          ),
        ),
      ],
    );
  }

  void _showHelpSheet(String title, Map<String, String> help) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
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
                color: Colors.white,
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
                        color: const Color(0xFF00C97B),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      e.value,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF888888),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipGroup(
    List<String> options,
    String selected,
    Function(String) onSelect,
  ) {
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
                  color: selected == o
                      ? const Color(0xFF00C97B)
                      : const Color(0xFF222222),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  o,
                  style: GoogleFonts.inter(
                    color: selected == o ? Colors.black : Colors.white,
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
                  color: selected.contains(o)
                      ? const Color(0xFF00C97B)
                      : const Color(0xFF222222),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  o,
                  style: GoogleFonts.inter(
                    color: selected.contains(o) ? Colors.black : Colors.white,
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
