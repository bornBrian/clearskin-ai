import 'dart:math' as math;

import 'package:clearskin_ai/domain/scan/face_mesh.dart';
import 'package:clearskin_ai/domain/scan/face_zones.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a square splits into two triangles', () {
    final tris = delaunay(const [
      Offset(0, 0),
      Offset(1, 0),
      Offset(1, 1),
      Offset(0, 1),
    ]);
    expect(tris, hasLength(2));
  });

  test('a regular grid triangulates fully with no circumcircle violations', () {
    final pts = [
      for (var y = 0; y < 5; y++)
        for (var x = 0; x < 5; x++)
          Offset(x + (y.isEven ? 0 : 0.03), y + x * 0.01),
    ];
    final tris = delaunay(pts);
    expect(tris, isNotEmpty);
    // Delaunay property: no point lies strictly inside any circumcircle.
    for (final (a, b, c) in tris) {
      final pa = pts[a], pb = pts[b], pc = pts[c];
      final d =
          2 *
          (pa.dx * (pb.dy - pc.dy) +
              pb.dx * (pc.dy - pa.dy) +
              pc.dx * (pa.dy - pb.dy));
      double sq(Offset o) => o.dx * o.dx + o.dy * o.dy;
      final ux =
          (sq(pa) * (pb.dy - pc.dy) +
              sq(pb) * (pc.dy - pa.dy) +
              sq(pc) * (pa.dy - pb.dy)) /
          d;
      final uy =
          (sq(pa) * (pc.dx - pb.dx) +
              sq(pb) * (pa.dx - pc.dx) +
              sq(pc) * (pb.dx - pa.dx)) /
          d;
      final center = Offset(ux, uy);
      final r = (pa - center).distance;
      for (var i = 0; i < pts.length; i++) {
        if (i == a || i == b || i == c) continue;
        expect((pts[i] - center).distance, greaterThan(r - 1e-9));
      }
    }
  });

  test('mesh comes from real landmarks and stays inside the face', () {
    // A face outline (circle) with a few inner landmarks.
    final outline = [
      for (var i = 0; i < 36; i++)
        Offset(
          0.5 + 0.3 * math.cos(i / 36 * math.pi * 2),
          0.5 + 0.38 * math.sin(i / 36 * math.pi * 2),
        ),
    ];
    final g = FaceGeometry(
      aspect: 0.75,
      contours: {
        'face': outline,
        'leftEye': const [Offset(0.6, 0.42), Offset(0.66, 0.42)],
        'rightEye': const [Offset(0.34, 0.42), Offset(0.4, 0.42)],
        'noseBottom': const [Offset(0.5, 0.56)],
        'upperLipTop': const [Offset(0.44, 0.66), Offset(0.56, 0.66)],
      },
    );
    final mesh = FaceMesh.fromGeometry(g);
    expect(mesh.isEmpty, isFalse);
    expect(mesh.points, hasLength(36 + 7));
    expect(mesh.edges.length, greaterThan(mesh.triangles.length));
  });

  test('no landmarks, no mesh — never a fake face', () {
    expect(FaceMesh.fromGeometry(null).isEmpty, isTrue);
    expect(
      FaceMesh.fromGeometry(const FaceGeometry(aspect: 1, contours: {})).isEmpty,
      isTrue,
    );
  });
}
