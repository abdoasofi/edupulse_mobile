import 'dart:io';

import 'package:edupulse_mobile/core/config/app_config.dart';
import 'package:edupulse_mobile/core/network/api_client.dart';
import 'package:edupulse_mobile/core/network/api_result.dart';
import 'package:edupulse_mobile/core/offline/library_cache.dart';
import 'package:edupulse_mobile/core/offline/offline_database.dart';
import 'package:edupulse_mobile/core/storage/token_store.dart';
import 'package:edupulse_mobile/features/library/data/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The sync loop and the download sequence.
///
/// Both are places where a plausible ordering loses data: a paged sync that
/// throws away the pages it did fetch, a cursor that never advances against a
/// server that keeps saying "more", and a download that deletes the copy on
/// the device before knowing whether the replacement arrived.
class _FakeApi extends ApiClient {
  _FakeApi({this.pages = const [], this.bytes = 0, this.fail})
    : super(
        config: const AppConfig(baseUrl: 'http://school.test'),
        tokens: TokenStore(),
      );

  /// One entry per `get_offline_manifest` call, in order.
  final List<Map<String, dynamic>> pages;

  /// What a download writes, when it is allowed to happen.
  final int bytes;
  final Object? fail;

  final List<String?> cursors = [];
  int downloads = 0;

  @override
  Future<ApiResult<T>> get<T>(
    String module,
    String method, {
    Map<String, dynamic>? query,
  }) async {
    cursors.add(query?['since'] as String?);

    final index = cursors.length - 1;
    if (index >= pages.length) throw StateError('unexpected extra sync call');

    final page = pages[index];
    if (page['throw'] == true) {
      throw const ApiException(
        code: ApiErrorCode.network,
        message: 'تعذّر الوصول',
      );
    }

    return ApiResult<T>(data: page as T);
  }

  @override
  Future<int> downloadFile({
    required String url,
    required String savePath,
    void Function(int received, int total)? onProgress,
    Object? cancelToken,
  }) async {
    downloads++;
    if (fail != null) throw fail!;

    await File(savePath).writeAsBytes(List.filled(bytes, 0));
    return bytes;
  }
}

Map<String, dynamic> _page(
  List<String> names, {
  bool hasMore = false,
  String? cursor,
  bool enabled = true,
  String? attachment,
}) => {
  'enabled': enabled,
  'has_more': hasMore,
  'synced_at': cursor ?? '2026-08-01 12:00:00',
  'items': [
    for (final name in names)
      {
        'name': name,
        'title': name,
        'title_ar': name,
        'item_type': 'Worksheet',
        'content': '<p>$name</p>',
        'attachment': attachment,
        'file_size': 0,
        'version': 1,
        'modified': '2026-08-01 10:00:00',
        'published': 1,
        'is_offline_available': 1,
      },
  ],
};

