import 'skin_maps.dart';

/// The numbers worth keeping from a photo's on-device measurement: how
/// much of the skin each lens picked up, overall and per face zone. A few
/// hundred bytes per scan, so progress can be proven later without
/// re-measuring every photo.
class SkinMeasure {
  const SkinMeasure({
    required this.coverage,
    required this.zones,
    required this.skinLightness,
  });

  /// Fraction (0..1) of skin each lens flagged.
  final Map<SkinLens, double> coverage;

  /// Per lens, per face zone, the fraction of that zone flagged.
  final Map<SkinLens, Map<String, double>> zones;
  final double skinLightness;

  factory SkinMeasure.of(SkinMaps m) => SkinMeasure(
    coverage: {for (final e in m.readings.entries) e.key: e.value.coverage},
    zones: {
      for (final e in m.readings.entries)
        e.key: {for (final z in e.value.zones) z.area: z.share},
    },
    skinLightness: m.skinLightness,
  );

  Map<String, Object?> toJson() => {
    'l': double.parse(skinLightness.toStringAsFixed(1)),
    'c': {
      for (final e in coverage.entries)
        e.key.name: double.parse(e.value.toStringAsFixed(4)),
    },
    'z': {
      for (final e in zones.entries)
        e.key.name: {
          for (final z in e.value.entries)
            z.key: double.parse(z.value.toStringAsFixed(4)),
        },
    },
  };

  static SkinMeasure? fromJson(Object? j) {
    if (j is! Map) return null;
    final lenses = SkinLens.values.asNameMap();
    final c = j['c'], z = j['z'];
    if (c is! Map) return null;
    return SkinMeasure(
      skinLightness: (j['l'] as num?)?.toDouble() ?? 0,
      coverage: {
        for (final e in c.entries)
          if (lenses[e.key] != null && e.value is num)
            lenses[e.key]!: (e.value as num).toDouble(),
      },
      zones: {
        if (z is Map)
          for (final e in z.entries)
            if (lenses[e.key] != null && e.value is Map)
              lenses[e.key]!: {
                for (final s in (e.value as Map).entries)
                  if (s.value is num) '${s.key}': (s.value as num).toDouble(),
              },
      },
    );
  }
}

/// One measured change between two photos.
class MeasuredChange {
  const MeasuredChange({
    required this.lens,
    required this.before,
    required this.after,
    this.zone,
    this.zoneChange,
  });

  final SkinLens lens;

  /// Share of skin flagged, 0..1.
  final double before;
  final double after;

  /// The zone where it changed most, and by how much (relative, −1..+∞).
  final String? zone;
  final double? zoneChange;

  /// Relative change in flagged area: −0.31 = 31% less.
  double get change => (after - before) / before;
  bool get improved => change < 0;
}

/// Progress you can see in the pixels, not just in an AI score: how much
/// less of the skin reads as red, marked, shiny or rough than on day one.
class ProgressProof {
  const ProgressProof({
    required this.changes,
    required this.days,
    required this.lightingDiffers,
  });

  /// Biggest improvements first, then anything that got worse.
  final List<MeasuredChange> changes;
  final int days;

  /// The two photos were lit very differently, so changes may partly be
  /// the light. Shown, never hidden.
  final bool lightingDiffers;

  List<MeasuredChange> get improvements =>
      changes.where((c) => c.improved).toList();

  /// Lenses where less is better. Radiance has its own score.
  static const _lenses = [
    SkinLens.redness,
    SkinLens.tone,
    SkinLens.shine,
    SkinLens.texture,
  ];

  /// Below this share a lens barely registered on day one, so a percentage
  /// change would be noise dressed up as progress.
  static const _minBefore = 0.02;

  /// Changes smaller than this (relative) are within photo-to-photo noise.
  static const _minChange = 0.1;

  /// L* units of lighting difference treated as "different light".
  static const _lightingTolerance = 8.0;

  static ProgressProof? compare(
    SkinMeasure first,
    SkinMeasure latest, {
    required int days,
  }) {
    final changes = <MeasuredChange>[];
    for (final lens in _lenses) {
      final before = first.coverage[lens];
      final after = latest.coverage[lens];
      if (before == null || after == null || before < _minBefore) continue;
      if (((after - before) / before).abs() < _minChange) continue;

      String? zone;
      double? zoneChange;
      final bz = first.zones[lens] ?? const {};
      final az = latest.zones[lens] ?? const {};
      for (final e in bz.entries) {
        if (e.value < _minBefore * 2) continue;
        final rel = ((az[e.key] ?? 0) - e.value) / e.value;
        final better = before > after;
        if (zoneChange == null ||
            (better ? rel < zoneChange : rel > zoneChange)) {
          zone = e.key;
          zoneChange = rel;
        }
      }
      changes.add(
        MeasuredChange(
          lens: lens,
          before: before,
          after: after,
          zone: zone,
          zoneChange: zoneChange,
        ),
      );
    }
    if (changes.isEmpty) return null;
    changes.sort((a, b) => a.change.compareTo(b.change));
    return ProgressProof(
      changes: changes,
      days: days,
      lightingDiffers:
          first.skinLightness > 0 &&
          latest.skinLightness > 0 &&
          (first.skinLightness - latest.skinLightness).abs() >
              _lightingTolerance,
    );
  }

  /// "Redness" → "Red areas", in words people use.
  static String noun(SkinLens lens) => switch (lens) {
    SkinLens.redness => 'Redness',
    SkinLens.tone => 'Dark marks',
    SkinLens.shine => 'Oily shine',
    SkinLens.texture => 'Rough texture',
    SkinLens.radiance => 'Glow',
  };

  static String zoneName(String area) => switch (area) {
    'under_eyes' => 'under your eyes',
    'upper_lip' => 'your upper lip',
    'jaw' => 'your jawline',
    final a => 'your $a',
  };

  /// "Redness: 31% less than day 1, most on your cheeks."
  static String sentence(MeasuredChange c) {
    final pct = (c.change.abs() * 100).round();
    final dir = c.improved ? 'less' : 'more';
    final where = c.zone == null ? '' : ', most on ${zoneName(c.zone!)}';
    return '${noun(c.lens)}: $pct% $dir than day 1$where.';
  }
}
