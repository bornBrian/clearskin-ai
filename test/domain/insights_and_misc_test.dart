import 'package:clearskin_ai/core/utils/dates.dart';
import 'package:clearskin_ai/data/models/check_in.dart';
import 'package:clearskin_ai/data/models/scan.dart';
import 'package:clearskin_ai/domain/forecast/skin_forecast.dart';
import 'package:clearskin_ai/domain/insights/insights_engine.dart';
import 'package:clearskin_ai/domain/routine/streaks.dart';
import 'package:clearskin_ai/domain/scan/capture_quality.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

CheckIn ci(
  DateTime d, {
  int breakouts = 0,
  Set<LifeTag> tags = const {},
  double sleep = 7.5,
  int stress = 2,
}) => CheckIn(
  day: Dates.dayKey(d),
  skinFeel: 3,
  breakouts: breakouts,
  sleepHours: sleep,
  stress: stress,
  waterGlasses: 5,
  tags: tags,
  note: '',
);

void main() {
  group('InsightsEngine', () {
    test('needs 14 days before reporting', () {
      final start = DateTime(2026, 3, 1);
      final r = InsightsEngine.analyze([
        for (var i = 0; i < 10; i++) ci(start.add(Duration(days: i))),
      ]);
      expect(r.ready, isFalse);
      expect(r.daysNeeded, 4);
    });

    test('detects a lagged dairy trigger', () {
      final start = DateTime(2026, 3, 1);
      final dairyDays = {0, 5, 10, 15, 20, 25};
      final logs = <CheckIn>[];
      for (var i = 0; i < 30; i++) {
        final afterDairy =
            dairyDays.contains(i - 1) || dairyDays.contains(i - 2);
        logs.add(
          ci(
            start.add(Duration(days: i)),
            breakouts: afterDairy ? 3 : 0,
            tags: dairyDays.contains(i) ? {LifeTag.dairy} : {},
          ),
        );
      }
      final r = InsightsEngine.analyze(logs);
      expect(r.ready, isTrue);
      final dairy = r.insights.firstWhere((i) => i.title == 'Dairy');
      expect(dairy.direction, InsightDirection.worse);
      expect(dairy.effect, greaterThan(1));
    });

    test('reports nothing on pure noise-free flat data', () {
      final start = DateTime(2026, 3, 1);
      final r = InsightsEngine.analyze([
        for (var i = 0; i < 20; i++)
          ci(
            start.add(Duration(days: i)),
            breakouts: 1,
            tags: i.isEven ? {LifeTag.sugar} : {},
          ),
      ]);
      expect(r.insights, isEmpty);
    });
  });

  group('Streaks', () {
    test('counts back from today, tolerating an unfinished today', () {
      final now = DateTime(2026, 5, 10, 9);
      final days = {
        for (var i = 1; i <= 4; i++)
          Dates.dayKey(now.subtract(Duration(days: i))),
      };
      expect(Streaks.current(days, now: now), 4);
      days.add(Dates.dayKey(now));
      expect(Streaks.current(days, now: now), 5);
    });

    test('longest streak spans gaps correctly', () {
      final d = DateTime(2026, 1, 1);
      final days = {
        for (final i in [0, 1, 2, 5, 6, 7, 8, 12])
          Dates.dayKey(d.add(Duration(days: i))),
      };
      expect(Streaks.longest(days), 4);
    });

    Set<String> run(DateTime start, List<int> offsets) => {
      for (final i in offsets) Dates.dayKey(start.add(Duration(days: i))),
    };

    test('7 days in a row earn a saver that covers one missed day', () {
      final start = DateTime(2026, 3, 1);
      // Days 0-6 done, day 7 missed, days 8-9 done.
      final days = run(start, [0, 1, 2, 3, 4, 5, 6, 8, 9]);
      final s = Streaks.compute(days, now: DateTime(2026, 3, 10, 20));
      expect(s.current, 9);
      expect(s.savers, 0, reason: 'the one saver was used');
      expect(s.savedDays, {Dates.dayKey(DateTime(2026, 3, 8))});
      expect(s.doneToday, isTrue);
    });

    test('two missed days in a row still end the streak', () {
      final start = DateTime(2026, 3, 1);
      final days = run(start, [0, 1, 2, 3, 4, 5, 6, 9, 10]);
      final s = Streaks.compute(days, now: DateTime(2026, 3, 11, 20));
      expect(s.current, 2);
      expect(s.best, 7);
      expect(s.savedDays, isEmpty);
    });

    test('no saver before the first 7 days, and never more than 2', () {
      final start = DateTime(2026, 3, 1);
      expect(
        Streaks.compute(
          run(start, [0, 1, 2, 4]),
          now: DateTime(2026, 3, 5, 20),
        ).current,
        1,
      );
      final long = Streaks.compute(
        run(start, [for (var i = 0; i < 30; i++) i]),
        now: DateTime(2026, 3, 30, 20),
      );
      expect(long.current, 30);
      expect(long.savers, Streaks.maxSavers);
    });

    test('an unfinished today never costs a saver', () {
      final start = DateTime(2026, 3, 1);
      final s = Streaks.compute(
        run(start, [for (var i = 0; i < 7; i++) i]),
        now: DateTime(2026, 3, 8, 9),
      );
      expect(s.current, 7);
      expect(s.savers, 1);
      expect(s.doneToday, isFalse);
    });
  });

  group('SkinForecaster', () {
    test('very high UV leads the forecast', () {
      final f = SkinForecaster.build(
        WeatherSnapshot(
          uvIndexMax: 9.4,
          humidity: 30,
          temperatureC: 28,
          fetchedAt: DateTime(2026),
        ),
        profile(),
      );
      expect(f.headline, 'Sunscreen day');
      expect(
        f.tips.map((t) => t.kind),
        containsAll([ForecastKind.uv, ForecastKind.dry]),
      );
    });
  });

  group('CaptureQuality', () {
    const good = CaptureMeasurements(
      faceCount: 1,
      meanLuminance: 140,
      shadowClipFraction: 0.02,
      highlightClipFraction: 0.01,
      sideBalance: 1.05,
      faceWidthFraction: 0.55,
      faceCenterOffset: 0.03,
      headYaw: 3,
      headRoll: 2,
      headPitch: 4,
      sharpness: 120,
      eyesOpen: 0.9,
      skinHue: 66,
      skinChroma: 27,
    );

    test('a well-lit centred face passes', () {
      expect(CaptureQuality.evaluate(good), isEmpty);
    });

    test('cut-off face, closed eyes and tinted light are caught', () {
      const m = CaptureMeasurements(
        faceCount: 1,
        meanLuminance: 140,
        shadowClipFraction: 0.02,
        highlightClipFraction: 0.01,
        sideBalance: 1.0,
        faceWidthFraction: 0.55,
        cutOff: true,
        eyesOpen: 0.1,
        skinHue: 68,
        // Warm bulb: daylight hue, far too much colour.
        skinChroma: 53,
      );
      expect(
        CaptureQuality.evaluate(m),
        containsAll([
          CaptureIssue.faceCut,
          CaptureIssue.eyesClosed,
          CaptureIssue.colourCast,
        ]),
      );
    });

    test('hue is ignored when skin colour is too muted to read', () {
      const m = CaptureMeasurements(
        faceCount: 1,
        meanLuminance: 120,
        shadowClipFraction: 0.02,
        highlightClipFraction: 0.01,
        sideBalance: 1.0,
        skinHue: 5,
        skinChroma: 4,
      );
      expect(
        CaptureQuality.evaluate(m),
        isNot(contains(CaptureIssue.colourCast)),
      );
      // Pink LED light on the same face is a real cast.
      const pink = CaptureMeasurements(
        faceCount: 1,
        meanLuminance: 120,
        shadowClipFraction: 0.02,
        highlightClipFraction: 0.01,
        sideBalance: 1.0,
        skinHue: 22,
        skinChroma: 26,
      );
      expect(CaptureQuality.evaluate(pink), contains(CaptureIssue.colourCast));
    });

    test('only light the person may not control can be accepted', () {
      expect(CaptureIssue.unevenLight.acceptable, isTrue);
      expect(CaptureIssue.colourCast.acceptable, isTrue);
      for (final i in [
        CaptureIssue.noFace,
        CaptureIssue.tooDark,
        CaptureIssue.tooFar,
        CaptureIssue.faceCut,
        CaptureIssue.blurry,
        CaptureIssue.eyesClosed,
        CaptureIssue.tilted,
      ]) {
        expect(i.acceptable, isFalse, reason: i.name);
      }
    });

    test('dark, side-lit, tilted photo reports each issue', () {
      const bad = CaptureMeasurements(
        faceCount: 1,
        meanLuminance: 50,
        shadowClipFraction: 0.4,
        highlightClipFraction: 0,
        sideBalance: 1.9,
        faceWidthFraction: 0.2,
        headYaw: 30,
      );
      expect(
        CaptureQuality.evaluate(bad),
        containsAll([
          CaptureIssue.tooDark,
          CaptureIssue.unevenLight,
          CaptureIssue.tooFar,
          CaptureIssue.tilted,
        ]),
      );
    });
  });

  group('SkinAnalysis parsing', () {
    test('clamps scores and drops unknown metrics', () {
      final a = SkinAnalysis.fromJson({
        'image_quality': {'usable': true, 'issues': []},
        'overall_score': 140,
        'metrics': [
          {'metric': 'acne', 'score': -5, 'note': 'x'},
          {'metric': 'made_up', 'score': 50, 'note': 'y'},
        ],
        'red_flags': [
          {'title': 'Mole', 'detail': 'd', 'urgency': 'soon'},
        ],
      });
      expect(a.overallScore, 100);
      expect(a.metrics.single.score, 0);
      expect(a.redFlags.single.urgency, FlagUrgency.soon);
    });
  });
}
