import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/library_item.dart';

/// Standing statement that everything on screen is as old as the last sync.
///
/// Not a snackbar. A student who opened the app on a bus will be here for the
/// whole ride, and a message that disappears after four seconds leaves them
/// reading stale content with nothing to say so.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 18, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'أنت دون اتصال. هذه العناصر محفوظة على جهازك.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// How much of the library's allowance is spent.
///
/// Hidden until it is four fifths full. A storage meter on every visit is
/// furniture a student stops seeing; one that appears when the next download
/// will start deleting something is a warning they can act on.
class StorageLine extends ConsumerWidget {
  const StorageLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final usage = ref.watch(libraryUsageProvider).valueOrNull;

    if (usage == null || !usage.shouldWarn) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sd_storage_outlined, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'مساحة المكتبة: ${humanBytes(usage.usedBytes)} '
                  'من ${humanBytes(usage.capBytes)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: usage.fraction,
              minHeight: 5,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 4),
          // Say what happens next, not just where the number is. "٩٥٪ ممتلئة"
          // asks the student to work out the consequence themselves.
          Text(
            'التنزيل التالي سيحذف أقدم ما لم تفتحه.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.disabledColor,
            ),
          ),
        ],
      ),
    );
  }
}

class LibraryTile extends StatelessWidget {
  const LibraryTile({required this.item, required this.onTap, super.key});

  final LibraryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: Icon(_icon, color: theme.colorScheme.primary),
        title: Text(
          item.displayTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Text(
          [
            item.typeLabel,
            if (item.subject != null && item.subject!.isNotEmpty) item.subject!,
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        trailing: item.isDownloaded
            ? Tooltip(
                message: 'محفوظ على جهازك',
                child: Icon(
                  Icons.offline_pin,
                  color: const Color(0xFF10B981),
                  size: 22,
                ),
              )
            : item.hasAttachment
            ? Icon(
                Icons.download_outlined,
                size: 20,
                color: theme.disabledColor,
              )
            : null,
      ),
    );
  }

  IconData get _icon => switch (item.itemType) {
    'Summary' => Icons.article_outlined,
    'Question Bank' => Icons.quiz_outlined,
    'Mind Map' => Icons.account_tree_outlined,
    'Formula Sheet' => Icons.functions,
    'Worksheet' => Icons.edit_note_outlined,
    _ => Icons.menu_book_outlined,
  };
}
