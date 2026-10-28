import 'dart:math' as math;

import '../../data/models/scan.dart';

class MetricPotential {
  const MetricPotential(this.metric, this.now, this.potential);
  final SkinMetric metric;
  final int now;
  final int potential;
  int get gain => potential - now;
}

/// Where this skin can realistically get in 12 weeks of consistent care.
///
/// Not a promise and not AI guesswork: each measure has a share of its gap
/// to 100 that consistent, evidence-based care typically closes in about
/// three months (active breakouts and dehydration respond a lot; pores,
/// lines and genetic under-eye darkness much less). The overall potential
/// is the current score plus the average expected gain, so it's always
/// grounded in this person's actual scan.
class SkinPotential {
  const SkinPotential({
    required this.now,
    required this.potential,
    required this.metrics,
  });

  final int now;
  final int potential;
  final List<MetricPotential> metrics;

  int get gain => potential - now;

  /// The measures with the most room to improve, biggest first.
  List<MetricPotential> get biggestGains =>
      ([...metrics]..sort((a, b) => b.gain.compareTo(a.gain)))
          .where((m) => m.gain > 0)
          .toList();

  /// Typical share of the gap closed in ~12 weeks.
  static const responsiveness = <SkinMetric, double>{
    SkinMetric.acne: 0.6,
    SkinMetric.hydration: 0.65,
    SkinMetric.oilBalance: 0.5,
    SkinMetric.redness: 0.45,
    SkinMetric.texture: 0.4,
    SkinMetric.pigmentation: 0.4,
    SkinMetric.pores: 0.25,
    SkinMetric.underEyes: 0.2,
    SkinMetric.fineLines: 0.15,
  };

  /// Nobody's skin photographs at 100.
  static const ceiling = 96;

  static SkinPotential? of(SkinAnalysis a) {
    if (!a.usable || a.metrics.isEmpty) return null;
    final metrics = [
      for (final m in a.metrics)
        MetricPotential(
          m.metric,
          m.score,
          math.min(
            ceiling,
            m.score +
                ((100 - m.score) * (responsiveness[m.metric] ?? 0.3)).round(),
          ),
        ),
    ];
    final avgGain = metrics.fold<int>(0, (s, m) => s + m.gain) / metrics.length;
    return SkinPotential(
      now: a.overallScore,
      potential: math.min(
        ceiling,
        math.max(a.overallScore, (a.overallScore + avgGain).round()),
      ),
      metrics: metrics,
    );
  }
}
