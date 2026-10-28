import 'dart:math' as math;

/// Inputs measured from a captured photo (luminance from pixels, face
/// geometry from on-device face detection). Pure data so the rules are
/// unit-testable without a camera.
class CaptureMeasurements {
  const CaptureMeasurements({
    required this.faceCount,
    required this.meanLuminance,
    required this.shadowClipFraction,
    required this.highlightClipFraction,
    required this.sideBalance,
    this.faceWidthFraction,
    this.faceCenterOffset,
    this.headYaw,
    this.headRoll,
    this.headPitch,
    this.sharpness,
    this.cutOff = false,
    this.headroom,
    this.eyesOpen,
    this.skinHue,
    this.skinChroma,
  });

  final int faceCount;

  /// 0..255 average over the face region (or whole image if no face).
  final double meanLuminance;
  final double shadowClipFraction;
  final double highlightClipFraction;

  /// Ratio of mean luminance left half / right half of the face. ~1 = even.
  final double sideBalance;

  /// Face bounding-box width as a fraction of image width.
  final double? faceWidthFraction;

  /// Distance of face centre from image centre, as a fraction of width.
  final double? faceCenterOffset;
  final double? headYaw;
  final double? headRoll;
  final double? headPitch;

  /// Variance of a Laplacian-like filter; low = blurry.
  final double? sharpness;

  /// The face box runs past an edge of the photo.
  final bool cutOff;

  /// Space above ML Kit's face box as a fraction of its height (the box
  /// starts mid-forehead, so this decides whether the hairline is in).
  final double? headroom;

  /// The less-open eye's open probability, 0..1.
  final double? eyesOpen;

  /// CIELAB hue angle (degrees) of the face's mean colour. Skin of every
  /// tone sits in a narrow band of hue in neutral light; far outside it,
  /// the light itself is tinting the skin.
  final double? skinHue;

  /// CIELAB chroma of the face's mean colour. Warm bulbs keep skin's hue
  /// but push its chroma far past what skin has in daylight.
  final double? skinChroma;
}

enum CaptureIssue {
  noFace('We couldn\'t find a face. Face the camera straight on.'),
  multipleFaces('Make sure only your face is in the frame.'),
  tooDark('Too dark. Face a window or a bright light.'),
  tooBright('Too bright. Avoid direct sun or a flash on your face.'),
  unevenLight('Light is coming from one side. Face the light source directly.'),
  faceCut('Part of your face is out of the photo. Bring it all into the oval.'),
  foreheadCut(
    'The top of your forehead is cut off. Hold the phone a little further away so your hairline is in the photo.',
  ),
  eyesClosed('Your eyes were closed. Keep them open and look at the camera.'),
  colourCast(
    'The light is tinting your skin. Daylight from a window reads truest.',
  ),
  tooFar('Move a little closer so your face fills the oval.'),
  tooClose('Move back slightly so your whole face fits.'),
  offCenter('Center your face in the oval.'),
  tilted('Keep your head straight and look directly at the camera.'),
  blurry('Photo is blurry. Hold still for a moment.');

  const CaptureIssue(this.message);
  final String message;

  /// Issues the person may knowingly accept (their light can be hard to
  /// change). Everything else means the photo can't be read reliably.
  bool get acceptable =>
      this == unevenLight ||
      this == colourCast ||
      this == tooBright ||
      // A gallery photo may simply be cropped that way.
      this == foreheadCut;
}

/// Consistent capture is what makes progress tracking meaningful. Every scan
/// passes these checks before it is analysed or stored.
abstract final class CaptureQuality {
  static List<CaptureIssue> evaluate(CaptureMeasurements m) {
    final issues = <CaptureIssue>[];
    if (m.faceCount == 0) return [CaptureIssue.noFace];
    if (m.faceCount > 1) issues.add(CaptureIssue.multipleFaces);

    if (m.meanLuminance < 70 || m.shadowClipFraction > 0.25) {
      issues.add(CaptureIssue.tooDark);
    } else if (m.meanLuminance > 215 || m.highlightClipFraction > 0.12) {
      issues.add(CaptureIssue.tooBright);
    }

    final balance = m.sideBalance <= 0 ? 1.0 : m.sideBalance;
    final imbalance = math.max(balance, 1 / balance);
    if (imbalance > 1.45) issues.add(CaptureIssue.unevenLight);

    // Hue means little when colour is very muted (deep shadow, low light),
    // so it is only judged once there's colour to judge.
    final hue = m.skinHue, chroma = m.skinChroma;
    if ((chroma != null && chroma > 46) ||
        (hue != null && (chroma ?? 8) >= 8 && (hue < 25 || hue > 85))) {
      issues.add(CaptureIssue.colourCast);
    }

    if (m.cutOff) {
      issues.add(CaptureIssue.faceCut);
    } else if ((m.headroom ?? 1) < 0.22) {
      issues.add(CaptureIssue.foreheadCut);
    }
    final w = m.faceWidthFraction;
    if (w != null) {
      if (w < 0.32) issues.add(CaptureIssue.tooFar);
      if (w > 0.85) issues.add(CaptureIssue.tooClose);
    }
    final off = m.faceCenterOffset;
    if (off != null && off > 0.18) issues.add(CaptureIssue.offCenter);

    bool beyond(double? v, double limit) => v != null && v.abs() > limit;
    if (beyond(m.headYaw, 15) ||
        beyond(m.headRoll, 12) ||
        beyond(m.headPitch, 15)) {
      issues.add(CaptureIssue.tilted);
    }

    if ((m.eyesOpen ?? 1) < 0.3) issues.add(CaptureIssue.eyesClosed);

    final s = m.sharpness;
    if (s != null && s < 35) issues.add(CaptureIssue.blurry);

    return issues;
  }
}
