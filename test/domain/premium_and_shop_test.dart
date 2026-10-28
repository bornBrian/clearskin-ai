import 'package:clearskin_ai/data/models/product.dart';
import 'package:clearskin_ai/domain/premium/renewal.dart';
import 'package:clearskin_ai/domain/shop/shop_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 3, 15, 30);

  SubscriptionInfo sub({
    bool active = true,
    required DateTime expires,
    bool willRenew = false,
    bool billingIssue = false,
  }) => SubscriptionInfo(
    active: active,
    expiresAt: expires,
    willRenew: willRenew,
    billingIssue: billingIssue,
  );

  group('RenewalPlanner', () {
    test('auto-renewing Premium needs no reminder', () {
      final p = RenewalPlanner.plan(
        sub(expires: now.add(const Duration(days: 3)), willRenew: true),
        const RenewalPrefs(),
        now,
      );
      expect(p.banner, isNull);
      expect(p.reminders, isEmpty);
    });

    test('cancelled: reminds a week before, the day before, and at the end', () {
      final expiry = DateTime(2026, 11, 30, 9);
      final p = RenewalPlanner.plan(
        sub(expires: expiry),
        const RenewalPrefs(),
        now,
      );
      expect(p.banner, isNull, reason: 'more than a week left');
      expect(p.reminders.map((r) => r.at), [
        DateTime(2026, 11, 23, 10),
        DateTime(2026, 11, 29, 10),
        expiry.add(const Duration(minutes: 5)),
      ]);
      expect(p.reminders.first.title, 'Your Premium ends in 7 days');
      expect(p.reminders[1].title, 'Your Premium ends tomorrow');
    });

    test('inside the last week: banner shows and past reminders are dropped', () {
      final expiry = now.add(const Duration(days: 4));
      final p = RenewalPlanner.plan(
        sub(expires: expiry),
        const RenewalPrefs(),
        now,
      );
      expect(p.banner, RenewalBanner.endingSoon);
      expect(p.daysLeft, 4);
      expect(p.reminders.every((r) => r.at.isAfter(now)), isTrue);
      expect(p.reminders, hasLength(2), reason: 'day-before + ended');
    });

    test('"remind me later" snoozes the banner and replaces the schedule', () {
      final expiry = now.add(const Duration(days: 4));
      final later = now.add(const Duration(days: 2));
      final prefs = const RenewalPrefs().snoozeUntil(later, expiry);
      final p = RenewalPlanner.plan(sub(expires: expiry), prefs, now);
      expect(p.banner, isNull);
      expect(p.reminders.first.at, later);
      expect(p.reminders.first.title, 'Your Premium ends in 2 days');

      // Once the snooze time passes, the banner is back.
      final after = RenewalPlanner.plan(
        sub(expires: expiry),
        prefs,
        later.add(const Duration(minutes: 1)),
      );
      expect(after.banner, RenewalBanner.endingSoon);
    });

    test('a snooze picked for an old period is ignored after renewing', () {
      final oldExpiry = now.subtract(const Duration(days: 20));
      final prefs = const RenewalPrefs().snoozeUntil(
        now.add(const Duration(days: 1)),
        oldExpiry,
      );
      final p = RenewalPlanner.plan(
        sub(expires: now.add(const Duration(days: 3))),
        prefs,
        now,
      );
      expect(p.banner, RenewalBanner.endingSoon);
    });

    test('"don\'t remind me again" silences everything', () {
      final p = RenewalPlanner.plan(
        sub(expires: now.add(const Duration(days: 2))),
        const RenewalPrefs(mode: RenewalReminderMode.off),
        now,
      );
      expect(p.banner, isNull);
      expect(p.reminders, isEmpty);
    });

    test('after it ends: renew banner for two weeks, then quiet', () {
      final ended = sub(
        active: false,
        expires: now.subtract(const Duration(days: 3)),
      );
      expect(
        RenewalPlanner.plan(ended, const RenewalPrefs(), now).banner,
        RenewalBanner.ended,
      );
      final longAgo = sub(
        active: false,
        expires: now.subtract(const Duration(days: 30)),
      );
      expect(
        RenewalPlanner.plan(longAgo, const RenewalPrefs(), now).banner,
        isNull,
      );
    });

    test('payment problem shows its own banner even when set to renew', () {
      final p = RenewalPlanner.plan(
        sub(
          expires: now.add(const Duration(days: 3)),
          willRenew: true,
          billingIssue: true,
        ),
        const RenewalPrefs(),
        now,
      );
      expect(p.banner, RenewalBanner.paymentIssue);
    });

    test('prefs survive a JSON round trip', () {
      final prefs = const RenewalPrefs().snoozeUntil(
        DateTime(2026, 12, 1, 18),
        DateTime(2026, 12, 4),
      );
      final back = RenewalPrefs.fromJson(prefs.toJson());
      expect(back.mode, RenewalReminderMode.custom);
      expect(back.customAt, DateTime(2026, 12, 1, 18));
      expect(back.forExpiry, DateTime(2026, 12, 4));
      expect(RenewalPrefs.fromJson(null).mode, RenewalReminderMode.auto);
    });
  });

  group('Shop links', () {
    final config = ShopConfig.fromJson({
      'default': {
        'store': 'Amazon',
        'url': 'https://www.amazon.com/s?k={q}&tag=cs-20',
      },
      'gb': {
        'store': 'Amazon UK',
        'url': 'https://www.amazon.co.uk/s?k={q}&tag=cs-21',
      },
      'XX': {'store': 'Evil', 'url': 'http://evil.example/{q}'},
    });

    test('picks the region, falls back to default, refuses non-https', () {
      expect(config.storeFor('GB')!.name, 'Amazon UK');
      expect(config.storeFor('tz')!.name, 'Amazon');
      expect(config.storeFor(null)!.name, 'Amazon');
      expect(config.storeFor('XX')!.name, 'Amazon');
    });

    test('encodes the query and keeps the affiliate tag', () {
      final uri = config.storeFor('GB')!.search('niacinamide serum')!;
      expect(uri.host, 'www.amazon.co.uk');
      expect(uri.queryParameters['k'], 'niacinamide serum');
      expect(uri.queryParameters['tag'], 'cs-21');
    });

    test('queries are sharpened by the key ingredient', () {
      expect(
        ShopQuery.forStep(ProductCategory.serum, ['Niacinamide']),
        'niacinamide serum',
      );
      expect(
        ShopQuery.forStep(ProductCategory.sunscreen, []),
        'sunscreen spf 50',
      );
      expect(ShopQuery.forType('spot_treatment'), 'spot treatment');
    });

    test('garbage config means no links', () {
      expect(ShopConfig.fromJson('nope').isEmpty, isTrue);
      expect(ShopConfig.fromJson(null).storeFor('US'), isNull);
    });
  });
}
