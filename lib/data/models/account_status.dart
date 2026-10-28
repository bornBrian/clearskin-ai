import '../../domain/shop/shop_links.dart';

/// The server's view of this account: plan, scan allowance and shop links.
/// Fetched from the account-status function; the app never computes its own
/// quota from local data when this is available.
class AccountStatus {
  const AccountStatus({
    required this.premium,
    required this.scansUsed,
    required this.scanLimit,
    required this.windowDays,
    required this.credits,
    required this.rewardedLeftToday,
    required this.shop,
    this.resetsAt,
  });

  final bool premium;
  final int scansUsed;
  final int scanLimit;
  final int windowDays;

  /// When the oldest counted scan leaves the window and frees a scan.
  final DateTime? resetsAt;

  /// Earned by watching rewarded videos, not yet spent.
  final int credits;
  final int rewardedLeftToday;
  final ShopConfig shop;

  int get freeScansLeft => (scanLimit - scansUsed).clamp(0, scanLimit);

  /// Whether a free user can start a scan right now.
  bool get canScan => premium || freeScansLeft > 0 || credits > 0;

  factory AccountStatus.fromJson(Map<String, dynamic> j) {
    final scans = (j['scans'] as Map?)?.cast<String, dynamic>() ?? const {};
    int n(Object? v, int fallback) => (v as num?)?.toInt() ?? fallback;
    return AccountStatus(
      premium: j['premium'] == true,
      scansUsed: n(scans['used'], 0),
      scanLimit: n(scans['limit'], 2),
      windowDays: n(scans['window_days'], 30),
      resetsAt: DateTime.tryParse(scans['resets_at'] as String? ?? '')
          ?.toLocal(),
      credits: n(scans['credits'], 0),
      rewardedLeftToday: n(scans['rewarded_left_today'], 0),
      shop: ShopConfig.fromJson(j['shop']),
    );
  }

  Map<String, Object?> toJson() => {
    'premium': premium,
    'scans': {
      'used': scansUsed,
      'limit': scanLimit,
      'window_days': windowDays,
      'resets_at': resetsAt?.toUtc().toIso8601String(),
      'credits': credits,
      'rewarded_left_today': rewardedLeftToday,
    },
    'shop': shop.toJson(),
  };
}
