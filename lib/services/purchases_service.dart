import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart' hide SubscriptionInfo;

import '../core/config/env.dart';
import '../domain/premium/renewal.dart';

/// A purchasable plan, flattened from RevenueCat for the paywall UI.
class Plan {
  const Plan({
    required this.package,
    required this.title,
    required this.priceString,
    required this.periodLabel,
    required this.pricePerWeek,
    this.pricePerWeekString,
    this.trialDays,
    this.prepaid = false,
  });

  final Package? package;
  final String title;
  final String priceString;
  final String periodLabel;
  final double pricePerWeek;
  final String? pricePerWeekString;
  final int? trialDays;

  /// Google Play prepaid plan: pay once for the period, no auto-renewal.
  /// Works with mobile money and carrier billing where cards are rare.
  final bool prepaid;

  bool get isAnnual => package?.packageType == PackageType.annual;
}

enum PurchaseOutcome { success, cancelled, pending, failed }

/// Why the paywall has no prices to show. Each has a different fix, so the
/// paywall says which one it is instead of a generic "check your
/// connection".
enum PlansIssue {
  /// No RevenueCat public key in this build (RC_ANDROID_KEY is empty).
  notConfigured,

  /// RevenueCat answered, but there's no current offering with packages:
  /// products aren't created/attached in Play Console or RevenueCat yet.
  noProducts,

  /// Google Play Billing isn't available (no Play Store, signed-out Play
  /// account, sideloaded build, or unsupported country).
  storeUnavailable,

  offline,
}

class PlansUnavailable implements Exception {
  const PlansUnavailable(this.issue, [this.detail]);
  final PlansIssue issue;
  final String? detail;

  @override
  String toString() =>
      'PlansUnavailable($issue${detail == null ? '' : ': $detail'})';
}

/// Wraps RevenueCat (Google Play Billing today, StoreKit when iOS ships).
///
/// RevenueCat validates every purchase token with Google on its servers,
/// so a patched app that fakes a purchase never gets a real entitlement.
/// Entitlement responses are also signature-verified on the device
/// (trusted entitlements), and the Edge Functions re-check Premium with
/// RevenueCat's REST API before any paid AI call.
class PurchasesService {
  PurchasesService();

  final _premium = StreamController<bool>.broadcast();
  final _subscription = StreamController<SubscriptionInfo?>.broadcast();
  bool _isPremium = false;
  SubscriptionInfo? _info;
  bool _configured = false;

  /// Debug-only override so Premium screens can be tested without a store.
  bool devPremium = false;

  bool get isPremium => _isPremium || (kDebugMode && devPremium);
  Stream<bool> get premiumChanges => _premium.stream;

  /// The current or most recent Premium period, or null if never Premium.
  SubscriptionInfo? get subscription => _info;
  Stream<SubscriptionInfo?> get subscriptionChanges => _subscription.stream;

  Future<void> configure({String? appUserId}) async {
    if (!Env.hasPurchases || _configured) return;
    try {
      if (kDebugMode) await Purchases.setLogLevel(LogLevel.info);
      final config = PurchasesConfiguration(Env.revenueCatKey)
        ..appUserID = appUserId
        // RevenueCat signs entitlement responses; a tampered response (MITM
        // proxy, hooked network layer) is reported as failed below.
        ..entitlementVerificationMode =
            EntitlementVerificationMode.informational;
      await Purchases.configure(config);
      _configured = true;
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
      _onCustomerInfo(await Purchases.getCustomerInfo());
    } on PlatformException catch (e) {
      debugPrint('RevenueCat configure failed: ${e.message}');
    }
  }

  /// Links the store customer to the backend user so server-side checks
  /// can find the subscription.
  Future<void> identify(String appUserId) async {
    if (!_configured) return;
    try {
      final result = await Purchases.logIn(appUserId);
      _onCustomerInfo(result.customerInfo);
    } on PlatformException catch (e) {
      debugPrint('RevenueCat logIn failed: ${e.message}');
    }
  }

  Future<void> refresh() async {
    if (!_configured) return;
    try {
      _onCustomerInfo(await Purchases.getCustomerInfo());
    } on PlatformException {
      // Keep last known state when offline.
    }
  }

