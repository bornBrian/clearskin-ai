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
import '../../core/widgets/widgets.dart';
import '../../data/models/scan.dart';
import '../../services/telemetry.dart';

/// Opens a preview of the shareable result card. The face photo is OFF by
/// default; users opt in explicitly.
Future<void> showShareCardSheet(
  BuildContext context, {
  required SkinScan scan,
  SkinScan? previous,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ShareSheet(scan: scan, previous: previous),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.scan, this.previous});
  final SkinScan scan;
  final SkinScan? previous;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _boundary = GlobalKey();
  bool _withPhoto = false;
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final obj = _boundary.currentContext?.findRenderObject();
      if (obj is! RenderRepaintBoundary) return;
      // Export at 1080 px wide regardless of screen size.
      final ratio = 1080 / obj.size.width;
      final image = await obj.toImage(pixelRatio: ratio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'clearskin-result.png'));
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: 'My skin score with ClearSkin AI ✨',
        ),
      );
      if (!mounted) return;
      ProviderScope.containerOf(context)
          .read(telemetryProvider)
          .track(Ev.shareCardShared, {'with_photo': _withPhoto});
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width - Space.gutter * 2;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Share your result', style: context.text.headlineSmall),
            const SizedBox(height: Space.md),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW.clamp(0, 340)),
              child: RepaintBoundary(
                key: _boundary,
                child: ResultCard(
                  scan: widget.scan,
                  previous: widget.previous,
                  showPhoto: _withPhoto,
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _withPhoto,
              onChanged: (v) => setState(() => _withPhoto = v),
              title: const Text('Include my photo'),
              subtitle: const Text('Off by default. Only you decide.'),
            ),
            const SizedBox(height: Space.xs),
            ArrowPill(
              label: _busy ? 'Preparing…' : 'Share',
              icon: Icons.ios_share_rounded,
              dark: true,
              onTap: _busy ? null : _share,
            ),
          ],
        ),
      ),
    );
  }
}

/// 4:5 card sized for Instagram/TikTok feeds. Always light theme so shared
/// images look consistent whatever the sender's theme.
class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.scan,
    this.previous,
    this.showPhoto = false,
  });

  final SkinScan scan;
  final SkinScan? previous;
  final bool showPhoto;

  @override
  Widget build(BuildContext context) {
    const c = AppColors.light;
    final a = scan.analysis;
    final delta = previous == null
        ? null
        : a.overallScore - previous!.analysis.overallScore;
    final days = previous == null
        ? null
        : scan.createdAt.difference(previous!.createdAt).inDays.abs();
    final best = [...a.metrics]..sort((x, y) => y.score.compareTo(x.score));

    return Theme(
      data: Theme.of(context).copyWith(extensions: const [AppColors.light]),
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.lg),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [c.glowA, c.background, c.glowB],
              ),
            ),
            padding: const EdgeInsets.all(22),
            child: LayoutBuilder(
              builder: (context, box) {
                final ring = box.maxWidth * 0.5;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wordmark(size: box.maxWidth * 0.05, color: c.ink),
                    const Spacer(),
                    Row(
                      children: [
                        ScoreRing(
                          score: a.overallScore,
                          size: ring,
                          stroke: 5,
                          label: 'SKIN SCORE',
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showPhoto)
                                Container(
                                  width: ring * 0.42,
                                  height: ring * 0.42,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                  ),
                                  child: ClipOval(
                                    child: Image.file(
                                      File(scan.photoPath),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          ColoredBox(color: c.surfaceAlt),
                                    ),
                                  ),
                                ),
                              if (delta != null && delta != 0)
                                Text(
                                  '${delta > 0 ? '+' : ''}$delta',
                                  style: TextStyle(
                                    fontFamily: kFontFamily,
                                    fontSize: box.maxWidth * 0.11,
                                    fontWeight: FontWeight.w300,
                                    color: delta > 0 ? c.good : c.bad,
                                    height: 1,
                                  ),
                                ),
                              if (days != null && delta != null && delta != 0)
                                Text(
                                  'in $days days',
                                  style: TextStyle(
                                    fontFamily: kFontFamily,
                                    fontSize: box.maxWidth * 0.04,
                                    color: c.inkMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final m in best.take(3))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(Radii.pill),
                            ),
                            child: Text(
                              '${m.metric.label} ${m.score}',
                              style: TextStyle(
                                fontFamily: kFontFamily,
                                fontSize: box.maxWidth * 0.036,
                                fontWeight: FontWeight.w600,
                                color: c.ink,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Scan yours free · ClearSkin AI',
                      style: TextStyle(
                        fontFamily: kFontFamily,
                        fontSize: box.maxWidth * 0.034,
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
