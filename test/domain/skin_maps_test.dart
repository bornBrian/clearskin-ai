import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clearskin_ai/domain/scan/face_zones.dart';
import 'package:clearskin_ai/domain/scan/skin_maps.dart';
import 'package:flutter_test/flutter_test.dart';

const _w = 300, _h = 400;

/// A front-facing face: an oval outline with eyes, brows, lips and nose
/// where the capture template expects them.
FaceGeometry _face() {
  List<Offset> ellipse(double cx, double cy, double rx, double ry, int n) => [
    for (var i = 0; i < n; i++)
      Offset(
        cx + rx * math.cos(i / n * math.pi * 2),
        cy + ry * math.sin(i / n * math.pi * 2),
      ),
  ];
  return FaceGeometry(
    aspect: _w / _h,
    contours: {
      'face': ellipse(0.5, 0.5, 0.3, 0.3, 36),
      'leftEye': ellipse(0.61, 0.42, 0.05, 0.015, 16),
      'rightEye': ellipse(0.39, 0.42, 0.05, 0.015, 16),
      'leftEyebrowTop': [for (var i = 0; i < 5; i++) Offset(0.56 + i * 0.025, 0.37)],
      'leftEyebrowBottom': [for (var i = 0; i < 5; i++) Offset(0.56 + i * 0.025, 0.38)],
      'rightEyebrowTop': [for (var i = 0; i < 5; i++) Offset(0.34 + i * 0.025, 0.37)],
      'rightEyebrowBottom': [for (var i = 0; i < 5; i++) Offset(0.34 + i * 0.025, 0.38)],
      'noseBottom': const [Offset(0.47, 0.53), Offset(0.5, 0.54), Offset(0.53, 0.53)],
      'upperLipTop': [for (var i = 0; i < 11; i++) Offset(0.44 + i * 0.012, 0.6)],
      'lowerLipBottom': [for (var i = 0; i < 11; i++) Offset(0.44 + i * 0.012, 0.63)],
    },
  );
}

/// Even skin, optionally with a disc of another colour at ([cx], [cy]).
Uint8List _photo({
  (double, double)? at,
  (int, int, int) spot = (0, 0, 0),
  double radius = 0.035,
}) {
  final px = Uint8List(_w * _h * 4);
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      final i = (y * _w + x) * 4;
      var (r, g, b) = (196, 150, 122);
      if (at != null) {
        final dx = x / _w - at.$1, dy = (y / _h - at.$2) * _h / _w;
        if (math.sqrt(dx * dx + dy * dy) < radius) (r, g, b) = spot;
      }
      px
        ..[i] = r
        ..[i + 1] = g
        ..[i + 2] = b
        ..[i + 3] = 255;
    }
  }
  return px;
}

