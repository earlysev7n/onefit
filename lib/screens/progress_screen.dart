import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;
import '../providers/progress_provider.dart';
import '../providers/profile_provider.dart';
import 'weekly_review_screen.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        context.read<ProgressProvider>().loadAll(
          uid,
          profile: context.read<ProfileProvider>().profile,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Consumer<ProgressProvider>(
        builder: (context, prov, _) {
          return RefreshIndicator(
            color: const Color(0xFF00C97B),
            backgroundColor: const Color(0xFF1A1A1A),
            onRefresh: () async {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                await prov.loadAll(
                  uid,
                  profile: context.read<ProfileProvider>().profile,
                );
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Text(
                    'Progress',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Track your fitness journey',
                    style: GoogleFonts.inter(color: const Color(0xFF888888)),
                  ),
                  const SizedBox(height: 24),

                  if (prov.isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: CircularProgressIndicator(
                          color: Color(0xFF00C97B),
                        ),
                      ),
                    )
                  else ...[
                    _TodaySnapshot(prov: prov),
                    const SizedBox(height: 20),
                    const _WeeklyReportCard(),
                    const SizedBox(height: 20),
                    _WeeklyAchievements(prov: prov),
                    const SizedBox(height: 20),
                    _CalorieTrendChart(prov: prov),
                    const SizedBox(height: 20),
                    _MacroTrendChart(prov: prov),
                    const SizedBox(height: 20),
                    _WeightSection(prov: prov),
                    const SizedBox(height: 20),
                    _MilestonesSection(prov: prov),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── TODAY SNAPSHOT ────────────────────────────────────────────────────────────
class _TodaySnapshot extends StatelessWidget {
  final ProgressProvider prov;
  const _TodaySnapshot({required this.prov});

  @override
  Widget build(BuildContext context) {
    final calProgress = prov.calorieGoal > 0
        ? (prov.todayCalories / prov.calorieGoal).clamp(0.0, 1.0)
        : 0.0;
    final protProgress = prov.proteinGoal > 0
        ? (prov.todayProtein / prov.proteinGoal).clamp(0.0, 1.0)
        : 0.0;

    return _SectionCard(
      title: 'Today',
      child: Row(
        children: [
          // Calorie ring
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CustomPaint(
                    painter: _RingPainter(calProgress, const Color(0xFF00C97B)),
                    child: Center(
                      child: Text(
                        '${prov.todayCalories.round()}',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Calories',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF888888),
                    fontSize: 11,
                  ),
                ),
                Text(
                  '/ ${prov.calorieGoal} kcal',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF555555),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          // Protein bar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Protein',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF888888),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: protProgress,
                    backgroundColor: const Color(0xFF2E2E2E),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF00C97B)),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${prov.todayProtein.round()} / ${prov.proteinGoal.round()}g',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Workout status
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: prov.todayWorkoutLog != null
                        ? const Color(0xFF00C97B).withOpacity(0.15)
                        : const Color(0xFF1E1E1E),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    prov.todayWorkoutLog != null
                        ? Icons.check_circle_rounded
                        : Icons.fitness_center_rounded,
                    color: prov.todayWorkoutLog != null
                        ? const Color(0xFF00C97B)
                        : const Color(0xFF444444),
                    size: 26,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  prov.todayWorkoutLog != null ? 'Done!' : 'No workout',
                  style: GoogleFonts.inter(
                    color: prov.todayWorkoutLog != null
                        ? const Color(0xFF00C97B)
                        : const Color(0xFF888888),
                    fontSize: 11,
                  ),
                ),
                if (prov.todayWorkoutLog != null)
                  Text(
                    '${prov.todayWorkoutLog!.durationMinutes} min',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF555555),
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── WEEKLY ADAPTIVE REPORT ENTRY ──────────────────────────────────────────────
class _WeeklyReportCard extends StatelessWidget {
  const _WeeklyReportCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const WeeklyReviewScreen())),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF00C97B).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.description_rounded,
                  color: Color(0xFF00C97B),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Weekly Adaptive Report',
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'View your performance review, adjustments and reasoning',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF888888),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF888888),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── WEEKLY ACHIEVEMENTS ───────────────────────────────────────────────────────
class _WeeklyAchievements extends StatelessWidget {
  final ProgressProvider prov;
  const _WeeklyAchievements({required this.prov});

  @override
  Widget build(BuildContext context) {
    final adherence = prov.calorieAdherence;
    final adherenceColor = adherence >= 90
        ? const Color(0xFF00C97B)
        : adherence >= 75
        ? const Color(0xFFFF6B35)
        : Colors.redAccent;

    return _SectionCard(
      title: 'This Week',
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.0,
        children: [
          _StatTile(
            label: 'Calorie Adherence',
            value: '${adherence.round()}%',
            color: adherenceColor,
            icon: Icons.local_fire_department_rounded,
          ),
          _StatTile(
            label: 'Workout Streak',
            value: '${prov.workoutStreak} days',
            color: const Color(0xFF6C63FF),
            icon: Icons.bolt_rounded,
          ),
          _StatTile(
            label: 'Workouts Done',
            value: '${prov.weekWorkoutLogs.length} this week',
            color: const Color(0xFFFF6B35),
            icon: Icons.fitness_center_rounded,
          ),
          _StatTile(
            label: 'Protein Consistency',
            value: '${prov.proteinConsistency.round()}%',
            color: const Color(0xFF00C97B),
            icon: Icons.egg_alt_rounded,
          ),
        ],
      ),
    );
  }
}

// ─── CALORIE TREND CHART ───────────────────────────────────────────────────────
class _CalorieTrendChart extends StatelessWidget {
  final ProgressProvider prov;
  const _CalorieTrendChart({required this.prov});

  @override
  Widget build(BuildContext context) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final goal = prov.calorieGoal.toDouble();
    final maxY = math.max(goal * 1.3, 500.0);

    final bars = days.asMap().entries.map((e) {
      final cal = prov.weeklyCalories[e.value] ?? 0.0;
      final color = cal > goal * 1.05
          ? const Color(0xFFFF6B35)
          : const Color(0xFF00C97B);
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: cal,
            color: color,
            width: 16,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    }).toList();

    return _SectionCard(
      title: 'Calorie Trend',
      subtitle: '7-day · goal ${prov.calorieGoal} kcal',
      child: SizedBox(
        height: 160,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: goal / 2,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: const Color(0xFF2E2E2E), strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) => Text(
                    days[v.toInt()],
                    style: GoogleFonts.inter(
                      color: const Color(0xFF555555),
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ),
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                HorizontalLine(
                  y: goal,
                  color: const Color(0xFF00C97B).withOpacity(0.4),
                  strokeWidth: 1.5,
                  dashArray: [6, 4],
                ),
              ],
            ),
            barGroups: bars,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                  '${rod.toY.round()} kcal',
                  GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── MACRO TREND CHART ────────────────────────────────────────────────────────
class _MacroTrendChart extends StatelessWidget {
  final ProgressProvider prov;
  const _MacroTrendChart({required this.prov});

  @override
  Widget build(BuildContext context) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    List<FlSpot> _spots(String macro) => days
        .asMap()
        .entries
        .map(
          (e) =>
              FlSpot(e.key.toDouble(), prov.weeklyMacros[e.value]?[macro] ?? 0),
        )
        .toList();

    double maxY = 10;
    for (final day in prov.weeklyMacros.values) {
      final v = [
        day['protein'] ?? 0,
        day['carbs'] ?? 0,
        day['fat'] ?? 0,
      ].reduce(math.max);
      if (v > maxY) maxY = v;
    }
    maxY = math.max(maxY * 1.2, 50.0);

    return _SectionCard(
      title: 'Macro Trend',
      subtitle: '7-day · grams per day',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _legend('Protein', const Color(0xFF00C97B)),
              const SizedBox(width: 12),
              _legend('Carbs', const Color(0xFF6C63FF)),
              const SizedBox(width: 12),
              _legend('Fat', const Color(0xFFFF6B35)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: const Color(0xFF2E2E2E), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= days.length)
                          return const SizedBox.shrink();
                        return Text(
                          days[i],
                          style: GoogleFonts.inter(
                            color: const Color(0xFF555555),
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  _line(_spots('protein'), const Color(0xFF00C97B)),
                  _line(_spots('carbs'), const Color(0xFF6C63FF)),
                  _line(_spots('fat'), const Color(0xFFFF6B35)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) => LineChartBarData(
    spots: spots,
    isCurved: true,
    color: color,
    barWidth: 2,
    dotData: FlDotData(
      getDotPainter: (_, __, ___, ____) =>
          FlDotCirclePainter(radius: 3, color: color, strokeWidth: 0),
    ),
    belowBarData: BarAreaData(show: true, color: color.withOpacity(0.08)),
  );

  Widget _legend(String label, Color color) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: GoogleFonts.inter(color: const Color(0xFF888888), fontSize: 11),
      ),
    ],
  );
}

// ─── WEIGHT SECTION ───────────────────────────────────────────────────────────
class _WeightSection extends StatelessWidget {
  final ProgressProvider prov;
  const _WeightSection({required this.prov});

  @override
  Widget build(BuildContext context) {
    final logs = prov.weightLogs;
    final useImperial = prov.profile?.unitSystem == 'imperial';

    double _kg(double kg) => useImperial ? kg * 2.20462 : kg;
    String _unit() => useImperial ? 'lbs' : 'kg';

    return _SectionCard(
      title: 'Weight',
      child: Column(
        children: [
          if (logs.length >= 2) ...[
            // Chart
            SizedBox(
              height: 130,
              child: LineChart(
                LineChartData(
                  minY: logs.map((l) => _kg(l.weight)).reduce(math.min) - 2,
                  maxY: logs.map((l) => _kg(l.weight)).reduce(math.max) + 2,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: const Color(0xFF2E2E2E), strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (v, _) => Text(
                          v.toStringAsFixed(1),
                          style: GoogleFonts.inter(
                            color: const Color(0xFF555555),
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: logs.reversed
                          .toList()
                          .asMap()
                          .entries
                          .map(
                            (e) =>
                                FlSpot(e.key.toDouble(), _kg(e.value.weight)),
                          )
                          .toList(),
                      isCurved: true,
                      color: const Color(0xFF6C63FF),
                      barWidth: 2,
                      dotData: FlDotData(
                        getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                          radius: 3,
                          color: const Color(0xFF6C63FF),
                          strokeWidth: 0,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFF6C63FF).withOpacity(0.08),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _weightStat(
                  'Start',
                  '${_kg(prov.startWeight!).toStringAsFixed(1)} ${_unit()}',
                  const Color(0xFF888888),
                ),
                _weightStat(
                  'Current',
                  '${_kg(prov.latestWeight!).toStringAsFixed(1)} ${_unit()}',
                  const Color(0xFF6C63FF),
                ),
                _weightStat(
                  'Change',
                  '${(_kg(prov.latestWeight!) - _kg(prov.startWeight!)) >= 0 ? '+' : ''}${(_kg(prov.latestWeight!) - _kg(prov.startWeight!)).toStringAsFixed(1)} ${_unit()}',
                  (_kg(prov.latestWeight!) - _kg(prov.startWeight!)).abs() < 0.1
                      ? const Color(0xFF888888)
                      : const Color(0xFF00C97B),
                ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                logs.isEmpty
                    ? 'Log your weight to start tracking your trend'
                    : 'Log weight for 2+ days to see your trend',
                style: GoogleFonts.inter(
                  color: const Color(0xFF555555),
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showLogWeightDialog(context),
              icon: const Icon(Icons.monitor_weight_outlined, size: 16),
              label: Text(
                "Log Today's Weight",
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6C63FF),
                side: const BorderSide(color: Color(0xFF6C63FF)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weightStat(String label, String value, Color color) => Column(
    children: [
      Text(
        value,
        style: GoogleFonts.spaceGrotesk(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
      Text(
        label,
        style: GoogleFonts.inter(color: const Color(0xFF888888), fontSize: 11),
      ),
    ],
  );

  void _showLogWeightDialog(BuildContext context) {
    final useImperial =
        context.read<ProgressProvider>().profile?.unitSystem == 'imperial';
    final latest = context.read<ProgressProvider>().latestWeight;
    final displayVal = latest != null
        ? (useImperial
              ? (latest * 2.20462).toStringAsFixed(1)
              : latest.toStringAsFixed(1))
        : '';
    final controller = TextEditingController(text: displayVal);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Log Today's Weight",
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 20),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF222222),
                suffixText: useImperial ? 'lbs' : 'kg',
                suffixStyle: GoogleFonts.inter(color: const Color(0xFF888888)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final val = double.tryParse(controller.text);
                  if (val == null) return;
                  final kg = useImperial ? val / 2.20462 : val;
                  // Capture providers before the async gap / pop.
                  final profileProvider = context.read<ProfileProvider>();
                  final progressProvider = context.read<ProgressProvider>();
                  Navigator.pop(context);
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid != null) {
                    // Sync the body weight first so BMR/TDEE/calorieGoal/BMI
                    // recompute reactively on Home & Nutrition; then reload
                    // Progress, whose internal loadAll re-fetches the updated
                    // profile so its own BMI/TDEE card reflects the change too.
                    await profileProvider.updateWeight(kg);
                    await progressProvider.logWeight(uid, kg);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Save',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── MILESTONES ───────────────────────────────────────────────────────────────
class _MilestonesSection extends StatelessWidget {
  final ProgressProvider prov;
  const _MilestonesSection({required this.prov});

  @override
  Widget build(BuildContext context) {
    final totalWorkouts =
        prov.weekWorkoutLogs.length +
        (prov.todayWorkoutLog != null ? 0 : 0); // all-time would need more data

    final badges = [
      _Badge(
        'First Workout',
        Icons.fitness_center_rounded,
        const Color(0xFF00C97B),
        prov.weekWorkoutLogs.isNotEmpty || prov.todayWorkoutLog != null,
      ),
      _Badge(
        '3-Day Streak',
        Icons.bolt_rounded,
        const Color(0xFF6C63FF),
        prov.workoutStreak >= 3,
      ),
      _Badge(
        '7-Day Streak',
        Icons.local_fire_department_rounded,
        const Color(0xFFFF6B35),
        prov.workoutStreak >= 7,
      ),
      _Badge(
        'On Track',
        Icons.track_changes_rounded,
        const Color(0xFFFFD60A),
        prov.calorieAdherence >= 80,
      ),
      _Badge(
        'Iron Will',
        Icons.emoji_events_rounded,
        const Color(0xFFFF6B35),
        totalWorkouts >= 5,
      ),
      _Badge(
        'Protein Pro',
        Icons.egg_alt_rounded,
        const Color(0xFF00C97B),
        prov.proteinConsistency >= 70,
      ),
      _Badge(
        'Consistent',
        Icons.calendar_today_rounded,
        const Color(0xFF6C63FF),
        prov.weeklyCalories.values.where((v) => v > 0).length >= 5,
      ),
    ];

    return _SectionCard(
      title: 'Milestones',
      child: SizedBox(
        height: 100,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: badges.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => _BadgeChip(badge: badges[i]),
        ),
      ),
    );
  }
}

class _Badge {
  final String label;
  final IconData icon;
  final Color color;
  final bool unlocked;
  const _Badge(this.label, this.icon, this.color, this.unlocked);
}

class _BadgeChip extends StatelessWidget {
  final _Badge badge;
  const _BadgeChip({required this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: badge.unlocked
            ? badge.color.withOpacity(0.12)
            : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: badge.unlocked
              ? badge.color.withOpacity(0.4)
              : const Color(0xFF2E2E2E),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            badge.unlocked ? badge.icon : Icons.lock_rounded,
            color: badge.unlocked ? badge.color : const Color(0xFF444444),
            size: 24,
          ),
          const SizedBox(height: 6),
          Text(
            badge.label,
            style: GoogleFonts.inter(
              color: badge.unlocked ? badge.color : const Color(0xFF444444),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

// ─── SHARED WIDGETS ───────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _SectionCard({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(width: 8),
                Text(
                  subtitle!,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF555555),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: GoogleFonts.spaceGrotesk(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF888888),
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RingPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF2E2E2E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
