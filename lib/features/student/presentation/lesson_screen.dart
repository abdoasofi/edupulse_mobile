import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/async_view.dart';
import '../../video/presentation/mastery_player.dart';
import '../domain/student_models.dart';

/// شاشة الدرس — الفيديو ثم بوابة الاختبار.
class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({required this.lesson, super.key});

  final String lesson;

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  bool _unlockedNow = false;
  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    // The messenger belongs to MaterialApp, not to this route, so a snackbar
    // left showing follows the student onto the quiz, the library and the
    // dashboard — still announcing "the quiz is open" for a lesson they left.
    _messenger?.clearSnackBars();
    super.dispose();
  }

  void _onVideoCompleted(String? gateQuiz) {
    if (!mounted) return;

    setState(() => _unlockedNow = true);
    ref.invalidate(lessonProvider(widget.lesson));

    // Replace rather than queue: a rebuilt player can report completion more
    // than once, and queued snackbars play back to back so the bar never
    // clears — which is what made it look permanent.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: const Text('أكملت المشاهدة — فُتح الاختبار'),
          action: gateQuiz == null
              ? null
              : SnackBarAction(
                  label: 'ابدأ',
                  onPressed: () => context.go('/student/home/quiz/$gateQuiz'),
                ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final lesson = ref.watch(lessonProvider(widget.lesson));

    return Scaffold(
      appBar: AppBar(title: const Text('الدرس')),
      body: AsyncView<LessonDetail>(
        value: lesson,
        onRetry: () => ref.invalidate(lessonProvider(widget.lesson)),
        builder: (data) => ListView(
          padding: EdgeInsets.zero,
          children: [
            MasteryPlayer(
              lesson: data.lesson,
              video: data.video,
              repository: ref.read(videoRepositoryProvider),
              resolveUrl: ref.read(apiClientProvider).resolveUrl,
              onCompleted: _onVideoCompleted,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (data.skill != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.psychology_outlined, size: 16),
                        const SizedBox(width: 6),
                        Text(data.skill!),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  _WatchGate(
                    video: data.video,
                    unlockedNow: _unlockedNow,
                    gateQuiz: data.gateQuiz,
                  ),
                  if ((data.body ?? '').isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(data.body!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Makes the pedagogical rule visible: the quiz opens only after the video.
class _WatchGate extends StatelessWidget {
  const _WatchGate({
    required this.video,
    required this.unlockedNow,
    required this.gateQuiz,
  });

  final VideoDescriptor video;
  final bool unlockedNow;
  final String? gateQuiz;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (gateQuiz == null) {
      return const SizedBox.shrink();
    }

    final open = unlockedNow || video.completed;
    final watched = video.watchedPercentage.round();

    return Card(
      color: open
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(open ? Icons.lock_open : Icons.lock_outline, size: 20),
                const SizedBox(width: 8),
                Text(
                  open ? 'الاختبار مفتوح' : 'الاختبار مقفل',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!open) ...[
              LinearProgressIndicator(
                value: (watched / video.minWatchPercentage).clamp(0.0, 1.0),
                minHeight: 6,
              ),
              const SizedBox(height: 8),
              Text(
                'شاهدت $watched% — يلزم ${video.minWatchPercentage}% لفتح الاختبار',
                style: theme.textTheme.bodySmall,
              ),
            ] else
              FilledButton.icon(
                icon: const Icon(Icons.quiz_outlined),
                label: const Text('ابدأ الاختبار'),
                onPressed: () => context.go('/student/home/quiz/$gateQuiz'),
              ),
          ],
        ),
      ),
    );
  }
}
