import 'dart:convert';

import '../../domain/scan/face_zones.dart';
import '../../domain/scan/skin_maps.dart';
import '../../domain/scan/skin_measure.dart';

/// Visible skin attributes scored by the analysis. Every score is 0-100 where
/// HIGHER IS BETTER (e.g. acne 90 = very few blemishes), so charts and colors
/// read consistently.
enum SkinMetric {
  acne('Blemishes', 'acne'),
  texture('Texture', 'texture'),
  pores('Pores', 'pores'),
  redness('Redness', 'redness'),
  pigmentation('Even tone', 'pigmentation'),
  hydration('Hydration', 'hydration'),
  oilBalance('Oil balance', 'oil_balance'),
  fineLines('Smoothness', 'fine_lines'),
  underEyes('Under-eyes', 'under_eyes');

  const SkinMetric(this.label, this.key);
  final String label;

  /// Wire key used by the backend JSON schema.
  final String key;

  static SkinMetric? fromKey(String key) =>
      values.where((m) => m.key == key).firstOrNull;
}

enum FlagUrgency { routine, soon, urgent }

class MetricScore {
  const MetricScore({
    required this.metric,
    required this.score,
    required this.note,
  });

  final SkinMetric metric;
  final int score;
  final String note;

  Map<String, Object?> toJson() => {
    'metric': metric.key,
    'score': score,
    'note': note,
  };
}

class Finding {
  const Finding({
    required this.title,
    required this.detail,
    required this.area,
    required this.severity,
  });

  final String title;
  final String detail;
  final String area;

  /// 1 (mild) .. 3 (pronounced)
  final int severity;

  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'area': area,
    'severity': severity,
  };

  factory Finding.fromJson(Map<String, dynamic> j) => Finding(
    title: j['title'] as String? ?? '',
    detail: j['detail'] as String? ?? '',
    area: j['area'] as String? ?? 'overall',
    severity: ((j['severity'] as num?)?.toInt() ?? 1).clamp(1, 3),
  );
}

class IngredientTip {
  const IngredientTip({required this.name, required this.why});
  final String name;
  final String why;

  Map<String, Object?> toJson() => {'name': name, 'why': why};
  factory IngredientTip.fromJson(Map<String, dynamic> j) => IngredientTip(
    name: j['name'] as String? ?? '',
    why: j['why'] as String? ?? '',
  );
}

class RedFlag {
  const RedFlag({
    required this.title,
    required this.detail,
    required this.urgency,
  });

  final String title;
  final String detail;
  final FlagUrgency urgency;

  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'urgency': urgency.name,
  };

  factory RedFlag.fromJson(Map<String, dynamic> j) => RedFlag(
    title: j['title'] as String? ?? '',
    detail: j['detail'] as String? ?? '',
    urgency:
        FlagUrgency.values.where((u) => u.name == j['urgency']).firstOrNull ??
        FlagUrgency.routine,
  );
}

/// The structured result of one AI skin analysis.
class SkinAnalysis {
  const SkinAnalysis({
    required this.usable,
    required this.qualityIssues,
    required this.overallScore,
    required this.metrics,
    required this.skinTypeEstimate,
    required this.summary,
    required this.strengths,
    required this.priorities,
    required this.findings,
    required this.recommendedIngredients,
    required this.ingredientsToAvoid,
    required this.redFlags,
    required this.model,
    this.focus,
    this.routineAdjustments = const [],
    this.ingredientWarnings = const [],
    this.recommendedProductTypes = const [],
    this.beyondProducts = const [],
    this.disclaimer = defaultDisclaimer,
  });

  /// Shown on every report. The server sends the canonical wording; this
  /// copy covers scans stored before it did.
  static const defaultDisclaimer =
      'This tracking log is powered by AI and does not constitute medical '
      'advice. Please consult a registered dermatologist for clinical '
      'concerns.';

