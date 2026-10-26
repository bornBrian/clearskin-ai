import 'package:flutter/material.dart';

/// Design tokens — the single source of truth for the visual language.
///
/// Direction (from the brand references in /screens): airy sage-white
/// canvas, soft mint/cream glows, near-black pill actions, thin green data
/// rings, light large headlines, generous radii. Gender-neutral by design.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.line,
    required this.primary,
    required this.onPrimary,
    required this.primarySoft,
    required this.accent,
    required this.accentSoft,
    required this.leaf,
    required this.glowA,
    required this.glowB,
    required this.good,
    required this.warn,
    required this.bad,
    required this.info,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color line;

  /// Primary *action* colour: near-black pills (inverted in dark mode).
  final Color primary;
  final Color onPrimary;

  /// Sage tint for selected states and soft containers.
  final Color primarySoft;

  /// Brand green for highlights, links and positive emphasis.
  final Color accent;
  final Color accentSoft;

  /// Data colour for rings, charts and progress.
  final Color leaf;

  /// Ambient background glows.
  final Color glowA;
  final Color glowB;

  final Color good;
  final Color warn;
  final Color bad;
  final Color info;

  static const light = AppColors(
    background: Color(0xFFEEF2ED),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE4EAE2),
    ink: Color(0xFF151A17),
    inkMuted: Color(0xFF68706A),
    inkFaint: Color(0xFFA2A9A3),
    line: Color(0xFFE0E6DE),
    primary: Color(0xFF151A17),
    onPrimary: Color(0xFFFFFFFF),
    primarySoft: Color(0xFFDCE9DC),
    accent: Color(0xFF3F8F5A),
    accentSoft: Color(0xFFE2EFE3),
    leaf: Color(0xFF4E9A5F),
    glowA: Color(0xFFCFE6C8),
    glowB: Color(0xFFF3EECF),
    good: Color(0xFF3F8F5A),
    warn: Color(0xFFC7861F),
    bad: Color(0xFFC4513F),
    info: Color(0xFF4F7FA8),
  );

  static const dark = AppColors(
    background: Color(0xFF0E1210),
    surface: Color(0xFF171C19),
    surfaceAlt: Color(0xFF212823),
    ink: Color(0xFFEEF2EC),
    inkMuted: Color(0xFFA0A9A2),
    inkFaint: Color(0xFF66706A),
    line: Color(0xFF28312C),
    primary: Color(0xFFEEF2EC),
    onPrimary: Color(0xFF0E1210),
    primarySoft: Color(0xFF22332A),
    accent: Color(0xFF7CC495),
    accentSoft: Color(0xFF1C3225),
    leaf: Color(0xFF7CC495),
    glowA: Color(0xFF1C3A28),
    glowB: Color(0xFF16231C),
    good: Color(0xFF7CC495),
    warn: Color(0xFFE3AE55),
    bad: Color(0xFFE57A68),
    info: Color(0xFF85AFD6),
  );

  /// Maps a 0-100 "higher is better" score to a semantic colour.
  Color forScore(num score) {
    if (score >= 70) return leaf;
    if (score >= 50) return warn;
    return bad;
  }

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? ink,
    Color? inkMuted,
    Color? inkFaint,
    Color? line,
    Color? primary,
    Color? onPrimary,
    Color? primarySoft,
    Color? accent,
    Color? accentSoft,
    Color? leaf,
    Color? glowA,
    Color? glowB,
    Color? good,
    Color? warn,
    Color? bad,
    Color? info,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      inkFaint: inkFaint ?? this.inkFaint,
      line: line ?? this.line,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primarySoft: primarySoft ?? this.primarySoft,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      leaf: leaf ?? this.leaf,
      glowA: glowA ?? this.glowA,
      glowB: glowB ?? this.glowB,
      good: good ?? this.good,
      warn: warn ?? this.warn,
      bad: bad ?? this.bad,
      info: info ?? this.info,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      inkFaint: l(inkFaint, other.inkFaint),
      line: l(line, other.line),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      primarySoft: l(primarySoft, other.primarySoft),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
      leaf: l(leaf, other.leaf),
      glowA: l(glowA, other.glowA),
      glowB: l(glowB, other.glowB),
      good: l(good, other.good),
      warn: l(warn, other.warn),
      bad: l(bad, other.bad),
      info: l(info, other.info),
    );
  }
}

abstract final class Space {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  /// Horizontal page gutter.
  static const gutter = 20.0;

  /// Floating nav bar: height and gap to the bottom safe area.
  static const navHeight = 64.0;
  static const navBottomGap = 12.0;

  /// Bottom padding so the last item of a tab scrolls fully clear of the
  /// floating nav bar on every device (gesture bar, 3-button nav, notch).
  static double navClearance(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + navHeight + navBottomGap + xl;
}

/// Brand colours from the logo. Used for the mark, splash and dark hero
/// surfaces — never for data.
abstract final class BrandColors {
  static const charcoal = Color(0xFF232321);
  static const cream = Color(0xFFF3E6CA);
}

abstract final class Radii {
  static const sm = 14.0;
  static const md = 20.0;
  static const lg = 28.0;
  static const pill = 999.0;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 160);
  static const normal = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 480);
}

/// Very soft elevation used by cards: present, never heavy.
List<BoxShadow> softShadow(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark
      ? const []
      : [
          BoxShadow(
            color: const Color(0xFF1B2A1F).withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ];
}

const kFontFamily = 'PlusJakartaSans';

extension AppThemeX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
}
