enum ProductCategory {
  cleanser('Cleanser'),
  toner('Toner / essence'),
  serum('Serum'),
  treatment('Treatment'),
  exfoliant('Exfoliant'),
  moisturizer('Moisturizer'),
  sunscreen('Sunscreen'),
  eyeCream('Eye cream'),
  mask('Mask'),
  shaving('Shaving / aftershave'),
  makeup('Makeup'),
  other('Other');

  const ProductCategory(this.label);
  final String label;
}

enum ProductUsage {
  am('Morning'),
  pm('Night'),
  both('Morning & night'),
  occasional('A few times a week');

  const ProductUsage(this.label);
  final String label;
}

enum ProductStatus { active, paused, finished }

/// A product on the user's shelf.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.category,
    required this.usage,
    required this.ingredientsRaw,
    required this.addedAt,
    this.barcode,
    this.imageUrl,
    this.status = ProductStatus.active,
    this.openedAt,
    this.paoMonths,
  });

  final String id;
  final String name;
  final String brand;
  final ProductCategory category;
  final ProductUsage usage;
  final String ingredientsRaw;
  final DateTime addedAt;
  final String? barcode;
  final String? imageUrl;
  final ProductStatus status;

  /// When it was opened, and how many months it stays good after (the
  /// open-jar symbol on the pack). Both null until the person sets them.
  final DateTime? openedAt;
  final int? paoMonths;

  bool get usedAm => usage == ProductUsage.am || usage == ProductUsage.both;
  bool get usedPm =>
      usage == ProductUsage.pm ||
      usage == ProductUsage.both ||
      usage == ProductUsage.occasional;

  String get displayName => brand.isEmpty ? name : '$brand $name';

  Product copyWith({
    String? name,
    String? brand,
    ProductCategory? category,
    ProductUsage? usage,
    String? ingredientsRaw,
    ProductStatus? status,
    DateTime? openedAt,
    int? paoMonths,
  }) => Product(
    id: id,
    name: name ?? this.name,
    brand: brand ?? this.brand,
    category: category ?? this.category,
    usage: usage ?? this.usage,
    ingredientsRaw: ingredientsRaw ?? this.ingredientsRaw,
    addedAt: addedAt,
    barcode: barcode,
    imageUrl: imageUrl,
    status: status ?? this.status,
    openedAt: openedAt ?? this.openedAt,
    paoMonths: paoMonths ?? this.paoMonths,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'brand': brand,
    'category': category.name,
    'usage': usage.name,
    'ingredients': ingredientsRaw,
    'added_at': addedAt.millisecondsSinceEpoch,
    'barcode': barcode,
    'image_url': imageUrl,
    'status': status.name,
    'opened_at': openedAt?.millisecondsSinceEpoch,
    'pao_months': paoMonths,
  };

  factory Product.fromRow(Map<String, Object?> r) => Product(
    id: r['id'] as String,
    name: r['name'] as String,
    brand: r['brand'] as String? ?? '',
    category:
        ProductCategory.values
            .where((c) => c.name == r['category'])
            .firstOrNull ??
        ProductCategory.other,
    usage:
        ProductUsage.values.where((u) => u.name == r['usage']).firstOrNull ??
        ProductUsage.both,
    ingredientsRaw: r['ingredients'] as String? ?? '',
    addedAt: DateTime.fromMillisecondsSinceEpoch(r['added_at'] as int),
    barcode: r['barcode'] as String?,
    imageUrl: r['image_url'] as String?,
    status:
        ProductStatus.values.where((s) => s.name == r['status']).firstOrNull ??
        ProductStatus.active,
    openedAt: switch (r['opened_at']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null,
    },
    paoMonths: r['pao_months'] as int?,
  );
}

/// Result of a product lookup (barcode database or OCR) before the user
/// decides to add it to their shelf.
class ProductDraft {
  const ProductDraft({
    this.name = '',
    this.brand = '',
    this.ingredientsRaw = '',
    this.barcode,
    this.imageUrl,
    this.category = ProductCategory.other,
  });

  final String name;
  final String brand;
  final String ingredientsRaw;
  final String? barcode;
  final String? imageUrl;
  final ProductCategory category;
}
