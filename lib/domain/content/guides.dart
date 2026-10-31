import '../../data/models/profile.dart';
import '../guidance/habits.dart';

/// One point in a guide: a few-word headline, one or two sentences, and how
/// solid the evidence is when that's worth saying.
class GuidePoint {
  const GuidePoint(this.title, this.detail, [this.evidence]);
  final String title;
  final String detail;
  final Evidence? evidence;
}

class GuideSection {
  const GuideSection(this.heading, this.points, {this.avoid = false});
  final String heading;
  final List<GuidePoint> points;

  /// A "don't" list: drawn with a cross instead of numbers.
  final bool avoid;
}

/// A full guide: everything about one part of looking after skin, beyond
/// the routine. Longer than a tip; still one idea per line.
class Guide {
  const Guide({
    required this.id,
    required this.title,
    required this.teaser,
    required this.image,
    required this.minutes,
    required this.sections,
    this.premium = false,
    this.concerns = const {},
    this.forDeeperTones = false,
    this.forShavers = false,
  });

  final String id;
  final String title;

  /// The whole guide in one line.
  final String teaser;
  final String image;
  final int minutes;
  final List<GuideSection> sections;

  /// Free guides cover safety and the basics anyone needs; the rest of the
  /// library is part of Premium.
  final bool premium;
  final Set<Concern> concerns;
  final bool forDeeperTones;
  final bool forShavers;
}

const _p = 'assets/images/photos';

