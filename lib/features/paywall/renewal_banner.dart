import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/premium/renewal.dart';
import '../../services/telemetry.dart';

/// Google Play's page for this app's subscription, where people resubscribe
/// after cancelling or fix a failed payment. Apps can't do either in-app.
Uri playSubscriptionsUri(SubscriptionInfo? sub) {
  final managed = sub?.managementUrl;
  if (managed != null && managed.startsWith('https://')) {
    return Uri.parse(managed);
  }
  // Google product ids look like "premium_monthly:monthly" (sub:base plan).
  final sku = sub?.productId?.split(':').first;
  return Uri.https('play.google.com', '/store/account/subscriptions', {
    'package': 'com.clearskinai.app',
    'sku': ?sku,
  });
}

/// Premium is ending, has ended, or a payment failed: say so plainly, with
/// one clear action and the person's choice of when (or whether) to hear
/// about it again.
class RenewalBannerCard extends ConsumerWidget {
  const RenewalBannerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(renewalPlanProvider);
    final sub = ref.watch(subscriptionProvider);
    final banner = plan.banner;
    if (banner == null) return const SizedBox.shrink();

    const cream = BrandColors.cream;
    final dim = cream.withValues(alpha: 0.65);
    final days = plan.daysLeft ?? 0;
    final (title, body, action) = switch (banner) {
      RenewalBanner.endingSoon => (
        days <= 0
            ? 'Your Premium ends today'
            : days == 1
            ? 'Your Premium ends tomorrow'
            : 'Your Premium ends in $days days',
        'Renew to keep unlimited scans, your coach and an ad-free app.',
        'Renew',
      ),
      RenewalBanner.ended => (
        'Your Premium has ended',
        'Your scans and progress are all still here. Renew to pick up where you left off.',
        'Renew Premium',
      ),
      RenewalBanner.paymentIssue => (
        'Payment didn\'t go through',
        'Update your payment method in Google Play to keep Premium.',
        'Fix payment',
      ),
    };

    Future<void> renew() async {
      ref.read(telemetryProvider).track(Ev.renewalAction, {
        'action': 'renew',
        'banner': banner.name,
      });
      // A cancelled auto-renewing plan, or a failed payment, is fixed in
      // Google Play; prepaid top-ups and lapsed plans go through the paywall.
      final viaPlay =
          banner == RenewalBanner.paymentIssue ||
          (banner == RenewalBanner.endingSoon &&
              !(sub?.isTrial ?? false) &&
              !_looksPrepaid(sub));
      if (viaPlay) {
        await launchUrl(
          playSubscriptionsUri(sub),
          mode: LaunchMode.externalApplication,
        );
      } else if (context.mounted) {
        await context.push('/paywall?source=renewal');
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: Space.lg),
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
        Space.lg,
        Space.sm,
      ),
      decoration: BoxDecoration(
        color: BrandColors.charcoal,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('ClearSkin Premium', color: dim),
          const SizedBox(height: Space.xs),
          Text(title, style: context.text.titleLarge?.copyWith(color: cream)),
          const SizedBox(height: 4),
          Text(body, style: context.text.bodyMedium?.copyWith(color: dim)),
          const SizedBox(height: Space.md),
          // Wraps onto two lines on narrow phones with large text.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.sm,
              runSpacing: Space.xs,
              children: [
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: cream,
                    foregroundColor: BrandColors.charcoal,
                    // The theme's buttons are full-width; this one sits in a row.
                    minimumSize: const Size(0, 46),
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  ),
                  onPressed: renew,
                  child: Text(action),
                ),
                if (banner != RenewalBanner.paymentIssue)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: dim),
                    onPressed: () => showRenewalReminderOptions(context, ref),
                    child: const Text('Remind me'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static bool _looksPrepaid(SubscriptionInfo? sub) =>
      sub != null && !sub.willRenew && sub.managementUrl == null;
}

/// "Remind me later" on a date and time they pick, or "don't remind me
/// again". Both can be changed in Settings.
Future<void> showRenewalReminderOptions(
  BuildContext context,
  WidgetRef ref,
) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Remind me on a date I choose'),
            onTap: () => Navigator.pop(ctx, 'pick'),
          ),
          ListTile(
            title: const Text('Tomorrow at this time'),
            onTap: () => Navigator.pop(ctx, 'tomorrow'),
          ),
          ListTile(
            title: const Text('Don\'t remind me again'),
            subtitle: const Text('You can turn reminders back on in Settings.'),
            onTap: () => Navigator.pop(ctx, 'off'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final notifier = ref.read(renewalPrefsProvider.notifier);
  ref.read(telemetryProvider).track(Ev.renewalAction, {'action': choice});
  switch (choice) {
    case 'off':
      await notifier.setEnabled(false);
      if (context.mounted) showSnack(context, 'Renewal reminders are off.');
    case 'tomorrow':
      final at = DateTime.now().add(const Duration(days: 1));
      await notifier.remindAt(at);
      if (context.mounted) {
        showSnack(context, 'We\'ll remind you tomorrow at ${_time(at)}.');
      }
    case 'pick':
      final now = DateTime.now();
      final date = await showDatePicker(
        context: context,
        initialDate: now.add(const Duration(days: 1)),
        firstDate: now,
        lastDate: now.add(const Duration(days: 60)),
        helpText: 'Remind me on',
      );
      if (date == null || !context.mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 10, minute: 0),
        helpText: 'At',
      );
      if (time == null || !context.mounted) return;
      var at = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (!at.isAfter(now)) at = now.add(const Duration(minutes: 5));
      await notifier.remindAt(at);
      if (context.mounted) {
        showSnack(
          context,
          'We\'ll remind you on ${DateFormat('d MMM').format(at)} at ${_time(at)}.',
        );
      }
  }
}

String _time(DateTime t) => DateFormat.jm().format(t);