  /// False when the photo can't be assessed reliably (blur, filters, heavy
  /// makeup, bad light). Such scans are kept out of trend charts.
  final bool usable;
  final List<String> qualityIssues;
  final int overallScore;
  final List<MetricScore> metrics;
  final String skinTypeEstimate;
  final String summary;
  final List<String> strengths;
  final List<String> priorities;
  final List<Finding> findings;
  final List<IngredientTip> recommendedIngredients;
  final List<IngredientTip> ingredientsToAvoid;
  final List<RedFlag> redFlags;
  final String model;

  /// What this skin needs most right now: clear a concern, build glow, or
  /// keep what's working. Null for older scans.
  final SkinFocus? focus;
  final List<String> routineAdjustments;
  final List<String> ingredientWarnings;

  /// Product types worth adding, most useful first ("moisturizer").
  final List<String> recommendedProductTypes;

  /// Non-product changes tied to what the scan saw (habits, sun, sleep…).
  final List<IngredientTip> beyondProducts;
  final String disclaimer;

  int? scoreFor(SkinMetric m) =>
      metrics.where((s) => s.metric == m).firstOrNull?.score;

  /// Lowest-scoring metrics first: what to focus on.
  List<MetricScore> get weakest =>
      [...metrics]..sort((a, b) => a.score.compareTo(b.score));

  Map<String, Object?> toJson() => {
    'image_quality': {'usable': usable, 'issues': qualityIssues},
    'overall_score': overallScore,
    'metrics': metrics.map((m) => m.toJson()).toList(),
    'skin_type_estimate': skinTypeEstimate,
    'summary': summary,
    'strengths': strengths,
    'priorities': priorities,
    'findings': findings.map((f) => f.toJson()).toList(),
    'recommended_ingredients': recommendedIngredients
        .map((e) => e.toJson())
        .toList(),
    'ingredients_to_avoid': ingredientsToAvoid.map((e) => e.toJson()).toList(),
    'red_flags': redFlags.map((e) => e.toJson()).toList(),
    'model': model,
    if (focus != null) 'focus': focus!.name,
    'routine_adjustments': routineAdjustments,
    'ingredient_warnings': ingredientWarnings,
    'recommended_product_types': recommendedProductTypes,
    'beyond_products': [
      for (final b in beyondProducts) {'title': b.name, 'detail': b.why},
    ],
    'disclaimer': disclaimer,
  };