/// The guide library. Mainstream dermatology and nutrition guidance only;
/// evidence levels are stated, and nothing here replaces a doctor.
abstract final class GuideLibrary {
  static const all = <Guide>[
    Guide(
      id: 'budget',
      title: 'Great skin on a small budget',
      teaser: 'Three cheap products do most of the work. Everything else is optional.',
      image: '$_p/cream_white.webp',
      minutes: 3,
      sections: [
        GuideSection('The three that matter', [
          GuidePoint(
            'A gentle cleanser',
            'Any fragrance-free, low-foam wash. A pharmacy own-brand works as well as a premium one.',
            Evidence.strong,
          ),
          GuidePoint(
            'A plain moisturiser',
            'Look for glycerin, ceramides or petrolatum near the top of the list. A tub lasts months.',
            Evidence.strong,
          ),
          GuidePoint(
            'Sunscreen, SPF 30 or more',
            'The biggest anti-mark, anti-ageing step there is. Buy the one you will wear every day.',
            Evidence.strong,
          ),
        ]),
        GuideSection('Cheap swaps that work', [
          GuidePoint(
            'Petroleum jelly',
            'A thin layer over moisturiser at night seals in water. Ideal for dry, cracked or wind-burnt skin; skip it on breakout areas.',
            Evidence.strong,
          ),
          GuidePoint(
            'Generic actives',
            'Benzoyl peroxide 2.5–5%, salicylic acid 2% and adapalene 0.1% are the same molecules at any price.',
            Evidence.strong,
          ),
          GuidePoint(
            'Fewer products, used daily',
            'Two steps done every day beat ten done twice a week.',
            Evidence.moderate,
          ),
        ]),
        GuideSection('Make it last', [
          GuidePoint(
            'Pea-sized amounts',
            'A pea of cream covers the face; a dropper of serum is too much.',
          ),
          GuidePoint(
            'Keep it cool and closed',
            'Heat and light break down actives like vitamin C. Close lids tightly.',
          ),
          GuidePoint(
            'Scan your shelf first',
            'Before buying, check whether something you own already does the job.',
          ),
        ]),
      ],
    ),
    Guide(
      id: 'kitchen',
      title: 'Fruits and kitchen remedies: what helps, what burns',
      teaser: 'A few kitchen things soothe skin. Others cause burns and dark marks. Know which.',
      image: '$_p/botanicals.webp',
      minutes: 4,
      sections: [
        GuideSection('Safe to put on skin', [
          GuidePoint(
            'Oats for itchy, irritated skin',
            'Blend plain oats to a fine powder, stir into a lukewarm bath or mix with water to a paste. 10–15 minutes, rinse.',
            Evidence.strong,
          ),
          GuidePoint(
            'Raw honey as a mask',
            'A thin layer on clean skin for 10–15 minutes, rinse with lukewarm water. It holds moisture and is mildly antibacterial.',
            Evidence.limited,
          ),
          GuidePoint(
            'Fresh aloe vera gel',
            'Scoop the clear inner gel only (not the yellow sap), apply thinly after sun or irritation. Patch test first.',
            Evidence.limited,
          ),
          GuidePoint(
            'Cooled green tea compress',
            'Brew, chill, soak a clean cloth and hold it on red or puffy areas for 10 minutes.',
            Evidence.limited,
          ),
          GuidePoint(
            'Cold cucumber or spoons for puffy eyes',
            'The cold does the work, for an hour or so. Pleasant, not a treatment.',
          ),
        ]),
        GuideSection('Never on your face', avoid: true, [
          GuidePoint(
            'Lemon or lime juice',
            'Acid plus sun causes burns and blotchy dark marks that last months.',
            Evidence.strong,
          ),
          GuidePoint(
            'Baking soda and toothpaste',
            'Far too alkaline: they strip the barrier and leave redness worse than the spot.',
            Evidence.strong,
          ),
          GuidePoint(
            'Raw garlic, ginger, cinnamon',
            'They cause chemical burns on facial skin.',
            Evidence.strong,
          ),
          GuidePoint(
            'Sugar, salt or coffee scrubs',
            'Sharp grains tear the skin. Fine on rough feet, not on a face.',
            Evidence.moderate,
          ),
          GuidePoint(
            'Undiluted vinegar',
            'Burns. Diluted, it still does nothing an actual product does better.',
            Evidence.moderate,
          ),
          GuidePoint(
            'Coconut oil on acne-prone skin',
            'It clogs pores for many people. Keep it for body and hair.',
            Evidence.moderate,
          ),
        ]),
        GuideSection('Better eaten than applied', [
          GuidePoint(
            'Vitamin C fruit daily',
            'Guava, oranges, pawpaw, mango, pineapple, kiwi. Skin needs vitamin C to build collagen.',
            Evidence.moderate,
          ),
          GuidePoint(
            'Tomatoes cooked with a little oil',
            'Lycopene gives a small boost to the skin\'s own sun defence. It never replaces sunscreen.',
            Evidence.limited,
          ),
          GuidePoint(
            'Avocado, groundnuts, seeds, oily fish',
            'Vitamin E and omega-3 fats support a comfortable, less inflamed barrier.',
            Evidence.limited,
          ),
          GuidePoint(
            'Watermelon, cucumber, oranges',
            'Mostly water: they count towards your daily water.',
          ),
        ]),
      ],
    ),
    Guide(
      id: 'lightening',
      title: 'Skin-lightening creams: the hidden danger',
      teaser: 'Many "fairness" creams contain mercury or steroids. They damage skin for years.',
      image: '$_p/cream_beige.webp',
      minutes: 3,
      forDeeperTones: true,
      concerns: {Concern.darkSpots, Concern.unevenTone},
      sections: [
        GuideSection('What\'s often inside', avoid: true, [
          GuidePoint(
            'Mercury',
            'Banned in cosmetics in most countries, still found in unlabelled creams. It poisons the kidneys and nerves.',
            Evidence.strong,
          ),
          GuidePoint(
            'Strong steroids (clobetasol, betamethasone)',
            'They thin skin, cause stretch marks, acne and permanent darkening when stopped.',
            Evidence.strong,
          ),
          GuidePoint(
            'High-strength hydroquinone without a doctor',
            'Long use can cause ochronosis: blue-black patches that are very hard to treat.',
            Evidence.strong,
          ),
        ]),
        GuideSection('Warning signs', [
          GuidePoint(
            'Fast, dramatic lightening',
            'Real mark-fading takes 8–12 weeks. Anything faster is usually a steroid.',
          ),
          GuidePoint(
            'No ingredient list or a vague one',
            'Unlabelled or "herbal secret formula" creams are the most likely to be contaminated.',
          ),
          GuidePoint(
            'Skin that gets worse when you stop',
            'Rebound darkening and spots after stopping are classic steroid withdrawal. See a doctor.',
            Evidence.strong,
          ),
        ]),
        GuideSection('What fades marks safely', [
          GuidePoint(
            'Daily sunscreen first',
            'Without it, nothing else works: sun re-darkens marks within hours.',
            Evidence.strong,
          ),
          GuidePoint(
            'Azelaic acid, niacinamide, vitamin C',
            'Gentle, proven mark-faders that are safe on deeper skin tones.',
            Evidence.strong,
          ),
          GuidePoint(
            'Treat the cause',
            'Fewer breakouts and no picking means fewer new marks.',
            Evidence.strong,
          ),
        ]),
      ],
    ),
    Guide(
      id: 'water',
      title: 'Water and your skin',
      teaser: 'Enough water keeps skin from looking dull and tight. More than enough does nothing extra.',
      image: '$_p/water.webp',
      minutes: 2,
      sections: [
        GuideSection('How much', [
          GuidePoint(
            'About 33 ml per kg of body weight',
            'Around 80% of that from drinks; food covers the rest. Your target is on Today.',
            Evidence.moderate,
          ),
          GuidePoint(
            'More on hot days and when you sweat',
            'Add about half a litre per hour of exercise and on days over 30°C.',
            Evidence.moderate,
          ),
          GuidePoint(
            'Pale yellow is the goal',
            'Dark urine means drink more; completely clear means you can ease off.',
            Evidence.moderate,
          ),
        ]),
        GuideSection('Make it easy', [
          GuidePoint(
            'A glass with each routine',
            'Morning routine, glass. Evening routine, glass. Two done before you think about it.',
          ),
          GuidePoint(
            'Spread it out',
            'A glass every couple of hours beats a litre at night (and saves your sleep).',
          ),
          GuidePoint(
            'Tea, milk and fruit count',
            'Sugary drinks count as water but work against breakouts.',
            Evidence.moderate,
          ),
        ]),
        GuideSection('Honestly', [
          GuidePoint(
            'Water is not a moisturiser',
            'Dry, flaky skin needs a barrier cream. Drinking more won\'t fix it if you already drink enough.',
            Evidence.moderate,
          ),
        ]),
      ],
    ),
    Guide(
      id: 'weather',
      title: 'Dress your skin for the weather',
      teaser: 'Heat, humidity, wind and sun each change what your skin needs. Adjust the routine, not just clothes.',
      image: '$_p/leaf_dew.webp',
      minutes: 3,
      premium: true,
      sections: [
        GuideSection('Hot and humid', [
          GuidePoint(
            'Lighter moisturiser',
            'A gel or lotion instead of a thick cream; humidity already holds water in.',
          ),
          GuidePoint(
            'Rinse sweat quickly',
            'Within 30 minutes of sweating, especially under caps, helmets and straps.',
            Evidence.moderate,
          ),
          GuidePoint(
            'Water-resistant sunscreen',
            'Reapply every two hours outside and after sweating.',
            Evidence.strong,
          ),
        ]),
        GuideSection('Dry, dusty or windy', [
          GuidePoint(
            'Richer cream, sealed at night',
            'Low humidity pulls water out of skin. A thin layer of petroleum jelly over moisturiser helps.',
            Evidence.strong,
          ),
          GuidePoint(
            'Cleanse gently at night',
            'Dust and pollution sit on skin all day; one gentle cleanse removes them without stripping.',
          ),
          GuidePoint(
            'Fewer acids for a while',
            'Pause exfoliating acids if skin stings in dry wind.',
          ),
        ]),
        GuideSection('Sun and UV', [
          GuidePoint(
            'UV 3 and above: sunscreen and shade',
            'Clouds block little UV. The UV index on Today tells you the day\'s peak.',
            Evidence.strong,
          ),
          GuidePoint(
            'Every skin tone needs it',
            'On deeper skin, UV darkens marks more than it burns.',
            Evidence.strong,
          ),
          GuidePoint(
            'Hats and shade count',
            'A wide brim cuts UV on the face by about half.',
            Evidence.moderate,
          ),
        ]),
        GuideSection('Cold', [
          GuidePoint(
            'Lukewarm, not hot, water',
            'Hot showers on cold days strip the barrier fast.',
            Evidence.moderate,
          ),
          GuidePoint(
            'Lip balm and a scarf',
            'Lips have no oil glands; wind cracks them first.',
          ),
        ]),
      ],
    ),
    Guide(
      id: 'bedding',
      title: 'Pillows, sheets, towels and phones',
      teaser: 'Your skin spends hours pressed against fabric and screens. Keep them clean.',
      image: '$_p/cream_fabric.webp',
      minutes: 2,
      premium: true,
      concerns: {Concern.acne, Concern.sensitivity, Concern.redness},
      sections: [
        GuideSection('How often', [
          GuidePoint(
            'Pillowcase: every 2–3 nights if you break out',
            'Weekly otherwise. Flip it in between for a clean side.',
            Evidence.moderate,
          ),
          GuidePoint(
            'Sheets: weekly',
            'Hot wash kills mites and bacteria; dry fully in sun or a dryer.',
          ),
          GuidePoint(
            'Face towel: your own, every 2–3 uses',
            'Pat, don\'t rub. A damp shared towel spreads bacteria.',
            Evidence.moderate,
          ),
          GuidePoint(
            'Makeup brushes and sponges: weekly',
            'Mild soap, rinse, dry flat.',
            Evidence.moderate,
          ),
        ]),
        GuideSection('Everyday contact', [
          GuidePoint(
            'Wipe your phone daily',
            'It touches your cheek and jaw on every call. An alcohol wipe or a damp cloth with soap.',
          ),
          GuidePoint(
            'Hair oil and pomade off the forehead',
            'Oily hair products clog pores along the hairline. Wash your face after applying them.',
            Evidence.moderate,
          ),
          GuidePoint(
            'Fragrance-free laundry if you\'re sensitive',
            'Fabric softener and scented detergent are common hidden irritants.',
            Evidence.moderate,
          ),
          GuidePoint(
            'Satin or silk is optional',
            'Smoother on skin and hair, but a clean cotton case does the main job.',
            Evidence.limited,
          ),
        ]),
      ],
    ),
    Guide(
      id: 'food',
      title: 'Eating for clearer skin',
      teaser: 'A few food patterns are linked to breakouts and redness. Test them on yourself for four weeks.',
      image: '$_p/leaf_shadow.webp',
      minutes: 3,
      premium: true,
      concerns: {Concern.acne, Concern.redness, Concern.oiliness},
      sections: [
        GuideSection('Linked to breakouts', [
          GuidePoint(
            'Sugary drinks and white carbs',
            'Fast-digesting sugar spikes hormones that drive oil. Swap soda and juice for water and whole grains.',
            Evidence.moderate,
          ),
          GuidePoint(
            'Milk, especially skimmed',
            'Some people break out more on dairy. Try four weeks without and compare your scans.',
            Evidence.moderate,
          ),
          GuidePoint(
            'Whey protein shakes',
            'A common trigger for jawline and back acne in gym-goers.',
            Evidence.moderate,
          ),
        ]),
        GuideSection('Linked to redness', [
          GuidePoint(
            'Alcohol, hot drinks, spicy food',
            'Classic flush triggers. Log them in check-ins to see which are yours.',
            Evidence.moderate,
          ),
        ]),
        GuideSection('Good for skin', [
          GuidePoint(
            'Oily fish, beans, nuts and seeds',
            'Omega-3 fats and zinc calm inflammation.',
            Evidence.limited,
          ),
          GuidePoint(
            'Colourful fruit and vegetables',
            'Vitamin C and antioxidants help skin repair.',
            Evidence.moderate,
          ),
          GuidePoint(
            'Chocolate, honestly',
            'The evidence is weak. If it\'s dark and low in sugar, don\'t worry about it.',
            Evidence.limited,
          ),
        ]),
        GuideSection('How to test', [
          GuidePoint(
            'One change at a time, four weeks',
            'Skin turns over in about a month. Change one thing, scan weekly, compare.',
          ),
        ]),
      ],
    ),
    Guide(
      id: 'sleep_stress',
      title: 'Sleep, stress and exercise',
      teaser: 'Stress hormones raise oil and slow repair. The basics show up in your scans.',
      image: '$_p/warm_shadow.webp',
      minutes: 2,
      premium: true,
      sections: [
        GuideSection('Sleep', [
          GuidePoint(
            '7–9 hours',
            'Skin repairs overnight; short sleep shows as dullness and dark circles.',
            Evidence.moderate,
          ),
          GuidePoint(
            'Same side, clean case',
            'If breakouts sit on one cheek, it\'s often the side you sleep on.',
          ),
        ]),
        GuideSection('Stress', [
          GuidePoint(
            'Expect flares in stressful weeks',
            'Exams and deadlines raise cortisol and oil. Keep the routine simple then, don\'t add new actives.',
            Evidence.moderate,
          ),
          GuidePoint(
            'Ten minutes a day',
            'A walk, breathing or prayer: anything that lowers stress shows up within weeks.',
            Evidence.limited,
          ),
        ]),
        GuideSection('Exercise', [
          GuidePoint(
            'Sweat is fine, leaving it isn\'t',
            'Rinse or cleanse within 30 minutes and change out of damp clothes.',
            Evidence.moderate,
          ),
          GuidePoint(
            'Sunscreen for outdoor training',
            'Water-resistant, reapplied every two hours.',
            Evidence.strong,
          ),
        ]),
      ],
    ),
  ];

  static Guide? byId(String id) => all.where((g) => g.id == id).firstOrNull;

  /// The library in the order that matters most to this person: guides for
  /// their concerns and skin first, free ones before Premium ones.
  static List<Guide> forProfile(UserProfile? p) {
    if (p == null) return all;
    int score(Guide g) {
      var s = 0;
      if (g.concerns.any(p.concerns.contains)) s += 3;
      if (g.forDeeperTones && (p.skinTone?.pihProne ?? false)) s += 3;
      if (g.forShavers && p.shaves) s += 2;
      if (p.budget == Budget.low && g.id == 'budget') s += 4;
      if (!g.premium) s += 1;
      return s;
    }

    return [...all]..sort((a, b) => score(b).compareTo(score(a)));
  }

  /// One guide a day, rotating, so Today always has something new to read.
  static Guide ofTheDay(UserProfile? p, DateTime day) {
    final list = forProfile(p);
    final n = DateTime.utc(
      day.year,
      day.month,
      day.day,
    ).difference(DateTime.utc(2026)).inDays;
    return list[n % list.length];
  }
}
