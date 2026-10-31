// Exports the in-app guides as JSON for the ClearSkin website, so each guide
// is also a web article and the site and app never disagree. Run with
// OUT=<file>:
//   OUT=../clearskin-site/web/src/content/guides.json flutter test tool/export_guides_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:clearskin_ai/domain/content/guides.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('export guides', () {
    final guides = [
      for (final g in GuideLibrary.all)
        {
          'id': g.id,
          'title': g.title,
          'teaser': g.teaser,
          'image': g.image.split('/').last,
          'minutes': g.minutes,
          'premium': g.premium,
          'sections': [
            for (final s in g.sections)
              {
                'heading': s.heading,
                'avoid': s.avoid,
                'points': [
                  for (final p in s.points)
                    {
                      'title': p.title,
                      'detail': p.detail,
                      if (p.evidence != null) 'evidence': p.evidence!.label,
                    },
                ],
              },
          ],
        },
    ];
    File(Platform.environment['OUT']!).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(guides),
    );
  });
}
