import '../../data/models/check_in.dart';
import '../../data/models/product.dart';
import '../../data/models/profile.dart';
import '../../data/models/scan.dart';
import '../ingredients/ingredient_kb.dart';
import '../ingredients/product_analyzer.dart';

class RoutineStep {
  const RoutineStep({
    required this.id,
    required this.slot,
    required this.title,
    required this.category,
    required this.why,
    required this.howTo,
    this.keyIngredients = const [],
    this.days = const {},
    this.caution,
    this.optional = false,
    this.matchedProduct,
  });

  /// Stable semantic id ("pm.retinoid"). Completion logs reference it, so it
  /// must not change when the routine is regenerated.
  final String id;
  final RoutineSlot slot;
  final String title;
  final ProductCategory category;
  final String why;
  final String howTo;
  final List<String> keyIngredients;

  /// ISO weekdays (1 = Mon .. 7 = Sun). Empty = every day.
  final Set<int> days;
  final String? caution;
  final bool optional;

  /// A product from the user's shelf that fills this step, if any.
  final Product? matchedProduct;

  bool isScheduledOn(DateTime date) =>
      days.isEmpty || days.contains(date.weekday);

  RoutineStep withProduct(Product? p) => RoutineStep(
    id: id,
    slot: slot,
    title: title,
    category: category,
    why: why,
    howTo: howTo,
    keyIngredients: keyIngredients,
    days: days,
    caution: caution,
    optional: optional,
    matchedProduct: p,
  );
}

class Routine {
  const Routine({required this.am, required this.pm, required this.notes});

  final List<RoutineStep> am;
  final List<RoutineStep> pm;
  final List<String> notes;

  List<RoutineStep> stepsFor(RoutineSlot slot, DateTime date) =>
      (slot == RoutineSlot.am ? am : pm)
          .where((s) => s.isScheduledOn(date))
          .toList();
}

/// The treatment "lane" chosen for evening actives. Only one strong active
/// family runs on a given night, which removes the most common cause of
/// irritation (stacking).
enum _PmActive { retinoid, adapalene, bha, aha, azelaic }

/// Deterministic, rule-based routine builder. Rules follow mainstream
/// dermatology guidance; the AI never invents a routine, which keeps advice
/// consistent, explainable, offline and free to compute.
abstract final class RoutineEngine {
  static const _mwf = {1, 3, 5};
  static const _tueSat = {2, 6};
  static const _monThu = {1, 4};

