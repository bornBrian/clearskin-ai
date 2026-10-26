import 'package:clearskin_ai/domain/scan/live_guidance.dart';
import 'package:flutter_test/flutter_test.dart';

LiveFrame frame({
  int faces = 1,
  double lum = 130,
  double? faceLum = 130,
  double? balance = 1.0,
  double w = 0.55,
  double cx = 0.5,
  double cy = 0.45,
  double yaw = 0,
  double roll = 0,
  double pitch = 0,
  bool cut = false,
  double? eyes = 0.9,
  double? motion = 0.005,
}) => LiveFrame(
  faceCount: faces,
  luminance: lum,
  faceLuminance: faceLum,
  sideBalance: balance,
  faceWidth: w,
  centerX: cx,
  centerY: cy,
  yaw: yaw,
  roll: roll,
  pitch: pitch,
  cutOff: cut,
  eyesOpen: eyes,
  motion: motion,
);

void main() {
  test('a centred, well-lit, straight, still face is ready', () {
    expect(LiveGuidance.evaluate(frame()), LiveHint.aligned);
    expect(LiveHint.aligned.ready, isTrue);
    expect(LiveGuidance.passed(LiveHint.aligned), LiveCheck.values.toSet());
  });

  test('one clear instruction at a time, highest priority first', () {
    // Dark AND far AND tilted: lighting is fixed first.
    expect(
      LiveGuidance.evaluate(frame(faceLum: 30, w: 0.2, yaw: 30)),
      LiveHint.tooDark,
    );
    expect(LiveGuidance.evaluate(frame(w: 0.2, yaw: 30)), LiveHint.moveCloser);
    expect(LiveGuidance.evaluate(frame(yaw: 30)), LiveHint.lookStraight);
  });

  test('framing problems are detected', () {
    expect(LiveGuidance.evaluate(frame(faces: 0)), LiveHint.noFace);
    expect(LiveGuidance.evaluate(frame(faces: 2)), LiveHint.multipleFaces);
    expect(LiveGuidance.evaluate(frame(cut: true)), LiveHint.faceCut);
    expect(LiveGuidance.evaluate(frame(w: 0.9)), LiveHint.moveBack);
    expect(LiveGuidance.evaluate(frame(cx: 0.8)), LiveHint.center);
    expect(LiveGuidance.evaluate(frame(pitch: 25)), LiveHint.levelChin);
  });

  test('light is judged on the face, not the whole frame', () {
    // Bright window behind a dim face: the frame looks fine, the face isn't.
    expect(
      LiveGuidance.evaluate(frame(lum: 170, faceLum: 90)),
      LiveHint.backlit,
    );
    expect(LiveGuidance.evaluate(frame(faceLum: 230)), LiveHint.tooBright);
    expect(LiveGuidance.evaluate(frame(balance: 1.8)), LiveHint.unevenLight);
    expect(
      LiveGuidance.evaluate(frame(balance: 1 / 1.8)),
      LiveHint.unevenLight,
    );
    // Without a face reading, the frame's light is the fallback.
    expect(
      LiveGuidance.evaluate(frame(lum: 40, faceLum: null)),
      LiveHint.tooDark,
    );
  });

  test('eyes open and holding still come last', () {
    expect(LiveGuidance.evaluate(frame(eyes: 0.1)), LiveHint.openEyes);
    expect(LiveGuidance.evaluate(frame(motion: 0.06)), LiveHint.holdStill);
  });

  test('checks light up in order', () {
    expect(LiveGuidance.passed(LiveHint.backlit), isEmpty);
    expect(LiveGuidance.passed(LiveHint.center), {LiveCheck.light});
    expect(LiveGuidance.passed(LiveHint.holdStill), {
      LiveCheck.light,
      LiveCheck.position,
    });
  });

  test('upright pixels map back to the right sensor pixel', () {
    // A 4×3 sensor buffer with a unique value per pixel.
    const w = 4, h = 3;
    final sensor = [
      for (var y = 0; y < h; y++) [for (var x = 0; x < w; x++) y * w + x],
    ];
    // Rotate it clockwise by 90° steps the slow, obvious way.
    List<List<int>> cw(List<List<int>> m) => [
      for (var x = 0; x < m.first.length; x++)
        [for (var y = m.length - 1; y >= 0; y--) m[y][x]],
    ];
    var upright = sensor;
    for (final rotation in [0, 90, 180, 270]) {
      for (var uy = 0; uy < upright.length; uy++) {
        for (var ux = 0; ux < upright.first.length; ux++) {
          final (sx, sy) = LiveGuidance.uprightToSensor(
            ux.toDouble(),
            uy.toDouble(),
            w,
            h,
            rotation,
          );
          expect(
            sensor[sy][sx],
            upright[uy][ux],
            reason: 'rotation $rotation at ($ux, $uy)',
          );
        }
      }
      upright = cw(upright);
    }
  });
}