void main() {
  sqfliteFfiInit();

  late Directory downloads;
  late LibraryCache cache;

  LibraryRepository repo(_FakeApi api) =>
      LibraryRepository(api: api, cache: cache);

  setUp(() async {
    downloads = await Directory.systemTemp.createTemp('edupulse_sync_test');
    cache = LibraryCache(
      database: OfflineDatabase(factory: databaseFactoryFfi),
      downloads: downloads,
      capBytes: 1000,
    );
  });

  tearDown(() async {
    await cache.database.close();
    if (downloads.existsSync()) await downloads.delete(recursive: true);
  });

  group('syncing', () {
    test('follows the cursor across pages', () async {
      final api = _FakeApi(
        pages: [
          _page(['a', 'b'], hasMore: true, cursor: 'T1'),
          _page(['c'], cursor: 'T2'),
        ],
      );

      final report = await repo(api).sync();

      expect(report.received, 3);
      expect(api.cursors, [null, 'T1']);
      expect(await cache.count(), 3);
      expect(await cache.cursor, 'T2');
    });

    test('stops when the cursor stops advancing', () async {
      // A server that keeps answering `has_more` with the same timestamp
      // would otherwise loop until the student's data ran out.
      final api = _FakeApi(
        pages: List.generate(3, (_) => _page(['a'], hasMore: true, cursor: 'T')),
      );

      await repo(api).sync();

      expect(api.cursors.length, 2);
    });

    test('an entitlement that went away wipes the device', () async {
      final api = _FakeApi(pages: [_page(['a']), _page([], enabled: false)]);

      await repo(api).sync();
      final report = await repo(api).sync();

      expect(report.wiped, isTrue);
      expect(await cache.count(), 0);
    });

    test('a rebuild drops what the server no longer lists', () async {
      // The repair for a change the delta cannot carry — a renamed subject
      // rewrites rows by SQL and leaves `modified` untouched, so no delta will
      // ever mention it.
      final first = _FakeApi(pages: [_page(['a', 'b'])]);
      await repo(first).sync();

      final second = _FakeApi(pages: [_page(['a'])]);
      final report = await repo(second).sync(full: true);

      expect(report.removed, 1);
      expect(await cache.count(), 1);
      expect(second.cursors, [null]);
    });

    test('a rebuild keeps the files already downloaded', () async {
      // Wiping first would cost a student every worksheet on their phone to
      // fix a label.
      final api = _FakeApi(
        pages: [
          _page(['a'], attachment: '/files/a.pdf'),
          _page(['a'], attachment: '/files/a.pdf'),
        ],
        bytes: 120,
      );
      await repo(api).sync();
      await repo(api).download('a');

      await repo(api).sync(full: true);

      final item = await cache.item('a');
      expect(item!.isDownloaded, isTrue);
      expect(File(item.localPath!).existsSync(), isTrue);
    });

    test('a rebuild cut short by the page bound prunes nothing', () async {
      // It has not seen the rest of the library; deleting what it did not
      // reach would be the bug it exists to repair.
      await repo(_FakeApi(pages: [_page(['a', 'b'])])).sync();

      final truncated = _FakeApi(
        pages: List.generate(
          20,
          (i) => _page(['a'], hasMore: true, cursor: 'T$i'),
        ),
      );
      final report = await repo(truncated).sync(full: true);

      expect(report.removed, 0);
      expect(await cache.count(), 2);
    });

    test('a page that fails keeps the pages that did not', () async {
      // Partly up to date is the normal state of an app like this; throwing
      // away three good pages because the fourth timed out is not.
      final api = _FakeApi(
        pages: [
          _page(['a', 'b'], hasMore: true, cursor: 'T1'),
          {'throw': true},
        ],
      );

      await expectLater(repo(api).sync(), throwsA(isA<ApiException>()));

      expect(await cache.count(), 2);
      expect(await cache.cursor, 'T1');
    });
  });

  group('downloading', () {
    Future<void> seed(_FakeApi api) =>
        repo(api).sync().then((_) {}, onError: (_) {});

    test('admits a file the server never measured', () async {
      // `file_size` is 0 for any attachment without a File row. The bytes are
      // weighed where they are actually known — on disk.
      final api = _FakeApi(
        pages: [
          _page(['a'], attachment: '/files/a.pdf'),
        ],
        bytes: 300,
      );
      await seed(api);

      await repo(api).download('a');

      expect((await cache.item('a'))!.localBytes, 300);
      expect(await cache.usedBytes(), 300);
    });

    test('keeps the extension so the file opens in something', () async {
      final api = _FakeApi(
        pages: [
          _page(['a'], attachment: '/files/a.pdf'),
        ],
        bytes: 10,
      );
      await seed(api);

      await repo(api).download('a');

      expect((await cache.item('a'))!.localPath, endsWith('.pdf'));
    });

    test('a failed download leaves nothing behind', () async {
      final api = _FakeApi(
        pages: [
          _page(['a'], attachment: '/files/a.pdf'),
        ],
        fail: const ApiException(
          code: ApiErrorCode.network,
          message: 'تعذّر الوصول',
        ),
      );
      await seed(api);

      await expectLater(
        repo(api).download('a'),
        throwsA(isA<ApiException>()),
      );

      expect((await cache.item('a'))!.isDownloaded, isFalse);
      expect(downloads.listSync(), isEmpty);
    });

    test('a failed replacement keeps the copy already on the device', () async {
      // The tempting order — delete, then fetch — turns a network blip into a
      // lost worksheet, offline, where re-downloading is not an option.
      final good = _FakeApi(
        pages: [
          _page(['a'], attachment: '/files/a.pdf'),
        ],
        bytes: 200,
      );
      await seed(good);
      await repo(good).download('a');

      final broken = _FakeApi(
        fail: const ApiException(
          code: ApiErrorCode.network,
          message: 'تعذّر الوصول',
        ),
      );

      await expectLater(
        repo(broken).download('a'),
        throwsA(isA<ApiException>()),
      );

      final item = await cache.item('a');
      expect(item!.isDownloaded, isTrue);
      expect(File(item.localPath!).existsSync(), isTrue);
    });

    test('refuses an oversized file before spending any data on it', () async {
      final api = _FakeApi(
        pages: [
          {
            'enabled': true,
            'has_more': false,
            'synced_at': 'T',
            'items': [
              {
                'name': 'a',
                'title': 'a',
                'item_type': 'Worksheet',
                'attachment': '/files/big.pdf',
                'file_size': 5000, // Declared, and larger than the whole cap.
                'version': 1,
                'modified': '2026-08-01 10:00:00',
                'published': 1,
                'is_offline_available': 1,
              },
            ],
          },
        ],
      );
      await seed(api);

      await expectLater(
        repo(api).download('a'),
        throwsA(isA<DownloadRefused>()),
      );

      expect(api.downloads, 0);
    });

    test('an item with no attachment is refused, not attempted', () async {
      final api = _FakeApi(
        pages: [
          _page(['a']),
        ],
      );
      await seed(api);

      await expectLater(
        repo(api).download('a'),
        throwsA(isA<DownloadRefused>()),
      );

      expect(api.downloads, 0);
    });
  });
}
