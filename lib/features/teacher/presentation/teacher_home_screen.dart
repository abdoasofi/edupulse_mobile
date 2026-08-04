import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/async_view.dart';
import '../../auth/domain/session.dart';
import '../domain/teacher_models.dart';
import 'teacher_widgets.dart';

/// بوابة المعلم — الصفحة الرئيسية.
///
/// Answers, in order, the three questions a teacher actually opens the app
/// with: how is my class doing, who needs me *today*, and did what I taught
/// move anyone. Everything else is a tap away.
class TeacherHomeScreen extends ConsumerWidget {
  const TeacherHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(classOverviewProvider(null));
    final user = ref.watch(authControllerProvider);
    final name = user is Authenticated ? user.user.fullName : '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('بوابة المعلم'),
        actions: [
          IconButton(
            tooltip: 'خروج',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(classOverviewProvider(null))
            ..invalidate(strugglingProvider(null))
            ..invalidate(masteryImpactProvider(null));
        },
        child: AsyncView<ClassOverview>(
          value: overview,
          onRetry: () => ref.invalidate(classOverviewProvider(null)),
          builder: (data) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _ClassHeader(name: name, stats: data.stats),
              const SizedBox(height: 24),
              const _InterventionQueue(),
              const SizedBox(height: 24),
              _RosterPreview(students: data.students),
              const SizedBox(height: 24),
              const _ImpactSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassHeader extends StatelessWidget {
  const _ClassHeader({required this.name, required this.stats});

  final String name;
  final ClassStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'صفوفي' : 'أهلاً، $name',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${stats.count} طالباً',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                MasteryBadge(percentage: stats.avgMastery, size: 56),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'متوسط الإتقان',
                    value: '${stats.avgMastery.round()}%',
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'المكسب',
                    value: '+${stats.avgGain.round()}',
                    colour: const Color(0xFF10B981),
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'يحتاجون دعماً',
                    value: '${stats.struggling}',
                    colour: stats.struggling > 0
                        ? theme.colorScheme.error
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The heart of the portal: who to help, ordered by whether the automated
/// loop has already been exhausted on them.
class _InterventionQueue extends ConsumerWidget {
  const _InterventionQueue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final struggling = ref.watch(strugglingProvider(null));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'قائمة التدخّل',
                style: theme.textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: () => context.go('/teacher/home/struggling'),
              child: const Text('الكل'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        struggling.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const EmptyState(
            icon: Icons.cloud_off_outlined,
            message: 'تعذّر تحميل قائمة التدخّل.',
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return const EmptyState(
                icon: Icons.verified_outlined,
                message: 'لا يوجد طالب متعثّر الآن.',
              );
            }

            // Teacher-first ordering: the cases the engine could not fix come
            // before the ones it has not tried yet, regardless of score.
            final sorted = [...rows]
              ..sort((a, b) {
                final byTriage = b.triage.index.compareTo(a.triage.index);
                if (byTriage != 0) return byTriage;
                return b.consecutiveFailures.compareTo(a.consecutiveFailures);
              });

            // One tile per student, not per skill. A student flagged in four
            // skills would otherwise fill the whole preview and hide everyone
            // else — the teacher would read "one struggling student" off a
            // screen that is actually reporting eight.
            final worstPerStudent = <String, StrugglingEntry>{};
            final flaggedSkills = <String, int>{};

            for (final entry in sorted) {
              worstPerStudent.putIfAbsent(entry.student, () => entry);
              flaggedSkills.update(
                entry.student,
                (n) => n + 1,
                ifAbsent: () => 1,
              );
            }

            final students = worstPerStudent.values.toList();
            final urgent = students
                .where((r) => r.triage == Triage.intervene)
                .length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (urgent > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '$urgent طالباً استنفد المعالجة الآلية وينتظرك',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ...students.take(4).map(
                  (e) => StrugglingTile(
                    entry: e,
                    alsoFlagged: (flaggedSkills[e.student] ?? 1) - 1,
                  ),
                ),
                if (students.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'و${students.length - 4} طلاب آخرين',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RosterPreview extends StatelessWidget {
  const _RosterPreview({required this.students});

  final List<StudentMastery> students;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (students.isEmpty) {
      return const EmptyState(
        icon: Icons.groups_outlined,
        message: 'لا يوجد طلاب مسجّلون في دوراتك بعد.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('الطلاب', style: theme.textTheme.titleMedium),
            ),
            TextButton(
              onPressed: () => context.go('/teacher/home/class'),
              child: const Text('الكل'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // The server already sorts ascending by mastery, so the students who
        // need attention are the ones that fit above the fold.
        ...students.take(5).map((s) => StudentRow(student: s)),
      ],
    );
  }
}

class _ImpactSection extends ConsumerWidget {
  const _ImpactSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final impact = ref.watch(masteryImpactProvider(null));

    return impact.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        if (data.rows.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('أثر التدريس', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        StatTile(
                          label: 'قبل',
                          value: '${data.pre.round()}%',
                        ),
                        const Icon(Icons.arrow_back, size: 18),
                        StatTile(
                          label: 'بعد',
                          value: '${data.post.round()}%',
                          colour: const Color(0xFF10B981),
                        ),
                        StatTile(
                          label: 'المكسب',
                          value: '+${data.gain.round()}',
                          colour: const Color(0xFF10B981),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...data.rows.map((row) => ImpactBar(row: row)),
          ],
        );
      },
    );
  }
}
