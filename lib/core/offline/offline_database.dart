import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// The device's copy of the school library.
///
/// One table, not two. A downloaded file is not an entity of its own — it is
/// a column on the item it belongs to — and splitting them would make the
/// eviction query a join and the "is this the copy the server has?" question
/// a comparison across two rows.
///
/// The database lives in the application *support* directory, not the cache
/// directory: Android and iOS both reclaim the cache directory under storage
/// pressure without asking, which would silently delete the offline library of
/// a student who is offline precisely because they cannot re-download it.
class OfflineDatabase {
  OfflineDatabase({this.factory});

  /// Injected by tests (`databaseFactoryFfi`), null on a device.
  final DatabaseFactory? factory;

  static const _fileName = 'edupulse_offline.db';
  static const _version = 1;

  Database? _db;

  Future<Database> open() async {
    final existing = _db;
    if (existing != null) return existing;

    final path = await _path();
    final opened = await (factory?.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: _version,
            onCreate: _create,
            onConfigure: _configure,
          ),
        ) ??
        openDatabase(
          path,
          version: _version,
          onCreate: _create,
          onConfigure: _configure,
        ));

    return _db = opened;
  }

  Future<String> _path() async {
    if (factory != null) return inMemoryDatabasePath;

    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, _fileName);
  }

  Future<void> _configure(Database db) =>
      db.execute('PRAGMA foreign_keys = ON');

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE library_item (
        name            TEXT PRIMARY KEY,
        title           TEXT NOT NULL DEFAULT '',
        title_ar        TEXT,
        item_type       TEXT NOT NULL DEFAULT '',
        subject         TEXT,
        skill           TEXT,
        grade_level     TEXT,
        language        TEXT,
        content         TEXT,
        attachment      TEXT,
        thumbnail       TEXT,
        remote_bytes    INTEGER NOT NULL DEFAULT 0,
        remote_version  INTEGER NOT NULL DEFAULT 0,
        remote_checksum TEXT,
        modified        TEXT,
        local_path      TEXT,
        local_bytes     INTEGER NOT NULL DEFAULT 0,
        local_version   INTEGER NOT NULL DEFAULT 0,
        downloaded_at   TEXT,
        last_opened_at  TEXT
      )
    ''');

    // Eviction reads exactly this: downloaded rows, oldest use first.
    await db.execute('''
      CREATE INDEX idx_lru ON library_item (last_opened_at)
      WHERE local_path IS NOT NULL
    ''');

    await db.execute('''
      CREATE TABLE sync_state (
        key   TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
