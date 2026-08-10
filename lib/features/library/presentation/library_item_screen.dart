import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/network/api_result.dart';
import '../../../shared/widgets/async_view.dart';
import '../data/library_repository.dart';
import '../domain/library_item.dart';

/// One library item, read from the device.
///
/// The body travels with the row, so a summary or a mind map is readable the
/// moment it has synced — no download, no network. Only an *attached file*
/// costs storage, which is why the download button belongs here and not on the
/// list: it is a decision about one thing, made while looking at it.
class LibraryItemScreen extends ConsumerWidget {
  const LibraryItemScreen({required this.item, super.key});

  final String item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(libraryItemProvider(item));

    return Scaffold(
      appBar: AppBar(
        title: Text(value.valueOrNull?.displayTitle ?? 'عنصر المكتبة'),
      ),
      body: AsyncView<LibraryItem?>(
        value: value,
        onRetry: () => ref.invalidate(libraryItemProvider(item)),
        builder: (data) {
          if (data == null) {
            return const EmptyState(
              icon: Icons.search_off,
              message: 'لم يعد هذا العنصر في مكتبتك.',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _Header(item: data),
              const SizedBox(height: 20),
              if (data.content != null && data.content!.trim().isNotEmpty)
                _Body(html: data.content!)
              else if (!data.hasAttachment)
                const EmptyState(
                  icon: Icons.description_outlined,
                  message: 'لا محتوى في هذا العنصر بعد.',
                ),
              if (data.hasAttachment) ...[
                const SizedBox(height: 24),
                _Attachment(item: data),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item});

  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.displayTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            Chip(
              label: Text(item.typeLabel),
              visualDensity: VisualDensity.compact,
            ),
            if (item.subject != null && item.subject!.isNotEmpty)
              Chip(
                label: Text(item.subject!),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    );
  }
}

/// The stored body.
///
/// Rendered as text, with tags stripped rather than interpreted. Shipping an
/// HTML renderer for what is in practice a paragraph would add a dependency
/// and a remote-content surface to a screen whose whole point is that it works
/// with nothing behind it.
class _Body extends StatelessWidget {
  const _Body({required this.html});

  final String html;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      _plain(html),
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.7),
    );
  }

  static String _plain(String value) => value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li|h[1-6])>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// The attached file: download it, keep it, or give the space back.
class _Attachment extends ConsumerStatefulWidget {
  const _Attachment({required this.item});

  final LibraryItem item;

  @override
  ConsumerState<_Attachment> createState() => _AttachmentState();
}

class _AttachmentState extends ConsumerState<_Attachment> {
  double? _progress;
  bool _busy = false;

  LibraryItem get _item => widget.item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _item.isDownloaded
                      ? Icons.offline_pin
                      : Icons.attach_file,
                  color: _item.isDownloaded
                      ? const Color(0xFF10B981)
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _item.isDownloaded
                        ? 'الملف محفوظ على جهازك (${humanBytes(_item.localBytes)})'
                        : _sizeLine,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (_progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _progress),
            ],
            const SizedBox(height: 12),
            if (_item.isDownloaded)
              OutlinedButton.icon(
                onPressed: _busy ? null : _remove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('حذف من الجهاز'),
              )
            else
              FilledButton.icon(
                onPressed: _busy ? null : _download,
                icon: const Icon(Icons.download),
                label: const Text('تنزيل للقراءة دون اتصال'),
              ),
          ],
        ),
      ),
    );
  }

  /// «ملف مرفق» when the server does not know the size — an external URL has
  /// no `File` row to measure, and «٠ بايت» would be a lie about a real file.
  String get _sizeLine {
    final size = _item.downloadSize;
    return size == null ? 'ملف مرفق' : 'ملف مرفق · ${humanBytes(size)}';
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _progress = 0;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final repo = await ref.read(libraryRepositoryProvider.future);
      final admission = await repo.download(
        _item.name,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = received / total);
        },
      );

      if (!mounted) return;
      _refresh();

      // Say what was given up. A student who returns to find three worksheets
      // gone, with nothing having said so, learns not to trust the library.
      if (admission.evicted.isNotEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'تم التنزيل، وحُذف ${admission.evicted.length} من أقدم ما لم '
              'تفتحه لإفساح المساحة.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(_message(e))));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);

    try {
      final repo = await ref.read(libraryRepositoryProvider.future);
      await repo.remove(_item.name);
      if (mounted) _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _refresh() => ref
    ..invalidate(libraryItemProvider(_item.name))
    ..invalidate(libraryItemsProvider)
    ..invalidate(libraryUsageProvider);

  /// A transport failure already names the address it could not reach, and a
  /// refusal already explains itself. Replacing either with a generic line
  /// throws away the only sentence the student could act on.
  String _message(Object error) => switch (error) {
    DownloadRefused e => e.message,
    ApiException e => e.message,
    _ => 'تعذّر تنزيل الملف.',
  };
}
