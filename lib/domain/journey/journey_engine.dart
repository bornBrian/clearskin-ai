import '../../data/models/profile.dart';
import '../../data/models/scan.dart';

/// The main thing a person's 12-week programme works on. Chosen from their
/// concerns (and, when concerns are vague, from their weakest scan metric).
enum JourneyTrack {
  clear('Clear skin', 'Calm breakouts and stop new ones.'),
  fade('Even tone', 'Fade dark marks and keep them away.'),
  calm('Calm skin', 'Repair your barrier. Less redness and stinging.'),
  smooth('Smooth skin', 'Refine texture, pores and fine lines.'),
  balance('Balanced skin', 'Less shine, without drying out.'),
  shave('Smooth shave', 'No more razor bumps or irritation.'),
  glow('Healthy glow', 'Hydrated, bright, resilient skin.');

  const JourneyTrack(this.title, this.promise);
  final String title;
  final String promise;
}

class JourneyPhase {
  const JourneyPhase({
    required this.name,
    required this.firstWeek,
    required this.lastWeek,
    required this.headline,
    required this.focus,
    required this.expect,
  });

  final String name;
  final int firstWeek;
  final int lastWeek;

  /// Six words or fewer.
  final String headline;

  /// Exactly three short actions for this phase.
  final List<String> focus;

  /// One honest sentence on what changes by the end of the phase.
  final String expect;

  bool contains(int week) => week >= firstWeek && week <= lastWeek;
  String get weeksLabel => firstWeek == lastWeek
      ? 'Week $firstWeek'
      : 'Weeks $firstWeek–$lastWeek';
}

class Journey {
  const Journey({
    required this.track,
    required this.phases,
    required this.week,
    required this.day,
    required this.doctorNote,
    this.baselineScore,
    this.latestScore,
    this.goalScore,
    this.seeDoctorNow = false,
  });

  static const totalWeeks = 12;

  final JourneyTrack track;
  final List<JourneyPhase> phases;

  /// 1-based programme week, capped at [totalWeeks].
  final int week;

  /// 1-based day since the plan started (not capped).
  final int day;

  /// When to get professional help for this track — always shown.
  final String doctorNote;

  final int? baselineScore;
  final int? latestScore;
  final int? goalScore;

  /// True when progress has stalled long enough that a professional is the
  /// right next step (e.g. acne unchanged by week 8).
  final bool seeDoctorNow;

  bool get complete => day > totalWeeks * 7;
  JourneyPhase get phase => phases.firstWhere(
    (p) => p.contains(week),
    orElse: () => phases.last,
  );
  int get phaseIndex => phases.indexOf(phase);

  /// 0–1 through the 12 weeks.
  double get progress => ((day - 1) / (totalWeeks * 7)).clamp(0.0, 1.0);

  /// True on the first day of a programme week (for "new week" nudges).
  bool get isNewWeek => day > 1 && (day - 1) % 7 == 0 && !complete;
}

/// Builds a person's 12-week guided programme. Deterministic, offline, and
/// conservative: one change at a time, sun protection always, and a clear
/// line on when to see a dermatologist instead of pushing on.
abstract final class JourneyEngine {
  static Journey build({
    required UserProfile profile,
    required List<SkinScan> usableScans,
    DateTime? now,
  }) {
    final today = _day(now ?? DateTime.now());
    final start = _day(profile.createdAt);
    final day = today.difference(start).inDays + 1;
    final week = ((day - 1) ~/ 7 + 1).clamp(1, Journey.totalWeeks);

    // Newest first.
    final latest = usableScans.firstOrNull?.analysis;
    final baseline = usableScans.lastOrNull?.analysis;
    final track = trackFor(profile, latest);

    final baseScore = baseline?.overallScore;
    // An ambitious but honest target: +15 points, at least 80, at most 95.
    final goal = baseScore == null
        ? null
        : baseScore >= 95
        ? baseScore
        : (baseScore + 15).clamp(80, 95).toInt();

    var stalled = false;
    if (week >= 8 && track == JourneyTrack.clear && usableScans.length >= 3) {
      final before = baseline?.scoreFor(SkinMetric.acne);
      final after = latest?.scoreFor(SkinMetric.acne);
      stalled = before != null && after != null && after - before < 3;
    }

    return Journey(
      track: track,
      phases: _phases(track, profile),
      week: week,
      day: day < 1 ? 1 : day,
      doctorNote: _doctorNote(track),
      baselineScore: baseScore,
      latestScore: latest?.overallScore,
      goalScore: goal,
      seeDoctorNow: stalled,
    );
  }

