import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/journey/journey_engine.dart';

/// The person's 12-week programme: where they are, what to focus on this
/// phase, and what to expect — in as few words as possible.
class JourneyScreen extends ConsumerWidget {
  const JourneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final j = ref.watch(journeyProvider);
    if (j == null) return const Scaffold(body: SizedBox.expand());
    final c = context.colors;
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            JourneyBackdrop(
              tone: j.phaseIndex.toDouble(),
              child: Padding(
                padding: EdgeInsets.only(top: top + Space.xs),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: Space.xs),
                        IconButton(
                          tooltip: 'Back',
                          onPressed: () => context.pop(),
                          icon: Icon(Icons.arrow_back_rounded, color: c.ink),
                        ),
                        Expanded(
                          child: Center(
                            child: Eyebrow(
                              j.complete
                                  ? 'Plan complete'
                                  : 'Week ${j.week} of ${Journey.totalWeeks}',
                              color: c.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 56),
                      ],
                    ),
                    const SizedBox(height: Space.md),
                    JourneyArc(
                      weeks: j.complete
                          ? Journey.totalWeeks.toDouble()
                          : j.week - 0.5,
                      height: 112,
                    ),
                    const SizedBox(height: Space.lg),
                    Text(
                      j.phase.name,
                      style: context.text.displayLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        letterSpacing: -2,
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                      child: Text(
                        j.track.promise,
                        textAlign: TextAlign.center,
                        style: context.text.bodyLarge?.copyWith(
                          color: c.inkMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.xl),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.md,
                Space.gutter,
                Space.xxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children:
                    [
                          if (j.baselineScore != null) ...[
                            _Scores(j: j),
                            const SizedBox(height: Space.xxl),
                          ],
                          Eyebrow('${j.track.title} · 12 weeks'),
                          const SizedBox(height: Space.xs),
                          for (var i = 0; i < j.phases.length; i++)
                            _PhaseRow(
                              number: i + 1,
                              phase: j.phases[i],
                              state: i < j.phaseIndex || j.complete
                                  ? _PhaseState.done
                                  : i == j.phaseIndex
                                  ? _PhaseState.current
                                  : _PhaseState.upcoming,
                              last: i == j.phases.length - 1,
                            ),
                          const SizedBox(height: Space.xl),
                          Container(
                            padding: const EdgeInsets.all(Space.md + 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(Radii.md),
                              border: Border.all(
                                color: j.seeDoctorNow ? c.bad : c.line,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  j.seeDoctorNow
                                      ? 'Time to see a dermatologist'
                                      : 'When to see a dermatologist',
                                  style: context.text.titleSmall,
                                ),
                                const SizedBox(height: Space.xxs),
                                Text(
                                  j.doctorNote,
                                  style: context.text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: Space.lg),
                          ArrowPill(
                            label: 'Today\'s routine',
                            dark: true,
                            onTap: () => context.go('/routine'),
                          ),
                        ]
                        .animate(interval: 40.ms)
                        .fadeIn(duration: Motion.normal)
                        .slideY(begin: 0.04, curve: Curves.easeOutCubic),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The twelve weeks as a fine ruler, lit up to this week.
class WeekBar extends StatelessWidget {
  const WeekBar({super.key, required this.week, this.complete = false});
  final int week;
  final bool complete;

  @override
  Widget build(BuildContext context) =>
      WeekRuler(week: week, complete: complete);
}

/// Start, now and goal as three large numbers between hairlines.
class _Scores extends StatelessWidget {
  const _Scores({required this.j});
  final Journey j;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget col(String label, int? v, {bool strong = false}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        child: Column(
          children: [
            Eyebrow(label),
            const SizedBox(height: 6),
            Text(
              v?.toString() ?? '—',
              style: context.text.displaySmall?.copyWith(
                fontWeight: strong ? FontWeight.w400 : FontWeight.w200,
                color: strong ? c.ink : c.inkMuted,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
    final rule = VerticalDivider(width: 1, thickness: 1, color: c.line);
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: c.line)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            col('Start', j.baselineScore),
            rule,
            col('Now', j.latestScore, strong: true),
            rule,
            col('Goal', j.goalScore),
          ],
        ),
      ),
    );
  }
}

enum _PhaseState { done, current, upcoming }

/// One phase as a hairline row: number, name, weeks and a quiet state word.
/// The current phase opens to show what to focus on.
class _PhaseRow extends StatelessWidget {
  const _PhaseRow({
    required this.number,
    required this.phase,
    required this.state,
    required this.last,
  });

  final int number;
  final JourneyPhase phase;
  final _PhaseState state;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final current = state == _PhaseState.current;
    final done = state == _PhaseState.done;
    return Container(
      padding: EdgeInsets.symmetric(vertical: current ? Space.lg : Space.md),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  number.toString().padLeft(2, '0'),
                  style: context.text.titleLarge?.copyWith(
                    color: current ? c.ink : c.inkFaint,
                    fontWeight: FontWeight.w200,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  phase.name,
                  style:
                      (current
                              ? context.text.headlineSmall
                              : context.text.titleLarge)
                          ?.copyWith(
                            color: current ? c.ink : c.inkMuted,
                            fontWeight: current
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                ),
              ),
              Text(
                done
                    ? 'Done'
                    : current
                    ? 'Now · ${phase.weeksLabel}'
                    : phase.weeksLabel,
                style: context.text.labelMedium?.copyWith(
                  color: current ? c.ink : c.inkFaint,
                  fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
          if (current) ...[
            Padding(
              padding: const EdgeInsets.only(left: 44, top: Space.xxs),
              child: Text(phase.headline, style: context.text.bodyMedium),
            ),
            const SizedBox(height: Space.md),
            for (var i = 0; i < phase.focus.length; i++)
              Padding(
                padding: const EdgeInsets.only(left: 44, bottom: Space.sm),
                child: Text(
                  phase.focus[i],
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 44, top: Space.xxs),
              child: Text(
                phase.expect,
                style: context.text.bodySmall?.copyWith(color: c.inkMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
