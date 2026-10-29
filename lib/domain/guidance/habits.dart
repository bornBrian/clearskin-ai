import '../../data/models/profile.dart';
import '../../data/models/scan.dart';

/// How solid the science behind a habit is. Shown so people can decide
/// what's worth their effort, and so we never oversell.
enum Evidence {
  strong('Strong evidence'),
  moderate('Some evidence'),
  limited('Early evidence');

  const Evidence(this.label);
  final String label;
}

class Habit {
  const Habit(this.id, this.title, this.detail, this.evidence);
  final String id;
  final String title;
  final String detail;
  final Evidence evidence;
}

/// What helps skin besides products: the changes that make the routine
/// work, chosen from what the scan and profile actually show.
abstract final class HabitCoach {
  static const _byMetric = <SkinMetric, List<Habit>>{
    SkinMetric.acne: [
      Habit(
        'hands_off',
        'Hands off, no picking',
        'Picking turns a 5-day spot into a mark that lasts months. Use a patch instead.',
        Evidence.strong,
      ),
      Habit(
        'pillowcase',
        'Fresh pillowcase twice a week',
        'It holds oil and bacteria against your cheek all night.',
        Evidence.moderate,
      ),
      Habit(
        'sweat',
        'Rinse within 30 minutes of sweating',
        'Trapped sweat clogs pores along the forehead and jaw. Caps, helmets and straps are the usual culprits.',
        Evidence.moderate,
      ),
      Habit(
        'glycaemic',
        'Fewer sugary drinks and white carbs',
        'Sugary, fast-digesting food is linked to more breakouts. Dairy can be too: try four weeks without and compare.',
        Evidence.moderate,
      ),
    ],
    SkinMetric.redness: [
      Habit(
        'lukewarm',
        'Lukewarm water only',
        'Hot showers and steam widen blood vessels and strip the barrier. Keep face washing cool to warm.',
        Evidence.moderate,
      ),
      Habit(
        'triggers',
        'Track your flush triggers',
        'Heat, alcohol, spicy food and hot drinks are common ones. Log them in check-ins; insights will show which are yours.',
        Evidence.moderate,
      ),
      Habit(
        'fragrance',
        'Fragrance-free everything',
        'Fragrance is the top cause of skincare irritation, essential oils included.',
        Evidence.strong,
      ),
    ],
    SkinMetric.pigmentation: [
      Habit(
        'sun_daily',
        'Sunscreen every day, even indoors by windows',
        'UV darkens marks within hours and undoes weeks of fading. Daily SPF is the single biggest lever for even tone.',
        Evidence.strong,
      ),
      Habit(
        'shade',
        'Hat and shade at midday',
        'Light and heat darken marks too, especially on deeper skin. Sunscreen alone doesn\'t block all of it.',
        Evidence.moderate,
      ),
      Habit(
        'patience',
        'Give marks 8–12 weeks',
        'Skin renews about every month; fading takes two or three cycles. Judge progress by monthly scans, not the mirror.',
        Evidence.strong,
      ),
    ],
    SkinMetric.hydration: [
      Habit(
        'damp',
        'Moisturise within a minute of washing',
        'Damp skin holds water; dry skin loses it fast. Seal it in while it\'s still damp.',
        Evidence.moderate,
      ),
      Habit(
        'humidity',
        'Humidifier in dry or air-conditioned rooms',
        'Air conditioning and heating pull water out of skin overnight. 40–60% humidity is the sweet spot.',
        Evidence.moderate,
      ),
      Habit(
        'short_showers',
        'Shorter, cooler showers',
        'Long hot showers dissolve the oils that keep skin from drying out.',
        Evidence.moderate,
      ),
    ],
    SkinMetric.oilBalance: [
      Habit(
        'twice',
        'Wash twice a day, no more',
        'Over-washing strips skin, which can respond with more oil. Blotting papers handle midday shine.',
        Evidence.moderate,
      ),
      Habit(
        'phone',
        'Wipe your phone screen daily',
        'It carries oil and bacteria straight to your cheek and jaw every call.',
        Evidence.limited,
      ),
    ],
    SkinMetric.texture: [
      Habit(
        'no_scrubs',
        'No gritty scrubs or brushes',
        'They cause micro-tears and roughness. Chemical exfoliants smooth texture without the damage.',
        Evidence.moderate,
      ),
    ],
    SkinMetric.pores: [
      Habit(
        'no_strips',
        'Skip pore strips and squeezing',
        'They empty pores for a day and stretch them over time. Salicylic acid keeps them clear from inside.',
        Evidence.moderate,
      ),
    ],
    SkinMetric.fineLines: [
      Habit(
        'sunglasses',
        'Sunglasses outdoors',
        'Squinting and UV are the two biggest drivers of lines around the eyes.',
        Evidence.moderate,
      ),
      Habit(
        'no_smoke',
        'Avoid smoke',
        'Smoking breaks down collagen and is one of the clearest causes of early lines.',
        Evidence.strong,
      ),
      Habit(
        'back_sleep',
        'Sleep on your back, or a silk pillowcase',
        'Pressing your face into a pillow every night creases the same lines.',
        Evidence.limited,
      ),
    ],
    SkinMetric.underEyes: [
      Habit(
        'sleep',
        '7–9 hours, regular times',
        'Short or irregular sleep shows first under the eyes as darkness and puffiness.',
        Evidence.moderate,
      ),
      Habit(
        'cold',
        'Cold compress for puffiness',
        'Two minutes with a cold spoon eases morning puffiness.',
        Evidence.moderate,
      ),
      Habit(
        'salt',
        'Less salt and alcohol late at night',
        'Both make you hold water, which pools under the eyes overnight.',
        Evidence.moderate,
      ),
      Habit(
        'rubbing',
        'Don\'t rub your eyes',
        'Rubbing darkens the skin there over time, especially with allergies. Treat the itch instead.',
        Evidence.moderate,
      ),
    ],
  };

