// Exports the sample scan's face mesh and skin-lens maps for the launch ad
// renderers in tool/ads. Run with OUT=<data dir>; PHOTO and FACE (a scan's
// face_json) default to the render fixture.
import 'dart:convert';
import 'dart:io';
import 'package:clearskin_ai/domain/scan/face_mesh.dart';
import 'package:clearskin_ai/domain/scan/face_zones.dart';
import 'package:clearskin_ai/domain/scan/skin_maps.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('export', () {
    final out = Platform.environment['OUT']!;
    final env = Platform.environment;
    final g = FaceGeometry.decode(
      File(env['FACE'] ?? 'tool/screenshots/fixtures/sample_face.json').readAsStringSync(),
    )!;
    var photo = img.decodeImage(
      File(env['PHOTO'] ?? 'tool/screenshots/fixtures/sample_face.jpg').readAsBytesSync(),
    )!;
    photo = img.copyResize(photo, width: 360, interpolation: img.Interpolation.average);
    final m = SkinMaps.analyze(photo.getBytes(order: img.ChannelOrder.rgba), photo.width, photo.height, g)!;
    for (final lens in SkinLens.values) {
      final v = m.readings[lens]!.values;
      final im = img.Image(width: m.width, height: m.height, numChannels: 1);
      for (var i = 0; i < v.length; i++) {
        final a = (v[i] * (2 - v[i]) * m.feather[i]).clamp(0, 1);
        im.setPixelR(i % m.width, i ~/ m.width, (a * 255).round());
      }
      File('$out/lens_${lens.name}.png').writeAsBytesSync(img.encodePng(im));
    }
    final mesh = FaceMesh.fromGeometry(g);
    File('$out/mesh.json').writeAsStringSync(jsonEncode({
      'aspect': g.aspect,
      'points': [for (final p in mesh.points) [p.dx, p.dy]],
      'tris': [for (final (a, b, c) in mesh.triangles) [a, b, c]],
      'contours': {for (final e in g.contours.entries) e.key: [for (final p in e.value) [p.dx, p.dy]]},
      'radiance': m.radiance.toJson(),
      'coverage': {for (final l in SkinLens.values) l.name: m.readings[l]!.coverage},
    }));
  });
}
