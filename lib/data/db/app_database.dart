import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Single on-device SQLite database. All personal data lives here (plus
/// photos in app-private storage), which keeps the app usable offline and
/// makes "export my data" and "delete everything" exact.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const _name = 'clearskin.db';
  static const _version = 4;

  static Future<AppDatabase> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, _name),
      version: _version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        for (var v = 1; v <= version; v++) {
          await _migrate(db, v);
        }
      },
      onUpgrade: (db, from, to) async {
        for (var v = from + 1; v <= to; v++) {
          await _migrate(db, v);
        }
      },
    );
    return AppDatabase._(db);
  }

  /// Append-only migrations. Never edit a shipped step; add a new one.
  static Future<void> _migrate(Database db, int version) async {
    switch (version) {
      case 1:
        final batch = db.batch()
          ..execute('''
            CREATE TABLE kv (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )''')
          ..execute('''
            CREATE TABLE scans (
              id TEXT PRIMARY KEY,
              created_at INTEGER NOT NULL,
              photo_path TEXT NOT NULL,
              overall_score INTEGER NOT NULL,
              usable INTEGER NOT NULL,
              analysis_json TEXT NOT NULL
            )''')
          ..execute('CREATE INDEX idx_scans_created ON scans(created_at)')
          ..execute('''
            CREATE TABLE checkins (
              day TEXT PRIMARY KEY,
              skin_feel INTEGER NOT NULL,
              breakouts INTEGER NOT NULL,
              sleep_hours REAL NOT NULL,
              stress INTEGER NOT NULL,
              water INTEGER NOT NULL,
              tags TEXT NOT NULL,
              note TEXT NOT NULL DEFAULT ''
            )''')
          ..execute('''
            CREATE TABLE routine_logs (
              day TEXT NOT NULL,
              slot TEXT NOT NULL,
              steps TEXT NOT NULL,
              PRIMARY KEY (day, slot)
            )''')
          ..execute('''
            CREATE TABLE products (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              brand TEXT NOT NULL DEFAULT '',
              category TEXT NOT NULL,
              usage TEXT NOT NULL,
              ingredients TEXT NOT NULL DEFAULT '',
              added_at INTEGER NOT NULL,
              barcode TEXT,
              image_url TEXT,
              status TEXT NOT NULL DEFAULT 'active'
            )''')
          ..execute('''
            CREATE TABLE chat_messages (
              id TEXT PRIMARY KEY,
              role TEXT NOT NULL,
              text TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )''')
          ..execute(
            'CREATE INDEX idx_chat_created ON chat_messages(created_at)',
          );
        await batch.commit(noResult: true);
      case 2:
        await db.execute('ALTER TABLE scans ADD COLUMN face_json TEXT');
      case 3:
        // On-device radiance measurement, filled in after the scan.
        await db.execute('ALTER TABLE scans ADD COLUMN radiance_json TEXT');
      case 4:
        // Per-lens, per-zone measurements (progress proof) and product
        // shelf life.
        final batch = db.batch()
          ..execute('ALTER TABLE scans ADD COLUMN measure_json TEXT')
          ..execute('ALTER TABLE products ADD COLUMN opened_at INTEGER')
          ..execute('ALTER TABLE products ADD COLUMN pao_months INTEGER');
        await batch.commit(noResult: true);
    }
  }

  /// Wipes every table. Used by "Delete all my data".
  Future<void> clearAll() async {
    await db.transaction((txn) async {
      for (final t in const [
        'kv',
        'scans',
        'checkins',
        'routine_logs',
        'products',
        'chat_messages',
      ]) {
        await txn.delete(t);
      }
    });
  }
}
