import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/profile.dart';
import '../../data/models/scan.dart';
import '../../domain/guidance/potential.dart';
import '../../domain/journey/journey_engine.dart';
import '../../domain/scan/skin_maps.dart';
import '../../domain/shop/shop_links.dart';
import '../progress/progress_proof.dart';
import '../share/share_card.dart';
import '../shop/shop_link.dart';
import 'face_map.dart';

class ScanResultScreen extends ConsumerStatefulWidget {
  const ScanResultScreen({super.key, required this.scanId, this.fresh = false});
  final String scanId;

  /// True right after a scan completes (enables celebration + review prompt).
  final bool fresh;

  @override
  ConsumerState<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends ConsumerState<ScanResultScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.fresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAskReview());
    }
  }

  void _maybeAskReview() {
    final scans = ref.read(usableScansProvider);
    if (scans.length < 2) return;
    final delta =
        scans[0].analysis.overallScore - scans[1].analysis.overallScore;
    if (scans[0].id == widget.scanId && delta >= 3) {
      Future<void>.delayed(
        const Duration(seconds: 3),
        () => ref.read(reviewServiceProvider).maybePrompt(),
      );
    }
  }

  Future<void> _delete(SkinScan scan) async {
    final ok = await confirm(
      context,
      title: 'Delete this scan?',
      body: 'The photo and its results will be permanently removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      final f = File(scan.photoPath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    await ref.read(scansProvider.notifier).remove(scan.id);
    if (mounted) context.pop();
  }

  /// The first result is when the plan becomes real, so a free user sees
  /// what Premium adds once, on the way to the routine built from it.
  Future<void> _toRoutine({required bool first}) async {
    if (first && widget.fresh && !ref.read(premiumProvider)) {
      await context.push('/paywall?source=first_scan');
      if (!mounted) return;
    }
    context.go('/routine');
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(scansProvider).value ?? const <SkinScan>[];
    final scan = all.where((s) => s.id == widget.scanId).firstOrNull;
    if (scan == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Scan not found')),
      );
    }
    final a = scan.analysis;
    final usable = ref.watch(usableScansProvider);
    final idx = usable.indexWhere((s) => s.id == scan.id);
    final previous = idx >= 0 && idx + 1 < usable.length
        ? usable[idx + 1]
        : null;
    final c = context.colors;
    // People here for glow see their glow first.
    final glowFirst =
        ref.watch(journeyProvider)?.track == JourneyTrack.glow ||
        (ref.watch(profileProvider).value?.goals.contains(Goal.glow) ?? false);

    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _Hero(
              scan: scan,
              previous: previous,
              onDelete: () => _delete(scan),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.xl,
                Space.gutter,
                Space.xxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The AI disclaimer opens every report.
                  Disclaimer(text: a.disclaimer),
                  const SizedBox(height: Space.lg),
                  if (!a.usable) ...[
                    Container(
                      padding: const EdgeInsets.all(Space.md),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(color: c.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Photo quality limited this scan',
                            style: context.text.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Retake in soft daylight. It won\'t count toward trends.',
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.lg),
                  ],
                  if (a.redFlags.isNotEmpty) ...[
                    _RedFlags(flags: a.redFlags),
                    const SizedBox(height: Space.xl),
                  ],
                  if (a.priorities.isNotEmpty) ...[
                    Eyebrow(
                      a.focus == null
                          ? 'Your focus'
                          : 'Your focus · ${a.focus!.label}',
                    ),
                    if (a.focus != null) ...[
                      const SizedBox(height: 4),
                      Text(a.focus!.line, style: context.text.bodyMedium),
                    ],
                    const SizedBox(height: Space.xs),
                    for (var i = 0; i < a.priorities.length; i++)
                      _Numbered(
                        n: i + 1,
                        text: a.priorities[i],
                        last: i == a.priorities.length - 1,
                      ),
                    const SizedBox(height: Space.xl),
                  ],
                  FaceMap(
                    scan: scan,
                    initialLens: glowFirst ? SkinLens.radiance : null,
                    previousRadiance: previous?.radiance,
                    onRadiance: scan.radiance == null
                        ? (r) => ref
                              .read(scansProvider.notifier)
                              .saveRadiance(scan.id, r)
                        : null,
                    onMeasure: scan.measure == null
                        ? (m) => ref
                              .read(scansProvider.notifier)
                              .saveMeasure(scan.id, m)
                        : null,
                  ),
                  const SizedBox(height: Space.xxl),
                  const Eyebrow('Breakdown'),
                  const SizedBox(height: Space.sm),
                  _MetricGrid(metrics: a.weakest, previous: previous?.analysis),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Out of 100, higher is better. Lowest first.',
                    style: context.text.bodySmall?.copyWith(color: c.inkFaint),
                  ),
                  // Measured proof belongs on the newest report only.
                  if (scan.id == ref.watch(latestScanProvider)?.id)
                    const ProgressProofSection(
                      padding: EdgeInsets.only(top: Space.xxl),
                    ),
                  if (SkinPotential.of(a) case final p?) ...[
                    const SizedBox(height: Space.xxl),
                    _Potential(potential: p),
                  ],
                  if (a.strengths.isNotEmpty) ...[
                    const SizedBox(height: Space.xxl),
                    const Eyebrow('Going well'),
                    const SizedBox(height: Space.sm),
                    Text(
                      _sentence(a.strengths),
                      style: context.text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w300,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (a.recommendedIngredients.isNotEmpty) ...[
                    const SizedBox(height: Space.xxl),
                    const Eyebrow('Reach for'),
                    const SizedBox(height: Space.xxs),
                    for (final (i, t) in a.recommendedIngredients.indexed)
                      _IngredientLine(
                        tip: t,
                        last: i == a.recommendedIngredients.length - 1,
                      ),
                  ],
                  if (a.ingredientsToAvoid.isNotEmpty) ...[
                    const SizedBox(height: Space.xl),
                    const Eyebrow('Skip for now'),
                    const SizedBox(height: Space.xxs),
                    for (final (i, t) in a.ingredientsToAvoid.indexed)
                      _IngredientLine(
                        tip: t,
                        last: i == a.ingredientsToAvoid.length - 1,
                      ),
                  ],
                  if (a.ingredientWarnings.isNotEmpty) ...[
                    const SizedBox(height: Space.xl),
                    Eyebrow('Don\'t combine', color: c.warn),
                    const SizedBox(height: Space.xxs),
                    for (final (i, w) in a.ingredientWarnings.indexed)
                      _Numbered(
                        n: i + 1,
                        text: w,
                        last: i == a.ingredientWarnings.length - 1,
                      ),
                  ],
                  if (a.routineAdjustments.isNotEmpty) ...[
                    const SizedBox(height: Space.xxl),
                    const Eyebrow('Change in your routine'),
                    const SizedBox(height: Space.xxs),
                    for (final (i, r) in a.routineAdjustments.indexed)
                      _Numbered(
                        n: i + 1,
                        text: r,
                        last: i == a.routineAdjustments.length - 1,
                      ),
                  ],
                  if (a.recommendedProductTypes.isNotEmpty) ...[
                    const SizedBox(height: Space.xxl),
                    const Eyebrow('Worth adding'),
                    const SizedBox(height: Space.xxs),
                    for (final (i, t) in a.recommendedProductTypes.indexed)
                      _ProductType(
                        n: i + 1,
                        type: t,
                        last: i == a.recommendedProductTypes.length - 1,
                      ),
                  ],
                  if (a.beyondProducts.isNotEmpty) ...[
                    const SizedBox(height: Space.xxl),
                    const Eyebrow('Beyond products'),
                    const SizedBox(height: Space.xxs),
                    for (final (i, t) in a.beyondProducts.indexed)
                      _IngredientLine(
                        tip: t,
                        last: i == a.beyondProducts.length - 1,
                      ),
                  ],
                  const SizedBox(height: Space.xxl),
                  ArrowPill(
                    label: previous == null
                        ? 'See my routine'
                        : 'See your updated routine',
                    dark: true,
                    onTap: () => _toRoutine(first: previous == null),
                  ),
                ].animate(interval: 30.ms).fadeIn(duration: Motion.normal),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where this skin can get in 12 weeks, and which measures carry it there.
class _Potential extends StatelessWidget {
  const _Potential({required this.potential});
  final SkinPotential potential;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gains = potential.biggestGains.take(3).toList();
    final numeral = context.text.displayMedium?.copyWith(
      fontWeight: FontWeight.w200,
      height: 1,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Your potential'),
        const SizedBox(height: Space.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${potential.now}',
              style: numeral?.copyWith(color: c.inkMuted),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              child: Icon(Icons.arrow_forward_rounded, color: c.inkFaint),
            ),
            Text('${potential.potential}', style: numeral),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                '+${potential.gain} in 12 weeks',
                textAlign: TextAlign.right,
                style: context.text.titleSmall?.copyWith(color: c.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        for (final (i, g) in gains.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            decoration: BoxDecoration(
              border: i == gains.length - 1
                  ? null
                  : Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(g.metric.label, style: context.text.bodyLarge),
                ),
                Text(
                  '${g.now}  →  ${g.potential}',
                  style: context.text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: Space.xs),
        Text(
          'An estimate of what consistent care typically achieves, from your own scores. Most of the change shows by week 6.',
          style: context.text.bodySmall?.copyWith(color: c.inkFaint),
        ),
      ],
    );
  }
}

/// A product type the scan suggests, with a regional shop link when one is
/// configured, or just its name.
class _ProductType extends ConsumerWidget {
  const _ProductType({required this.n, required this.type, required this.last});
  final int n;
  final String type;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ShopQuery.forType(type);
    final hasShop =
        ref
            .watch(accountStatusProvider)
            .value
            ?.shop
            .storeFor(ShopLinkRow.region) !=
        null;
    if (!hasShop) {
      return _Numbered(
        n: n,
        text: query[0].toUpperCase() + query.substring(1),
        last: last,
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: context.colors.line)),
      ),
      child: ShopLinkRow(query: query, source: 'scan'),
    );
  }
}

