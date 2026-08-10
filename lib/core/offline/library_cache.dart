import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../features/library/domain/library_item.dart';
import 'offline_database.dart';

/// How much of the device the library may occupy.
///
/// A cap exists because the alternative is an app that grows until the phone
/// complains, and the person who then deletes it is a parent who never chose
/// to store any of this. Half a gigabyte holds a term of worksheets and is
/// small enough that nobody notices it.
const int kLibraryCapBytes = 500 * 1024 * 1024;

/// Why a download was refused before it started.
enum AdmissionRefusal {
  /// The file alone is larger than the entire budget. Evicting everything
  /// still would not fit it, so nothing is evicted and nothing is downloaded.
  tooLargeForCap,
}

class Admission {
  const Admission({this.evicted = const [], this.refusal});

  /// Items deleted to make room, so the UI can say what it gave up.
  final List<String> evicted;
  final AdmissionRefusal? refusal;

  bool get admitted => refusal == null;
}

/// Reads and writes the device's library.
///
/// Owns the local files as well as the rows: a row without its file, or a file
/// without its row, is a bug that only shows up offline, so the two are never
/// changed apart.
class LibraryCache {
  LibraryCache({
    required this.database,
    required this.downloads,
    this.capBytes = kLibraryCapBytes,
  });

  final OfflineDatabase database;

  /// Where the downloaded attachments live. Owned here because a row and its
  /// file are never changed apart.
  final Directory downloads;
  final int capBytes;

  static const _kCursor = 'manifest_cursor';
  static const _kOwner = 'owner';

  Future<Database> get _db => database.open();

  // ----------------------------------------------------------------- owner

  /// Bind the store to one person on one site, wiping it if it belonged to
  /// somebody else.
  ///
  /// A school tablet is shared, and a phone is handed to a sibling. Without
  /// this, the second student to log in inherits the first one's library —
  /// their subjects, their downloads, their reading history — which is both a
  /// wrong screen and someone else's data.
  Future<bool> claim(String owner) async {
    final db = await _db;
    final current = await _state(_kOwner);

    if (current == owner) return false;

    await wipe();
    await _setState(_kOwner, owner);
    // A wipe drops the cursor with everything else; be explicit about it so
    // the next sync is a full one rather than a delta onto an empty table.
    await db.delete('sync_state', where: 'key = ?', whereArgs: [_kCursor]);

    return true;
  }

  // ------------------------------------------------------------------ sync

  Future<String?> get cursor => _state(_kCursor);

  Future<void> setCursor(String value) => _setState(_kCursor, value);

  /// Apply one manifest page.
  ///
  /// Rows the school withdrew arrive here too — that is the whole reason the
  /// server stopped filtering them out — and they are deleted, file and all.
  /// Returns how many were removed.
  Future<int> applyPage(List<Map<String, dynamic>> rows) async {
    final db = await _db;
    var removed = 0;

    await db.transaction((txn) async {
      for (final row in rows) {
        final name = row['name'] as String;

        if (!_isAvailable(row)) {
          await _deleteFileOf(txn, name);
          await txn.delete('library_item', where: 'name = ?', whereArgs: [name]);
          removed++;
          continue;
        }

        final incoming = _columns(row);
        final existing = await txn.query(
          'library_item',
          columns: ['local_path', 'local_bytes', 'local_version'],
          where: 'name = ?',
          whereArgs: [name],
        );

        if (existing.isEmpty) {
          await txn.insert('library_item', incoming);
          continue;
        }

        // A newer version on the server makes the downloaded file the wrong
        // file. Keeping it would serve a worksheet the school has replaced,
        // with nothing on screen to suggest it is out of date.
        final localVersion = existing.first['local_version'] as int? ?? 0;
        final stale =
            existing.first['local_path'] != null &&
            (incoming['remote_version'] as int) > localVersion;

        if (stale) {
          await _deleteFileOf(txn, name);
          incoming.addAll({
            'local_path': null,
            'local_bytes': 0,
            'local_version': 0,
            'downloaded_at': null,
          });
        }

        await txn.update(
          'library_item',
          incoming,
          where: 'name = ?',
          whereArgs: [name],
        );
      }
    });

    return removed;
  }

