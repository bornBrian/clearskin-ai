import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/scan.dart';
import '../../domain/scan/face_mesh.dart';
import '../../domain/scan/face_zones.dart';
import '../../domain/scan/skin_maps.dart';
import 'skin_lens.dart';

const _moderate = Color(0xFFF0B85F);
const _marked = Color(0xFFF08A76);
const _mild = Color(0xFFF7EBD3);

Color _severityColor(int s) => switch (s) {
  3 => _marked,
  2 => _moderate,
  _ => _mild,
};

String _severityWord(int s) => switch (s) {
  3 => 'Marked',
  2 => 'Moderate',
  _ => 'Mild',
};

String _areaLabel(String a) => switch (a) {
  'under_eyes' => 'Under-eyes',
  'upper_lip' => 'Upper lip',
  'overall' => 'Overall',
  _ => a[0].toUpperCase() + a.substring(1),
};

/// One plain word for how much of the skin a lens picked up.
String _levelWord(double coverage) => coverage < 0.02
    ? 'Low'
    : coverage < 0.08
    ? 'Some'
    : coverage < 0.2
    ? 'Noticeable'
    : 'Marked';

String _percent(double share) =>
    share < 0.01 ? 'Under 1%' : '${(share * 100).round()}%';

/// The user's own scan photo, tracked like an AR lens: the facial landmarks
/// detected at capture drawn as a fine mesh, each finding named on the face,
/// and four measurement lenses (redness, tone, shine, texture) painted onto
/// the skin from the photo's real pixels.
///
/// No photo, no face: a drawn stand-in would misrepresent the analysis.
class FaceMap extends StatefulWidget {
  const FaceMap({
    super.key,
    required this.scan,
    this.initialLens,
    this.previousRadiance,
    this.onRadiance,
  });
  final SkinScan scan;

  /// Lens shown first; null shows the findings.
  final SkinLens? initialLens;

  /// The last scan's radiance, for the change shown on the readout.
  final Radiance? previousRadiance;

  /// Called once the photo has been measured, so the reading can be kept.
  final ValueChanged<Radiance>? onRadiance;

  @override
  State<FaceMap> createState() => _FaceMapState();
}

