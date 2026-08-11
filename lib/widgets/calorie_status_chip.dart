import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../algorithms/calorie_tolerance.dart';
import '../theme/app_colors.dart';

/// "On Target" / "Under Target · −N kcal" / "Over Target · +N kcal" pill.
///
/// The single visual expression of the ±5% [CalorieTolerance] band — shared by
/// the Home calorie card and the Nutrition ring so both read identically.
/// Intake inside the band is on target: ordinary logging noise is never shown
/// as a shortfall or an excess.
///
/// Renders **nothing** until something is logged. A day that has not started is
/// not a shortfall, and "Under Target · −2199 kcal" first thing in the morning
/// is a false alarm. For the same reason a *current* day below the band reads
/// "In Progress", not "Under Target" — the day isn't over yet.
class CalorieStatusChip extends StatelessWidget {
  /// Calories logged so far on the day being shown.
  final double consumed;

  /// That day's effective calorie target (`ProfileProvider.dailyEffectiveGoal`).
  final num target;

  /// Whether the day shown is today (still running) or a finished past day.
  final bool isCurrentDay;

  /// Show the numeric band (e.g. "2850–3150 kcal") beneath the pill.
  final bool showRange;

  /// Drop the ± kcal figure from the label. Used where the surrounding card
  /// already shows the same number (the Home card's "Remaining" row) and space
  /// is tight. Never applied to "In Progress", where the remaining figure is
  /// the whole point.
  final bool compact;

  const CalorieStatusChip({
    super.key,
    required this.consumed,
    required this.target,
    this.isCurrentDay = true,
    this.showRange = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = CalorieTolerance.statusFor(
      consumed: consumed,
      target: target,
      isCurrentDay: isCurrentDay,
    );
    if (status == CalorieStatus.notLogged) return const SizedBox.shrink();

    final diff = (consumed - target).abs().round();

    final String label;
    final Color color;
    final IconData icon;
    switch (status) {
      case CalorieStatus.inProgress:
        label = 'In Progress · $diff kcal to go';
        color = c.muted;
        icon = Icons.schedule_rounded;
        break;
      case CalorieStatus.onTarget:
        label = 'On Target';
        color = AppColors.primary;
        icon = Icons.check_circle_rounded;
        break;
      case CalorieStatus.under:
        label = compact ? 'Under Target' : 'Under Target · −$diff kcal';
        color = AppColors.orange;
        icon = Icons.trending_down_rounded;
        break;
      case CalorieStatus.over:
        label = compact ? 'Over Target' : 'Over Target · +$diff kcal';
        color = AppColors.orange;
        icon = Icons.trending_up_rounded;
        break;
      case CalorieStatus.notLogged:
        return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              // Flexible + ellipsis: the pill lives inside narrow cards, and a
              // long label must shrink rather than overflow the card.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showRange) ...[
          const SizedBox(height: 6),
          Text(
            'On-target range '
            '${CalorieTolerance.lower(target).round()}–'
            '${CalorieTolerance.upper(target).round()} kcal (±5%)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(color: c.muted, fontSize: 11),
          ),
        ],
      ],
    );
  }
}
