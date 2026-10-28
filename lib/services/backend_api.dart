import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_store.dart';
import '../core/config/env.dart';
import '../data/models/account_status.dart';
import '../data/models/chat.dart';
import '../data/models/profile.dart';
import '../data/models/scan.dart';
import 'security_service.dart';

enum ApiErrorKind {
  offline,
  premiumRequired,
  quotaExceeded,
  badImage,
  notConfigured,
  untrusted,
  server,
}

class ApiException implements Exception {
  const ApiException(this.kind, this.message);
  final ApiErrorKind kind;
  final String message;

  @override
  String toString() => 'ApiException($kind): $message';
}

/// Client for the ClearSkin Edge Functions. The app authenticates with an
/// anonymous Supabase session (no sign-up friction); the session id doubles
/// as the RevenueCat app-user-id so the server can verify Premium.
class BackendApi {
  BackendApi(this._security);

  final SecurityService _security;

  SupabaseClient get _client => Supabase.instance.client;

  /// Ensures an (anonymous) session exists and returns the user id, or null
  /// when the backend isn't configured (demo mode).
  Future<String?> ensureSession() async {
    if (!Env.hasBackend) return null;
    final auth = _client.auth;
    final existing = auth.currentUser;
    if (existing != null) return existing.id;
    try {
      final res = await auth.signInAnonymously();
      return res.user?.id;
    } on AuthException catch (e) {
      debugPrint('Anonymous sign-in failed: ${e.message}');
      return null;
    } on SocketException {
      return null;
    }
  }

  String? get userId => Env.hasBackend ? _client.auth.currentUser?.id : null;

  /// [jpeg] should be the small AI copy (≤1024 px, ~150 KB): image tokens
  /// scale with pixels, so this is the single biggest cost lever.
  Future<SkinAnalysis> analyzeSkin({
    required Uint8List jpeg,
    required UserProfile profile,
    SkinAnalysis? previous,
    Set<SkinIssue> issues = const {},
    List<Uint8List> sideJpegs = const [],
  }) async {
    if (Env.aiDemo) return _demoAnalysis(previous);
    final body = {
      'image_base64': base64Encode(jpeg),
      'media_type': 'image/jpeg',
      'profile': profile.toAiContext(),
      'current_issues': [for (final i in issues) i.key],
      if (sideJpegs.isNotEmpty)
        'side_images': [for (final j in sideJpegs.take(2)) base64Encode(j)],
      if (previous != null && previous.usable)
        'previous': {
          'overall_score': previous.overallScore,
          'metrics': previous.metrics.map((m) => m.toJson()).toList(),
        },
    };
    final data = await _invoke(
      'analyze-skin',
      body,
      timeout: const Duration(seconds: 90),
    );
    final analysis = data['analysis'];
    if (analysis is! Map<String, dynamic>) {
      throw const ApiException(
        ApiErrorKind.server,
        'The analysis came back empty. Please try again.',
      );
    }
    return SkinAnalysis.fromJson({
      ...analysis,
      if (data['disclaimer'] is String) 'disclaimer': data['disclaimer'],
    });
  }

  /// Plan, scan allowance and shop links, as the server sees them. Null in
  /// demo mode or when offline (callers fall back to cached values).
  Future<AccountStatus?> accountStatus() async {
    if (!Env.hasBackend) return null;
    try {
      final data = await _invoke(
        'account-status',
        const {},
        timeout: const Duration(seconds: 15),
      );
      return AccountStatus.fromJson(data);
    } on ApiException catch (e) {
      debugPrint('account-status failed: ${e.message}');
      return null;
    }
  }

