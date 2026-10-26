import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../core/config/env.dart';
import '../data/repositories/repositories.dart';

/// Funnel and health events. Names are stable: dashboards depend on them.
enum Ev {
  appOpen('app_open'),
  onboardingComplete('onboarding_complete'),
  planRevealView('plan_reveal_view'),
  paywallView('paywall_view'),
  purchaseResult('purchase_result'),
  scanStarted('scan_started'),
  scanAutoCaptured('scan_auto_captured'),
  scanQualityIssue('scan_quality_issue'),
  scanCompleted('scan_completed'),
  scanFailed('scan_failed'),
  routineCompleted('routine_completed'),
  checkInSaved('checkin_saved'),
  productAdded('product_added'),
  shareCardShared('share_card_shared'),
  coachMessageSent('coach_message_sent'),
  tipOpened('tip_opened'),
  appError('app_error');

  const Ev(this.name);
  final String name;
}

/// Privacy-first product analytics + error reporting via PostHog's HTTP API.
///
/// - Anonymous random id (no name, email, photos or health answers ever).
/// - Users can opt out in Settings; nothing is sent when opted out.
/// - Disabled entirely when no key is configured (development).
class Telemetry {
  Telemetry(KeyValueStore this._kv, {http.Client? client})
    : _http = client ?? http.Client();

  /// Inert instance that never sends anything (tests, screenshots).
  Telemetry.noop() : _kv = null, _http = http.Client();

  final KeyValueStore? _kv;
  final http.Client _http;
  final _queue = <Map<String, Object?>>[];
  String? _id;
  bool _optedOut = false;
  Timer? _timer;

  static const _idKey = 'telemetry_id';
  static const _optOutKey = 'telemetry_opt_out';

  bool get enabled => Env.posthogKey.isNotEmpty && !_optedOut;
  bool get optedOut => _optedOut;

  Future<void> init() async {
    final kv = _kv;
    if (kv == null) return;
    _optedOut = await kv.get(_optOutKey) == '1';
    _id = await kv.get(_idKey);
    if (_id == null) {
      _id = const Uuid().v4();
      await kv.set(_idKey, _id!);
    }
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
  }

  Future<void> setOptOut(bool value) async {
    _optedOut = value;
    await _kv?.set(_optOutKey, value ? '1' : '0');
    if (value) _queue.clear();
  }

  void track(Ev event, [Map<String, Object?> props = const {}]) {
    if (kDebugMode) debugPrint('[telemetry] ${event.name} $props');
    if (!enabled || _id == null) return;
    _queue.add({
      'event': event.name,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'properties': {
        'distinct_id': _id,
        r'$process_person_profile': false,
        'platform': defaultTargetPlatform.name,
        'app_version': Env.appVersion,
        ...props,
      },
    });
    if (_queue.length >= 20) unawaited(flush());
  }

  void captureError(Object error, StackTrace? stack, {String? context}) {
    track(Ev.appError, {
      'type': error.runtimeType.toString(),
      // Error messages never contain user content in this app, but cap them.
      'message': _cap(error.toString(), 300),
      'stack': _cap(stack?.toString() ?? '', 3000),
      'context': ?context,
    });
    unawaited(flush());
  }

  static String _cap(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);

  Future<void> flush() async {
    if (_queue.isEmpty || !enabled) return;
    final batch = List<Map<String, Object?>>.of(_queue);
    _queue.clear();
    try {
      await _http
          .post(
            Uri.parse('${Env.posthogHost}/batch/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'api_key': Env.posthogKey, 'batch': batch}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Offline: keep the most recent events for the next attempt.
      _queue.insertAll(0, batch.take(100));
    }
  }

  void dispose() {
    _timer?.cancel();
    unawaited(flush());
  }
}
