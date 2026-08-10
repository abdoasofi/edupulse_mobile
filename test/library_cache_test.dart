import 'dart:io';

import 'package:edupulse_mobile/core/offline/library_cache.dart';
import 'package:edupulse_mobile/core/offline/offline_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The offline store, tested where its bugs actually live.
///
/// Every failure here is one a student meets with no signal and no way to
/// report it: a worksheet the school withdrew that never leaves the phone, a
/// download that quietly deletes the thing they were studying, or a shared
/// tablet handing one child's library to the next.
void main() {
  sqfliteFfiInit();

  late Directory downloads;
  late LibraryCache cache;

  /// A manifest row as the server sends it.
  Map<String, dynamic> row(
    String name, {
    String? title,
    int published = 1,
    int offline = 1,
    int version = 1,
    String? attachment,
    String modified = '2026-08-01 10:00:00',
  }) => {
    'name': name,
    'title': title ?? name,
    'title_ar': title ?? name,
    'item_type': 'Summary',
    'subject': 'رياضيات',
    'content': '<p>$name</p>',
    'attachment': attachment,
    'file_size': 0,
    'version': version,
    'checksum': null,
    'modified': modified,
    'published': published,
    'is_offline_available': offline,
  };

  /// Pretend [name] was downloaded, with a real file behind it.
  Future<File> fakeDownload(String name, int bytes) async {
    final file = File(p.join(downloads.path, name));
    await file.create(recursive: true);
    await file.writeAsBytes(List.filled(bytes, 0));

    await cache.registerDownload(
      name: name,
      path: file.path,
      bytes: bytes,
      version: 1,
    );

    return file;
  }

  setUp(() async {
    downloads = await Directory.systemTemp.createTemp('edupulse_library_test');
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

  group('applying a manifest page', () {
    test('stores the body, so the item is readable with no network', () async {
      await cache.applyPage([row('a')]);

      final item = await cache.item('a');

      expect(item!.content, '<p>a</p>');
      expect(item.isAvailableOffline, isTrue);
    });

    test('deletes an item the school unpublished', () async {
      await cache.applyPage([row('a')]);
      await cache.applyPage([row('a', published: 0)]);

      expect(await cache.item('a'), isNull);
    });

    test('deletes an item the school took offline', () async {
      await cache.applyPage([row('a')]);
      await cache.applyPage([row('a', offline: 0)]);

      expect(await cache.item('a'), isNull);
    });

    test('a withdrawal takes the downloaded file with it', () async {
      await cache.applyPage([row('a', attachment: '/files/a.pdf')]);
      final file = await fakeDownload('a', 100);

      await cache.applyPage([row('a', published: 0)]);

      expect(file.existsSync(), isFalse);
      expect(await cache.usedBytes(), 0);
    });

    test('a newer version drops the copy the device is holding', () async {
      // Otherwise the student keeps reading the worksheet the school replaced,
      // with nothing on screen to suggest it is the wrong one.
      await cache.applyPage([row('a', attachment: '/files/a.pdf')]);
      final file = await fakeDownload('a', 100);

      await cache.applyPage([row('a', attachment: '/files/a.pdf', version: 2)]);

      expect(file.existsSync(), isFalse);
      expect((await cache.item('a'))!.isDownloaded, isFalse);
    });

    test('an unchanged version keeps the download', () async {
      await cache.applyPage([row('a', attachment: '/files/a.pdf')]);
      await fakeDownload('a', 100);

      await cache.applyPage([row('a', attachment: '/files/a.pdf')]);

      expect((await cache.item('a'))!.isDownloaded, isTrue);
    });
  });

  group('the storage cap', () {
    test('evicts the least recently used until the file fits', () async {
      await cache.applyPage([row('a'), row('b'), row('c')]);
      await fakeDownload('a', 400);
      await fakeDownload('b', 400);

      await cache.markOpened('b');

      final admission = await cache.makeRoom(400, keep: 'c');

      expect(admission.admitted, isTrue);
      expect(admission.evicted, ['a']);
      expect((await cache.item('b'))!.isDownloaded, isTrue);
    });

    test('never evicts the item being downloaded', () async {
      // Deleting the old copy of the very thing you are replacing, to make
      // room for it, is a way to end up with neither.
      await cache.applyPage([row('a')]);
      await fakeDownload('a', 900);

      final admission = await cache.makeRoom(900, keep: 'a');

      expect(admission.admitted, isFalse);
      expect((await cache.item('a'))!.isDownloaded, isTrue);
    });

    test('refuses a file larger than the whole budget without evicting', () async {
      await cache.applyPage([row('a')]);
      await fakeDownload('a', 400);

      final admission = await cache.makeRoom(2000);

      expect(admission.refusal, AdmissionRefusal.tooLargeForCap);
      expect(admission.evicted, isEmpty);
      expect(await cache.usedBytes(), 400);
    });

    test('a file that fits evicts nothing', () async {
      await cache.applyPage([row('a')]);
      await fakeDownload('a', 400);

      expect((await cache.makeRoom(400)).evicted, isEmpty);
    });

    test('counts a queued download as used, not as cold', () async {
      // A student who queues three worksheets for tonight has opened none of
      // them. Ordering by `last_opened_at` alone makes them the coldest rows
      // in the table, so the fourth download would evict exactly what they
      // just asked for.
      await cache.applyPage([row('old'), row('new')]);

      await fakeDownload('old', 300);
      await cache.markOpened('old');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await fakeDownload('new', 300);

      final admission = await cache.makeRoom(500);

      expect(admission.evicted, ['old']);
    });
  });

  group('who the library belongs to', () {
    test('a different student on the same device starts empty', () async {
      await cache.applyPage([row('a')]);
      await cache.setCursor('2026-08-01 10:00:00');

      final wiped = await cache.claim('site|second@school.test');

      expect(wiped, isTrue);
      expect(await cache.count(), 0);
      expect(await cache.cursor, isNull);
    });

    test('the same student keeps their library', () async {
      await cache.claim('site|first@school.test');
      await cache.applyPage([row('a')]);

      final wiped = await cache.claim('site|first@school.test');

      expect(wiped, isFalse);
      expect(await cache.count(), 1);
    });

    test('the same account on another school starts empty', () async {
      // Two sites can hold the same email. Keying on the user alone would
      // hand one school's material to another.
      await cache.claim('school-a|shared@edu.test');
      await cache.applyPage([row('a')]);

      expect(await cache.claim('school-b|shared@edu.test'), isTrue);
      expect(await cache.count(), 0);
    });

    test('wiping removes the files as well as the rows', () async {
      await cache.applyPage([row('a')]);
      final file = await fakeDownload('a', 100);

      await cache.wipe();

      expect(file.existsSync(), isFalse);
    });
  });

  group('filtering', () {
    test('"on my device" hides what was only synced', () async {
      await cache.applyPage([row('a'), row('b')]);
      await fakeDownload('a', 100);

      final rows = await cache.items(downloadedOnly: true);

      expect(rows.map((r) => r.name), ['a']);
    });

    test('search matches the Arabic title', () async {
      await cache.applyPage([
        row('a', title: 'ملخص الكسور'),
        row('b', title: 'بنك أسئلة الجبر'),
      ]);

      final rows = await cache.items(search: 'الكسور');

      expect(rows.map((r) => r.name), ['a']);
    });
  });
}
