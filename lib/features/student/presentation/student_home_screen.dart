import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/async_view.dart';
import '../../auth/domain/session.dart';
import '../domain/student_models.dart';

/// بوابة الطالب — الصفحة الرئيسية.
class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final user = ref.watch(authControllerProvider);
    final name = user is Authenticated ? user.user.fullName : '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('بوابة الطالب'),
        actions: [
          IconButton(
            tooltip: 'المكتبة',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => context.go('/student/home/library'),
          ),
          IconButton(
            tooltip: 'خروج',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(dashboardProvider),
        child: AsyncView<StudentDashboard>(
          value: dashboard,
          onRetry: () => ref.invalidate(dashboardProvider),
          builder: (data) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _Greeting(name: name, streak: data.streak, mastery: data.avgMastery),
              if (data.remedialPending.isNotEmpty) ...[
                const SizedBox(height: 20),
                _RemedialBanner(items: data.remedialPending),
              ],
              const SizedBox(height: 24),
              Text('دوراتي', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (data.courses.isEmpty)
                const EmptyState(
                  icon: Icons.school_outlined,
                  message: 'لم تُسجَّل في أي دورة بعد.',
                )
              else
                ...data.courses.map((c) => _CourseCard(course: c)),
              if (data.flaggedSkills.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'مهارات تحتاج مراجعة',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...data.flaggedSkills.map((s) => _FlaggedTile(skill: s)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.name,
    required this.streak,
    required this.mastery,
  });

  final String name;
  final int streak;
  final double mastery;

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
                  Text('مرحباً، $name', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.local_fire_department, size: 18),
                      const SizedBox(width: 4),
                      Text('$streak يوم متتالٍ'),
                    ],
                  ),
                ],
              ),
            ),
            MasteryBadge(percentage: mastery, size: 56),
          ],
        ),
      ),
    );
  }
}

/// The remedial path is the product's promise — it gets the loudest slot.
class _RemedialBanner extends StatelessWidget {
  const _RemedialBanner({required this.items});

  final List<RemedialSummary> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/student/home/remedial'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.auto_fix_high, color: theme.colorScheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'لديك ${items.length} مسار علاجي',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'شرح بمعلّم آخر + تمارين داعمة',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course});

  final EnrolledCourse course;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/student/home/path/${course.course}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (course.progress / 100).clamp(0.0, 1.0),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'التقدّم ${course.progress.round()}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              MasteryBadge(percentage: course.mastery),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlaggedTile extends StatelessWidget {
  const _FlaggedTile({required this.skill});

  final FlaggedSkill skill;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.flag_outlined),
        title: Text(skill.skill),
        subtitle: Text('${skill.consecutiveFailures} إخفاق متتالٍ'),
        trailing: MasteryBadge(percentage: skill.currentMastery, size: 38),
      ),
    );
  }
}
