import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/weekly_summary.dart';
import '../services/firestore_service.dart';
import '../app_clock.dart';

// Shared design tokens (kept inline per project convention).
const _kBg = Color(0xFF0D0D0D);
const _kSurface = Color(0xFF1A1A1A);
const _kAccent = Color(0xFF00C97B);
const _kMuted = Color(0xFF888888);
const _kBorder = Color(0xFF2E2E2E);
const _kOrange = Color(0xFFFF6B35);
const _kPurple = Color(0xFF6C63FF);

/// Weekly Adaptive Report. Surfaces the adaptation snapshots persisted by
/// `plans_screen._generate()` — the current week's review plus past-week history.
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
    final weekId = FirestoreService.weekIdFor(appNow());
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
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Weekly Review',
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _kAccent,
          labelColor: _kAccent,
          unselectedLabelColor: _kMuted,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Current Week'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
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
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == history.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: _kMuted, size: 15),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Changes are applied weekly based on your adherence, progress '
                    'and feedback.',
                    style: GoogleFonts.inter(color: _kMuted, fontSize: 11),
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
    final badge = summary.adjustmentBadge;
    final color = _badgeColor(badge);
    return Material(
      color: _kSurface,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _rangeLabel(summary.weekStart, summary.weekEnd),
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _weekLabel(summary.weekId),
                      style: GoogleFonts.inter(color: _kMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              _BadgeChip(label: badge, color: color),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: _kMuted, size: 20),
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
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Weekly Review',
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white,
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
    final s = summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Expanded(
              child: Text(
                'Week of ${_rangeLabel(s.weekStart, s.weekEnd)}',
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
            if (isCurrent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kAccent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'Current Week',
                  style: GoogleFonts.inter(
                    color: _kAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),

        // Performance summary
        _Card(
          title: 'Performance Summary',
          child: Column(
            children: [
              _perfRow(
                'Calories',
                s.daysLogged > 0 ? '${s.calorieAdherence.round()}%' : '—',
                _adherenceTag(s.daysLogged > 0 ? s.calorieAdherence : null),
              ),
              _divider(),
              _perfRow(
                'Protein',
                s.proteinAdherence != null
                    ? '${s.proteinAdherence!.round()}%'
                    : '—',
                _adherenceTag(s.proteinAdherence),
              ),
              _divider(),
              _perfRow(
                'Workouts',
                '${s.workoutsCompleted} / ${s.workoutsPlanned}',
                _workoutTag(s.workoutsCompleted, s.workoutsPlanned),
              ),
              _divider(),
              _perfRow(
                'Workout Feedback (avg)',
                _ratingEmoji(s.avgRating),
                _ratingTag(s.avgRating),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // AI adjustments
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
                style: GoogleFonts.inter(color: _kMuted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              _adjustRow(
                'Calories',
                _delta(s.calorieBias, 'kcal'),
                'New target: ${s.newCalorieGoal} kcal',
                _arrowFor(s.calorieBias),
              ),
              if (s.calorieBias != 0) ...[
                _adjustRow(
                  'Protein',
                  _delta(s.proteinDelta, 'g'),
                  'New target: ${s.newProtein} g',
                  _arrowFor(s.proteinDelta),
                ),
                _adjustRow(
                  'Carbs',
                  _delta(s.carbsDelta, 'g'),
                  'New target: ${s.newCarbs} g',
                  _arrowFor(s.carbsDelta),
                ),
                _adjustRow(
                  'Fat',
                  _delta(s.fatDelta, 'g'),
                  'New target: ${s.newFat} g',
                  _arrowFor(s.fatDelta),
                ),
              ],
              _adjustRow(
                'Workout Intensity',
                _intensityLabel(s),
                _intensitySubtitle(s),
                _intensityArrow(s),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Why these changes
        if (s.notes.trim().isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.psychology_rounded,
                        color: _kAccent, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Why These Changes?',
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
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
                    color: const Color(0xFFBBBBBB),
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

  // ── Row builders ─────────────────────────────────────────────────────────
  Widget _perfRow(String label, String value, _Tag tag) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white,
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

  Widget _adjustRow(String label, String value, String subtitle, _Arrow arrow) =>
      Padding(
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
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(color: _kMuted, fontSize: 11),
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

  Widget _divider() =>
      Container(height: 1, color: _kBorder.withValues(alpha: 0.5));
}

// ─── SMALL SHARED WIDGETS ──────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _kBorder, size: 56),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: _kMuted, fontSize: 13, height: 1.4),
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
  if (pct == null) return const _Tag('No data', _kMuted);
  if (pct < 90) return const _Tag('Below Goal', _kOrange);
  if (pct > 110) return const _Tag('Above Goal', _kOrange);
  return const _Tag('On Goal', _kAccent);
}

_Tag _workoutTag(int done, int planned) {
  if (planned > 0 && done >= planned) return const _Tag('Completed', _kAccent);
  if (done == 0) return const _Tag('Missed', Colors.redAccent);
  return const _Tag('Partial', _kOrange);
}

_Tag _ratingTag(double? r) {
  if (r == null) return const _Tag('No rating', _kMuted);
  if (r <= 2.4) return const _Tag('Easy', _kAccent);
  if (r >= 3.6) return const _Tag('Hard', _kOrange);
  return const _Tag('Moderate', _kPurple);
}

String _ratingEmoji(double? r) {
  if (r == null) return '—';
  if (r <= 2.4) return '🙂';
  if (r >= 3.6) return '😓';
  return '😐';
}

/// Signed delta string, e.g. "+150 kcal", "−10 g", "No change".
String _delta(int v, String unit) {
  if (v == 0) return 'No change';
  final sign = v > 0 ? '+' : '−';
  return '$sign${v.abs()} $unit';
}

_Arrow _arrowFor(int v) {
  if (v > 0) return const _Arrow(Icons.arrow_upward_rounded, _kAccent);
  if (v < 0) return const _Arrow(Icons.arrow_downward_rounded, _kOrange);
  return const _Arrow(Icons.remove_rounded, _kMuted);
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
  if (!s.volumeChanged) return const _Arrow(Icons.remove_rounded, _kMuted);
  if (s.difficultyBias == 'up') {
    return const _Arrow(Icons.arrow_upward_rounded, _kAccent);
  }
  if (s.difficultyBias == 'down') {
    return const _Arrow(Icons.arrow_downward_rounded, _kOrange);
  }
  return const _Arrow(Icons.remove_rounded, _kMuted);
}

Color _badgeColor(String badge) {
  switch (badge) {
    case 'Increased Calories':
    case 'Increased Intensity':
      return _kAccent;
    case 'Reduced Calories':
    case 'Reduced Intensity':
      return _kOrange;
    default:
      return _kPurple;
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}';

String _rangeLabel(DateTime start, DateTime end) =>
    '${_date(start)} – ${_date(end)}';

/// "week_2026_25" → "Week 25".
String _weekLabel(String weekId) {
  final parts = weekId.split('_');
  if (parts.length >= 3) return 'Week ${parts.last}';
  return weekId;
}
