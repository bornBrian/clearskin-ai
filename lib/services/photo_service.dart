import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset, Rect;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/scan/capture_quality.dart';
import '../domain/scan/face_zones.dart';
import '../domain/scan/skin_maps.dart';

class ProcessedPhoto {
  const ProcessedPhoto({
    required this.jpeg,
    required this.width,
    required this.height,
    required this.tempPath,
  });

  final Uint8List jpeg;
  final int width;
  final int height;
  final String tempPath;
}

class CaptureCheck {
  const CaptureCheck({
    required this.photo,
    required this.issues,
    this.facePoints = const [],
    this.geometry,
  });
  final ProcessedPhoto photo;
  final List<CaptureIssue> issues;

  /// Detected face contour points, normalised to 0..1 of the photo. Drives
  /// the face-mesh animation while the analysis runs.
  final List<Offset> facePoints;

  /// Landmarks by contour type, stored with the scan for the face map.
  final FaceGeometry? geometry;

  /// A photo that can't be read reliably isn't analysed: only lighting the
  /// person may not be able to change can be knowingly accepted.
  bool get blocking => issues.any((i) => !i.acceptable);
}

/// Normalises captured photos and checks capture quality on-device before
/// anything is uploaded.
class PhotoService {
  PhotoService();

  FaceDetector? _detector;
  FaceDetector get _faces => _detector ??= FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableContours: true,
      enableClassification: true,
      minFaceSize: 0.15,
    ),
  );

  /// Long edge in pixels. Enough detail for skin texture while keeping the
  /// upload ~250 KB and AI image-token cost predictable.
  static const maxEdge = 1280;

  Future<CaptureCheck> process(String sourcePath, {bool mirror = false}) async {
    final bytes = await File(sourcePath).readAsBytes();
    final out = await compute(_normalize, _NormalizeArgs(bytes, mirror));
    if (out == null) {
      throw const FormatException('Unsupported image');
    }
    final tmp = await getTemporaryDirectory();
    final tempPath = p.join(
      tmp.path,
      'capture_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await File(tempPath).writeAsBytes(out.jpeg, flush: true);
    final photo = ProcessedPhoto(
      jpeg: out.jpeg,
      width: out.width,
      height: out.height,
      tempPath: tempPath,
    );

    List<Face> faces = const [];
    try {
      faces = await _faces.processImage(InputImage.fromFilePath(tempPath));
    } catch (e) {
      debugPrint('Face detection failed: $e');
    }

    final face = faces.isEmpty
        ? null
        : (faces.toList()..sort(
                (a, b) => (b.boundingBox.width * b.boundingBox.height)
                    .compareTo(a.boundingBox.width * a.boundingBox.height),
              ))
              .first;

    // Ignore tiny background faces (posters, people behind).
    final significant = faces
        .where(
          (f) =>
              face == null ||
              f.boundingBox.width > face.boundingBox.width * 0.45,
        )
        .length;

    final stats = await compute(
      _measure,
      _MeasureArgs(out.jpeg, face?.boundingBox),
    );

    final m = CaptureMeasurements(
      faceCount: significant,
      meanLuminance: stats.mean,
      shadowClipFraction: stats.shadowClip,
      highlightClipFraction: stats.highlightClip,
      sideBalance: stats.sideBalance,
      sharpness: stats.sharpness,
      faceWidthFraction: face == null
          ? null
          : face.boundingBox.width / out.width,
      faceCenterOffset: face == null
          ? null
          : (face.boundingBox.center.dx - out.width / 2).abs() / out.width,
      headYaw: face?.headEulerAngleY,
      headRoll: face?.headEulerAngleZ,
      headPitch: face?.headEulerAngleX,
      cutOff:
          face != null &&
          (face.boundingBox.left < out.width * 0.01 ||
              face.boundingBox.top < out.height * 0.005 ||
              face.boundingBox.right > out.width * 0.99 ||
              face.boundingBox.bottom > out.height * 0.995),
      eyesOpen: switch ((
        face?.leftEyeOpenProbability,
        face?.rightEyeOpenProbability,
      )) {
        (final double l, final double r) => math.min(l, r),
        _ => null,
      },
      skinHue: face == null ? null : stats.skinHue,
      skinChroma: face == null ? null : stats.skinChroma,
    );

    final points = <Offset>[
      if (face != null)
        for (final contour in face.contours.values)
          if (contour != null)
            for (final pt in contour.points)
              Offset(pt.x / out.width, pt.y / out.height),
    ];

    final geometry = FaceGeometry(
      aspect: out.width / out.height,
      contours: {
        if (face != null)
          for (final entry in face.contours.entries)
            if (entry.value != null && entry.value!.points.isNotEmpty)
              entry.key.name: [
                for (final pt in entry.value!.points)
                  Offset(pt.x / out.width, pt.y / out.height),
              ],
      },
    );

    return CaptureCheck(
      photo: photo,
      issues: CaptureQuality.evaluate(m),
      facePoints: points,
      geometry: geometry,
    );
  }

  /// Moves an analysed photo into app-private permanent storage.
  Future<String> persist(ProcessedPhoto photo, String scanId) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'scans'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final path = p.join(dir.path, '$scanId.jpg');
    await File(path).writeAsBytes(photo.jpeg, flush: true);
    _deleteQuietly(photo.tempPath);
    return path;
  }

  void discard(ProcessedPhoto photo) => _deleteQuietly(photo.tempPath);

  Future<void> deleteAllPhotos() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'scans'));
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  void _deleteQuietly(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<void> dispose() async => _detector?.close();
}

