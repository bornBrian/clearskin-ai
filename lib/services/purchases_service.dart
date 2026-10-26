import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/config/env.dart';

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
  });

  final Package? package;
  final String title;
  final String priceString;
  final String periodLabel;
  final double pricePerWeek;
  final String? pricePerWeekString;
  final int? trialDays;

  bool get isAnnual => package?.packageType == PackageType.annual;
}

enum PurchaseOutcome { success, cancelled, pending, failed }

/// Wraps RevenueCat (Google Play Billing today, StoreKit when iOS ships).
/// RevenueCat is the source of truth for entitlements; the Edge Functions
/// re-verify with RevenueCat's REST API so Premium can't be faked client-side.
class PurchasesService {
  PurchasesService();

  final _premium = StreamController<bool>.broadcast();
  bool _isPremium = false;
  bool _configured = false;

  /// Debug-only override so Premium screens can be tested without a store.
  bool devPremium = false;

  bool get isPremium => _isPremium || (kDebugMode && devPremium);
  Stream<bool> get premiumChanges => _premium.stream;

  Future<void> configure({String? appUserId}) async {
    if (!Env.hasPurchases || _configured) return;
    try {
      if (kDebugMode) await Purchases.setLogLevel(LogLevel.info);
      final config = PurchasesConfiguration(Env.revenueCatKey)
        ..appUserID = appUserId;
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

  Future<List<Plan>> plans() async {
    if (!_configured) return const [];
    final offerings = await Purchases.getOfferings();
    final current = offerings.current;
    if (current == null) return const [];
    final plans = current.availablePackages.map(_toPlan).toList()
      ..sort((a, b) => a.pricePerWeek.compareTo(b.pricePerWeek));
    return plans;
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
    final active =
        info.entitlements.active[Env.premiumEntitlement]?.isActive ?? false;
    if (active != _isPremium) {
      _isPremium = active;
    }
    _premium.add(isPremium);
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

  void dispose() => _premium.close();
}
