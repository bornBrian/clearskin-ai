import '../../data/models/check_in.dart';
import '../../data/models/product.dart';
import '../routine/routine_engine.dart';

/// Exactly how to use one routine step: how much, how to put it on, how
/// long it stays on, how long to wait before the next layer, and how to
/// take it off. Deterministic and offline, so it never contradicts itself
/// between days.
class ApplicationGuide {
  const ApplicationGuide({
    required this.amount,
    required this.technique,
    required this.contact,
    this.waitBeforeNext,
    this.removal,
  });

  final String amount;
  final String technique;

  /// How long it stays on the skin ("60 seconds, then rinse", "Overnight").
  final String contact;

  /// Pause before the next layer, when it matters.
  final Duration? waitBeforeNext;

  /// How to take it off, for anything that isn't left on until the next
  /// cleanse.
  final String? removal;

  /// Layering rules for the whole routine, shown once above the steps.
  static const layering = [
    'Thinnest to thickest: water-light layers first, creams after.',
    'Treatments go on clean, dry skin so they reach it evenly.',
    'In the morning, sunscreen is always last. Makeup goes on top of it.',
    'One strong active a night. More isn\'t faster; it\'s irritation.',
  ];

  static ApplicationGuide forStep(RoutineStep s) => switch (s.id) {
    'am.cleanse' when s.keyIngredients.any((k) => k.contains('Benzoyl')) =>
      const ApplicationGuide(
        amount: 'A pea-sized amount, worked into a lather.',
        technique: 'Massage over breakout areas with fingertips.',
        contact: '1–2 minutes on the skin, so the benzoyl peroxide can work.',
        removal: 'Rinse well with lukewarm water. Pat dry with a white towel (it bleaches fabric).',
      ),
    'am.cleanse' || 'pm.cleanse' => ApplicationGuide(
      amount: s.id == 'pm.cleanse' && s.title.contains('Double')
          ? 'Balm: an almond-sized scoop. Cleanser: a pea-sized amount.'
          : 'A pea-sized amount (two pumps for foams).',
      technique: s.id == 'pm.cleanse' && s.title.contains('Double')
          ? 'Massage the balm onto dry skin to melt sunscreen and makeup, add water to turn it milky, rinse, then wash with the cleanser.'
          : 'Massage in small circles on damp skin, including the hairline, jaw and sides of the nose.',
      contact: s.id == 'pm.cleanse'
          ? '60 seconds: long enough to break down sunscreen and oil.'
          : '20–30 seconds is enough in the morning.',
      removal: 'Rinse with lukewarm water, never hot. Pat dry with a clean towel; don\'t rub.',
    ),
    'am.shave' => const ApplicationGuide(
      amount: 'A thin layer of shave gel; a pea-sized amount of balm after.',
      technique: 'Warm, damp skin. Shave with the grain, light pressure, rinse the blade every stroke.',
      contact: 'Balm stays on.',
      removal: 'Rinse off any gel with cool water before the balm.',
    ),
    'am.toner' || 'pm.toner' => const ApplicationGuide(
      amount: '3–5 drops in your palm.',
      technique: 'Press into still-damp skin with both palms.',
      contact: 'Stays on. It\'s absorbed in about 30 seconds.',
    ),
    'am.antioxidant' => const ApplicationGuide(
      amount: '3–4 drops for face and neck.',
      technique: 'Pat onto dry skin; avoid the eye area.',
      contact: 'Stays on all day, under sunscreen, where it adds protection.',
      waitBeforeNext: Duration(minutes: 1),
    ),
    'am.niacinamide' => const ApplicationGuide(
      amount: '2–3 drops.',
      technique: 'Smooth over the face, focusing on oilier areas.',
      contact: 'Stays on.',
      waitBeforeNext: Duration(minutes: 1),
    ),
    'am.moisturize' || 'pm.moisturize' => ApplicationGuide(
      amount: 'A pea-to-almond-sized amount for face and neck.',
      technique: 'Warm between fingertips, then press in and smooth outward. Don\'t drag the skin.',
      contact: s.slot == RoutineSlot.am
          ? 'Stays on.'
          : 'Overnight. Rinse it off in the morning cleanse.',
      waitBeforeNext: s.slot == RoutineSlot.am
          ? const Duration(minutes: 2)
          : null,
    ),
    'am.spf' => const ApplicationGuide(
      amount: 'Two finger-lengths for face and neck. Less than that and you get a fraction of the SPF on the label.',
      technique: 'Dot over the face, spread evenly, don\'t forget ears, neck and hairline.',
      contact: 'All day. Reapply every 2 hours outdoors, and after sweating or swimming.',
      waitBeforeNext: Duration(minutes: 15),
      removal: 'At night: massage your cleanser (or a balm) for a full 60 seconds to break it down.',
    ),
    'pm.retinoid' => const ApplicationGuide(
      amount: 'One pea-sized amount for the whole face. More causes irritation, not results.',
      technique: 'Dot on forehead, cheeks and chin, then spread thinly. Keep away from eyes, nostril creases and lips.',
      contact: 'Overnight. Washed off in the morning cleanse.',
      waitBeforeNext: Duration(minutes: 5),
      removal: 'If it stings badly, rinse it off and use it every third night for a while.',
    ),
    'pm.bha' || 'pm.aha' => const ApplicationGuide(
      amount: 'Enough to wet the area: 3–4 drops, or one swipe of a pad.',
      technique: 'Apply to dry skin; skip broken or freshly shaved skin.',
      contact: 'Leave-on. A mild tingle is normal; burning isn\'t.',
      waitBeforeNext: Duration(minutes: 2),
      removal: 'If it burns, rinse with cool water and moisturise.',
    ),
    'pm.azelaic' => const ApplicationGuide(
      amount: 'A pea-sized amount.',
      technique: 'Thin layer on dry skin, over redness and marks.',
      contact: 'Overnight. A brief itch in the first weeks is common.',
      waitBeforeNext: Duration(minutes: 2),
    ),
    'pm.eye' => const ApplicationGuide(
      amount: 'A rice-grain amount for both eyes.',
      technique:
          'Tap along the orbital bone with your ring finger, not on the lid.',
      contact: 'Overnight.',
    ),
    'pm.spot' => const ApplicationGuide(
      amount: 'One patch per spot.',
      technique: 'Clean, dry skin. Press the patch on for a few seconds.',
      contact: '6–8 hours, or overnight, until it turns white.',
      removal: 'Peel slowly from one edge towards the centre, then cleanse.',
    ),
    _ => _byCategory(s.category),
  };

  static ApplicationGuide _byCategory(ProductCategory c) => switch (c) {
    ProductCategory.mask => const ApplicationGuide(
      amount: 'An even, opaque layer.',
      technique: 'Clean skin, avoid eyes and lips.',
      contact: '10–15 minutes. Clay: take it off before it fully cracks.',
      removal:
          'Soften with lukewarm water and a cloth, rinse, then moisturise.',
    ),
    ProductCategory.exfoliant => const ApplicationGuide(
      amount: '3–4 drops or one pad.',
      technique: 'Dry skin, avoid the eye area. No scrubbing.',
      contact: 'Leave-on unless the label says rinse-off.',
      waitBeforeNext: Duration(minutes: 2),
    ),
    ProductCategory.makeup => const ApplicationGuide(
      amount: 'As little as gives the coverage you want.',
      technique: 'Over sunscreen, with clean brushes or sponges (wash weekly).',
      contact: 'All day; never sleep in it.',
      removal: 'Balm or micellar water first, then your cleanser.',
    ),
    _ => const ApplicationGuide(
      amount: 'A small amount; follow the label.',
      technique: 'Apply to clean skin.',
      contact: 'As directed.',
    ),
  };
}