  Future<String> coachReply({
    required List<ChatMessage> history,
    required UserProfile profile,
    SkinAnalysis? latestScan,
    List<String> routineSummary = const [],
    List<String> shelf = const [],
  }) async {
    if (Env.aiDemo) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      return 'Demo mode: connect the backend to chat with your AI coach. '
          'In the meantime, keep your routine consistent and wear SPF daily!';
    }
    // Last 20 turns are plenty of context and cap cost.
    final recent = history.length > 20
        ? history.sublist(history.length - 20)
        : history;
    final data = await _invoke('coach', {
      'messages': [
        for (final m in recent) {'role': m.role.name, 'content': m.text},
      ],
      'context': {
        'profile': profile.toAiContext(),
        if (latestScan != null)
          'latest_scan': {
            'overall_score': latestScan.overallScore,
            'summary': latestScan.summary,
            'priorities': latestScan.priorities,
            'metrics': latestScan.metrics.map((m) => m.toJson()).toList(),
          },
        'routine': routineSummary,
        'shelf': shelf,
      },
    }, timeout: const Duration(seconds: 60));
    final reply = data['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      throw const ApiException(
        ApiErrorKind.server,
        'No reply. Please try again.',
      );
    }
    return reply.trim();
  }

  /// Deletes the server-side account, usage records and subscription
  /// customer record. Required by Google Play's account-deletion policy.
  Future<void> deleteAccount() async {
    if (!Env.hasBackend || _client.auth.currentUser == null) return;
    await _invoke(
      'delete-account',
      const {},
      timeout: const Duration(seconds: 30),
    );
    await _client.auth.signOut();
  }

  Future<Map<String, dynamic>> _invoke(
    String fn,
    Map<String, Object?> body, {
    required Duration timeout,
  }) async {
    if (!Env.hasBackend) {
      throw const ApiException(
        ApiErrorKind.notConfigured,
        'This feature is temporarily unavailable.',
      );
    }
    final uid = await ensureSession();
    if (uid == null) {
      throw const ApiException(
        ApiErrorKind.offline,
        'Can\'t reach ClearSkin right now. Check your connection.',
      );
    }
    final ts = clock.now().millisecondsSinceEpoch;
    final device = await _security.deviceHash();
    final integrity = await _security.integrityToken(
      userId: uid,
      function: fn,
      timestampMs: ts,
      registerAppAttest: _registerAppAttest,
    );
    try {
      final res = await _client.functions
          .invoke(
            fn,
            body: body,
            headers: {
              'x-cs-ts': '$ts',
              'x-cs-device': ?device,
              'x-cs-integrity': ?integrity,
            },
          )
          .timeout(timeout);
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      if (data is String) return jsonDecode(data) as Map<String, dynamic>;
      throw const ApiException(ApiErrorKind.server, 'Unexpected response.');
    } on FunctionException catch (e) {
      throw _mapFunctionError(e);
    } on TimeoutException {
      throw const ApiException(
        ApiErrorKind.offline,
        'This is taking too long. Check your connection and try again.',
      );
    } on SocketException {
      throw const ApiException(
        ApiErrorKind.offline,
        'You\'re offline. Connect to the internet and try again.',
      );
    } on ClientException {
      throw const ApiException(
        ApiErrorKind.offline,
        'Network error. Please try again.',
      );
    }
  }

  /// Sends a new App Attest key's attestation to the server (iPhone, once
  /// per install).
  Future<AttestRegistration> _registerAppAttest(
    String keyId,
    String attestation,
    int timestampMs,
  ) async {
    try {
      await _client.functions
          .invoke(
            'app-attest',
            body: {
              'key_id': keyId,
              'attestation': attestation,
              'ts': timestampMs,
            },
          )
          .timeout(const Duration(seconds: 20));
      return AttestRegistration.accepted;
    } on FunctionException catch (e) {
      debugPrint('App Attest registration: ${e.status} ${e.details}');
      // 400/403: the server looked at the attestation and refused it.
      // 503: not set up yet; anything else: try again next time.
      return e.status == 400 || e.status == 403
          ? AttestRegistration.rejected
          : AttestRegistration.unavailable;
    } catch (e) {
      debugPrint('App Attest registration failed: $e');
      return AttestRegistration.unavailable;
    }
  }

  ApiException _mapFunctionError(FunctionException e) {
    final details = e.details;
    String? message;
    String? code;
    if (details is Map) {
      message = details['message'] as String?;
      code = details['error'] as String?;
    }
    return switch ((e.status, code)) {
      (402, _) || (_, 'premium_required') => ApiException(
        ApiErrorKind.premiumRequired,
        message ?? 'This is a Premium feature.',
      ),
      (429, _) || (_, 'quota_exceeded') => ApiException(
        ApiErrorKind.quotaExceeded,
        message ?? 'You\'ve reached today\'s limit. Try again tomorrow.',
      ),
      (422, _) || (_, 'bad_image') => ApiException(
        ApiErrorKind.badImage,
        message ?? 'We couldn\'t analyse that photo. Try a clearer one.',
      ),
      (403, _) || (_, 'integrity') => ApiException(
        ApiErrorKind.untrusted,
        message ?? 'Please install ClearSkin from ${AppStore.name}.',
      ),
      _ => ApiException(
        ApiErrorKind.server,
        message ?? 'Something went wrong on our side. Please try again.',
      ),
    };
  }

  // ── Demo data (debug builds without a backend only) ─────────────────
  Future<SkinAnalysis> _demoAnalysis(SkinAnalysis? previous) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final rnd = math.Random();
    int jitter(int base) =>
        (base + rnd.nextInt(9) - 3 + (previous == null ? 0 : 3)).clamp(0, 100);
    final metrics = <MetricScore>[
      MetricScore(
        metric: SkinMetric.acne,
        score: jitter(58),
        note: 'A few active blemishes on the chin and jawline.',
      ),
      MetricScore(
        metric: SkinMetric.texture,
        score: jitter(66),
        note: 'Mild unevenness on the cheeks.',
      ),
      MetricScore(
        metric: SkinMetric.pores,
        score: jitter(61),
        note: 'Pores more visible on the nose and inner cheeks.',
      ),
      MetricScore(
        metric: SkinMetric.redness,
        score: jitter(72),
        note: 'Slight redness around the nose.',
      ),
      MetricScore(
        metric: SkinMetric.pigmentation,
        score: jitter(63),
        note: 'Some post-blemish marks on the cheeks.',
      ),
      MetricScore(
        metric: SkinMetric.hydration,
        score: jitter(70),
        note: 'Looks reasonably hydrated.',
      ),
      MetricScore(
        metric: SkinMetric.oilBalance,
        score: jitter(55),
        note: 'Shine across the T-zone.',
      ),
      MetricScore(
        metric: SkinMetric.fineLines,
        score: jitter(86),
        note: 'Very few visible lines.',
      ),
      MetricScore(
        metric: SkinMetric.underEyes,
        score: jitter(68),
        note: 'Mild shadowing under the eyes.',
      ),
    ];
    final overall =
        (metrics.map((m) => m.score).reduce((a, b) => a + b) / metrics.length)
            .round();
    return SkinAnalysis(
      usable: true,
      qualityIssues: const [],
      overallScore: overall,
      metrics: metrics,
      skinTypeEstimate: 'combination',
      summary: 'Your skin looks healthy overall with a well-hydrated barrier. The main things to focus on are a few breakouts along the jawline and lingering marks from past spots — both respond well to consistent care.',
      strengths: const [
        'Good hydration',
        'Very few fine lines',
        'Even texture on the forehead',
      ],
      priorities: const [
        'Calm active breakouts on the chin and jaw',
        'Fade post-blemish marks',
        'Balance T-zone oil',
      ],
      findings: const [
        Finding(
          title: 'Inflamed blemishes',
          detail: '3–4 small red papules along the jawline.',
          area: 'jaw',
          severity: 2,
        ),
        Finding(
          title: 'Post-blemish marks',
          detail: 'Flat brown marks where spots have healed.',
          area: 'cheeks',
          severity: 2,
        ),
        Finding(
          title: 'Visible pores',
          detail: 'Enlarged-looking pores on the nose.',
          area: 'nose',
          severity: 1,
        ),
      ],
      recommendedIngredients: const [
        IngredientTip(
          name: 'Adapalene',
          why: 'Prevents new breakouts and helps fade marks over time.',
        ),
        IngredientTip(
          name: 'Niacinamide',
          why: 'Balances oil and softens redness.',
        ),
        IngredientTip(
          name: 'Azelaic acid',
          why: 'Targets both blemishes and dark marks gently.',
        ),
      ],
      ingredientsToAvoid: const [
        IngredientTip(
          name: 'Coconut oil',
          why: 'Highly pore-clogging for breakout-prone skin.',
        ),
      ],
      redFlags: const [],
      model: 'demo',
    );
  }
}
