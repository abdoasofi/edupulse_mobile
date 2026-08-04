import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/student_models.dart';

/// مسار التعلّم — الدروس بترتيبها وحالة القفل.
///
/// Lock state comes from the server on every load. The UI mirrors it; it never
/// computes it, so a tampered client still cannot open a gated lesson.
class LearningPathScreen extends ConsumerWidget {
  const LearningPathScreen({required this.course, super.key});

  final String course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(learningPathProvider(course));

    return Scaffold(
      appBar: AppBar(title: const Text('مسار التعلّم')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(learningPathProvider(course)),
        child: AsyncView<LearningPath>(
          value: path,
          onRetry: () => ref.invalidate(learningPathProvider(course)),
          builder: (data) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _MasteryHeader(title: data.title, mastery: data.mastery),
              const SizedBox(height: 20),
              ...data.path.asMap().entries.map(
                (entry) => _LessonTile(
                  index: entry.key + 1,
                  node: entry.value,
                  isNext: entry.value.lesson == data.nextLesson,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MasteryHeader extends StatelessWidget {
  const _MasteryHeader({required this.title, required this.mastery});

  final String title;
  final CourseMastery mastery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'أتقنت ${mastery.mastered} من ${mastery.skills} مهارة',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (mastery.flagged > 0)
                    Text(
                      '${mastery.flagged} مهارة تحتاج دعماً',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            MasteryBadge(percentage: mastery.mastery, size: 56),
          ],
        ),
      ),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({
    required this.index,
    required this.node,
    required this.isNext,
  });

  final int index;
  final LessonNode node;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, colour) = switch (node.state) {
      LessonState.completed => (Icons.check_circle, const Color(0xFF10B981)),
      LessonState.unlocked => (Icons.play_circle_fill, theme.colorScheme.primary),
      LessonState.locked => (Icons.lock, theme.disabledColor),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isNext ? 3 : 0,
      shape: isNext
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: node.isLocked
            ? () => _explainLock(context)
            : () => context.go('/student/home/lesson/${node.lesson}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: colour, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$index. ',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.disabledColor,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            node.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: node.isLocked ? theme.disabledColor : null,
                            ),
                          ),
                        ),
                        if (isNext)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'التالي',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _ProgressRow(node: node),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _explainLock(BuildContext context) {
    // Tapping three locked lessons must not queue three identical bars that
    // then play back to back for twelve seconds.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('أكمل الدرس السابق واجتز اختباره لفتح هذا الدرس.'),
        ),
      );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.node});

  final LessonNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiz = node.quiz;

    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Chip(
          icon: node.video.completed
              ? Icons.videocam
              : Icons.videocam_outlined,
          label: 'مشاهدة ${node.video.watchedPercentage.round()}%',
          highlight: node.video.completed,
        ),
        if (quiz != null)
          _Chip(
            icon: quiz.passed ? Icons.task_alt : Icons.quiz_outlined,
            label: quiz.passed
                ? 'اجتاز ${quiz.bestPercentage.round()}%'
                : quiz.attemptsUsed == 0
                ? 'اختبار ${quiz.passingPercentage}%'
                : 'محاولات ${quiz.attemptsUsed}',
            highlight: quiz.passed,
          ),
        if (node.video.resumeAt > 5 && !node.video.completed)
          Text(
            'يُستأنف من ${_mmss(node.video.resumeAt)}',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }

  String _mmss(double seconds) {
    final total = seconds.round();
    return '${(total ~/ 60).toString().padLeft(2, '0')}:'
        '${(total % 60).toString().padLeft(2, '0')}';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = highlight
        ? const Color(0xFF10B981)
        : theme.textTheme.bodySmall?.color;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: colour),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: colour),
        ),
      ],
    );
  }
}
