import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/network/api_result.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/remedial_models.dart';

/// المسار العلاجي — ما يحدث بعد الرسوب.
///
/// This is the screen that makes the product's promise concrete: failing three
/// times does not end in a wall, it ends in a different teacher explaining the
/// same skill, plus practice, then a fresh assessment.
class RemedialScreen extends ConsumerStatefulWidget {
  const RemedialScreen({this.assignment, super.key});

  final String? assignment;

  @override
  ConsumerState<RemedialScreen> createState() => _RemedialScreenState();
}

class _RemedialScreenState extends ConsumerState<RemedialScreen> {
  int? _busyRow;

  Future<void> _complete(RemedialPath path, RemedialResource resource) async {
    setState(() => _busyRow = resource.idx);

    try {
      await ref
          .read(remedialRepositoryProvider)
          .completeResource(assignment: path.name, rowIdx: resource.idx);

      ref.invalidate(remedialPathProvider(widget.assignment));
      ref.invalidate(dashboardProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyRow = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = ref.watch(remedialPathProvider(widget.assignment));

    return Scaffold(
      appBar: AppBar(title: const Text('المسار العلاجي')),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(remedialPathProvider(widget.assignment)),
        child: AsyncView<RemedialPath?>(
          value: path,
          onRetry: () => ref.invalidate(remedialPathProvider(widget.assignment)),
          builder: (data) {
            if (data == null) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.verified_outlined,
                    message: 'لا يوجد مسار علاجي مفتوح.\nأنت على المسار الصحيح.',
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _Header(path: data),
                const SizedBox(height: 20),
                Text(
                  'خطوات المسار',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...data.resources.map(
                  (r) => _ResourceTile(
                    resource: r,
                    busy: _busyRow == r.idx,
                    onComplete: r.isCompleted ? null : () => _complete(data, r),
                  ),
                ),
                const SizedBox(height: 20),
                _ReassessmentCard(path: data),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.path});

  final RemedialPath path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_fix_high,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    path.skillName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                _StatusChip(status: path.status),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'تعثّرت في هذه المهارة، فأعددنا لك شرحاً بأسلوب مختلف. '
              'أكمل الخطوات ثم أعد التقييم.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: path.progress,
                minHeight: 7,
                backgroundColor: theme.colorScheme.onPrimaryContainer
                    .withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'أنجزت ${path.completedCount} من ${path.resources.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const Spacer(),
                if (path.dueOn != null)
                  Text(
                    path.isOverdue
                        ? 'متأخر — استحق ${path.dueOn}'
                        : 'يستحق ${path.dueOn}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: path.isOverdue
                          ? theme.colorScheme.error
                          : theme.colorScheme.onPrimaryContainer,
                      fontWeight: path.isOverdue ? FontWeight.bold : null,
                    ),
                  ),
              ],
            ),
            if (path.cycleNo > 1) ...[
              const SizedBox(height: 8),
              Text(
                'الدورة العلاجية رقم ${path.cycleNo}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final RemedialStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(status.label, style: theme.textTheme.labelSmall),
    );
  }
}

class _ResourceTile extends StatelessWidget {
  const _ResourceTile({
    required this.resource,
    required this.busy,
    this.onComplete,
  });

  final RemedialResource resource;
  final bool busy;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = resource.isCompleted;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  done ? Icons.check_circle : resource.type.icon,
                  color: done
                      ? const Color(0xFF10B981)
                      : theme.colorScheme.primary,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resource.type.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          decoration: done ? TextDecoration.lineThrough : null,
                          color: done ? theme.disabledColor : null,
                        ),
                      ),
                      // The differentiator: name the other teacher.
                      if (resource.instructorName != null) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              resource.instructorName!,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (resource.isOpenable)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('افتح'),
                    onPressed: () => context.push(resource.route!),
                  ),
                const Spacer(),
                if (done)
                  Text(
                    'مكتمل',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: const Color(0xFF10B981),
                    ),
                  )
                else
                  FilledButton.tonal(
                    onPressed: busy ? null : onComplete,
                    child: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('تم'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The closing gate: re-assessment unlocks only when every step is done.
class _ReassessmentCard extends StatelessWidget {
  const _ReassessmentCard({required this.path});

  final RemedialPath path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = path.canReassess;

    if (path.reassessmentQuiz == null) {
      return const SizedBox.shrink();
    }

    return Card(
      color: ready
          ? theme.colorScheme.secondaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ready ? Icons.lock_open : Icons.lock_outline, size: 20),
                const SizedBox(width: 8),
                Text('إعادة التقييم', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              ready
                  ? 'أنجزت كل الخطوات. أثبت إتقانك الآن.'
                  : 'أكمل خطوات المسار أولاً ليُفتح التقييم.',
              style: theme.textTheme.bodyMedium,
            ),
            if (path.preScore > 0) ...[
              const SizedBox(height: 8),
              Text(
                'درجتك قبل المسار: ${path.preScore.round()}%',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.assignment_turned_in_outlined),
                label: const Text('ابدأ إعادة التقييم'),
                onPressed: ready
                    ? () => context.push(
                        '/student/home/quiz/${path.reassessmentQuiz}',
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
