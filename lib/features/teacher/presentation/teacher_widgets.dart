import 'package:flutter/material.dart';

import '../../../shared/widgets/async_view.dart';
import '../domain/teacher_models.dart';

/// A labelled number. Used across every staff screen so a figure always reads
/// the same way whoever is looking at it.
class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    this.colour,
    super.key,
  });

  final String label;
  final String value;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: colour,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// One flagged student-skill pair, carrying its triage state.
class StrugglingTile extends StatelessWidget {
  const StrugglingTile({required this.entry, this.alsoFlagged = 0, super.key});

  final StrugglingEntry entry;

  /// How many *other* skills this student is flagged in. Only the collapsed
  /// preview passes it; the full list shows every pair on its own row.
  final int alsoFlagged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final triage = entry.triage;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // A coloured rail rather than a badge: it survives a glance
                // down a long list, which is how this screen gets used.
                Container(
                  width: 4,
                  height: 34,
                  decoration: BoxDecoration(
                    color: triage.colour,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.studentName,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        alsoFlagged > 0
                            ? '${entry.skillName} و$alsoFlagged مهارات أخرى'
                            : entry.skillName,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                MasteryBadge(percentage: entry.currentMastery, size: 38),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              triage.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: triage.colour,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _Fact(
                  icon: Icons.close,
                  text: '${entry.consecutiveFailures} إخفاق متتالٍ',
                ),
                if (entry.remedialCount > 0)
                  _Fact(
                    icon: Icons.auto_fix_high,
                    text: '${entry.remedialCount} دورة علاجية',
                  ),
                if (entry.lastAttemptOn != null)
                  _Fact(
                    icon: Icons.schedule,
                    text: 'آخر محاولة ${_ago(entry.lastAttemptOn!)}',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

String _ago(DateTime when) {
  final diff = DateTime.now().difference(when);

  if (diff.inDays > 1) return 'قبل ${diff.inDays} أيام';
  if (diff.inDays == 1) return 'أمس';
  if (diff.inHours >= 1) return 'قبل ${diff.inHours} ساعة';
  if (diff.inMinutes >= 1) return 'قبل ${diff.inMinutes} دقيقة';
  return 'الآن';
}

/// A roster line — mastery now, and how far the student travelled to get here.
class StudentRow extends StatelessWidget {
  const StudentRow({required this.student, super.key});

  final StudentMastery student;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            MasteryBadge(percentage: student.avgMastery, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          student.studentName,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (student.isStruggling)
                        Icon(
                          Icons.flag,
                          size: 15,
                          color: theme.colorScheme.error,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // The baseline matters more than the score: a student at 65%
                  // who started at 20% is a success story, and one at 65% who
                  // started at 70% is a problem. The bar shows both.
                  GainBar(
                    baseline: student.avgBaseline,
                    current: student.avgMastery,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'أتقن ${student.mastered} من ${student.skills} · '
                    'من ${student.avgBaseline.round()}% إلى '
                    '${student.avgMastery.round()}%',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Baseline and gain on one track: grey for where the student started, green
/// for the distance travelled. Public so its geometry can be asserted — an
/// off-by-a-direction bar in RTL misreports every student on the screen.
class GainBar extends StatelessWidget {
  const GainBar({required this.baseline, required this.current, super.key});

  final double baseline;
  final double current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = (baseline / 100).clamp(0.0, 1.0);
    final end = (current / 100).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return SizedBox(
          height: 6,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              // Baseline segment, then the gain layered on top of it.
              Container(
                width: width * start,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              if (end > start)
                Positioned(
                  right: width * start,
                  child: Container(
                    width: width * (end - start),
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Pre → post for one skill, sized so the gain is the thing you see.
class ImpactBar extends StatelessWidget {
  const ImpactBar({required this.row, super.key});

  final ImpactRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(row.skillName, style: theme.textTheme.bodyMedium),
              ),
              Text(
                '${row.preMastery.round()}% ← ${row.postMastery.round()}%',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
              Text(
                '+${row.gain.round()}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF10B981),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          GainBar(baseline: row.preMastery, current: row.postMastery),
          const SizedBox(height: 4),
          Text(
            '${row.students} طالباً · أتقن ${row.mastered} '
            '(${row.masteryRate.round()}%) · ${row.remedialCycles} دورة علاجية',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
