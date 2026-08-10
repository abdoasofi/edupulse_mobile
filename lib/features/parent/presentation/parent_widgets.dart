import 'package:flutter/material.dart';

import '../../../shared/arabic.dart' as ar;
import '../domain/parent_models.dart';

/// The colour a child's state is allowed to use.
///
/// Only one thing on this screen is ever red, and only when the school's own
/// remedial loop has already been tried and failed. A parent who sees red for
/// ordinary variation stops reading the colour at all.
extension ChildStateStyle on ChildState {
  Color colour(ColorScheme scheme) => switch (this) {
    ChildState.needsHelp => scheme.error,
    ChildState.behind => const Color(0xFFF59E0B),
    ChildState.fine => const Color(0xFF10B981),
  };

  String get label => switch (this) {
    ChildState.needsHelp => 'يحتاج متابعة',
    ChildState.behind => 'دون المتوقّع',
    ChildState.fine => 'يسير جيداً',
  };

  IconData get icon => switch (this) {
    ChildState.needsHelp => Icons.flag_outlined,
    ChildState.behind => Icons.trending_down,
    ChildState.fine => Icons.check_circle_outline,
  };
}

/// A child's row on the guardian's home screen.
class ChildCard extends StatelessWidget {
  const ChildCard({required this.child, required this.onTap, super.key});

  final Child child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = child.state;
    final colour = state.colour(theme.colorScheme);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _Avatar(child: child, colour: colour),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(child.name, style: theme.textTheme.titleMedium),
                    if (child.classLine != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        child.classLine!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(state.icon, size: 15, color: colour),
                        const SizedBox(width: 5),
                        Text(
                          state.label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colour,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (child.flaggedCount > 0)
                          Text(
                            ' · ${ar.counted(child.flaggedCount, ar.skills)}',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.child, required this.colour});

  final Child child;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final initial = child.name.trim().isEmpty ? '؟' : child.name.trim()[0];

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colour.withValues(alpha: 0.12),
        // The ring carries the state, so the card needs no coloured banner and
        // the child's name stays the loudest thing on the row.
        border: Border.all(color: colour.withValues(alpha: 0.55), width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: colour,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// A number with its label, sized for a parent glancing rather than reading.
class ParentStat extends StatelessWidget {
  const ParentStat({
    required this.value,
    required this.label,
    this.colour,
    super.key,
  });

  final String value;
  final String label;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
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

/// One flagged skill, told as a sentence a parent can act on.
class FlaggedSkillTile extends StatelessWidget {
  const FlaggedSkillTile({required this.skill, super.key});

  final FlaggedSkill skill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exhausted = skill.engineExhausted;
    final colour = exhausted
        ? theme.colorScheme.error
        : const Color(0xFFF59E0B);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 38,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(skill.skillName, style: theme.textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  // What the school has already done comes before what is
                  // wrong. A parent told only "failed three times" concludes
                  // nobody noticed — when in fact the loop ran twice.
                  exhausted
                      ? 'جرّبت المدرسة شرحاً بديلاً ${skill.remedialCount} مرة ولم تُتقَن بعد'
                      : skill.remedialCount > 0
                      ? 'أُسند شرح بديل، والتقييم لم يُجتَز بعد'
                      : 'إتقان ${skill.currentMastery.round()}٪ — أقل من المطلوب',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Before and after for one skill, as a pair of bars.
class TrendBar extends StatelessWidget {
  const TrendBar({required this.row, super.key});

  final MasteryTrend row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gained = row.gain > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(row.skillName, style: theme.textTheme.bodyMedium),
              ),
              Text(
                ar.signed(row.gain),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: gained
                      ? const Color(0xFF10B981)
                      : theme.disabledColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Stack(
            children: [
              // The baseline sits behind the current value rather than beside
              // it, so the growth is the visible part.
              _Bar(value: row.current, colour: const Color(0xFF10B981)),
              _Bar(
                value: row.baseline,
                colour: theme.colorScheme.onSurface.withValues(alpha: 0.22),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.colour});

  final double value;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: (value / 100).clamp(0.0, 1.0),
      child: Container(
        height: 8,
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
