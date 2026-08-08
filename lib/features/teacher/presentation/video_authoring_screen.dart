import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/teacher_models.dart';

/// فيديوهات الدروس — attach, replace and remove a lesson's clip.
///
/// The screen never learns a provider name. It asks the server how this school
/// wants videos attached and renders that one strategy: a file picker, a link
/// box, or nothing at all. A school on Drive and a school on YouTube run the
/// same binary and see different forms, and adding a sixth provider changes
/// neither.
class VideoAuthoringScreen extends ConsumerWidget {
  const VideoAuthoringScreen({this.course, super.key});

  final String? course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessons = ref.watch(authoringLessonsProvider(course));
    final target = ref.watch(uploadTargetProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('فيديوهات الدروس')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(authoringLessonsProvider(course));
          ref.invalidate(uploadTargetProvider);
        },
        child: AsyncView<List<AuthoringLesson>>(
          value: lessons,
          onRetry: () => ref.invalidate(authoringLessonsProvider(course)),
          builder: (data) {
            if (data.isEmpty) {
              return const EmptyState(
                icon: Icons.video_library_outlined,
                message: 'لا توجد دروس في المقررات التي تُدرّسها.',
              );
            }

            // Missing videos first. A teacher opens this screen to find the
            // gaps, and sorting by course order buries them under lessons that
            // are already done.
            final missing = data.where((l) => !l.hasVideo).toList();
            final done = data.where((l) => l.hasVideo).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _TargetCard(target: target),
                const SizedBox(height: 16),
                if (missing.isNotEmpty) ...[
                  _SectionTitle('بلا فيديو', count: missing.length),
                  for (final lesson in missing)
                    _LessonTile(lesson: lesson, target: target, course: course),
                  const SizedBox(height: 16),
                ],
                if (done.isNotEmpty) ...[
                  _SectionTitle('جاهزة', count: done.length),
                  for (final lesson in done)
                    _LessonTile(lesson: lesson, target: target, course: course),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label, {required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      '$label ($count)',
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

/// What the school's provider expects — shown once, at the top.
class _TargetCard extends StatelessWidget {
  const _TargetCard({required this.target});

  final AsyncValue<UploadTarget> target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return target.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) => Card(
        color: data.canUpload
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                data.canUpload ? Icons.cloud_upload_outlined : Icons.block,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.providerLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      data.canUpload
                          ? data.hint
                          : 'مزوّد الفيديو المُختار غير مُفعّل بعد. '
                                'غيّره في إعدادات المدرسة قبل الرفع.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LessonTile extends ConsumerWidget {
  const _LessonTile({
    required this.lesson,
    required this.target,
    required this.course,
  });

  final AuthoringLesson lesson;
  final AsyncValue<UploadTarget> target;
  final String? course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          lesson.hasVideo ? Icons.play_circle_outline : Icons.videocam_off_outlined,
          color: lesson.hasVideo
              ? theme.colorScheme.primary
              : theme.colorScheme.error,
        ),
        title: Text(lesson.title, style: theme.textTheme.bodyMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            lesson.hasVideo
                ? '${lesson.providerLabel ?? ''} · ${_mmss(lesson.duration)}'
                : 'لم يُرفع شرح بعد',
            style: theme.textTheme.bodySmall,
          ),
        ),
        trailing: lesson.isRemedial
            ? Chip(
                label: const Text('علاجي', style: TextStyle(fontSize: 10)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              )
            : null,
        onTap: () => _open(context, ref),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final data = target.valueOrNull;
    if (data == null) return;

    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        // Above the keyboard: the link field is the last thing on screen and
        // would otherwise be typed into blind.
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _AttachSheet(lesson: lesson, target: data),
      ),
    );

    if (changed == true) {
      ref.invalidate(authoringLessonsProvider(course));
    }
  }
}

/// The attach / replace / remove form for one lesson.
class _AttachSheet extends ConsumerStatefulWidget {
  const _AttachSheet({required this.lesson, required this.target});

  final AuthoringLesson lesson;
  final UploadTarget target;

  @override
  ConsumerState<_AttachSheet> createState() => _AttachSheetState();
}

class _AttachSheetState extends ConsumerState<_AttachSheet> {
  final _link = TextEditingController();
  final _duration = TextEditingController();

