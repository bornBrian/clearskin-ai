import 'dart:async';
import 'dart:io';
import 'dart:ui' show Offset, Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../domain/scan/live_guidance.dart';

/// Analyses camera frames on-device (~3/s) and exposes a single live hint
/// plus an auto-capture progress value. Nothing leaves the phone.
class LiveFaceGuide extends ChangeNotifier {
  LiveFaceGuide({
    required this.controller,
    required this.description,
    required this.onReady,
  });

  final CameraController controller;
  final CameraDescription description;

  /// Called once when the face has been held aligned long enough.
  final VoidCallback onReady;

  final _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      // Eye-open probabilities: closed eyes hide the under-eye area.
      enableClassification: true,
      minFaceSize: 0.2,
    ),
  );

  LiveHint hint = LiveHint.noFace;

  /// Which photo is being taken. Changing it restarts the hold timer.
  ScanPose get pose => _pose;
  ScanPose _pose = ScanPose.front;
  set pose(ScanPose p) {
    _pose = p;
    _alignedSince = null;
    progress = 0;
    hint = p.isSide ? LiveHint.turnSide : LiveHint.noFace;
    notifyListeners();
  }

  /// Head yaw of the first side photo, so the second turns the other way.
  double? firstSideYaw;

  /// Yaw of the latest analysed frame.
  double? lastYaw;

  /// 0..1 progress towards auto-capture.
  double progress = 0;

  bool _streaming = false;
  bool _busy = false;
  bool _fired = false;
  bool _disposed = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _alignedSince;
  Offset? _lastCenter;

  static const _interval = Duration(milliseconds: 300);

  bool get active => _streaming;

  Future<void> start() async {
    if (_streaming || _disposed || !controller.value.isInitialized) return;
    _fired = false;
    _alignedSince = null;
    _lastCenter = null;
    progress = 0;
    try {
      await controller.startImageStream(_onFrame);
      _streaming = true;
    } on CameraException catch (e) {
      // Guidance is an enhancement; manual capture still works.
      debugPrint('Live guide unavailable: ${e.code}');
    }
  }

  Future<void> stop() async {
    if (!_streaming) return;
    _streaming = false;
    try {
      await controller.stopImageStream();
    } on CameraException {
      // Already stopped (e.g. controller disposed).
    }
  }

  void _onFrame(CameraImage image) {
    final now = DateTime.now();
    if (_busy || _fired || now.difference(_lastFrame) < _interval) return;
    _lastFrame = now;
    _busy = true;
    unawaited(_process(image).whenComplete(() => _busy = false));
  }

  Future<void> _process(CameraImage image) async {
    final input = _toInputImage(image);
    if (input == null) return;
    List<Face> faces;
    try {
      faces = await _detector.processImage(input);
    } catch (_) {
      return;
    }
    if (_disposed || _fired) return;

    final rotated =
        description.sensorOrientation == 90 ||
        description.sensorOrientation == 270;
    final upright = rotated
        ? Size(image.height.toDouble(), image.width.toDouble())
        : Size(image.width.toDouble(), image.height.toDouble());

    final face = faces.isEmpty
        ? null
        : faces.reduce(
            (a, b) => a.boundingBox.width >= b.boundingBox.width ? a : b,
          );
    final significant = face == null
        ? 0
        : faces
              .where((f) => f.boundingBox.width > face.boundingBox.width * 0.45)
              .length;

    final box = face?.boundingBox;
    final center = box == null
        ? null
        : Offset(box.center.dx / upright.width, box.center.dy / upright.height);
    final motion = center == null || _lastCenter == null
        ? null
        : (center - _lastCenter!).distance;
    _lastCenter = center;
    final light = box == null ? null : _faceLight(image, box, upright);
    final leftEye = face?.leftEyeOpenProbability;
    final rightEye = face?.rightEyeOpenProbability;

    final frame = LiveFrame(
      faceCount: significant,
      luminance: _luminance(image),
      faceLuminance: light?.$1,
      sideBalance: light?.$2,
      faceWidth: box == null ? null : box.width / upright.width,
      centerX: center?.dx,
      centerY: center?.dy,
      yaw: face?.headEulerAngleY,
      roll: face?.headEulerAngleZ,
      pitch: face?.headEulerAngleX,
      cutOff:
          box != null &&
          (box.left < upright.width * 0.01 ||
              box.top < upright.height * 0.005 ||
              box.right > upright.width * 0.99 ||
              box.bottom > upright.height * 0.995),
      headroom: box == null || box.height <= 0 ? null : box.top / box.height,
      eyesOpen: leftEye == null || rightEye == null
          ? null
          : (leftEye < rightEye ? leftEye : rightEye),
      motion: motion,
    );

    lastYaw = face?.headEulerAngleY;
    hint = LiveGuidance.evaluate(
      frame,
      pose: _pose,
      firstSideYaw: firstSideYaw,
    );
    final now = DateTime.now();
    if (hint.ready) {
      _alignedSince ??= now;
      final held = now.difference(_alignedSince!);
      progress =
          (held.inMilliseconds / LiveGuidance.holdDuration.inMilliseconds)
              .clamp(0.0, 1.0);
      if (progress >= 1 && !_fired) {
        _fired = true;
        notifyListeners();
        onReady();
        return;
      }
    } else {
      _alignedSince = null;
      progress = 0;
    }
    notifyListeners();
  }

  InputImage? _toInputImage(CameraImage image) {
    final rotation = InputImageRotationValue.fromRawValue(
      description.sensorOrientation,
    );
    final format = InputImageFormatValue.fromRawValue(image.format.raw as int);
    if (rotation == null || format == null) return null;
    // NV21 on Android and BGRA on iOS arrive as a single plane.
    if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
    if (Platform.isIOS && format != InputImageFormat.bgra8888) return null;
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Mean luma over the face box (inset to skip hair and background at its
  /// edges) and the ratio of its left half to its right half, sampled on a
  /// 24×24 grid straight from the sensor buffer.
  (double, double)? _faceLight(CameraImage image, Rect box, Size upright) {
    final bytes = image.planes.first.bytes;
    final stride = image.planes.first.bytesPerRow;
    if (bytes.isEmpty) return null;
    final inner = box.deflate(box.width * 0.15);
    var left = 0.0, right = 0.0;
    var nl = 0, nr = 0;
    const grid = 24;
    for (var gy = 0; gy < grid; gy++) {
      for (var gx = 0; gx < grid; gx++) {
        final ux = (inner.left + inner.width * (gx + 0.5) / grid).clamp(
          0.0,
          upright.width - 1,
        );
        final uy = (inner.top + inner.height * (gy + 0.5) / grid).clamp(
          0.0,
          upright.height - 1,
        );
        final (sx, sy) = LiveGuidance.uprightToSensor(
          ux,
          uy,
          image.width,
          image.height,
          description.sensorOrientation,
        );
        final double luma;
        if (Platform.isIOS) {
          final i = sy * stride + sx * 4;
          if (i + 2 >= bytes.length) continue;
          luma = 0.114 * bytes[i] + 0.587 * bytes[i + 1] + 0.299 * bytes[i + 2];
        } else {
          final i = sy * stride + sx;
          if (i >= bytes.length) continue;
          luma = bytes[i].toDouble();
        }
        if (gx < grid / 2) {
          left += luma;
          nl++;
        } else {
          right += luma;
          nr++;
        }
      }
    }
    if (nl == 0 || nr == 0) return null;
    final l = left / nl, r = right / nr;
    return ((left + right) / (nl + nr), r < 1 ? 1.0 : l / r);
  }

  /// Fast, sparse mean brightness of the frame.
  double _luminance(CameraImage image) {
    final bytes = image.planes.first.bytes;
    if (bytes.isEmpty) return 128;
    var sum = 0.0;
    var n = 0;
    if (Platform.isIOS) {
      // BGRA: 4 bytes per pixel.
      for (var i = 0; i + 2 < bytes.length; i += 4 * 97) {
        sum += 0.114 * bytes[i] + 0.587 * bytes[i + 1] + 0.299 * bytes[i + 2];
        n++;
      }
    } else {
      // NV21: the first width*height bytes are the Y (luma) plane.
      final yLen = image.width * image.height;
      for (var i = 0; i < yLen && i < bytes.length; i += 97) {
        sum += bytes[i];
        n++;
      }
    }
    return n == 0 ? 128 : sum / n;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    unawaited(_detector.close());
    super.dispose();
  }
}
