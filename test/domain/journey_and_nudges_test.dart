import 'package:clearskin_ai/data/models/check_in.dart';
import 'package:clearskin_ai/data/models/product.dart';
import 'package:clearskin_ai/data/models/profile.dart';
import 'package:clearskin_ai/data/models/scan.dart';
import 'package:clearskin_ai/domain/journey/journey_engine.dart';
import 'package:clearskin_ai/domain/nudges/nudge_engine.dart';
import 'package:clearskin_ai/domain/routine/routine_engine.dart';
import 'package:clearskin_ai/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

SkinScan _scan(DateTime at, int overall, {int? acne}) => SkinScan(
  id: at.toIso8601String(),
  createdAt: at,
  photoPath: '',
  analysis: SkinAnalysis(
    usable: true,
    qualityIssues: const [],
    overallScore: overall,
    metrics: [
      MetricScore(metric: SkinMetric.acne, score: acne ?? overall, note: ''),
    ],
    skinTypeEstimate: 'normal',
    summary: '',
    strengths: const [],
    priorities: const [],
    findings: const [],
    recommendedIngredients: const [],
    ingredientsToAvoid: const [],
    redFlags: const [],
    model: 'test',
  ),
);

RoutineStep _step(String id, {Set<int> days = const {}, String? title}) =>
    RoutineStep(
      id: id,
      slot: id.startsWith('am') ? RoutineSlot.am : RoutineSlot.pm,
      title: title ?? id,
      category: ProductCategory.treatment,
      why: '',
      howTo: '',
      days: days,
    );

