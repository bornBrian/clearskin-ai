import 'dart:convert';

import 'package:clearskin_ai/core/config/app_store.dart';
import 'package:clearskin_ai/services/ads_service.dart';
import 'package:clearskin_ai/services/security_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('com.clearskinai/security');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(_channel, null);
  });

  group('App Attest flow', () {
    late List<MethodCall> calls;
    late bool attested;

    void fakeIphone() {
      calls = [];
      attested = false;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'appAttestKey' =>
            attested
                ? {'keyId': 'a+b/c='}
                : {'keyId': 'a+b/c=', 'attestation': 'QVRU'},
          'appAttestConfirm' => () {
            attested = true;
          }(),
          'appAttestAssert' => 'as+se/rt==',
          _ => null,
        };
      });
    }

    test('registers once, then signs each call', () async {
      fakeIphone();
      final registered = <String>[];
      final security = SecurityService();
      Future<AttestRegistration> register(String k, String a, int ts) async {
        registered.add('$k $a');
        return AttestRegistration.accepted;
      }

      final token = await security.integrityToken(
        userId: 'u1',
        function: 'analyze-skin',
        timestampMs: 1000,
        registerAppAttest: register,
      );
      // base64url, no padding, so it survives the server's token check.
      expect(token, 'ios.a-b_c.as-se_rt');
      expect(registered, ['a+b/c= QVRU']);
      final assertCall = calls.firstWhere((c) => c.method == 'appAttestAssert');
      // The same request hash Android sends, which the server recomputes.
      expect(
        (assertCall.arguments as Map)['clientDataHash'],
        sha256.convert(utf8.encode('u1|analyze-skin|1000')).toString(),
      );

      await security.integrityToken(
        userId: 'u1',
        function: 'coach',
        timestampMs: 2000,
        registerAppAttest: register,
      );
      expect(registered, hasLength(1), reason: 'registered only once');
    });

    test('a refused attestation resets the key and sends no proof', () async {
      fakeIphone();
      final token = await SecurityService().integrityToken(
        userId: 'u1',
        function: 'coach',
        timestampMs: 1,
        registerAppAttest: (_, _, _) async => AttestRegistration.rejected,
      );
      expect(token, isNull);
      expect(calls.map((c) => c.method), contains('appAttestReset'));
      expect(calls.map((c) => c.method), isNot(contains('appAttestAssert')));
    });

    test('server not set up: no proof, key kept for later', () async {
      fakeIphone();
      final token = await SecurityService().integrityToken(
        userId: 'u1',
        function: 'coach',
        timestampMs: 1,
        registerAppAttest: (_, _, _) async => AttestRegistration.unavailable,
      );
      expect(token, isNull);
      expect(calls.map((c) => c.method), isNot(contains('appAttestReset')));
    });

    test('simulator (no App Attest) sends no proof', () async {
      messenger.setMockMethodCallHandler(_channel, (_) async => null);
      final token = await SecurityService().integrityToken(
        userId: 'u1',
        function: 'coach',
        timestampMs: 1,
        registerAppAttest: (_, _, _) async => AttestRegistration.accepted,
      );
      expect(token, isNull);
    });
  });

  test('iPhone device id is hashed, never sent raw', () async {
    messenger.setMockMethodCallHandler(
      _channel,
      (call) async => call.method == 'deviceId' ? 'RAW-KEYCHAIN-ID' : null,
    );
    final hash = await SecurityService().deviceHash();
    expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(hash, isNot(contains('RAW')));
  });

  test('store wording and links follow the platform', () {
    expect(AppStore.name, 'the App Store');
    expect(AppStore.manageIn, contains('Apple'));
    expect(
      AppStore.subscriptionsUri().toString(),
      'https://apps.apple.com/account/subscriptions',
    );
    expect(
      AppStore.subscriptionsUri(managementUrl: 'https://apple.example/x').host,
      'apple.example',
    );
    // Never follow a non-https management URL.
    expect(
      AppStore.subscriptionsUri(managementUrl: 'javascript:alert(1)').host,
      'apps.apple.com',
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(AppStore.name, 'Google Play');
    final play = AppStore.subscriptionsUri(
      productId: 'premium_monthly:monthly',
    );
    expect(play.host, 'play.google.com');
    expect(play.queryParameters['sku'], 'premium_monthly');
  });

  test('iPhone uses its own ad units (test units in debug)', () {
    final ios = AdsService.unitFor(AdPlacement.rewarded);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final android = AdsService.unitFor(AdPlacement.rewarded);
    expect(ios, isNotNull);
    expect(ios, isNot(android));
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(AdsService.unitFor(AdPlacement.rewarded), isNull);
  });
}