  static Routine build({
    required UserProfile profile,
    SkinAnalysis? latest,
    List<Product> shelf = const [],
  }) {
    final focus = _focus(profile, latest);
    final type = _effectiveSkinType(profile, latest);
    final sensitive = profile.isSensitive;
    final pregnant = profile.pregnantOrNursing;
    final minimal = profile.complexity == RoutineComplexity.minimal;
    final enthusiast = profile.complexity == RoutineComplexity.enthusiast;
    final deepTone = profile.skinTone?.pihProne ?? false;
    final oily = type == SkinType.oily || focus.contains(Concern.oiliness);
    final dry = type == SkinType.dry || focus.contains(Concern.dryness);

    final notes = <String>[];
    final am = <RoutineStep>[];
    final pm = <RoutineStep>[];

    // ── Choose evening actives ────────────────────────────────────────
    final pmActives = <_PmActive>[];
    final acne = focus.contains(Concern.acne);
    final clogged =
        focus.contains(Concern.blackheads) ||
        focus.contains(Concern.largePores);
    final marks =
        focus.contains(Concern.darkSpots) || focus.contains(Concern.unevenTone);
    final aging =
        focus.contains(Concern.fineLines) ||
        profile.goals.contains(Goal.antiAging);
    final texture = focus.contains(Concern.texture);
    final redness =
        focus.contains(Concern.redness) || focus.contains(Concern.sensitivity);
    final razor = profile.shaves && focus.contains(Concern.razorBumps);

    if (pregnant) {
      if (acne || marks || redness || clogged) pmActives.add(_PmActive.azelaic);
      if (texture && !sensitive) pmActives.add(_PmActive.aha);
    } else {
      if (acne) {
        pmActives.add(_PmActive.adapalene);
      } else if (aging || (marks && !redness)) {
        pmActives.add(_PmActive.retinoid);
      }
      if (clogged && !acne) pmActives.add(_PmActive.bha);
      if (razor && !pmActives.contains(_PmActive.bha)) {
        pmActives.add(_PmActive.bha);
      }
      if (texture &&
          !pmActives.contains(_PmActive.bha) &&
          !(sensitive && pmActives.isNotEmpty)) {
        pmActives.add(_PmActive.aha);
      }
      if ((redness || (marks && deepTone)) &&
          !pmActives.contains(_PmActive.azelaic)) {
        pmActives.add(_PmActive.azelaic);
      }
    }

    final maxActives = minimal ? 1 : (enthusiast ? 3 : 2);
    while (pmActives.length > maxActives) {
      pmActives.removeLast();
    }

    // ── Morning ───────────────────────────────────────────────────────
    final useBpoWash = acne && !sensitive && !minimal && !dry;
    am.add(
      RoutineStep(
        id: 'am.cleanse',
        slot: RoutineSlot.am,
        category: ProductCategory.cleanser,
        title: useBpoWash
            ? 'Benzoyl peroxide wash'
            : dry || sensitive
            ? 'Rinse or gentle cream cleanse'
            : 'Gentle gel cleanser',
        keyIngredients: useBpoWash
            ? const ['Benzoyl peroxide 2.5–5%']
            : const [],
        why: useBpoWash
            ? 'Kills acne-causing bacteria as a short-contact wash, with less dryness than a leave-on.'
            : dry || sensitive
            ? 'Your skin keeps its natural oils overnight; a gentle cleanse avoids stripping them.'
            : 'Removes overnight oil and sweat so the rest of your routine works better.',
        howTo: useBpoWash
            ? 'Massage on for 1–2 minutes, rinse. Use a white towel: it bleaches fabric.'
            : 'Lukewarm water, 20–30 seconds, pat dry.',
      ),
    );

    if (profile.shaves) {
      am.add(
        const RoutineStep(
          id: 'am.shave',
          slot: RoutineSlot.am,
          category: ProductCategory.shaving,
          title: 'Shave & soothe (shave days)',
          keyIngredients: ['Panthenol', 'Allantoin', 'Fragrance-free balm'],
          why: 'Most razor bumps come from technique and irritation, not the razor itself.',
          howTo: 'Shave after cleansing on warm, damp skin, with the grain, light pressure, sharp blade. Finish with a fragrance-free balm — skip alcohol aftershaves.',
          optional: true,
        ),
      );
    }

    if (!minimal) {
      final vitC =
          (marks || aging || profile.goals.contains(Goal.glow)) &&
          !pmActives.contains(_PmActive.azelaic);
      final niacin = oily || clogged || acne || redness;
      if (vitC) {
        am.add(
          RoutineStep(
            id: 'am.antioxidant',
            slot: RoutineSlot.am,
            category: ProductCategory.serum,
            title: sensitive ? 'Gentle vitamin C serum' : 'Vitamin C serum',
            keyIngredients: sensitive
                ? const ['Ascorbyl glucoside', 'Sodium ascorbyl phosphate']
                : const ['L-ascorbic acid 10–15%', 'Vitamin E', 'Ferulic acid'],
            why: 'Brightens, fades marks and boosts your sunscreen\'s protection against UV and pollution.',
            howTo: '3–4 drops on dry skin, wait a minute before moisturiser.',
          ),
        );
      }
      if (niacin && (!vitC || enthusiast)) {
        am.add(
          const RoutineStep(
            id: 'am.niacinamide',
            slot: RoutineSlot.am,
            category: ProductCategory.serum,
            title: 'Niacinamide serum',
            keyIngredients: ['Niacinamide 4–5%', 'Zinc PCA'],
            why: 'Balances oil, refines the look of pores and calms redness. Gentle and pairs with everything.',
            howTo: 'A few drops after cleansing. Higher strengths aren\'t better; 4–5% is the sweet spot.',
          ),
        );
      }
    }

    if (!minimal) {
      am.add(_moisturizer(RoutineSlot.am, oily: oily, dry: dry));
    }

    am.add(
      RoutineStep(
        id: 'am.spf',
        slot: RoutineSlot.am,
        category: ProductCategory.sunscreen,
        title: minimal ? 'Moisturiser with SPF 30+' : 'Sunscreen SPF 30+',
        keyIngredients: deepTone
            ? const ['Invisible chemical/hybrid filters', 'or tinted mineral']
            : const ['Broad-spectrum', 'SPF 30–50'],
        why: deepTone
            ? 'Your #1 tool against dark marks: UV makes pigmentation darker and slower to fade, on every skin tone.'
            : 'Prevents up to 80% of visible skin aging and stops marks from darkening. Non-negotiable with actives.',
        howTo: deepTone
            ? 'Two finger-lengths for face and neck. Choose a formula without white cast so you\'ll actually wear it. Reapply every 2 hours outdoors.'
            : 'Two finger-lengths for face and neck, as the last step. Reapply every 2 hours outdoors.',
      ),
    );

    // ── Evening ───────────────────────────────────────────────────────
    pm.add(
      RoutineStep(
        id: 'pm.cleanse',
        slot: RoutineSlot.pm,
        category: ProductCategory.cleanser,
        title: enthusiast ? 'Double cleanse' : 'Cleanse',
        keyIngredients: enthusiast
            ? const ['Cleansing balm or oil', 'then gentle cleanser']
            : const [],
        why: 'Removes sunscreen, makeup, pollution and oil so your treatment can reach the skin.',
        howTo: enthusiast
            ? 'Massage a balm/oil on dry skin, emulsify with water, then follow with your gentle cleanser.'
            : 'Gentle cleanser, 30–60 seconds, pat dry. On treatment nights, wait until skin is fully dry.',
      ),
    );

    final schedule = _schedule(pmActives, sensitive: sensitive);
    for (final active in pmActives) {
      pm.add(
        _activeStep(
          active,
          schedule[active]!,
          sensitive: sensitive,
          deepTone: deepTone,
          razor: razor,
        ),
      );
    }

    pm.add(_moisturizer(RoutineSlot.pm, oily: oily, dry: dry, night: true));

    if (enthusiast &&
        (focus.contains(Concern.darkCircles) ||
            focus.contains(Concern.fineLines))) {
      pm.add(
        const RoutineStep(
          id: 'pm.eye',
          slot: RoutineSlot.pm,
          category: ProductCategory.eyeCream,
          title: 'Eye cream',
          keyIngredients: ['Caffeine', 'Peptides', 'Niacinamide'],
          why: 'Hydrates the thin under-eye skin; caffeine can temporarily reduce puffiness.',
          howTo: 'Pat a rice-grain amount along the orbital bone with your ring finger.',
          optional: true,
        ),
      );
    }

    if (acne && !minimal) {
      pm.add(
        RoutineStep(
          id: 'pm.spot',
          slot: RoutineSlot.pm,
          category: ProductCategory.treatment,
          title: 'Spot care (as needed)',
          keyIngredients: pregnant
              ? const ['Hydrocolloid patch']
              : const ['Hydrocolloid patch', 'or sulfur spot treatment'],
          why: 'Protects active spots from picking, which is what leaves marks and scars.',
          howTo: 'Patch over a whitehead overnight. Never squeeze.',
          optional: true,
        ),
      );
    }

    // ── Guidance notes ────────────────────────────────────────────────
    if (pmActives.isNotEmpty) {
      notes.add(
        'Start one new active at a time and give it 2 weeks before adding another.',
      );
      notes.add(
        'Mild dryness or "purging" in your usual breakout spots can happen for 4–6 weeks with retinoids and acids. Burning, swelling or rash is not normal — stop and simplify.',
      );
    }
    if (pmActives.length > 1) {
      notes.add(
        'Your actives are on different nights on purpose (skin cycling). Recovery nights are just cleanse + moisturise.',
      );
    }
    if (sensitive) {
      notes.add(
        'Patch test new products behind the ear or on the jaw for 3 nights before using them on your whole face.',
      );
    }
    if (pregnant) {
      notes.add(
        'Your plan avoids retinoids and hydroquinone. Check any new product with your doctor or midwife.',
      );
    }
    if (profile.ageRange.isMinor) {
      notes.add(
        'Keep it simple and gentle. For persistent or painful acne, see a doctor — effective prescription treatments exist.',
      );
    }
    if (deepTone && (marks || acne)) {
      notes.add(
        'Deeper skin tones mark more easily after spots and irritation, so gentle and consistent beats strong and harsh.',
      );
    }
    notes.add(
      'Visible change takes 6–12 weeks of consistency. Scan every 1–2 weeks in similar light to track it.',
    );

    return Routine(
      am: _matchShelf(am, shelf, profile),
      pm: _matchShelf(pm, shelf, profile),
      notes: notes,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  static RoutineStep _moisturizer(
    RoutineSlot slot, {
    required bool oily,
    required bool dry,
    bool night = false,
  }) {
    final id = slot == RoutineSlot.am ? 'am.moisturize' : 'pm.moisturize';
    if (oily && !dry) {
      return RoutineStep(
        id: id,
        slot: slot,
        category: ProductCategory.moisturizer,
        title: 'Light gel moisturiser',
        keyIngredients: const ['Glycerin', 'Niacinamide', 'Non-comedogenic'],
        why: 'Oily skin still needs water. Skipping moisturiser can make skin produce more oil.',
        howTo: 'A pea-to-almond amount over face and neck.',
      );
    }
    if (dry) {
      return RoutineStep(
        id: id,
        slot: slot,
        category: ProductCategory.moisturizer,
        title: night ? 'Rich barrier cream' : 'Barrier moisturiser',
        keyIngredients: const [
          'Ceramides',
          'Glycerin',
          'Squalane or petrolatum',
        ],
        why: 'Repairs and seals your barrier so skin stays comfortable and less reactive.',
        howTo: night
            ? 'Apply generously. On treatment nights you can apply it before your active to buffer irritation.'
            : 'Apply on slightly damp skin to lock in hydration.',
      );
    }
    return RoutineStep(
      id: id,
      slot: slot,
      category: ProductCategory.moisturizer,
      title: 'Moisturiser',
      keyIngredients: const ['Glycerin', 'Ceramides'],
      why: 'Keeps your barrier strong, which makes every other product work better.',
      howTo: 'A pea-to-almond amount over face and neck.',
    );
  }

  /// Assigns each evening active its own nights so no two strong actives
  /// ever share a night (retinoid → acids → azelaic fills what's left).
  static Map<_PmActive, Set<int>> _schedule(
    List<_PmActive> actives, {
    required bool sensitive,
  }) {
    final out = <_PmActive, Set<int>>{};
    final retinoid = actives
        .where((a) => a == _PmActive.retinoid || a == _PmActive.adapalene)
        .firstOrNull;
    final hasAha = actives.contains(_PmActive.aha);
    final hasBha = actives.contains(_PmActive.bha);

    final retinoidNights = retinoid == null
        ? const <int>{}
        : (sensitive ? _monThu : _mwf);
    if (retinoid != null) out[retinoid] = retinoidNights;

    if (retinoid != null) {
      // Off-retinoid nights: Tue/Thu/Sat/Sun (or Tue/Wed/Fri/Sat/Sun).
      if (hasBha && hasAha) {
        out[_PmActive.bha] = const {2};
        out[_PmActive.aha] = const {6};
      } else if (hasBha) {
        out[_PmActive.bha] = sensitive ? const {6} : _tueSat;
      } else if (hasAha) {
        out[_PmActive.aha] = sensitive ? const {6} : _tueSat;
      }
    } else {
      if (hasBha && hasAha) {
        out[_PmActive.bha] = sensitive ? const {3} : _monThu;
        out[_PmActive.aha] = const {6};
      } else if (hasBha) {
        out[_PmActive.bha] = sensitive ? const {3} : _monThu;
      } else if (hasAha) {
        out[_PmActive.aha] = sensitive ? const {3} : _monThu;
      }
    }

    if (actives.contains(_PmActive.azelaic)) {
      final taken = {
        ...retinoidNights,
        ...?out[_PmActive.aha],
        ...?out[_PmActive.bha],
      };
      // Empty set means "every night" when nothing else is scheduled.
      out[_PmActive.azelaic] = taken.isEmpty
          ? const {}
          : {1, 2, 3, 4, 5, 6, 7}.difference(taken);
    }
    return out;
  }

  static RoutineStep _activeStep(
    _PmActive a,
    Set<int> days, {
    required bool sensitive,
    required bool deepTone,
    required bool razor,
  }) {
    final freq = days.isEmpty ? 'Nightly' : '${days.length}× a week';
    return switch (a) {
      _PmActive.adapalene => RoutineStep(
        id: 'pm.retinoid',
        slot: RoutineSlot.pm,
        category: ProductCategory.treatment,
        title: 'Adapalene 0.1% gel',
        keyIngredients: const ['Adapalene 0.1%'],
        days: days,
        why:
            'A proven retinoid for acne: unclogs pores and prevents new breakouts. $freq to start.',
        howTo: 'Pea-sized amount for the whole face on dry skin, avoiding eyes, nostrils and lips. Build to nightly over 4–8 weeks if comfortable.',
        caution: 'Not for use during pregnancy. Use sunscreen daily.',
      ),
      _PmActive.retinoid => RoutineStep(
        id: 'pm.retinoid',
        slot: RoutineSlot.pm,
        category: ProductCategory.treatment,
        title: sensitive ? 'Gentle retinoid' : 'Retinol serum',
        keyIngredients: sensitive
            ? const ['Retinal 0.05% or HPR', 'or retinol 0.1–0.2%']
            : const ['Retinol 0.2–0.5%'],
        days: days,
        why:
            'The best-studied ingredient for fine lines, texture and marks. $freq to start.',
        howTo: 'Pea-sized amount on dry skin. Increase frequency slowly as your skin adjusts.',
        caution: 'Not for use during pregnancy. Use sunscreen daily.',
      ),
      _PmActive.bha => RoutineStep(
        id: 'pm.bha',
        slot: RoutineSlot.pm,
        category: ProductCategory.exfoliant,
        title: razor ? 'BHA on beard area' : 'BHA exfoliant',
        keyIngredients: const ['Salicylic acid 1–2%'],
        days: days,
        why: razor
            ? 'Frees trapped hairs and calms razor bumps. $freq.'
            : 'Dissolves oil inside pores to clear blackheads. $freq.',
        howTo: razor
            ? 'Swipe or press over the beard area. Not on freshly shaved skin — wait a few hours.'
            : 'Apply on dry skin, leave on, then moisturise.',
      ),
      _PmActive.aha => RoutineStep(
        id: 'pm.aha',
        slot: RoutineSlot.pm,
        category: ProductCategory.exfoliant,
        title: sensitive || deepTone ? 'Gentle AHA' : 'AHA exfoliant',
        keyIngredients: sensitive || deepTone
            ? const ['Lactic or mandelic acid 5–10%']
            : const ['Glycolic acid 5–8%'],
        days: days,
        why: 'Smooths rough texture and brightens dullness. $freq.',
        howTo: 'Apply on dry skin, avoid the eye area, then moisturise.',
        caution:
            'Increases sun sensitivity. Stop if you see redness or peeling.',
      ),
      _PmActive.azelaic => RoutineStep(
        id: 'pm.azelaic',
        slot: RoutineSlot.pm,
        category: ProductCategory.treatment,
        title: 'Azelaic acid',
        keyIngredients: const ['Azelaic acid 10%'],
        days: days,
        why:
            'Calms redness, fights breakouts and fades marks. Gentle and pregnancy-friendly. $freq.',
        howTo: 'Thin layer on dry skin. A mild tingle in the first weeks is common.',
      ),
    };
  }

  static Set<Concern> _focus(UserProfile p, SkinAnalysis? scan) {
    final focus = {...p.concerns};
    if (scan == null || !scan.usable) return focus;
    for (final m in scan.metrics.where((m) => m.score < 55)) {
      final c = switch (m.metric) {
        SkinMetric.acne => Concern.acne,
        SkinMetric.texture => Concern.texture,
        SkinMetric.pores => Concern.largePores,
        SkinMetric.redness => Concern.redness,
        SkinMetric.pigmentation => Concern.darkSpots,
        SkinMetric.hydration => Concern.dryness,
        SkinMetric.oilBalance => Concern.oiliness,
        SkinMetric.fineLines => Concern.fineLines,
        SkinMetric.underEyes => Concern.darkCircles,
      };
      focus.add(c);
    }
    return focus;
  }

  static SkinType _effectiveSkinType(UserProfile p, SkinAnalysis? scan) {
    if (p.skinType != SkinType.unsure) return p.skinType;
    final est = scan?.skinTypeEstimate.toLowerCase() ?? '';
    return SkinType.values.where((t) => t.name == est).firstOrNull ??
        SkinType.normal;
  }

  /// Attaches shelf products to the steps they fulfil.
  static List<RoutineStep> _matchShelf(
    List<RoutineStep> steps,
    List<Product> shelf,
    UserProfile profile,
  ) {
    final active = shelf
        .where((p) => p.status == ProductStatus.active)
        .toList();
    if (active.isEmpty) return steps;
    final families = {
      for (final p in active)
        p.id: ProductAnalyzer.analyze(p.ingredientsRaw, profile).families,
    };
    final used = <String>{};

    Product? find(bool Function(Product, Set<Family>) test, RoutineSlot slot) {
      for (final p in active) {
        if (used.contains(p.id)) continue;
        final inSlot = slot == RoutineSlot.am ? p.usedAm : p.usedPm;
        if (inSlot && test(p, families[p.id]!)) {
          used.add(p.id);
          return p;
        }
      }
      return null;
    }

    return [
      for (final s in steps)
        s.withProduct(
          find((p, f) {
            return switch (s.id) {
              'pm.retinoid' => f.contains(Family.retinoid),
              'pm.bha' => f.contains(Family.bha),
              'pm.aha' => f.contains(Family.aha) || f.contains(Family.pha),
              'pm.azelaic' => f.contains(Family.azelaicAcid),
              'am.antioxidant' =>
                f.contains(Family.vitaminC) ||
                    f.contains(Family.vitaminCDerivative),
              'am.niacinamide' =>
                p.category == ProductCategory.serum &&
                    f.contains(Family.niacinamide),
              'am.cleanse'
                  when s.keyIngredients.any((k) => k.contains('Benzoyl')) =>
                f.contains(Family.benzoylPeroxide),
              'am.spf' =>
                p.category == ProductCategory.sunscreen ||
                    f.any(sunscreenFamilies.contains),
              _ => p.category == s.category,
            };
          }, s.slot),
        ),
    ];
  }
}
