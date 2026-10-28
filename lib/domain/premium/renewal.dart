/// What the store says about the current Premium period. Built from
/// RevenueCat's CustomerInfo (see PurchasesService).
class SubscriptionInfo {
  const SubscriptionInfo({
    required this.active,
    required this.expiresAt,
    required this.willRenew,
    this.billingIssue = false,
    this.isTrial = false,
    this.productId,
    this.managementUrl,
  });

  final bool active;

  /// Null for a lifetime purchase.
  final DateTime? expiresAt;

  /// False once the person cancels, and always false for prepaid plans:
  /// those end unless they top up, which is exactly when a reminder helps.
  final bool willRenew;

  /// Google couldn't charge the renewal; Premium continues through the
  /// grace period while they fix their payment method.
  final bool billingIssue;
  final bool isTrial;
  final String? productId;
  final String? managementUrl;
}

enum RenewalReminderMode {
  /// A week before Premium ends, then the day before.
  auto,

  /// At a date and time the person picked ("remind me later").
  custom,

  /// "Don't remind me again". Can be turned back on in Settings.
  off,
}

/// The person's reminder choice, stored on the device.
class RenewalPrefs {
  const RenewalPrefs({
    this.mode = RenewalReminderMode.auto,
    this.customAt,
    this.forExpiry,
  });

  final RenewalReminderMode mode;
  final DateTime? customAt;

  /// The expiry the custom time was picked for. When a new period starts
  /// (they renewed), a stale custom time falls back to [RenewalReminderMode.auto].
  final DateTime? forExpiry;

  RenewalPrefs snoozeUntil(DateTime at, DateTime? expiry) => RenewalPrefs(
    mode: RenewalReminderMode.custom,
    customAt: at,
    forExpiry: expiry,
  );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'custom_at': customAt?.toIso8601String(),
    'for_expiry': forExpiry?.toIso8601String(),
  };

  factory RenewalPrefs.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const RenewalPrefs();
    return RenewalPrefs(
      mode:
          RenewalReminderMode.values.asNameMap()[j['mode']] ??
          RenewalReminderMode.auto,
      customAt: DateTime.tryParse(j['custom_at'] as String? ?? ''),
      forExpiry: DateTime.tryParse(j['for_expiry'] as String? ?? ''),
    );
  }
}

enum RenewalBanner { endingSoon, ended, paymentIssue }

class RenewalReminder {
  const RenewalReminder(this.at, this.title, this.body);
  final DateTime at;
  final String title;
  final String body;
}

class RenewalPlan {
  const RenewalPlan({this.banner, this.daysLeft, this.reminders = const []});

  static const none = RenewalPlan();

  final RenewalBanner? banner;

  /// Whole days until Premium ends (0 = ends today). Null when not ending.
  final int? daysLeft;

  /// Local notifications to (re)schedule. Always a complete set: callers
  /// cancel the previous plan's reminders first.
  final List<RenewalReminder> reminders;
}

/// Decides when to remind someone that Premium is ending, from the store's
/// facts and their reminder choice. Pure, so it's fully unit-tested.
abstract final class RenewalPlanner {
  /// How long before the end the first reminder and the banner appear.
  static const leadTime = Duration(days: 7);

  /// How long after Premium ends the "renew" banner stays on Today.
  static const lapsedFor = Duration(days: 14);

  static const _remindHour = 10;

  static RenewalPlan plan(
    SubscriptionInfo? sub,
    RenewalPrefs prefs,
    DateTime now,
  ) {
    final expiry = sub?.expiresAt;
    if (sub == null || expiry == null) return RenewalPlan.none;

    if (sub.active && sub.billingIssue) {
      // Google emails about failed payments; the in-app nudge is enough.
      return const RenewalPlan(banner: RenewalBanner.paymentIssue);
    }
    // Auto-renewing: nothing to do, Google renews it.
    if (sub.active && sub.willRenew) return RenewalPlan.none;

    if (prefs.mode == RenewalReminderMode.off) return RenewalPlan.none;

    final custom =
        prefs.mode == RenewalReminderMode.custom &&
            prefs.customAt != null &&
            prefs.forExpiry == expiry
        ? prefs.customAt
        : null;
    final snoozed = custom != null && custom.isAfter(now);

    if (sub.active) {
      final left = expiry.difference(now);
      final daysLeft = _wholeDays(now, expiry);
      final reminders = <RenewalReminder>[
        if (custom != null)
          _reminder(custom, expiry, now)
        else ...[
          for (final before in const [Duration(days: 7), Duration(days: 1)])
            _reminder(_at10(expiry.subtract(before)), expiry, now),
        ],
        // When it ends, say so plainly, once.
        RenewalReminder(
          expiry.add(const Duration(minutes: 5)),
          'Your Premium has ended',
          'Renew to keep unlimited scans, your coach and an ad-free app.',
        ),
      ].where((r) => r.at.isAfter(now)).toList();
      return RenewalPlan(
        banner: left <= leadTime && !snoozed ? RenewalBanner.endingSoon : null,
        daysLeft: daysLeft,
        reminders: reminders,
      );
    }

    // Ended. Offer to renew for a while, then go quiet.
    if (now.difference(expiry) > lapsedFor) return RenewalPlan.none;
    return RenewalPlan(
      banner: snoozed ? null : RenewalBanner.ended,
      reminders: [
        if (snoozed)
          RenewalReminder(
            custom,
            'Renew ClearSkin Premium',
            'You asked us to remind you. Pick up where you left off.',
          ),
      ],
    );
  }

  static RenewalReminder _reminder(DateTime at, DateTime expiry, DateTime now) {
    final days = _wholeDays(at, expiry);
    return RenewalReminder(
      at,
      days <= 0
          ? 'Your Premium ends today'
          : days == 1
          ? 'Your Premium ends tomorrow'
          : 'Your Premium ends in $days days',
      'Renew now to keep unlimited scans, your coach and an ad-free app.',
    );
  }

  static DateTime _at10(DateTime d) =>
      DateTime(d.year, d.month, d.day, _remindHour);

  /// Calendar days from [from] to [to], ignoring the time of day.
  static int _wholeDays(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }
}
