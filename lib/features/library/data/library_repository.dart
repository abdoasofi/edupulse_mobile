import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:path/path.dart' as p;

import '../../../core/network/api_client.dart';
import '../../../core/offline/library_cache.dart';
import '../domain/library_item.dart';

/// Outcome of a sync, in the terms the screen reports it.
class SyncReport {
  const SyncReport({
    this.pages = 0,
    this.received = 0,
    this.removed = 0,
    this.wiped = false,
  });

  final int pages;
  final int received;
  final int removed;

  /// The school no longer has the offline library. Everything was deleted.
  final bool wiped;
}

class DownloadRefused implements Exception {
  const DownloadRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

class LibraryRepository {
  LibraryRepository({required this.api, required this.cache});

  final ApiClient api;
  final LibraryCache cache;

  /// A cursor that stops advancing would loop forever against a server that
  /// keeps answering `has_more`. Twenty pages is 4,000 items — far past any
  /// real school library, and a bound rather than a promise.
  static const int _maxPages = 20;

  // -------------------------------------------------------------------- sync

  /// Pull every manifest page the server has for us.
  ///
  /// Applied page by page rather than accumulated and applied at the end: a
  /// sync that dies on page four should leave the first three on the device,
  /// not throw them away. Being partly up to date is the normal state of an
  /// app like this.
  Future<SyncReport> sync({bool full = false}) async {
    var cursor = full ? null : await cache.cursor;
    var pages = 0;
    var received = 0;
    var removed = 0;
    var reachedEnd = false;

    // Only a full walk knows what the server no longer has.
    final seen = <String>{};

    while (pages < _maxPages) {
      final result = await api.get<Map<String, dynamic>>(
        'student',
        'get_offline_manifest',
        query: {'since': cursor},
      );

      final data = result.data;

      // Not "nothing changed" — the entitlement is gone, and content the
      // school stopped paying for should not stay readable on the device.
      if (data['enabled'] != true) {
        await cache.wipe();
        return SyncReport(pages: pages, wiped: true);
      }

      final rows = (data['items'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      removed += await cache.applyPage(rows);
      received += rows.length;
      pages++;

      if (full) seen.addAll(rows.map((r) => r['name'] as String));

      final next = data['synced_at'] as String?;
      if (next != null) await cache.setCursor(next);

      // Stop on the last page, and on a cursor that did not move — the second
      // is the only thing standing between a server bug and an infinite loop
      // on a student's data plan.
      if (data['has_more'] != true || next == null || next == cursor) {
        reachedEnd = data['has_more'] != true;
        break;
      }

      cursor = next;
    }

    // Only prune on a walk that actually finished. A full sync cut short by
    // the page bound has not seen the rest of the library, and deleting
    // everything it did not reach would be the bug it exists to repair.
    if (full && reachedEnd) removed += await cache.retainOnly(seen);

    return SyncReport(pages: pages, received: received, removed: removed);
  }

  // ---------------------------------------------------------------- reading

  Future<List<LibraryItem>> items({
    String? itemType,
    String? subject,
    String? search,
    bool downloadedOnly = false,
  }) => cache.items(
    itemType: itemType,
    subject: subject,
    search: search,
    downloadedOnly: downloadedOnly,
  );

  Future<List<String>> subjects() => cache.subjects();

  Future<LibraryItem?> open(String name) async {
    await cache.markOpened(name);
    return cache.item(name);
  }

  Future<StorageUsage> usage() async => StorageUsage(
    usedBytes: await cache.usedBytes(),
    capBytes: cache.capBytes,
    downloads: await cache.downloadedCount(),
  );

  // -------------------------------------------------------------- downloads

  /// Download an item's attachment, evicting older ones if the budget is full.
  ///
  /// The order matters and is not the obvious one. The server's `file_size` is
  /// zero whenever the attachment is an external URL, so the budget cannot
  /// always be checked before starting. Instead the bytes land in a temporary
  /// file first, where their real size is known, and only then are they
  /// admitted — which is also what makes a half-finished download impossible
  /// to mistake for a complete one, since it never occupies the real path.
  Future<Admission> download(
    String name, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final item = await cache.item(name);

    if (item == null) {
      throw const DownloadRefused('لم يعد هذا العنصر في مكتبتك.');
    }
    if (!item.hasAttachment) {
      throw const DownloadRefused('لا ملف مرفقاً بهذا العنصر.');
    }

    // Refuse what cannot fit before spending the student's data on it, when
    // the server told us enough to know.
    final declared = item.downloadSize;
    if (declared != null && declared > cache.capBytes) {
      throw DownloadRefused(_tooLarge(declared));
    }

    final directory = cache.downloads;
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final staging = File(p.join(directory.path, '$name.part'));
    final target = p.join(directory.path, '$name${_extension(item.attachment)}');

    final bytes = await api.downloadFile(
      url: item.attachment!,
      savePath: staging.path,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );

    final admission = await cache.makeRoom(bytes, keep: name);

    if (!admission.admitted) {
      if (staging.existsSync()) await staging.delete();
      throw DownloadRefused(_tooLarge(bytes));
    }

    // Replacing a previous copy: drop it only now, once the new bytes are on
    // disk and admitted. Doing it earlier trades a stale file for no file at
    // all whenever the download fails.
    if (item.isDownloaded) await cache.removeDownload(name);

    await staging.rename(target);
    await cache.registerDownload(
      name: name,
      path: target,
      bytes: bytes,
      version: item.remoteVersion,
    );

    return admission;
  }

  Future<void> remove(String name) => cache.removeDownload(name);

  String _tooLarge(int bytes) =>
      'حجم الملف ${humanBytes(bytes)}، وهو أكبر من المساحة المخصّصة '
      'للمكتبة كاملة (${humanBytes(cache.capBytes)}).';

  /// Keep the server's extension so the platform opens the file with the right
  /// application. A PDF saved without `.pdf` opens in nothing.
  String _extension(String? url) {
    final ext = p.extension(Uri.parse(url ?? '').path);
    return ext.length <= 8 ? ext : '';
  }
}

class StorageUsage {
  const StorageUsage({
    required this.usedBytes,
    required this.capBytes,
    required this.downloads,
  });

  final int usedBytes;
  final int capBytes;
  final int downloads;

  double get fraction => capBytes == 0 ? 0 : (usedBytes / capBytes).clamp(0, 1);

  int get freeBytes => capBytes - usedBytes;

  /// Silent until it matters. A storage line on every visit is furniture; one
  /// that appears at four fifths full is information.
  bool get shouldWarn => fraction >= 0.8;
}
