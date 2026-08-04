import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/teacher_models.dart';
import 'teacher_widgets.dart';

/// كشف الصف — كل الطلاب، مع إمكانية الترتيب.
class ClassScreen extends ConsumerStatefulWidget {
  const ClassScreen({this.course, super.key});

  final String? course;

  @override
  ConsumerState<ClassScreen> createState() => _ClassScreenState();
}

enum _Sort {
  mastery('الأدنى إتقاناً'),
  gain('الأقل تقدّماً'),
  name('الاسم');

  const _Sort(this.label);

  final String label;
}

class _ClassScreenState extends ConsumerState<ClassScreen> {
  _Sort _sort = _Sort.mastery;

  List<StudentMastery> _sorted(List<StudentMastery> students) {
    final list = [...students];

    switch (_sort) {
      // Ascending in both numeric cases: this screen exists to find the
      // students who need help, so the ones who need it most come first.
      case _Sort.mastery:
        list.sort((a, b) => a.avgMastery.compareTo(b.avgMastery));
      case _Sort.gain:
        list.sort((a, b) => a.gain.compareTo(b.gain));
      case _Sort.name:
        list.sort((a, b) => a.studentName.compareTo(b.studentName));
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(classOverviewProvider(widget.course));

    return Scaffold(
      appBar: AppBar(
        title: const Text('كشف الصف'),
        actions: [
          PopupMenuButton<_Sort>(
            tooltip: 'الترتيب',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (_) => _Sort.values
                .map((s) => PopupMenuItem(value: s, child: Text(s.label)))
                .toList(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(classOverviewProvider(widget.course)),
        child: AsyncView<ClassOverview>(
          value: overview,
          onRetry: () => ref.invalidate(classOverviewProvider(widget.course)),
          builder: (data) {
            if (data.students.isEmpty) {
              return const EmptyState(
                icon: Icons.groups_outlined,
                message: 'لا يوجد طلاب مسجّلون في هذه الدورة.',
              );
            }

            final students = _sorted(data.students);

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: students.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) return _Summary(stats: data.stats, sort: _sort);
                return StudentRow(student: students[i - 1]);
              },
            );
          },
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.stats, required this.sort});

  final ClassStats stats;
  final _Sort sort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${stats.count} طالباً · ${stats.struggling} يحتاجون دعماً',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(sort.label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
