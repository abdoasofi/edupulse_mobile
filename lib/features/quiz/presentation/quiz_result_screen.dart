import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/quiz_models.dart';

/// نتيجة الاختبار — والأهم: ما الخطوة التالية.
///
/// The next step is not decided here. `result.nextAction` comes from the
/// server, which already knows whether a remedial path was generated.
class QuizResultScreen extends StatelessWidget {
  const QuizResultScreen({required this.result, required this.paper, super.key});

  final QuizResult result;
  final QuizPaper paper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final passed = result.passed;

    final colour = passed
        ? const Color(0xFF10B981)
        : theme.colorScheme.error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('النتيجة'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              child: Column(
                children: [
                  Icon(
                    passed ? Icons.emoji_events : Icons.refresh,
                    size: 56,
                    color: colour,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${result.percentage.round()}%',
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: colour,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    passed ? 'أحسنت! لقد اجتزت الاختبار' : 'لم تجتز هذه المرة',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'المطلوب ${result.passingPercentage}% · '
                    'المحاولة ${result.attemptNo}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _NextStep(result: result),
          if (result.review.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('مراجعة الإجابات', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...result.review.map((item) => _ReviewTile(item: item)),
          ],
        ],
      ),
    );
  }
}

class _NextStep extends StatelessWidget {
  const _NextStep({required this.result});

  final QuizResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = result.nextAction;

    if (action.isRemedial) {
      return Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_fix_high),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'أعددنا لك مساراً علاجياً',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'شرح للمهارة نفسها بمعلّم آخر، مع تمارين داعمة ومواد من '
                'المكتبة. بعد إكماله ستُعيد التقييم.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/student/home/remedial'),
                child: const Text('ابدأ المسار العلاجي'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              action.isRetry ? 'يمكنك المحاولة مجدداً' : 'تابع مسارك',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (action.isRetry)
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إعادة المحاولة'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () => context.go('/student/home'),
                  child: const Text('العودة للرئيسية'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.item});

  final ReviewItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  item.isCorrect ? Icons.check_circle : Icons.cancel,
                  size: 18,
                  color: item.isCorrect
                      ? const Color(0xFF10B981)
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.question,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            // Only wrong answers get the full treatment. A student who was
            // right does not need a lecture, and a wall of text on every item
            // makes the review unreadable exactly where it matters.
            if (!item.isCorrect) ...[
              if ((item.yourAnswer ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                _Line(
                  label: 'إجابتك',
                  value: item.yourAnswer!,
                  color: theme.colorScheme.error,
                ),
              ],
              if ((item.yourExplanation ?? '').isNotEmpty)
                _Note(text: item.yourExplanation!),
              if (item.correctOptions.isNotEmpty) ...[
                const SizedBox(height: 8),
                _Line(
                  label: 'الإجابة الصحيحة',
                  value: item.correctText,
                  color: const Color(0xFF10B981),
                ),
              ],
              if ((item.correctExplanation ?? '').isNotEmpty)
                _Note(text: item.correctExplanation!),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: theme.textTheme.bodySmall),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The teaching line — why an option is right or wrong.
class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 26, top: 4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),
    );
  }
}