void main() {
  test('Lab conversion matches reference values', () {
    final (l, a, b) = SkinMaps.labOf(255, 255, 255);
    expect(l, closeTo(100, 0.1));
    expect(a.abs(), lessThan(0.1));
    expect(b.abs(), lessThan(0.1));
    // sRGB pure red is L 53.2, a 80.1, b 67.2.
    final (rl, ra, rb) = SkinMaps.labOf(255, 0, 0);
    expect(rl, closeTo(53.2, 0.3));
    expect(ra, closeTo(80.1, 0.5));
    expect(rb, closeTo(67.2, 0.5));
  });

  test('even skin reads as clear on every lens', () {
    final maps = SkinMaps.analyze(_photo(), _w, _h, _face())!;
    for (final lens in SkinLens.values.where((l) => l != SkinLens.radiance)) {
      expect(maps.readings[lens]!.coverage, lessThan(0.005), reason: lens.name);
    }
    // Radiance is the one lens that lights up good skin.
    expect(maps.readings[SkinLens.radiance]!.coverage, greaterThan(0.5));
  });

  test('eyes, brows and lips are left out of the skin mask', () {
    final maps = SkinMaps.analyze(_photo(), _w, _h, _face())!;
    int at(double x, double y) => maps.mask[(y * _h).round() * _w + (x * _w).round()];
    expect(at(0.61, 0.42), 0); // eye
    expect(at(0.6, 0.375), 0); // brow
    expect(at(0.5, 0.615), 0); // lips
    expect(at(0.5, 0.3), 1); // forehead
    expect(at(0.36, 0.5), 1); // cheek
    expect(at(0.05, 0.05), 0); // background
  });

  test('a red patch on one cheek shows on the redness lens, in the cheeks', () {
    final maps = SkinMaps.analyze(
      _photo(at: (0.33, 0.55), spot: (214, 128, 112)),
      _w,
      _h,
      _face(),
    )!;
    final red = maps.readings[SkinLens.redness]!;
    expect(red.coverage, greaterThan(0.01));
    expect(red.zones.first.area, 'cheeks');
    expect(maps.readings[SkinLens.shine]!.coverage, lessThan(0.005));
  });

  test('a brown mark shows on tone; an equally dark grey shadow does not', () {
    final mark = SkinMaps.analyze(
      _photo(at: (0.64, 0.5), spot: (160, 112, 80)),
      _w,
      _h,
      _face(),
    )!;
    expect(mark.readings[SkinLens.tone]!.coverage, greaterThan(0.01));

    // Same lightness drop, colour scaled down with it: what shade does.
    final shadow = SkinMaps.analyze(
      _photo(at: (0.64, 0.5), spot: (160, 122, 100)),
      _w,
      _h,
      _face(),
    )!;
    expect(
      shadow.readings[SkinLens.tone]!.coverage,
      lessThan(mark.readings[SkinLens.tone]!.coverage / 3),
    );
  });

  test('a bright colourless highlight shows on the shine lens', () {
    final maps = SkinMaps.analyze(
      _photo(at: (0.5, 0.3), spot: (236, 222, 214), radius: 0.03),
      _w,
      _h,
      _face(),
    )!;
    final shine = maps.readings[SkinLens.shine]!;
    expect(shine.coverage, greaterThan(0.005));
    expect(shine.zones.first.area, 'forehead');
  });

  test('even skin is radiant; blotchy skin scores lower on evenness and clarity', () {
    final even = SkinMaps.analyze(_photo(), _w, _h, _face())!.radiance;
    expect(even.evenness, greaterThan(90));
    expect(even.clarity, greaterThan(90));

    // Scatter brown and red marks across both cheeks and the forehead.
    final px = _photo();
    final rnd = math.Random(7);
    for (var k = 0; k < 60; k++) {
      final cx = 0.3 + rnd.nextDouble() * 0.4;
      final cy = rnd.nextBool()
          ? 0.24 + rnd.nextDouble() * 0.08
          : 0.46 + rnd.nextDouble() * 0.08;
      final (r, g, b) = k.isEven ? (160, 112, 80) : (214, 128, 112);
      for (var y = 0; y < _h; y++) {
        for (var x = 0; x < _w; x++) {
          final dx = x / _w - cx, dy = (y / _h - cy) * _h / _w;
          if (dx * dx + dy * dy > 0.025 * 0.025) continue;
          final i = (y * _w + x) * 4;
          px
            ..[i] = r
            ..[i + 1] = g
            ..[i + 2] = b;
        }
      }
    }
    final blotchy = SkinMaps.analyze(px, _w, _h, _face())!.radiance;
    expect(blotchy.evenness, lessThan(even.evenness - 10));
    expect(blotchy.clarity, lessThan(even.clarity - 10));
    expect(blotchy.score, lessThan(even.score));
  });

  test('radiance survives JSON and clamps bad values', () {
    const r = Radiance(score: 72, evenness: 68, clarity: 89, sheen: 57);
    expect(Radiance.fromJson(r.toJson())?.toJson(), r.toJson());
    expect(Radiance.fromJson({'score': 140})?.score, 100);
    expect(Radiance.fromJson('nope'), isNull);
    expect(Radiance.fromJson(<String, Object?>{}), isNull);
  });

  test('no landmarks, no reading', () {
    expect(
      SkinMaps.analyze(
        _photo(),
        _w,
        _h,
        FaceGeometry(aspect: 0.75, contours: {}),
      ),
      isNull,
    );
  });
}
