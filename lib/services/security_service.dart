import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/config/env.dart';

/// Device trust signals for the backend, and a tamper check for the app.
///
/// What this can and can't do, honestly: anything that runs on someone's
/// phone can eventually be patched. So nothing valuable is decided here.
/// AI scans, the coach, Premium and rewarded credits are all enforced on
/// the server (RevenueCat receipts, AdMob signatures, Play Integrity). This
/// class supplies the evidence and makes a re-signed copy obvious.
class SecurityService {
  SecurityService();

  static const _channel = MethodChannel('com.clearskinai/security');

  String? _deviceHash;
  AppTrust? _trust;

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  /// SHA-256 of the app-scoped Android ID. The raw ID never leaves the
  /// phone; the hash lets the server count free scans per device so
  /// reinstalling doesn't reset them.
  Future<String?> deviceHash() async {
    if (_deviceHash != null || !_android) return _deviceHash;
    try {
      final id = await _channel.invokeMethod<String>('deviceId');
      if (id == null || id.isEmpty) return null;
      _deviceHash = sha256.convert(utf8.encode('clearskin:$id')).toString();
    } on PlatformException catch (e) {
      debugPrint('deviceId failed: ${e.message}');
    } on MissingPluginException {
      // Tests and non-Android platforms.
    }
    return _deviceHash;
  }

  /// A Play Integrity token bound to this exact call, or null when
  /// integrity isn't configured or Google can't issue one (the server
  /// decides what that means).
  Future<String?> integrityToken({
    required String userId,
    required String function,
    required int timestampMs,
  }) async {
    if (!_android || Env.playIntegrityProjectNumber <= 0) return null;
    final hash = sha256
        .convert(utf8.encode('$userId|$function|$timestampMs'))
        .toString();
    try {
      return await _channel.invokeMethod<String>('integrityToken', {
        'projectNumber': Env.playIntegrityProjectNumber,
        'requestHash': hash,
      });
    } on PlatformException catch (e) {
      debugPrint('Integrity token failed: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Private window: hidden in the recent-apps switcher and closed to
  /// screenshots. On while app lock is on.
  Future<void> setPrivateWindow(bool private) async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': private});
    } on PlatformException catch (e) {
      debugPrint('setSecure failed: ${e.message}');
    } on MissingPluginException {
      // Tests and non-Android platforms.
    }
  }

  /// Checks the APK's signing certificate against the release certificate.
  /// A mismatch means someone unpacked, modified and re-signed the app.
  Future<AppTrust> appTrust() async {
    if (_trust != null) return _trust!;
    if (!_android || kDebugMode || Env.expectedSigningSha256.isEmpty) {
      return _trust = AppTrust.unchecked;
    }
    try {
      final info = await _channel.invokeMapMethod<String, Object?>('appInfo');
      final digests = (info?['signingSha256'] as List?)?.cast<String>() ?? [];
      final expected = Env.expectedSigningSha256
          .split(',')
          .map((s) => s.trim().toUpperCase())
          .where((s) => s.isNotEmpty)
          .toSet();
      final genuine = digests.any((d) => expected.contains(d.toUpperCase()));
      if (!genuine || info?['debuggable'] == true) {
        return _trust = AppTrust.tampered;
      }
      return _trust = AppTrust.genuine;
    } on PlatformException {
      return _trust = AppTrust.unchecked;
    } on MissingPluginException {
      return _trust = AppTrust.unchecked;
    }
  }
}

enum AppTrust {
  genuine,
  tampered,

  /// Debug build, tests, or no expected certificate configured.
  unchecked,
}
