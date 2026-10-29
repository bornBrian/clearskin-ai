import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/product.dart';
import '../theme/tokens.dart';

// Crafted, illustration-free visuals: drawn rather than stock, so the app
// has its own look instead of a template's.

// ── Score dial ──────────────────────────────────────────────────────────

/// A watch-style dial: fine ticks around the edge, lit up to the score, with
/// a large light number in the middle.
class ScoreDial extends StatelessWidget {
  const ScoreDial({
    super.key,
    required this.score,
    this.size = 200,
    this.color,
    this.trackColor,
    this.textColor,
    this.label,
    this.caption,
    this.ticks = 72,
  });

  final int score;
  final double size;
  final Color? color;
  final Color? trackColor;
  final Color? textColor;
  final String? label;
  final String? caption;
  final int ticks;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = textColor ?? c.ink;
    return Semantics(
      label: '${label ?? 'Skin score'} $score out of 100',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: score / 100),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _DialPainter(
              progress: t,
              color: color ?? c.forScore(score),
              track: trackColor ?? c.line,
              ticks: ticks,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (label != null)
                    Text(
                      label!.toUpperCase(),
                      style: context.text.labelSmall?.copyWith(
                        color: fg.withValues(alpha: 0.6),
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        fontSize: size < 150 ? 9 : 11,
                      ),
                    ),
                  Text(
                    '${(t * 100).round()}',
                    style: TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: size * 0.32,
                      fontWeight: FontWeight.w200,
                      letterSpacing: -size * 0.01,
                      height: 1.05,
                      color: fg,
                    ),
                  ),
                  if (caption != null)
                    Text(
                      caption!,
                      style: context.text.labelMedium?.copyWith(
                        color: fg.withValues(alpha: 0.6),
                        fontSize: size < 150 ? 11 : null,
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

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.ticks,
  });

  final double progress;
  final Color color;
  final Color track;
  final int ticks;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final lit = (progress * ticks).round();
    for (var i = 0; i < ticks; i++) {
      final a = -math.pi / 2 + i / ticks * math.pi * 2;
      final major = i % 6 == 0;
      final len = r * (major ? 0.11 : 0.075);
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        center + dir * (r - 1),
        center + dir * (r - 1 - len),
        Paint()
          ..color = i < lit ? color : track
          ..strokeWidth = major ? 2 : 1.4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

// ── Journey arc ─────────────────────────────────────────────────────────

/// Week boundaries of the four phases (Reset 1–2, Treat 3–6, Refine 7–10,
/// Glow 11–12): these ticks stand taller on the arc and the ruler.
const kPhaseBreaks = {0, 2, 6, 10, 12};

/// The top of a large, softly lit disc (from the "Day 1" reference) with the
/// twelve weeks marked on its rim like a dial: ticks lit up to [weeks], and
/// the current point marked by a longer tick under a soft light.
class JourneyArc extends StatelessWidget {
  const JourneyArc({
    super.key,
    required this.weeks,
    this.height = 120,
    this.color = Colors.white,
  });

  /// Position along the programme, 0 (day 1) to 12.
  final double weeks;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: weeks <= 0 ? 'Day 1' : 'Week ${weeks.ceil()} of 12',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: weeks),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
          builder: (_, w, _) => CustomPaint(
            painter: _ArcPainter(weeks: w, color: color),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.weeks, required this.color});

  final double weeks;
  final Color color;

