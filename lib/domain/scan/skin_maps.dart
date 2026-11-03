import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'face_zones.dart';

/// A way of looking at the skin in a scan photo. Each one is a measurement
/// of the photo's own pixels, not a guess: colour is converted to CIELAB
/// (the perceptual colour space used in dermatology imaging) and compared
/// against the person's own skin, so it works the same on every skin tone.
enum SkinLens {
  /// Where skin is even in colour (small CIE ΔE against the skin around it)
  /// and catches light softly rather than as oily hot-spots — the cues
  /// people read as a healthy glow. The one lens that shows what's good.
  radiance('Radiance', 'Even colour that catches light softly: your glow.'),

  /// a* (red–green axis) above the person's own skin average, globally or
  /// against the skin around it — the photographic proxy for erythema.
  redness('Redness', 'Redder than your own skin: irritation or active spots.'),

  /// L* (lightness) below the skin around it — marks and uneven pigment.
  tone('Tone', 'Darker than the skin around it: marks and uneven tone.'),

  /// Specular highlights: brighter than the surrounding skin with less
  /// colour — light bouncing off surface oil.
  shine('Shine', 'Bright, colourless reflections: where oil sits.'),

  /// Fine-scale lightness variation (high-pass energy) relative to the
  /// face's own median — pores and an uneven surface.
  texture('Texture', 'Fine light-and-shadow detail: pores and rough patches.');

  const SkinLens(this.label, this.explainer);
  final String label;
  final String explainer;
}

/// How much of one face zone a lens picked up.
class ZoneShare {
  const ZoneShare(this.area, this.share);

  /// FaceZones area key ("cheeks", "forehead"…).
  final String area;

  /// Fraction (0..1) of that zone's skin above [SkinMaps.threshold].
  final double share;
}

class LensReading {
  const LensReading({
    required this.values,
    required this.coverage,
    required this.zones,
  });

  /// 0..1 per pixel (row-major, analysis resolution), 0 outside skin.
  final Float32List values;

  /// Fraction (0..1) of all skin pixels above [SkinMaps.threshold].
  final double coverage;

  /// Zones with a meaningful share, most affected first.
  final List<ZoneShare> zones;
}

/// A photo's glow as three measurements and their blend, each 0–100 where
/// higher is better.
class Radiance {
  const Radiance({
    required this.score,
    required this.evenness,
    required this.clarity,
    required this.sheen,
  });

  /// Half evenness, a third clarity, a fifth sheen: evenness of colour is
  /// the strongest single cue in how healthy and radiant skin looks.
  final int score;

  /// How little colour varies patch to patch (median local ΔE).
  final int evenness;

  /// How free of red and dark spots (redness + tone coverage).
  final int clarity;

  /// Soft, diffuse highlights present, harsh oily hot-spots absent.
  final int sheen;

  Map<String, int> toJson() => {
    'score': score,
    'evenness': evenness,
    'clarity': clarity,
    'sheen': sheen,
  };

  static Radiance? fromJson(Object? j) {
    if (j is! Map) return null;
    int? v(String k) => (j[k] as num?)?.round().clamp(0, 100);
    final score = v('score');
    if (score == null) return null;
    return Radiance(
      score: score,
      evenness: v('evenness') ?? score,
      clarity: v('clarity') ?? score,
      sheen: v('sheen') ?? score,
    );
  }
}

/// Per-pixel skin measurements for one photo, at analysis resolution.
class SkinMaps {
  const SkinMaps({
    required this.width,
    required this.height,
    required this.mask,
    required this.feather,
    required this.readings,
    required this.radiance,
    this.skinLightness = 0,
  });

  final int width;
  final int height;

  /// 1 where the pixel is readable skin.
  final Uint8List mask;

  /// 0..1 soft version of [mask], for drawing overlays without hard edges.
  final Float32List feather;
  final Map<SkinLens, LensReading> readings;
  final Radiance radiance;

  /// Median CIELAB L* of the skin: how brightly the face was lit. Two photos
  /// far apart here weren't taken in comparable light.
  final double skinLightness;

  /// A pixel counts towards coverage above this value.
  static const threshold = 0.4;

  static const _zones = [
    'forehead',
    'temples',
    'under_eyes',
    'nose',
    'cheeks',
    'upper_lip',
    'chin',
    'jaw',
  ];

