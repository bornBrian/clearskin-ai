import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/scan.dart';
import '../../domain/scan/skin_measure.dart';
import '../scan/skin_lens.dart';

/// Day one against the latest scan, measured from the photos themselves.
/// Older scans are measured once in the background and the numbers kept.
final progressProofProvider = FutureProvider<ProgressProof?>((ref) async {
  final scans = ref
      .watch(usableScansProvider)
      .where((s) => s.face?.hasLandmarks ?? false)
      .toList();
  if (scans.length < 2) return null;
  final latest = scans.first, first = scans.last;

  Future<SkinMeasure?> measureOf(SkinScan s) async {
    if (s.measure != null) return s.measure;
    if (!File(s.photoPath).existsSync()) return null;
    final m = await SkinLensStore.measure(s.photoPath, s.face!);
    if (m != null) {
      unawaited(ref.read(scansProvider.notifier).saveMeasure(s.id, m));
    }
    return m;
  }

  final before = await measureOf(first);
  final after = await measureOf(latest);
  if (before == null || after == null) return null;
  return ProgressProof.compare(
    before,
    after,
    days: latest.createdAt.difference(first.createdAt).inDays,
  );
});

/// "Measured since day 1": the change in red, marked, shiny and rough skin
/// area, with where it changed most. Real numbers from real pixels.
class ProgressProofSection extends ConsumerWidget {
  const ProgressProofSection({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proof = ref.watch(progressProofProvider).value;
    if (proof == null) return const SizedBox.shrink();
    final c = context.colors;
    final rows = proof.changes.take(4).toList();
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('Measured since day 1 · ${proof.days} days'),
          const SizedBox(height: Space.sm),
          for (final (i, ch) in rows.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: Space.sm + 2),
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: c.line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ProgressProof.noun(ch.lens),
                          style: context.text.titleSmall,
                        ),
                        if (ch.zone != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${ch.improved ? 'Clearest' : 'Most'} change on ${ProgressProof.zoneName(ch.zone!)}',
                            style: context.text.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    '${ch.improved ? '−' : '+'}${(ch.change.abs() * 100).round()}%',
                    style: context.text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w300,
                      color: ch.improved ? c.ink : c.warn,
                    ),
                  ),
                ],
              ),
            ),
          if (proof.lightingDiffers) ...[
            const SizedBox(height: Space.xs),
            Text(
              'Your first photo was taken in different light, so part of this change may be the light. Scan in the same spot to compare like with like.',
              style: context.text.bodySmall?.copyWith(color: c.warn),
            ),
          ],
        ],
      ),
    );
  }
}
