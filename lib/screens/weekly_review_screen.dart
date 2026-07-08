import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../models/weekly_summary.dart';
import '../providers/profile_provider.dart';
import '../services/firestore_service.dart';
import '../theme/app_colors.dart';
import '../app_clock.dart';

class WeeklyReviewScreen extends StatefulWidget {
  const WeeklyReviewScreen({super.key});

  @override
  State<WeeklyReviewScreen> createState() => _WeeklyReviewScreenState();
}

class _WeeklyReviewScreenState extends State<WeeklyReviewScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _fs = FirestoreService();

  bool _loading = true;
  WeeklySummary? _current;
  List<WeeklySummary> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    final anchorWeekday = context.read<ProfileProvider>().profile?.createdAt?.weekday ?? 1;
    final weekId = FirestoreService.weekIdFor(appNow(), anchorWeekday: anchorWeekday);
    final results = await Future.wait([
      _fs.getWeeklySummary(uid, weekId),
      _fs.getWeeklySummaries(uid),
    ]);
    if (!mounted) return;
    setState(() {
      _current = results[0] as WeeklySummary?;
      _history = results[1] as List<WeeklySummary>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        iconTheme: IconThemeData(color: c.onBackground),
        title: Text(
          'Weekly Review',
          style: GoogleFonts.spaceGrotesk(
            color: c.onBackground,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: c.muted,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Current Week'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : TabBarView(
              controller: _tabs,
              children: [
                _CurrentWeekTab(summary: _current),
                _HistoryTab(history: _history),
              ],
            ),
    );
  }
}

// ─── CURRENT WEEK ──────────────────────────────────────────────────────────────
class _CurrentWeekTab extends StatelessWidget {
  final WeeklySummary? summary;
  const _CurrentWeekTab({required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s == null) {
      return const _EmptyState(
        icon: Icons.insights_rounded,
        title: 'No adaptive report yet',
        message:
            'Your plan adapts at the start of each week once you have a week of '
            'history. Generate next week\'s plan to see your first report.',
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: _SummaryDetailView(summary: s, isCurrent: true),
    );
  }
}

// ─── HISTORY ───────────────────────────────────────────────────────────────────
class _HistoryTab extends StatelessWidget {
  final List<WeeklySummary> history;
  const _HistoryTab({required this.history});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (history.isEmpty) {
      return const _EmptyState(
        icon: Icons.history_rounded,
        title: 'No past weeks yet',
        message:
            'Your history builds week by week. Each weekly adaptation will appear '
            'here so you can look back on how your plan has changed.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      itemCount: history.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == history.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: c.muted, size: 15),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Changes are applied weekly based on your adherence, progress '
                    'and feedback.',
                    style: GoogleFonts.inter(color: c.muted, fontSize: 11),
                  ),
                ),
              ],
            ),
          );
        }
        return _HistoryRow(summary: history[i]);
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final WeeklySummary summary;
  const _HistoryRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final badge = summary.adjustmentBadge;
    final color = _badgeColor(badge);
    final reviewedStart = summary.weekStart.subtract(const Duration(days: 7));
    final reviewedEnd = summary.weekStart.subtract(const Duration(days: 1));
    final isCurrentWeek =
        summary.weekId == FirestoreService.weekIdFor(appNow(), anchorWeekday: context.read<ProfileProvider>().profile?.createdAt?.weekday ?? 1);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _HistoryDetailScreen(summary: summary),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Review: ${_rangeLabel(reviewedStart, reviewedEnd)}',
                  style: GoogleFonts.inter(
                    color: c.onBackground,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              if (isCurrentWeek) ...[
                _BadgeChip(label: 'Current', color: AppColors.primary),
                const SizedBox(width: 6),
              ],
              _BadgeChip(label: badge, color: color),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: c.muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryDetailScreen extends StatelessWidget {
  final WeeklySummary summary;
  const _HistoryDetailScreen({required this.summary});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        iconTheme: IconThemeData(color: c.onBackground),
        title: Text(
          'Weekly Review',
          style: GoogleFonts.spaceGrotesk(
            color: c.onBackground,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: _SummaryDetailView(summary: summary, isCurrent: false),
      ),
    );
  }
}

