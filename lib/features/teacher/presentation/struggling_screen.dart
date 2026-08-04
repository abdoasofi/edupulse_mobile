import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/teacher_models.dart';
import 'teacher_widgets.dart';

/// قائمة التدخّل — كل الحالات المتعثّرة، مرتّبة بحسب الأولوية.
///
/// Grouped by triage rather than by student or by score. The teacher's real
/// question is "where is my time worth the most", and that is answered by how
/// far the automated loop has already gone, not by who scored lowest.
class StrugglingScreen extends ConsumerWidget {
  const StrugglingScreen({this.course, super.key});

  final String? course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(strugglingProvider(course));

    return Scaffold(
      appBar: AppBar(title: const Text('قائمة التدخّل')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(strugglingProvider(course)),
        child: AsyncView<List<StrugglingEntry>>(
          value: rows,
          onRetry: () => ref.invalidate(strugglingProvider(course)),
          builder: (data) {
            if (data.isEmpty) {
              return const EmptyState(
                icon: Icons.verified_outlined,
                message: 'لا يوجد طالب متعثّر الآن.',
              );
            }

            final groups = <Triage, List<StrugglingEntry>>{};
            for (final entry in data) {
              groups.putIfAbsent(entry.triage, () => []).add(entry);
            }

            // Most urgent first.
            final order = [Triage.intervene, Triage.watch, Triage.automatic];

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                for (final triage in order)
                  if (groups[triage] case final entries?
                      when entries.isNotEmpty) ...[
                    _GroupHeader(triage: triage, count: entries.length),
                    ...(entries
                      ..sort(
                        (a, b) => b.consecutiveFailures.compareTo(
                          a.consecutiveFailures,
                        ),
                      ))
                        .map((e) => StrugglingTile(entry: e)),
                    const SizedBox(height: 16),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.triage, required this.count});

  final Triage triage;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: triage.colour,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              triage.label,
              style: theme.textTheme.titleSmall?.copyWith(color: triage.colour),
            ),
          ),
          Text('$count', style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}
