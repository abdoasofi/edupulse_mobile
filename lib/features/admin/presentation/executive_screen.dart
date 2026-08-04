import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/async_view.dart';
import '../../teacher/presentation/teacher_widgets.dart';
import '../domain/admin_models.dart';

/// بوابة الإدارة — مؤشرات الأداء وأثر المنصة.
///
/// Shared by the admin and supervisor portals: the endpoint is open to every
/// staff role and the questions are the same. Only the licence card differs,
/// because only an admin is sent the plan and seat detail.
class ExecutiveScreen extends ConsumerStatefulWidget {
  const ExecutiveScreen({this.title = 'بوابة الإدارة', super.key});

  final String title;

  @override
  ConsumerState<ExecutiveScreen> createState() => _ExecutiveScreenState();
}

const _windows = <int, String>{7: 'أسبوع', 30: 'شهر', 90: 'فصل'};

class _ExecutiveScreenState extends ConsumerState<ExecutiveScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final kpis = ref.watch(executiveKpisProvider(_days));
    final tenant = ref.watch(tenantProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'خروج',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(executiveKpisProvider(_days)),
        child: AsyncView<ExecutiveKpis>(
          value: kpis,
          onRetry: () => ref.invalidate(executiveKpisProvider(_days)),
          builder: (data) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (tenant?.licence != null)
                _LicenceCard(licence: tenant!.licence!),
              _WindowPicker(
                days: _days,
                onChanged: (days) => setState(() => _days = days),
              ),
              const SizedBox(height: 16),
              if (!data.hasData)
                const EmptyState(
                  icon: Icons.insights_outlined,
                  message: 'لا توجد قياسات في هذه الفترة بعد.',
                )
              else ...[
                _ImpactHeadline(mastery: data.mastery),
                const SizedBox(height: 24),
                _MasteryStory(mastery: data.mastery, quizzes: data.quizzes),
                const SizedBox(height: 24),
                _RemedialCard(remedial: data.remedial),
                const SizedBox(height: 24),
                _EngagementCard(students: data.students, days: data.periodDays),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowPicker extends StatelessWidget {
  const _WindowPicker({required this.days, required this.onChanged});

  final int days;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SegmentedButton<int>(
        segments: _windows.entries
            .map((e) => ButtonSegment(value: e.key, label: Text(e.value)))
            .toList(),
        selected: {days},
        showSelectedIcon: false,
        onSelectionChanged: (set) => onChanged(set.first),
      ),
    );
  }
}

class _LicenceCard extends StatelessWidget {
  const _LicenceCard({required this.licence});

  final Licence licence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seats = licence.seats;

    // A healthy licence with plenty of seats is noise on a dashboard the head
    // opens to read outcomes. It appears only when it wants something.
    if (!licence.needsAttention && (seats == null || seats.fraction < 0.85)) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: licence.state.colour.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  licence.blocking
                      ? Icons.error_outline
                      : Icons.info_outline,
                  size: 20,
                  color: licence.state.colour,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الاشتراك — ${licence.state.label}'
                    '${licence.plan == null ? '' : ' · ${licence.plan}'}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (licence.warning != null) ...[
              const SizedBox(height: 8),
              Text(licence.warning!, style: theme.textTheme.bodyMedium),
            ],
            if (seats != null && !seats.unlimited) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: seats.fraction,
                  minHeight: 6,
                  color: licence.state.colour,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${seats.used} من ${seats.total} مقعداً '
                '· متبقٍّ ${seats.available}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImpactHeadline extends StatelessWidget {
  const _ImpactHeadline({required this.mastery});

  final MasteryStats mastery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
        child: Column(
          children: [
            Text('أثر المنصة على الإتقان', style: theme.textTheme.titleSmall),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                StatTile(label: 'قبل', value: '${mastery.pre.round()}%'),
                const Icon(Icons.arrow_back, size: 20),
                StatTile(
                  label: 'بعد',
                  value: '${mastery.post.round()}%',
                  colour: const Color(0xFF10B981),
                ),
                StatTile(
                  label: 'المكسب',
                  value: '+${mastery.gain.round()}',
                  colour: const Color(0xFF10B981),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GainBar(baseline: mastery.pre, current: mastery.post),
            const SizedBox(height: 10),
            Text(
              'على ${mastery.measured} حالة مهارة عمل عليها الطلاب خلال الفترة',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            // The window picks which skills are counted; "before" stays each
            // student's first-ever score on that skill. Saying so prevents the
            // reasonable-but-wrong reading that "before" means the start of
            // the selected period.
            Text(
              '«قبل» هي أول درجة سجّلها الطالب في المهارة',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The three-number narrative.
///
/// Shown alone, the attempt pass rate reads as catastrophe: on the demo cohort
/// it is 29%, because every deliberate retry on the way to mastery counts as a
/// failed attempt. A head of school seeing that single figure concludes the
/// platform does not work — when it is in fact evidence of the loop running.
/// The three rows separate what the number actually measures.
class _MasteryStory extends StatelessWidget {
  const _MasteryStory({required this.mastery, required this.quizzes});

  final MasteryStats mastery;
  final QuizStats quizzes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('كيف وصل الطلاب للإتقان', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'ثلاثة أرقام مختلفة تقيس ثلاثة أشياء مختلفة',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        _StoryRow(
          label: 'أتقنوا من أول محاولة',
          detail: '${mastery.firstTime} من ${mastery.measured} حالة',
          percentage: mastery.firstTimeRate,
          colour: const Color(0xFF3B82F6),
        ),
        _StoryRow(
          label: 'تعافوا بعد المسار العلاجي',
          detail: 'من أخفقوا أولاً ثم أتقنوا — ${mastery.recovered} حالة',
          percentage: mastery.recoveryRate,
          colour: const Color(0xFF10B981),
          emphasis: true,
        ),
        _StoryRow(
          label: 'أتقنوا في النهاية',
          detail: '${mastery.mastered} من ${mastery.measured} حالة',
          percentage: mastery.masteryRate,
          colour: const Color(0xFF6366F1),
        ),
        const SizedBox(height: 14),
        _AttemptFootnote(quizzes: quizzes),
      ],
    );
  }
}

class _StoryRow extends StatelessWidget {
  const _StoryRow({
    required this.label,
    required this.detail,
    required this.percentage,
    required this.colour,
    this.emphasis = false,
  });

  final String label;
  final String detail;
  final double percentage;
  final Color colour;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '${percentage.round()}%',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colour,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (percentage / 100).clamp(0.0, 1.0),
              minHeight: emphasis ? 8 : 5,
              color: colour,
              backgroundColor: colour.withValues(alpha: 0.14),
            ),
          ),
          const SizedBox(height: 4),
          Text(detail, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _AttemptFootnote extends StatelessWidget {
  const _AttemptFootnote({required this.quizzes});

  final QuizStats quizzes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'نسبة نجاح المحاولات ${quizzes.attemptPassRate.round()}%',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'هذا الرقم يَعُدّ كل محاولة على حدة، وكل إعادة محاولة مقصودة في '
            'طريق الإتقان تُحتسب إخفاقاً. انخفاضه دليل على أن الحلقة تعمل، '
            'لا على ضعف النتائج — والقياس الحقيقي هو الأرقام أعلاه.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            '${quizzes.attempts} محاولة · متوسط الدرجة '
            '${quizzes.avgScore.round()}%',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RemedialCard extends StatelessWidget {
  const _RemedialCard({required this.remedial});

  final RemedialStats remedial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('فاعلية التدخّل العلاجي', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    StatTile(
                      label: 'مسار مُسند',
                      value: '${remedial.triggered}',
                    ),
                    StatTile(
                      label: 'نجح',
                      value: '${remedial.resolved}',
                      colour: const Color(0xFF10B981),
                    ),
                    StatTile(
                      label: 'صُعِّد',
                      value: '${remedial.escalated}',
                      colour: remedial.escalated > 0
                          ? theme.colorScheme.error
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (remedial.effectiveness / 100).clamp(0.0, 1.0),
                    minHeight: 7,
                    color: const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'فاعلية ${remedial.effectiveness.round()}% · '
                  'متوسط المكسب +${remedial.avgGain.round()} نقطة',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EngagementCard extends StatelessWidget {
  const _EngagementCard({required this.students, required this.days});

  final StudentEngagement students;
  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('المشاركة', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                MasteryBadge(percentage: students.engagementRate, size: 54),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${students.active} من ${students.total} طالباً نشطون',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'شاهدوا درساً واحداً على الأقل خلال $days يوماً',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