// ─── REUSABLE DETAIL BODY ──────────────────────────────────────────────────────
class _SummaryDetailView extends StatelessWidget {
  final WeeklySummary summary;
  final bool isCurrent;
  const _SummaryDetailView({required this.summary, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = summary;
    final reviewedStart = s.weekStart.subtract(const Duration(days: 7));
    final reviewedEnd = s.weekStart.subtract(const Duration(days: 1));
    const minNutritionDays = 4;
    final enoughNutrition = s.daysLogged >= minNutritionDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Review: ${_rangeLabel(reviewedStart, reviewedEnd)}',
                style: GoogleFonts.spaceGrotesk(
                  color: c.onBackground,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
            if (isCurrent)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  'Current Week',
                  style: GoogleFonts.inter(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Adjustments applied to ${_rangeLabel(s.weekStart, s.weekEnd)}',
          style: GoogleFonts.inter(color: c.muted, fontSize: 12),
        ),
        const SizedBox(height: 14),

        _Card(
          title: 'Performance Summary',
          subtitle: 'Last week · ${_rangeLabel(reviewedStart, reviewedEnd)}',
          child: Column(
            children: [
              _perfRow(
                context,
                'Calories',
                enoughNutrition ? '${s.calorieAdherence.round()}%' : '—',
                _adherenceTag(enoughNutrition ? s.calorieAdherence : null),
              ),
              _divider(context),
              _perfRow(
                context,
                'Protein',
                s.proteinAdherence != null
                    ? '${s.proteinAdherence!.round()}%'
                    : '—',
                _adherenceTag(s.proteinAdherence),
              ),
              _divider(context),
              _perfRow(
                context,
                'Workouts',
                '${s.workoutsCompleted} / ${s.workoutsPlanned}',
                _workoutTag(s.workoutsCompleted, s.workoutsPlanned),
              ),
              _divider(context),
              _perfRow(
                context,
                'Workout Feedback (avg)',
                _ratingEmoji(s.avgRating),
                _ratingTag(s.avgRating),
              ),
              if (!enoughNutrition)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: c.muted,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Only ${s.daysLogged} day${s.daysLogged == 1 ? '' : 's'} '
                          'logged last week — adherence needs ≥4 days to count.',
                          style: GoogleFonts.inter(
                            color: c.muted,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _Card(
          title: 'AI Adjustments',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isCurrent
                    ? "Based on last week's performance, we've updated this "
                          'week\'s plan.'
                    : "Based on the prior week's performance, your plan was "
                          'updated for this week.',
                style: GoogleFonts.inter(color: c.muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              _adjustRow(
                context,
                'Calories',
                _delta(s.calorieBias, 'kcal'),
                'New target: ${s.newCalorieGoal} kcal',
                _arrowFor(s.calorieBias),
              ),
              if (s.calorieBias != 0) ...[
                _adjustRow(
                  context,
                  'Protein',
                  _delta(s.proteinDelta, 'g'),
                  'New target: ${s.newProtein} g',
                  _arrowFor(s.proteinDelta),
                ),
                _adjustRow(
                  context,
                  'Carbs',
                  _delta(s.carbsDelta, 'g'),
                  'New target: ${s.newCarbs} g',
                  _arrowFor(s.carbsDelta),
                ),
                _adjustRow(
                  context,
                  'Fat',
                  _delta(s.fatDelta, 'g'),
                  'New target: ${s.newFat} g',
                  _arrowFor(s.fatDelta),
                ),
              ],
              _adjustRow(
                context,
                'Workout Intensity',
                _intensityLabel(s),
                _intensitySubtitle(s),
                _intensityArrow(s),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (s.notes.trim().isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.psychology_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Why These Changes?',
                      style: GoogleFonts.spaceGrotesk(
                        color: c.onBackground,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  s.notes,
                  style: GoogleFonts.inter(
                    color: c.muted,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _perfRow(BuildContext context, String label, String value, _Tag tag) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(color: c.onBackground, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              color: c.onBackground,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: Align(
              alignment: Alignment.centerRight,
              child: _BadgeChip(label: tag.label, color: tag.color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _adjustRow(
    BuildContext context,
    String label,
    String value,
    String subtitle,
    _Arrow arrow,
  ) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(color: c.onBackground, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(color: c.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              color: arrow.color,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 4),
          Icon(arrow.icon, color: arrow.color, size: 16),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) =>
      Container(height: 1, color: context.colors.border.withValues(alpha: 0.5));
}

// ─── SMALL SHARED WIDGETS ──────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _Card({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              color: c.onBackground,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: GoogleFonts.inter(color: c.muted, fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final String label;
  final Color color;
  const _BadgeChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 10.5,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: c.border, size: 56),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.spaceGrotesk(
                color: c.onBackground,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: c.muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── VALUE/PRESENTATION HELPERS ────────────────────────────────────────────────
class _Tag {
  final String label;
  final Color color;
  const _Tag(this.label, this.color);
}

class _Arrow {
  final IconData icon;
  final Color color;
  const _Arrow(this.icon, this.color);
}

_Tag _adherenceTag(double? pct) {
  if (pct == null) return _Tag('No data', AppColors.dark.muted);
  if (pct < 90) return const _Tag('Below Goal', AppColors.orange);
  if (pct > 110) return const _Tag('Above Goal', AppColors.orange);
  return const _Tag('On Goal', AppColors.primary);
}

_Tag _workoutTag(int done, int planned) {
  if (planned > 0 && done >= planned)
    return const _Tag('Completed', AppColors.primary);
  if (done == 0) return const _Tag('Missed', Colors.redAccent);
  return const _Tag('Partial', AppColors.orange);
}

_Tag _ratingTag(double? r) {
  if (r == null) return _Tag('No rating', AppColors.dark.muted);
  if (r <= 2.4) return const _Tag('Easy', AppColors.primary);
  if (r >= 3.6) return const _Tag('Hard', AppColors.orange);
  return const _Tag('Moderate', AppColors.purple);
}

String _ratingEmoji(double? r) {
  if (r == null) return '—';
  if (r <= 2.4) return '🙂';
  if (r >= 3.6) return '😓';
  return '😐';
}

String _delta(int v, String unit) {
  if (v == 0) return 'No change';
  final sign = v > 0 ? '+' : '−';
  return '$sign${v.abs()} $unit';
}

_Arrow _arrowFor(int v) {
  if (v > 0) return const _Arrow(Icons.arrow_upward_rounded, AppColors.primary);
  if (v < 0)
    return const _Arrow(Icons.arrow_downward_rounded, AppColors.orange);
  return _Arrow(Icons.remove_rounded, AppColors.dark.muted);
}

String _intensityLabel(WeeklySummary s) {
  if (!s.volumeChanged) return 'Maintained';
  if (s.difficultyBias == 'up') return 'Slightly Increased';
  if (s.difficultyBias == 'down') return 'Slightly Reduced';
  return 'Maintained';
}

String _intensitySubtitle(WeeklySummary s) {
  if (!s.volumeChanged) return 'Same volume as last week';
  if (s.difficultyBias == 'up') return 'More challenging workouts';
  if (s.difficultyBias == 'down') return 'Eased to aid recovery';
  return 'Same volume as last week';
}

_Arrow _intensityArrow(WeeklySummary s) {
  if (!s.volumeChanged)
    return _Arrow(Icons.remove_rounded, AppColors.dark.muted);
  if (s.difficultyBias == 'up') {
    return const _Arrow(Icons.arrow_upward_rounded, AppColors.primary);
  }
  if (s.difficultyBias == 'down') {
    return const _Arrow(Icons.arrow_downward_rounded, AppColors.orange);
  }
  return _Arrow(Icons.remove_rounded, AppColors.dark.muted);
}

Color _badgeColor(String badge) {
  switch (badge) {
    case 'Increased Calories':
    case 'Increased Intensity':
      return AppColors.primary;
    case 'Reduced Calories':
    case 'Reduced Intensity':
      return AppColors.orange;
    default:
      return AppColors.purple;
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}';

String _rangeLabel(DateTime start, DateTime end) =>
    '${_date(start)} – ${_date(end)}';
