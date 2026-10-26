import '../../data/models/profile.dart';
import 'ingredient_kb.dart';
import 'ingredient_parser.dart';

enum FlagSeverity { info, low, medium, high }

enum FlagKind {
  pregnancy,
  fragrance,
  essentialOil,
  comedogenic,
  dryingAlcohol,
  harshSurfactant,
  allergenPreservative,
  physicalScrub,
  strongActive,
  fungalAcne,
}

class IngredientFlag {
  const IngredientFlag({
    required this.kind,
    required this.severity,
    required this.title,
    required this.message,
    required this.ingredients,
  });

  final FlagKind kind;
  final FlagSeverity severity;
  final String title;
  final String message;
  final List<String> ingredients;
}

class Highlight {
  const Highlight({required this.ingredient, required this.forConcerns});
  final Ingredient ingredient;
  final Set<Concern> forConcerns;
}

enum Verdict {
  great('Great match'),
  good('Good match'),
  caution('Use with caution'),
  avoid('Not ideal for you'),
  unknown('Not enough data');

  const Verdict(this.label);
  final String label;
}

class ProductAnalysis {
  const ProductAnalysis({
    required this.ingredients,
    required this.families,
    required this.highlights,
    required this.flags,
    required this.fitScore,
    required this.verdict,
  });

  final List<ParsedIngredient> ingredients;
  final Set<Family> families;
  final List<Highlight> highlights;
  final List<IngredientFlag> flags;
  final int fitScore;
  final Verdict verdict;

  int get recognizedCount => ingredients.where((i) => i.match != null).length;

  bool get isSunscreen => families.any(sunscreenFamilies.contains);
  bool get isExfoliant => families.any(exfoliatingFamilies.contains);
  bool get hasRetinoid => families.contains(Family.retinoid);

  static const empty = ProductAnalysis(
    ingredients: [],
    families: {},
    highlights: [],
    flags: [],
    fitScore: 0,
    verdict: Verdict.unknown,
  );
}

/// Scores a product's ingredient list against a specific person's skin.
/// The same product can be "great" for one user and "not ideal" for another,
/// which is the point: generic "clean/toxic" ratings help nobody.
abstract final class ProductAnalyzer {
  static ProductAnalysis analyze(String ingredientsRaw, UserProfile? profile) {
    final parsed = IngredientParser.parse(ingredientsRaw);
    if (parsed.isEmpty) return ProductAnalysis.empty;

    final matched = parsed.where((p) => p.match != null).toList();
    final families = <Family>{for (final p in matched) ...p.match!.families};

    final concerns = profile?.concerns ?? const <Concern>{};
    final highlights = <Highlight>[];
    final seenHighlights = <String>{};
    for (final p in matched) {
      final ing = p.match!;
      final overlap = ing.goodFor.intersection(concerns);
      if (overlap.isNotEmpty && seenHighlights.add(ing.id)) {
        highlights.add(Highlight(ingredient: ing, forConcerns: overlap));
      }
    }

    final flags = _flags(matched, profile);

    if (matched.length < 3) {
      return ProductAnalysis(
        ingredients: parsed,
        families: families,
        highlights: highlights,
        flags: flags,
        fitScore: 0,
        verdict: Verdict.unknown,
      );
    }

    var score = 78;
    score += (highlights.length * 5).clamp(0, 20);
    for (final f in flags) {
      score -= switch (f.severity) {
        FlagSeverity.high => 30,
        FlagSeverity.medium => 12,
        FlagSeverity.low => 4,
        FlagSeverity.info => 0,
      };
    }
    score = score.clamp(0, 100);

    final hasHigh = flags.any((f) => f.severity == FlagSeverity.high);
    final verdict = hasHigh
        ? Verdict.avoid
        : score >= 82
        ? Verdict.great
        : score >= 66
        ? Verdict.good
        : score >= 45
        ? Verdict.caution
        : Verdict.avoid;

    return ProductAnalysis(
      ingredients: parsed,
      families: families,
      highlights: highlights,
      flags: flags
        ..sort((a, b) => b.severity.index.compareTo(a.severity.index)),
      fitScore: score,
      verdict: verdict,
    );
  }