  /// Defensive parser: the backend validates against a strict schema, but the
  /// client still clamps and drops anything malformed rather than crashing.
  factory SkinAnalysis.fromJson(Map<String, dynamic> j) {
    List<T> listOf<T>(Object? raw, T? Function(Map<String, dynamic>) f) =>
        ((raw as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(f)
            .whereType<T>()
            .toList();
    List<String> strings(Object? raw) =>
        ((raw as List?) ?? const []).whereType<String>().toList();

    final quality = (j['image_quality'] as Map<String, dynamic>?) ?? const {};
    final metrics = listOf<MetricScore>(j['metrics'], (m) {
      final metric = SkinMetric.fromKey(m['metric'] as String? ?? '');
      if (metric == null) return null;
      return MetricScore(
        metric: metric,
        score: ((m['score'] as num?)?.round() ?? 50).clamp(0, 100),
        note: m['note'] as String? ?? '',
      );
    });

    return SkinAnalysis(
      usable: quality['usable'] as bool? ?? true,
      qualityIssues: strings(quality['issues']),
      overallScore: ((j['overall_score'] as num?)?.round() ?? 0).clamp(0, 100),
      metrics: metrics,
      skinTypeEstimate: j['skin_type_estimate'] as String? ?? 'unknown',
      summary: j['summary'] as String? ?? '',
      strengths: strings(j['strengths']),
      priorities: strings(j['priorities']),
      findings: listOf(j['findings'], Finding.fromJson),
      recommendedIngredients: listOf(
        j['recommended_ingredients'],
        IngredientTip.fromJson,
      ),
      ingredientsToAvoid: listOf(
        j['ingredients_to_avoid'],
        IngredientTip.fromJson,
      ),
      redFlags: listOf(j['red_flags'], RedFlag.fromJson),
      model: j['model'] as String? ?? '',
      focus: SkinFocus.values.asNameMap()[j['focus']],
      routineAdjustments: strings(j['routine_adjustments']),
      ingredientWarnings: strings(j['ingredient_warnings']),
      recommendedProductTypes: strings(j['recommended_product_types']),
      beyondProducts: listOf(j['beyond_products'], (b) {
        final title = b['title'], detail = b['detail'];
        return title is String && detail is String
            ? IngredientTip(name: title, why: detail)
            : null;
      }),
      disclaimer: switch (j['disclaimer']) {
        final String d when d.isNotEmpty => d,
        _ => defaultDisclaimer,
      },
    );
  }
}

/// The scan's tracking mode.
enum SkinFocus {
  cure('Clear', "Calm what's active first."),
  glow('Glow', 'Build radiance and evenness.'),
  maintain('Maintain', "Keep what's working.");

  const SkinFocus(this.label, this.line);
  final String label;
  final String line;
}

class SkinScan {
  const SkinScan({
    required this.id,
    required this.createdAt,
    required this.photoPath,
    required this.analysis,
    this.face,
    this.radiance,
    this.measure,
  });

  final String id;
  final DateTime createdAt;

  /// Absolute path inside the app's private storage. Photos never leave the
  /// device except transiently for analysis.
  final String photoPath;
  final SkinAnalysis analysis;

  /// Facial landmarks from capture, used to draw the face map. Null for
  /// scans taken before landmarks were stored.
  final FaceGeometry? face;

  /// Glow measured on the phone from the photo's pixels. Null until it has
  /// been measured, or when the scan has no landmarks to measure with.
  final Radiance? radiance;

  /// What each lens measured, overall and per zone. Null until measured.
  final SkinMeasure? measure;

  SkinScan withRadiance(Radiance r) => SkinScan(
    id: id,
    createdAt: createdAt,
    photoPath: photoPath,
    analysis: analysis,
    face: face,
    radiance: r,
    measure: measure,
  );

  SkinScan withMeasure(SkinMeasure m) => SkinScan(
    id: id,
    createdAt: createdAt,
    photoPath: photoPath,
    analysis: analysis,
    face: face,
    radiance: radiance,
    measure: m,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'created_at': createdAt.millisecondsSinceEpoch,
    'photo_path': photoPath,
    'overall_score': analysis.overallScore,
    'usable': analysis.usable ? 1 : 0,
    'analysis_json': jsonEncode(analysis.toJson()),
    'face_json': face?.encode(),
    'radiance_json': radiance == null ? null : jsonEncode(radiance!.toJson()),
    'measure_json': measure == null ? null : jsonEncode(measure!.toJson()),
  };

  factory SkinScan.fromRow(Map<String, Object?> r) => SkinScan(
    id: r['id'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    photoPath: r['photo_path'] as String,
    analysis: SkinAnalysis.fromJson(
      jsonDecode(r['analysis_json'] as String) as Map<String, dynamic>,
    ),
    face: FaceGeometry.decode(r['face_json'] as String?),
    radiance: switch (r['radiance_json']) {
      final String raw => Radiance.fromJson(jsonDecode(raw)),
      _ => null,
    },
    measure: switch (r['measure_json']) {
      final String raw => SkinMeasure.fromJson(jsonDecode(raw)),
      _ => null,
    },
  );
}

/// What's bothering the person today, picked right before a scan. Sent to
/// the AI so it looks for these specifically.
enum SkinIssue {
  dryness('dryness', 'Dryness'),
  redness('redness', 'Redness'),
  breakouts('breakouts', 'Breakouts'),
  darkSpots('dark_spots', 'Dark spots'),
  oiliness('oiliness', 'Oiliness');

  const SkinIssue(this.key, this.label);
  final String key;
  final String label;
}
