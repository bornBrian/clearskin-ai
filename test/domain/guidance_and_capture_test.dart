import 'dart:math' as math;

import 'package:clearskin_ai/data/models/profile.dart';
import 'package:clearskin_ai/data/models/scan.dart';
import 'package:clearskin_ai/domain/guidance/application_guide.dart';
import 'package:clearskin_ai/domain/guidance/habits.dart';
import 'package:clearskin_ai/domain/guidance/potential.dart';
import 'package:clearskin_ai/domain/routine/routine_engine.dart';
import 'package:clearskin_ai/domain/scan/face_zones.dart';
import 'package:clearskin_ai/domain/scan/live_guidance.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

SkinAnalysis analysis(Map<SkinMetric, int> scores, {bool usable = true}) =>
    SkinAnalysis(
      usable: usable,
      qualityIssues: const [],
      overallScore:
          (scores.values.reduce((a, b) => a + b) / scores.length).round(),
      metrics: [
        for (final e in scores.entries)
          MetricScore(metric: e.key, score: e.value, note: ''),
      ],
      skinTypeEstimate: 'combination',
      summary: '',
      strengths: const [],
      priorities: const [],
      findings: const [],
      recommendedIngredients: const [],
      ingredientsToAvoid: const [],
      redFlags: const [],
      model: 'test',
    );

LiveFrame frame({
  double w = 0.55,
  double yaw = 0,
  double? headroom = 0.5,
  int faces = 1,
}) => LiveFrame(
  faceCount: faces,
  luminance: 130,
  faceLuminance: 130,
  sideBalance: 1,
  faceWidth: w,
  centerX: 0.5,
  centerY: 0.45,
  yaw: yaw,
  roll: 0,
  pitch: 0,
  headroom: headroom,
  eyesOpen: 0.9,
  motion: 0.005,
);