// ── Isolate workers ──────────────────────────────────────────────────────

class _NormalizeArgs {
  const _NormalizeArgs(this.bytes, this.mirror);
  final Uint8List bytes;
  final bool mirror;
}

class _NormalizeResult {
  const _NormalizeResult(this.jpeg, this.width, this.height);
  final Uint8List jpeg;
  final int width;
  final int height;
}

_NormalizeResult? _normalize(_NormalizeArgs a) {
  var image = img.decodeImage(a.bytes);
  if (image == null) return null;
  image = img.bakeOrientation(image);
  if (a.mirror) image = img.flipHorizontal(image);
  final longEdge = math.max(image.width, image.height);
  if (longEdge > PhotoService.maxEdge) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: PhotoService.maxEdge,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: PhotoService.maxEdge,
            interpolation: img.Interpolation.average,
          );
  }
  // Strip EXIF (location, device) — privacy by default.
  image.exif = img.ExifData();
  final jpeg = img.encodeJpg(image, quality: 88);
  return _NormalizeResult(jpeg, image.width, image.height);
}

class _MeasureArgs {
  const _MeasureArgs(this.jpeg, this.face);
  final Uint8List jpeg;
  final Rect? face;
}

class _Stats {
  const _Stats(
    this.mean,
    this.shadowClip,
    this.highlightClip,
    this.sideBalance,
    this.sharpness,
    this.skinHue,
    this.skinChroma,
  );
  final double mean;
  final double shadowClip;
  final double highlightClip;
  final double sideBalance;
  final double sharpness;
  final double skinHue;
  final double skinChroma;
}

_Stats _measure(_MeasureArgs a) {
  final image = img.decodeJpg(a.jpeg)!;
  // Region of interest: the face box, or the centre third if no face.
  final r =
      a.face ??
      Rect.fromLTWH(
        image.width / 3,
        image.height / 3,
        image.width / 3,
        image.height / 3,
      );
  final x0 = r.left.clamp(0, image.width - 1).toInt();
  final y0 = r.top.clamp(0, image.height - 1).toInt();
  final x1 = r.right.clamp(1, image.width).toInt();
  final y1 = r.bottom.clamp(1, image.height).toInt();
  final midX = (x0 + x1) ~/ 2;

  // Colour from the middle of the face (cheeks, nose), clear of hair, brows
  // and background, for the colour-cast check.
  final cx0 = x0 + (x1 - x0) ~/ 4, cx1 = x1 - (x1 - x0) ~/ 4;
  final cy0 = y0 + (y1 - y0) * 2 ~/ 5, cy1 = y1 - (y1 - y0) ~/ 5;
  var sr = 0.0, sg = 0.0, sb = 0.0;
  var cn = 0;
  var sum = 0.0, left = 0.0, right = 0.0;
  var n = 0, nl = 0, nr = 0, dark = 0, bright = 0;
  const step = 2;
  for (var y = y0; y < y1; y += step) {
    for (var x = x0; x < x1; x += step) {
      final px = image.getPixel(x, y);
      final l = 0.299 * px.r + 0.587 * px.g + 0.114 * px.b;
      sum += l;
      n++;
      if (l < 25) dark++;
      if (l > 245) bright++;
      if (x >= cx0 && x < cx1 && y >= cy0 && y < cy1) {
        sr += px.r;
        sg += px.g;
        sb += px.b;
        cn++;
      }
      if (x < midX) {
        left += l;
        nl++;
      } else {
        right += l;
        nr++;
      }
    }
  }
  final mean = n == 0 ? 0.0 : sum / n;
  final lMean = nl == 0 ? 1.0 : left / nl;
  final rMean = nr == 0 ? 1.0 : right / nr;

  // Sharpness: variance of a 4-neighbour Laplacian on a downscaled face crop.
  final crop = img.copyResize(
    img.copyCrop(
      image,
      x: x0,
      y: y0,
      width: math.max(1, x1 - x0),
      height: math.max(1, y1 - y0),
    ),
    width: 256,
  );
  final gray = img.grayscale(crop);
  var lapSum = 0.0, lapSq = 0.0;
  var ln = 0;
  for (var y = 1; y < gray.height - 1; y++) {
    for (var x = 1; x < gray.width - 1; x++) {
      final c = gray.getPixel(x, y).r.toDouble();
      final lap =
          4 * c -
          gray.getPixel(x - 1, y).r -
          gray.getPixel(x + 1, y).r -
          gray.getPixel(x, y - 1).r -
          gray.getPixel(x, y + 1).r;
      lapSum += lap;
      lapSq += lap * lap;
      ln++;
    }
  }
  final lapMean = ln == 0 ? 0 : lapSum / ln;
  final variance = ln == 0 ? 0.0 : lapSq / ln - lapMean * lapMean;

  final (_, la, lb) = cn == 0
      ? (0.0, 1.0, 1.0)
      : SkinMaps.labOf((sr / cn).round(), (sg / cn).round(), (sb / cn).round());
  final hue = math.atan2(lb, la) * 180 / math.pi;

  return _Stats(
    mean,
    n == 0 ? 0 : dark / n,
    n == 0 ? 0 : bright / n,
    rMean == 0 ? 1 : lMean / math.max(rMean, 1),
    variance,
    hue < 0 ? hue + 360 : hue,
    math.sqrt(la * la + lb * lb),
  );
}