  static JourneyTrack trackFor(UserProfile p, SkinAnalysis? latest) {
    final c = p.concerns;
    if (c.contains(Concern.acne) || c.contains(Concern.blackheads)) {
      return JourneyTrack.clear;
    }
    if (p.shaves && c.contains(Concern.razorBumps)) return JourneyTrack.shave;
    if (c.contains(Concern.darkSpots) || c.contains(Concern.unevenTone)) {
      return JourneyTrack.fade;
    }
    if (c.contains(Concern.sensitivity) ||
        c.contains(Concern.redness) ||
        c.contains(Concern.dryness)) {
      return JourneyTrack.calm;
    }
    if (c.contains(Concern.texture) ||
        c.contains(Concern.fineLines) ||
        c.contains(Concern.largePores)) {
      return JourneyTrack.smooth;
    }
    if (c.contains(Concern.oiliness)) return JourneyTrack.balance;

    final weakest = latest?.weakest.firstOrNull;
    if (weakest != null && weakest.score < 70) {
      return switch (weakest.metric) {
        SkinMetric.acne => JourneyTrack.clear,
        SkinMetric.pigmentation => JourneyTrack.fade,
        SkinMetric.redness || SkinMetric.hydration => JourneyTrack.calm,
        SkinMetric.texture ||
        SkinMetric.pores ||
        SkinMetric.fineLines => JourneyTrack.smooth,
        SkinMetric.oilBalance => JourneyTrack.balance,
        SkinMetric.underEyes => JourneyTrack.glow,
      };
    }
    return JourneyTrack.glow;
  }

