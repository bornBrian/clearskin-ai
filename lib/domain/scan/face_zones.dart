import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Facial landmarks saved with a scan: ML Kit contour points grouped by
/// contour type, normalised to 0..1 of the photo, plus the photo's aspect.
class FaceGeometry {
  FaceGeometry({
    required this.aspect,
    required Map<String, List<Offset>> contours,
  }) : raw = contours;

  /// width / height of the stored photo.
  final double aspect;

  /// Contours exactly as ML Kit detected them. This is what's stored.
  final Map<String, List<Offset>> raw;

  /// Contours for measuring and drawing: as detected, except that the face
  /// outline reaches the hairline (see [withFullForehead]).
  late final Map<String, List<Offset>> contours = withFullForehead(raw);

  bool get hasLandmarks => raw.isNotEmpty;

  /// How far the outline above the brows is stretched upwards.
  static const foreheadLift = 1.45;

  /// ML Kit's face contour stops around the middle of the forehead, so
  /// lenses, the mesh and the forehead zone used to miss its upper part
  /// (most of it on a high forehead). Points above the brow line are
  /// lifted by [foreheadLift] × their height above it. Any hair the larger
  /// outline catches is dropped later by the skin-colour filter in
  /// SkinMaps, so the outline can be generous.
  static Map<String, List<Offset>> withFullForehead(
    Map<String, List<Offset>> c,
  ) {
    final oval = c['face'];
    final brows = [...?c['leftEyebrowTop'], ...?c['rightEyebrowTop']];
    if (oval == null || oval.length < 8 || brows.isEmpty) return c;
    final browY = brows.map((p) => p.dy).reduce(math.min);
    return {
      ...c,
      'face': [
        for (final p in oval)
          p.dy < browY
              ? Offset(
                  p.dx,
                  math.max(0.0, browY - (browY - p.dy) * foreheadLift),
                )
              : p,
      ],
    };
  }

  String encode() => jsonEncode({
    'a': aspect,
    'c': {
      for (final e in raw.entries)
        e.key: [
          for (final p in e.value)
            [
              double.parse(p.dx.toStringAsFixed(4)),
              double.parse(p.dy.toStringAsFixed(4)),
            ],
        ],
    },
  });

  static FaceGeometry? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final c = (j['c'] as Map<String, dynamic>? ?? const {}).map(
        (k, v) => MapEntry(k, [
          for (final p in v as List)
            Offset(
              ((p as List)[0] as num).toDouble(),
              (p[1] as num).toDouble(),
            ),
        ]),
      );
      return FaceGeometry(aspect: (j['a'] as num).toDouble(), contours: c);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

/// Maps the analysis' face areas (forehead, cheeks, jaw…) to positions on
/// the photo, using real landmarks when available and standard facial
/// proportions otherwise (e.g. gallery photos without detection).
abstract final class FaceZones {
  /// Template for a centred, front-facing face (matches the capture oval).
  static const _template = <String, List<Offset>>{
    'forehead': [Offset(0.5, 0.22)],
    'temples': [Offset(0.27, 0.32), Offset(0.73, 0.32)],
    'under_eyes': [Offset(0.39, 0.42), Offset(0.61, 0.42)],
    'nose': [Offset(0.5, 0.47)],
    'cheeks': [Offset(0.33, 0.52), Offset(0.67, 0.52)],
    'upper_lip': [Offset(0.5, 0.58)],
    'chin': [Offset(0.5, 0.76)],
    'jaw': [Offset(0.29, 0.68), Offset(0.71, 0.68)],
    'neck': [Offset(0.5, 0.86)],
  };

  /// Zone centres (normalised) for an area; empty for "overall".
  static List<Offset> centers(String area, FaceGeometry? g) {
    if (area == 'overall') return const [];
    final fromLandmarks = g != null && g.hasLandmarks
        ? _fromLandmarks(area, g.contours)
        : null;
    return fromLandmarks ?? _template[area] ?? const [];
  }

  /// Relative radius of a zone highlight (fraction of photo width).
  static double radius(String area) => switch (area) {
    'forehead' => 0.16,
    'cheeks' || 'jaw' => 0.11,
    'neck' => 0.14,
    'nose' || 'chin' => 0.08,
    _ => 0.07,
  };

  static List<Offset>? _fromLandmarks(
    String area,
    Map<String, List<Offset>> c,
  ) {
    Offset? mean(String key) {
      final pts = c[key];
      if (pts == null || pts.isEmpty) return null;
      var x = 0.0, y = 0.0;
      for (final p in pts) {
        x += p.dx;
        y += p.dy;
      }
      return Offset(x / pts.length, y / pts.length);
    }

    final oval = c['face'];
    final lEye = mean('leftEye'), rEye = mean('rightEye');
    final lBrow = mean('leftEyebrowTop'), rBrow = mean('rightEyebrowTop');
    final nose = mean('noseBottom') ?? mean('noseBridge');
    final mouthTop = mean('upperLipTop');
    final mouthBottom = mean('lowerLipBottom');
    if (oval == null ||
        oval.length < 8 ||
        lEye == null ||
        rEye == null ||
        nose == null) {
      return null;
    }
    final top = oval.map((p) => p.dy).reduce(math.min);
    final bottom = oval.map((p) => p.dy).reduce(math.max);
    final left = oval.map((p) => p.dx).reduce(math.min);
    final right = oval.map((p) => p.dx).reduce(math.max);
    final width = right - left;
    final browY = [lBrow?.dy, rBrow?.dy].whereType<double>().fold<double>(
      (lEye.dy + rEye.dy) / 2 - (bottom - top) * 0.08,
      (a, b) => math.min(a, b),
    );
    final cx = (lEye.dx + rEye.dx) / 2;
    final eyeY = (lEye.dy + rEye.dy) / 2;
    final mouthY = mouthTop?.dy ?? (nose.dy + (bottom - nose.dy) * 0.35);

    // ML Kit's "left" is the subject's left (viewer's right); order doesn't
    // matter for highlighting both sides.
    return switch (area) {
      'forehead' => [Offset(cx, (top + browY) / 2)],
      'temples' => [
        Offset(left + width * 0.1, eyeY - (eyeY - browY) * 0.6),
        Offset(right - width * 0.1, eyeY - (eyeY - browY) * 0.6),
      ],
      'under_eyes' => [
        Offset(lEye.dx, eyeY + (nose.dy - eyeY) * 0.35),
        Offset(rEye.dx, eyeY + (nose.dy - eyeY) * 0.35),
      ],
      'nose' => [
        Offset(
          (cx + nose.dx) / 2,
          (eyeY + nose.dy) / 2 + (nose.dy - eyeY) * 0.25,
        ),
      ],
      'cheeks' => [
        Offset(
          left + width * 0.22,
          (eyeY + mouthY) / 2 + (mouthY - eyeY) * 0.1,
        ),
        Offset(
          right - width * 0.22,
          (eyeY + mouthY) / 2 + (mouthY - eyeY) * 0.1,
        ),
      ],
      'upper_lip' => [Offset(nose.dx, (nose.dy + mouthY) / 2)],
      'chin' => [Offset(cx, ((mouthBottom?.dy ?? mouthY) + bottom) / 2)],
      'jaw' => [
        Offset(left + width * 0.14, mouthY + (bottom - mouthY) * 0.35),
        Offset(right - width * 0.14, mouthY + (bottom - mouthY) * 0.35),
      ],
      'neck' => [Offset(cx, math.min(0.97, bottom + (bottom - top) * 0.18))],
      _ => null,
    };
  }
}
