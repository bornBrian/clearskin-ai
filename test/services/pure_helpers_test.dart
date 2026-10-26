import 'package:clearskin_ai/data/models/product.dart';
import 'package:clearskin_ai/domain/ingredients/ingredient_parser.dart';
import 'package:clearskin_ai/services/device_services.dart';
import 'package:clearskin_ai/services/product_lookup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OcrService.extractIngredients', () {
    test('keeps only the INCI block from a full label', () {
      const label = '''
HYDRATING FACIAL CLEANSER
For normal to dry skin
INGREDIENTS: AQUA / WATER, GLYCERIN, CETEARYL ALCOHOL,
CERAMIDE NP, SODIUM HYALURONATE, PHENOXYETHANOL
Directions: Wet skin with lukewarm water.
Made in France''';
      final out = OcrService.extractIngredients(label);
      expect(out, startsWith('INGREDIENTS'));
      expect(out, isNot(contains('Directions')));
      final parsed = IngredientParser.parse(out);
      expect(
        parsed.map((p) => p.match?.id),
        containsAll(['glycerin', 'ceramides', 'ha', 'fatty_alcohols']),
      );
    });
  });

  group('ProductLookupService.guessCategory', () {
    test('maps common names and tags', () {
      expect(
        ProductLookupService.guessCategory('Ultra Light Sunscreen SPF 50'),
        ProductCategory.sunscreen,
      );
      expect(
        ProductLookupService.guessCategory('Foaming Facial Cleanser'),
        ProductCategory.cleanser,
      );
      expect(
        ProductLookupService.guessCategory('Niacinamide 10% Serum'),
        ProductCategory.serum,
      );
      expect(
        ProductLookupService.guessCategory('Daily Moisturizing Lotion'),
        ProductCategory.moisturizer,
      );
      expect(
        ProductLookupService.guessCategory('Mystery'),
        ProductCategory.other,
      );
    });
  });
}