  /// Measures [rgba] (8-bit RGBA, [w]×[h]) using the landmarks in [g].
  /// Null when there are no usable landmarks or too little visible skin.
  static SkinMaps? analyze(Uint8List rgba, int w, int h, FaceGeometry g) {
    final oval = g.contours['face'];
    if (oval == null || oval.length < 8 || rgba.length < w * h * 4) {
      return null;
    }
    final n = w * h;
    final l = Float32List(n), a = Float32List(n), b = Float32List(n);
    _toLab(rgba, l, a, b);

    // ── Skin mask: the face outline minus eyes, brows, lips and nostrils.
    List<Offset> px(List<Offset> pts) => [
      for (final p in pts) Offset(p.dx * w, p.dy * h),
    ];
    final mask = Uint8List(n);
    _fill(mask, w, h, _scale(px(oval), 0.95, 0.96), 1);
    final outline = Float32List(n);
    for (var i = 0; i < n; i++) {
      outline[i] = mask[i].toDouble();
    }
    for (final eye in ['leftEye', 'rightEye']) {
      final pts = g.contours[eye];
      if (pts != null && pts.length >= 3) {
        _fill(mask, w, h, _scale(px(pts), 1.4, 2.6), 0);
      }
    }
    for (final side in ['left', 'right']) {
      final top = g.contours['${side}EyebrowTop'];
      final bottom = g.contours['${side}EyebrowBottom'];
      if (top != null && bottom != null && top.length + bottom.length >= 3) {
        _fill(
          mask,
          w,
          h,
          _scale(px([...top, ...bottom.reversed]), 1.3, 2.6),
          0,
        );
      }
    }
    final lipTop = g.contours['upperLipTop'];
    final lipBottom = g.contours['lowerLipBottom'];
    if (lipTop != null && lipBottom != null) {
      _fill(
        mask,
        w,
        h,
        _scale(px([...lipTop, ...lipBottom.reversed]), 1.15, 1.5),
        0,
      );
    }
    final ovalPx = px(oval);
    final faceLeft = ovalPx.map((p) => p.dx).reduce(math.min);
    final faceRight = ovalPx.map((p) => p.dx).reduce(math.max);
    final faceWidth = faceRight - faceLeft;
    final nose = g.contours['noseBottom'];
    if (nose != null && nose.isNotEmpty) {
      final pts = px(nose);
      final cx = pts.map((p) => p.dx).reduce((x, y) => x + y) / pts.length;
      final cy = pts.map((p) => p.dy).reduce((x, y) => x + y) / pts.length;
      final rx = faceWidth * 0.13, ry = faceWidth * 0.06;
      _fill(mask, w, h, [
        for (var i = 0; i < 16; i++)
          Offset(
            cx + rx * math.cos(i / 16 * math.pi * 2),
            cy - ry * 0.3 + ry * math.sin(i / 16 * math.pi * 2),
          ),
      ], 0);
    }

    // Drop what isn't skin colour (hair across the face, glasses, deep
    // shadow) relative to this person's own median skin.
    var medL = _median(l, mask), medA = _median(a, mask);
    var medB = _median(b, mask);
    for (var i = 0; i < n; i++) {
      if (mask[i] == 0) continue;
      final dab = math.sqrt(
        (a[i] - medA) * (a[i] - medA) + (b[i] - medB) * (b[i] - medB),
      );
      if ((l[i] - medL).abs() > 30 || dab > 20) mask[i] = 0;
    }
    _erode(mask, w, h);
    final skin = mask.fold<int>(0, (s, m) => s + m);
    if (skin < n * 0.04) return null;
    medL = _median(l, mask);
    medA = _median(a, mask);
    medB = _median(b, mask);

    // ── Local baselines: what the skin around each pixel looks like, so
    // lighting falling across the face isn't read as a skin change.
    final big = math.max(3, (faceWidth * 0.09).round());
    final lLocal = _boxMean(l, mask, w, h, big);
    final aLocal = _boxMean(a, mask, w, h, big);
    final chroma = Float32List(n);
    for (var i = 0; i < n; i++) {
      chroma[i] = math.sqrt(a[i] * a[i] + b[i] * b[i]);
    }
    final cLocal = _boxMean(chroma, mask, w, h, big);
    final bLocal = _boxMean(b, mask, w, h, big);

    // Fine-scale energy for texture, scaled to the photo's resolution.
    final fine = math.max(1, (faceWidth / 220).round());
    final lBlur = _boxMean(l, mask, w, h, fine);
    final hp2 = Float32List(n);
    for (var i = 0; i < n; i++) {
      final d = l[i] - lBlur[i];
      hp2[i] = d * d;
    }
    final energy = _boxMean(hp2, mask, w, h, fine * 2);
    for (var i = 0; i < n; i++) {
      energy[i] = math.sqrt(energy[i]);
    }
    final medE = math.max(0.05, _median(energy, mask));

    // Patch-scale colour (a few mm) against the wider skin: the colour
    // variation the eye reads as uneven, above pore-level detail.
    final mid = math.max(2, (faceWidth * 0.02).round());
    final lMid = _boxMean(l, mask, w, h, mid);
    final aMid = _boxMean(a, mask, w, h, mid);
    final bMid = _boxMean(b, mask, w, h, mid);
    final deltaE = Float32List(n);
    for (var i = 0; i < n; i++) {
      final dl = lMid[i] - lLocal[i];
      final da = aMid[i] - aLocal[i];
      final db = bMid[i] - bLocal[i];
      deltaE[i] = math.sqrt(dl * dl + da * da + db * db);
    }

    // The face curves away from the camera at its edges: shading and stray
    // hair there aren't skin changes, so readings fade out near the outline.
    final all = Uint8List(n)..fillRange(0, n, 1);
    final depth = _boxMean(outline, all, w, h, big);
    // Lashes and brow hairs at the edges of the cut-outs read as texture.
    final maskF = Float32List(n);
    for (var i = 0; i < n; i++) {
      maskF[i] = mask[i].toDouble();
    }
    final holeDepth = _boxMean(maskF, all, w, h, fine * 3);

    double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
    final raw = {for (final lens in SkinLens.values) lens: Float32List(n)};
    for (var i = 0; i < n; i++) {
      if (mask[i] == 0) continue;
      final inner = clamp01((depth[i] - 0.62) / 0.3);
      final redGlobal = a[i] - medA;
      final redLocal = (a[i] - aLocal[i]) * 1.2;
      raw[SkinLens.redness]![i] =
          clamp01((math.max(redGlobal, redLocal) - 3.5) / 8) * inner;
      // Shadow scales colour down with lightness; melanin darkens without
      // losing chroma. Keeping only darkening that holds its chroma
      // separates marks from folds and shading.
      final pigmented = clamp01(
        (chroma[i] - cLocal[i] * 0.9) / math.max(0.5, cLocal[i] * 0.12),
      );
      raw[SkinLens.tone]![i] =
          clamp01((lLocal[i] - l[i] - 3) / 9) * pigmented * inner;
      final colourless = clamp01(
        (cLocal[i] * 1.15 - chroma[i]) / math.max(1, cLocal[i] * 0.3),
      );
      raw[SkinLens.shine]![i] =
          clamp01((l[i] - lLocal[i] - 4) / 8) * colourless * inner;
      // Glow: even colour here, lifted a little where light falls softly,
      // and none of it where the light is an oily hot-spot.
      final even = clamp01(1 - (deltaE[i] - 1) / 4);
      final lift = clamp01((lMid[i] - lLocal[i] - 0.5) / 3);
      raw[SkinLens.radiance]![i] =
          even * (0.6 + 0.4 * lift) * (1 - raw[SkinLens.shine]![i]) * inner;
      raw[SkinLens.texture]![i] =
          clamp01((energy[i] / medE - 1.25) / 1.5) *
          inner *
          clamp01((holeDepth[i] - 0.8) / 0.15);
    }

    // ── Smooth into regions, then read coverage per face zone.
    final centers = <(String, Offset)>[
      for (final z in _zones)
        for (final c in FaceZones.centers(z, g))
          (z, Offset(c.dx * w, c.dy * h)),
    ];
    final zoneOf = Int8List(n)..fillRange(0, n, -1);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (mask[i] == 0) continue;
        var best = -1;
        var bestD = double.infinity;
        for (var k = 0; k < centers.length; k++) {
          final c = centers[k].$2;
          final d = (c.dx - x) * (c.dx - x) + (c.dy - y) * (c.dy - y);
          if (d < bestD) {
            bestD = d;
            best = _zones.indexOf(centers[k].$1);
          }
        }
        zoneOf[i] = best;
      }
    }

    final readings = <SkinLens, LensReading>{};
    final soft = math.max(1, (faceWidth * 0.012).round());
    for (final lens in SkinLens.values) {
      var v = raw[lens]!;
      for (var pass = 0; pass < 2; pass++) {
        v = _boxMean(
          v,
          mask,
          w,
          h,
          lens == SkinLens.texture || lens == SkinLens.radiance
              ? soft * 2
              : soft,
        );
      }
      var hits = 0;
      final zoneSkin = List.filled(_zones.length, 0);
      final zoneHits = List.filled(_zones.length, 0);
      for (var i = 0; i < n; i++) {
        if (mask[i] == 0) {
          v[i] = 0;
          continue;
        }
        final z = zoneOf[i];
        if (z >= 0) zoneSkin[z]++;
        if (v[i] > threshold) {
          hits++;
          if (z >= 0) zoneHits[z]++;
        }
      }
      final zones = [
        for (var z = 0; z < _zones.length; z++)
          if (zoneSkin[z] > skin * 0.02 && zoneHits[z] / zoneSkin[z] >= 0.02)
            ZoneShare(_zones[z], zoneHits[z] / zoneSkin[z]),
      ]..sort((x, y) => y.share.compareTo(x.share));
      readings[lens] = LensReading(
        values: v,
        coverage: hits / skin,
        zones: zones,
      );
    }

    // Two passes give a soft falloff at every cut-out, so overlays never
    // show the shape of the mask.
    var feather = _boxMean(maskF, all, w, h, math.max(3, soft * 3));
    feather = _boxMean(feather, all, w, h, math.max(2, soft * 2));
    for (var i = 0; i < n; i++) {
      final f = ((feather[i] - 0.25) / 0.6).clamp(0.0, 1.0);
      feather[i] = f * f * (3 - 2 * f) * mask[i];
    }

    // ── Radiance scores.
    // How strongly light catches the high planes (cheekbones, brow, nose
    // bridge): the 90th percentile of patch lift over the skin around it,
    // leaving out oily hot-spots, which count against sheen instead.
    final lifts = <double>[
      for (var i = 0; i < n; i++)
        if (mask[i] == 1 && raw[SkinLens.shine]![i] < 0.3) lMid[i] - lLocal[i],
    ]..sort();
    final catchLight = lifts.isEmpty
        ? 0.0
        : lifts[(lifts.length * 0.9).floor()];
    // Mean, not median: scattered marks over a minority of the face still
    // make it look uneven.
    var sumDE = 0.0;
    for (var i = 0; i < n; i++) {
      if (mask[i] == 1) sumDE += deltaE[i];
    }
    // ~1.5 ΔE is camera noise on even skin; 6.5 is visibly blotchy.
    final evenness = 100 * clamp01(1 - (sumDE / skin - 1.5) / 5);
    final blemish =
        readings[SkinLens.redness]!.coverage +
        readings[SkinLens.tone]!.coverage;
    final clarity = 100 * clamp01(1 - blemish / 0.12);
    final harsh = readings[SkinLens.shine]!.coverage;
    final sheen =
        100 *
        clamp01((catchLight - 0.5) / 4) *
        (1 - 0.6 * clamp01(harsh / 0.06));

    return SkinMaps(
      width: w,
      height: h,
      mask: mask,
      feather: feather,
      readings: readings,
      skinLightness: medL,
      radiance: Radiance(
        score: (0.5 * evenness + 0.3 * clarity + 0.2 * sheen).round(),
        evenness: evenness.round(),
        clarity: clarity.round(),
        sheen: sheen.round(),
      ),
    );
  }

  // ── Colour ──────────────────────────────────────────────────────────

  static final _linear = Float64List.fromList([
    for (var i = 0; i < 256; i++)
      i / 255 <= 0.04045
          ? i / 255 / 12.92
          : math.pow((i / 255 + 0.055) / 1.055, 2.4).toDouble(),
  ]);

  static double _f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;

  /// sRGB → CIELAB (D65).
  static void _toLab(
    Uint8List rgba,
    Float32List l,
    Float32List a,
    Float32List b,
  ) {
    for (var i = 0; i < l.length; i++) {
      final r = _linear[rgba[i * 4]];
      final g = _linear[rgba[i * 4 + 1]];
      final bl = _linear[rgba[i * 4 + 2]];
      final fx = _f((0.4124 * r + 0.3576 * g + 0.1805 * bl) / 0.95047);
      final fy = _f(0.2126 * r + 0.7152 * g + 0.0722 * bl);
      final fz = _f((0.0193 * r + 0.1192 * g + 0.9505 * bl) / 1.08883);
      l[i] = 116 * fy - 16;
      a[i] = 500 * (fx - fy);
      b[i] = 200 * (fy - fz);
    }
  }

  /// Lab colour of a pixel, exposed for tests.
  static (double, double, double) labOf(int r, int g, int b) {
    final l = Float32List(1), a = Float32List(1), bb = Float32List(1);
    _toLab(Uint8List.fromList([r, g, b, 255]), l, a, bb);
    return (l[0], a[0], bb[0]);
  }

  // ── Raster helpers ──────────────────────────────────────────────────

  static double _median(Float32List v, Uint8List mask) {
    final vals = <double>[
      for (var i = 0; i < v.length; i++)
        if (mask[i] == 1) v[i],
    ];
    if (vals.isEmpty) return 0;
    vals.sort();
    return vals[vals.length ~/ 2];
  }

  /// Mean of [v] over masked pixels in a (2r+1)² window, via summed-area
  /// tables, so cost doesn't depend on the radius.
  static Float32List _boxMean(
    Float32List v,
    Uint8List mask,
    int w,
    int h,
    int r,
  ) {
    final sw = w + 1;
    final sum = Float64List(sw * (h + 1));
    final cnt = Float64List(sw * (h + 1));
    for (var y = 0; y < h; y++) {
      var rowSum = 0.0, rowCnt = 0.0;
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (mask[i] == 1) {
          rowSum += v[i];
          rowCnt += 1;
        }
        final j = (y + 1) * sw + x + 1;
        sum[j] = sum[j - sw] + rowSum;
        cnt[j] = cnt[j - sw] + rowCnt;
      }
    }
    final out = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - r), y1 = math.min(h, y + r + 1);
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - r), x1 = math.min(w, x + r + 1);
        final c =
            cnt[y1 * sw + x1] -
            cnt[y0 * sw + x1] -
            cnt[y1 * sw + x0] +
            cnt[y0 * sw + x0];
        if (c <= 0) continue;
        final s =
            sum[y1 * sw + x1] -
            sum[y0 * sw + x1] -
            sum[y1 * sw + x0] +
            sum[y0 * sw + x0];
        out[y * w + x] = s / c;
      }
    }
    return out;
  }

  static void _erode(Uint8List mask, int w, int h) {
    final copy = Uint8List.fromList(mask);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (copy[i] == 0) continue;
        if (x == 0 ||
            y == 0 ||
            x == w - 1 ||
            y == h - 1 ||
            copy[i - 1] == 0 ||
            copy[i + 1] == 0 ||
            copy[i - w] == 0 ||
            copy[i + w] == 0) {
          mask[i] = 0;
        }
      }
    }
  }

  static List<Offset> _scale(List<Offset> poly, double sx, double sy) {
    var cx = 0.0, cy = 0.0;
    for (final p in poly) {
      cx += p.dx;
      cy += p.dy;
    }
    cx /= poly.length;
    cy /= poly.length;
    return [
      for (final p in poly)
        Offset(cx + (p.dx - cx) * sx, cy + (p.dy - cy) * sy),
    ];
  }

  /// Scanline polygon fill (even–odd).
  static void _fill(
    Uint8List mask,
    int w,
    int h,
    List<Offset> poly,
    int value,
  ) {
    if (poly.length < 3) return;
    final ys = poly.map((p) => p.dy);
    final top = math.max(0, ys.reduce(math.min).floor());
    final bottom = math.min(h - 1, ys.reduce(math.max).ceil());
    for (var y = top; y <= bottom; y++) {
      final sy = y + 0.5;
      final xs = <double>[];
      for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        final p = poly[i], q = poly[j];
        if ((p.dy > sy) != (q.dy > sy)) {
          xs.add(p.dx + (sy - p.dy) / (q.dy - p.dy) * (q.dx - p.dx));
        }
      }
      xs.sort();
      for (var k = 0; k + 1 < xs.length; k += 2) {
        final x0 = math.max(0, (xs[k] - 0.5).ceil());
        final x1 = math.min(w - 1, (xs[k + 1] - 0.5).floor());
        for (var x = x0; x <= x1; x++) {
          mask[y * w + x] = value;
        }
      }
    }
  }
}
