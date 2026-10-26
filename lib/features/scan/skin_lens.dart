import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../domain/scan/face_zones.dart';
import '../../domain/scan/skin_maps.dart';

/// Overlay colour per lens: one hue each, never a rainbow heatmap.
const lensColors = <SkinLens, ui.Color>{
  SkinLens.radiance: ui.Color(0xFFFFE2AE),
  SkinLens.redness: ui.Color(0xFFFF7A66),
  SkinLens.tone: ui.Color(0xFFE9A955),
  SkinLens.shine: ui.Color(0xFFFFFBF2),
  SkinLens.texture: ui.Color(0xFFBFE6D6),
};

/// A photo's skin measurements plus a ready-to-draw overlay per lens.
class LensImages {
  const LensImages({required this.maps, required this.overlays});
  final SkinMaps maps;
  final Map<SkinLens, ui.Image> overlays;
}

/// Measures scan photos off the UI thread and keeps the last few results,
/// so reopening a report is instant. Everything stays on the phone.
abstract final class SkinLensStore {
  /// Analysis width: ~0.7 mm of face per pixel on a typical selfie, fine
  /// enough for texture while keeping the work well under a second.
  static const _width = 360;
  static const _keep = 3;

  static final _pending = <String, Future<LensImages?>>{};
  static final _done = <String, LensImages?>{};

  /// The finished result for [path], if it has already been measured.
  static LensImages? peek(String path) => _done[path];

  static Future<LensImages?> load(String path, FaceGeometry geometry) =>
      _pending[path] ??= _load(path, geometry);

  static Future<LensImages?> _load(String path, FaceGeometry g) async {
    try {
      final maps = await Isolate.run(() => _measure(path, g));
      if (maps == null) return _remember(path, null);
      final overlays = <SkinLens, ui.Image>{};
      for (final lens in SkinLens.values) {
        overlays[lens] = await _overlay(maps, lens);
      }
      return _remember(path, LensImages(maps: maps, overlays: overlays));
    } catch (e) {
      debugPrint('Skin lens analysis failed: $e');
      return _remember(path, null);
    }
  }

  static LensImages? _remember(String path, LensImages? v) {
    _done[path] = v;
    while (_done.length > _keep) {
      final oldest = _done.keys.first;
      _done.remove(oldest);
      _pending.remove(oldest);
    }
    return v;
  }

  static SkinMaps? _measure(String path, FaceGeometry g) {
    final decoded = img.decodeImage(File(path).readAsBytesSync());
    if (decoded == null) return null;
    var photo = img.bakeOrientation(decoded);
    if (photo.width > _width) {
      photo = img.copyResize(
        photo,
        width: _width,
        interpolation: img.Interpolation.average,
      );
    }
    final rgba = photo.getBytes(order: img.ChannelOrder.rgba);
    return SkinMaps.analyze(rgba, photo.width, photo.height, g);
  }

  /// Premultiplied RGBA: the lens colour, with alpha from the measurement
  /// eased so faint signal stays faint, and feathered at the skin's edge.
  static Future<ui.Image> _overlay(SkinMaps maps, SkinLens lens) {
    final color = lensColors[lens]!;
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    final v = maps.readings[lens]!.values;
    // Radiance covers most of an even face, so it's a wash of warm light
    // rather than a strong mark.
    final strength = lens == SkinLens.radiance ? 0.5 : 0.9;
    final out = Uint8List(maps.width * maps.height * 4);
    for (var i = 0; i < v.length; i++) {
      final s = v[i];
      if (s <= 0.02) continue;
      final alpha = (s * (2 - s)) * maps.feather[i] * strength;
      out[i * 4] = (r * alpha).round();
      out[i * 4 + 1] = (g * alpha).round();
      out[i * 4 + 2] = (b * alpha).round();
      out[i * 4 + 3] = (255 * alpha).round();
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      out,
      maps.width,
      maps.height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }
}
