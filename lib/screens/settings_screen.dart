import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_clock.dart';
import '../dev/dev_tools.dart';
import '../main.dart';
import '../providers/profile_provider.dart';
import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'profile_input_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showGoalPopup = true;
  bool _seeding = false;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() {
          _showGoalPopup = !(p.getBool('hideGoalAdjustmentPopup') ?? false);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final themeProvider = context.watch<ThemeProvider>();
    final profileProvider = context.watch<ProfileProvider>();
    final profile = profileProvider.profile;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.chevron_left, color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Settings',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: c.onBackground,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Preferences section
              _sectionHeader(context, 'Preferences'),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _settingsTile(
                      context,
                      icon: Icons.light_mode_outlined,
                      iconColor: AppColors.yellow,
                      title: 'Dark Mode',
                      subtitle: 'Switch between light and dark mode',
                      trailing: Switch(
                        value: themeProvider.isDark,
                        onChanged: (_) => themeProvider.toggleTheme(),
                        activeTrackColor: AppColors.primary,
                        activeThumbColor: Colors.white,
                      ),
                    ),
                    Divider(height: 1, color: c.border, indent: 64),
                    _settingsTile(
                      context,
                      icon: Icons.straighten_outlined,
                      iconColor: AppColors.primary,
                      title: 'Units',
                      subtitle: profile?.unitSystem == 'imperial'
                          ? 'Imperial (lb, ft)'
                          : 'Metric (kg, cm)',
                      trailing: Icon(Icons.chevron_right, color: c.subtle),
                      onTap: () {
                        if (profile == null) return;
                        final newUnit = profile.unitSystem == 'imperial'
                            ? 'metric'
                            : 'imperial';
                        profileProvider.save(
                          profile.copyWith(unitSystem: newUnit),
                        );
                      },
                    ),
                    Divider(height: 1, color: c.border, indent: 64),
                    _settingsTile(
                      context,
                      icon: Icons.notifications_outlined,
                      iconColor: AppColors.amber,
                      title: 'Goal Adjustment Notification',
                      subtitle: 'Remind me when today\'s calorie goal is adjusted',
                      trailing: Switch(
                        value: _showGoalPopup,
                        onChanged: (val) async {
                          final p = await SharedPreferences.getInstance();
                          await p.setBool('hideGoalAdjustmentPopup', !val);
                          if (val) {
                            await p.remove('goalAdjustmentLastShown');
                          }
                          if (mounted) setState(() => _showGoalPopup = val);
                        },
                        activeTrackColor: AppColors.primary,
                        activeThumbColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Account section
              _sectionHeader(context, 'Account'),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _settingsTile(
                      context,
                      icon: Icons.person_outline,
                      iconColor: AppColors.primary,
                      title: 'Edit Profile',
                      subtitle: 'Update your personal information',
                      trailing: Icon(Icons.chevron_right, color: c.subtle),
                      onTap: profile == null
                          ? null
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ProfileInputScreen(existing: profile),
                                ),
                              ),
                    ),
                    Divider(height: 1, color: c.border, indent: 64),
                    _settingsTile(
                      context,
                      icon: Icons.lock_outline,
                      iconColor: AppColors.amber,
                      title: 'Change Password',
                      subtitle: 'Update your password',
                      trailing: Icon(Icons.chevron_right, color: c.subtle),
                      onTap: () => _showChangePasswordDialog(context),
                    ),
                    Divider(height: 1, color: c.border, indent: 64),
                    _settingsTile(
                      context,
                      icon: Icons.logout,
                      iconColor: Colors.redAccent,
                      title: 'Log Out',
                      subtitle: 'Sign out of your account',
                      trailing: Icon(Icons.chevron_right, color: c.subtle),
                      titleColor: Colors.redAccent,
                      onTap: () async {
                        await AuthService().signOut();
                        navigatorKey.currentState?.pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                          (route) => false,
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Developer section
              _developerSection(context),
            ],
          ),
        ),
      ),
    );
  }

  // ── Developer mode ─────────────────────────────────────────────────────────

  Widget _developerSection(BuildContext context) {
    final c = context.colors;
    Widget divider() => Divider(height: 1, color: c.border, indent: 64);

    return ValueListenableBuilder<bool>(
      valueListenable: developerModeEnabled,
      builder: (context, devOn, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 28),
          _sectionHeader(context, 'Developer'),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _settingsTile(
                  context,
                  icon: Icons.developer_mode_outlined,
                  iconColor: AppColors.amber,
                  title: 'Developer Mode',
                  subtitle: 'Demo tools for the adaptive system',
                  trailing: Switch(
                    value: devOn,
                    onChanged: _toggleDeveloperMode,
                    activeTrackColor: AppColors.primary,
                    activeThumbColor: Colors.white,
                  ),
                ),
                if (devOn) ...[
                  divider(),
                  ValueListenableBuilder<bool>(
                    valueListenable: devDayChangerEnabled,
                    builder: (context, on, _) => _settingsTile(
                      context,
                      icon: Icons.calendar_today_outlined,
                      iconColor: AppColors.amber,
                      title: 'Change Day',
                      subtitle: 'Show the floating date control',
                      trailing: Switch(
                        value: on,
                        onChanged: (v) => devDayChangerEnabled.value = v,
                        activeTrackColor: AppColors.primary,
                        activeThumbColor: Colors.white,
                      ),
                    ),
                  ),
                  divider(),
                  _scenarioPicker(context),
                  divider(),
                  _settingsTile(
                    context,
                    icon: Icons.bolt_outlined,
                    iconColor: AppColors.amber,
                    title: 'Auto-Complete Today\'s Workout',
                    subtitle: 'Log today\'s plan as done',
                    trailing: Icon(Icons.chevron_right, color: c.subtle),
                    onTap: _runAutoComplete,
                  ),
                  divider(),
                  _settingsTile(
                    context,
                    icon: Icons.fast_forward_outlined,
                    iconColor: AppColors.amber,
                    title: 'Skip to Next Week',
                    subtitle: 'Seed this week, then jump forward 7 days',
                    trailing: _seeding
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : Icon(Icons.chevron_right, color: c.subtle),
                    onTap: _seeding ? null : _runSkipToNextWeek,
                  ),
                  divider(),
                  _settingsTile(
                    context,
                    icon: Icons.restart_alt_outlined,
                    iconColor: Colors.redAccent,
                    title: 'Reset to Day One',
                    subtitle: 'Delete all history and restart from scratch',
                    trailing: _resetting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.redAccent,
                            ),
                          )
                        : Icon(Icons.chevron_right, color: c.subtle),
                    onTap: _resetting ? null : _runReset,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scenarioPicker(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Demo Scenario',
                style: GoogleFonts.inter(
                  color: c.onBackground,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: c.surface,
                    title: Text(
                      'Demo Scenarios',
                      style: GoogleFonts.spaceGrotesk(
                        color: c.onBackground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _scenarioInfo(
                          c,
                          'Level Up',
                          'Simulates a week where you ate under your calorie goal (80%) and found all workouts too easy (rating 1). '
                          'Result: +100 kcal next week, difficulty stepped up.',
                        ),
                        const SizedBox(height: 16),
                        _scenarioInfo(
                          c,
                          'Ease Off',
                          'Simulates a week where workouts felt too hard (rating 5) and you only completed ~40% of them. '
                          'Result: no calorie change, difficulty stepped down.',
                        ),
                        const SizedBox(height: 16),
                        _scenarioInfo(
                          c,
                          'Realistic',
                          'Simulates a typical week — mildly under calories (83%), neutral effort (rating 3), ~70% workout completion. '
                          'Result: +100 kcal, difficulty held steady.',
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Got it',
                            style: TextStyle(color: AppColors.primary)),
                      ),
                    ],
                  ),
                ),
                child: Icon(Icons.info_outline,
                    size: 18, color: c.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<DevScenario>(
            valueListenable: devScenario,
            builder: (context, selected, _) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DevScenario.values.map((s) {
                final isSel = s == selected;
                return ChoiceChip(
                  label: Text(DevTools.scenarioLabel(s)),
                  selected: isSel,
                  onSelected: (_) => devScenario.value = s,
                  showCheckmark: false,
                  backgroundColor: c.background,
                  selectedColor: AppColors.primary,
                  labelStyle: GoogleFonts.inter(
                    color: isSel ? Colors.white : c.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: isSel ? AppColors.primary : c.border,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scenarioInfo(AppColors c, String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: GoogleFonts.inter(color: c.muted, fontSize: 13),
        ),
      ],
    );
  }

  Future<void> _toggleDeveloperMode(bool value) async {
    developerModeEnabled.value = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool('developerMode', value);
    if (!value) {
      // Never leave a real user on a shifted day.
      devDayChangerEnabled.value = false;
      debugDayOffset.value = 0;
    }
  }

  Future<void> _runAutoComplete() async {
    final messenger = ScaffoldMessenger.of(context);
    final msg = await DevTools.autoCompleteToday(context);
    messenger.showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.primary),
    );
  }

  Future<void> _runSkipToNextWeek() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _seeding = true);
    messenger.showSnackBar(
      const SnackBar(content: Text('Seeding last week…')),
    );
    try {
      final msg = await DevTools.simulateWeekAndAdvance(
        context,
        devScenario.value,
      );
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.primary),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Seed failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _runReset() async {
    final c = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Reset to Day One?',
          style: GoogleFonts.spaceGrotesk(
            color: c.onBackground,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'This will permanently delete all workout, nutrition, and progress data. '
          'Your profile settings (goals, equipment, etc.) will be kept.',
          style: GoogleFonts.inter(color: c.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: c.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text('Reset', style: GoogleFonts.inter(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resetting = true);
    try {
      await DevTools.resetAccount(context);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reset failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: GoogleFonts.spaceGrotesk(
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    );
  }

  Widget _settingsTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
    Color? titleColor,
    VoidCallback? onTap,
  }) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: titleColor ?? c.onBackground,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: c.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final c = context.colors;
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool loading = false;
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Change Password',
            style: GoogleFonts.spaceGrotesk(
              color: c.onBackground,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentCtrl,
                obscureText: obscureCurrent,
                style: GoogleFonts.inter(color: c.onBackground),
                decoration: InputDecoration(
                  hintText: 'Current password',
                  fillColor: c.inputFill,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.borderLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.borderLight),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureCurrent ? Icons.visibility_off : Icons.visibility,
                      color: c.muted,
                    ),
                    onPressed: () => setDialogState(() => obscureCurrent = !obscureCurrent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newCtrl,
                obscureText: obscureNew,
                style: GoogleFonts.inter(color: c.onBackground),
                decoration: InputDecoration(
                  hintText: 'New password',
                  fillColor: c.inputFill,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.borderLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.borderLight),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureNew ? Icons.visibility_off : Icons.visibility,
                      color: c.muted,
                    ),
                    onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: obscureConfirm,
                style: GoogleFonts.inter(color: c.onBackground),
                decoration: InputDecoration(
                  hintText: 'Confirm new password',
                  fillColor: c.inputFill,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.borderLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.borderLight),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureConfirm ? Icons.visibility_off : Icons.visibility,
                      color: c.muted,
                    ),
                    onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(color: c.muted),
              ),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      if (newCtrl.text != confirmCtrl.text) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Passwords do not match'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }
                      if (newCtrl.text.length < 6) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Password must be at least 6 characters',
                            ),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }
                      setDialogState(() => loading = true);
                      try {
                        await AuthService().changePassword(
                          currentCtrl.text,
                          newCtrl.text,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Password updated'),
                              backgroundColor: AppColors.primary,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => loading = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('$e'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Update',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
