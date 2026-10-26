import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/models/product.dart';

/// Looks products up by barcode in Open Beauty Facts, a free, open
/// (ODbL-licensed) database of cosmetics. Attribution is shown in the UI.
class ProductLookupService {
  ProductLookupService({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static const _userAgent =
      'ClearSkinAI/1.0 (Android/iOS; bonbrian2@gmail.com)';

  Future<ProductDraft?> byBarcode(String barcode) async {
    final code = barcode.replaceAll(RegExp(r'\D'), '');
    if (code.length < 8) return null;
    final uri = Uri.https(
      'world.openbeautyfacts.org',
      '/api/v2/product/$code.json',
      {
        'fields': 'product_name,product_name_en,brands,ingredients_text,ingredients_text_en,image_front_small_url,categories_tags',
      },
    );
    final res = await _http
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['status'] != 1) return null;
    final p = body['product'] as Map<String, dynamic>? ?? const {};

    String pick(List<String> keys) {
      for (final k in keys) {
        final v = p[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }

    final categories = ((p['categories_tags'] as List?) ?? const [])
        .whereType<String>()
        .join(' ');

    return ProductDraft(
      name: pick(['product_name_en', 'product_name']),
      brand: pick(['brands']).split(',').first.trim(),
      ingredientsRaw: pick(['ingredients_text_en', 'ingredients_text']),
      barcode: code,
      imageUrl: pick(['image_front_small_url']).isEmpty
          ? null
          : pick(['image_front_small_url']),
      category: guessCategory('${pick(['product_name'])} $categories'),
    );
  }

  /// Best-effort category from a product name or category tags.
  static ProductCategory guessCategory(String text) {
    final t = text.toLowerCase();
    bool any(List<String> words) => words.any(t.contains);
    if (any(['sunscreen', 'spf', 'sun-protection', 'sun cream', 'solaire'])) {
      return ProductCategory.sunscreen;
    }
    if (any([
      'cleanser',
      'face-wash',
      'face wash',
      'cleansing',
      'micellar',
      'gel nettoyant',
    ])) {
      return ProductCategory.cleanser;
    }
    if (any(['eye cream', 'eye-cream', 'eye gel', 'contour des yeux'])) {
      return ProductCategory.eyeCream;
    }
    if (any(['serum', 'sérum', 'ampoule'])) return ProductCategory.serum;
    if (any(['exfoliant', 'peel', 'aha', 'bha', 'scrub'])) {
      return ProductCategory.exfoliant;
    }
    if (any(['toner', 'essence', 'lotion tonique'])) {
      return ProductCategory.toner;
    }
    if (any(['moisturi', 'cream', 'crème', 'lotion', 'hydrat'])) {
      return ProductCategory.moisturizer;
    }
    if (any(['mask', 'masque'])) return ProductCategory.mask;
    if (any(['shav', 'after-shave', 'aftershave', 'beard'])) {
      return ProductCategory.shaving;
    }
    if (any(['foundation', 'concealer', 'makeup', 'mascara', 'lipstick'])) {
      return ProductCategory.makeup;
    }
    return ProductCategory.other;
  }
}
