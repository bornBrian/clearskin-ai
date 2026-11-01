import 'dart:typed_data';

import 'package:clearskin_ai/data/models/profile.dart';
import 'package:clearskin_ai/data/models/scan.dart';
import 'package:clearskin_ai/domain/routine/routine_engine.dart';
import 'package:clearskin_ai/domain/scan/on_device_analysis.dart';
import 'package:clearskin_ai/domain/scan/skin_maps.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

SkinMaps _maps(Map<SkinLens, double> coverage, {int glow = 60}) => SkinMaps(
  width: 1,
  height: 1,
  mask: Uint8List(1),
  feather: Float32List(1),
  readings: {
    for (final l in SkinLens.values)
      l: LensReading(
        values: Float32List(1),
        coverage: coverage[l] ?? 0,
        zones: [ZoneShare('cheeks', (coverage[l] ?? 0) * 2)],
      ),
  },
  radiance: Radiance(score: glow, evenness: glow, clarity: glow, sheen: glow),
);

void main() {
  test('a clear photo scores high and focuses on keeping it', () {
    final a = OnDeviceAnalysis.build(_maps({}, glow: 80), profile());
    expect(a.model, OnDeviceAnalysis.model);
    expect(a.usable, isTrue);
    expect(a.metrics.map((m) => m.metric), [
      SkinMetric.redness,
      SkinMetric.pigmentation,
      SkinMetric.oilBalance,
      SkinMetric.texture,
    ]);
    expect(a.metrics.every((m) => m.score == 95), isTrue);
    expect(a.priorities, isEmpty);
    expect(a.focus, SkinFocus.maintain);
  });

  test('flagged redness and oil become low scores, priorities and tips', () {
    final a = OnDeviceAnalysis.build(
      _maps({SkinLens.redness: 0.07, SkinLens.shine: 0.06}),
      profile(),
    );
    expect(a.scoreFor(SkinMetric.redness), lessThan(55));
    expect(a.scoreFor(SkinMetric.oilBalance), 40);
    expect(a.priorities, containsAll(['Calm redness', 'Balance oil']));
    expect(a.focus, SkinFocus.cure);
    expect(
      a.recommendedIngredients.map((t) => t.name).toSet().length,
      a.recommendedIngredients.length,
    );
    expect(
      a.metrics.firstWhere((m) => m.metric == SkinMetric.redness).note,
      contains('cheeks'),
    );
  });

  test('scores never leave 40..95, however extreme the photo', () {
    expect(OnDeviceAnalysis.score(SkinLens.redness, 0), 95);
    expect(OnDeviceAnalysis.score(SkinLens.redness, 0.5), 40);
    expect(
      OnDeviceAnalysis.score(SkinLens.texture, 0.06),
      inInclusiveRange(40, 95),
    );
  });

  test('the routine engine builds a routine from an on-device result', () {
    final a = OnDeviceAnalysis.build(
      _maps({SkinLens.redness: 0.08}),
      profile(skinType: SkinType.oily),
    );
    final routine = RoutineEngine.build(
      profile: profile(skinType: SkinType.oily),
      latest: a,
    );
    expect(routine.am, isNotEmpty);
    expect(routine.pm, isNotEmpty);
  });
}
