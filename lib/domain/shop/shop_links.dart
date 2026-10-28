import '../../data/models/product.dart';

/// A store to send people to for a product type, with our affiliate tag
/// already in the URL template.
class ShopStore {
  const ShopStore({required this.name, required this.urlTemplate});

  final String name;

  /// HTTPS search URL with a `{q}` placeholder, e.g.
  /// `https://www.amazon.co.uk/s?k={q}&tag=clearskin-21`.
  final String urlTemplate;

  Uri? search(String query) {
    if (!urlTemplate.contains('{q}')) return null;
    final uri = Uri.tryParse(
      urlTemplate.replaceAll('{q}', Uri.encodeQueryComponent(query)),
    );
    // Config comes from our server, but never open anything but https.
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }
}

/// Region → store, served by the account-status function so tags and stores
/// change without an app release. Empty config = no shop links at all.
class ShopConfig {
  const ShopConfig(this._byRegion);

  static const empty = ShopConfig({});

  final Map<String, ShopStore> _byRegion;

  bool get isEmpty => _byRegion.isEmpty;

  /// The store for an ISO country code, falling back to "default".
  ShopStore? storeFor(String? countryCode) =>
      _byRegion[countryCode?.toUpperCase()] ?? _byRegion['default'];

  factory ShopConfig.fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final stores = <String, ShopStore>{};
    for (final MapEntry(:key, :value) in raw.entries) {
      if (key is! String || value is! Map) continue;
      final name = value['store'];
      final url = value['url'];
      if (name is String && url is String && url.startsWith('https://')) {
        stores[key == 'default' ? key : key.toUpperCase()] = ShopStore(
          name: name,
          urlTemplate: url,
        );
      }
    }
    return ShopConfig(stores);
  }

  Map<String, Object?> toJson() => {
    for (final MapEntry(:key, :value) in _byRegion.entries)
      key: {'store': value.name, 'url': value.urlTemplate},
  };
}

/// What to search for: the category, sharpened by the key ingredient when
/// there is one ("niacinamide serum" finds better products than "serum").
abstract final class ShopQuery {
  static String forStep(ProductCategory category, List<String> ingredients) {
    final noun = categoryNoun(category);
    final key = ingredients.firstOrNull?.toLowerCase();
    if (key == null || noun.contains(key)) return noun;
    return '$key $noun';
  }

  /// Product types named by the scan ("moisturizer", "spot_treatment").
  static String forType(String type) => switch (type) {
    'eye_cream' => 'eye cream',
    'spot_treatment' => 'spot treatment',
    'moisturizer' => 'moisturiser',
    'sunscreen' => 'sunscreen spf 50',
    _ => type.replaceAll('_', ' '),
  };

  static String categoryNoun(ProductCategory c) => switch (c) {
    ProductCategory.cleanser => 'gentle cleanser',
    ProductCategory.toner => 'hydrating toner',
    ProductCategory.serum => 'serum',
    ProductCategory.treatment => 'treatment',
    ProductCategory.exfoliant => 'exfoliant',
    ProductCategory.moisturizer => 'moisturiser',
    ProductCategory.sunscreen => 'sunscreen spf 50',
    ProductCategory.eyeCream => 'eye cream',
    ProductCategory.mask => 'face mask',
    ProductCategory.shaving => 'aftershave balm',
    ProductCategory.makeup => 'non comedogenic makeup',
    ProductCategory.other => 'skincare',
  };
}
