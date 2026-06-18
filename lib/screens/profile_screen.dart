import '../main.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/profile_provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../data/seed_data.dart';
import 'login_screen.dart';
import 'profile_input_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>().profile;
    final macros = profile?.macroGoals ?? {};
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profile',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),

            // Avatar + name
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: const Color(0xFF00C97B).withOpacity(0.15),
                    child: Text(
                      (profile?.name.isNotEmpty == true)
                          ? profile!.name[0].toUpperCase()
                          : 'A',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF00C97B),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile?.name ?? 'Athlete',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    AuthService().currentUser?.email ?? '',
                    style: GoogleFonts.inter(color: const Color(0xFF888888)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Daily Targets card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF00C97B).withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        color: Color(0xFF00C97B),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Daily Targets',
                        style: GoogleFonts.spaceGrotesk(
                          color: const Color(0xFF00C97B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Calorie goal big number
                  Center(
                    child: Column(
                      children: [
                        Text(
                          '${profile?.calorieGoal ?? 2000}',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'kcal / day',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF888888),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildMacroTarget(
                        'Protein',
                        '${macros['protein'] ?? 0}g',
                        const Color(0xFF00C97B),
                      ),
                      _buildMacroTarget(
                        'Carbs',
                        '${macros['carbs'] ?? 0}g',
                        const Color(0xFF6C63FF),
                      ),
                      _buildMacroTarget(
                        'Fat',
                        '${macros['fat'] ?? 0}g',
                        const Color(0xFFFF6B35),
                      ),
                      _buildMacroTarget(
                        'Fiber',
                        '${macros['fiber'] ?? 0}g',
                        const Color(0xFF00B4D8),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Color(0xFF2E2E2E)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'BMR',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF888888),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${profile?.bmr ?? 0} kcal',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'TDEE',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF888888),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${profile?.tdee ?? 0} kcal',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'BMI',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF888888),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        profile?.bmiDisplay ?? '-',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Biometrics
            _buildInfoCard('Biometrics', [
              _infoRow('Age', '${profile?.age ?? '-'} yrs'),
              _infoRow('Weight', profile?.weightDisplay ?? '-'),
              _infoRow('Height', profile?.heightDisplay ?? '-'),
              _infoRow('Gender', profile?.gender ?? '-'),
              _infoRow(
                'Units',
                profile?.unitSystem == 'imperial' ? 'Imperial' : 'Metric',
              ),
              _infoRow(
                'Avg Sleep',
                '${profile?.avgHoursSlept.toStringAsFixed(1) ?? '-'} h',
              ),
            ]),
            const SizedBox(height: 12),

            // Fitness
            _buildInfoCard('Fitness', [
              _infoRow('Goal', profile?.fitnessGoal ?? '-'),
              _infoRow('Level', profile?.experienceLevel ?? '-'),
              _infoRow('Activity', profile?.activityLevel ?? '-'),
              _infoRow('Location', profile?.workoutLocation ?? '-'),
              _infoRow('Split', profile?.workoutSplit ?? '-'),
              _infoRow('Days / Week', '${profile?.workoutDaysPerWeek ?? '-'}'),
              _infoRow('Session', '${profile?.sessionMinutes ?? '-'} min'),
              if (profile?.equipment.isNotEmpty == true)
                _infoRow('Equipment', profile!.equipment.join(', ')),
            ]),
            const SizedBox(height: 12),

            // Diet
            _buildInfoCard('Diet', [
              _infoRow(
                'Restrictions',
                profile?.dietaryRestrictions.isEmpty == true
                    ? 'None'
                    : profile!.dietaryRestrictions.join(', '),
              ),
              _infoRow('Sugar limit', '${profile?.macroGoals['sugar'] ?? 50}g'),
              _infoRow(
                'Sodium limit',
                '${profile?.macroGoals['sodium'] ?? 2300}mg',
              ),
            ]),
            const SizedBox(height: 24),

            // Edit Profile — reuses the onboarding screen in edit mode.
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: profile == null
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ProfileInputScreen(existing: profile),
                          ),
                        ),
                icon: const Icon(Icons.edit_outlined, color: Colors.black),
                label: Text(
                  'Edit Profile',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C97B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Dev-only: one-tap seeding of the USDA `ingredients` collection
            // that the Genetic Algorithm draws on. Gated by kShowSeedTools.
            if (kShowSeedTools) ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.showSnackBar(const SnackBar(
                      content: Text('Seeding ingredients… this may take a minute.'),
                      duration: Duration(minutes: 2),
                    ));
                    try {
                      await SeedData.seedIngredients();
                      // Drop the in-memory cache so the freshly seeded fields
                      // (allergens / category) load on the next read.
                      FirestoreService.clearIngredientCache();
                      messenger.hideCurrentSnackBar();
                      messenger.showSnackBar(const SnackBar(
                        content: Text('Ingredients seeded ✓'),
                        backgroundColor: Color(0xFF00C97B),
                      ));
                    } catch (e) {
                      messenger.hideCurrentSnackBar();
                      messenger.showSnackBar(SnackBar(
                        content: Text('Seed failed: $e'),
                        backgroundColor: Colors.redAccent,
                      ));
                    }
                  },
                  icon: const Icon(Icons.cloud_upload_outlined, color: Color(0xFF00C97B)),
                  label: Text(
                    'Seed Ingredients',
                    style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF00C97B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF00C97B)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await AuthService().signOut();
                  navigatorKey.currentState?.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.logout, color: Colors.redAccent),
                label: Text(
                  'Sign Out',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMacroTarget(String label, String value, Color color) {
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
            style: GoogleFonts.inter(
              color: const Color(0xFF888888),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, List<Widget> rows) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              color: const Color(0xFF00C97B),
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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(color: const Color(0xFF888888))),
          Text(
            value,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