class _FaceMapState extends State<FaceMap> with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..forward();
  late final FaceMesh _mesh = FaceMesh.fromGeometry(widget.scan.face);
  late SkinLens? _lens = widget.initialLens;
  LensImages? _lenses;
  int? _focus;

  bool get _canMeasure => !_mesh.isEmpty;

  @override
  void initState() {
    super.initState();
    final g = widget.scan.face;
    final nothingToPin = widget.scan.analysis.findings.every(
      (f) => f.area == 'overall',
    );
    if (_canMeasure && nothingToPin) _lens ??= SkinLens.redness;
    if (_canMeasure && g != null) {
      _lenses = SkinLensStore.peek(widget.scan.photoPath);
      if (_lenses == null) {
        unawaited(
          SkinLensStore.load(widget.scan.photoPath, g).then((v) {
            if (!mounted) return;
            setState(() => _lenses = v);
            _report(v);
          }),
        );
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _report(_lenses));
      }
    }
  }

  void _report(LensImages? v) {
    if (v != null && mounted) widget.onRadiance?.call(v.maps.radiance);
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  void _select(SkinLens? lens) {
    if (lens == _lens) return;
    setState(() {
      _lens = lens;
      _focus = null;
    });
    _sweep
      ..duration = const Duration(milliseconds: 1100)
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scan = widget.scan;
    final findings = scan.analysis.findings;
    final mapped = findings.where((f) => f.area != 'overall').toList();
    final photo = File(scan.photoPath);
    final hasPhoto =
        photo.existsSync() && (mapped.isNotEmpty || _canMeasure);
    if (!hasPhoto && findings.isEmpty) return const SizedBox.shrink();
    final geometry = scan.face;
    final aspect = geometry?.aspect ?? 0.75;
    final lens = _lens;
    final reading = lens == null ? null : _lenses?.maps.readings[lens];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Eyebrow('Face map'),
            const Spacer(),
            if (hasPhoto)
              Text(
                _mesh.isEmpty
                    ? 'Approximate areas'
                    : '${_mesh.points.length} landmarks · on-device',
                style: context.text.labelSmall,
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        if (hasPhoto)
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.lg),
            child: AspectRatio(
              aspectRatio: aspect,
              child: LayoutBuilder(
                builder: (context, box) {
                  final size = Size(box.maxWidth, box.maxHeight);
                  final callouts = _layoutCallouts(mapped, geometry, size);
                  final overlay = lens == null ? null : _lenses?.overlays[lens];
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(photo, fit: BoxFit.cover),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x59000000),
                              Color(0x1A000000),
                              Color(0xA6000000),
                            ],
                            stops: [0, 0.4, 1],
                          ),
                        ),
                      ),
                      // Dim the photo a touch under a lens so the
                      // measurement reads like light on the skin.
                      AnimatedOpacity(
                        duration: Motion.normal,
                        opacity: lens == null ? 0 : 1,
                        child: const ColoredBox(color: Color(0x33000000)),
                      ),
                      AnimatedBuilder(
                        animation: _sweep,
                        builder: (_, _) {
                          final t = Curves.easeInOutCubic.transform(
                            _sweep.value,
                          );
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              if (overlay != null)
                                CustomPaint(
                                  painter: _LensPainter(
                                    image: overlay,
                                    reveal: _sweepY(size, t),
                                    // Glow is light on the skin, so it
                                    // brightens; findings are marks, so
                                    // they tint.
                                    blend: lens == SkinLens.radiance
                                        ? BlendMode.screen
                                        : BlendMode.srcOver,
                                  ),
                                ),
                              CustomPaint(
                                painter: _MeshPainter(
                                  mesh: _mesh,
                                  geometry: geometry,
                                  progress: t,
                                  sweepY: _sweepY(size, t),
                                  quiet: lens != null,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      if (lens == null) ...[
                        CustomPaint(
                          painter: _CalloutPainter(
                            callouts: callouts,
                            findings: mapped,
                            geometry: geometry,
                            focus: _focus,
                          ),
                        ),
                        for (final co in callouts)
                          Positioned(
                            left: co.left ? Space.md : null,
                            right: co.left ? null : Space.md,
                            top: co.labelTop,
                            width: _labelWidth,
                            child: AnimatedOpacity(
                              duration: Motion.fast,
                              opacity: _focus == null || _focus == co.index
                                  ? 1
                                  : 0.3,
                              child: _CalloutLabel(
                                area: _areaLabel(mapped[co.index].area),
                                title: mapped[co.index].title,
                                alignEnd: !co.left,
                              ),
                            ),
                          ),
                      ],
                      Positioned(
                        left: Space.md + 2,
                        top: Space.md,
                        right: Space.md,
                        child: AnimatedSwitcher(
                          duration: Motion.normal,
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.topLeft,
                            children: [...previous, ?current],
                          ),
                          child: lens == null
                              ? const SizedBox.shrink()
                              : _Readout(
                                  key: ValueKey(lens),
                                  lens: lens,
                                  reading: reading,
                                  radiance: _lenses?.maps.radiance,
                                  previous: widget.previousRadiance,
                                  measuring: _lenses == null,
                                ),
                        ),
                      ),
                      if (_canMeasure)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _LensTabs(
                            selected: lens,
                            onSelect: _select,
                            showFindings: mapped.isNotEmpty,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        const SizedBox(height: Space.sm),
        if (lens == null) ...[
          for (var i = 0; i < findings.length; i++)
            _FindingRow(
              finding: findings[i],
              number: findings[i].area == 'overall'
                  ? null
                  : mapped.indexOf(findings[i]) + 1,
              selected: _focus != null && mapped.indexOf(findings[i]) == _focus,
              last: i == findings.length - 1,
              onTap: findings[i].area == 'overall' || !hasPhoto
                  ? null
                  : () => setState(() {
                      final idx = mapped.indexOf(findings[i]);
                      _focus = _focus == idx ? null : idx;
                    }),
            ),
        ] else
          _LensDetail(
            lens: lens,
            reading: reading,
            radiance: _lenses?.maps.radiance,
          ),
        if (_canMeasure && hasPhoto) ...[
          const SizedBox(height: Space.sm),
          Text(
            'Measured on your phone from this photo\'s colour. Light can shift readings.',
            style: context.text.bodySmall?.copyWith(color: c.inkFaint),
          ),
        ],
      ],
    );
  }

  /// Where the scan line is, in pixels, for animation progress [t].
  double _sweepY(Size size, double t) {
    if (_mesh.isEmpty) return size.height * t;
    final ys = _mesh.points.map((p) => p.dy);
    final top = ys.reduce(math.min) * size.height - 24;
    final bottom = ys.reduce(math.max) * size.height + 24;
    return t >= 1 ? size.height : top + (bottom - top) * t;
  }

  static const _labelWidth = 118.0;

  /// One callout per finding, alternating sides for paired zones and kept
  /// from overlapping on each side.
  List<_Callout> _layoutCallouts(
    List<Finding> mapped,
    FaceGeometry? g,
    Size size,
  ) {
    final out = <_Callout>[];
    for (var i = 0; i < math.min(mapped.length, 4); i++) {
      final centers = FaceZones.centers(mapped[i].area, g);
      if (centers.isEmpty) continue;
      Offset anchor;
      if (centers.length > 1) {
        final sorted = [...centers]..sort((a, b) => a.dx.compareTo(b.dx));
        anchor = i.isEven ? sorted.first : sorted.last;
      } else {
        anchor = centers.first;
      }
      final px = Offset(anchor.dx * size.width, anchor.dy * size.height);
      final title = TextPainter(
        text: TextSpan(text: mapped[i].title, style: _CalloutLabel.titleStyle),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: _labelWidth);
      final height = _CalloutLabel.areaHeight + title.height;
      out.add(
        _Callout(
          index: i,
          anchor: px,
          left: anchor.dx < 0.5,
          labelTop: px.dy - height - 30,
          labelHeight: height,
        ),
      );
    }
    for (final side in [true, false]) {
      final list = out.where((c) => c.left == side).toList()
        ..sort((a, b) => a.labelTop.compareTo(b.labelTop));
      var floor = Space.md;
      for (final c in list) {
        c.labelTop = math.max(c.labelTop, floor);
        c.labelTop = math.min(c.labelTop, size.height - c.labelHeight - 64);
        floor = c.labelTop + c.labelHeight + 22;
      }
    }
    // Text sits on a hairline that runs the label's width, then angles in
    // to the point on the face.
    for (final c in out) {
      final y = c.labelTop + c.labelHeight + 6;
      c.lineEnd = Offset(c.left ? Space.md : size.width - Space.md, y);
      c.elbow = Offset(
        c.left ? Space.md + _labelWidth : size.width - Space.md - _labelWidth,
        y,
      );
    }
    return out;
  }
}

