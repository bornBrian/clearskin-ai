import '../../data/models/profile.dart';
import '../../data/models/scan.dart';
import 'skin_maps.dart';

/// A scan result built entirely on the phone, from what [SkinMaps] measured
/// in the photo's pixels. Used when the AI analysis can't be reached
/// (offline, outage), so a scan never ends in nothing.
///
/// It reads four of the nine metrics, the ones a photo's colour and light
/// can show honestly: redness, even tone, oil and texture. The rest need
/// the full analysis and are left out rather than guessed.
abstract final class OnDeviceAnalysis {
  static const model = 'on-device';

  /// Coverage (share of skin flagged) at which a lens scores its floor.
  /// Matched to the radiance "clarity" scale in [SkinMaps], where 12% of
  /// skin reading red or dark already looks visibly blotchy.
  static const _caps = {
    SkinLens.redness: 0.08,
    SkinLens.tone: 0.08,
    SkinLens.shine: 0.06,
    SkinLens.texture: 0.12,
  };

  static const _metric = {
    SkinLens.redness: SkinMetric.redness,
    SkinLens.tone: SkinMetric.pigmentation,
    SkinLens.shine: SkinMetric.oilBalance,
    SkinLens.texture: SkinMetric.texture,
  };

  /// 40..95: a photo alone never earns a perfect or a failing mark.
  static int score(SkinLens lens, double coverage) {
    final cap = _caps[lens]!;
    final clean = (1 - coverage / cap).clamp(0.0, 1.0);
    return (40 + 55 * clean).round();
  }

  static SkinAnalysis build(SkinMaps maps, UserProfile profile) {
    final metrics = <MetricScore>[
      for (final e in _metric.entries)
        if (maps.readings[e.key] case final r?)
          MetricScore(
            metric: e.value,
            score: score(e.key, r.coverage),
            note: _note(e.key, r),
          ),
    ];
    final avg = metrics.isEmpty
        ? maps.radiance.score
        : metrics.map((m) => m.score).reduce((a, b) => a + b) / metrics.length;
    final overall = (0.6 * avg + 0.4 * maps.radiance.score).round().clamp(
      0,
      100,
    );

    final sorted = [...metrics]..sort((a, b) => a.score.compareTo(b.score));
    final weak = sorted.where((m) => m.score < 65).toList();
    final strong = sorted.reversed.where((m) => m.score >= 80).toList();

    return SkinAnalysis(
      usable: true,
      qualityIssues: const [],
      overallScore: overall,
      metrics: metrics,
      skinTypeEstimate: profile.skinType.name,
      summary: _summary(weak, maps.radiance.score),
      strengths: [
        for (final m in strong.take(2)) '${m.metric.label} looks good',
      ],
      priorities: [for (final m in weak.take(3)) _priority(m.metric)],
      findings: const [],
      recommendedIngredients: _ingredients(weak),
      ingredientsToAvoid: const [],
      redFlags: const [],
      model: model,
      focus: weak.isEmpty
          ? (maps.radiance.score >= 70 ? SkinFocus.maintain : SkinFocus.glow)
          : SkinFocus.cure,
      disclaimer:
          'Measured on your phone from the colours and light in your photo, '
          'without the full analysis. It reads four things, not nine, and '
          'light can shift it. This is not medical advice.',
    );
  }

  static String _note(SkinLens lens, LensReading r) {
    final top = [...r.zones]..sort((a, b) => b.share.compareTo(a.share));
    final where = top.isEmpty || top.first.share < 0.02
        ? null
        : _zone(top.first.area);
    final pct = (r.coverage * 100).round();
    final what = switch (lens) {
      SkinLens.redness => 'redder than the skin around it',
      SkinLens.tone => 'darker than the skin around it',
      SkinLens.shine => 'shiny with oil',
      SkinLens.texture => 'uneven in texture',
      SkinLens.radiance => 'glowing',
    };
    if (pct == 0) return 'Very little of your skin reads $what.';
    return 'About $pct% of your skin reads $what'
        '${where == null ? '' : ', most on $where'}.';
  }

  static String _zone(String area) => switch (area) {
    'under_eyes' => 'your under-eyes',
    'upper_lip' => 'your upper lip',
    'jaw' => 'your jawline',
    final a => 'your $a',
  };

  static String _summary(List<MetricScore> weak, int glow) {
    if (weak.isEmpty) {
      return glow >= 70
          ? 'Your skin reads even and calm in this photo.'
          : 'Your skin reads calm; evenness and glow can still build.';
    }
    final names = weak.take(2).map((m) => m.metric.label.toLowerCase());
    return 'This photo shows the most room to improve in ${names.join(' and ')}.';
  }

  static String _priority(SkinMetric m) => switch (m) {
    SkinMetric.redness => 'Calm redness',
    SkinMetric.pigmentation => 'Even out dark marks',
    SkinMetric.oilBalance => 'Balance oil',
    SkinMetric.texture => 'Smooth texture',
    _ => m.label,
  };

  /// One per weak metric, most needed first, without repeats.
  static List<IngredientTip> _ingredients(List<MetricScore> weak) {
    final out = <IngredientTip>[];
    for (final m in weak.take(3)) {
      final tip = _ingredient(m.metric);
      if (tip != null && out.every((t) => t.name != tip.name)) out.add(tip);
    }
    return out;
  }

  static IngredientTip? _ingredient(SkinMetric m) => switch (m) {
    SkinMetric.redness => const IngredientTip(
      name: 'Azelaic acid',
      why: 'Calms redness and is gentle enough for most skin.',
    ),
    SkinMetric.pigmentation => const IngredientTip(
      name: 'Niacinamide',
      why: 'Helps fade marks and evens tone, alongside daily sunscreen.',
    ),
    SkinMetric.oilBalance => const IngredientTip(
      name: 'Niacinamide',
      why: 'Helps balance oil without drying the skin.',
    ),
    SkinMetric.texture => const IngredientTip(
      name: 'Salicylic acid',
      why: 'Clears inside pores and smooths rough patches.',
    ),
    _ => null,
  };
}
