import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/async_view.dart';
import '../../auth/domain/session.dart';
import '../domain/parent_models.dart';
import 'parent_widgets.dart';

/// بوابة ولي الأمر — الصفحة الرئيسية.
///
/// A guardian opens this app with one question: is my child alright? So the
/// screen answers it before anything else — the children who need attention
/// come first, and a parent with nothing to worry about is told so in a
/// sentence instead of being handed a dashboard to interpret.
class ParentHomeScreen extends ConsumerWidget {
  const ParentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(childrenProvider);
    final user = ref.watch(authControllerProvider);
    final name = user is Authenticated ? user.user.fullName : '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('بوابة ولي الأمر'),
        actions: [
          IconButton(
            tooltip: 'خروج',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(childrenProvider),
        child: AsyncView<List<Child>>(
          value: children,
          onRetry: () => ref.invalidate(childrenProvider),
          builder: (rows) {
            if (rows.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  EmptyState(
                    icon: Icons.family_restroom,
                    message:
                        'لم تُربط أي حساب طالب بحسابك بعد.\n'
                        'تواصل مع إدارة المدرسة لربط أبنائك.',
                  ),
                ],
              );
            }

            // Children who need something come first. Within each state the
            // lower mastery leads — a parent scrolling stops at the top.
            final sorted = [...rows]
              ..sort((a, b) {
                final byState = a.state.index.compareTo(b.state.index);
                if (byState != 0) return byState;
                return a.avgMastery.compareTo(b.avgMastery);
              });

            final needing = sorted
                .where((c) => c.state != ChildState.fine)
                .length;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _Greeting(name: name, children: sorted, needing: needing),
                const SizedBox(height: 20),
                ...sorted.map(
                  (child) => ChildCard(
                    child: child,
                    onTap: () =>
                        context.push('/parent/home/child/${child.student}'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.name,
    required this.children,
    required this.needing,
  });

  final String name;
  final List<Child> children;
  final int needing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calm = needing == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name.isEmpty ? 'أبناؤك' : 'أهلاً، $name',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        // The headline is a sentence, not a statistic. "٢ من ٣ يحتاجون
        // متابعة" is a thing a parent can act on; "متوسط الإتقان ٦٤٪" is not.
        Text(
          calm
              ? children.length == 1
                    ? 'لا شيء يستدعي القلق اليوم.'
                    : 'لا شيء يستدعي القلق اليوم لدى أيٍّ من أبنائك.'
              : needing == children.length
              ? 'جميع أبنائك يحتاجون متابعة هذا الأسبوع.'
              : '$needing من ${children.length} يحتاجون متابعة هذا الأسبوع.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: calm
                ? const Color(0xFF10B981)
                : theme.colorScheme.onSurface,
            fontWeight: calm ? FontWeight.w600 : FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
