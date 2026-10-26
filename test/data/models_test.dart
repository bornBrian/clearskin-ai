import 'package:clearskin_ai/data/models/check_in.dart';
import 'package:clearskin_ai/data/models/product.dart';
import 'package:clearskin_ai/data/models/profile.dart';
import 'package:clearskin_ai/data/models/scan.dart';
import 'package:clearskin_ai/domain/scan/skin_maps.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UserProfile survives encode/decode, and AI context excludes PII', () {
    final p = UserProfile(
      name: 'Amara Okafor',
      gender: Gender.woman,
      ageRange: AgeRange.a25,
      skinType: SkinType.combination,
      sensitivity: Sensitivity.medium,
      concerns: {Concern.acne, Concern.darkSpots},
      goals: {Goal.evenTone},
      complexity: RoutineComplexity.balanced,
      budget: Budget.mid,
      skinTone: SkinTone.v,
      pregnantOrNursing: true,
      location: const Location(
        name: 'Lagos, Nigeria',
        latitude: 6.45,
        longitude: 3.39,
      ),
      amReminder: const ReminderTime(6, 45),
      createdAt: DateTime(2026, 10, 1),
    );
    final back = UserProfile.decode(p.encode());
    expect(back.firstName, 'Amara');
    expect(back.concerns, p.concerns);
    expect(back.skinTone, SkinTone.v);
    expect(back.location?.name, 'Lagos, Nigeria');
    expect(back.amReminder.format(), '6:45 AM');

    final ctx = p.toAiContext();
    expect(ctx.containsKey('name'), isFalse);
    expect(ctx.containsKey('location'), isFalse);
    expect(ctx['fitzpatrick'], 'V');
  });

  test('unknown enum values from a future version fall back safely', () {
    final p = UserProfile.fromJson({
      'gender': 'somethingNew',
      'skinType': 'oily',
      'concerns': ['acne', 'notAConcern'],
    });
    expect(p.gender, Gender.preferNotToSay);
    expect(p.skinType, SkinType.oily);
    expect(p.concerns, {Concern.acne});
  });

  test('SkinScan row round-trip', () {
    final scan = SkinScan(
      id: 's1',
      createdAt: DateTime(2026, 10, 20, 9),
      photoPath: '/x/s1.jpg',
      analysis: const SkinAnalysis(
        usable: true,
        qualityIssues: [],
        overallScore: 71,
        metrics: [
          MetricScore(metric: SkinMetric.redness, score: 64, note: 'n'),
        ],
        skinTypeEstimate: 'oily',
        summary: 'ok',
        strengths: ['a'],
        priorities: ['b'],
        findings: [Finding(title: 't', detail: 'd', area: 'chin', severity: 2)],
        recommendedIngredients: [IngredientTip(name: 'Niacinamide', why: 'w')],
        ingredientsToAvoid: [],
        redFlags: [],
        model: 'm',
      ),
    );
    final back = SkinScan.fromRow(scan.toRow());
    expect(back.analysis.scoreFor(SkinMetric.redness), 64);
    expect(back.analysis.findings.single.area, 'chin');
    expect(back.createdAt, scan.createdAt);
    expect(back.radiance, isNull);

    const glow = Radiance(score: 72, evenness: 68, clarity: 89, sheen: 57);
    final measured = SkinScan.fromRow(scan.withRadiance(glow).toRow());
    expect(measured.radiance?.toJson(), glow.toJson());
    expect(measured.analysis.overallScore, 71);
  });

  test('CheckIn and Product rows round-trip', () {
    const c = CheckIn(
      day: '2026-10-20',
      skinFeel: 4,
      breakouts: 1,
      sleepHours: 6.5,
      stress: 3,
      waterGlasses: 7,
      tags: {LifeTag.dairy, LifeTag.workout},
      note: '',
    );
    expect(CheckIn.fromRow(c.toRow()).tags, c.tags);

    final p = Product(
      id: 'p',
      name: 'Gel',
      brand: 'B',
      category: ProductCategory.cleanser,
      usage: ProductUsage.am,
      ingredientsRaw: 'Water',
      addedAt: DateTime(2026),
    );
    final back = Product.fromRow(p.toRow());
    expect(back.usedAm, isTrue);
    expect(back.usedPm, isFalse);
    expect(back.displayName, 'B Gel');
  });
}