/// Lens names along the bottom of the photo, like a camera's modes.
class _LensTabs extends StatelessWidget {
  const _LensTabs({
    required this.selected,
    required this.onSelect,
    required this.showFindings,
  });

  final SkinLens? selected;
  final ValueChanged<SkinLens?> onSelect;
  final bool showFindings;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, SkinLens? lens) {
      final on = selected == lens;
      return Semantics(
        button: true,
        selected: on,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelect(lens),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 14),
            child: AnimatedDefaultTextStyle(
              duration: Motion.fast,
              style: TextStyle(
                fontFamily: kFontFamily,
                fontSize: 13,
                letterSpacing: 0.2,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: Colors.white.withValues(alpha: on ? 1 : 0.55),
              ),
              child: Text(label),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Space.xs),
      child: Row(
        children: [
          if (showFindings) tab('Findings', null),
          for (final l in SkinLens.values) tab(l.label, l),
        ],
      ),
    );
  }
}

/// Top-left heads-up readout for the active lens. Radiance reads as a
/// score with its change; the others as how much of the skin they found.
class _Readout extends StatelessWidget {
  const _Readout({
    super.key,
    required this.lens,
    required this.reading,
    required this.radiance,
    required this.previous,
    required this.measuring,
  });

  final SkinLens lens;
  final LensReading? reading;
  final Radiance? radiance;
  final Radiance? previous;
  final bool measuring;

