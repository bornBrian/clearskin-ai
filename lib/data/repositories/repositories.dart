import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/chat.dart';
import '../models/check_in.dart';
import '../models/product.dart';
import '../models/profile.dart';
import '../models/scan.dart';
import '../../domain/scan/skin_maps.dart';
import '../../domain/scan/skin_measure.dart';

/// Small typed key-value store on top of the `kv` table.
class KeyValueStore {
  KeyValueStore(this._db);
  final AppDatabase _db;

  Future<String?> get(String key) async {
    final rows = await _db.db.query(
      'kv',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> set(String key, String value) => _db.db.insert('kv', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> remove(String key) =>
      _db.db.delete('kv', where: 'key = ?', whereArgs: [key]);

  Future<Map<String, dynamic>?> getJson(String key) async {
    final raw = await get(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  Future<void> setJson(String key, Map<String, Object?> value) =>
      set(key, jsonEncode(value));
}

abstract final class KvKeys {
  static const profile = 'profile';
  static const weather = 'weather_cache';
  static const scanQuota = 'scan_quota';
  static const productQuota = 'product_quota';
  static const appLock = 'app_lock_enabled';
  static const reviewPrompted = 'review_prompted_at';
  static const devPremium = 'dev_premium';
  static const photoConsent = 'photo_consent_v1';
  static const lastOpen = 'last_open_at';
  static const account = 'account_v1';

  /// Which account the skin data on this phone belongs to (Account.key).
  static const dataOwner = 'data_owner_v1';
  static const firstOpen = 'first_open_at';
  static const interstitialLog = 'interstitial_log';
  static const renewalPrefs = 'renewal_prefs_v1';
  static const accountStatus = 'account_status_v1';
  static const streakCelebrated = 'streak_celebrated_day';

  /// Body size and activity for the water target (HydrationSettings).
  static const hydration = 'hydration_v1';

  /// + yyyy-MM-dd: glasses of water logged that day.
  static const waterPrefix = 'water_';

  /// Setup answers so far, so a closed app resumes at the same question.
  static const onboardingDraft = 'onboarding_draft_v1';

  /// Version of the medical disclaimer the person accepted. Bump
  /// [MedicalDisclaimer.version] when the wording changes materially.
  static const disclaimerAccepted = 'medical_disclaimer_v';
}

class ProfileRepository {
  ProfileRepository(this._kv);
  final KeyValueStore _kv;

  Future<UserProfile?> load() async {
    final raw = await _kv.get(KvKeys.profile);
    if (raw == null) return null;
    try {
      return UserProfile.decode(raw);
    } on FormatException {
      return null;
    }
  }

  Future<void> save(UserProfile p) => _kv.set(KvKeys.profile, p.encode());
}

class ScanRepository {
  ScanRepository(this._db);
  final AppDatabase _db;

  Future<List<SkinScan>> all() async {
    final rows = await _db.db.query('scans', orderBy: 'created_at DESC');
    return rows.map(SkinScan.fromRow).toList();
  }

  Future<void> insert(SkinScan s) => _db.db.insert(
    'scans',
    s.toRow(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> delete(String id) =>
      _db.db.delete('scans', where: 'id = ?', whereArgs: [id]);

  Future<void> setRadiance(String id, Radiance r) => _db.db.update(
    'scans',
    {'radiance_json': jsonEncode(r.toJson())},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> setMeasure(String id, SkinMeasure m) => _db.db.update(
    'scans',
    {'measure_json': jsonEncode(m.toJson())},
    where: 'id = ?',
    whereArgs: [id],
  );
}

class CheckInRepository {
  CheckInRepository(this._db);
  final AppDatabase _db;

  Future<List<CheckIn>> all() async {
    final rows = await _db.db.query('checkins', orderBy: 'day DESC');
    return rows.map(CheckIn.fromRow).toList();
  }

  Future<void> upsert(CheckIn c) => _db.db.insert(
    'checkins',
    c.toRow(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

class RoutineLogRepository {
  RoutineLogRepository(this._db);
  final AppDatabase _db;

  Future<List<RoutineLog>> all() async {
    final rows = await _db.db.query('routine_logs', orderBy: 'day DESC');
    return rows.map(RoutineLog.fromRow).toList();
  }

  Future<void> upsert(RoutineLog log) => _db.db.insert(
    'routine_logs',
    log.toRow(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

class ProductRepository {
  ProductRepository(this._db);
  final AppDatabase _db;

  Future<List<Product>> all() async {
    final rows = await _db.db.query('products', orderBy: 'added_at DESC');
    return rows.map(Product.fromRow).toList();
  }

  Future<void> upsert(Product p) => _db.db.insert(
    'products',
    p.toRow(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> delete(String id) =>
      _db.db.delete('products', where: 'id = ?', whereArgs: [id]);
}

class ChatRepository {
  ChatRepository(this._db);
  final AppDatabase _db;

  Future<List<ChatMessage>> all() async {
    final rows = await _db.db.query('chat_messages', orderBy: 'created_at ASC');
    return rows.map(ChatMessage.fromRow).toList();
  }

  Future<void> insert(ChatMessage m) => _db.db.insert(
    'chat_messages',
    m.toRow(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> clear() => _db.db.delete('chat_messages');
}
