import 'package:flutter/foundation.dart';

/// The store ClearSkin is installed from, for wording and links: Google
/// Play on Android, the App Store on iPhone. Subscriptions are cancelled and
/// payments fixed there, never inside the app.
abstract final class AppStore {
  static bool get isApple => defaultTargetPlatform == TargetPlatform.iOS;

  /// "Google Play" / "the App Store", mid-sentence.
  static String get name => isApple ? 'the App Store' : 'Google Play';

  /// Where subscriptions are managed, mid-sentence: "cancel anytime …".
  static String get manageIn =>
      isApple ? 'in your Apple account settings' : 'in Google Play';

  /// Menu path for subscriptions.
  static String get subscriptionsPath => isApple
      ? 'Settings → your name → Subscriptions'
      : 'Google Play → Subscriptions';

  static String get billingUnavailable => isApple
      ? 'App Store purchases aren\'t available. Check you\'re signed in to the App Store and in-app purchases are allowed in Screen Time.'
      : 'Google Play billing isn\'t available. Make sure the Play Store is installed, up to date and signed in.';

  /// The store's page for this app's subscription. [managementUrl] is the
  /// one RevenueCat reports, when there is one; [productId] picks the plan
  /// on Google Play ("premium_monthly:monthly" is sub:base plan).
  static Uri subscriptionsUri({String? managementUrl, String? productId}) {
    if (managementUrl != null && managementUrl.startsWith('https://')) {
      return Uri.parse(managementUrl);
    }
    if (isApple) return Uri.https('apps.apple.com', '/account/subscriptions');
    final sku = productId?.split(':').first;
    return Uri.https('play.google.com', '/store/account/subscriptions', {
      'package': 'com.clearskinai.app',
      'sku': ?sku,
    });
  }
}
