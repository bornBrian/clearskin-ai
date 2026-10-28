import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/config/env.dart';

/// Device trust signals for the backend, and a tamper check for the app.
///
/// What this can and can't do, honestly: anything that runs on someone's
/// phone can eventually be patched. So nothing valuable is decided here.
/// AI scans, the coach, Premium and rewarded credits are all enforced on
/// the server (RevenueCat receipts, AdMob signatures, Play Integrity on
/// Android, App Attest on iPhone). This class supplies the evidence and makes
/// a re-signed copy obvious.
class SecurityService {
  SecurityService();

  static const _channel = MethodChannel('com.clearskinai/security');

  String? _deviceHash;
  AppTrust? _trust;

  bool get _android => defaultTargetPlatform == TargetPlatform.android;
  bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  /// SHA-256 of the app-scoped Android ID, or on iPhone of a random ID kept
  /// in the Keychain. The raw ID never leaves the phone; the hash lets the
  /// server count free scans per device so reinstalling doesn't reset them.
  Future<String?> deviceHash() async {
    if (_deviceHash != null || !(_android || _ios)) return _deviceHash;
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

  /// A Play Integrity token (Android) or App Attest assertion (iPhone)
  /// bound to this exact call, or null when integrity isn't configured or
  /// can't be produced (the server decides what that means).
  ///
  /// On iPhone the first call registers a new key: [registerAppAttest]
  /// sends its attestation to the server and says whether it was accepted.
  Future<String?> integrityToken({
    required String userId,
    required String function,
    required int timestampMs,
    AppAttestRegistrar? registerAppAttest,
  }) async {
    final hash = _clientDataHash(userId, function, timestampMs);
    if (_ios && registerAppAttest != null) {
      return _appAttestToken(userId, hash, registerAppAttest);
    }
    if (!_android || Env.playIntegrityProjectNumber <= 0) return null;
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

  static String _clientDataHash(String userId, String function, int ts) =>
      sha256.convert(utf8.encode('$userId|$function|$ts')).toString();

  /// `ios.<key id>.<assertion>`, both base64url. Registers the key first if
  /// the server hasn't seen it.
  Future<String?> _appAttestToken(
    String userId,
    String requestHash,
    AppAttestRegistrar register,
  ) async {
    try {
      final ts = clock.now().millisecondsSinceEpoch;
      final key = await _channel.invokeMapMethod<String, Object?>(
        'appAttestKey',
        {'clientDataHash': _clientDataHash(userId, 'app-attest', ts)},
      );
      final keyId = key?['keyId'] as String?;
      if (keyId == null) return null; // Not supported (simulator).
      final attestation = key?['attestation'] as String?;
      if (attestation != null) {
        switch (await register(keyId, attestation, ts)) {
          case AttestRegistration.accepted:
            await _channel.invokeMethod<void>('appAttestConfirm', {
              'keyId': keyId,
            });
          case AttestRegistration.rejected:
            await _channel.invokeMethod<void>('appAttestReset');
            return null;
          case AttestRegistration.unavailable:
            return null;
        }
      }
      final assertion = await _channel.invokeMethod<String>('appAttestAssert', {
        'keyId': keyId,
        'clientDataHash': requestHash,
      });
      if (assertion == null) return null;
      return 'ios.${_base64Url(keyId)}.${_base64Url(assertion)}';
    } on PlatformException catch (e) {
      debugPrint('App Attest failed: ${e.code} ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static String _base64Url(String base64) =>
      base64.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');

  /// The key the server said it doesn't know (e.g. its record was lost):
  /// make a new one next time.
  Future<void> resetAppAttest() async {
    if (!_ios) return;
    try {
      await _channel.invokeMethod<void>('appAttestReset');
    } on PlatformException {
      // Nothing to reset.
    } on MissingPluginException {
      // Tests.
    }
  }

  /// Private window: hidden in the recent-apps switcher, and on Android
  /// closed to screenshots too (iOS can't block them). On while app lock
  /// is on.
  Future<void> setPrivateWindow(bool private) async {
    if (!(_android || _ios)) return;
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

enum AttestRegistration {
  accepted,

  /// The server checked the attestation and refused it.
  rejected,

  /// Offline, or App Attest isn't set up on the server yet.
  unavailable,
}

typedef AppAttestRegistrar = Future<AttestRegistration> Function(
  String keyId,
  String attestation,
  int timestampMs,
);

enum AppTrust {
  genuine,
  tampered,

  /// Debug build, tests, or no expected certificate configured.
  unchecked,
}