  static const _shadow = [Shadow(color: Color(0x66000000), blurRadius: 8)];

  @override
  Widget build(BuildContext context) {
    final r = reading;
    final glow = lens == SkinLens.radiance ? radiance : null;
    final String big;
    final String? small;
    if (r == null) {
      big = measuring ? 'Measuring' : '—';
      small = null;
    } else if (glow != null) {
      big = '${glow.score}';
      final d = previous == null ? null : glow.score - previous!.score;
      small = d == null || d == 0
          ? 'out of 100'
          : '${d > 0 ? '+' : '−'}${d.abs()} since last scan';
    } else {
      big = _levelWord(r.coverage);
      small = '${_percent(r.coverage)} of your skin';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lens.label.toUpperCase(),
          style: const TextStyle(
            fontFamily: kFontFamily,
            fontSize: 10,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
            color: Color(0xCCFFFFFF),
            shadows: _shadow,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          big,
          style: TextStyle(
            fontFamily: kFontFamily,
            fontSize: glow != null ? 46 : 34,
            height: 1.1,
            letterSpacing: -0.8,
            fontWeight: FontWeight.w200,
            color: Colors.white,
            shadows: _shadow,
          ),
        ),
        if (small != null)
          Text(
            small,
            style: const TextStyle(
              fontFamily: kFontFamily,
              fontSize: 12,
              color: Color(0xD9FFFFFF),
              shadows: _shadow,
            ),
          ),
      ],
    );
  }
}

/// Under the photo while a lens is on: what it measures, then where — or,
/// for radiance, its three parts and the one thing that would lift it most.
class _LensDetail extends StatelessWidget {
  const _LensDetail({
    required this.lens,
    required this.reading,
    required this.radiance,
  });
  final SkinLens lens;
  final LensReading? reading;
  final Radiance? radiance;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final glow = radiance;
    if (lens == SkinLens.radiance) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Space.xs),
          Text(lens.explainer, style: context.text.bodyMedium),
          if (glow != null) ...[
            const SizedBox(height: Space.md),
            _RadianceParts(radiance: glow),
            const SizedBox(height: Space.md),
            Text(
              _glowTip(glow),
              style: context.text.titleMedium?.copyWith(
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      );
    }
    final zones = reading?.zones.take(3).toList() ?? const <ZoneShare>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.xs),
        Text(lens.explainer, style: context.text.bodyMedium),
        const SizedBox(height: Space.xs),
        if (reading != null && zones.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              'Nothing stands out.',
              style: context.text.titleSmall,
            ),
          ),
        for (var i = 0; i < zones.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: i == zones.length - 1
                  ? null
                  : Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _areaLabel(zones[i].area),
                    style: context.text.titleSmall,
                  ),
                ),
                Text(
                  _percent(zones[i].share),
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w300,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The one change that would lift radiance most: aimed at its weakest part.
String _glowTip(Radiance r) {
  final weakest = [
    (r.evenness, 'evenness'),
    (r.clarity, 'clarity'),
    (r.sheen, 'sheen'),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return switch (weakest.first.$2) {
    'clarity' => 'Calm active spots first. They cost the most glow.',
    'sheen' => 'For more glow: a hydrating serum under a light moisturiser.',
    _ => 'To even it out: daily SPF, with vitamin C or niacinamide.',
  };
}

/// Evenness, clarity and sheen as three numbers between hairlines.
class _RadianceParts extends StatelessWidget {
  const _RadianceParts({required this.radiance});
  final Radiance radiance;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget part(String label, int v, bool first) => Expanded(
      child: Padding(
        padding: EdgeInsets.fromLTRB(first ? 0 : Space.md, 14, 0, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: context.text.labelMedium?.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: 6),
            Text(
              '$v',
              style: TextStyle(
                fontFamily: kFontFamily,
                fontSize: 34,
                height: 1,
                letterSpacing: -0.8,
                fontWeight: FontWeight.w200,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
    final rule = VerticalDivider(width: 1, thickness: 1, color: c.line);
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: c.line)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            part('Evenness', radiance.evenness, true),
            rule,
            part('Clarity', radiance.clarity, false),
            rule,
            part('Sheen', radiance.sheen, false),
          ],
        ),
      ),
    );
  }
}

