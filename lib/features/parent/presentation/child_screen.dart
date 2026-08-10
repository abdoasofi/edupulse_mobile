import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/arabic.dart' as ar;
import '../../../shared/widgets/async_view.dart';
import '../domain/parent_models.dart';
import 'parent_widgets.dart';

/// One child, in the order a guardian asks about them.
///
/// What needs attention comes before what was done, and what was done comes
/// before whether it is working. Reversing that gives a parent two screens of
/// activity to scroll past before reaching the thing they came for.
class ChildScreen extends ConsumerStatefulWidget {
  const ChildScreen({required this.student, super.key});

  final String student;

  @override
  ConsumerState<ChildScreen> createState() => _ChildScreenState();
}

class _ChildScreenState extends ConsumerState<ChildScreen> {
  /// "This week" is the question a parent opens with; the month is the
  /// deliberate second look, not a default to be scrolled back through.
  int _days = 7;

  ChildWindow get _window => (student: widget.student, days: _days);

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(childSummaryProvider(_window));

    return Scaffold(
      appBar: AppBar(
        title: Text(summary.valueOrNull?.studentName ?? 'متابعة الابن'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(childSummaryProvider(_window))
            ..invalidate(childFlaggedProvider(widget.student))
            ..invalidate(childTrendProvider(widget.student));
        },
        child: AsyncView<ChildSummary>(
          value: summary,
          onRetry: () => ref.invalidate(childSummaryProvider(_window)),
          builder: (data) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _NeedsAttention(student: widget.student),
              const SizedBox(height: 22),
              _PeriodPicker(
                days: _days,
                onChanged: (value) => setState(() => _days = value),
              ),
              const SizedBox(height: 10),
              _ActivityCard(summary: data),
              const SizedBox(height: 22),
              _RecentLessons(lessons: data.recentLessons),
              const SizedBox(height: 22),
              _IsItWorking(student: widget.student),
            ],
          ),
        ),
      ),
    );
  }
}

/// The action list. First on the screen, and absent entirely when empty —
/// an empty "needs attention" panel trains a parent to skip the section that
/// matters on the day it is not empty.
class _NeedsAttention extends ConsumerWidget {
  const _NeedsAttention({required this.student});

  final String student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final flagged = ref.watch(childFlaggedProvider(student));

    return flagged.when(
      loading: () => const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        if (!data.needsAttention) {
          return Card(
            color: const Color(0xFF10B981).withValues(alpha: 0.10),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Color(0xFF10B981),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('لا توجد مهارات متعثّرة حالياً.'),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('يحتاج متابعة', style: theme.textTheme.titleMedium),
            if (data.openRemedials > 0) ...[
              const SizedBox(height: 4),
              Text(
                'المدرسة أسندت ${data.openRemedials} مساراً علاجياً قيد التنفيذ',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            ...data.bySubject.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...entry.value.map((s) => FlaggedSkillTile(skill: s)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  static const _options = {7: 'أسبوع', 30: 'شهر', 90: 'فصل'};

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: _options.entries
          .map((e) => ButtonSegment(value: e.key, label: Text(e.value)))
          .toList(),
      selected: {days},
      showSelectedIcon: false,
      onSelectionChanged: (values) => onChanged(values.first),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.summary});

  final ChildSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totals = summary.totals;

    if (totals.isIdle) {
      // Four zeroes read as a broken screen. Say the thing they mean.
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.hourglass_empty, color: theme.disabledColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'لا نشاط مسجَّل خلال هذه الفترة.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ParentStat(
              value: '${totals.lessonsCompleted}',
              label: 'درساً أكمله',
            ),
            ParentStat(
              value: totals.watchMinutes.round().toString(),
              label: 'دقيقة مشاهدة',
            ),
            ParentStat(
              value: '${totals.quizzesPassed}/${totals.quizAttempts}',
              label: 'اختبار اجتازه',
              colour: totals.quizAttempts > 0 &&
                      totals.quizzesPassed == totals.quizAttempts
                  ? const Color(0xFF10B981)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentLessons extends StatelessWidget {
  const _RecentLessons({required this.lessons});

  final List<RecentLesson> lessons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (lessons.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('آخر ما شاهده', style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        ...lessons.take(6).map(
          (lesson) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(
                  lesson.isCompleted
                      ? Icons.check_circle
                      : Icons.play_circle_outline,
                  size: 20,
                  color: lesson.isCompleted
                      ? const Color(0xFF10B981)
                      : theme.disabledColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lesson.lessonTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (lesson.courseTitle.isNotEmpty)
                        Text(
                          lesson.courseTitle,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                Text(
                  '${lesson.watchedPercentage.round()}٪',
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The question a parent asks last and cares about most: is any of this
/// making a difference?
class _IsItWorking extends ConsumerWidget {
  const _IsItWorking({required this.student});

  final String student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trend = ref.watch(childTrendProvider(student));

    return trend.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (rows) {
        // A skill at 0 → 0 has not started; showing it would pad the section
        // with rows that say nothing.
        final moved = rows.where((r) => r.hasMoved).toList();
        if (moved.isEmpty) return const SizedBox.shrink();

        final gained = moved.where((r) => r.gain > 0).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل يتحسّن؟', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'تحسّن في $gained من ${ar.counted(moved.length, ar.skills)} منذ البداية',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ...moved.take(8).map((row) => TrendBar(row: row)),
          ],
        );
      },
    );
  }
}
