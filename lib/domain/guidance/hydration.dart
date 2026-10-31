import 'dart:convert';
import 'dart:math' as math;

import '../../data/models/profile.dart';

/// What the person told us for their water target. All optional: without a
/// weight the target falls back to the EFSA adequate intake for their sex.
class HydrationSettings {
  const HydrationSettings({
    this.weightKg,
    this.heightCm,
    this.activeMinutes = 0,
  });

  final double? weightKg;
  final double? heightCm;

  /// Minutes of sweaty exercise on a typical day.
  final int activeMinutes;

  bool get hasBody => weightKg != null;

  String encode() => jsonEncode({
    'weightKg': weightKg,
    'heightCm': heightCm,
    'activeMinutes': activeMinutes,
  });

  static HydrationSettings decode(String? raw) {
    if (raw == null) return const HydrationSettings();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return HydrationSettings(
        weightKg: (j['weightKg'] as num?)?.toDouble(),
        heightCm: (j['heightCm'] as num?)?.toDouble(),
        activeMinutes: (j['activeMinutes'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const HydrationSettings();
    }
  }
}

/// A day's drinking target and why it's that number.
class HydrationTarget {
  const HydrationTarget({required this.ml, required this.reasons});

  /// From drinks (food covers roughly another fifth of daily water).
  final int ml;
  final List<String> reasons;

  int get glasses => (ml / Hydration.glassMl).ceil();
}

/// Daily water from body size, activity, weather and pregnancy, using
/// mainstream nutrition guidance:
///  - 30–35 ml per kg of body weight a day in total water (we use 33), about
///    80% of it from drinks; with a BMI over 30 the weight is adjusted
///    towards a healthy one, since fat holds little water
///  - without a weight: EFSA's adequate intake, 2.0 L (women) / 2.5 L (men)
///    in total
///  - +500 ml per hour of sweaty exercise
///  - +250 ml from 25 °C, +500 ml from 30 °C, +250 ml in very dry air
///  - +300 ml when pregnant or nursing (EFSA; nursing needs more, ~700 ml)
abstract final class Hydration {
  static const glassMl = 250;

  static HydrationTarget target({
    required UserProfile profile,
    HydrationSettings settings = const HydrationSettings(),
    double? temperatureC,
    double? humidity,
  }) {
    final reasons = <String>[];
    double total;
    final w = settings.weightKg;
    if (w != null && w > 25) {
      var weight = w;
      final h = settings.heightCm;
      if (h != null && h > 100) {
        final m = h / 100;
        final bmi = w / (m * m);
        if (bmi > 30) {
          final healthy = 25 * m * m;
          weight = healthy + 0.25 * (w - healthy);
        }
      }
      total = 33 * weight;
      reasons.add('${w.round()} kg body weight');
    } else {
      total = profile.gender == Gender.man ? 2500 : 2000;
      reasons.add('Adult average (add your weight for yours)');
    }
    var drinks = total * 0.8;
    if (settings.activeMinutes > 0) {
      drinks += 500 * settings.activeMinutes / 60;
      reasons.add('${settings.activeMinutes} min of exercise');
    }
    if (temperatureC != null && temperatureC >= 30) {
      drinks += 500;
      reasons.add('${temperatureC.round()}°C today');
    } else if (temperatureC != null && temperatureC >= 25) {
      drinks += 250;
      reasons.add('${temperatureC.round()}°C today');
    }
    if (humidity != null && humidity < 30) {
      drinks += 250;
      reasons.add('Dry air today');
    }
    if (profile.pregnantOrNursing) {
      drinks += 300;
      reasons.add('Pregnancy or nursing');
    }
    final ml = (drinks.clamp(1200, 4000) / 50).round() * 50;
    return HydrationTarget(ml: ml, reasons: reasons);
  }

  /// Glasses still to go, spread over the waking hours left (08:00–22:00),
  /// so the nudge says "one now" rather than "six to go".
  static int dueBy(DateTime now, int goal) {
    final start = 8 * 60;
    final end = 22 * 60;
    final minute = now.hour * 60 + now.minute;
    final share = ((minute - start) / (end - start)).clamp(0.0, 1.0);
    return math.min(goal, (goal * share).floor());
  }
}
