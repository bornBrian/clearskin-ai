import 'package:clearskin_ai/data/models/check_in.dart';
import 'package:clearskin_ai/data/models/product.dart';
import 'package:clearskin_ai/data/models/profile.dart';
import 'package:clearskin_ai/domain/ingredients/conflict_checker.dart';
import 'package:clearskin_ai/domain/ingredients/ingredient_kb.dart';
import 'package:clearskin_ai/domain/ingredients/ingredient_parser.dart';
import 'package:clearskin_ai/domain/ingredients/product_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

const cerave =
    'Ingredients: Aqua/Water/Eau, Glycerin, Cetearyl Alcohol, Caprylic/Capric '
    'Triglyceride, Cetyl Alcohol, Ceramide NP, Ceramide AP, Ceramide EOP, '
    'Carbomer, Dimethicone, Behentrimonium Methosulfate, Sodium Lauroyl '
    'Lactylate, Sodium Hyaluronate, Cholesterol, Phenoxyethanol, Disodium EDTA, '
    'Dipotassium Phosphate, Tocopherol, Phytosphingosine, Xanthan Gum, '
    'Ethylhexylglycerin.';

Product product(
  String id,
  String ingredients, {
  ProductUsage usage = ProductUsage.pm,
  ProductCategory category = ProductCategory.serum,
}) => Product(
  id: id,
  name: id,
  brand: '',
  category: category,
  usage: usage,
  ingredientsRaw: ingredients,
  addedAt: DateTime(2026),
);

void main() {
  group('IngredientParser', () {
    test('strips the "Ingredients:" prefix and keeps order', () {
      final parsed = IngredientParser.parse(cerave);
      expect(parsed.first.match?.id, 'water');
      expect(parsed[1].match?.id, 'glycerin');
      expect(parsed[1].position, 1);
    });

    test('does not split commas inside parentheses', () {
      final parsed = IngredientParser.parse('Water (Aqua, Eau), Niacinamide');
      expect(parsed, hasLength(2));
      expect(parsed[1].match?.id, 'niacinamide');
    });

    test('handles OCR newlines, bullets and percentages', () {
      final parsed = IngredientParser.parse(
        'Niacinamide 10%\n• Zinc PCA 1% • Glycerin',
      );
      expect(parsed.map((p) => p.match?.id), [
        'niacinamide',
        'zinc_pca',
        'glycerin',
      ]);
    });

    test('matches INCI names with parenthetical common names', () {
      expect(
        IngredientKb.match('butyrospermum parkii (shea) butter')?.id,
        'shea',
      );
    });
  });

  group('IngredientKb word-boundary matching', () {
    test('fatty alcohols are not drying alcohol', () {
      expect(IngredientKb.match('cetearyl alcohol')?.id, 'fatty_alcohols');
      expect(IngredientKb.match('myristyl alcohol'), isNull);
      expect(IngredientKb.match('alcohol denat.')?.id, 'denat_alcohol');
    });

    test('flower water is not plain water', () {
      expect(IngredientKb.match('rosa damascena flower water'), isNull);
    });
  });

  group('ProductAnalyzer', () {
    test('a ceramide moisturiser is a great match for dry skin', () {
      final a = ProductAnalyzer.analyze(
        cerave,
        profile(skinType: SkinType.dry, concerns: {Concern.dryness}),
      );
      expect(a.verdict, anyOf(Verdict.great, Verdict.good));
      expect(a.highlights.map((h) => h.ingredient.id), contains('ceramides'));
      expect(
        a.flags.where((f) => f.severity.index >= FlagSeverity.medium.index),
        isEmpty,
      );
    });

    test('fragrance is a medium flag only for sensitive skin', () {
      const ing =
          'Water, Glycerin, Dimethicone, Parfum, Linalool, Phenoxyethanol';
      final normal = ProductAnalyzer.analyze(ing, profile());
      final sensitive = ProductAnalyzer.analyze(
        ing,
        profile(sensitivity: Sensitivity.high),
      );
      FlagSeverity sev(ProductAnalysis a) =>
          a.flags.firstWhere((f) => f.kind == FlagKind.fragrance).severity;
      expect(sev(normal), FlagSeverity.info);
      expect(sev(sensitive), FlagSeverity.medium);
    });

    test('pore-clogging flags only for acne-prone users', () {
      const ing = 'Cocos Nucifera Oil, Isopropyl Myristate, Glycerin, Water';
      final clear = ProductAnalyzer.analyze(ing, profile());
      final acne = ProductAnalyzer.analyze(
        ing,
        profile(concerns: {Concern.acne}),
      );
      expect(clear.flags.any((f) => f.kind == FlagKind.comedogenic), isFalse);
      expect(acne.flags.any((f) => f.kind == FlagKind.comedogenic), isTrue);
    });

    test('retinol is "avoid" for pregnant users', () {
      const ing = 'Water, Glycerin, Squalane, Retinol, Tocopherol';
      final a = ProductAnalyzer.analyze(ing, profile(pregnant: true));
      expect(a.verdict, Verdict.avoid);
      expect(a.flags.first.kind, FlagKind.pregnancy);
      expect(a.flags.first.severity, FlagSeverity.high);
    });

    test('too few recognised ingredients gives unknown verdict', () {
      final a = ProductAnalyzer.analyze('Foo extract, bar complex', profile());
      expect(a.verdict, Verdict.unknown);
    });
  });

  group('ConflictChecker', () {
    test('retinoid + AHA in the same night is flagged', () {
      final c = ConflictChecker.check([
        product('ret', 'Water, Glycerin, Retinol'),
        product('aha', 'Water, Glycolic Acid, Sodium Hydroxide'),
        product(
          'spf',
          'Water, Zinc Oxide, Glycerin',
          usage: ProductUsage.am,
          category: ProductCategory.sunscreen,
        ),
      ], profile());
      expect(c.any((x) => x.title.contains('Retinoid + exfoliating')), isTrue);
      expect(c.any((x) => x.title.contains('sunscreen')), isFalse);
    });

    test('actives without sunscreen raise a high-severity warning', () {
      final c = ConflictChecker.check([
        product('ret', 'Water, Glycerin, Retinol'),
      ], profile());
      expect(c.first.severity, FlagSeverity.high);
      expect(c.first.title, contains('sunscreen'));
    });

    test('niacinamide + vitamin C is NOT a conflict (myth)', () {
      final c = ConflictChecker.check([
        product(
          'c',
          'Water, Ascorbic Acid, Tocopherol',
          usage: ProductUsage.am,
        ),
        product('n', 'Water, Niacinamide, Zinc PCA', usage: ProductUsage.am),
      ], profile());
      expect(c, isEmpty);
    });

    test(
      'a single product combining actives is not a conflict with itself',
      () {
        final c = ConflictChecker.check([
          product('combo', 'Water, Glycolic Acid, Salicylic Acid, Glycerin'),
          product(
            'spf',
            'Water, Zinc Oxide',
            usage: ProductUsage.am,
            category: ProductCategory.sunscreen,
          ),
        ], profile());
        expect(c.where((x) => x.slot == RoutineSlot.pm), isEmpty);
      },
    );

    test('pregnancy flags retinoid products', () {
      final c = ConflictChecker.check([
        product('ret', 'Water, Adapalene, Glycerin'),
        product(
          'spf',
          'Water, Zinc Oxide',
          usage: ProductUsage.am,
          category: ProductCategory.sunscreen,
        ),
      ], profile(pregnant: true));
      expect(c.first.title, contains('pregnant'));
    });
  });
}