  static List<JourneyPhase> _phases(JourneyTrack t, UserProfile p) {
    // Retinoids are paused in pregnancy; azelaic acid is the usual swap.
    final retinoid = p.pregnantOrNursing ? 'Azelaic acid' : 'Retinoid';
    final reset = switch (t) {
      JourneyTrack.calm => const [
        'Pause all actives for two weeks',
        'Lukewarm water, gentle cleanser',
        'Rich ceramide moisturiser, twice daily',
      ],
      JourneyTrack.shave => const [
        'Shave after a warm wash',
        'With the grain, light pressure',
        'Fragrance-free balm after',
      ],
      JourneyTrack.fade => const [
        'SPF 30+ every single morning',
        'No scrubs, nothing that stings',
        'Moisturise morning and night',
      ],
      _ => const [
        'Cleanse gently, morning and night',
        'Moisturise — even oily skin',
        'SPF 30+ every morning',
      ],
    };

    final treat = switch (t) {
      JourneyTrack.clear => [
        p.pregnantOrNursing
            ? 'Azelaic acid, three nights a week'
            : 'Treatment three nights a week',
        'Patch spots — don\'t pick',
        'Change one thing at a time',
      ],
      JourneyTrack.fade => const [
        'Brightening serum each morning',
        'Azelaic acid at night',
        'Reapply SPF when outdoors',
      ],
      JourneyTrack.calm => const [
        'Add niacinamide once a day',
        'Patch test anything new',
        'Mineral SPF if others sting',
      ],
      JourneyTrack.smooth => [
        '$retinoid two nights a week',
        'Moisturise on top if it stings',
        'SPF every morning',
      ],
      JourneyTrack.balance => const [
        'Niacinamide every morning',
        'Light gel moisturiser',
        'BHA two nights a week',
      ],
      JourneyTrack.shave => const [
        'BHA on the beard area twice weekly',
        'Fresh blade every 5–7 shaves',
        'Never shave over active bumps',
      ],
      JourneyTrack.glow => const [
        'Vitamin C every morning',
        'Hydrating serum at night',
        'Seven to eight hours of sleep',
      ],
    };

    final refine = switch (t) {
      JourneyTrack.clear => const [
        'Treatment every other night',
        'SPF daily to fade marks faster',
        'Log food, sleep and stress',
      ],
      JourneyTrack.fade => const [
        'Gentle exfoliant twice a week',
        'Keep SPF non-negotiable',
        'Scan weekly in the same light',
      ],
      JourneyTrack.calm => const [
        'Add one gentle active slowly',
        'Keep only what your skin likes',
        'Note flare triggers in check-ins',
      ],
      JourneyTrack.smooth => [
        '$retinoid every other night',
        'Exfoliate on a separate night',
        'Hydrate more as you build up',
      ],
      JourneyTrack.balance => const [
        'BHA three nights a week',
        'Blot, don\'t over-wash',
        'Check pores in your weekly scan',
      ],
      JourneyTrack.shave => const [
        'Try trimming instead of close shaves',
        'Keep BHA on non-shave days',
        'Fade marks with daily SPF',
      ],
      JourneyTrack.glow => const [
        'Gentle exfoliant once a week',
        'Antioxidant serum every morning',
        'Keep SPF daily',
      ],
    };

    const glow = [
      'Keep the routine that works',
      'Compare your first and latest scan',
      'Set your maintenance plan',
    ];

    final (resetExpect, treatExpect, refineExpect, glowExpect) = switch (t) {
      JourneyTrack.clear => (
        'Skin feels calmer. Spots may not change yet.',
        'Fewer new spots by week six. A little purging is normal.',
        'Clear most days. Marks start to fade.',
        'Clear skin, and the habits to keep it.',
      ),
      JourneyTrack.fade => (
        'No new marks from irritation.',
        'Marks begin to soften around week six.',
        'Visibly more even tone.',
        'Even, bright skin you can protect.',
      ),
      JourneyTrack.calm => (
        'Less stinging. Skin feels comfortable.',
        'Redness settles; products stop burning.',
        'Calm skin that tolerates more.',
        'Resilient skin that stays calm.',
      ),
      JourneyTrack.smooth => (
        'Skin is ready for actives.',
        'Smoother feel by week six.',
        'Refined texture and softer lines.',
        'Smooth, even skin — keep it going.',
      ),
      JourneyTrack.balance => (
        'Less tightness, less rebound oil.',
        'Shine lasts longer into the day.',
        'Pores look cleaner and smaller.',
        'Balanced skin morning to night.',
      ),
      JourneyTrack.shave => (
        'Less sting after every shave.',
        'Fewer new bumps each week.',
        'Smooth shaves, fading marks.',
        'A shave routine that just works.',
      ),
      JourneyTrack.glow => (
        'Skin feels hydrated and comfortable.',
        'A brighter, fresher look.',
        'Even, luminous skin.',
        'Healthy glow, every day.',
      ),
    };

    return [
      JourneyPhase(
        name: 'Reset',
        firstWeek: 1,
        lastWeek: 2,
        headline: 'Build the habit',
        focus: reset,
        expect: resetExpect,
      ),
      JourneyPhase(
        name: 'Treat',
        firstWeek: 3,
        lastWeek: 6,
        headline: 'Target what matters',
        focus: treat,
        expect: treatExpect,
      ),
      JourneyPhase(
        name: 'Refine',
        firstWeek: 7,
        lastWeek: 10,
        headline: 'Step it up, gently',
        focus: refine,
        expect: refineExpect,
      ),
      JourneyPhase(
        name: 'Glow',
        firstWeek: 11,
        lastWeek: 12,
        headline: 'Lock in your results',
        focus: glow,
        expect: glowExpect,
      ),
    ];
  }

  static String _doctorNote(JourneyTrack t) => switch (t) {
    JourneyTrack.clear =>
      'Painful, deep or scarring breakouts — or no change by week 8 — need a dermatologist. Prescription options work.',
    JourneyTrack.fade =>
      'See a dermatologist for patches that spread, change shape, or appeared in pregnancy.',
    JourneyTrack.calm =>
      'Constant flushing, burning or bumps can be rosacea or eczema. A doctor can help.',
    JourneyTrack.shave =>
      'Bumps that keep coming back or scar are worth a dermatologist visit.',
    _ =>
      'Any spot that bleeds, itches or changes should be checked by a doctor.',
  };

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
}
