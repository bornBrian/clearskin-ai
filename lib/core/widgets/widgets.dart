import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/ingredients/product_analyzer.dart';
import '../providers.dart';
import '../theme/tokens.dart';

import 'visuals.dart';

export 'visuals.dart';

// ── Surfaces ────────────────────────────────────────────────────────────

/// Calm page background: a single soft sage wash from the top-right.
class AuraBackground extends StatelessWidget {
  const AuraBackground({super.key, required this.child, this.intensity = 1});
  final Widget child;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = MediaQuery.sizeOf(context);
    return Material(
      color: c.background,
      child: Stack(
        children: [
          Positioned(
            top: -size.width * 0.7,
            right: -size.width * 0.5,
            child: IgnorePointer(
              child: Container(
                width: size.width * 1.5,
                height: size.width * 1.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      c.glowA.withValues(alpha: 0.55 * intensity.clamp(0, 1.4)),
                      c.glowA.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.md + 2),
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = Radii.lg,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget card(ValueChanged<bool>? onHighlight) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: color == null ? softShadow(context) : null,
      ),
      child: Material(
        color: color ?? c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: borderColor == null
              ? BorderSide.none
              : BorderSide(color: borderColor!),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onHighlightChanged: onHighlight,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    // Only cards you can tap press in; a large surface moves less.
    return onTap == null ? card(null) : PressScale(scale: 0.985, builder: card);
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm, top: Space.xs),
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.text.titleLarge)),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Row(
                children: [
                  Text(
                    action!,
                    style: context.text.labelLarge?.copyWith(
                      color: context.colors.accent,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: context.colors.accent,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Large light page title used at the top of every tab.
class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.md,
        Space.gutter,
        Space.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.displaySmall),
                if (subtitle != null) ...[
                  const SizedBox(height: Space.xxs),
                  Text(subtitle!, style: context.text.bodyMedium),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ── Buttons ─────────────────────────────────────────────────────────────

/// White pill with a label and a black circular arrow — the signature CTA.
class ArrowPill extends StatelessWidget {
  const ArrowPill({
    super.key,
    required this.label,
    required this.onTap,
    this.dark = false,
    this.icon = Icons.arrow_forward_rounded,
  });

  final String label;
  final VoidCallback? onTap;
  final bool dark;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = dark ? c.primary : c.surface;
    final fg = dark ? c.onPrimary : c.ink;
    final circleBg = dark ? c.onPrimary : c.primary;
    final circleFg = dark ? c.primary : c.onPrimary;
    return Semantics(
      button: true,
      label: label,
      child: PressScale(
        builder: (onHighlight) => Material(
          color: bg,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onHighlightChanged: onHighlight,
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    onTap!();
                  },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 7, 7, 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: context.text.titleMedium?.copyWith(color: fg),
                    ),
                  ),
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: circleBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: circleFg, size: 22),
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

/// Round white icon button (top-right actions in the references).
class CircleButton extends StatelessWidget {
  const CircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 46,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Unfilled: just the icon and its press, no bubble behind it.
    final button = PressScale(
      scale: 0.9,
      builder: (onHighlight) => Material(
        color: filled ? c.primary : Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onHighlightChanged: onHighlight,
          child: SizedBox.square(
            dimension: size,
            child: Icon(
              icon,
              size: size * 0.45,
              color: filled ? c.onPrimary : c.ink,
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

// ── Data visualisation ──────────────────────────────────────────────────

/// Animated thin ring with a large light number — the main score display.
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.score,
    this.size = 140,
    this.stroke = 7,
    this.label,
    this.caption,
    this.suffix = '',
  });

  final int score;
  final double size;
  final double stroke;
  final String? label;

  /// Quiet one-liner under the number. Never a +/- badge.
  final String? caption;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = c.forScore(score);
    return Semantics(
      label: '${label ?? 'Skin score'} $score out of 100',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: score / 100),
        duration: Motion.slow * 2,
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: RingPainter(
              progress: t,
              color: color,
              track: c.surfaceAlt,
              stroke: stroke,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (label != null)
                    Text(label!, style: context.text.labelSmall),
                  Text(
                    '${(t * 100).round()}$suffix',
                    style: context.text.displayMedium?.copyWith(
                      fontSize: size * 0.3,
                      height: 1.05,
                    ),
                  ),
                  if (caption != null)
                    Text(caption!, style: context.text.labelSmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RingPainter extends CustomPainter {
  RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double progress;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

class MetricBar extends StatelessWidget {
  const MetricBar({
    super.key,
    required this.label,
    required this.score,
    this.note,
    this.delta,
  });

  final String label;
  final int score;
  final String? note;
  final int? delta;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = c.forScore(score);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: context.text.titleSmall)),
              if (delta != null && delta != 0)
                Padding(
                  padding: const EdgeInsets.only(right: Space.xs),
                  child: Text(
                    '${delta! > 0 ? '+' : ''}$delta',
                    style: context.text.labelMedium?.copyWith(
                      color: delta! > 0 ? c.good : c.bad,
                    ),
                  ),
                ),
              Text(
                '$score',
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: score / 100),
              duration: Motion.slow,
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 5,
                backgroundColor: c.surfaceAlt,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          if (note != null && note!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(note!, style: context.text.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// One plain word for a 0–100 score, so a number never stands alone.
String scoreWord(int v) => v >= 85
    ? 'Excellent'
    : v >= 70
    ? 'Good'
    : v >= 55
    ? 'Fair'
    : 'Needs care';

/// Label, a large light number and one quiet word. Typography only — no
/// bars, rings or colour coding.
class MiniMetric extends StatelessWidget {
  const MiniMetric({super.key, required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value, ${scoreWord(value)}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.text.labelMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          CountUp(
            value,
            style: context.text.headlineMedium?.copyWith(
              fontWeight: FontWeight.w300,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(scoreWord(value), style: context.text.bodySmall),
        ],
      ),
    );
  }
}

/// Dark or light square stat tile ("Your skin health 75%" / "Last scan").
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.dark = false,
    this.onTap,
  });

  final String label;
  final String value;
  final bool dark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = dark ? c.onPrimary : c.ink;
    return AppCard(
      onTap: onTap,
      color: dark ? c.primary : c.surfaceAlt.withValues(alpha: 0.6),
      radius: Radii.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.text.labelMedium?.copyWith(
              color: fg.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: Space.lg),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: context.text.headlineMedium?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Brand ───────────────────────────────────────────────────────────────

// Proportions match scripts/brand/generate_brand.py.
const _kRingRadius = 0.40; // centre-line radius, of box size
const _kGap = 78 * math.pi / 180; // opening on the right
const _kStrokeMax = 0.062; // fullest weight, at the lower left
const _kStrokeMin = 0.010; // hairline at the tips
const _kHeavy = 155 * math.pi / 180; // where the stroke is fullest

/// The ClearSkin "C": a calligraphic open stroke, hairline at the tips and
/// fullest at the lower left. Use [BrandMark] where the word fits.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 32, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(
          color ?? context.colors.ink,
          // Small marks need more weight to stay crisp.
          weight: size < 48 ? 1.8 : 1,
        ),
      ),
    );
  }
}

/// The full mark from the app icon: the "C" ring holding the word "skin".
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 120, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.ink;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(c, weight: size < 80 ? 1.5 : 1),
        child: Align(
          alignment: const Alignment(0.16, 0),
          child: Text(
            'skin',
            style: TextStyle(
              fontFamily: kFontFamily,
              fontSize: size * 0.27,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.2,
              height: 1,
              color: c,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color, {this.weight = 1});
  final Color color;

  /// Multiplies the stroke weight (heavier for tiny sizes).
  final double weight;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final r = _kRingRadius * s;
    final c = Offset(s / 2, s / 2);
    const steps = 120;
    final outer = <Offset>[];
    final inner = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final a = _kGap / 2 + (math.pi * 2 - _kGap) * i / steps;
      final t = math.pow((1 + math.cos(a - _kHeavy)) / 2, 1.6);
      final w = math.max(
        0.6,
        (_kStrokeMin + (_kStrokeMax - _kStrokeMin) * t) * weight * s / 2,
      );
      final dir = Offset(math.cos(a), math.sin(a));
      outer.add(c + dir * (r + w));
      inner.add(c + dir * (r - w));
    }
    canvas.drawPath(
      Path()..addPolygon([...outer, ...inner.reversed], true),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.weight != weight;
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 22, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.ink;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LogoMark(size: size * 1.25, color: c),
        SizedBox(width: size * 0.25),
        Text(
          'clearskin',
          style: TextStyle(
            fontFamily: kFontFamily,
            fontSize: size,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.4,
            color: c,
            height: 1,
          ),
        ),
      ],
    );
  }
}

// ── Photography ─────────────────────────────────────────────────────────

/// Editorial photography bundled with the app (Unsplash License; see
/// docs/PHOTO_CREDITS.md). One place to swap in a brand shoot later.
abstract final class Photos {
  static const _dir = 'assets/images/photos';

  /// The only portraits in the app, on the sign-in screen. Women and men,
  /// different skin tones; they slide from one to the next, in this order.
  static const auth = '$_dir/auth.webp';
  static const auth2 = '$_dir/auth_2.webp';
  static const auth3 = '$_dir/auth_3.webp';
  static const auth4 = '$_dir/auth_4.webp';
  static const auth5 = '$_dir/auth_5.webp';
  static const authPortraits = [auth2, auth3, auth, auth4, auth5];

  static const sageWaves = '$_dir/sage_waves.webp';
  static const leafShadow = '$_dir/leaf_shadow.webp';
  static const palmShadow = '$_dir/palm_shadow.webp';
  static const plantWall = '$_dir/plant_wall.webp';
  static const warmShadow = '$_dir/warm_shadow.webp';
  static const creamFabric = '$_dir/cream_fabric.webp';
  static const water = '$_dir/water.webp';
  static const droplets = '$_dir/droplets.webp';
  static const leafDew = '$_dir/leaf_dew.webp';
  static const dropperClear = '$_dir/dropper_clear.webp';
  static const dropperAmber = '$_dir/dropper_amber.webp';
  static const serumPink = '$_dir/serum_pink.webp';
  static const botanicals = '$_dir/botanicals.webp';
  static const serumPour = '$_dir/serum_pour.webp';
  static const serumPlates = '$_dir/serum_plates.webp';
  static const textures = '$_dir/textures.webp';
  static const creamBeige = '$_dir/cream_beige.webp';
  static const creamWhite = '$_dir/cream_white.webp';
  static const gelSwirl = '$_dir/gel_swirl.webp';
}

/// Full-bleed photo with a soft bottom scrim for legible white text.
class PhotoFill extends StatelessWidget {
  const PhotoFill(
    this.asset, {
    super.key,
    this.alignment = Alignment.center,
    this.scrim = 0.55,
    this.scrimStart = 0.35,
    this.scrimColor = Colors.black,
  });

  final String asset;
  final Alignment alignment;

  /// Colour the photo fades into, e.g. the surface it sits on.
  final Color scrimColor;

  /// Opacity at the bottom of the scrim (0 = none).
  final double scrim;

  /// Where (0 top – 1 bottom) the scrim starts fading in.
  final double scrimStart;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: alignment,
          errorBuilder: (_, _, _) =>
              ColoredBox(color: context.colors.surfaceAlt),
        ),
        if (scrim > 0)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [scrimStart, 1],
                colors: [
                  scrimColor.withValues(alpha: 0),
                  scrimColor.withValues(alpha: scrim),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Rounded editorial photo card with an optional eyebrow and a title.
class PhotoCard extends StatelessWidget {
  const PhotoCard({
    super.key,
    required this.asset,
    required this.title,
    this.eyebrow,
    this.onTap,
    this.height = 220,
    this.width,
    this.alignment = Alignment.center,
    this.trailing,
  });

  final String asset;
  final String title;
  final String? eyebrow;
  final VoidCallback? onTap;
  final double height;
  final double? width;
  final Alignment alignment;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: Material(
        borderRadius: BorderRadius.circular(Radii.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PhotoFill(asset, alignment: alignment, scrimStart: 0.3),
              Padding(
                padding: const EdgeInsets.all(Space.md + 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    if (eyebrow != null) ...[
                      Eyebrow(
                        eyebrow!,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w400,
                              height: 1.2,
                            ),
                          ),
                        ),
                        ?trailing,
                      ],
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

/// A row separated by hairlines — the calm alternative to chips and pills.
class LineItem extends StatelessWidget {
  const LineItem({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.divider = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: divider
              ? Border(bottom: BorderSide(color: context.colors.line))
              : null,
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: Space.sm)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: context.text.bodySmall),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Small spaced uppercase label above a section or value.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: context.text.labelSmall?.copyWith(
      letterSpacing: 1.2,
      fontWeight: FontWeight.w600,
      color: color ?? context.colors.inkMuted,
    ),
  );
}

// ── Small parts ─────────────────────────────────────────────────────────

/// Quiet label: hairline outline, no tinted fill, no icon by default.
/// A colour, when given, only tints the text.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon, this.solid = false});
  final String text;
  final Color? color;
  final IconData? icon;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = solid ? c.onPrimary : (color ?? c.inkMuted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: solid ? c.primary : null,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: solid ? null : Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: context.text.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Large tappable option used in onboarding and settings.
class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.multi = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs + 2),
      child: Semantics(
        selected: selected,
        button: true,
        child: AnimatedContainer(
          duration: Motion.fast,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: selected ? c.ink : Colors.transparent,
              width: 1.4,
            ),
            boxShadow: selected ? null : softShadow(context),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.md),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md + 2,
                vertical: 16,
              ),
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: Space.sm),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: context.text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: context.text.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  AnimatedContainer(
                    duration: Motion.fast,
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: selected ? c.primary : Colors.transparent,
                      shape: multi ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: multi ? BorderRadius.circular(7) : null,
                      border: Border.all(
                        color: selected ? c.primary : c.inkFaint,
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: c.onPrimary,
                          )
                        : null,
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

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                boxShadow: softShadow(context),
              ),
              child: Icon(icon, size: 30, color: c.ink),
            ),
            const SizedBox(height: Space.lg),
            Text(
              title,
              style: context.text.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.xs),
            Text(
              body,
              style: context.text.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: Space.lg),
              ArrowPill(label: actionLabel!, onTap: onAction, dark: true),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows a loading spinner / error / data for an AsyncValue.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.data});
  final AsyncValue<T> value;
  final Widget Function(T) data;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Text(
            'Something went wrong loading this.\n$e',
            textAlign: TextAlign.center,
            style: context.text.bodyMedium,
          ),
        ),
      ),
    );
  }
}

