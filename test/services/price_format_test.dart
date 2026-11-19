import 'package:clearskin_ai/services/purchases_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tidyPrice', () {
    test('drops zero cents', () {
      expect(PurchasesService.tidyPrice('TSh 9,900.00'), 'TSh 9,900');
      expect(PurchasesService.tidyPrice('4,00 €'), '4 €');
    });

    test('keeps real cents', () {
      expect(PurchasesService.tidyPrice(r'$4.99'), r'$4.99');
      expect(PurchasesService.tidyPrice(r'$1,000.50'), r'$1,000.50');
    });
  });

  group('weeklyPrice', () {
    test('large amounts lose the cents, in the store style', () {
      expect(PurchasesService.weeklyPrice('TSh 9,900.00', 2286.4), 'TSh 2,286');
    });

    test('small amounts keep two decimals', () {
      expect(PurchasesService.weeklyPrice(r'$29.99', 0.5767), r'$0.58');
    });

    test('suffix currencies keep the suffix', () {
      expect(PurchasesService.weeklyPrice('29,99 €', 0.58), '0.58 €');
    });
  });
}
