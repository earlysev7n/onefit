import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/user_profile.dart';
import '../providers/profile_provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../data/seed_data.dart';
import '../theme/app_colors.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final profileProvider = context.watch<ProfileProvider>();
    final profile = profileProvider.profile;
    final macros = profileProvider.effectiveMacroGoals;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with gear icon
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Profile',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: c.onBackground,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.settings_outlined,
                      color: c.muted,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Avatar + name
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: AppColors.primary.withOpacity(0.15),
                    child: Text(
                      (profile?.name.isNotEmpty == true)
                          ? profile!.name[0].toUpperCase()
                          : 'A',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile?.name ?? 'Athlete',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: c.onBackground,
                    ),
                  ),
                  Text(
                    AuthService().currentUser?.email ?? '',
                    style: GoogleFonts.inter(color: c.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Daily Targets card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Daily Targets',
                        style: GoogleFonts.spaceGrotesk(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        Text(
                          '${profileProvider.dailyEffectiveGoal}',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: c.onBackground,
                          ),
                        ),
                        Text(
                          'kcal / day',
                          style: GoogleFonts.inter(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildMacroTarget(
                        context,
                        'Protein',
                        '${macros['protein'] ?? 0}g',
                        AppColors.primary,
                      ),
                      _buildMacroTarget(
                        context,
                        'Carbs',
                        '${macros['carbs'] ?? 0}g',
                        AppColors.purple,
                      ),
                      _buildMacroTarget(
                        context,
                        'Fat',
                        '${macros['fat'] ?? 0}g',
                        AppColors.orange,
                      ),
                      _buildMacroTarget(
                        context,
                        'Fiber',
                        '${macros['fiber'] ?? 0}g',
                        AppColors.cyan,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(color: c.border),
                  const SizedBox(height: 8),
                  _infoRow(context, 'BMR', '${profile?.bmr ?? 0} kcal'),
                  const SizedBox(height: 6),
                  _infoRow(context, 'TDEE', '${profile?.tdee ?? 0} kcal'),
                  const SizedBox(height: 6),
                  _infoRow(context, 'BMI', profile?.bmiDisplay ?? '-'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _buildInfoCard(context, 'Biometrics', [
              _infoRow(context, 'Age', '${profile?.age ?? '-'} yrs'),
              _infoRow(context, 'Weight', profile?.weightDisplay ?? '-'),
              _infoRow(context, 'Height', profile?.heightDisplay ?? '-'),
              _infoRow(context, 'Gender', profile?.gender ?? '-'),
              _infoRow(
                context,
                'Units',
                profile?.unitSystem == 'imperial' ? 'Imperial' : 'Metric',
              ),
            ]),
            const SizedBox(height: 12),

            _buildInfoCard(context, 'Fitness', [
              _infoRow(context, 'Goal', profile?.fitnessGoal ?? '-'),
              _infoRow(context, 'Level', profile?.experienceLevel ?? '-'),
              _infoRow(context, 'Activity', profile?.activityLevel ?? '-'),
              _infoRow(context, 'Location', profile?.workoutLocation ?? '-'),
              _infoRow(context, 'Split', profile?.workoutSplit ?? '-'),
              _infoRow(
                context,
                'Days / Week',
                '${profile?.workoutDaysPerWeek ?? '-'}',
              ),
              _infoRow(
                context,
                'Session',
                '${profile?.sessionMinutes ?? '-'} min',
              ),
              if (profile?.equipment.isNotEmpty == true)
                _infoRow(context, 'Equipment', profile!.equipment.join(', ')),
            ]),
            const SizedBox(height: 12),

            _buildInfoCard(context, 'Diet', [
              _infoRow(
                context,
                'Style',
                profile?.dietaryRestrictions.firstWhere(
                      _dietStyleOptions.contains,
                      orElse: () => 'Balanced',
                    ) ??
                    'Balanced',
              ),
              _infoRow(context, 'Restrictions', _restrictionsLabel(profile)),
            ]),
            const SizedBox(height: 24),

            if (kShowSeedTools) ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Seeding ingredients… this may take a minute.',
                        ),
                        duration: Duration(minutes: 2),
                      ),
                    );
                    try {
                      await SeedData.seedIngredients();
                      FirestoreService.clearIngredientCache();
                      messenger.hideCurrentSnackBar();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Ingredients seeded'),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                    } catch (e) {
                      messenger.hideCurrentSnackBar();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Seed failed: $e'),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    }
                  },
                  icon: const Icon(
                    Icons.cloud_upload_outlined,
                    color: AppColors.primary,
                  ),
                  label: Text(
                    'Seed Ingredients',
                    style: GoogleFonts.spaceGrotesk(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMacroTarget(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(color: context.colors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  static const _dietStyleOptions = {'High-protein', 'Low-carb', 'Balanced'};

  String _restrictionsLabel(UserProfile? profile) {
    final restrictions = (profile?.dietaryRestrictions ?? [])
        .where((r) => !_dietStyleOptions.contains(r))
        .toList();
    return restrictions.isEmpty ? 'None' : restrictions.join(', ');
  }

  Widget _buildInfoCard(BuildContext context, String title, List<Widget> rows) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(color: c.muted)),
          Text(
            value,
            style: GoogleFonts.inter(
              color: c.onBackground,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