class Disclaimer extends StatelessWidget {
  const Disclaimer({super.key, this.text});
  final String? text;

  @override
  Widget build(BuildContext context) {
    // Quiet fine print: always there, never competing with the content.
    return Text(
      text ?? 'Cosmetic guidance, not a diagnosis. For painful, spreading or changing spots, see a dermatologist.',
      style: context.text.bodySmall?.copyWith(
        color: context.colors.inkFaint,
        fontSize: 12,
        height: 1.4,
      ),
    );
  }
}

/// Wraps premium content: shows it to subscribers, a teaser with an upgrade
/// CTA to everyone else.
class PremiumGate extends ConsumerWidget {
  const PremiumGate({
    super.key,
    required this.child,
    required this.feature,
    this.teaser,
  });

  final Widget child;
  final String feature;
  final Widget? teaser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(premiumProvider)) return child;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (teaser != null) ...[teaser!, const SizedBox(height: Space.md)],
          ArrowPill(
            label: 'Unlock with Premium',
            icon: Icons.lock_open_rounded,
            dark: true,
            onTap: () => context.push('/paywall?source=$feature'),
          ),
        ],
      ),
    );
  }
}

extension SeverityStyle on FlagSeverity {
  Color color(AppColors c) => switch (this) {
    FlagSeverity.high => c.bad,
    FlagSeverity.medium => c.warn,
    FlagSeverity.low => c.info,
    FlagSeverity.info => c.inkMuted,
  };

  IconData get icon => switch (this) {
    FlagSeverity.high => Icons.error_outline_rounded,
    FlagSeverity.medium => Icons.warning_amber_rounded,
    FlagSeverity.low => Icons.info_outline_rounded,
    FlagSeverity.info => Icons.info_outline_rounded,
  };
}

extension VerdictStyle on Verdict {
  Color color(AppColors c) => switch (this) {
    Verdict.great => c.good,
    Verdict.good => c.leaf,
    Verdict.caution => c.warn,
    Verdict.avoid => c.bad,
    Verdict.unknown => c.inkMuted,
  };
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final c = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: c.bad)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