  /// Plans to show on the paywall, cheapest per week first. Throws
  /// [PlansUnavailable] with the specific reason when there are none.
  Future<List<Plan>> plans() async {
    if (!Env.hasPurchases) {
      throw const PlansUnavailable(PlansIssue.notConfigured);
    }
    if (!_configured) await configure();
    if (!_configured) {
      throw const PlansUnavailable(PlansIssue.storeUnavailable);
    }
    final Offerings offerings;
    try {
      offerings = await Purchases.getOfferings();
    } on PlatformException catch (e) {
      throw PlansUnavailable(switch (PurchasesErrorHelper.getErrorCode(e)) {
        PurchasesErrorCode.networkError ||
        PurchasesErrorCode.offlineConnectionError ||
        PurchasesErrorCode.productRequestTimeout => PlansIssue.offline,
        PurchasesErrorCode.configurationError ||
        PurchasesErrorCode.invalidCredentialsError => PlansIssue.noProducts,
        _ => PlansIssue.storeUnavailable,
      }, e.message);
    }
    final current = offerings.current;
    if (current == null || current.availablePackages.isEmpty) {
      throw const PlansUnavailable(PlansIssue.noProducts);
    }
    return current.availablePackages.map(_toPlan).toList()
      ..sort((a, b) => a.pricePerWeek.compareTo(b.pricePerWeek));
  }

  Future<PurchaseOutcome> purchase(Plan plan) async {
    final pkg = plan.package;
    if (pkg == null) return PurchaseOutcome.failed;
    try {
      final result = await Purchases.purchase(PurchaseParams.package(pkg));
      _onCustomerInfo(result.customerInfo);
      return isPremium ? PurchaseOutcome.success : PurchaseOutcome.pending;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      return switch (code) {
        PurchasesErrorCode.purchaseCancelledError => PurchaseOutcome.cancelled,
        PurchasesErrorCode.paymentPendingError => PurchaseOutcome.pending,
        _ => PurchaseOutcome.failed,
      };
    }
  }

  /// Returns true when an active entitlement was restored.
  Future<bool> restore() async {
    if (!_configured) return false;
    try {
      _onCustomerInfo(await Purchases.restorePurchases());
    } on PlatformException catch (e) {
      debugPrint('Restore failed: ${e.message}');
    }
    return isPremium;
  }

  void setDevPremium(bool value) {
    devPremium = value;
    _premium.add(isPremium);
  }

  void _onCustomerInfo(CustomerInfo info) {
    // Present in `all` even after it lapses, which is what lets us say
    // "your Premium ended" instead of acting as if it never existed.
    final ent = info.entitlements.all[Env.premiumEntitlement];
    final tampered =
        info.entitlements.verification == VerificationResult.failed ||
        ent?.verification == VerificationResult.failed;
    if (tampered) debugPrint('RevenueCat entitlement signature failed');

    _isPremium = !tampered && (ent?.isActive ?? false);
    _info = ent == null || tampered
        ? null
        : SubscriptionInfo(
            active: ent.isActive,
            expiresAt: DateTime.tryParse(ent.expirationDate ?? '')?.toLocal(),
            willRenew: ent.willRenew && ent.periodType != PeriodType.prepaid,
            billingIssue: ent.billingIssueDetectedAt != null,
            isTrial: ent.periodType == PeriodType.trial,
            productId: ent.productIdentifier,
            managementUrl: info.managementURL,
          );
    _premium.add(isPremium);
    _subscription.add(_info);
  }

  Plan _toPlan(Package p) {
    final product = p.storeProduct;
    final (title, period) = switch (p.packageType) {
      PackageType.annual => ('Yearly', 'year'),
      PackageType.sixMonth => ('6 months', '6 months'),
      PackageType.threeMonth => ('3 months', '3 months'),
      PackageType.monthly => ('Monthly', 'month'),
      PackageType.weekly => ('Weekly', 'week'),
      PackageType.lifetime => ('Lifetime', 'once'),
      _ => (product.title, ''),
    };
    final weeks = switch (p.packageType) {
      PackageType.annual => 52.0,
      PackageType.sixMonth => 26.0,
      PackageType.threeMonth => 13.0,
      PackageType.twoMonth => 8.7,
      PackageType.monthly => 4.33,
      PackageType.weekly => 1.0,
      _ => 1.0,
    };
    return Plan(
      package: p,
      title: title,
      priceString: product.priceString,
      periodLabel: period,
      pricePerWeek: product.pricePerWeek ?? product.price / weeks,
      pricePerWeekString: product.pricePerWeekString,
      trialDays: _trialDays(product),
      prepaid: product.defaultOption?.isPrepaid ?? false,
    );
  }

  int? _trialDays(StoreProduct product) {
    // Google Play: free trial is a pricing phase on the subscription option.
    final free = product.defaultOption?.freePhase?.billingPeriod;
    if (free != null) return _days(free.unit, free.value);
    // App Store: introductory price of 0.
    final intro = product.introductoryPrice;
    if (intro != null && intro.price == 0) {
      return _days(intro.periodUnit, intro.periodNumberOfUnits) * intro.cycles;
    }
    return null;
  }

  int _days(PeriodUnit unit, int value) => switch (unit) {
    PeriodUnit.day => value,
    PeriodUnit.week => value * 7,
    PeriodUnit.month => value * 30,
    PeriodUnit.year => value * 365,
    _ => value,
  };

  void dispose() {
    _premium.close();
    _subscription.close();
  }
}