class _Callout {
  _Callout({
    required this.index,
    required this.anchor,
    required this.left,
    required this.labelTop,
    required this.labelHeight,
  });

  final int index;
  final Offset anchor;
  final bool left;
  final double labelHeight;
  double labelTop;
  Offset lineEnd = Offset.zero;
  Offset elbow = Offset.zero;
}

class _CalloutLabel extends StatelessWidget {
  const _CalloutLabel({
    required this.area,
    required this.title,
    required this.alignEnd,
  });

  final String area;
  final String title;
  final bool alignEnd;

  static const areaHeight = 16.0;
  static const titleStyle = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 12.5,
    height: 1.25,
    fontWeight: FontWeight.w500,
    color: Colors.white,
    shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
  );

  @override
  Widget build(BuildContext context) {
    final align = alignEnd ? TextAlign.right : TextAlign.left;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          area.toUpperCase(),
          textAlign: align,
          style: const TextStyle(
            height: 1.2,
            fontFamily: kFontFamily,
            fontSize: 9.5,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w600,
            color: Color(0xCCFFFFFF),
          ),
        ),
        SizedBox(height: areaHeight - 12),
        Text(
          title,
          textAlign: align,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
      ],
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({
    required this.finding,
    required this.number,
    required this.selected,
    required this.last,
    this.onTap,
  });

  final Finding finding;
  final int? number;
  final bool selected;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 36,
              child: Text(
                number == null ? '—' : number.toString().padLeft(2, '0'),
                style: context.text.titleMedium?.copyWith(
                  color: selected ? c.ink : c.inkFaint,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w300,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(finding.title, style: context.text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    '${_areaLabel(finding.area)} · ${finding.detail}',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            Text(
              _severityWord(finding.severity),
              style: context.text.labelMedium?.copyWith(
                color: switch (finding.severity) {
                  3 => c.bad,
                  2 => c.warn,
                  _ => c.inkMuted,
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A smooth closed (or open) curve through landmark points (Catmull–Rom).
Path _smooth(List<Offset> pts, {bool closed = true}) {
  final n = pts.length;
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  Offset at(int i) => closed ? pts[(i % n + n) % n] : pts[i.clamp(0, n - 1)];
  for (var i = 0; i < (closed ? n : n - 1); i++) {
    final p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2);
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  if (closed) path.close();
  return path;
}

/// The landmark mesh and feature contours, revealed by a scan line. Under a
/// lens it steps back so the measurement leads.
class _MeshPainter extends CustomPainter {
  _MeshPainter({
    required this.mesh,
    required this.geometry,
    required this.progress,
    required this.sweepY,
    required this.quiet,
  });

  final FaceMesh mesh;
  final FaceGeometry? geometry;
  final double progress;
  final double sweepY;
  final bool quiet;

  @override
  void paint(Canvas canvas, Size size) {
    if (mesh.isEmpty) {
      if (progress < 1) _scanLine(canvas, size);
      return;
    }
    Offset px(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    // While scanning the mesh is bright; once settled it's a whisper.
    final settle = progress < 1 ? 1.0 : (quiet ? 0.35 : 0.8);

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, sweepY));
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.2 * settle)
      ..strokeWidth = 0.6;
    for (final (a, b) in mesh.edges) {
      canvas.drawLine(px(mesh.points[a]), px(mesh.points[b]), line);
    }
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.7 * settle);
    for (final p in mesh.points) {
      canvas.drawCircle(px(p), 1.05, dot);
    }

    // Feature contours as smooth curves: the "tracked" look.
    final g = geometry;
    if (g != null) {
      final contour = Paint()
        ..color = Colors.white.withValues(alpha: 0.55 * settle)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9;
      List<Offset>? pts(String k) => g.contours[k]?.map(px).toList();
      for (final k in ['leftEye', 'rightEye']) {
        final e = pts(k);
        if (e != null && e.length > 3) canvas.drawPath(_smooth(e), contour);
      }
      final lipTop = pts('upperLipTop'), lipBottom = pts('lowerLipBottom');
      if (lipTop != null && lipBottom != null) {
        canvas.drawPath(
          _smooth([...lipTop, ...lipBottom.reversed]),
          contour,
        );
      }
      for (final side in ['left', 'right']) {
        final brow = pts('${side}EyebrowTop');
        if (brow != null && brow.length > 2) {
          canvas.drawPath(_smooth(brow, closed: false), contour);
        }
      }
      final face = pts('face');
      if (face != null && face.length > 3) {
        canvas.drawPath(
          _smooth(face),
          contour..color = Colors.white.withValues(alpha: 0.4 * settle),
        );
      }
    }
    canvas.restore();
    if (progress < 1) _scanLine(canvas, size);
  }

  void _scanLine(Canvas canvas, Size size) {
    final band = Rect.fromLTWH(0, sweepY - 36, size.width, 36);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.18),
          ],
        ).createShader(band),
    );
    canvas.drawLine(
      Offset(0, sweepY),
      Offset(size.width, sweepY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_MeshPainter old) =>
      old.progress != progress ||
      old.sweepY != sweepY ||
      old.quiet != quiet ||
      old.mesh != mesh;
}

/// A lens overlay, cover-fitted to the photo and revealed down to [reveal].
class _LensPainter extends CustomPainter {
  _LensPainter({
    required this.image,
    required this.reveal,
    required this.blend,
  });
  final ui.Image image;
  final double reveal;
  final BlendMode blend;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Size(image.width.toDouble(), image.height.toDouble());
    final fit = applyBoxFit(BoxFit.cover, src, size);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, reveal));
    canvas.drawImageRect(
      image,
      Alignment.center.inscribe(fit.source, Offset.zero & src),
      Alignment.center.inscribe(fit.destination, Offset.zero & size),
      Paint()
        ..filterQuality = FilterQuality.high
        ..blendMode = blend,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LensPainter old) =>
      old.image != image || old.reveal != reveal || old.blend != blend;
}