void main() {
  group('Full-face capture', () {
    test('the front photo needs room for the whole forehead', () {
      expect(
        LiveGuidance.evaluate(frame(headroom: 0.1)),
        LiveHint.showForehead,
      );
      expect(LiveGuidance.evaluate(frame(headroom: 0.4)), LiveHint.aligned);
    });

    test('too close to fit the hairline is caught before centring', () {
      expect(LiveGuidance.evaluate(frame(w: 0.76)), LiveHint.moveBack);
    });

    test('side photos need a real turn, then the opposite way', () {
      const a = ScanPose.sideA, b = ScanPose.sideB;
      expect(LiveGuidance.evaluate(frame(yaw: 5), pose: a), LiveHint.turnSide);
      expect(LiveGuidance.evaluate(frame(yaw: 35), pose: a), LiveHint.aligned);
      expect(LiveGuidance.evaluate(frame(yaw: 70), pose: a), LiveHint.turnLess);
      // Same direction as the first side: turn the other way.
      expect(
        LiveGuidance.evaluate(frame(yaw: 30), pose: b, firstSideYaw: 33),
        LiveHint.turnOtherSide,
      );
      expect(
        LiveGuidance.evaluate(frame(yaw: -30), pose: b, firstSideYaw: 33),
        LiveHint.aligned,
      );
      // Headroom only matters straight on.
      expect(
        LiveGuidance.evaluate(frame(yaw: 35, headroom: 0.05), pose: a),
        LiveHint.aligned,
      );
    });

    test('the face outline is lifted to cover the whole forehead', () {
      // A simple oval: top at y=0.30, brows at 0.40, chin at 0.80.
      final oval = [
        for (var i = 0; i < 16; i++)
          Offset(
            0.5 + 0.2 * math.cos(i / 16 * 2 * math.pi),
            0.55 + 0.25 * math.sin(i / 16 * 2 * math.pi),
          ),
      ];
      final g = FaceGeometry(
        aspect: 0.75,
        contours: {
          'face': oval,
          'leftEyebrowTop': const [Offset(0.4, 0.40)],
          'rightEyebrowTop': const [Offset(0.6, 0.40)],
        },
      );
      double top(List<Offset> pts) =>
          pts.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
      expect(top(g.raw['face']!), closeTo(0.30, 0.001));
      // 0.10 above the brows becomes 0.145.
      expect(top(g.contours['face']!), closeTo(0.255, 0.001));
      // Below the brows nothing moves; the stored data is untouched.
      expect(
        g.contours['face']!.where((p) => p.dy >= 0.40),
        oval.where((p) => p.dy >= 0.40),
      );
      expect(g.encode(), contains('0.3'));
    });
  });

  group('Application guide', () {
    test('every generated step has concrete instructions', () {
      for (final c in RoutineComplexity.values) {
        final r = RoutineEngine.build(
          profile: profile(
            complexity: c,
            skinType: SkinType.dry,
            concerns: {Concern.acne, Concern.darkSpots, Concern.darkCircles},
          ),
        );
        for (final s in [...r.am, ...r.pm]) {
          final g = ApplicationGuide.forStep(s);
          expect(g.amount, isNot(contains('follow the label')), reason: s.id);
          expect(g.contact, isNotEmpty, reason: s.id);
        }
      }
    });

    test('sunscreen waits before makeup and explains removal', () {
      final spf = RoutineEngine.build(profile: profile()).am.last;
      final g = ApplicationGuide.forStep(spf);
      expect(g.waitBeforeNext, const Duration(minutes: 15));
      expect(g.removal, contains('60 seconds'));
    });

    test('toner sits between cleanser and treatments when used', () {
      final r = RoutineEngine.build(
        profile: profile(
          skinType: SkinType.dry,
          complexity: RoutineComplexity.enthusiast,
          concerns: {Concern.darkSpots},
        ),
      );
      final ids = r.am.map((s) => s.id).toList();
      expect(ids.indexOf('am.toner'), ids.indexOf('am.cleanse') + 1);
      expect(ids.last, 'am.spf');
      expect(r.am.firstWhere((s) => s.id == 'am.toner').optional, isTrue);
    });
  });

  group('Habits', () {
    test('follow the weakest measures, round-robin, no duplicates', () {
      final h = HabitCoach.pick(
        profile: profile(),
        latest: analysis({
          SkinMetric.acne: 50,
          SkinMetric.underEyes: 60,
          SkinMetric.hydration: 92,
        }),
      );
      expect(h.length, 5);
      expect(h.first.id, 'hands_off');
      expect(h[1].id, 'sleep');
      expect(h.map((x) => x.id).toSet().length, h.length);
      expect(h.any((x) => x.id == 'damp'), isFalse, reason: 'hydration is fine');
    });

    test('fall back to concerns without a scan', () {
      final h = HabitCoach.pick(profile: profile(concerns: {Concern.redness}));
      expect(h.first.id, 'lukewarm');
    });
  });

  group('Potential', () {
    test('responsive measures gain most, never past the ceiling', () {
      final p = SkinPotential.of(
        analysis({
          SkinMetric.acne: 50,
          SkinMetric.fineLines: 50,
          SkinMetric.hydration: 95,
        }),
      )!;
      final acne = p.metrics.firstWhere((m) => m.metric == SkinMetric.acne);
      final lines = p.metrics.firstWhere(
        (m) => m.metric == SkinMetric.fineLines,
      );
      expect(acne.potential, 80);
      expect(lines.potential, 58);
      expect(p.biggestGains.first.metric, SkinMetric.acne);
      expect(p.potential, greaterThan(p.now));
      expect(p.metrics.every((m) => m.potential <= SkinPotential.ceiling), isTrue);
    });

    test('no potential for unusable photos', () {
      expect(
        SkinPotential.of(analysis({SkinMetric.acne: 50}, usable: false)),
        isNull,
      );
    });
  });
}