  static List<IngredientFlag> _flags(
    List<ParsedIngredient> matched,
    UserProfile? p,
  ) {
    final sensitive = p?.isSensitive ?? false;
    final acneProne = p?.acneProne ?? false;
    final dry =
        p?.skinType == SkinType.dry ||
        (p?.concerns.contains(Concern.dryness) ?? false);
    final pregnant = p?.pregnantOrNursing ?? false;

    List<String> names(bool Function(ParsedIngredient) test) =>
        matched.where(test).map((e) => e.match!.name).toSet().toList();

    final flags = <IngredientFlag>[];

    // Pregnancy — always surfaced for pregnant/nursing users.
    final avoid = names(
      (i) => i.match!.pregnancyCaution == PregnancyCaution.avoid,
    );
    final ask = names(
      (i) => i.match!.pregnancyCaution == PregnancyCaution.askDoctor,
    );
    if (pregnant && avoid.isNotEmpty) {
      flags.add(
        IngredientFlag(
          kind: FlagKind.pregnancy,
          severity: FlagSeverity.high,
          title: 'Not recommended while pregnant or nursing',
          message: 'Contains ingredients commonly advised against during pregnancy and breastfeeding. Check with your doctor or midwife.',
          ingredients: avoid,
        ),
      );
    } else if (pregnant && ask.isNotEmpty) {
      flags.add(
        IngredientFlag(
          kind: FlagKind.pregnancy,
          severity: FlagSeverity.medium,
          title: 'Check with your doctor',
          message: 'Usually considered low-risk in wash-off products, but confirm leave-on use with your clinician.',
          ingredients: ask,
        ),
      );
    }

    // Fragrance & essential oils.
    final fragrance = names(
      (i) =>
          i.match!.families.contains(Family.fragrance) &&
          !i.match!.families.contains(Family.essentialOil),
    );
    if (fragrance.isNotEmpty) {
      flags.add(
        IngredientFlag(
          kind: FlagKind.fragrance,
          severity: sensitive ? FlagSeverity.medium : FlagSeverity.info,
          title: 'Contains fragrance',
          message: sensitive
              ? 'Fragrance is a top cause of reactions. With sensitive skin, fragrance-free is the safer choice.'
              : 'Fine for many people, but the first thing to cut if your skin ever reacts.',
          ingredients: fragrance,
        ),
      );
    }
    final eos = names((i) => i.match!.families.contains(Family.essentialOil));
    if (eos.isNotEmpty) {
      flags.add(
        IngredientFlag(
          kind: FlagKind.essentialOil,
          severity: sensitive ? FlagSeverity.medium : FlagSeverity.low,
          title: 'Contains essential oils',
          message: 'Concentrated plant fragrance; a frequent irritant. Citrus oils can react with sunlight.',
          ingredients: eos,
        ),
      );
    }

    // Pore-clogging: only meaningful for acne-prone skin.
    final comedo = names((i) => i.match!.comedogenic >= 3);
    if (comedo.isNotEmpty && acneProne) {
      final early = matched.any(
        (i) => i.match!.comedogenic >= 3 && i.position < 6,
      );
      flags.add(
        IngredientFlag(
          kind: FlagKind.comedogenic,
          severity: early ? FlagSeverity.medium : FlagSeverity.low,
          title: 'May clog pores',
          message: 'Has ingredients with a high pore-clogging rating. Ratings vary by formula, so watch for new breakouts over 2–4 weeks.',
          ingredients: comedo,
        ),
      );
    }

    // Drying alcohol high in the list.
    final dryingEarly = matched.where(
      (i) => i.match!.families.contains(Family.dryingAlcohol) && i.position < 5,
    );
    if (dryingEarly.isNotEmpty) {
      flags.add(
        IngredientFlag(
          kind: FlagKind.dryingAlcohol,
          severity: (dry || sensitive) ? FlagSeverity.medium : FlagSeverity.low,
          title: 'High in drying alcohol',
          message: 'Alcohol near the top of the list can strip and dehydrate skin over time.',
          ingredients: dryingEarly.map((e) => e.match!.name).toSet().toList(),
        ),
      );
    }

    final harsh = names(
      (i) => i.match!.families.contains(Family.harshSurfactant),
    );
    if (harsh.isNotEmpty) {
      flags.add(
        IngredientFlag(
          kind: FlagKind.harshSurfactant,
          severity: (dry || sensitive) ? FlagSeverity.medium : FlagSeverity.low,
          title: 'Strong cleansing agent',
          message: 'Can leave skin tight and irritated, especially if dry or sensitive.',
          ingredients: harsh,
        ),
      );
    }

    final allergens = names(
      (i) => i.match!.families.contains(Family.allergenPreservative),
    );
    if (allergens.isNotEmpty) {
      flags.add(
        IngredientFlag(
          kind: FlagKind.allergenPreservative,
          severity: sensitive ? FlagSeverity.medium : FlagSeverity.low,
          title: 'Allergy-prone preservative',
          message: 'A known contact allergen for a small share of people.',
          ingredients: allergens,
        ),
      );
    }

    final scrubs = names(
      (i) => i.match!.families.contains(Family.physicalExfoliant),
    );
    if (scrubs.isNotEmpty) {
      flags.add(
        IngredientFlag(
          kind: FlagKind.physicalScrub,
          severity: (sensitive || acneProne)
              ? FlagSeverity.medium
              : FlagSeverity.low,
          title: 'Gritty scrub particles',
          message: 'Rough particles can inflame breakouts and irritate. Chemical exfoliants are gentler.',
          ingredients: scrubs,
        ),
      );
    }

    final actives = names(
      (i) => i.match!.families.any(
        (f) => const {
          Family.retinoid,
          Family.aha,
          Family.bha,
          Family.benzoylPeroxide,
          Family.vitaminC,
          Family.hydroquinone,
        }.contains(f),
      ),
    );
    if (actives.isNotEmpty) {
      flags.add(
        IngredientFlag(
          kind: FlagKind.strongActive,
          severity: sensitive ? FlagSeverity.low : FlagSeverity.info,
          title: 'Contains active ingredients',
          message: 'Introduce slowly (2–3 times a week), don\'t stack with other strong actives, and wear SPF daily.',
          ingredients: actives,
        ),
      );
    }

    final fungal = names((i) => i.match!.fungalAcneTrigger);
    if (fungal.isNotEmpty) {
      flags.add(
        IngredientFlag(
          kind: FlagKind.fungalAcne,
          severity: FlagSeverity.info,
          title: 'Fungal-acne note',
          message: 'Only relevant if you have fungal acne (itchy, uniform little bumps): these ingredients can feed the yeast involved.',
          ingredients: fungal,
        ),
      );
    }

    return flags;
  }
}
