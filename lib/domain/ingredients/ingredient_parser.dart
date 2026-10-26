import 'ingredient_kb.dart';

class ParsedIngredient {
  const ParsedIngredient({
    required this.raw,
    required this.normalized,
    required this.position,
    this.match,
  });

  /// Text as it appeared on the label (trimmed).
  final String raw;
  final String normalized;

  /// 0-based position in the list. INCI lists are ordered by concentration
  /// down to 1%, so early positions mean higher amounts.
  final int position;
  final Ingredient? match;
}

/// Turns a raw INCI label (typed, from a barcode database or from OCR) into
/// an ordered list of recognised ingredients.
abstract final class IngredientParser {
  static List<ParsedIngredient> parse(String raw) {
    var text = raw.toLowerCase();

    // OCR and databases often prefix the list.
    text = text.replaceFirst(
      RegExp(
        r'^.*?(ingredients|ingrédients|inci|composition)\s*[:：]\s*',
        dotAll: true,
      ),
      '',
    );

    // "May contain (+/-): CI 77491, ..." — colorants, keep but they rarely matter.
    text = text.replaceAll(RegExp(r'\[\s*\+/-\s*\]|\(\s*\+/-\s*\)|\+/-'), ',');
    text = text.replaceAll(
      RegExp(r'may contain\s*[:：]?', caseSensitive: false),
      ',',
    );

    // Normalise separators and OCR artefacts.
    text = text
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .replaceAll('•', ',')
        .replaceAll('·', ',')
        .replaceAll(';', ',')
        .replaceAll(RegExp(r'\s+'), ' ');

    final tokens = _splitTopLevel(text);
    final out = <ParsedIngredient>[];
    for (final token in tokens) {
      final normalized = _normalize(token);
      if (normalized.isEmpty || normalized.length > 120) continue;
      out.add(
        ParsedIngredient(
          raw: token.trim(),
          normalized: normalized,
          position: out.length,
          match: IngredientKb.match(normalized),
        ),
      );
    }
    return out;
  }

  /// Splits on commas that are not inside parentheses, so
  /// "water (aqua, eau), glycerin" yields two tokens.
  static List<String> _splitTopLevel(String text) {
    final parts = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    for (final ch in text.split('')) {
      if (ch == '(' || ch == '[') depth++;
      if (ch == ')' || ch == ']') depth = depth > 0 ? depth - 1 : 0;
      if (ch == ',' && depth == 0) {
        parts.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) parts.add(buf.toString());
    return parts;
  }

  static String _normalize(String token) {
    return token
        .replaceAll(RegExp(r'\d+(\.\d+)?\s*%'), '') // "niacinamide 10%"
        .replaceAll(RegExp(r'[*†‡¹²³°]'), '') // organic / footnote marks
        .replaceAll(RegExp(r'\.$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