void main() {
  group('JourneyEngine', () {
    test('acne comes first, then shaving, then marks', () {
      expect(
        JourneyEngine.trackFor(
          profile(concerns: {Concern.darkSpots, Concern.acne}),
          null,
        ),
        JourneyTrack.clear,
      );
      expect(
        JourneyEngine.trackFor(
          profile(
            shaves: true,
            gender: Gender.man,
            concerns: {Concern.razorBumps, Concern.darkSpots},
          ),
          null,
        ),
        JourneyTrack.shave,
      );
      // Razor bumps without shaving don't pick the shave track.
      expect(
        JourneyEngine.trackFor(
          profile(concerns: {Concern.razorBumps, Concern.darkSpots}),
          null,
        ),
        JourneyTrack.fade,
      );
    });

    test('falls back to the weakest scan metric, then to glow', () {
      final p = profile();
      expect(
        JourneyEngine.trackFor(p, _scan(DateTime(2026), 60, acne: 40).analysis),
        JourneyTrack.clear,
      );
      expect(JourneyEngine.trackFor(p, null), JourneyTrack.glow);
    });

    test('week and phase follow the start date', () {
      final p = profile(concerns: {Concern.acne}); // starts 2026-01-01
      final day1 = JourneyEngine.build(
        profile: p,
        usableScans: const [],
        now: DateTime(2026, 1, 1, 9),
      );
      expect((day1.week, day1.day, day1.phase.name), (1, 1, 'Reset'));
      expect(day1.isNewWeek, isFalse);

      final week3 = JourneyEngine.build(
        profile: p,
        usableScans: const [],
        now: DateTime(2026, 1, 15),
      );
      expect(
        (week3.week, week3.phase.name, week3.isNewWeek),
        (3, 'Treat', true),
      );

      final done = JourneyEngine.build(
        profile: p,
        usableScans: const [],
        now: DateTime(2026, 6, 1),
      );
      expect(done.week, Journey.totalWeeks);
      expect(done.complete, isTrue);
      expect(done.progress, 1);
    });

    test('every phase has exactly three focus actions', () {
      for (final t in JourneyTrack.values) {
        final concerns = switch (t) {
          JourneyTrack.clear => {Concern.acne},
          JourneyTrack.fade => {Concern.darkSpots},
          JourneyTrack.calm => {Concern.redness},
          JourneyTrack.smooth => {Concern.texture},
          JourneyTrack.balance => {Concern.oiliness},
          JourneyTrack.shave => {Concern.razorBumps},
          JourneyTrack.glow => <Concern>{},
        };
        final j = JourneyEngine.build(
          profile: profile(concerns: concerns, shaves: true),
          usableScans: const [],
        );
        expect(j.track, t);
        expect(j.phases, hasLength(4));
        for (final ph in j.phases) {
          expect(ph.focus, hasLength(3), reason: '$t ${ph.name}');
        }
      }
    });

    test('pregnancy swaps retinoids for azelaic acid', () {
      final j = JourneyEngine.build(
        profile: profile(concerns: {Concern.texture}, pregnant: true),
        usableScans: const [],
      );
      final text = j.phases.expand((p) => p.focus).join(' ');
      expect(text, isNot(contains('Retinoid')));
      expect(text, contains('Azelaic'));
    });

    test('goal is +15, clamped to 80–95, and never below the start', () {
      Journey withBaseline(int score) => JourneyEngine.build(
        profile: profile(),
        usableScans: [_scan(DateTime(2026, 1, 2), score)],
        now: DateTime(2026, 1, 10),
      );
      expect(withBaseline(50).goalScore, 80);
      expect(withBaseline(72).goalScore, 87);
      expect(withBaseline(90).goalScore, 95);
      expect(withBaseline(97).goalScore, 97);
    });

    test('flags a dermatologist when acne stalls by week 8', () {
      final p = profile(concerns: {Concern.acne});
      Journey at(int acneNow) => JourneyEngine.build(
        profile: p,
        usableScans: [
          _scan(DateTime(2026, 2, 25), 70, acne: acneNow),
          _scan(DateTime(2026, 1, 20), 69, acne: 55),
          _scan(DateTime(2026, 1, 2), 68, acne: 54),
        ],
        now: DateTime(2026, 2, 28), // week 9
      );
      expect(at(55).seeDoctorNow, isTrue);
      expect(at(65).seeDoctorNow, isFalse);
    });
  });

  group('NudgeEngine', () {
    final routine = Routine(
      am: [_step('am.cleanse'), _step('am.spf')],
      pm: [
        _step('pm.cleanse'),
        _step('pm.retinoid', days: {DateTime.monday}, title: 'Retinol serum'),
      ],
      notes: const [],
    );

    NudgeContext ctx({
      required DateTime now,
      DateTime? previousOpen,
      DateTime? lastScan,
      Set<String> completed = const {},
      Set<String> amDone = const {},
      int streak = 0,
      bool checkedIn = true,
      int? uv,
      int scans = 3,
    }) => NudgeContext(
      now: now,
      profile: profile(),
      routine: routine,
      amDone: amDone,
      pmDone: const {},
      completedDays: completed,
      streak: streak,
      lastScanAt: lastScan,
      previousOpenAt: previousOpen,
      checkedInToday: checkedIn,
      uvIndex: uv,
      journey: null,
      scanCount: scans,
    );

    List<NudgeKind> kinds(NudgeContext c) =>
        NudgeEngine.pick(c).map((n) => n.kind).toList();

    test('the second scan is named for what it shows: change', () {
      Nudge scanNudge(int scans) => NudgeEngine.pick(
        ctx(
          now: DateTime(2026, 3, 9, 9),
          previousOpen: DateTime(2026, 3, 8),
          lastScan: DateTime(2026, 3, 1),
          scans: scans,
        ),
      ).firstWhere((n) => n.kind == NudgeKind.scanDue);
      expect(scanNudge(1).title, 'Your second scan');
      expect(scanNudge(1).body, contains('shows change'));
      expect(scanNudge(4).title, 'Scan day');
    });

    test('welcomes people back after three quiet days, first', () {
      final now = DateTime(2026, 3, 2, 9); // Monday
      final k = kinds(
        ctx(
          now: now,
          previousOpen: DateTime(2026, 2, 26),
          lastScan: DateTime(2026, 3, 1),
        ),
      );
      expect(k.first, NudgeKind.welcomeBack);
      expect(k, isNot(contains(NudgeKind.freshStart)));
    });

    test('names tonight\'s active on its scheduled night', () {
      final monday = NudgeEngine.pick(
        ctx(
          now: DateTime(2026, 3, 2, 19),
          previousOpen: DateTime(2026, 3, 2, 8),
          lastScan: DateTime(2026, 3, 1),
        ),
      ).firstWhere((n) => n.kind == NudgeKind.tonight);
      expect(monday.title, 'Tonight: Retinol serum');

      final tuesday = NudgeEngine.pick(
        ctx(
          now: DateTime(2026, 3, 3, 19),
          previousOpen: DateTime(2026, 3, 3, 8),
          lastScan: DateTime(2026, 3, 1),
        ),
      ).firstWhere((n) => n.kind == NudgeKind.tonight);
      expect(tuesday.title, 'Tonight is a rest night');
    });

    test('protects a streak in the evening instead of a generic nudge', () {
      final k = kinds(
        ctx(
          now: DateTime(2026, 3, 3, 20),
          previousOpen: DateTime(2026, 3, 3, 8),
          lastScan: DateTime(2026, 3, 1),
          streak: 4,
          checkedIn: false,
        ),
      );
      expect(k, containsAllInOrder([NudgeKind.streak, NudgeKind.checkIn]));
      expect(k, isNot(contains(NudgeKind.tonight)));
    });

    test('scan due after a week; UV only by day; fresh start after a miss', () {
      final k = kinds(
        ctx(
          now: DateTime(2026, 3, 10, 9),
          previousOpen: DateTime(2026, 3, 9),
          lastScan: DateTime(2026, 3, 1),
          uv: 8,
        ),
      );
      expect(
        k,
        containsAll([NudgeKind.scanDue, NudgeKind.sun, NudgeKind.freshStart]),
      );
      final night = kinds(
        ctx(
          now: DateTime(2026, 3, 10, 21),
          previousOpen: DateTime(2026, 3, 10, 9),
          lastScan: DateTime(2026, 3, 8),
          uv: 8,
        ),
      );
      expect(night, isNot(contains(NudgeKind.sun)));
    });

    test('quiet when everything is on track', () {
      expect(
        kinds(
          ctx(
            now: DateTime(2026, 3, 10, 10),
            previousOpen: DateTime(2026, 3, 10, 7),
            lastScan: DateTime(2026, 3, 8),
            completed: {'2026-03-09'},
            amDone: {'am.cleanse'},
          ),
        ),
        isEmpty,
      );
    });
  });

  group('Evening reminder copy', () {
    test('follows the routine schedule per weekday', () {
      final routine = Routine(
        am: const [],
        pm: [
          _step('pm.cleanse'),
          _step('pm.aha', days: {DateTime.friday}, title: 'AHA exfoliant'),
        ],
        notes: const [],
      );
      expect(
        NotificationService.eveningCopy(routine, DateTime.friday).$1,
        'Tonight: AHA exfoliant',
      );
      expect(
        NotificationService.eveningCopy(routine, DateTime.monday).$1,
        'Rest night',
      );
      expect(
        NotificationService.eveningCopy(null, DateTime.monday).$1,
        'Evening routine',
      );
    });
  });

  group('ReminderSettings', () {
    test('round-trips and tolerates old profiles without it', () {
      final p = profile().copyWith(
        reminders: const ReminderSettings(
          checkIn: false,
          scanWeekday: DateTime.wednesday,
          scanTime: ReminderTime(18, 15),
          smart: false,
        ),
      );
      final back = UserProfile.decode(p.encode()).reminders;
      expect(back.checkIn, isFalse);
      expect(back.scanWeekday, DateTime.wednesday);
      expect(back.scanTime.format(), '6:15 PM');
      expect(back.smart, isFalse);

      final legacy = p.toJson()..remove('reminders');
      expect(UserProfile.fromJson(legacy).reminders.smart, isTrue);
    });
  });
}
