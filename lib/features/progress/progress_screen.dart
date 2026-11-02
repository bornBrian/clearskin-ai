import 'dart:io';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/scan.dart';
import '../../domain/insights/insights_engine.dart';
import 'progress_proof.dart';

enum _View { trends, photos, insights }

class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  _View _view = _View.trends;

  @override
  Widget build(BuildContext context) {
    final scans = ref.watch(scansProvider).value ?? const <SkinScan>[];
    return Scaffold(
      body: AuraBackground(
        intensity: 0.7,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              PageHeader(
                'Progress',
                trailing: ref.watch(usableScansProvider).length >= 2
                    ? CircleButton(
                        icon: Icons.compare_rounded,
                        tooltip: 'Before & after',
                        onTap: () => ref.read(premiumProvider)
                            ? context.push('/compare')
                            : context.push('/paywall?source=compare'),
                      )
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.gutter,
                  vertical: Space.xs,
                ),
                child: TextTabs(
                  labels: const ['Trends', 'Photos', 'Insights'],
                  index: _view.index,
                  onChanged: (i) => setState(() => _view = _View.values[i]),
                ),
              ),
              Expanded(
                child: switch (_view) {
                  _View.trends => const _Trends(),
                  _View.photos => _Photos(scans: scans),
                  _View.insights => const _Insights(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Trends extends ConsumerStatefulWidget {
  const _Trends();

  @override
  ConsumerState<_Trends> createState() => _TrendsState();
}

class _TrendsState extends ConsumerState<_Trends> {
  SkinMetric? _metric;

  /// Radiance is measured on the phone, so its trend is free for everyone.
  bool _glow = false;

  @override
  Widget build(BuildContext context) {
    final scans = ref.watch(usableScansProvider).reversed.toList();
    final premium = ref.watch(premiumProvider);
    final c = context.colors;

    // A second scan within days shows noise, not change, and spends a free
    // scan on a disappointment. Until a week has passed, say when, and
    // point at what does move the line.
    final baseline = scans.firstOrNull?.createdAt;
    final next = baseline == null
        ? null
        : DateTime(baseline.year, baseline.month, baseline.day + 7);
    final waitDays = scans.length == 1
        ? next!.difference(Dates.startOfDay(clock.now())).inDays
        : 0;
    if (waitDays > 0) {
      return EmptyState(
        icon: Icons.show_chart_rounded,
        title: waitDays == 1
            ? 'Your second scan is tomorrow'
            : 'Your second scan: ${DateFormat('EEEE d MMM').format(next!)}',
        body:
            'Skin takes about a week to show change. Until then, your '
            'routine is what moves this line.',
        actionLabel: 'Today\'s routine',
        onAction: () => context.go('/routine'),
      );
    }
    if (scans.length < 2) {
      return EmptyState(
        icon: Icons.show_chart_rounded,
        title: scans.isEmpty ? 'No scans yet' : 'One more scan',
        body: 'Your trend starts with your second weekly scan.',
        actionLabel: 'Scan now',
        onAction: () => context.push('/scan'),
      );
    }

    int? value(SkinScan s) => _glow
        ? s.radiance?.score
        : _metric == null
        ? s.analysis.overallScore
        : s.analysis.scoreFor(_metric!);

    final first = scans.first.createdAt;
    final points = <FlSpot>[
      for (final s in scans)
        if (value(s) case final v?)
          FlSpot(s.createdAt.difference(first).inHours / 24.0, v.toDouble()),
    ];
    if (points.length < 2) {
      return EmptyState(
        icon: Icons.show_chart_rounded,
        title: 'Not enough data',
        body: _glow
            ? 'Radiance is measured from your photo on every scan. Two scans start the trend.'
            : 'This measure needs two scans.',
      );
    }
    final firstV = points.first.y;
    final lastV = points.last.y.round();
    final lo = points.map((p) => p.y).reduce(math.min);
    final hi = points.map((p) => p.y).reduce(math.max);
    final minY = math.max(0.0, (lo - 12).floorToDouble());
    final maxY = math.min(100.0, (hi + 10).ceilToDouble());
    final maxX = points.last.x;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Space.gutter,
        Space.md,
        Space.gutter,
        Space.navClearance(context),
      ),
      children: [
        Eyebrow(_glow ? 'Radiance' : _metric?.label ?? 'Skin score'),
        const SizedBox(height: Space.xxs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('$lastV', style: context.text.displayMedium),
            const SizedBox(width: Space.sm),
            Text(
              'from ${firstV.round()} on ${Dates.short(first)}',
              style: context.text.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        SizedBox(
          height: 230,
          child: LineChart(
            duration: Motion.slow,
            curve: Curves.easeOutCubic,
            LineChartData(
              minY: minY,
              maxY: maxY,
              minX: 0,
              maxX: maxX,
              clipData: const FlClipData.none(),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    interval: maxX <= 0 ? 1 : maxX,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                      child: Text(
                        Dates.short(
                          first.add(Duration(hours: (v * 24).round())),
                        ),
                        style: context.text.labelSmall,
                      ),
                    ),
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                getTouchedSpotIndicator: (bar, idx) => [
                  for (final _ in idx)
                    TouchedSpotIndicatorData(
                      FlLine(
                        color: c.ink.withValues(alpha: 0.25),
                        strokeWidth: 1,
                      ),
                      FlDotData(
                        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                          radius: 5,
                          color: c.surface,
                          strokeColor: c.ink,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                ],
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => c.ink,
                  tooltipBorderRadius: BorderRadius.circular(Radii.pill),
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${s.y.round()}  ·  ${Dates.short(first.add(Duration(hours: (s.x * 24).round())))}',
                        TextStyle(
                          color: c.background,
                          fontFamily: kFontFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: points,
                  isCurved: true,
                  curveSmoothness: 0.35,
                  preventCurveOverShooting: true,
                  barWidth: 2.5,
                  isStrokeCapRound: true,
                  gradient: LinearGradient(
                    colors: [c.leaf.withValues(alpha: 0.45), c.leaf],
                  ),
                  dotData: FlDotData(
                    checkToShowDot: (spot, bar) => spot == bar.spots.last,
                    getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                      radius: 5,
                      color: c.surface,
                      strokeColor: c.leaf,
                      strokeWidth: 2.5,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        c.leaf.withValues(alpha: 0.22),
                        c.leaf.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.lg),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              _MetricTab(
                label: 'Overall',
                selected: _metric == null && !_glow,
                onTap: () => setState(() {
                  _metric = null;
                  _glow = false;
                }),
              ),
              _MetricTab(
                label: 'Radiance',
                selected: _glow,
                onTap: () => setState(() {
                  _metric = null;
                  _glow = true;
                }),
              ),
              for (final m in SkinMetric.values)
                _MetricTab(
                  label: m.label,
                  selected: _metric == m && !_glow,
                  locked: !premium,
                  onTap: () => premium
                      ? setState(() {
                          _metric = m;
                          _glow = false;
                        })
                      : context.push('/paywall?source=trends'),
                ),
            ],
          ),
        ),
        const ProgressProofSection(padding: EdgeInsets.only(top: Space.xl)),
        const SizedBox(height: Space.xl),
        const SectionHeader('Biggest changes'),
        _BiggestChanges(first: scans.first, last: scans.last),
      ],
    );
  }
}

class _MetricTab extends StatelessWidget {
  const _MetricTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.locked = false,
  });

  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: Space.lg),
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: context.text.titleSmall?.copyWith(
                      color: selected ? c.ink : c.inkMuted,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (locked && !selected) ...[
                    const SizedBox(width: 3),
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 11,
                      color: c.inkFaint,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: Motion.fast,
                width: selected ? 18 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color: c.ink,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BiggestChanges extends StatelessWidget {
  const _BiggestChanges({required this.first, required this.last});
  final SkinScan first;
  final SkinScan last;

  @override
  Widget build(BuildContext context) {
    final rows = <(SkinMetric, int, int)>[];
    for (final m in SkinMetric.values) {
      final a = first.analysis.scoreFor(m);
      final b = last.analysis.scoreFor(m);
      if (a != null && b != null) rows.add((m, b, b - a));
    }
    rows.sort((a, b) => b.$3.abs().compareTo(a.$3.abs()));
    final c = context.colors;
    final top = rows.take(4).toList();
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Space.md + 2),
      child: Column(
        children: [
          for (var i = 0; i < top.length; i++)
            LineItem(
              title: top[i].$1.label,
              divider: i < top.length - 1,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    top[i].$3 == 0
                        ? 'No change'
                        : top[i].$3 > 0
                        ? 'Up ${top[i].$3}'
                        : 'Down ${-top[i].$3}',
                    style: context.text.bodySmall?.copyWith(
                      color: top[i].$3 > 0
                          ? c.good
                          : top[i].$3 < 0
                          ? c.bad
                          : c.inkMuted,
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${top[i].$2}',
                      textAlign: TextAlign.right,
                      style: context.text.titleMedium,
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

class _Photos extends StatelessWidget {
  const _Photos({required this.scans});
  final List<SkinScan> scans;

  @override
  Widget build(BuildContext context) {
    if (scans.isEmpty) {
      return EmptyState(
        icon: Icons.photo_library_outlined,
        title: 'Your skin timeline',
        body: 'Scan photos stay private on your phone.',
        actionLabel: 'Take first scan',
        onAction: () => context.push('/scan'),
      );
    }
    final c = context.colors;
    return GridView.builder(
      padding: const EdgeInsets.all(Space.gutter),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: Space.xs,
        crossAxisSpacing: Space.xs,
        childAspectRatio: 0.75,
      ),
      itemCount: scans.length,
      itemBuilder: (context, i) {
        final s = scans[i];
        return GestureDetector(
          onTap: () => context.push('/scan/${s.id}'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(s.photoPath),
                  fit: BoxFit.cover,
                  cacheWidth: 300,
                  errorBuilder: (_, _, _) => Container(color: c.surfaceAlt),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            Dates.short(s.createdAt),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Text(
                          s.analysis.usable
                              ? '${s.analysis.overallScore}'
                              : '—',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Insights extends ConsumerWidget {
  const _Insights();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(insightsProvider);
    final c = context.colors;

    if (!report.ready) {
      final progress = report.daysLogged / InsightsEngine.minDays;
      return ListView(
        padding: const EdgeInsets.all(Space.gutter),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Finding your triggers', style: context.text.titleLarge),
                const SizedBox(height: Space.xs),
                Text(
                  'Daily check-ins reveal what affects your skin.',
                  style: context.text.bodyMedium,
                ),
                const SizedBox(height: Space.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: c.surfaceAlt,
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  '${report.daysLogged} of ${InsightsEngine.minDays} check-ins',
                  style: context.text.labelMedium,
                ),
                const SizedBox(height: Space.md),
                FilledButton(
                  onPressed: () => context.push('/checkin'),
                  child: const Text('Check in today'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (report.insights.isEmpty) {
      return const EmptyState(
        icon: Icons.verified_rounded,
        title: 'No clear triggers yet',
        body: 'Nothing lines up with breakouts yet. Keep checking in.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        PremiumGate(
          feature: 'insights',
          teaser: Text(
            'We found ${report.insights.length} pattern${report.insights.length == 1 ? '' : 's'} in your ${report.daysLogged} days of check-ins.',
            style: context.text.titleMedium,
          ),
          child: Column(
            children: [
              for (final i in report.insights)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: AppCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i.emoji ?? '•',
                          style: const TextStyle(fontSize: 26),
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      i.title,
                                      style: context.text.titleMedium,
                                    ),
                                  ),
                                  Pill(
                                    i.direction == InsightDirection.worse
                                        ? 'Possible trigger'
                                        : 'Helps',
                                    color: i.direction == InsightDirection.worse
                                        ? c.warn
                                        : c.good,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(i.detail, style: context.text.bodyMedium),
                              const SizedBox(height: Space.xs),
                              Text(
                                'Confidence ${(i.confidence * 100).round()}% · based on ${i.withCount + i.withoutCount} days',
                                style: context.text.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Disclaimer(
                text: 'Patterns, not proof. Try removing a suspected trigger for 2–3 weeks and see if your check-ins change.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