  // Kept inside the screen's width so day 1 and week 12 are both visible.
  static const _start = math.pi * 1.32;
  static const _span = math.pi * 0.36;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final r = w * 0.78;
    final center = Offset(w / 2, size.height * 0.62 + r);
    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.34),
            color.withValues(alpha: 0.1),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.3, 0.75],
        ).createShader(rect),
    );

    Offset on(double a, double radius) =>
        center + Offset(math.cos(a), math.sin(a)) * radius;
    final t = (weeks / 12).clamp(0.0, 1.0);
    final here = _start + _span * t;

    // Rim: travelled part a touch brighter than the road ahead.
    canvas.drawArc(
      rect,
      math.pi * 1.1,
      _start - math.pi * 1.1,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (t > 0) {
      canvas.drawArc(
        rect,
        _start,
        here - _start,
        false,
        Paint()
          ..color = color.withValues(alpha: 0.95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
    canvas.drawArc(
      rect,
      here,
      math.pi * 1.9 - here,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    for (var i = 0; i <= 12; i++) {
      final a = _start + _span * i / 12;
      final major = kPhaseBreaks.contains(i);
      final len = major ? 11.0 : 6.0;
      canvas.drawLine(
        on(a, r + 3),
        on(a, r + 3 + len),
        Paint()
          ..color = color.withValues(alpha: i <= weeks + 0.01 ? 0.95 : 0.42)
          ..strokeWidth = major ? 1.6 : 1.2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Where you are: a soft light on the rim and one long tick through it.
    canvas.drawCircle(
      on(here, r),
      30,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawLine(
      on(here, r - 10),
      on(here, r + 26),
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.weeks != weeks || old.color != color;
}

/// Twelve weeks as a fine ruler: a tick per week, lit up to [week], the
/// current week standing tallest, phase starts a little taller than the
/// rest. Optional [labels] name the phases under their weeks.
class WeekRuler extends StatelessWidget {
  const WeekRuler({
    super.key,
    required this.week,
    this.complete = false,
    this.color,
    this.labels,
  });

  /// Current week, 1–12.
  final int week;
  final bool complete;
  final Color? color;

  /// (name, first week, last week) per phase.
  final List<(String, int, int)>? labels;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? context.colors.ink;
    final current = complete ? 13 : week;
    return Semantics(
      label: complete ? 'Plan complete' : 'Week $week of 12',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 20,
            child: CustomPaint(
              painter: _RulerPainter(week: current, color: ink),
            ),
          ),
          if (labels != null) ...[
            const SizedBox(height: Space.xs),
            Row(
              children: [
                for (final (name, first, last) in labels!)
                  Expanded(
                    flex: last - first + 1,
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: context.text.labelMedium?.copyWith(
                        color: ink.withValues(
                          alpha: current >= first && current <= last ? 1 : 0.5,
                        ),
                        fontWeight: current >= first && current <= last
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.week, required this.color});
  final int week;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / 12;
    final base = size.height;
    canvas.drawLine(
      Offset(0, base - 0.5),
      Offset(size.width, base - 0.5),
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..strokeWidth = 1,
    );
    for (var i = 1; i <= 12; i++) {
      // Ticks sit at the start of each week's slot, so phase labels line up
      // with the tick that opens them.
      final x = (i - 1) * slot + 0.75;
      final now = i == week;
      final h = now
          ? size.height
          : kPhaseBreaks.contains(i - 1)
          ? size.height * 0.55
          : size.height * 0.35;
      canvas.drawLine(
        Offset(x, base),
        Offset(x, base - h),
        Paint()
          ..color = color.withValues(alpha: i <= week ? 0.9 : 0.28)
          ..strokeWidth = now ? 1.8 : 1.1,
      );
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.week != week || old.color != color;
}

/// Soft vertical wash used behind journey moments. [tone] 0–3 shifts from
/// sage to mint to cream to sand as the journey moves on.
class JourneyBackdrop extends StatelessWidget {
  const JourneyBackdrop({super.key, required this.child, this.tone = 0});
  final Widget child;
  final double tone;

  static const _tops = [
    Color(0xFFBFD9C6),
    Color(0xFFC9E2D6),
    Color(0xFFE6DDC4),
    Color(0xFFE9D3C3),
  ];

  @override
  Widget build(BuildContext context) {
    final i = tone.clamp(0, _tops.length - 1).toDouble();
    final lo = i.floor();
    final hi = math.min(lo + 1, _tops.length - 1);
    final top = Color.lerp(_tops[lo], _tops[hi], i - lo)!;
    final bg = context.colors.background;
    return AnimatedContainer(
      duration: Motion.slow,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.55, 1],
          colors: [top, Color.lerp(top, bg, 0.7)!, bg],
        ),
      ),
      child: child,
    );
  }
}

// ── Product glyphs ──────────────────────────────────────────────────────

enum _Vessel { tube, dropper, jar, pump }

_Vessel _vesselFor(ProductCategory c) => switch (c) {
  ProductCategory.cleanser ||
  ProductCategory.sunscreen ||
  ProductCategory.shaving => _Vessel.tube,
  ProductCategory.serum ||
  ProductCategory.treatment ||
  ProductCategory.exfoliant ||
  ProductCategory.toner => _Vessel.dropper,
  ProductCategory.moisturizer ||
  ProductCategory.mask ||
  ProductCategory.eyeCream => _Vessel.jar,
  ProductCategory.makeup || ProductCategory.other => _Vessel.pump,
};

/// Fine line drawing of the product's container (tube, dropper, jar, pump).
class ProductGlyph extends StatelessWidget {
  const ProductGlyph({
    super.key,
    required this.category,
    this.size = 56,
    this.color,
  });

  final ProductCategory category;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _GlyphPainter(
        _vesselFor(category),
        color ?? context.colors.ink.withValues(alpha: 0.7),
      ),
    ),
  );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.vessel, this.color);
  final _Vessel vessel;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.1, s * 0.022)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    RRect rr(double l, double t, double r, double b, double rad) =>
        RRect.fromLTRBR(l * s, t * s, r * s, b * s, Radius.circular(rad * s));

    switch (vessel) {
      case _Vessel.tube:
        final body = Path()
          ..moveTo(0.34 * s, 0.14 * s)
          ..lineTo(0.66 * s, 0.14 * s)
          ..lineTo(0.62 * s, 0.70 * s)
          ..lineTo(0.38 * s, 0.70 * s)
          ..close();
        canvas.drawPath(body, p);
        canvas.drawRRect(rr(0.40, 0.70, 0.60, 0.86, 0.03), p);
        canvas.drawLine(
          Offset(0.36 * s, 0.22 * s),
          Offset(0.64 * s, 0.22 * s),
          p,
        );
      case _Vessel.dropper:
        canvas.drawRRect(rr(0.32, 0.42, 0.68, 0.88, 0.06), p);
        canvas.drawRRect(rr(0.40, 0.30, 0.60, 0.42, 0.02), p);
        canvas.drawRRect(rr(0.44, 0.10, 0.56, 0.30, 0.06), p);
        canvas.drawLine(
          Offset(0.32 * s, 0.56 * s),
          Offset(0.68 * s, 0.56 * s),
          p,
        );
      case _Vessel.jar:
        canvas.drawRRect(rr(0.24, 0.46, 0.76, 0.84, 0.08), p);
        canvas.drawRRect(rr(0.22, 0.34, 0.78, 0.46, 0.03), p);
        canvas.drawLine(
          Offset(0.24 * s, 0.60 * s),
          Offset(0.76 * s, 0.60 * s),
          p,
        );
      case _Vessel.pump:
        canvas.drawRRect(rr(0.33, 0.40, 0.67, 0.88, 0.07), p);
        canvas.drawRRect(rr(0.43, 0.28, 0.57, 0.40, 0.02), p);
        final head = Path()
          ..moveTo(0.50 * s, 0.28 * s)
          ..lineTo(0.50 * s, 0.16 * s)
          ..lineTo(0.70 * s, 0.16 * s);
        canvas.drawPath(head, p);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.vessel != vessel || old.color != color;
}

// ── Check circle ────────────────────────────────────────────────────────

/// Round toggle used for routine steps: hairline when open, ink when done.
class CheckCircle extends StatelessWidget {
  const CheckCircle({
    super.key,
    required this.done,
    required this.onTap,
    this.size = 34,
    this.label,
  });

  final bool done;
  final VoidCallback onTap;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      checked: done,
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: done ? c.primary : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: done ? c.primary : c.inkFaint.withValues(alpha: 0.6),
                width: 1.3,
              ),
            ),
            child: AnimatedOpacity(
              duration: Motion.fast,
              opacity: done ? 1 : 0,
              child: Icon(
                Icons.check_rounded,
                size: size * 0.55,
                color: c.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two-to-four big text tabs ("Morning  Evening"): the selected one in ink,
/// the rest faint. Editorial, no pill container.
class TextTabs extends StatelessWidget {
  const TextTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.style,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = style ?? context.text.headlineSmall;
    // Wraps instead of overflowing on narrow phones or large text.
    return Wrap(
      runSpacing: Space.xs,
      children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: Space.lg),
            child: Semantics(
              button: true,
              selected: i == index,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedDefaultTextStyle(
                  duration: Motion.fast,
                  style: base!.copyWith(
                    color: i == index ? c.ink : c.inkFaint,
                    fontWeight: i == index ? FontWeight.w400 : FontWeight.w300,
                  ),
                  child: Text(labels[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
