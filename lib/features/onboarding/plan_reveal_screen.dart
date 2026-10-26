import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/profile.dart';
import '../../domain/routine/routine_engine.dart';
import '../../domain/journey/journey_engine.dart';

/// "Your plan is ready" — shown between onboarding and the paywall.
///
/// Showing people the concrete, personal plan they're about to unlock (their
/// focus, routine, timeline and why it fits them) is the single biggest
/// conversion lever in subscription apps. Everything here is real output of
/// the routine engine, never placeholder marketing.
class PlanRevealScreen extends ConsumerWidget {
  const PlanRevealScreen({super.key, required this.profile});
  final UserProfile profile;

  Future<void> _continue(
    BuildContext context,
    WidgetRef ref,
    bool upgrade,
  ) async {
    // Account first, so a purchase is tied to a person, not just a phone.
    if (ref.read(accountProvider).value == null) {
      await context.push<bool>('/auth?mode=save');
      if (!context.mounted) return;
    }
    if (upgrade && !ref.read(premiumProvider)) {
      await context.push('/paywall?source=onboarding');
    }
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routine = RoutineEngine.build(profile: profile);
    final timeline = PlanCopy.timeline(profile);
    final journey = JourneyEngine.build(profile: profile, usableScans: const []);
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
                                    'Typical with daily use. Your weekly scans show the real thing.',
                                    style: context.text.bodySmall?.copyWith(
                                      color: context.colors.inkFaint,
                                    ),
                                  ),
                                  const SizedBox(height: Space.xxl),
                                  _RoutinePreview(
                                    am: routine.am
                                        .where((s) => !s.optional)
                                        .toList(),
                                    pm: routine.pm
                                        .where((s) => !s.optional)
                                        .toList(),
                                  ),
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
                      label: 'Unlock my full plan',
                      dark: true,
                      onTap: () => _continue(context, ref, true),
                    ),
                    TextButton(
                      onPressed: () => _continue(context, ref, false),
                      child: const Text('Continue free'),
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

/// Morning / evening steps, one list at a time, each with the line drawing
/// of what it comes in.
class _RoutinePreview extends StatefulWidget {
  const _RoutinePreview({required this.am, required this.pm});
  final List<RoutineStep> am;
  final List<RoutineStep> pm;

  @override
  State<_RoutinePreview> createState() => _RoutinePreviewState();
}

class _RoutinePreviewState extends State<_RoutinePreview> {
  int _slot = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final steps = _slot == 0 ? widget.am : widget.pm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Eyebrow('Your routine'),
            const Spacer(),
            Text(
              '${steps.length} steps',
              style: context.text.labelMedium?.copyWith(color: c.inkFaint),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        TextTabs(
          labels: const ['Morning', 'Evening'],
          index: _slot,
          style: context.text.headlineSmall,
          onChanged: (i) => setState(() => _slot = i),
        ),
        const SizedBox(height: Space.xs),
        AnimatedSwitcher(
          duration: Motion.normal,
          child: Column(
            key: ValueKey(_slot),
            children: [
              for (var i = 0; i < steps.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  decoration: BoxDecoration(
                    border: i == steps.length - 1
                        ? null
                        : Border(bottom: BorderSide(color: c.line)),
                  ),
                  child: Row(
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
                        child: Text(
                          steps[i].title,
                          style: context.text.titleMedium,
                        ),
                      ),
                      ProductGlyph(
                        category: steps[i].category,
                        size: 34,
                        color: c.inkMuted,
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
      Concern.acne => (
        'Fewer new breakouts',
        'Clearer skin, marks fading',
      ),
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