  String? _pickedPath;
  String? _pickedName;
  double? _sent;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.lesson.duration > 0) {
      _duration.text = widget.lesson.duration.toString();
    }
  }

  @override
  void dispose() {
    _link.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strategy = widget.target.strategy;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.lesson.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(widget.target.providerLabel, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),

            if (!widget.target.canUpload)
              _Notice(
                icon: Icons.block,
                message:
                    'لا يمكن الرفع عبر «${widget.target.providerLabel}» في هذا '
                    'الإصدار. غيّر مزوّد الفيديو في إعدادات المدرسة.',
              )
            else ...[
              if (strategy == UploadStrategy.siteFile) _filePicker(theme),
              if (strategy == UploadStrategy.externalUrl) _linkField(),
              const SizedBox(height: 12),
              _durationField(theme),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              _Notice(icon: Icons.error_outline, message: _error!),
            ],

            if (_sent != null) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(value: _sent),
              const SizedBox(height: 6),
              Text(
                'جارٍ الرفع… ${((_sent ?? 0) * 100).round()}%',
                style: theme.textTheme.bodySmall,
              ),
            ],

            const SizedBox(height: 20),
            Row(
              children: [
                if (widget.lesson.hasVideo)
                  TextButton.icon(
                    onPressed: _busy ? null : _detach,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('إزالة'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _busy || !widget.target.canUpload ? null : _attach,
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(widget.lesson.hasVideo ? 'استبدال' : 'إرفاق'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filePicker(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.video_library_outlined, size: 18),
              label: const Text('من المعرض'),
            ),
          ),
          const SizedBox(width: 8),
          // A teacher standing at the board is one tap from a second
          // explanation. Making them record, leave the app, and come back to
          // find the file is where a remedial clip stops getting made.
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.camera),
              icon: const Icon(Icons.videocam_outlined, size: 18),
              label: const Text('تسجيل'),
            ),
          ),
        ],
      ),
      if (_pickedName != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              const Icon(Icons.check_circle, size: 15, color: Colors.green),
              const SizedBox(width: 6),
              // A filename is LTR text. Left to the ambient RTL direction the
              // bidi algorithm moves the extension to the front, and
              // "1000024789.mp4" is shown as "mp4.1000024789" — a teacher
              // checking they picked the right file cannot read it.
              Expanded(
                child: Text(
                  _pickedName!,
                  style: theme.textTheme.bodySmall,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _linkField() => TextField(
    controller: _link,
    keyboardType: TextInputType.url,
    textDirection: TextDirection.ltr,
    decoration: const InputDecoration(
      labelText: 'رابط الفيديو',
      hintText: 'https://…',
      prefixIcon: Icon(Icons.link),
    ),
  );

  Widget _durationField(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: _duration,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'مدة المقطع (ثانية)',
          prefixIcon: Icon(Icons.timer_outlined),
        ),
      ),
      const SizedBox(height: 5),
      Text(
        // Not cosmetic: the unlock gate is a percentage OF this number. Set it
        // to half the real runtime and the quiz opens halfway through.
        'تُحسب عليها نسبة المشاهدة المطلوبة لفتح الاختبار.',
        style: theme.textTheme.bodySmall,
      ),
    ],
  );

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickVideo(source: source);
    if (file == null) return;

    // Check the size here, not after the upload. Frappe severs an oversized
    // request body at the WSGI layer, so the failure arrives with no reason
    // attached — and by then the teacher has already waited through it.
    final tooBig = widget.target.rejects(await file.length());
    if (tooBig != null) {
      if (mounted) {
        setState(() {
          _pickedPath = null;
          _pickedName = null;
          _error = tooBig;
        });
      }
      return;
    }

    setState(() {
      _pickedPath = file.path;
      _pickedName = file.name;
      _error = null;
    });

    // Read the real runtime off the file so the teacher is not asked to time
    // their own video. They can still correct it; a wrong number here silently
    // moves the unlock gate.
    final seconds = await _probeDuration(Uri.file(_pickedPath!));
    if (seconds != null && mounted) {
      _duration.text = seconds.toString();
    }
  }

  /// Ask the platform decoder how long a clip is. Returns null when it cannot
  /// say — a YouTube link, or a codec this device has no decoder for.
  Future<int?> _probeDuration(Uri uri) async {
    final controller = uri.isScheme('file')
        ? VideoPlayerController.file(File(uri.toFilePath()))
        : VideoPlayerController.networkUrl(uri);

    try {
      await controller.initialize().timeout(const Duration(seconds: 20));
      final seconds = controller.value.duration.inSeconds;
      return seconds > 0 ? seconds : null;
    } catch (_) {
      return null;
    } finally {
      await controller.dispose();
    }
  }

  Future<void> _attach() async {
    final repo = ref.read(teacherRepositoryProvider);
    final duration = int.tryParse(_duration.text.trim());

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      var reference = _link.text.trim();

      if (widget.target.strategy == UploadStrategy.siteFile) {
        final path = _pickedPath;
        if (path == null) {
          throw Exception('اختر ملف الفيديو أولاً.');
        }

        setState(() => _sent = 0);
        reference = await repo.uploadToSite(
          path: path,
          filename: _pickedName ?? 'lesson.mp4',
          onProgress: (sent, total) {
            if (mounted && total > 0) setState(() => _sent = sent / total);
          },
        );
        if (mounted) setState(() => _sent = null);
      }

      if (reference.isEmpty) {
        throw Exception('أدخل رابط الفيديو.');
      }

      await repo.attachVideo(
        lesson: widget.lesson.lesson,
        reference: reference,
        duration: duration,
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sent = null;
          _error = _message(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detach() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(teacherRepositoryProvider).detachVideo(widget.lesson.lesson);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Server validation messages are written for the teacher — «رابط يوتيوب غير
/// صالح» tells them exactly what to fix. Replacing them with a generic failure
/// would throw away the only useful part.
String _message(Object error) =>
    error.toString().replaceFirst(RegExp(r'^(Exception|ApiException): '), '');

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}

String _mmss(int seconds) {
  final m = (seconds ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
