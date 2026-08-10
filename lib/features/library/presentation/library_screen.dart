import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/async_view.dart';
import '../../auth/domain/session.dart';
import '../data/library_repository.dart';
import '../domain/library_item.dart';
import 'library_widgets.dart';

/// مكتبة إدو بلس — the offline library.
///
/// Everything on this screen is read from the device. A sync fills the
/// database in the background and the list rebuilds; it never blocks on the
/// network, because the one student who most needs this screen is the one
/// whose network is not there.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String? _type;
  String _search = '';
  bool _downloadedOnly = false;

  @override
  void initState() {
    super.initState();
    // One sync per visit, after the first frame so the cached list paints
    // immediately rather than waiting on a server that may not answer.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(quiet: true));
  }

  LibraryQuery get _query => (
    itemType: _type,
    search: _search,
    downloadedOnly: _downloadedOnly,
  );

  Future<void> _sync({bool quiet = false, bool full = false}) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final repo = await ref.read(libraryRepositoryProvider.future);
      final report = await repo.sync(full: full);

      if (!mounted) return;
      ref
        ..invalidate(libraryItemsProvider)
        ..invalidate(libraryUsageProvider);

      if (report.wiped) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('لم تعد المكتبة دون اتصال ضمن اشتراك مدرستك.'),
          ),
        );
      } else if (!quiet) {
        messenger.showSnackBar(
          SnackBar(content: Text(_syncMessage(report))),
        );
      }
    } catch (e) {
      if (!mounted || quiet) return;
      messenger.showSnackBar(SnackBar(content: Text(_errorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final offline = auth is Authenticated && auth.offline;
    final items = ref.watch(libraryItemsProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('مكتبة إدو بلس'),
        actions: [
          IconButton(
            tooltip: 'تحديث المكتبة',
            icon: const Icon(Icons.sync),
            onPressed: _sync,
          ),
          // The escape hatch for a change the delta cannot carry: renaming a
          // subject on the server rewrites every row that points at it without
          // touching `modified`, so an ordinary sync will never learn of it and
          // the phone shows the old label indefinitely.
          PopupMenuButton<void>(
            itemBuilder: (_) => [
              PopupMenuItem(
                onTap: () => _sync(full: true),
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.restart_alt),
                  title: Text('إعادة بناء المكتبة'),
                  subtitle: Text('يبقى ما نزّلته على جهازك'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (offline) const OfflineBanner(),
          _Filters(
            type: _type,
            search: _search,
            downloadedOnly: _downloadedOnly,
            onType: (value) => setState(() => _type = value),
            onSearch: (value) => setState(() => _search = value),
            onDownloadedOnly: (value) =>
                setState(() => _downloadedOnly = value),
          ),
          const StorageLine(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _sync,
              child: AsyncView<List<LibraryItem>>(
                value: items,
                onRetry: () => ref.invalidate(libraryItemsProvider),
                builder: (rows) => rows.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 60),
                          EmptyState(
                            icon: Icons.menu_book_outlined,
                            message: _emptyMessage(offline),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
                        itemCount: rows.length,
                        itemBuilder: (_, i) => LibraryTile(
                          item: rows[i],
                          onTap: () => context.push(
                            '/student/home/library/item/${rows[i].name}',
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _emptyMessage(bool offline) {
    if (_downloadedOnly) return 'لم تنزّل أي عنصر بعد.';
    if (_search.isNotEmpty || _type != null) {
      return 'لا عنصر يطابق بحثك.';
    }

    return offline
        ? 'لا عناصر محفوظة على جهازك، ولا اتصال لتحميلها الآن.'
        : 'لم تُضف مدرستك عناصر إلى المكتبة بعد.';
  }

  String _syncMessage(SyncReport report) {
    if (report.received == 0 && report.removed == 0) {
      return 'المكتبة محدَّثة.';
    }

    final parts = <String>[
      if (report.received > 0) 'حُدّث ${report.received}',
      if (report.removed > 0) 'حُذف ${report.removed}',
    ];

    return '${parts.join('، ')} من عناصر المكتبة.';
  }
}

String _errorText(Object error) =>
    error is DownloadRefused ? error.message : 'تعذّر تحديث المكتبة الآن.';

class _Filters extends ConsumerWidget {
  const _Filters({
    required this.type,
    required this.search,
    required this.downloadedOnly,
    required this.onType,
    required this.onSearch,
    required this.onDownloadedOnly,
  });

  final String? type;
  final String search;
  final bool downloadedOnly;
  final ValueChanged<String?> onType;
  final ValueChanged<String> onSearch;
  final ValueChanged<bool> onDownloadedOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'ابحث في المكتبة',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: onSearch,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                FilterChip(
                  label: const Text('على جهازي'),
                  selected: downloadedOnly,
                  avatar: const Icon(Icons.offline_pin_outlined, size: 18),
                  onSelected: onDownloadedOnly,
                ),
                const SizedBox(width: 8),
                ...LibraryItem.typeOptions.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: FilterChip(
                      label: Text(entry.value),
                      selected: type == entry.key,
                      onSelected: (on) => onType(on ? entry.key : null),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
