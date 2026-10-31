import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/content/guides.dart';
import '../../services/telemetry.dart';

/// The guide library: everything about skin beyond the routine, ordered for
/// this person's concerns.
class GuidesScreen extends ConsumerWidget {
  const GuidesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final guides = GuideLibrary.forProfile(ref.watch(profileProvider).value);
    final premium = ref.watch(premiumProvider);
    return Scaffold(
      body: AuraBackground(
        intensity: 0.5,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.xs,
              Space.gutter,
              Space.xxl,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: CircleButton(
                  icon: Icons.arrow_back_rounded,
                  size: 42,
                  tooltip: 'Back',
                  onTap: () => context.pop(),
                ),
              ),
              const SizedBox(height: Space.lg),
              Text('Guides', style: context.text.displaySmall),
              const SizedBox(height: Space.xs),
              Text(
                'Food, water, weather, bedding, budget. Everything around the routine.',
                style: context.text.bodyMedium?.copyWith(color: c.inkMuted),
              ),
              const SizedBox(height: Space.lg),
              for (final (i, g) in guides.indexed)
                _GuideRow(
                  guide: g,
                  locked: g.premium && !premium,
                  last: i == guides.length - 1,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideRow extends ConsumerWidget {
  const _GuideRow({
    required this.guide,
    required this.locked,
    required this.last,
  });
  final Guide guide;
  final bool locked;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return InkWell(
      onTap: () => openGuide(context, ref, guide),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.sm),
              child: SizedBox.square(
                dimension: 72,
                child: PhotoFill(guide.image, scrim: 0),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(guide.title, style: context.text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    locked
                        ? '${guide.minutes} min read · Premium'
                        : '${guide.minutes} min read',
                    style: context.text.bodySmall?.copyWith(color: c.inkFaint),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}

void openGuide(BuildContext context, WidgetRef ref, Guide g) {
  ref.read(telemetryProvider).track(Ev.tipOpened, {'id': 'guide_${g.id}'});
  context.push('/guide/${g.id}');
}

/// Today's guide on the home screen: one a day, rotating, image beside words.
class GuideOfTheDay extends ConsumerWidget {
  const GuideOfTheDay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final g = GuideLibrary.ofTheDay(
      ref.watch(profileProvider).value,
      clock.now(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Eyebrow('Today\'s guide'),
            const Spacer(),
            TextButton(
              onPressed: () => context.push('/guides'),
              child: const Text('All guides'),
            ),
          ],
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => openGuide(context, ref, g),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.md),
                child: SizedBox(
                  width: 112,
                  height: 112,
                  child: PhotoFill(g.image, scrim: 0),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.title,
                      style: context.text.titleMedium?.copyWith(height: 1.25),
                    ),
                    const SizedBox(height: Space.xxs),
                    Text(
                      g.teaser,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One guide: title, image, the takeaway, then each section as numbered
/// hairline rows ("don't" sections with a cross). Premium guides show their
/// first section to everyone.
class GuideScreen extends ConsumerWidget {
  const GuideScreen({super.key, required this.guideId});
  final String guideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = GuideLibrary.byId(guideId);
    if (g == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Not found')),
      );
    }
    final c = context.colors;
    final locked = g.premium && !ref.watch(premiumProvider);
    final sections = locked ? g.sections.take(1) : g.sections;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.xs,
            Space.gutter,
            Space.xxl,
          ),
          children:
              [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: 'Back',
                        onPressed: () => context.pop(),
                        icon: Icon(Icons.arrow_back_rounded, color: c.ink),
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    Eyebrow('Guide  ·  ${g.minutes} min read'),
                    const SizedBox(height: Space.sm),
                    Text(
                      g.title,
                      style: context.text.displaySmall?.copyWith(height: 1.1),
                    ),
                    const SizedBox(height: Space.lg),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: PhotoFill(g.image, scrim: 0),
                      ),
                    ),
                    const SizedBox(height: Space.xl),
                    const Eyebrow('In short'),
                    const SizedBox(height: Space.sm),
                    Text(
                      g.teaser,
                      style: context.text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w300,
                        height: 1.4,
                      ),
                    ),
                    if (g.id == 'water') ...[
                      const SizedBox(height: Space.lg),
                      ArrowPill(
                        label: 'Work out my water',
                        onTap: () => context.push('/water'),
                      ),
                    ],
                    for (final s in sections) ...[
                      const SizedBox(height: Space.xl),
                      Eyebrow(s.heading),
                      const SizedBox(height: Space.xs),
                      for (var i = 0; i < s.points.length; i++)
                        _Point(
                          n: i + 1,
                          point: s.points[i],
                          avoid: s.avoid,
                          last: i == s.points.length - 1,
                        ),
                    ],
                    if (locked) ...[
                      const SizedBox(height: Space.xl),
                      Container(
                        padding: const EdgeInsets.all(Space.lg),
                        decoration: BoxDecoration(
                          color: BrandColors.charcoal,
                          borderRadius: BorderRadius.circular(Radii.lg),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${g.sections.length - 1} more sections',
                              style: context.text.titleLarge?.copyWith(
                                color: BrandColors.cream,
                              ),
                            ),
                            const SizedBox(height: Space.xxs),
                            Text(
                              'Every guide in full comes with Premium.',
                              style: context.text.bodyMedium?.copyWith(
                                color: BrandColors.cream.withValues(alpha: 0.7),
                              ),
                            ),
                            const SizedBox(height: Space.md),
                            ArrowPill(
                              label: 'See Premium',
                              onTap: () =>
                                  context.push('/paywall?source=guides'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.xl),
                    const Disclaimer(
                      text: 'General guidance, not a diagnosis. See a doctor for anything painful, spreading or not improving.',
                    ),
                  ]
                  .animate(interval: 30.ms)
                  .fadeIn(duration: Motion.normal)
                  .slideY(begin: 0.04, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({
    required this.n,
    required this.point,
    required this.avoid,
    required this.last,
  });
  final int n;
  final GuidePoint point;
  final bool avoid;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: avoid
                ? Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.close_rounded, size: 22, color: c.bad),
                  )
                : Text(
                    n.toString().padLeft(2, '0'),
                    style: context.text.headlineMedium?.copyWith(
                      color: c.inkFaint,
                      fontWeight: FontWeight.w200,
                      height: 1,
                    ),
                  ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(point.title, style: context.text.titleMedium),
                const SizedBox(height: 2),
                Text(point.detail, style: context.text.bodyMedium),
                if (point.evidence != null) ...[
                  const SizedBox(height: Space.xxs),
                  Text(
                    point.evidence!.label,
                    style: context.text.labelSmall?.copyWith(color: c.inkFaint),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
