import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/scan.dart';

/// Before/after slider. Photos are only ever shared when the user explicitly
/// taps Share, and the export is watermarked.
class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({super.key});

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  final _boundary = GlobalKey();
  SkinScan? _before;
  SkinScan? _after;
  double _split = 0.5;
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final obj = _boundary.currentContext?.findRenderObject();
      if (obj is! RenderRepaintBoundary) return;
      final image = await obj.toImage(pixelRatio: 2.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'clearskin-progress.png'));
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: 'My skin progress with ClearSkin AI ✨',
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scans = ref.watch(usableScansProvider);
    if (scans.length < 2) {
      return Scaffold(
        appBar: AppBar(title: const Text('Compare')),
        body: const EmptyState(
          icon: Icons.compare_rounded,
          title: 'Need two scans',
          body: 'Take another scan to compare before and after.',
        ),
      );
    }
    _after ??= scans.first;
    _before ??= scans.last;
    final c = context.colors;
    final before = _before!;
    final after = _after!;
    final delta = after.analysis.overallScore - before.analysis.overallScore;
    final days = after.createdAt.difference(before.createdAt).inDays.abs();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Before & after'),
        actions: [
          IconButton(
            onPressed: _sharing ? null : _share,
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Share',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.gutter),
        children: [
          RepaintBoundary(
            key: _boundary,
            child: Container(
              color: c.surface,
              padding: const EdgeInsets.all(Space.sm),
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 3 / 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.md),
                      child: LayoutBuilder(
                        builder: (context, box) {
                          return GestureDetector(
                            onHorizontalDragUpdate: (d) => setState(
                              () => _split = (d.localPosition.dx / box.maxWidth)
                                  .clamp(0.02, 0.98),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  File(after.photoPath),
                                  fit: BoxFit.cover,
                                ),
                                ClipRect(
                                  clipper: _LeftClipper(_split),
                                  child: Image.file(
                                    File(before.photoPath),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  left: box.maxWidth * _split - 1.5,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 3,
                                    color: Colors.white,
                                  ),
                                ),
                                Positioned(
                                  left: box.maxWidth * _split - 18,
                                  top: box.maxHeight / 2 - 18,
                                  child: const CircleAvatar(
                                    radius: 18,
                                    backgroundColor: Colors.white,
                                    child: Icon(
                                      Icons.unfold_more_rounded,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                _Label(
                                  Dates.short(before.createdAt),
                                  alignment: Alignment.topLeft,
                                ),
                                _Label(
                                  Dates.short(after.createdAt),
                                  alignment: Alignment.topRight,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Row(
                    children: [
                      Icon(Icons.spa_rounded, color: c.primary, size: 18),
                      const SizedBox(width: 4),
                      Text('ClearSkin AI', style: context.text.titleSmall),
                      const Spacer(),
                      Text(
                        '${before.analysis.overallScore} → ${after.analysis.overallScore}'
                        '  (${delta >= 0 ? '+' : ''}$delta in $days days)',
                        style: context.text.titleSmall?.copyWith(
                          color: delta >= 0 ? c.good : c.bad,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
          _ScanPicker(
            label: 'Before',
            scans: scans,
            value: before,
            onChanged: (s) => setState(() => _before = s),
          ),
          const SizedBox(height: Space.sm),
          _ScanPicker(
            label: 'After',
            scans: scans,
            value: after,
            onChanged: (s) => setState(() => _after = s),
          ),
          const SizedBox(height: Space.lg),
          const SectionHeader('By attribute'),
          AppCard(
            child: Column(
              children: [
                for (final m in SkinMetric.values)
                  if (after.analysis.scoreFor(m) != null)
                    MetricBar(
                      label: m.label,
                      score: after.analysis.scoreFor(m)!,
                      delta: before.analysis.scoreFor(m) == null
                          ? null
                          : after.analysis.scoreFor(m)! -
                                before.analysis.scoreFor(m)!,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  _LeftClipper(this.split);
  final double split;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * split, size.height);

  @override
  bool shouldReclip(_LeftClipper old) => old.split != split;
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.alignment});
  final String text;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: Container(
      margin: const EdgeInsets.all(Space.xs),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    ),
  );
}

class _ScanPicker extends StatelessWidget {
  const _ScanPicker({
    required this.label,
    required this.scans,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<SkinScan> scans;
  final SkinScan value;
  final ValueChanged<SkinScan> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value.id,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final s in scans)
          DropdownMenuItem(
            value: s.id,
            child: Text(
              '${Dates.short(s.createdAt)} · score ${s.analysis.overallScore}',
            ),
          ),
      ],
      onChanged: (id) {
        final s = scans.where((x) => x.id == id).firstOrNull;
        if (s != null) onChanged(s);
      },
    );
  }
}
