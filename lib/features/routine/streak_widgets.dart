import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/routine/streaks.dart';
import '../../services/telemetry.dart';
import 'streak_flame.dart';

/// Today's streak: the number, the best, any savers, and the last two
/// weeks as tick marks (done, saved by a saver, or missed).
class StreakLine extends ConsumerWidget {
  const StreakLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(streakStateProvider);
    final done = ref.watch(completedDaysProvider);
    final c = context.colors;
    final yesterday = Dates.dayKey(
      clock.now().subtract(const Duration(days: 1)),
    );
    final atRisk = s.current > 0 && !s.doneToday;
    final detail = s.current == 0
        ? 'Finish a routine to light it'
        : atRisk
        ? 'Finish a routine today to keep it'
        : s.savedDays.contains(yesterday)
        ? 'A saver kept it going yesterday'
        : [
            if (s.best > s.current) 'Best ${s.best}',
            if (s.savers > 0)
              '${s.savers} streak saver${s.savers == 1 ? '' : 's'}',
            if (s.best <= s.current && s.current > 1) 'Your best yet',
          ].join(' · ');
    return Semantics(
      label: '${s.current} day streak. $detail',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          StreakFlame(lit: s.doneToday && s.current > 0, size: 34),
          const SizedBox(width: Space.xs),
          Text(
            '${s.current}',
            style: context.text.displaySmall?.copyWith(
              fontWeight: FontWeight.w200,
              height: 1,
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('day streak', style: context.text.titleSmall),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: context.text.bodySmall?.copyWith(
                      color: atRisk ? c.warn : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 120,
            height: 28,
            child: CustomPaint(
              painter: _DayTicks(
                done: done,
                saved: s.savedDays,
                ink: c.ink,
                faint: c.inkFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The last 14 days, oldest on the left: tall ink tick = done, tall faint
/// tick = covered by a saver, short tick = missed, open tick = today to go.
class _DayTicks extends CustomPainter {
  const _DayTicks({
    required this.done,
    required this.saved,
    required this.ink,
    required this.faint,
  });

  final Set<String> done;
  final Set<String> saved;
  final Color ink;
  final Color faint;

  static const days = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final today = Dates.startOfDay(clock.now());
    final gap = size.width / days;
    for (var i = 0; i < days; i++) {
      final d = DateTime(today.year, today.month, today.day - (days - 1 - i));
      final key = Dates.dayKey(d);
      final x = gap * i + gap / 2;
      final isToday = i == days - 1;
      final paint = Paint()
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      double h;
      if (done.contains(key)) {
        paint.color = ink;
        h = size.height;
      } else if (saved.contains(key)) {
        paint.color = ink.withValues(alpha: 0.35);
        h = size.height;
      } else if (isToday) {
        paint
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - 2, 0, 4, size.height),
            const Radius.circular(2),
          ),
          paint,
        );
        continue;
      } else {
        paint.color = faint.withValues(alpha: 0.5);
        h = size.height * 0.35;
      }
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DayTicks old) =>
      old.done != done || old.saved != saved || old.ink != ink;
}

/// One line for each milestone, in the voice of the app.
String streakLine(int days) => switch (days) {
  3 => 'Three days. The habit is forming.',
  7 => 'A full week. This is when skin starts to respond.',
  14 => 'Two weeks of showing up. Scan this week to see it.',
  21 => 'Three weeks. It\'s a habit now.',
  30 => 'A whole month. Time for your 30-day scan.',
  _ => '$days days. Your skin has noticed.',
};

/// The shareable streak card: the number, a ring of a month's ticks, and
/// the brand. Charcoal and cream, like every ClearSkin card.
class StreakCard extends StatelessWidget {
  const StreakCard({super.key, required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    const cream = BrandColors.cream;
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.lg),
        child: ColoredBox(
          color: BrandColors.charcoal,
          // Sized in card units; ignores the phone's text size, like the
          // result cards.
          child: MediaQuery.withNoTextScaling(
            child: LayoutBuilder(
              builder: (context, box) {
                final u = box.maxWidth / 100;
                TextStyle t(double size, {double a = 1, FontWeight? w}) =>
                    TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: size * u,
                      color: cream.withValues(alpha: a),
                      fontWeight: w ?? FontWeight.w400,
                      height: 1.1,
                      decoration: TextDecoration.none,
                    );
                return Padding(
                  padding: EdgeInsets.all(7 * u),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wordmark(size: 4.4 * u, color: cream),
                      ),
                      const Spacer(),
                      SizedBox.square(
                        dimension: 58 * u,
                        child: CustomPaint(
                          painter: _MonthRing(days: days, color: cream),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 9 * u,
                                  height: 11 * u,
                                  child: const CustomPaint(
                                    painter: FlamePainter(lit: true),
                                  ),
                                ),
                                SizedBox(height: 1.5 * u),
                                Text('$days', style: t(20, w: FontWeight.w200)),
                                SizedBox(height: 1 * u),
                                Text(
                                  'DAY STREAK',
                                  style: t(
                                    3,
                                    a: 0.6,
                                    w: FontWeight.w600,
                                  ).copyWith(letterSpacing: 0.5 * u),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 5 * u),
                      Text(
                        'Skincare, every day.',
                        style: t(4.6, w: FontWeight.w300),
                      ),
                      const Spacer(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text('Scan yours free', style: t(3, a: 0.6)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 30 ticks around a circle, one per day of the current month of the
/// streak; lit up to [days] (a full ring from day 30 on).
class _MonthRing extends CustomPainter {
  const _MonthRing({required this.days, required this.color});
  final int days;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const ticks = 30;
    final lit = days >= ticks ? ticks : days;
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    for (var i = 0; i < ticks; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / ticks;
      final dir = Offset(math.cos(a), math.sin(a));
      final on = i < lit;
      canvas.drawLine(
        c + dir * (r - (on ? r * 0.12 : r * 0.07)),
        c + dir * r,
        Paint()
          ..color = on ? color : color.withValues(alpha: 0.2)
          ..strokeWidth = on ? r * 0.035 : r * 0.022
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_MonthRing old) => old.days != days;
}

/// The milestone moment: the card, one line, the saver they earned (if
/// any), and a share button. Shown once per day at most.
Future<void> showStreakCelebration(
  BuildContext context, {
  required StreakState state,
}) {
  HapticFeedback.heavyImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: BrandColors.charcoal,
    builder: (_) => _Celebration(state: state),
  );
}

class _Celebration extends ConsumerStatefulWidget {
  const _Celebration({required this.state});
  final StreakState state;

  @override
  ConsumerState<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends ConsumerState<_Celebration> {
  final _card = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final obj = _card.currentContext?.findRenderObject();
      if (obj is! RenderRepaintBoundary) return;
      final image = await obj.toImage(pixelRatio: 1080 / obj.size.width);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'clearskin-streak.png'));
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text:
              '${widget.state.current} days of skincare in a row with ClearSkin AI.',
        ),
      );
      ref.read(telemetryProvider).track(Ev.shareCardShared, {
        'style': 'streak',
        'days': widget.state.current,
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const cream = BrandColors.cream;
    final s = widget.state;
    final earned = s.current % Streaks.saverEvery == 0 && s.savers > 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 260,
            child: RepaintBoundary(
              key: _card,
              child: StreakCard(days: s.current),
            ),
          ),
          const SizedBox(height: Space.lg),
          Text(
            streakLine(s.current),
            textAlign: TextAlign.center,
            style: context.text.titleLarge?.copyWith(
              color: cream,
              fontWeight: FontWeight.w300,
            ),
          ),
          if (earned) ...[
            const SizedBox(height: Space.xs),
            Text(
              'You earned a streak saver: miss a day and your streak stays.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(
                color: cream.withValues(alpha: 0.65),
              ),
            ),
          ],
          const SizedBox(height: Space.lg),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cream,
                foregroundColor: BrandColors.charcoal,
              ),
              onPressed: _busy ? null : _share,
              icon: const Icon(Icons.ios_share_rounded, size: 20),
              label: const Text('Share'),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: cream.withValues(alpha: 0.7),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
