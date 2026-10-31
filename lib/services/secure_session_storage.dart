import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the Supabase session (access and refresh tokens) in the platform's
/// secure store: AES-GCM with a key held by Android's Keystore, and the
/// Keychain on iPhone. Supabase's default keeps it in plain
/// SharedPreferences, readable from a rooted phone or a backup tool.
///
/// A session saved by an earlier version is moved across once and deleted
/// from SharedPreferences, so nobody is signed out by the update.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this.persistSessionKey});

  /// The same key Supabase uses (`sb-<project ref>-auth-token`).
  final String persistSessionKey;

  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(persistSessionKey);
    if (legacy == null) return;
    if (await _store.read(key: persistSessionKey) == null) {
      await _store.write(key: persistSessionKey, value: legacy);
    }
    await prefs.remove(persistSessionKey);
  }

  @override
  Future<bool> hasAccessToken() => _store.containsKey(key: persistSessionKey);

  @override
  Future<String?> accessToken() => _store.read(key: persistSessionKey);

  @override
  Future<void> removePersistedSession() =>
      _store.delete(key: persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _store.write(key: persistSessionKey, value: persistSessionString);
}
