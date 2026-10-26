import 'dart:math' as math;

import 'package:clearskin_ai/domain/scan/face_zones.dart';
import 'package:flutter_test/flutter_test.dart';

FaceGeometry _face() {
  // A synthetic front-facing face: oval centred at (0.5, 0.48).
  final oval = [
    for (var i = 0; i < 36; i++)
      Offset(0.5 + 0.27 * _cos(i * 10.0), 0.48 + 0.36 * _sin(i * 10.0)),
  ];
  return FaceGeometry(
    aspect: 0.75,
    contours: {
      'face': oval,
      'leftEye': [const Offset(0.40, 0.40), const Offset(0.44, 0.40)],
      'rightEye': [const Offset(0.56, 0.40), const Offset(0.60, 0.40)],
      'leftEyebrowTop': [const Offset(0.40, 0.34)],
      'rightEyebrowTop': [const Offset(0.60, 0.34)],
      'noseBottom': [const Offset(0.5, 0.52)],
      'upperLipTop': [const Offset(0.5, 0.60)],
      'lowerLipBottom': [const Offset(0.5, 0.66)],
    },
  );
}

double _cos(double deg) => math.cos(deg * math.pi / 180);
double _sin(double deg) => math.sin(deg * math.pi / 180);

void main() {
  test('landmark zones are ordered top to bottom like a real face', () {
    final g = _face();
    double y(String area) => FaceZones.centers(area, g).first.dy;
    expect(y('forehead'), lessThan(y('under_eyes')));
    expect(y('under_eyes'), lessThan(y('nose')));
    expect(y('nose'), lessThan(y('upper_lip')));
    expect(y('upper_lip'), lessThan(y('chin')));
    expect(y('chin'), lessThan(y('neck')));
  });

  test('paired zones sit on both sides of the face', () {
    final cheeks = FaceZones.centers('cheeks', _face());
    expect(cheeks, hasLength(2));
    expect(cheeks[0].dx, lessThan(0.5));
    expect(cheeks[1].dx, greaterThan(0.5));
  });

  test('falls back to the template without landmarks; overall has no pin', () {
    expect(FaceZones.centers('jaw', null), hasLength(2));
    expect(FaceZones.centers('overall', _face()), isEmpty);
  });

  test('geometry survives encode/decode', () {
    final g = _face();
    final back = FaceGeometry.decode(g.encode())!;
    expect(back.aspect, 0.75);
    expect(back.contours['leftEye']!.first.dx, closeTo(0.40, 1e-4));
    expect(FaceGeometry.decode('not json'), isNull);
  });
}
