import 'package:clearskin_ai/data/models/product.dart';
import 'package:clearskin_ai/data/models/profile.dart';
import 'package:clearskin_ai/domain/routine/routine_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  Iterable<String> ids(List<RoutineStep> steps) => steps.map((s) => s.id);

  test('every routine ends the morning with sunscreen', () {
    for (final c in RoutineComplexity.values) {
      final r = RoutineEngine.build(profile: profile(complexity: c));
      expect(r.am.last.id, 'am.spf', reason: c.name);
    }
  });

  test('acne gets adapalene at night and never alongside an acid', () {
    final r = RoutineEngine.build(
      profile: profile(
        concerns: {Concern.acne, Concern.texture, Concern.blackheads},
        complexity: RoutineComplexity.enthusiast,
      ),
    );
    final retinoid = r.pm.firstWhere((s) => s.id == 'pm.retinoid');
    expect(retinoid.title, contains('Adapalene'));
    for (final acid in r.pm.where(
      (s) => s.id == 'pm.aha' || s.id == 'pm.bha',
    )) {
      expect(
        acid.days.intersection(retinoid.days),
        isEmpty,
        reason: '${acid.id} shares a night with the retinoid',
      );
    }
  });

  test('no two strong actives share a night across many profiles', () {
    final strong = {'pm.retinoid', 'pm.aha', 'pm.bha', 'pm.azelaic'};
    for (final concerns in [
      {Concern.acne, Concern.redness, Concern.texture},
      {Concern.darkSpots, Concern.texture, Concern.blackheads},
      {Concern.fineLines, Concern.texture, Concern.razorBumps},
      {Concern.blackheads, Concern.texture, Concern.redness},
    ]) {
      for (final sensitivity in Sensitivity.values) {
        final r = RoutineEngine.build(
          profile: profile(
            concerns: concerns,
            sensitivity: sensitivity,
            shaves: true,
            tone: SkinTone.v,
            complexity: RoutineComplexity.enthusiast,
          ),
        );
        for (var day = 1; day <= 7; day++) {
          final tonight = r.pm
              .where((s) => strong.contains(s.id))
              .where((s) => s.days.isEmpty || s.days.contains(day))
              .toList();
          expect(
            tonight.length,
            lessThanOrEqualTo(1),
            reason:
                '$concerns/$sensitivity day $day: '
                '${tonight.map((s) => s.id).toList()}',
          );
        }
      }
    }
  });

  test('pregnancy removes retinoids and uses azelaic acid', () {
    final r = RoutineEngine.build(
      profile: profile(
        concerns: {Concern.acne, Concern.darkSpots},
        pregnant: true,
      ),
    );
    expect(ids(r.pm), isNot(contains('pm.retinoid')));
    expect(ids(r.pm), contains('pm.azelaic'));
    expect(r.notes.any((n) => n.contains('avoids retinoids')), isTrue);
  });

  test('minimal routines stay short', () {
    final r = RoutineEngine.build(
      profile: profile(
        concerns: {Concern.acne, Concern.darkSpots, Concern.texture},
        complexity: RoutineComplexity.minimal,
      ),
    );
    expect(r.am.length, lessThanOrEqualTo(3));
    expect(r.pm.length, lessThanOrEqualTo(3));
  });

  test('deeper skin tones get no-white-cast sunscreen guidance', () {
    final r = RoutineEngine.build(profile: profile(tone: SkinTone.vi));
    final spf = r.am.firstWhere((s) => s.id == 'am.spf');
    expect(spf.howTo, contains('white cast'));
  });

  test('shelf products are matched to their steps', () {
    final r = RoutineEngine.build(
      profile: profile(concerns: {Concern.acne}),
      shelf: [
        Product(
          id: 'p1',
          name: 'Differin',
          brand: '',
          category: ProductCategory.treatment,
          usage: ProductUsage.pm,
          ingredientsRaw: 'Adapalene, Carbomer, Water, Propylene Glycol',
          addedAt: DateTime(2026),
        ),
      ],
    );
    expect(
      r.pm.firstWhere((s) => s.id == 'pm.retinoid').matchedProduct?.id,
      'p1',
    );
  });
}
