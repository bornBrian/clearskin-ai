import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/profile.dart';
import '../../domain/journey/journey_engine.dart';

/// "Your plan is ready" — shown at the end of onboarding, before the first
/// scan.
///
/// The answers set the goal and the timeline; the routine itself waits for
/// the scan, because answers alone can't tell acne from irritation or dry
/// from dehydrated skin. So this screen shows the plan's shape and what the
/// scan will measure, then starts it. The paywall comes after the first
/// result, when there's something real to keep.
class PlanRevealScreen extends ConsumerWidget {
  const PlanRevealScreen({super.key, required this.profile});
  final UserProfile profile;

  /// Account first, so the scan and any later purchase belong to a person,
  /// not just a phone. Then onboarding opens the first scan.
  Future<void> _continue(BuildContext context, WidgetRef ref) async {
    if (ref.read(accountProvider).value == null) {
      await context.push<bool>('/auth?mode=save');
      if (!context.mounted) return;
    }
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeline = PlanCopy.timeline(profile);
    final journey = JourneyEngine.build(
      profile: profile,
      usableScans: const [],
    );
    final name = profile.firstName;
    final top = MediaQuery.paddingOf(context).top;
    const cream = BrandColors.cream;
    final skin = profile.skinType == SkinType.unsure
        ? null
        : profile.skinType.label.toLowerCase();

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        color: BrandColors.charcoal,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(Radii.lg + 8),
                        ),
                      ),
                      padding: EdgeInsets.fromLTRB(
                        Space.gutter,
                        top + Space.md,
                        Space.gutter,
                        Space.xl,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BrandMark(size: 44, color: cream),
                          const SizedBox(height: Space.xl),
                          Eyebrow(
                            'Your 12-week plan',
                            color: cream.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: Space.sm),
                          Text(
                            name.isEmpty
                                ? 'Your plan\nis ready.'
                                : '$name, your plan\nis ready.',
                            style: context.text.displaySmall?.copyWith(
                              color: cream,
                            ),
                          ),
                          const SizedBox(height: Space.sm),
                          Text(
                            skin == null
                                ? journey.track.title
                                : '${journey.track.title}, for $skin skin.',
                            style: context.text.bodyLarge?.copyWith(
                              color: cream.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: Space.xl),
                          WeekRuler(
                            week: 1,
                            color: cream,
                            labels: [
                              for (final p in journey.phases)
                                (p.name, p.firstWeek, p.lastWeek),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.gutter,
                        Space.xl,
                        Space.gutter,
                        Space.lg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children:
                            [
                                  const Eyebrow('What you\'ll see'),
                                  const SizedBox(height: Space.sm),
                                  _Outcomes(timeline: timeline),
                                  const SizedBox(height: Space.xs),
                                  Text(
                                    'Typical with daily use.',
                                    style: context.text.bodySmall?.copyWith(
                                      color: context.colors.inkFaint,
                                    ),
                                  ),
                                  const SizedBox(height: Space.xxl),
                                  const _ScanNext(),
                                ]
                                .animate(interval: 50.ms)
                                .fadeIn(duration: Motion.slow)
                                .slideY(
                                  begin: 0.05,
                                  curve: Curves.easeOutCubic,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.xs,
                  Space.gutter,
                  Space.sm,
                ),
                child: Column(
                  children: [
                    ArrowPill(
                      label: 'Scan my skin',
                      dark: true,
                      onTap: () => _continue(context, ref),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Week 2, 6 and 12 as three large numbers, each with one short outcome,
/// split by hairlines.
class _Outcomes extends StatelessWidget {
  const _Outcomes({required this.timeline});
  final List<(String, String)> timeline;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: c.line)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < timeline.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, thickness: 1, color: c.line),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    i == 0 ? 0 : Space.sm,
                    Space.md,
                    Space.xs,
                    Space.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('Week'),
                      Text(
                        timeline[i].$1.replaceAll(RegExp(r'[^0-9]'), ''),
                        style: TextStyle(
                          fontFamily: kFontFamily,
                          fontSize: 44,
                          height: 1.15,
                          letterSpacing: -1.5,
                          fontWeight: FontWeight.w200,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        timeline[i].$2,
                        style: context.text.bodyMedium?.copyWith(
                          color: c.ink,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What happens next: three angles, nine measures, then the routine built
/// from them. Numbered hairline rows.
class _ScanNext extends StatelessWidget {
  const _ScanNext();

  static const _rows = [
    ('Front, left and right', 'Every zone: forehead, cheeks, jawline.'),
    (
      'Nine measures',
      'Blemishes, texture, pores, redness, tone, hydration, oil, '
          'smoothness, under-eyes.',
    ),
    ('Then your routine', 'Built for what the scan finds, nothing guessed.'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Eyebrow('Next: your first scan'),
        const SizedBox(height: Space.xs),
        for (var i = 0; i < _rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            decoration: BoxDecoration(
              border: i == _rows.length - 1
                  ? null
                  : Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    (i + 1).toString().padLeft(2, '0'),
                    style: context.text.titleMedium?.copyWith(
                      color: c.inkFaint,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_rows[i].$1, style: context.text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        _rows[i].$2,
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

/// Personalised, evidence-based copy for the plan reveal. Kept separate and
/// pure so it's testable.
abstract final class PlanCopy {
  static const _priority = [
    Concern.acne,
    Concern.darkSpots,
    Concern.razorBumps,
    Concern.redness,
    Concern.sensitivity,
    Concern.blackheads,
    Concern.texture,
    Concern.fineLines,
    Concern.unevenTone,
    Concern.dryness,
    Concern.oiliness,
    Concern.largePores,
    Concern.darkCircles,
  ];

  static Concern? primary(UserProfile p) =>
      _priority.where(p.concerns.contains).firstOrNull;

  static List<String> focus(UserProfile p) => [
    for (final cn in _priority.where(p.concerns.contains).take(3)) cn.label,
  ];

  static List<(String, String)> timeline(UserProfile p) {
    final (w6, w12) = switch (primary(p)) {
      Concern.acne => ('Fewer new breakouts', 'Clearer skin, marks fading'),
      Concern.blackheads => (
        'Pores look clearer',
        'Smoother, less congested skin',
      ),
      Concern.darkSpots ||
      Concern.unevenTone => ('Marks begin to soften', 'Visibly more even tone'),
      Concern.redness || Concern.sensitivity => (
        'Calmer, less reactive skin',
        'Stronger barrier, fewer flare-ups',
      ),
      Concern.razorBumps => (
        'Fewer bumps after shaving',
        'Smoother beard area',
      ),
      Concern.fineLines => ('Smoother texture', 'Fine lines look softer'),
      Concern.texture => ('Noticeably smoother skin', 'Refined, even texture'),
      Concern.dryness => (
        'Comfortable, hydrated skin',
        'Resilient barrier all day',
      ),
      Concern.oiliness ||
      Concern.largePores => ('More balanced shine', 'Pores look refined'),
      Concern.darkCircles => (
        'Brighter-looking eye area',
        'Rested, even under-eyes',
      ),
      null => ('Visibly healthier skin', 'Your best skin baseline'),
    };
    return [
      ('Week 2', 'Your routine becomes a habit'),
      ('Week 6', w6),
      ('Week 12', w12),
    ];
  }
}
