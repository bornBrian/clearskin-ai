import '../../data/models/profile.dart';

enum TipKind {
  basics('Basics'),
  ingredients('Ingredients'),
  lifestyle('Lifestyle'),
  myth('Myth'),
  safety('Safety');

  const TipKind(this.label);
  final String label;
}

/// One short, scannable point: a few-word headline and one sentence.
class TipPoint {
  const TipPoint(this.title, this.detail);
  final String title;
  final String detail;
}

class Tip {
  const Tip({
    required this.id,
    required this.title,
    required this.teaser,
    required this.kind,
    required this.image,
    required this.points,
    this.avoid,
    this.concerns = const {},
    this.forShavers = false,
    this.forDeeperTones = false,
    this.forPregnancy = false,
    this.forCycle = false,
  });

  final String id;
  final String title;

  /// The whole tip in one line — what someone remembers if they read
  /// nothing else.
  final String teaser;
  final TipKind kind;

  /// Bundled photo (see `Photos` in core/widgets).
  final String image;

  /// Exactly three points. Mainstream dermatology consensus only.
  final List<TipPoint> points;

  /// One line on what to skip, if there's something worth saying.
  final String? avoid;
  final Set<Concern> concerns;
  final bool forShavers;
  final bool forDeeperTones;
  final bool forPregnancy;
  final bool forCycle;
}

const _p = 'assets/images/photos';

