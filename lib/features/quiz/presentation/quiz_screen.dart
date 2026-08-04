import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/network/api_result.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/quiz_models.dart';
import 'quiz_result_screen.dart';

/// شاشة الاختبار — بوابة الإتقان.
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({required this.quiz, super.key});

  final String quiz;

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  final Map<String, QuizAnswer> _answers = {};
  final _textControllers = <String, TextEditingController>{};

  int _index = 0;
  bool _submitting = false;
  DateTime? _startedAt;
  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    // Captured in didChangeDependencies — looking the messenger up here would
    // touch a deactivated element.
    _messenger?.clearSnackBars();
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Wipes the previous attempt. Anything left behind is a different attempt's
  /// data: the old answers would come back pre-selected, the question index
  /// would drop the student on the last question, and the elapsed timer would
  /// bill attempt 2 for the time spent on attempt 1.
  void _resetForNewAttempt() {
    for (final c in _textControllers.values) {
      c.clear();
    }

    setState(() {
      _answers.clear();
      _index = 0;
      _startedAt = DateTime.now();
    });

    // Attempt counters live on the server — refetch so the header is honest.
    ref.invalidate(quizPaperProvider(widget.quiz));
  }

  QuizAnswer _answerFor(QuizQuestion q) =>
      _answers[q.name] ?? QuizAnswer(question: q.name);

  void _select(QuizQuestion q, int idx) {
    final current = _answerFor(q);

    setState(() {
      if (q.multiple) {
        final next = [...current.selected];
        next.contains(idx) ? next.remove(idx) : next.add(idx);
        _answers[q.name] = current.copyWith(selected: next);
      } else {
        _answers[q.name] = current.copyWith(selected: [idx]);
      }
    });
  }

  Future<void> _submit(QuizPaper paper) async {
    final unanswered = paper.questions
        .where((q) => !_answerFor(q).isAnswered)
        .length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تسليم الاختبار'),
        content: Text(
          unanswered == 0
              ? 'هل تريد تسليم الاختبار؟'
              : 'لديك $unanswered سؤال بلا إجابة. هل تريد التسليم؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('سلّم'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);

    try {
      final elapsed = _startedAt == null
          ? null
          : DateTime.now().difference(_startedAt!).inSeconds.toDouble();

      final result = await ref
          .read(quizRepositoryProvider)
          .submit(
            quiz: widget.quiz,
            answers: paper.questions.map(_answerFor).toList(),
            timeTaken: elapsed,
          );

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => QuizResultScreen(result: result, paper: paper),
        ),
      );

      // Unconditional: any return to this screen is a new attempt, whether the
      // student tapped "إعادة المحاولة" or the system back button.
      if (mounted) _resetForNewAttempt();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paper = ref.watch(quizPaperProvider(widget.quiz));

    return Scaffold(
      appBar: AppBar(title: const Text('الاختبار')),
      body: AsyncView<QuizPaper>(
        value: paper,
        onRetry: () => ref.invalidate(quizPaperProvider(widget.quiz)),
        builder: (data) {
          _startedAt ??= DateTime.now();

          if (data.questions.isEmpty) {
            return const EmptyState(
              icon: Icons.quiz_outlined,
              message: 'لا توجد أسئلة في هذا الاختبار بعد.',
            );
          }

          final question = data.questions[_index];

          return Column(
            children: [
              _Header(paper: data, index: _index),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _QuestionCard(
                    question: question,
                    answer: _answerFor(question),
                    controller: question.isFreeText
                        ? _textControllers.putIfAbsent(
                            question.name,
                            TextEditingController.new,
                          )
                        : null,
                    onSelect: (idx) => _select(question, idx),
                    onText: (value) => setState(() {
                      _answers[question.name] = _answerFor(
                        question,
                      ).copyWith(text: value);
                    }),
                  ),
                ),
              ),
              _Navigation(
                index: _index,
                total: data.questions.length,
                submitting: _submitting,
                onPrevious: _index == 0 ? null : () => setState(() => _index--),
                onNext: _index == data.questions.length - 1
                    ? null
                    : () => setState(() => _index++),
                onSubmit: _submitting ? null : () => _submit(data),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.paper, required this.index});

  final QuizPaper paper;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(paper.title, style: theme.textTheme.titleSmall),
                ),
                Text(
                  'النجاح ${paper.passingPercentage}%',
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (index + 1) / paper.questions.length,
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'السؤال ${index + 1} من ${paper.questions.length}',
                  style: theme.textTheme.bodySmall,
                ),
                if (paper.attemptsLeft != null)
                  Text(
                    'المحاولات المتبقية: ${paper.attemptsLeft}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.answer,
    required this.onSelect,
    required this.onText,
    this.controller,
  });

  final QuizQuestion question;
  final QuizAnswer answer;
  final void Function(int) onSelect;
  final void Function(String) onText;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(question.question, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          question.multiple ? 'اختر كل الإجابات الصحيحة' : 'اختر إجابة واحدة',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        if (question.isFreeText)
          TextField(
            controller: controller,
            onChanged: onText,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'اكتب إجابتك هنا',
              border: OutlineInputBorder(),
            ),
          )
        else
          ...question.options.map((option) {
            final selected = answer.selected.contains(option.idx);

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: selected ? theme.colorScheme.primaryContainer : null,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelect(option.idx),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        question.multiple
                            ? (selected
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank)
                            : (selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(option.text)),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _Navigation extends StatelessWidget {
  const _Navigation({
    required this.index,
    required this.total,
    required this.submitting,
    this.onPrevious,
    this.onNext,
    this.onSubmit,
  });

  final int index;
  final int total;
  final bool submitting;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            OutlinedButton(
              onPressed: onPrevious,
              child: const Text('السابق'),
            ),
            const Spacer(),
            if (index == total - 1)
              FilledButton.icon(
                onPressed: onSubmit,
                icon: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('سلّم الاختبار'),
              )
            else
              FilledButton(onPressed: onNext, child: const Text('التالي')),
          ],
        ),
      ),
    );
  }
}
