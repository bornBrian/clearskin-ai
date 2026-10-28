import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/config/env.dart';
import '../data/repositories/repositories.dart';

enum AdPlacement { banner, interstitial, rewarded }

/// AdMob for free users. Premium users never load the SDK's ads at all.
///
/// Rules this follows:
///  - Google's consent form (UMP) runs first; no ad is requested until
///    `canRequestAds` says so (GDPR/UK and US state privacy laws).
///  - Content is capped at teen-safe (T), and at PG with non-personalised
///    ads for 13–17s. Sensitive categories (gambling, dating, alcohol…) are
///    blocked in the AdMob console too (see docs/LAUNCH_PLAYSTORE.md).
///  - Placements are only at natural breaks: a banner on the routine list,
///    one interstitial after a routine is finished (capped), and rewarded
///    videos only when the person asks for one.
class AdsService {
  AdsService(this._kv);

  final KeyValueStore _kv;

  bool _started = false;
  bool _canRequest = false;
  bool _minor = false;
  InterstitialAd? _interstitial;
  DateTime? _lastInterstitial;

  /// No interstitials in someone's first days: let the habit form first.
  static const _graceDays = 2;
  static const _minGap = Duration(minutes: 4);
  static const _maxPerDay = 3;

  bool get canRequestAds => _canRequest;

  static bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Google's test units in debug builds; the configured units (or none)
  /// in release builds.
  static String? unitFor(AdPlacement p) {
    if (!_supported) return null;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final configured = switch (p) {
      AdPlacement.banner => ios ? Env.admobIosBannerId : Env.admobBannerId,
      AdPlacement.interstitial =>
        ios ? Env.admobIosInterstitialId : Env.admobInterstitialId,
      AdPlacement.rewarded =>
        ios ? Env.admobIosRewardedId : Env.admobRewardedId,
    };
    if (configured.isNotEmpty) return configured;
    if (!kDebugMode) return null;
    return switch ((p, ios)) {
      (AdPlacement.banner, false) => 'ca-app-pub-3940256099942544/9214589741',
      (AdPlacement.interstitial, false) =>
        'ca-app-pub-3940256099942544/1033173712',
      (AdPlacement.rewarded, false) => 'ca-app-pub-3940256099942544/5224354917',
      (AdPlacement.banner, true) => 'ca-app-pub-3940256099942544/2435281174',
      (AdPlacement.interstitial, true) =>
        'ca-app-pub-3940256099942544/4411468910',
      (AdPlacement.rewarded, true) => 'ca-app-pub-3940256099942544/1712485313',
    };
  }

  AdRequest get request => AdRequest(nonPersonalizedAds: _minor);

  /// Gathers consent and starts the SDK. Call once for free users, after
  /// onboarding (never before the person has seen the app).
  Future<void> start({required bool minor}) async {
    if (_started || !_supported) return;
    _started = true;
    _minor = minor;
    try {
      final consent = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(tagForUnderAgeOfConsent: minor),
        () async {
          await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
          consent.complete();
        },
        (_) => consent.complete(),
      );
      await consent.future;
      _canRequest = await ConsentInformation.instance.canRequestAds();
      if (!_canRequest) return;

      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          maxAdContentRating: minor
              ? MaxAdContentRating.pg
              : MaxAdContentRating.t,
          ageRestrictedTreatment: minor
              ? AgeRestrictedTreatment.teen
              : AgeRestrictedTreatment.unspecified,
        ),
      );
      await MobileAds.instance.initialize();
      _loadInterstitial();
    } catch (e) {
      debugPrint('Ads start failed: $e');
    }
  }

  /// Whether the privacy-options entry point must be shown in Settings
  /// (required where the consent form applies).
  Future<bool> privacyOptionsRequired() async {
    if (!_started) return false;
    return await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
  }

  Future<void> showPrivacyOptions() =>
      ConsentForm.showPrivacyOptionsForm((_) async {
        _canRequest = await ConsentInformation.instance.canRequestAds();
      });

  // ── Interstitial: after finishing a routine ──────────────────────────

  void _loadInterstitial() {
    final unit = unitFor(AdPlacement.interstitial);
    if (unit == null || !_canRequest) return;
    InterstitialAd.load(
      adUnitId: unit,
      request: request,
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (e) => debugPrint('Interstitial failed: $e'),
      ),
    );
  }

  /// Shows the routine-complete interstitial if every cap allows it.
  Future<void> maybeShowInterstitial() async {
    final ad = _interstitial;
    if (ad == null || !_canRequest) return;
    final now = clock.now();
    if (_lastInterstitial != null &&
        now.difference(_lastInterstitial!) < _minGap) {
      return;
    }
    final first = DateTime.tryParse(await _kv.get(KvKeys.firstOpen) ?? '');
    if (first == null) {
      await _kv.set(KvKeys.firstOpen, now.toIso8601String());
      return;
    }
    if (now.difference(first).inDays < _graceDays) return;

    final today = '${now.year}-${now.month}-${now.day}';
    final log = await _kv.getJson(KvKeys.interstitialLog);
    final shown = log?['day'] == today ? (log!['n'] as num).toInt() : 0;
    if (shown >= _maxPerDay) return;

    _interstitial = null;
    _lastInterstitial = now;
    await _kv.setJson(KvKeys.interstitialLog, {'day': today, 'n': shown + 1});
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _loadInterstitial();
      },
    );
    await ad.show();
  }

  // ── Rewarded: one extra scan ─────────────────────────────────────────

  /// Loads and shows a rewarded video. Resolves true once the person has
  /// watched enough to earn the reward. The scan credit itself is granted
  /// by our server when Google's signed callback arrives, keyed to
  /// [userId]; the app only waits for it.
  Future<bool> showRewarded({required String userId}) async {
    final unit = unitFor(AdPlacement.rewarded);
    if (unit == null) return false;
    if (!_started) await start(minor: _minor);
    if (!_canRequest) return false;

    final loaded = Completer<RewardedAd?>();
    await RewardedAd.load(
      adUnitId: unit,
      request: request,
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: loaded.complete,
        onAdFailedToLoad: (e) {
          debugPrint('Rewarded failed: $e');
          loaded.complete(null);
        },
      ),
    );
    final ad = await loaded.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => null,
    );
    if (ad == null) return false;

    await ad.setServerSideOptions(
      ServerSideVerificationOptions(userId: userId),
    );
    final done = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!done.isCompleted) done.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        if (!done.isCompleted) done.complete(false);
      },
    );
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    return done.future;
  }
}
