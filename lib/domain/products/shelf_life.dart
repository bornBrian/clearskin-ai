import '../../data/models/product.dart';
import '../ingredients/ingredient_kb.dart';

enum Freshness { fresh, endingSoon, expired }

/// How long a product stays good once opened (the open-jar "12M" symbol,
/// period-after-opening). Actives like vitamin C and retinoids lose
/// strength first, which quietly makes a routine stop working.
abstract final class ShelfLife {
  static const choices = [3, 6, 9, 12, 18, 24];

  /// Warn this long before the date.
  static const warnBefore = Duration(days: 30);

  /// A sensible default when the person doesn't know the label's number.
  static int suggestedMonths(ProductCategory category, Set<Family> families) {
    if (families.contains(Family.vitaminC)) return 3;
    if (families.contains(Family.vitaminCDerivative) ||
        families.contains(Family.retinoid) ||
        families.contains(Family.benzoylPeroxide)) {
      return 6;
    }
    return switch (category) {
      ProductCategory.eyeCream || ProductCategory.makeup => 6,
      ProductCategory.sunscreen ||
      ProductCategory.serum ||
      ProductCategory.treatment => 12,
      _ => 12,
    };
  }

  static DateTime? useBy(Product p) {
    final opened = p.openedAt, months = p.paoMonths;
    if (opened == null || months == null) return null;
    return DateTime(opened.year, opened.month + months, opened.day);
  }

  static Freshness? freshness(Product p, DateTime now) {
    final end = useBy(p);
    if (end == null) return null;
    if (!end.isAfter(now)) return Freshness.expired;
    if (end.difference(now) <= warnBefore) return Freshness.endingSoon;
    return Freshness.fresh;
  }
}
