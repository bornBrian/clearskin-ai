import 'package:clearskin_ai/data/models/product.dart';
import 'package:clearskin_ai/data/models/profile.dart';
import 'package:clearskin_ai/domain/ingredients/ingredient_kb.dart';
import 'package:clearskin_ai/domain/ingredients/product_analyzer.dart';
import 'package:clearskin_ai/domain/products/shelf_life.dart';
import 'package:clearskin_ai/domain/routine/routine_engine.dart';
import 'package:clearskin_ai/domain/scan/skin_maps.dart';
import 'package:clearskin_ai/domain/scan/skin_measure.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

SkinMeasure measure(
  Map<SkinLens, double> coverage, {
  Map<SkinLens, Map<String, double>> zones = const {},
  double light = 65,
}) => SkinMeasure(coverage: coverage, zones: zones, skinLightness: light);

void main() {
  group('Progress proof', () {
    test('reports real improvements with the zone that changed most', () {
      final proof = ProgressProof.compare(
        measure(
          {SkinLens.redness: 0.20, SkinLens.tone: 0.10, SkinLens.shine: 0.08},
          zones: {
            SkinLens.redness: {'cheeks': 0.30, 'jaw': 0.25},
          },
        ),
        measure(
          {SkinLens.redness: 0.12, SkinLens.tone: 0.095, SkinLens.shine: 0.10},
          zones: {
            SkinLens.redness: {'cheeks': 0.12, 'jaw': 0.22},
          },
        ),
        days: 42,
      )!;
      final redness = proof.changes.first;
      expect(redness.lens, SkinLens.redness);
      expect(redness.change, closeTo(-0.4, 0.001));
      expect(redness.zone, 'cheeks');
      // Tone moved 5%: noise, not reported.
      expect(proof.changes.any((c) => c.lens == SkinLens.tone), isFalse);
      // Shine got worse and is shown, never hidden.
      expect(
        proof.changes.firstWhere((c) => c.lens == SkinLens.shine).improved,
        isFalse,
      );
      expect(proof.improvements.length, 1);
      expect(
        ProgressProof.sentence(redness),
        'Redness: 40% less than day 1, most on your cheeks.',
      );
      expect(proof.lightingDiffers, isFalse);
    });

    test('tiny day-one readings are not turned into big percentages', () {
      expect(
        ProgressProof.compare(
          measure({SkinLens.redness: 0.01}),
          measure({SkinLens.redness: 0.0}),
          days: 30,
        ),
        isNull,
      );
    });

    test('flags photos taken in very different light', () {
      final proof = ProgressProof.compare(
        measure({SkinLens.redness: 0.2}, light: 52),
        measure({SkinLens.redness: 0.1}, light: 70),
        days: 30,
      )!;
      expect(proof.lightingDiffers, isTrue);
    });

    test('survives a JSON round trip', () {
      final m = measure(
        {SkinLens.redness: 0.1234567, SkinLens.texture: 0.05},
        zones: {
          SkinLens.redness: {'forehead': 0.2},
        },
      );
      final back = SkinMeasure.fromJson(m.toJson())!;
      expect(back.coverage[SkinLens.redness], closeTo(0.1235, 0.0001));
      expect(back.zones[SkinLens.redness]!['forehead'], 0.2);
      expect(back.skinLightness, 65);
      expect(SkinMeasure.fromJson('junk'), isNull);
    });
  });

  group('I react to', () {
    const fragranced =
        'Water, Glycerin, Cetearyl Alcohol, Niacinamide, Parfum, Phenoxyethanol, Dimethicone';

    test('a product with a known trigger is flagged and not recommended', () {
      final me = profile().copyWith(reactsTo: {Reaction.niacinamide});
      final a = ProductAnalyzer.analyze(fragranced, me);
      expect(a.flags.first.kind, FlagKind.personal);
      expect(a.flags.first.ingredients.join(), contains('Niacinamide'));
      expect(a.verdict, Verdict.avoid);
      // Without the reaction the same product is fine.
      expect(
        ProductAnalyzer.analyze(fragranced, profile()).verdict,
        isNot(Verdict.avoid),
      );
    });

    test('the routine swaps a retinoid for azelaic acid and drops niacinamide', () {
      final base = profile(
        concerns: {Concern.acne, Concern.oiliness},
        complexity: RoutineComplexity.balanced,
      );
      expect(
        RoutineEngine.build(profile: base).pm.map((s) => s.id),
        contains('pm.retinoid'),
      );
      final r = RoutineEngine.build(
        profile: base.copyWith(
          reactsTo: {Reaction.retinoids, Reaction.niacinamide},
        ),
      );
      final ids = [...r.am, ...r.pm].map((s) => s.id);
      expect(ids, isNot(contains('pm.retinoid')));
      expect(ids, contains('pm.azelaic'));
      expect(ids, isNot(contains('am.niacinamide')));
      expect(r.notes.where((n) => n.contains('retinoids')), isNotEmpty);
    });

    test('is saved with the profile and sent to the AI by label', () {
      final p = profile().copyWith(reactsTo: {Reaction.fragrance});
      expect(UserProfile.fromJson(p.toJson()).reactsTo, {Reaction.fragrance});
      expect(
        p.toAiContext()['knownReactionsToAvoid'],
        ['Fragrance & perfume'],
      );
      expect(profile().toAiContext().containsKey('knownReactionsToAvoid'), isFalse);
    });
  });

  group('Shelf life', () {
    Product product({DateTime? opened, int? months}) => Product(
      id: 'p',
      name: 'Serum',
      brand: '',
      category: ProductCategory.serum,
      usage: ProductUsage.am,
      ingredientsRaw: '',
      addedAt: DateTime(2026, 1, 1),
      openedAt: opened,
      paoMonths: months,
    );

    test('use-by and freshness follow the opened date', () {
      final p = product(opened: DateTime(2026, 1, 15), months: 6);
      expect(ShelfLife.useBy(p), DateTime(2026, 7, 15));
      expect(ShelfLife.freshness(p, DateTime(2026, 3, 1)), Freshness.fresh);
      expect(ShelfLife.freshness(p, DateTime(2026, 7, 1)), Freshness.endingSoon);
      expect(ShelfLife.freshness(p, DateTime(2026, 8, 1)), Freshness.expired);
      expect(ShelfLife.freshness(product(), DateTime(2026, 8, 1)), isNull);
    });

    test('actives get shorter defaults', () {
      expect(
        ShelfLife.suggestedMonths(ProductCategory.serum, {Family.vitaminC}),
        3,
      );
      expect(
        ShelfLife.suggestedMonths(ProductCategory.treatment, {Family.retinoid}),
        6,
      );
      expect(ShelfLife.suggestedMonths(ProductCategory.moisturizer, {}), 12);
    });

    test('dates survive the database row', () {
      final p = product(opened: DateTime(2026, 2, 3), months: 12);
      final back = Product.fromRow(p.toRow());
      expect(back.openedAt, DateTime(2026, 2, 3));
      expect(back.paoMonths, 12);
    });
  });
}
