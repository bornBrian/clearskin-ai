import 'dart:math' as math;

/// What the live camera should tell the user right now. Ordered by priority:
/// the first problem found is the one shown, so instructions never compete.
enum LiveHint {
  noFace('Fit your face inside the oval'),
  multipleFaces('Only your face in the frame'),
  faceCut('Bring your whole face into view'),
  showForehead('Move back so your whole forehead fits'),
  tooDark('Find more light — face a window'),
  backlit('Light is behind you — turn to face it'),
  tooBright('Too bright — step out of direct sun'),
  unevenLight('Light is on one side — face it straight on'),
  moveCloser('Move a little closer'),
  moveBack('Move back a little'),
  center('Center your face in the oval'),
  lookStraight('Look straight at the camera'),
  levelChin('Keep your chin level'),
  turnSide('Slowly turn your head to one side'),
  turnOtherSide('Now turn to the other side'),
  turnLess('A little less — turn back slightly'),
  openEyes('Keep your eyes open'),
  holdStill('Hold still'),
  aligned('Perfect — hold it there');

  const LiveHint(this.message);
  final String message;

  bool get ready => this == LiveHint.aligned;

  /// Which of the three on-screen checks this hint belongs to.
  LiveCheck? get check => switch (this) {
    tooDark || backlit || tooBright || unevenLight => LiveCheck.light,
    noFace ||
    multipleFaces ||
    faceCut ||
    showForehead ||
    moveCloser ||
    moveBack ||
    center ||
    lookStraight ||
    levelChin ||
    turnSide ||
    turnOtherSide ||
    turnLess => LiveCheck.position,
    openEyes || holdStill => LiveCheck.still,
    aligned => null,
  };
}

/// The three things a good scan needs, shown as quiet words that light up.
enum LiveCheck {
  light('Light'),
  position('Position'),
  still('Still');

  const LiveCheck(this.label);
  final String label;
}

/// The three photos of a full scan. The front shows the whole face from
/// hairline to chin; the two side views show cheeks, jawline and temples
/// that a straight-on photo foreshortens.
enum ScanPose {
  front('Front'),
  sideA('Side'),
  sideB('Other side');

  const ScanPose(this.label);
  final String label;

  bool get isSide => this != front;
}

/// One analysed camera frame, in upright (portrait) coordinates.
class LiveFrame {
  const LiveFrame({
    required this.faceCount,
    required this.luminance,
    this.faceLuminance,
    this.sideBalance,
    this.faceWidth,
    this.centerX,
    this.centerY,
    this.yaw,
    this.roll,
    this.pitch,
    this.cutOff = false,
    this.headroom,
    this.eyesOpen,
    this.motion,
  });

  final int faceCount;

  /// Mean frame luminance, 0..255.
  final double luminance;

  /// Mean luminance over the face box only, 0..255. The face is what has to
  /// be lit: a bright window behind a dark face is still a dark face.
  final double? faceLuminance;

  /// Mean luminance of the face's left half over its right half. ~1 = even.
  final double? sideBalance;

  /// Face box width as a fraction of frame width.
  final double? faceWidth;

  /// Face centre as fractions of frame width/height.
  final double? centerX;
  final double? centerY;
  final double? yaw;
  final double? roll;
  final double? pitch;

  /// The face box runs past an edge of the frame.
  final bool cutOff;

  /// Space above the face box, as a fraction of the box's height. ML Kit's
  /// box starts around mid-forehead, so the hairline needs room above it.
  final double? headroom;

  /// The less-open eye's open probability, 0..1.
  final double? eyesOpen;

  /// How far the face centre moved since the last frame, as a fraction of
  /// frame width.
  final double? motion;
}

/// Live thresholds are a little looser than the post-capture checks
/// ([CaptureQuality]) so the guide feels helpful rather than fussy; the
/// final photo is still validated strictly.
abstract final class LiveGuidance {
  /// Where the on-screen oval sits (fraction of frame height).
  static const targetY = 0.45;

  /// Room needed above the face box for the full forehead and hairline.
  static const minHeadroom = 0.3;

  /// Head turn for the side photos, in degrees: enough to show the cheek
  /// and jawline, not so much that the far side disappears.
  static const sideYawMin = 24.0;
  static const sideYawMax = 55.0;