/// Curated, reviewed education content shipped with the app (works offline,
/// costs nothing per view, and never hallucinates).
abstract final class TipLibrary {
  static const all = <Tip>[
    Tip(
      id: 'spf-amount',
      title: 'How much sunscreen is enough?',
      teaser: 'Two finger-lengths for face and neck. Most people use a third.',
      kind: TipKind.basics,
      image: '$_p/warm_shadow.webp',
      points: [
        TipPoint('Measure it', 'Two finger-lengths covers face and neck.'),
        TipPoint('Every day', 'UVA passes through clouds and windows.'),
        TipPoint('Reapply outside', 'Every two hours, and after sweating.'),
      ],
      avoid: 'Relying on SPF in makeup alone.',
      concerns: {Concern.darkSpots, Concern.unevenTone, Concern.fineLines},
    ),
    Tip(
      id: 'purge-vs-breakout',
      title: 'Purging or breaking out?',
      teaser: 'Purging is short, familiar and only from retinoids or acids.',
      kind: TipKind.ingredients,
      image: '$_p/serum_pink.webp',
      points: [
        TipPoint(
          'Only some products purge',
          'Retinoids and exfoliating acids.',
        ),
        TipPoint('Same spots, faster', 'Where you usually break out.'),
        TipPoint('Gone in 4–6 weeks', 'If not, the product isn\'t for you.'),
      ],
      avoid: 'New spots in new places, itching or burning — stop the product.',
      concerns: {Concern.acne, Concern.blackheads},
    ),
    Tip(
      id: 'no-picking',
      title: 'Why picking leaves marks',
      teaser: 'The spot heals in days. The mark can stay for months.',
      kind: TipKind.basics,
      image: '$_p/droplets.webp',
      points: [
        TipPoint(
          'Patch it',
          'Hydrocolloid patches flatten whiteheads overnight.',
        ),
        TipPoint('Warm compress', 'Eases deep, painful spots.'),
        TipPoint('Get help for cysts', 'Prescriptions prevent scarring.'),
      ],
      avoid: 'Squeezing — it pushes inflammation deeper.',
      concerns: {Concern.acne, Concern.darkSpots},
    ),
    Tip(
      id: 'retinoid-start',
      title: 'Start a retinoid, skip the redness',
      teaser: 'Low and slow is how retinoids work best.',
      kind: TipKind.ingredients,
      image: '$_p/serum_pour.webp',
      points: [
        TipPoint('Pea-sized', 'For the whole face, on dry skin.'),
        TipPoint('Two nights a week', 'Build up after 2–4 comfortable weeks.'),
        TipPoint('Buffer if it stings', 'Moisturiser first, retinoid on top.'),
      ],
      avoid: 'Retinoids in pregnancy, or without daily SPF.',
      concerns: {
        Concern.acne,
        Concern.fineLines,
        Concern.texture,
        Concern.darkSpots,
      },
    ),
    Tip(
      id: 'vitc-niacinamide',
      title: 'Vitamin C and niacinamide are fine',
      teaser: 'An old myth. Modern formulas work well together.',
      kind: TipKind.myth,
      image: '$_p/serum_plates.webp',
      points: [
        TipPoint('Same routine is OK', 'The warning came from old lab tests.'),
        TipPoint(
          'Tingles? Split them',
          'Vitamin C morning, niacinamide night.',
        ),
        TipPoint('Real clashes', 'Retinoids with acids. We flag these.'),
      ],
      concerns: {Concern.darkSpots, Concern.oiliness, Concern.unevenTone},
    ),
    Tip(
      id: 'pih-deeper-skin',
      title: 'Dark marks on deeper skin',
      teaser: 'They last longer. Gentle and consistent fades them.',
      kind: TipKind.basics,
      image: '$_p/dropper_amber.webp',
      forDeeperTones: true,
      points: [
        TipPoint(
          'SPF without white cast',
          'The one you\'ll actually wear daily.',
        ),
        TipPoint('Gentle brighteners', 'Azelaic acid, niacinamide, vitamin C.'),
        TipPoint('Treat spots early', 'Fewer breakouts, fewer marks.'),
      ],
      avoid: 'Scrubs, lemon juice and home peels.',
      concerns: {Concern.darkSpots, Concern.unevenTone, Concern.acne},
    ),
    Tip(
      id: 'razor-bumps',
      title: 'Shave without razor bumps',
      teaser: 'Technique matters more than the razor.',
      kind: TipKind.basics,
      image: '$_p/water.webp',
      forShavers: true,
      points: [
        TipPoint('Shave warm', 'After a shower, with a lubricating gel.'),
        TipPoint('With the grain', 'Light pressure, sharp blade.'),
        TipPoint('Calm after', 'Fragrance-free balm, not alcohol.'),
      ],
      avoid: 'Acids straight after shaving.',
      concerns: {Concern.razorBumps},
    ),
    Tip(
      id: 'barrier',
      title: 'Your skin barrier, explained',
      teaser: 'Stinging and tightness mean your barrier needs a break.',
      kind: TipKind.basics,
      image: '$_p/cream_beige.webp',
      points: [
        TipPoint('Gentle cleanser', 'Lukewarm water, no squeaky-clean feel.'),
        TipPoint('Ceramide moisturiser', 'Morning and night.'),
        TipPoint('Two-week pause', 'No exfoliants or retinoids.'),
      ],
      concerns: {Concern.sensitivity, Concern.redness, Concern.dryness},
    ),
    Tip(
      id: 'oily-moisturiser',
      title: 'Oily skin still needs moisturiser',
      teaser: 'Skipping it can make shine worse.',
      kind: TipKind.myth,
      image: '$_p/leaf_dew.webp',
      points: [
        TipPoint('Oil isn\'t water', 'Oily skin can still be dehydrated.'),
        TipPoint('Go light', 'Gel textures with glycerin or niacinamide.'),
        TipPoint('Blot, don\'t scrub', 'Wash twice a day, no more.'),
      ],
      concerns: {Concern.oiliness, Concern.largePores, Concern.acne},
    ),
    Tip(
      id: 'sebaceous-filaments',
      title: 'Blackheads or filaments?',
      teaser: 'Most grey dots on the nose are normal.',
      kind: TipKind.myth,
      image: '$_p/textures.webp',
      points: [
        TipPoint('Filaments are normal', 'Everyone has them. They refill.'),
        TipPoint('Blackheads are fewer', 'Darker and slightly raised.'),
        TipPoint('BHA helps both', 'Salicylic acid, 2–3 times a week.'),
      ],
      avoid: 'Pore strips and squeezing.',
      concerns: {Concern.blackheads, Concern.largePores},
    ),
    Tip(
      id: 'diet-acne',
      title: 'Does food cause breakouts?',
      teaser: 'For some people. Your check-ins can show if it\'s you.',
      kind: TipKind.lifestyle,
      image: '$_p/botanicals.webp',
      points: [
        TipPoint('Common suspects', 'Sugar-heavy diets and skim milk.'),
        TipPoint('Tag, don\'t guess', 'Log foods in your daily check-in.'),
        TipPoint('Test for 3 weeks', 'Cut one food, keep everything else.'),
      ],
      concerns: {Concern.acne},
    ),
    Tip(
      id: 'sleep-stress',
      title: 'Sleep, stress and skin',
      teaser: 'Why breakouts love busy weeks.',
      kind: TipKind.lifestyle,
      image: '$_p/cream_fabric.webp',
      points: [
        TipPoint('Stress adds oil', 'Hormones raise oil and inflammation.'),
        TipPoint('Keep it simple', 'Basics only. No new actives.'),
        TipPoint('Log it', 'Check-ins show how your skin follows your week.'),
      ],
      avoid: 'Stress-picking — it leaves the longest marks.',
    ),
    Tip(
      id: 'patch-test',
      title: 'Patch test in three nights',
      teaser: 'A two-minute habit that saves your face.',
      kind: TipKind.safety,
      image: '$_p/cream_white.webp',
      points: [
        TipPoint('Behind the ear', 'Or along the jaw, three nights running.'),
        TipPoint('All clear?', 'Then use it on your whole face.'),
        TipPoint('One at a time', 'Two weeks apart, so you know what works.'),
      ],
      concerns: {Concern.sensitivity, Concern.redness},
    ),
    Tip(
      id: 'pregnancy-safe',
      title: 'Skincare in pregnancy',
      teaser: 'What to pause, and what\'s usually considered safe.',
      kind: TipKind.safety,
      image: '$_p/plant_wall.webp',
      forPregnancy: true,
      points: [
        TipPoint('Pause', 'Retinoids and hydroquinone.'),
        TipPoint('Usually fine', 'Azelaic acid, niacinamide, vitamin C.'),
        TipPoint('SPF matters more', 'Pregnancy can trigger dark patches.'),
      ],
      avoid: 'Starting anything new without asking your doctor or midwife.',
    ),
    Tip(
      id: 'dark-circles',
      title: 'Dark circles, honestly',
      teaser: 'Some are pigment, some are shadow. Creams help one.',
      kind: TipKind.myth,
      image: '$_p/dropper_clear.webp',
      points: [
        TipPoint('Pigment', 'SPF and brighteners help over time.'),
        TipPoint('Puffiness', 'Caffeine helps for a few hours.'),
        TipPoint('Hollows', 'Structural. No cream fills them.'),
      ],
      avoid: 'Products that promise to "erase" circles.',
      concerns: {Concern.darkCircles},
    ),
    Tip(
      id: 'exfoliate-less',
      title: 'Exfoliation: less is more',
      teaser: 'Smoother skin comes from consistency, not scrubbing.',
      kind: TipKind.ingredients,
      image: '$_p/gel_swirl.webp',
      points: [
        TipPoint('Acids over scrubs', 'They work evenly, without micro-tears.'),
        TipPoint('Two or three nights', 'Never on retinoid nights.'),
        TipPoint('Stings? Stop', 'Pause two weeks and rebuild.'),
      ],
      concerns: {Concern.texture, Concern.blackheads, Concern.unevenTone},
    ),
    Tip(
      id: 'cycle-breakouts',
      title: 'Your cycle and breakouts',
      teaser: 'Jawline spots before your period are hormonal.',
      kind: TipKind.lifestyle,
      image: '$_p/leaf_shadow.webp',
      forCycle: true,
      points: [
        TipPoint('Expected timing', 'The week before your period.'),
        TipPoint('Stay steady', 'Same routine all month.'),
        TipPoint('Tag your period', 'See if breakouts follow it.'),
      ],
      avoid: 'Harsh spot treatments when a flare starts.',
      concerns: {Concern.acne},
    ),
    Tip(
      id: 'weekly-scans',
      title: 'Weekly scans beat daily selfies',
      teaser: 'Skin renews over weeks. Track it that way.',
      kind: TipKind.basics,
      image: '$_p/sage_waves.webp',
      points: [
        TipPoint('Once a week', 'Daily photos mostly show lighting.'),
        TipPoint('Same setup', 'Same time, facing a window, no makeup.'),
        TipPoint('Give it 6–12 weeks', 'Trust the trend line.'),
      ],
    ),
  ];