/// Soft glows on each finding's areas, with fine leader lines to the labels.
class _CalloutPainter extends CustomPainter {
  _CalloutPainter({
    required this.callouts,
    required this.findings,
    required this.geometry,
    required this.focus,
  });

  final List<_Callout> callouts;
  final List<Finding> findings;
  final FaceGeometry? geometry;
  final int? focus;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < findings.length; i++) {
      final dim = focus != null && focus != i;
      final color = _severityColor(findings[i].severity);
      final r = FaceZones.radius(findings[i].area) * size.width * 0.75;
      for (final pt in FaceZones.centers(findings[i].area, geometry)) {
        final center = Offset(pt.dx * size.width, pt.dy * size.height);
        final rect = Rect.fromCircle(center: center, radius: r);
        canvas.drawCircle(
          center,
          r,
          Paint()
            ..shader = RadialGradient(
              colors: [
                color.withValues(alpha: dim ? 0.08 : 0.42),
                color.withValues(alpha: 0),
              ],
            ).createShader(rect),
        );
        canvas.drawCircle(
          center,
          3,
          Paint()..color = color.withValues(alpha: dim ? 0.3 : 1),
        );
      }
    }
    for (final c in callouts) {
      final dim = focus != null && focus != c.index;
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: dim ? 0.2 : 0.7)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;
      canvas.drawPath(
        Path()
          ..moveTo(c.anchor.dx, c.anchor.dy)
          ..lineTo(c.elbow.dx, c.elbow.dy)
          ..lineTo(c.lineEnd.dx, c.lineEnd.dy),
        paint,
      );
      canvas.drawCircle(
        c.anchor,
        5.5,
        Paint()
          ..color = Colors.white.withValues(alpha: dim ? 0.2 : 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_CalloutPainter old) =>
      old.focus != focus ||
      old.callouts != callouts ||
      old.findings != findings;
}