  /// Everything the device holds, newest first, filtered the way the screen
  /// filters.
  Future<List<LibraryItem>> items({
    String? itemType,
    String? subject,
    String? search,
    bool downloadedOnly = false,
  }) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];

    if (itemType != null) {
      where.add('item_type = ?');
      args.add(itemType);
    }
    if (subject != null) {
      where.add('subject = ?');
      args.add(subject);
    }
    if (downloadedOnly) {
      where.add('local_path IS NOT NULL');
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(title LIKE ? OR title_ar LIKE ?)');
      final term = '%${search.trim()}%';
      args..add(term)..add(term);
    }

    final rows = await db.query(
      'library_item',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'modified DESC',
    );

    return rows.map(LibraryItem.fromRow).toList();
  }

  Future<LibraryItem?> item(String name) async {
    final db = await _db;
    final rows = await db.query(
      'library_item',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );

    return rows.isEmpty ? null : LibraryItem.fromRow(rows.first);
  }

  Future<List<String>> subjects() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT DISTINCT subject FROM library_item '
      "WHERE subject IS NOT NULL AND subject <> '' ORDER BY subject",
    );

    return rows.map((r) => r['subject'] as String).toList();
  }

  Future<int> count() async {
    final db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM library_item'),
        ) ??
        0;
  }

  // -------------------------------------------------------------- downloads

  Future<int> usedBytes() async {
    final db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COALESCE(SUM(local_bytes), 0) FROM library_item '
            'WHERE local_path IS NOT NULL',
          ),
        ) ??
        0;
  }

  Future<int> downloadedCount() async {
    final db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM library_item WHERE local_path IS NOT NULL',
          ),
        ) ??
        0;
  }

  /// Free enough room for [bytes], evicting least-recently-used downloads.
  ///
  /// [keep] is never evicted: it is the item being downloaded, and deleting
  /// the previous copy of the very thing you are replacing, to make room for
  /// it, is a way to lose both.
  ///
  /// Recency is `last_opened_at` falling back to `downloaded_at` — a student
  /// who queues five worksheets for tonight has opened none of them, and
  /// treating "never opened" as "coldest" would evict exactly what they just
  /// asked for.
  Future<Admission> makeRoom(int bytes, {String? keep}) async {
    if (bytes > capBytes) {
      return const Admission(refusal: AdmissionRefusal.tooLargeForCap);
    }

    final db = await _db;
    final evicted = <String>[];
    var used = await usedBytes();

    while (used + bytes > capBytes) {
      final rows = await db.query(
        'library_item',
        columns: ['name', 'local_bytes'],
        where: keep == null
            ? 'local_path IS NOT NULL'
            : 'local_path IS NOT NULL AND name <> ?',
        whereArgs: keep == null ? null : [keep],
        orderBy: 'COALESCE(last_opened_at, downloaded_at) ASC',
        limit: 1,
      );

      // Nothing left to give up. Only reachable when `keep` is itself most of
      // the budget, and refusing is better than deleting the library for a
      // file that still will not fit.
      if (rows.isEmpty) {
        return Admission(
          evicted: evicted,
          refusal: AdmissionRefusal.tooLargeForCap,
        );
      }

      final name = rows.first['name'] as String;
      await removeDownload(name);

      used -= rows.first['local_bytes'] as int? ?? 0;
      evicted.add(name);
    }

    return Admission(evicted: evicted);
  }

  Future<void> registerDownload({
    required String name,
    required String path,
    required int bytes,
    required int version,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.update(
      'library_item',
      {
        'local_path': path,
        'local_bytes': bytes,
        'local_version': version,
        'downloaded_at': now,
      },
      where: 'name = ?',
      whereArgs: [name],
    );
  }

  Future<void> removeDownload(String name) async {
    final db = await _db;

    await _deleteFileOf(db, name);
    await db.update(
      'library_item',
      {
        'local_path': null,
        'local_bytes': 0,
        'local_version': 0,
        'downloaded_at': null,
      },
      where: 'name = ?',
      whereArgs: [name],
    );
  }

  Future<void> markOpened(String name) async {
    final db = await _db;

    await db.update(
      'library_item',
      {'last_opened_at': DateTime.now().toUtc().toIso8601String()},
      where: 'name = ?',
      whereArgs: [name],
    );
  }

  /// Drop everything — rows and files.
  ///
  /// Called when the school's entitlement goes away and when the device
  /// changes hands.
  Future<void> wipe() async {
    final db = await _db;

    await db.delete('library_item');
    await db.delete('sync_state');

    if (downloads.existsSync()) {
      await downloads.delete(recursive: true);
    }
  }

  // ----------------------------------------------------------------- detail

  /// A withdrawn item is one the student may no longer have, whichever flag
  /// the school used to withdraw it.
  bool _isAvailable(Map<String, dynamic> row) =>
      _asInt(row['published']) == 1 && _asInt(row['is_offline_available']) == 1;

  Map<String, Object?> _columns(Map<String, dynamic> row) => {
    'name': row['name'],
    'title': row['title'] ?? '',
    'title_ar': row['title_ar'],
    'item_type': row['item_type'] ?? '',
    'subject': row['subject'],
    'skill': row['skill'],
    'grade_level': row['grade_level'],
    'language': row['language'],
    'content': row['content'],
    'attachment': row['attachment'],
    'thumbnail': row['thumbnail'],
    'remote_bytes': _asInt(row['file_size']),
    'remote_version': _asInt(row['version']),
    'remote_checksum': row['checksum'],
    'modified': row['modified']?.toString(),
  };

  Future<void> _deleteFileOf(DatabaseExecutor db, String name) async {
    final rows = await db.query(
      'library_item',
      columns: ['local_path'],
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );

    final path = rows.isEmpty ? null : rows.first['local_path'] as String?;
    if (path == null) return;

    final file = File(path);
    if (file.existsSync()) await file.delete();
  }

  Future<String?> _state(String key) async {
    final db = await _db;
    final rows = await db.query(
      'sync_state',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _setState(String key, String value) async {
    final db = await _db;
    await db.insert(
      'sync_state',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static int _asInt(Object? value) => switch (value) {
    int v => v,
    num v => v.toInt(),
    String v => int.tryParse(v) ?? 0,
    bool v => v ? 1 : 0,
    _ => 0,
  };
}
