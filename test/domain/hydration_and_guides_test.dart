import 'package:clearskin_ai/data/models/profile.dart';
import 'package:clearskin_ai/domain/content/guides.dart';
import 'package:clearskin_ai/domain/guidance/hydration.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  group('water target', () {
    test('without a weight: EFSA adult intake, 80% from drinks', () {
      expect(Hydration.target(profile: profile()).ml, 1600);
      expect(Hydration.target(profile: profile(gender: Gender.man)).ml, 2000);
    });

    test('scales with weight: 70 kg is about 1.85 L of drinks', () {
      final t = Hydration.target(
        profile: profile(),
        settings: const HydrationSettings(weightKg: 70),
      );
      expect(t.ml, 1850);
      expect(t.glasses, 8);
    });

    test('a high BMI uses an adjusted weight, not the full weight', () {
      const tall = HydrationSettings(weightKg: 130, heightCm: 170);
      final adjusted = Hydration.target(profile: profile(), settings: tall);
      final raw = Hydration.target(
        profile: profile(),
        settings: const HydrationSettings(weightKg: 130),
      );
      expect(adjusted.ml, lessThan(raw.ml));
    });

    test('exercise, heat, dry air and pregnancy each add water', () {
      const s = HydrationSettings(weightKg: 60);
      final base = Hydration.target(profile: profile(), settings: s).ml;
      final busy = Hydration.target(
        profile: profile(pregnant: true),
        settings: const HydrationSettings(weightKg: 60, activeMinutes: 60),
        temperatureC: 32,
        humidity: 20,
      );
      expect(busy.ml, base + 500 + 500 + 250 + 300);
      expect(busy.reasons, hasLength(5));
    });

    test('stays within safe bounds', () {
      final huge = Hydration.target(
        profile: profile(),
        settings: const HydrationSettings(weightKg: 200, activeMinutes: 300),
        temperatureC: 40,
      );
      expect(huge.ml, 4000);
    });

    test('settings survive a round trip and bad data', () {
      const s = HydrationSettings(
        weightKg: 72,
        heightCm: 178,
        activeMinutes: 30,
      );
      final back = HydrationSettings.decode(s.encode());
      expect(back.weightKg, 72);
      expect(back.heightCm, 178);
      expect(back.activeMinutes, 30);
      expect(HydrationSettings.decode('not json').hasBody, isFalse);
    });

    test('glasses due are spread over the waking day', () {
      expect(Hydration.dueBy(DateTime(2026, 1, 1, 7), 8), 0);
      expect(Hydration.dueBy(DateTime(2026, 1, 1, 15), 8), 4);
      expect(Hydration.dueBy(DateTime(2026, 1, 1, 23), 8), 8);
    });
  });

  group('guides', () {
    test('ids are unique and every guide has real content', () {
      final ids = GuideLibrary.all.map((g) => g.id).toSet();
      expect(ids, hasLength(GuideLibrary.all.length));
      for (final g in GuideLibrary.all) {
        expect(g.sections, isNotEmpty, reason: g.id);
        for (final s in g.sections) {
          expect(s.points, isNotEmpty, reason: '${g.id}: ${s.heading}');
        }
      }
    });

    test('every guide image is bundled', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      for (final g in GuideLibrary.all) {
        await rootBundle.load(g.image);
      }
    });

    test('safety guides are free for everyone', () {
      for (final id in ['budget', 'kitchen', 'lightening', 'water']) {
        expect(GuideLibrary.byId(id)!.premium, isFalse, reason: id);
      }
    });

    test('the kitchen guide warns against lemon and toothpaste', () {
      final avoid = GuideLibrary.byId('kitchen')!.sections
          .where((s) => s.avoid)
          .expand((s) => s.points)
          .map((p) => p.title.toLowerCase())
          .join(' ');
      expect(avoid, contains('lemon'));
      expect(avoid, contains('toothpaste'));
    });

    test('deeper skin tones see the lightening-cream guide first', () {
      final list = GuideLibrary.forProfile(profile(tone: SkinTone.v));
      expect(list.first.id, 'lightening');
    });

    test('a different guide each day, cycling through all of them', () {
      final p = profile();
      final seen = {
        for (var d = 0; d < GuideLibrary.all.length; d++)
          GuideLibrary.ofTheDay(p, DateTime(2026, 11, 1 + d)).id,
      };
      expect(seen, hasLength(GuideLibrary.all.length));
    });
  });
}
