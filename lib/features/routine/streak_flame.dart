import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../domain/routine/streaks.dart';

/// Streak fire colours: a warm core to a deep orange edge. The one warm
/// accent in the app, kept for the streak so it always means "your streak".
abstract final class FlameColors {
  static const core = Color(0xFFFFD45C);
  static const mid = Color(0xFFFF9A2E);
  static const edge = Color(0xFFF0562B);
}

/// The streak flame. Lit (with a slow flicker) once today counts; grey
/// while today is still to do, so a glance says whether the streak is safe.
class StreakFlame extends StatefulWidget {
  const StreakFlame({
    super.key,
    required this.lit,
    this.size = 28,
    this.animate = true,
    this.unlitColor,
  });

  final bool lit;
  final double size;
  final bool animate;
  final Color? unlitColor;

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame>
    with SingleTickerProviderStateMixin {
  late final _flicker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(StreakFlame old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.lit && widget.animate && !still) {
      if (!_flicker.isAnimating) _flicker.repeat();
    } else {
      _flicker.stop();
    }
  }

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unlit = widget.unlitColor ?? context.colors.inkFaint;
    return SizedBox(
      width: widget.size * 0.8,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _flicker,
        builder: (_, _) => CustomPaint(
          painter: FlamePainter(
            lit: widget.lit,
            phase: _flicker.value,
            unlit: unlit,
          ),
        ),
      ),
    );
  }
}

/// A flame drawn from curves: an outer tongue with a side lick, and an
/// inner core. [phase] (0–1) sways and stretches it a little; [grow] (0–1)
/// lets it ignite from the base.
class FlamePainter extends CustomPainter {
  const FlamePainter({
    required this.lit,
    this.phase = 0,
    this.grow = 1,
    this.unlit = const Color(0xFFA2A9A3),
  });

  final bool lit;
  final double phase;
  final double grow;
  final Color unlit;

  static Path outer(Size s, double sway) {
    double x(double v) => v * s.width;
    double y(double v) => v * s.height;
    final tip = 0.5 + sway;
    return Path()
      ..moveTo(x(tip), y(0))
      ..cubicTo(x(0.62 + sway), y(0.2), x(0.98), y(0.38), x(0.94), y(0.66))
      ..cubicTo(x(0.91), y(0.88), x(0.72), y(1), x(0.5), y(1))
      ..cubicTo(x(0.27), y(1), x(0.06), y(0.86), x(0.06), y(0.62))
      ..cubicTo(x(0.06), y(0.46), x(0.16), y(0.36), x(0.27), y(0.27))
      ..cubicTo(x(0.26), y(0.4), x(0.32), y(0.49), x(0.4), y(0.52))
      ..cubicTo(x(0.36), y(0.32), x(0.42 + sway), y(0.14), x(tip), y(0))
      ..close();
  }

