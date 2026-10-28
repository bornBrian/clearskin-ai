import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/check_in.dart';
import '../../data/models/scan.dart';
import '../../domain/ingredients/product_analyzer.dart';
import '../../domain/nudges/nudge_engine.dart';
import '../paywall/renewal_banner.dart';
import '../routine/streak_widgets.dart';
import '../journey/journey_screen.dart';
import '../routine/routine_screen.dart';
import '../tips/tips_widgets.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final name = profile?.firstName ?? '';
    final hasScan = ref.watch(latestScanProvider) != null;
    final now = clock.now();

    return Scaffold(
      body: AuraBackground(
        intensity: 0.7,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(weatherProvider);
              await ref.read(purchasesServiceProvider).refresh();
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                Space.gutter,
                Space.sm,
                Space.gutter,
                Space.navClearance(context),
              ),
              children:
                  [
                        _TopBar(initial: name.isEmpty ? null : name[0]),
                        const SizedBox(height: Space.lg),
                        Eyebrow(DateFormat('EEEE, d MMMM').format(now)),
                        const SizedBox(height: Space.xs),
                        Text(
                          name.isEmpty
                              ? Dates.greeting(now)
                              : '${Dates.greeting(now)},\n$name',
                          style: context.text.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w300,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: Space.xl),
                        const RenewalBannerCard(),
                        if (hasScan) const _ScoreHero() else const _FirstScan(),
                        const _RedFlagBanner(),
                        if (hasScan) const _TopNudge(),
                        const SizedBox(height: Space.xl),
                        const StreakLine(),
                        const SizedBox(height: Space.lg),
                        const _TodayRoutine(),
                        const SizedBox(height: Space.md),
                        const _PlanCard(),
                        const SizedBox(height: Space.xl),
                        const _Forecast(),
                        const ForYouCarousel(),
                        const SizedBox(height: Space.lg),
                        const _ConflictAlert(),
                        const _MoreRows(),
                      ]
                      .animate(interval: 35.ms)
                      .fadeIn(duration: Motion.normal)
                      .slideY(begin: 0.03, curve: Curves.easeOutCubic),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.initial});
  final String? initial;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        const BrandMark(size: 46),
        const Spacer(),
        IconButton(
          tooltip: 'Reminders',
          onPressed: () => context.push('/settings/reminders'),
          icon: Icon(Icons.notifications_none_rounded, color: c.ink),
        ),
        const SizedBox(width: Space.xxs),
        Semantics(
          button: true,
          label: 'Settings',
          child: GestureDetector(
            onTap: () => context.push('/settings'),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.primary,
                shape: BoxShape.circle,
              ),
              child: initial == null
                  ? Icon(
                      Icons.person_outline_rounded,
                      size: 18,
                      color: c.onPrimary,
                    )
                  : Text(
                      initial!.toUpperCase(),
                      style: context.text.titleSmall?.copyWith(
                        color: c.onPrimary,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Score dial and three key measures, straight on the canvas.
class _ScoreHero extends ConsumerWidget {
  const _ScoreHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(latestScanProvider)!;
    final a = latest.analysis;
    final c = context.colors;
    final metrics = [
      SkinMetric.hydration,
      SkinMetric.acne,
      SkinMetric.pigmentation,
    ].where((m) => a.scoreFor(m) != null).toList();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/scan/${latest.id}'),
      child: Column(
        children: [
          Row(
            children: [
              ScoreDial(score: a.overallScore, size: 150),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('Skin score'),
                    const SizedBox(height: Space.xs),
                    Text(
                      scoreWord(a.overallScore),
                      style: context.text.headlineMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Scanned ${Dates.relative(latest.createdAt).toLowerCase()}',
                      style: context.text.bodySmall,
                    ),
                    const SizedBox(height: Space.md),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Full report',
                            style: context.text.labelLarge?.copyWith(
                              color: c.ink,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: c.ink,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: Space.lg),
            Container(
              padding: const EdgeInsets.symmetric(vertical: Space.md),
              decoration: BoxDecoration(
                border: Border.symmetric(horizontal: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < metrics.length; i++) ...[
                    if (i > 0)
                      Container(
                        width: 1,
                        height: 56,
                        margin: const EdgeInsets.symmetric(
                          horizontal: Space.md,
                        ),
                        color: c.line,
                      ),
                    Expanded(
                      child: MiniMetric(
                        label: metrics[i].label,
                        value: a.scoreFor(metrics[i])!,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// First run: one crafted charcoal card, no stock faces.
class _FirstScan extends StatelessWidget {
  const _FirstScan();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BrandColors.charcoal,
      borderRadius: BorderRadius.circular(Radii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/scan'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.xl,
            Space.lg,
            Space.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: SizedBox.square(
                  dimension: 190,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ScoreDial(
                        score: 0,
                        size: 190,
                        trackColor: BrandColors.cream.withValues(alpha: 0.28),
                        color: BrandColors.cream,
                        textColor: Colors.transparent,
                      ),
                      const LogoMark(size: 70, color: BrandColors.cream),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.xl),
              Eyebrow(
                '10 seconds',
                color: BrandColors.cream.withValues(alpha: 0.6),
              ),
              const SizedBox(height: Space.xs),
              Text(
                'Your first scan',
                style: context.text.displaySmall?.copyWith(
                  color: BrandColors.cream,
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                'Your baseline for every result to come.',
                style: context.text.bodyMedium?.copyWith(
                  color: BrandColors.cream.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: Space.lg),
              Container(
                height: 54,
                decoration: const ShapeDecoration(
                  color: BrandColors.cream,
                  shape: StadiumBorder(),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Start scan',
                  style: context.text.titleMedium?.copyWith(
                    color: BrandColors.charcoal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The single most useful alert right now, as a quiet charcoal strip.
class _TopNudge extends ConsumerWidget {
  const _TopNudge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasScan = ref.watch(latestScanProvider) != null;
    final n = ref
        .watch(nudgesProvider)
        // The first-scan nudge repeats the hero card.
        .where((n) => hasScan || n.kind != NudgeKind.scanDue)
        // Tonight's step is already in the checklist below.
        .where((n) => n.kind != NudgeKind.tonight)
        .firstOrNull;
    if (n == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: Material(
        color: BrandColors.charcoal,
        borderRadius: BorderRadius.circular(Radii.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(n.route),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.md + 2, 14, Space.md, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        style: context.text.titleSmall?.copyWith(
                          color: BrandColors.cream,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        n.body,
                        style: context.text.bodySmall?.copyWith(
                          color: BrandColors.cream.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  n.action,
                  style: context.text.labelLarge?.copyWith(
                    color: BrandColors.cream,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// This slot's steps, tickable right here.
class _TodayRoutine extends ConsumerWidget {
  const _TodayRoutine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routine = ref.watch(routineProvider);
    if (routine == null) return const SizedBox.shrink();
    final now = clock.now();
    final slot = now.hour >= 15 ? RoutineSlot.pm : RoutineSlot.am;
    final steps = routine
        .stepsFor(slot, now)
        .where((s) => !s.optional)
        .toList();
    final done = ref.watch(todayCompletedProvider(slot));
    final completed = steps.where((s) => done.contains(s.id)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Eyebrow(slot == RoutineSlot.am ? 'This morning' : 'Tonight'),
            const Spacer(),
            Text(
              '$completed of ${steps.length}',
              style: context.text.labelMedium,
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Space.md + 2),
          child: Column(
            children: [
              for (var i = 0; i < steps.length; i++)
                StepRow(
                  index: i + 1,
                  step: steps[i],
                  done: done.contains(steps[i].id),
                  divider: i < steps.length - 1,
                  onToggle: () =>
                      toggleRoutineStep(ref, context, slot, steps[i], steps),
                  onOpen: () => showStepSheet(context, steps[i]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final j = ref.watch(journeyProvider);
    if (j == null) return const SizedBox.shrink();
    final c = context.colors;
    return AppCard(
      onTap: () => context.push('/journey'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Eyebrow(j.track.title),
              const Spacer(),
              Text(
                j.complete ? 'Complete' : 'Week ${j.week} of 12',
                style: context.text.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${j.phase.name} · ${j.phase.headline}',
                  style: context.text.titleMedium,
                ),
              ),
              Icon(Icons.arrow_forward_rounded, size: 18, color: c.ink),
            ],
          ),
          const SizedBox(height: Space.md),
          WeekBar(week: j.week, complete: j.complete),
        ],
      ),
    );
  }
}

class _Forecast extends ConsumerWidget {
  const _Forecast();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final c = context.colors;
    if (profile?.location == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.xl),
        child: LineItem(
          title: 'Daily skin forecast',
          subtitle: 'Add your city for UV and humidity',
          onTap: () => context.push('/settings/profile'),
          trailing: Icon(Icons.chevron_right_rounded, color: c.inkFaint),
        ),
      );
    }
    final weather = ref.watch(weatherProvider).value;
    final forecast = ref.watch(forecastProvider);
    if (weather == null || forecast == null) return const SizedBox.shrink();
    final tip = forecast.tips.firstOrNull?.body;
    final firstSentence = tip == null
        ? null
        : '${tip.split(RegExp(r'(?<=\.)\s')).first.replaceAll(RegExp(r'\.$'), '')}.';
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('Forecast · ${profile!.location!.name.split(',').first}'),
          const SizedBox(height: Space.xs),
          Text(forecast.headline, style: context.text.headlineMedium),
          if (firstSentence != null) ...[
            const SizedBox(height: Space.xxs),
            Text(firstSentence, style: context.text.bodyMedium),
          ],
          const SizedBox(height: Space.md),
          Container(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            decoration: BoxDecoration(
              border: Border.symmetric(horizontal: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                _Stat(value: '${weather.uvIndexMax.round()}', label: 'UV'),
                _Stat(value: '${weather.humidity.round()}%', label: 'Humidity'),
                _Stat(value: '${weather.temperatureC.round()}°', label: 'Temp'),
                if (weather.usAqi != null)
                  _Stat(value: '${weather.usAqi}', label: 'Air'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w300),
        ),
        Text(label, style: context.text.labelSmall),
      ],
    ),
  );
}

class _RedFlagBanner extends ConsumerWidget {
  const _RedFlagBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(latestScanProvider);
    final flags = latest?.analysis.redFlags ?? const <RedFlag>[];
    if (flags.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final urgent = flags.any((f) => f.urgency != FlagUrgency.routine);
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: LineItem(
        title: urgent ? 'Worth a dermatologist visit' : 'One to watch',
        subtitle: 'From your last scan',
        divider: false,
        leading: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: urgent ? c.bad : c.warn,
            shape: BoxShape.circle,
          ),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: c.inkFaint),
        onTap: () => context.push('/scan/${latest!.id}'),
      ),
    );
  }
}

class _ConflictAlert extends ConsumerWidget {
  const _ConflictAlert();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflicts = ref
        .watch(conflictsProvider)
        .where((x) => x.severity.index >= FlagSeverity.medium.index)
        .toList();
    if (conflicts.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return LineItem(
      title: conflicts.first.title,
      subtitle: conflicts.length > 1
          ? '${conflicts.length} shelf alerts'
          : 'Shelf alert',
      leading: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c.warn, shape: BoxShape.circle),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: c.inkFaint),
      onTap: () => context.go('/shelf'),
    );
  }
}

class _MoreRows extends ConsumerWidget {
  const _MoreRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final today = ref.watch(todayCheckInProvider);
    final report = ref.watch(insightsProvider);
    final premium = ref.watch(premiumProvider);
    final chevron = Icon(Icons.chevron_right_rounded, color: c.inkFaint);
    return Column(
      children: [
        LineItem(
          title: today == null ? 'Daily check-in' : 'Checked in today',
          subtitle: today == null
              ? (report.ready
                    ? 'Ten seconds'
                    : '${report.daysNeeded} more to find your triggers')
              : '${today.sleepHours.toStringAsFixed(today.sleepHours % 1 == 0 ? 0 : 1)}h sleep · stress ${today.stress}/5',
          trailing: today == null
              ? chevron
              : Icon(Icons.check_rounded, color: c.leaf),
          onTap: () => context.push('/checkin'),
        ),
        LineItem(
          title: 'Ask your skin coach',
          subtitle: premium ? 'Knows your skin and routine' : 'Premium',
          trailing: chevron,
          divider: false,
          onTap: () => context.push('/coach'),
        ),
      ],
    );
  }
}
