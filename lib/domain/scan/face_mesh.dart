import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'face_zones.dart';

/// A triangle as three indexes into the mesh's point list.
typedef Tri = (int, int, int);

class FaceMesh {
  const FaceMesh({required this.points, required this.triangles});

  /// Landmarks in photo space (0..1 of width/height).
  final List<Offset> points;
  final List<Tri> triangles;

  bool get isEmpty => triangles.isEmpty;

  /// Unique edges, for drawing the wireframe once per line.
  Iterable<(int, int)> get edges sync* {
    final seen = <int>{};
    for (final (a, b, c) in triangles) {
      for (final (p, q) in [(a, b), (b, c), (c, a)]) {
        final lo = math.min(p, q), hi = math.max(p, q);
        if (seen.add(lo * 4096 + hi)) yield (lo, hi);
      }
    }
  }

  /// Builds a mesh from the face landmarks captured at scan time: every
  /// contour point, triangulated (Delaunay), keeping only triangles inside
  /// the face outline. Empty when the scan has no landmarks.
  static FaceMesh fromGeometry(FaceGeometry? g) {
    if (g == null || !g.hasLandmarks) {
      return const FaceMesh(points: [], triangles: []);
    }
    final outline = g.contours['face'] ?? const <Offset>[];
    final pts = <Offset>[for (final c in g.contours.values) ...c];
    // De-duplicate shared points (ML Kit repeats lip corners).
    final unique = <Offset>[];
    for (final p in pts) {
      if (!unique.any((u) => (u - p).distance < 1e-3)) unique.add(p);
    }
    // Triangulate in true proportions (x scaled by the photo's aspect).
    final scaled = [for (final p in unique) Offset(p.dx * g.aspect, p.dy)];
    final tris = delaunay(scaled);
    final faceWidth = outline.isEmpty
        ? 1.0
        : (outline.map((p) => p.dx).reduce(math.max) -
                  outline.map((p) => p.dx).reduce(math.min)) *
              g.aspect;
    final kept = <Tri>[];
    for (final t in tris) {
      final a = scaled[t.$1], b = scaled[t.$2], c = scaled[t.$3];
      final longest = [
        (a - b).distance,
        (b - c).distance,
        (c - a).distance,
      ].reduce(math.max);
      if (longest > faceWidth * 0.32) continue;
      final centroid = Offset(
        (unique[t.$1].dx + unique[t.$2].dx + unique[t.$3].dx) / 3,
        (unique[t.$1].dy + unique[t.$2].dy + unique[t.$3].dy) / 3,
      );
      if (outline.length >= 3 && !_inside(centroid, outline)) continue;
      kept.add(t);
    }
    return FaceMesh(points: unique, triangles: kept);
  }

  static bool _inside(Offset p, List<Offset> poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i], b = poly[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }
}

/// Bowyer–Watson Delaunay triangulation. Fine for the ~130 landmarks of a
/// face; returns triangles as index triples into [pts].
List<Tri> delaunay(List<Offset> pts) {
  if (pts.length < 3) return const [];
  var minX = pts.first.dx, minY = pts.first.dy;
  var maxX = minX, maxY = minY;
  for (final p in pts) {
    minX = math.min(minX, p.dx);
    minY = math.min(minY, p.dy);
    maxX = math.max(maxX, p.dx);
    maxY = math.max(maxY, p.dy);
  }
  final d = math.max(maxX - minX, maxY - minY) * 20;
  final mx = (minX + maxX) / 2, my = (minY + maxY) / 2;
  final all = [
    ...pts,
    Offset(mx - d, my - d),
    Offset(mx, my + d),
    Offset(mx + d, my - d),
  ];
  final n = pts.length;
  var tris = <Tri>[(n, n + 1, n + 2)];

  bool inCircumcircle(Tri t, Offset p) {
    final a = all[t.$1], b = all[t.$2], c = all[t.$3];
    final ax = a.dx - p.dx, ay = a.dy - p.dy;
    final bx = b.dx - p.dx, by = b.dy - p.dy;
    final cx = c.dx - p.dx, cy = c.dy - p.dy;
    final det =
        (ax * ax + ay * ay) * (bx * cy - cx * by) -
        (bx * bx + by * by) * (ax * cy - cx * ay) +
        (cx * cx + cy * cy) * (ax * by - bx * ay);
    final orient =
        (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
    return orient > 0 ? det > 0 : det < 0;
  }

  for (var i = 0; i < n; i++) {
    final p = all[i];
    final bad = tris.where((t) => inCircumcircle(t, p)).toList();
    final edgeCount = <(int, int), int>{};
    for (final (a, b, c) in bad) {
      for (final (u, v) in [(a, b), (b, c), (c, a)]) {
        final key = u < v ? (u, v) : (v, u);
        edgeCount[key] = (edgeCount[key] ?? 0) + 1;
      }
    }
    tris = [
      for (final t in tris)
        if (!bad.contains(t)) t,
      for (final e in edgeCount.entries)
        if (e.value == 1) (e.key.$1, e.key.$2, i),
    ];
  }
  return [
    for (final t in tris)
      if (t.$1 < n && t.$2 < n && t.$3 < n) t,
  ];
}