  static Path inner(Size s, double sway) {
    double x(double v) => v * s.width;
    double y(double v) => v * s.height;
    return Path()
      ..moveTo(x(0.52 - sway), y(0.42))
      ..cubicTo(x(0.6), y(0.56), x(0.74), y(0.66), x(0.72), y(0.8))
      ..cubicTo(x(0.7), y(0.93), x(0.6), y(1), x(0.5), y(1))
      ..cubicTo(x(0.38), y(1), x(0.28), y(0.93), x(0.28), y(0.8))
      ..cubicTo(x(0.28), y(0.66), x(0.44), y(0.56), x(0.52 - sway), y(0.42))
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = phase * 2 * math.pi;
    final sway = lit ? math.sin(t) * 0.025 + math.sin(t * 2.3) * 0.012 : 0.0;
    final stretch = lit ? 1 + math.sin(t * 1.7) * 0.035 : 1.0;

    canvas.save();
    // Grow and flicker from the base, like a real flame.
    canvas.translate(size.width / 2, size.height);
    canvas.scale(grow, grow * stretch);
    canvas.translate(-size.width / 2, -size.height);

    if (!lit) {
      canvas.drawPath(outer(size, 0), Paint()..color = unlit);
      canvas.drawPath(
        inner(size, 0),
        Paint()..color = unlit.withValues(alpha: 0.45),
      );
      canvas.restore();
      return;
    }
    final rect = Offset.zero & size;
    canvas.drawPath(
      outer(size, sway),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [FlameColors.mid, FlameColors.edge],
        ).createShader(rect),
    );
    canvas.drawPath(
      inner(size, sway * 1.6),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [FlameColors.core, FlameColors.mid],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(FlamePainter old) =>
      old.lit != lit ||
      old.phase != phase ||
      old.grow != grow ||
      old.unlit != unlit;
}

/// Flame and number for the top bar, like other streak apps: lit once
/// today counts. Tapping opens the streak week.
class StreakFlameCount extends ConsumerWidget {
  const StreakFlameCount({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(streakStateProvider);
    final c = context.colors;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: s.doneToday
          ? '${s.current} day streak, safe today'
          : '${s.current} day streak, finish a routine today to keep it',
      child: InkResponse(
        onTap: () => showStreakWeek(context),
        radius: 28,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreakFlame(lit: s.doneToday && s.current > 0, size: 24),
              const SizedBox(width: 5),
              Text(
                '${s.current}',
                style: context.text.titleMedium?.copyWith(
                  color: s.doneToday && s.current > 0 ? c.ink : c.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Monday-to-Sunday of this week as flames: lit = done, faint orange =
/// covered by a streak saver, grey = missed, fainter = still to come.
class StreakWeek extends ConsumerWidget {
  const StreakWeek({
    super.key,
    this.onDark = false,
    this.highlightToday = false,
  });

  final bool onDark;

  /// Ignite today's flame (the daily streak moment).
  final bool highlightToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = ref.watch(completedDaysProvider);
    final saved = ref.watch(streakStateProvider).savedDays;
    final today = Dates.startOfDay(clock.now());
    final monday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1),
    );
    final ink = onDark ? BrandColors.cream : context.colors.ink;
    final faint = onDark
        ? BrandColors.cream.withValues(alpha: 0.25)
        : context.colors.inkFaint.withValues(alpha: 0.6);
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          Builder(
            builder: (context) {
              final d = DateTime(monday.year, monday.month, monday.day + i);
              final key = Dates.dayKey(d);
              final isToday = Dates.dayKey(today) == key;
              final lit = done.contains(key);
              Widget flame = StreakFlame(
                lit: lit,
                size: 26,
                animate: isToday,
                unlitColor: saved.contains(key)
                    ? FlameColors.mid.withValues(alpha: 0.35)
                    : d.isAfter(today)
                    // Still to come: fainter than a missed day.
                    ? faint.withValues(alpha: faint.a * 0.4)
                    : faint,
              );
              if (isToday && lit && highlightToday) {
                flame = _Ignite(child: flame);
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  flame,
                  const SizedBox(height: 6),
                  Text(
                    letters[i],
                    style: context.text.labelMedium?.copyWith(
                      color: isToday ? ink : ink.withValues(alpha: 0.5),
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _Ignite extends StatelessWidget {
  const _Ignite({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.elasticOut,
      builder: (_, v, child) => Transform.scale(
        scale: 0.3 + 0.7 * v,
        alignment: Alignment.bottomCenter,
        child: child,
      ),
      child: child,
    );
  }
}

/// The daily moment when today's first routine keeps the streak alive:
/// the flame ignites, the number ticks up, the week fills in.
Future<void> showStreakExtended(BuildContext context, StreakState state) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: Motion.normal,
    pageBuilder: (_, _, _) => StreakExtendedCard(state: state),
    transitionBuilder: (_, a, _, child) =>
        FadeTransition(opacity: a, child: child),
  );
}

/// The card inside [showStreakExtended].
class StreakExtendedCard extends StatelessWidget {
  const StreakExtendedCard({super.key, required this.state});
  final StreakState state;

  @override
  Widget build(BuildContext context) {
    const cream = BrandColors.cream;
    final days = state.current;
    final line = days == 1
        ? 'Day one. Come back tomorrow to keep it lit.'
        : state.best <= days
        ? 'Your longest streak yet.'
        : 'Keep it lit tomorrow.';
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Material(
            color: BrandColors.charcoal,
            borderRadius: BorderRadius.circular(Radii.lg),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.xl,
                Space.lg,
                Space.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.elasticOut,
                    builder: (_, grow, _) => SizedBox(
                      width: 96,
                      height: 120,
                      child: grow < 1
                          ? CustomPaint(
                              painter: FlamePainter(lit: true, grow: grow),
                            )
                          : const StreakFlame(lit: true, size: 120),
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: math.max(0, days - 1).toDouble(),
                      end: days.toDouble(),
                    ),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => Text(
                      '${v.round()}',
                      style: context.text.displayMedium?.copyWith(
                        color: cream,
                        fontWeight: FontWeight.w300,
                        height: 1,
                      ),
                    ),
                  ),
                  Text(
                    'day streak',
                    style: context.text.titleMedium?.copyWith(
                      color: cream.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  const StreakWeek(onDark: true, highlightToday: true),
                  const SizedBox(height: Space.lg),
                  Text(
                    line,
                    textAlign: TextAlign.center,
                    style: context.text.bodyLarge?.copyWith(
                      color: cream.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: cream,
                        foregroundColor: BrandColors.charcoal,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Continue'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The streak week from the top bar: the flames, the numbers, and what
/// savers do.
Future<void> showStreakWeek(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (_) => const StreakWeekSheet(),
  );
}

/// The sheet inside [showStreakWeek].
class StreakWeekSheet extends ConsumerWidget {
  const StreakWeekSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(streakStateProvider);
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StreakFlame(lit: s.doneToday && s.current > 0, size: 40),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s.current} day streak',
                      style: context.text.titleLarge,
                    ),
                    Text(
                      s.current == 0
                          ? 'Finish a routine to light it.'
                          : s.doneToday
                          ? 'Safe for today.'
                          : 'Finish a routine today to keep it.',
                      style: context.text.bodyMedium?.copyWith(
                        color: s.doneToday ? c.inkMuted : c.warn,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          const StreakWeek(),
          const SizedBox(height: Space.lg),
          Text(
            'Best ${s.best} days'
            '${s.savers > 0 ? ' · ${s.savers} streak saver${s.savers == 1 ? '' : 's'}' : ''}',
            style: context.text.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Every ${Streaks.saverEvery} days in a row earns a streak saver '
            '(up to ${Streaks.maxSavers}). It covers one missed day for you.',
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }
}
