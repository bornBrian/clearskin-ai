import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/account_status.dart';
import '../../services/ads_service.dart';
import '../../services/telemetry.dart';

enum OutOfScansChoice { premium, video }

/// Shown when a free user has used this month's scans: go Premium, or
/// watch one short video for one more scan.
Future<OutOfScansChoice?> showOutOfScansSheet(
  BuildContext context,
  AccountStatus? status,
) {
  return showModalBottomSheet<OutOfScansChoice>(
    context: context,
    backgroundColor: BrandColors.charcoal,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
    ),
    builder: (_) => _OutOfScans(status: status),
  );
}

class _OutOfScans extends StatelessWidget {
  const _OutOfScans({required this.status});
  final AccountStatus? status;

  @override
  Widget build(BuildContext context) {
    const cream = BrandColors.cream;
    final s = status;
    final resets = s?.resetsAt;
    final canWatch =
        (s?.rewardedLeftToday ?? 0) > 0 &&
        AdsService.unitFor(AdPlacement.rewarded) != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.xl,
          Space.gutter,
          Space.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(
              '${s?.scanLimit ?? FreeLimits.scansPerWindow} free scans a month',
              color: cream.withValues(alpha: 0.6),
            ),
            const SizedBox(height: Space.sm),
            Text(
              'You\'ve used this\nmonth\'s scans.',
              style: context.text.headlineMedium?.copyWith(
                color: cream,
                height: 1.15,
              ),
            ),
            if (resets != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                'Your next free scan opens on ${DateFormat('d MMMM').format(resets)}.',
                style: context.text.bodyMedium?.copyWith(
                  color: cream.withValues(alpha: 0.65),
                ),
              ),
            ],
            const SizedBox(height: Space.xl),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: cream,
                  foregroundColor: BrandColors.charcoal,
                ),
                onPressed: () =>
                    Navigator.pop(context, OutOfScansChoice.premium),
                child: const Text('Unlimited scans with Premium'),
              ),
            ),
            if (canWatch) ...[
              const SizedBox(height: Space.sm),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cream,
                    side: BorderSide(color: cream.withValues(alpha: 0.35)),
                  ),
                  onPressed: () =>
                      Navigator.pop(context, OutOfScansChoice.video),
                  child: const Text('Watch a short video for 1 scan'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Plays a rewarded video and waits for our server to confirm the credit
/// (Google calls it directly with a signed receipt, usually within
/// seconds). Returns true once the extra scan is really available.
Future<bool> earnScanWithVideo(WidgetRef ref, BuildContext context) async {
  final api = ref.read(backendApiProvider);
  final uid = await api.ensureSession();
  if (uid == null) {
    if (context.mounted) {
      showSnack(context, 'Connect to the internet to watch a video.');
    }
    return false;
  }
  final before = ref.read(accountStatusProvider).value?.credits ?? 0;
  final earned = await ref.read(adsServiceProvider).showRewarded(userId: uid);
  ref.read(telemetryProvider).track(Ev.rewardedResult, {'earned': earned});
  if (!earned) {
    if (context.mounted) {
      showSnack(context, 'Watch to the end to unlock your extra scan.');
    }
    return false;
  }
  for (var i = 0; i < 8; i++) {
    final status = await ref.read(accountStatusProvider.notifier).refresh();
    if ((status?.credits ?? 0) > before) return true;
    await Future<void>.delayed(const Duration(milliseconds: 1500));
  }
  if (context.mounted) {
    showSnack(context, 'Your extra scan is on its way. Try again in a minute.');
  }
  return false;
}
