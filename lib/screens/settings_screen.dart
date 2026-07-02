import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../providers/profile_provider.dart';
import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';
import 'profile_input_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showGoalPopup = true;

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
            ],
          ),
        ),
      ),
    );
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
                obscureText: true,
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
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newCtrl,
                obscureText: true,
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
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
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