  static const _shaving = Habit(
    'shave_technique',
    'Shave with the grain, sharp blade',
    'Most razor bumps come from technique. Warm damp skin, light pressure, with the grain, a fresh blade every 5–7 shaves.',
    Evidence.moderate,
  );

  static const _sleepBasics = Habit(
    'sleep_basics',
    'Protect your sleep',
    'Skin repairs most at night. Consistent sleep improves barrier recovery and how rested skin looks.',
    Evidence.moderate,
  );

  /// Up to [max] habits, most relevant first: the weakest measures from the
  /// latest scan lead; with no scan, the profile's concerns do.
  static List<Habit> pick({
    required UserProfile profile,
    SkinAnalysis? latest,
    int max = 5,
  }) {
    final metrics = <SkinMetric>[
      if (latest != null && latest.usable)
        for (final m in latest.weakest)
          if (m.score < 80) m.metric,
      for (final c in profile.concerns) ?_metricFor(c),
    ];
    final out = <Habit>[];
    final seen = <String>{};
    void add(Habit h) {
      if (out.length < max && seen.add(h.id)) out.add(h);
    }

    // Round-robin so one weak measure doesn't take every slot.
    for (var round = 0; round < 4 && out.length < max; round++) {
      for (final m in metrics.toSet()) {
        final list = _byMetric[m] ?? const [];
        if (round < list.length) add(list[round]);
      }
    }
    if (profile.shaves &&
        (profile.concerns.contains(Concern.razorBumps) ||
            (latest?.findings.any(
                  (f) => f.title.toLowerCase().contains('razor'),
                ) ??
                false))) {
      add(_shaving);
    }
    add(_sleepBasics);
    return out;
  }

  static SkinMetric? _metricFor(Concern c) => switch (c) {
    Concern.acne => SkinMetric.acne,
    Concern.blackheads || Concern.largePores => SkinMetric.pores,
    Concern.darkSpots || Concern.unevenTone => SkinMetric.pigmentation,
    Concern.redness || Concern.sensitivity => SkinMetric.redness,
    Concern.dryness => SkinMetric.hydration,
    Concern.oiliness => SkinMetric.oilBalance,
    Concern.texture => SkinMetric.texture,
    Concern.fineLines => SkinMetric.fineLines,
    Concern.darkCircles => SkinMetric.underEyes,
    Concern.razorBumps => null,
  };
}
