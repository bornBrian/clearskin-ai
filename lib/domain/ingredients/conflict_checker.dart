import '../../data/models/check_in.dart';
import '../../data/models/product.dart';
import '../../data/models/profile.dart';
import 'ingredient_kb.dart';
import 'product_analyzer.dart';

class RoutineConflict {
  const RoutineConflict({
    required this.severity,
    required this.title,
    required this.advice,
    required this.products,
    this.slot,
  });

  final FlagSeverity severity;
  final String title;
  final String advice;
  final List<String> products;
  final RoutineSlot? slot;
}

/// Checks the user's active shelf for combinations that commonly cause
/// irritation or cancel each other out. Deliberately does NOT repeat
/// debunked myths (e.g. niacinamide + vitamin C is fine).
abstract final class ConflictChecker {
  static List<RoutineConflict> check(
    List<Product> shelf,
    UserProfile? profile,
  ) {
    final active = shelf
        .where((p) => p.status == ProductStatus.active)
        .toList();
    final analysis = {
      for (final p in active)
        p.id: ProductAnalyzer.analyze(p.ingredientsRaw, profile),
    };
    Set<Family> fam(Product p) => analysis[p.id]!.families;
    bool has(Product p, Family f) => fam(p).contains(f);
    bool exfoliates(Product p) => fam(p).any(exfoliatingFamilies.contains);

    final out = <RoutineConflict>[];

    for (final slot in RoutineSlot.values) {
      final inSlot = active
          .where((p) => slot == RoutineSlot.am ? p.usedAm : p.usedPm)
          .toList();

      // Pairwise rules across *different* products. Formulas that already
      // combine actives were designed (and pH-balanced) to do so.
      for (var i = 0; i < inSlot.length; i++) {
        for (var j = i + 1; j < inSlot.length; j++) {
          final a = inSlot[i], b = inSlot[j];
          final pair = [a.displayName, b.displayName];

          bool either(bool Function(Product, Product) rule) =>
              rule(a, b) || rule(b, a);

          if (either((x, y) => has(x, Family.retinoid) && exfoliates(y))) {
            out.add(
              RoutineConflict(
                severity: FlagSeverity.medium,
                slot: slot,
                title: 'Retinoid + exfoliating acid in the same routine',
                advice: 'Together they often cause redness and peeling. Use them on alternate nights.',
                products: pair,
              ),
            );
          }
          if (either(
            (x, y) => has(x, Family.retinoid) && has(y, Family.benzoylPeroxide),
          )) {
            out.add(
              RoutineConflict(
                severity: FlagSeverity.medium,
                slot: slot,
                title: 'Benzoyl peroxide can deactivate retinoids',
                advice: 'Use benzoyl peroxide in the morning and your retinoid at night (adapalene is the exception and is stable with it).',
                products: pair,
              ),
            );
          }
          if (either(
            (x, y) => has(x, Family.vitaminC) && has(y, Family.benzoylPeroxide),
          )) {
            out.add(
              RoutineConflict(
                severity: FlagSeverity.low,
                slot: slot,
                title: 'Benzoyl peroxide can oxidise vitamin C',
                advice: 'Split them: vitamin C in the morning, benzoyl peroxide at night (or vice versa).',
                products: pair,
              ),
            );
          }
          if (either((x, y) => has(x, Family.vitaminC) && exfoliates(y))) {
            out.add(
              RoutineConflict(
                severity: FlagSeverity.low,
                slot: slot,
                title: 'Vitamin C + acids may sting',
                advice: 'Both are acidic. If you notice stinging, use vitamin C in the morning and acids at night.',
                products: pair,
              ),
            );
          }
          if (has(a, Family.retinoid) && has(b, Family.retinoid)) {
            out.add(
              RoutineConflict(
                severity: FlagSeverity.medium,
                slot: slot,
                title: 'Two retinoids at once',
                advice: 'Doubling up adds irritation, not results. Pick one.',
                products: pair,
              ),
            );
          }
        }
      }

      final exfoliants = inSlot.where(exfoliates).toList();
      if (exfoliants.length >= 2) {
        out.add(
          RoutineConflict(
            severity: FlagSeverity.medium,
            slot: slot,
            title: 'Over-exfoliation risk',
            advice:
                '${exfoliants.length} exfoliating products in one routine can damage your barrier. Keep one and use it 2–3 times a week.',
            products: exfoliants.map((p) => p.displayName).toList(),
          ),
        );
      }

      if (slot == RoutineSlot.am) {
        final amRetinoids = inSlot
            .where((p) => has(p, Family.retinoid))
            .toList();
        if (amRetinoids.isNotEmpty) {
          out.add(
            RoutineConflict(
              severity: FlagSeverity.low,
              slot: slot,
              title: 'Retinoids work best at night',
              advice: 'Sunlight breaks down many retinoids. Move it to your evening routine.',
              products: amRetinoids.map((p) => p.displayName).toList(),
            ),
          );
        }
      }
    }

    // Photosensitising actives without daily sunscreen.
    final sensitizers = active.where(
      (p) =>
          has(p, Family.retinoid) ||
          fam(p).contains(Family.aha) ||
          has(p, Family.hydroquinone),
    );
    final hasSpf = active.any(
      (p) =>
          p.usedAm &&
          (p.category == ProductCategory.sunscreen ||
              analysis[p.id]!.isSunscreen),
    );
    if (sensitizers.isNotEmpty && !hasSpf) {
      out.add(
        RoutineConflict(
          severity: FlagSeverity.high,
          title: 'Your actives need daily sunscreen',
          advice: 'Retinoids and acids make skin more sun-sensitive and undo their own results without SPF 30+. Add a morning sunscreen.',
          products: sensitizers.map((p) => p.displayName).toList(),
        ),
      );
    }

    if (profile?.pregnantOrNursing ?? false) {
      final risky = active.where(
        (p) => analysis[p.id]!.ingredients.any(
          (i) => i.match?.pregnancyCaution == PregnancyCaution.avoid,
        ),
      );
      if (risky.isNotEmpty) {
        out.add(
          RoutineConflict(
            severity: FlagSeverity.high,
            title: 'Pause these while pregnant or nursing',
            advice: 'They contain retinoids or hydroquinone. Azelaic acid and niacinamide are commonly suggested alternatives — confirm with your clinician.',
            products: risky.map((p) => p.displayName).toList(),
          ),
        );
      }
    }

    out.sort((a, b) => b.severity.index.compareTo(a.severity.index));
    return out;
  }
}