  /// [firstSideYaw] is the yaw of the first side photo; the second must
  /// turn the opposite way. Which way people turn first doesn't matter,
  /// and the camera's sign convention never has to be trusted.
  static LiveHint evaluate(
    LiveFrame f, {
    ScanPose pose = ScanPose.front,
    double? firstSideYaw,
  }) {
    if (f.faceCount == 0) {
      return pose.isSide ? LiveHint.turnSide : LiveHint.noFace;
    }
    if (f.faceCount > 1) return LiveHint.multipleFaces;
    if (f.cutOff) return LiveHint.faceCut;
    if (!pose.isSide && (f.headroom ?? 1) < minHeadroom) {
      return LiveHint.showForehead;
    }

    final face = f.faceLuminance ?? f.luminance;
    if (face < 60) return LiveHint.tooDark;
    // Background much brighter than a dim face: a window or lamp behind.
    if (f.faceLuminance != null && face < 115 && f.luminance - face > 40) {
      return LiveHint.backlit;
    }
    if (face > 210) return LiveHint.tooBright;
    if (pose.isSide) return _side(f, pose, firstSideYaw);
    final balance = f.sideBalance;
    if (balance != null && balance > 0) {
      if (math.max(balance, 1 / balance) > 1.5) return LiveHint.unevenLight;
    }

    final w = f.faceWidth;
    if (w != null && w < 0.36) return LiveHint.moveCloser;
    if (w != null && w > 0.72) return LiveHint.moveBack;
    final cx = f.centerX, cy = f.centerY;
    if ((cx != null && (cx - 0.5).abs() > 0.13) ||
        (cy != null && (cy - targetY).abs() > 0.14)) {
      return LiveHint.center;
    }
    if ((f.yaw?.abs() ?? 0) > 12 || (f.roll?.abs() ?? 0) > 10) {
      return LiveHint.lookStraight;
    }
    if ((f.pitch?.abs() ?? 0) > 14) return LiveHint.levelChin;
    if ((f.eyesOpen ?? 1) < 0.35) return LiveHint.openEyes;
    if ((f.motion ?? 0) > 0.025) return LiveHint.holdStill;
    return LiveHint.aligned;
  }

  static LiveHint _side(LiveFrame f, ScanPose pose, double? firstSideYaw) {
    final yaw = f.yaw ?? 0;
    final w = f.faceWidth;
    if (w != null && w < 0.3) return LiveHint.moveCloser;
    if (w != null && w > 0.75) return LiveHint.moveBack;
    final turnedOpposite =
        firstSideYaw == null || yaw.sign != firstSideYaw.sign;
    if (yaw.abs() < sideYawMin || !turnedOpposite) {
      return pose == ScanPose.sideB && firstSideYaw != null
          ? LiveHint.turnOtherSide
          : LiveHint.turnSide;
    }
    if (yaw.abs() > sideYawMax) return LiveHint.turnLess;
    if ((f.roll?.abs() ?? 0) > 14) return LiveHint.levelChin;
    if ((f.motion ?? 0) > 0.025) return LiveHint.holdStill;
    return LiveHint.aligned;
  }

  /// Which checks pass, given the current hint. Checks are ordered, so a
  /// failing light check says nothing yet about position or stillness.
  static Set<LiveCheck> passed(LiveHint hint) {
    final failing = hint.check;
    if (failing == null) return LiveCheck.values.toSet();
    return {
      for (final c in LiveCheck.values)
        if (c.index < failing.index) c,
    };
  }

  /// How long the face must stay aligned before auto-capture.
  static const holdDuration = Duration(milliseconds: 1300);

  /// Maps an upright (displayed) pixel to the camera sensor's buffer, given
  /// the clockwise rotation (0/90/180/270) that turns the sensor image
  /// upright. [w] and [h] are the sensor buffer's width and height.
  static (int, int) uprightToSensor(
    double ux,
    double uy,
    int w,
    int h,
    int rotation,
  ) {
    final (sx, sy) = switch (rotation) {
      90 => (uy, h - 1 - ux),
      180 => (w - 1 - ux, h - 1 - uy),
      270 => (w - 1 - uy, ux),
      _ => (ux, uy),
    };
    return (sx.round().clamp(0, w - 1), sy.round().clamp(0, h - 1));
  }
}