  static Tip? byId(String id) => all.where((t) => t.id == id).firstOrNull;

  /// Tips ranked for this person: life-stage specific first, then by how many
  /// of their concerns a tip covers.
  static List<Tip> forProfile(UserProfile? p, {int limit = 6}) {
    if (p == null) return all.take(limit).toList();
    final deep = p.skinTone?.pihProne ?? false;
    final cycle = p.gender != Gender.man && !p.pregnantOrNursing;

    bool eligible(Tip t) =>
        (!t.forShavers || p.shaves) &&
        (!t.forPregnancy || p.pregnantOrNursing) &&
        (!t.forCycle || cycle);

    int score(Tip t) {
      var s = t.concerns.intersection(p.concerns).length * 10;
      if (t.forPregnancy && p.pregnantOrNursing) s += 100;
      if (t.forShavers && p.shaves && p.concerns.contains(Concern.razorBumps)) {
        s += 40;
      }
      if (t.forShavers && p.shaves) s += 15;
      if (t.forDeeperTones && deep) s += 30;
      if (t.forCycle && cycle && p.concerns.contains(Concern.acne)) s += 12;
      if (t.concerns.isEmpty) s += 3; // universal basics
      return s;
    }

    final ranked = all.where(eligible).toList()
      ..sort((a, b) => score(b).compareTo(score(a)));
    return ranked.take(limit).toList();
  }
}