/// "Good hydration, even redness and smooth forehead." from short phrases.
String _sentence(List<String> parts) {
  String lower(String s) =>
      s.length > 1 && s[1] == s[1].toLowerCase() ? s.toLowerCase() : s;
  final p = [parts.first, for (final s in parts.skip(1)) lower(s)];
  final body = p.length == 1
      ? p.first
      : '${p.sublist(0, p.length - 1).join(', ')} and ${p.last}';
  return body.endsWith('.') ? body : '$body.';
}

/// Charcoal report cover: date, the score dial under a soft pool of light,
/// one sentence, and three facts.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.scan,
    required this.previous,
    required this.onDelete,
  });

  final SkinScan scan;
  final SkinScan? previous;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    const cream = BrandColors.cream;
    final a = scan.analysis;
    final top = MediaQuery.paddingOf(context).top;
    final summary = a.summary.split(RegExp(r'(?<=\.)\s')).first;
    final delta = previous == null
        ? null
        : a.overallScore - previous!.analysis.overallScore;
    final strongest = a.weakest.lastOrNull;
    final type = a.skinTypeEstimate;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: BrandColors.charcoal,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(Radii.lg + 8),
        ),
      ),
      child: Stack(
        children: [
          // A lamp over the dial: warm, barely there.
          Positioned(
            left: 0,
            right: 0,
            top: top + 20,
            height: 360,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.62,
                  colors: [
                    cream.withValues(alpha: 0.11),
                    cream.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              Space.xs,
              top + Space.xs,
              Space.xs,
              Space.lg,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back_rounded, color: cream),
                    ),
                    Expanded(
                      child: Center(
                        child: Eyebrow(
                          DateFormat('d MMMM yyyy').format(scan.createdAt),
                          color: cream.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Share',
                      onPressed: () => unawaited(
                        showShareCardSheet(
                          context,
                          scan: scan,
                          previous: previous,
                        ),
                      ),
                      icon: const Icon(Icons.ios_share_rounded, color: cream),
                    ),
                    PopupMenuButton<String>(
                      iconColor: cream,
                      onSelected: (_) => onDelete(),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete scan'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: Space.lg),
                // Arrives from Today's dial (ScoreDial.flight).
                Hero(
                  tag: 'dial-${scan.id}',
                  flightShuttleBuilder: ScoreDial.flight,
                  child: ScoreDial(
                    score: a.overallScore,
                    size: 236,
                    color: cream,
                    trackColor: cream.withValues(alpha: 0.16),
                    textColor: cream,
                    label: 'Skin score',
                  ),
                ),
                const SizedBox(height: Space.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                  child: Text(
                    summary,
                    textAlign: TextAlign.center,
                    style: context.text.titleLarge?.copyWith(
                      color: cream.withValues(alpha: 0.88),
                      fontWeight: FontWeight.w300,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: Space.xl),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                  child: _FactStrip(
                    facts: [
                      (
                        'Since last',
                        delta == null
                            ? 'First scan'
                            : delta == 0
                            ? 'Steady'
                            : '${delta > 0 ? '+' : '−'}${delta.abs()}',
                      ),
                      if (SkinPotential.of(a) case final p?)
                        ('Potential', '${p.potential}')
                      else if (type.isNotEmpty && type != 'unknown')
                        (
                          'Skin type',
                          type[0].toUpperCase() + type.substring(1),
                        ),
                      if (scan.radiance case final r?)
                        ('Radiance', '${r.score}')
                      else if (strongest != null)
                        ('Strongest', strongest.metric.label),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Up to three label/value pairs split by cream hairlines.
class _FactStrip extends StatelessWidget {
  const _FactStrip({required this.facts});
  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    const cream = BrandColors.cream;
    final rule = cream.withValues(alpha: 0.14);
    return Container(
      padding: const EdgeInsets.only(top: Space.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: rule)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < facts.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, thickness: 1, color: rule),
              Expanded(
                child: Column(
                  children: [
                    Eyebrow(facts[i].$1, color: cream.withValues(alpha: 0.5)),
                    const SizedBox(height: 6),
                    Text(
                      facts[i].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall?.copyWith(
                        color: cream,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Numbered extends StatelessWidget {
  const _Numbered({required this.n, required this.text, required this.last});
  final int n;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              n.toString().padLeft(2, '0'),
              style: context.text.headlineSmall?.copyWith(
                color: c.inkFaint,
                fontWeight: FontWeight.w200,
              ),
            ),
          ),
          Expanded(child: Text(text, style: context.text.titleMedium)),
        ],
      ),
    );
  }
}

/// Every score as a number in a hairline grid, three across — read like a
/// specification sheet. The change since last scan sits beside it, small.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics, this.previous});
  final List<MetricScore> metrics;
  final SkinAnalysis? previous;

  static const _across = 3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = [
      for (var i = 0; i < metrics.length; i += _across)
        metrics.sublist(i, (i + _across).clamp(0, metrics.length)),
    ];
    return Column(
      children: [
        for (final (r, row) in rows.indexed)
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: c.line),
                bottom: r == rows.length - 1
                    ? BorderSide(color: c.line)
                    : BorderSide.none,
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  for (var i = 0; i < _across; i++) ...[
                    if (i > 0)
                      VerticalDivider(width: 1, thickness: 1, color: c.line),
                    Expanded(
                      child: i < row.length
                          ? _MetricCell(
                              metric: row[i],
                              before: previous?.scoreFor(row[i].metric),
                              first: i == 0,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.metric,
    required this.before,
    required this.first,
  });

  final MetricScore metric;
  final int? before;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final diff = before == null ? 0 : metric.score - before!;
    return Semantics(
      label:
          '${metric.metric.label} ${metric.score}${diff == 0 ? '' : ', ${diff > 0 ? 'up' : 'down'} ${diff.abs()}'}',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(first ? 0 : Space.md, 18, Space.xs, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              metric.metric.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium?.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: Space.xs),
            // Shrinks rather than overflows in narrow cells.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CountUp(
                    metric.score,
                    style: TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: 38,
                      height: 1,
                      letterSpacing: -1,
                      fontWeight: FontWeight.w200,
                      color: c.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (diff != 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 3, top: 1),
                      child: Text(
                        '${diff > 0 ? '+' : '−'}${diff.abs()}',
                        style: context.text.labelSmall?.copyWith(
                          color: c.inkMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RedFlags extends StatelessWidget {
  const _RedFlags({required this.flags});
  final List<RedFlag> flags;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final urgent = flags.any((f) => f.urgency == FlagUrgency.urgent);
    final color = urgent ? c.bad : c.warn;
    return Container(
      padding: const EdgeInsets.all(Space.md + 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            urgent
                ? 'Please see a doctor soon'
                : 'Worth showing a dermatologist',
            style: context.text.titleMedium,
          ),
          const SizedBox(height: Space.xs),
          for (final f in flags)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(f.title, style: context.text.bodyMedium),
            ),
          const SizedBox(height: Space.xs),
          Text(
            'AI can\'t diagnose. When in doubt, get it checked.',
            style: context.text.bodySmall,
          ),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => launchUrl(
              Uri.parse(
                'https://www.google.com/maps/search/dermatologist+near+me',
              ),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('Find a dermatologist nearby'),
          ),
        ],
      ),
    );
  }
}

class _IngredientLine extends StatelessWidget {
  const _IngredientLine({required this.tip, required this.last});
  final IngredientTip tip;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tip.name, style: context.text.titleSmall),
          const SizedBox(height: 2),
          Text(tip.why, style: context.text.bodySmall),
        ],
      ),
    );
  }
}
