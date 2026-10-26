import 'package:flutter/foundation.dart';

/// Build-time configuration, injected with:
///   flutter run --dart-define-from-file=env/dev.json
///   flutter build appbundle --dart-define-from-file=env/prod.json
///
/// Only *publishable* values belong here. Secrets (Anthropic key, RevenueCat
/// secret key, Supabase service-role key) live exclusively in the Supabase
/// Edge Function environment and never ship inside the app binary.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// Google Sign-In. The *web* client id is what Supabase verifies ID tokens
  /// against (Android uses it as serverClientId); iOS also needs its own
  /// iOS client id. Both are public identifiers, not secrets.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  static const revenueCatAndroidKey = String.fromEnvironment('RC_ANDROID_KEY');
  static const revenueCatIosKey = String.fromEnvironment('RC_IOS_KEY');

  /// RevenueCat entitlement identifier that unlocks Premium.
  static const premiumEntitlement = String.fromEnvironment(
    'RC_ENTITLEMENT',
    defaultValue: 'premium',
  );

  static const privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_URL',
    defaultValue: 'https://bornbrian.github.io/clearskin/privacy.html',
  );
  static const termsUrl = String.fromEnvironment(
    'TERMS_URL',
    defaultValue: 'https://bornbrian.github.io/clearskin/terms.html',
  );
  static const supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'bonbrian2@gmail.com',
  );

  /// Open-Meteo is free for non-commercial use only. Once the app earns
  /// revenue, buy a commercial key and set it here (or swap providers).
  static const openMeteoApiKey = String.fromEnvironment('OPEN_METEO_KEY');

  /// PostHog project API key (publishable) for analytics + error reports.
  /// Empty = telemetry disabled.
  static const posthogKey = String.fromEnvironment('POSTHOG_KEY');
  static const posthogHost = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://eu.i.posthog.com',
  );
  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );

  static bool get hasBackend =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  static String get revenueCatKey => defaultTargetPlatform == TargetPlatform.iOS
      ? revenueCatIosKey
      : revenueCatAndroidKey;

  static bool get hasPurchases => revenueCatKey.isNotEmpty;

  /// Debug builds without a backend run in demo mode: AI calls return
  /// realistic sample data so every screen can be exercised locally.
  /// Release builds never fall back to demo data.
  static bool get demoMode => kDebugMode && !hasBackend;

  /// Sample AI results while the real backend handles everything else
  /// (sign-in, accounts, quotas) — for testing before an AI key is set.
  /// Debug builds, or a release explicitly built as a PREVIEW_BUILD for
  /// testers, whose reports are labelled as samples. Store builds always
  /// use the real AI.
  static const _aiDemo = bool.fromEnvironment('AI_DEMO');
  static const previewBuild = bool.fromEnvironment('PREVIEW_BUILD');
  static bool get aiDemo => demoMode || ((kDebugMode || previewBuild) && _aiDemo);
}
