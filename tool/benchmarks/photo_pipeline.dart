// Times the on-phone photo pipeline (what PhotoService does per photo, in a
// background isolate) for a camera frame (ResolutionPreset.veryHigh) and the
// largest gallery photo the picker hands over (maxWidth 2400):
//
//   dart run tool/benchmarks/photo_pipeline.dart
//
// Desktop numbers; a mid-range phone is roughly 3-5x slower.
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const maxEdge = 1280, aiEdge = 1024, aiTarget = 160 * 1024;

img.Image resize(img.Image i, int edge) => i.width >= i.height
    ? img.copyResize(i, width: edge, interpolation: img.Interpolation.average)
    : img.copyResize(i, height: edge, interpolation: img.Interpolation.average);

void main() {
  final face = img.decodeJpg(
    File('tool/screenshots/fixtures/sample_face.jpg').readAsBytesSync(),
  )!;
  for (final (label, w, h) in [
    ('camera 1080x1920', 1080, 1920),
    ('gallery 2400x3200', 2400, 3200),
  ]) {
    stdout.writeln('\n$label');
    _bench(
      img.encodeJpg(img.copyResize(face, width: w, height: h), quality: 92),
    );
  }
}

void _bench(Uint8List camera) {
  stdout.writeln('input: ${(camera.length / 1024).round()} KB');

  final t = <String, List<int>>{};
  void time(String name, void Function() f) {
    final sw = Stopwatch()..start();
    f();
    (t[name] ??= []).add(sw.elapsedMilliseconds);
  }

  for (var run = 0; run < 5; run++) {
    late img.Image decoded, normal, small;
    late Uint8List jpeg;
    time('1 decode', () => decoded = img.decodeJpg(camera)!);
    time('2 resize to 1280', () => normal = resize(decoded, maxEdge));
    time(
      '3 encode 1280 (q88)',
      () => jpeg = img.encodeJpg(normal, quality: 88),
    );
    time('4 resize to 1024', () => small = resize(normal, aiEdge));
    var q = 85, tries = 0;
    time('5 encode AI copy (fit 160 KB)', () {
      var out = img.encodeJpg(small, quality: q);
      tries = 1;
      while (out.length > aiTarget && q > 60) {
        q -= 5;
        tries++;
        out = img.encodeJpg(small, quality: q);
      }
    });
    if (run == 0) stdout.writeln('AI copy: quality $q after $tries encode(s)');
    time('6 decode 1280 again (light check)', () => img.decodeJpg(jpeg));
  }
  var total = 0;
  t.forEach((k, v) {
    final med = (v..sort())[v.length ~/ 2];
    total += med;
    stdout.writeln('${k.padRight(36)} ${med.toString().padLeft(5)} ms');
  });
  stdout.writeln(
    '${'total per photo'.padRight(36)} ${total.toString().padLeft(5)} ms (x3 photos per scan)',
  );
}
