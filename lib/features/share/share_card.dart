import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/scan.dart';
import '../../domain/guidance/potential.dart';
import '../../domain/scan/skin_measure.dart';
import '../progress/progress_proof.dart';
import '../../services/telemetry.dart';

/// The three cards. Each has one "flex": the score, the person's own glow,
/// or the change between two scans.
enum CardStyle {
  score('Score'),
  photo('Photo'),
  beforeAfter('Before / after');

  const CardStyle(this.label);
  final String label;
}

/// Story is what Instagram, TikTok and WhatsApp status expect; Post fits
/// feeds. Exported at 1080 px wide either way.
enum CardFormat {
  story('Story', 9 / 16),
  post('Post', 4 / 5);

  const CardFormat(this.label, this.aspect);
  final String label;
  final double aspect;
}

/// Opens a preview of the shareable result card. The face photo is never
/// on the card unless the person picks a photo style.
Future<void> showShareCardSheet(
  BuildContext context, {
  required SkinScan scan,
  SkinScan? previous,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ShareSheet(scan: scan, previous: previous),
  );
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.scan, this.previous});
  final SkinScan scan;
  final SkinScan? previous;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  final _boundary = GlobalKey();
  CardStyle _style = CardStyle.score;
  CardFormat _format = CardFormat.story;
  bool _busy = false;

  /// The first scan, for before/after (the most dramatic comparison).
  SkinScan? get _first {
    final usable = ref.read(usableScansProvider);
    final first = usable.isEmpty ? null : usable.last;
    return first == null || first.id == widget.scan.id ? null : first;
  }

  Future<void> _pick(CardStyle s) async {
    if (s == CardStyle.beforeAfter && !ref.read(premiumProvider)) {
      final bought = await context.push<bool>('/paywall?source=compare');
      if (bought != true || !mounted) return;
    }
    setState(() => _style = s);
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final obj = _boundary.currentContext?.findRenderObject();
      if (obj is! RenderRepaintBoundary) return;
      final image = await obj.toImage(pixelRatio: 1080 / obj.size.width);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'clearskin-${_style.name}.png'));
      await file.writeAsBytes(bytes.buffer.asUint8List());
      final a = widget.scan.analysis;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text:
              'My skin score: ${a.overallScore}. Scan yours free with ClearSkin AI.',
        ),
      );
      if (!mounted) return;
      ref.read(telemetryProvider).track(Ev.shareCardShared, {
        'style': _style.name,
        'format': _format.name,
      });
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final first = _first;
    final styles = [
      CardStyle.score,
      CardStyle.photo,
      if (first != null) CardStyle.beforeAfter,
    ];
    // Fit the preview in the sheet whatever the format.
    final previewH = size.height * 0.56;
    final previewW = (previewH * _format.aspect).clamp(0.0, size.width - 48);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.sm,
        Space.gutter,
        Space.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextTabs(
            labels: [for (final s in styles) s.label],
            index: styles.indexOf(_style).clamp(0, styles.length - 1),
            onChanged: (i) => _pick(styles[i]),
          ),
          const SizedBox(height: Space.md),
          SizedBox(
            width: previewW.toDouble(),
            child: RepaintBoundary(
              key: _boundary,
              child: ResultCard(
                scan: widget.scan,
                previous: widget.previous,
                first: first,
                style: _style,
                format: _format,
                proof: ref.watch(progressProofProvider).value,
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          TextTabs(
            labels: [for (final f in CardFormat.values) f.label],
            index: _format.index,
            onChanged: (i) => setState(() => _format = CardFormat.values[i]),
          ),
          const SizedBox(height: Space.md),
          ArrowPill(
            label: _busy ? 'Preparing…' : 'Share',
            icon: Icons.ios_share_rounded,
            dark: true,
            onTap: _busy ? null : _share,
          ),
          if (_style != CardStyle.score) ...[
            const SizedBox(height: Space.xs),
            Text(
              'Your photo is only shared if you send this card.',
              style: context.text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// The shareable card. Charcoal and cream in every theme so a shared image
/// always looks like ClearSkin; sizes are relative so the 1080 px export
/// matches the preview exactly.
class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.scan,
    this.previous,
    this.first,
    this.style = CardStyle.score,
    this.format = CardFormat.story,
    this.proof,
  });

  final SkinScan scan;
  final SkinScan? previous;

  /// The first scan, for before/after.
  final SkinScan? first;
  final CardStyle style;
  final CardFormat format;

  /// Measured change since day 1, for the before/after card.
  final ProgressProof? proof;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: format.aspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.lg),
        // A designed image, sized in card units: the phone's text size
        // setting would only push text out of place.
        child: MediaQuery.withNoTextScaling(
          child: LayoutBuilder(
            builder: (context, box) {
              final u = box.maxWidth / 100; // 1 unit = 1% of card width
              return switch (style) {
                CardStyle.score => _ScoreCard(card: this, u: u),
                CardStyle.photo => _PhotoCard(card: this, u: u),
                CardStyle.beforeAfter => _BeforeAfterCard(card: this, u: u),
              };
            },
          ),
        ),
      ),
    );
  }
}

const _cream = BrandColors.cream;
const _charcoal = BrandColors.charcoal;

TextStyle _type(double size, {double alpha = 1, FontWeight? weight}) =>
    TextStyle(
      fontFamily: kFontFamily,
      fontSize: size,
      color: _cream.withValues(alpha: alpha),
      fontWeight: weight ?? FontWeight.w400,
      height: 1.1,
      decoration: TextDecoration.none,
    );

Widget _eyebrow(String text, double u, {double alpha = 0.6}) => Text(
  text.toUpperCase(),
  style: _type(
    2.9 * u,
    alpha: alpha,
    weight: FontWeight.w600,
  ).copyWith(letterSpacing: 0.5 * u),
);

String _deltaLine(SkinScan scan, SkinScan? previous) {
  if (previous == null) return 'First scan';
  final d = scan.analysis.overallScore - previous.analysis.overallScore;
  final days = scan.createdAt.difference(previous.createdAt).inDays.abs();
  if (d == 0) return 'Steady over $days days';
  return '${d > 0 ? '+' : '−'}${d.abs()} in $days days';
}

/// Brand, then the flex, then the call to scan.
class _Footer extends StatelessWidget {
  const _Footer({required this.u});
  final double u;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Wordmark(size: 4.4 * u, color: _cream),
        const Spacer(),
        Text('Scan yours free', style: _type(3 * u, alpha: 0.6)),
      ],
    );
  }
}

/// No photo: the score dial under a pool of light, the gain, and the three
/// strongest measures as big light numerals.
class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.card, required this.u});
  final ResultCard card;
  final double u;

  @override
  Widget build(BuildContext context) {
    final a = card.scan.analysis;
    final best = ([
      ...a.metrics,
    ]..sort((x, y) => y.score.compareTo(x.score))).take(3).toList();
    final potential = SkinPotential.of(a);
    final story = card.format == CardFormat.story;
    return ColoredBox(
      color: _charcoal,
      child: Stack(
        children: [
          Positioned(
            left: -20 * u,
            right: -20 * u,
            top: story ? 18 * u : 6 * u,
            height: 110 * u,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.55,
                  colors: [
                    _cream.withValues(alpha: 0.12),
                    _cream.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(7 * u),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _eyebrow('My skin', u),
                Spacer(flex: story ? 3 : 1),
                Center(
                  child: ScoreDial(
                    score: a.overallScore,
                    size: (story ? 66 : 52) * u,
                    color: _cream,
                    trackColor: _cream.withValues(alpha: 0.16),
                    textColor: _cream,
                    label: 'Skin score',
                  ),
                ),
                SizedBox(height: 4 * u),
                Center(
                  child: Text(
                    _deltaLine(card.scan, card.previous),
                    style: _type(5 * u, weight: FontWeight.w300),
                  ),
                ),
                Spacer(flex: story ? 3 : 1),
                Container(
                  padding: EdgeInsets.only(top: 4 * u),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: _cream.withValues(alpha: 0.18)),
                    ),
                  ),
                  child: Row(
                    children: [
                      for (final m in best)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${m.score}',
                                style: _type(9 * u, weight: FontWeight.w200),
                              ),
                              SizedBox(height: 1.2 * u),
                              Text(
                                m.metric.label,
                                style: _type(3 * u, alpha: 0.6),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (potential != null && potential.gain > 0) ...[
                  SizedBox(height: 5 * u),
                  Text(
                    'Potential ${potential.potential} in 12 weeks',
                    style: _type(3.6 * u, alpha: 0.8),
                  ),
                ],
                SizedBox(height: story ? 8 * u : 5 * u),
                _Footer(u: u),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _photo(SkinScan? scan) {
  final path = scan?.photoPath;
  if (path == null) return const ColoredBox(color: Color(0xFF3A3936));
  return Image.file(
    File(path),
    fit: BoxFit.cover,
    alignment: const Alignment(0, -0.2),
    errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF3A3936)),
  );
}

/// The person's own photo, full bleed, with the score set over a deep
/// scrim. No circles, no stickers: it should look like a magazine cover.
class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.card, required this.u});
  final ResultCard card;
  final double u;

  @override
  Widget build(BuildContext context) {
    final a = card.scan.analysis;
    final potential = SkinPotential.of(a);
    return Stack(
      fit: StackFit.expand,
      children: [
        _photo(card.scan),
        // Top: keep the wordmark legible. Bottom: room for the numbers.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x80232321),
                Color(0x00232321),
                Color(0x00232321),
                Color(0xE6232321),
              ],
              stops: [0, 0.22, 0.5, 0.86],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(7 * u),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wordmark(size: 4.4 * u, color: _cream),
              const Spacer(),
              _eyebrow('Skin score', u, alpha: 0.75),
              SizedBox(height: 1.5 * u),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${a.overallScore}',
                    style: _type(28 * u, weight: FontWeight.w200),
                  ),
                  SizedBox(width: 4 * u),
                  Padding(
                    padding: EdgeInsets.only(bottom: 3.5 * u),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _deltaLine(card.scan, card.previous),
                          style: _type(4.2 * u),
                        ),
                        if (potential != null && potential.gain > 0) ...[
                          SizedBox(height: 1 * u),
                          Text(
                            'Potential ${potential.potential}',
                            style: _type(4.2 * u, alpha: 0.7),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 5 * u),
              Container(
                padding: EdgeInsets.only(top: 3.5 * u),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: _cream.withValues(alpha: 0.25)),
                  ),
                ),
                child: Row(
                  children: [
                    Text('Scan yours free', style: _type(3 * u, alpha: 0.75)),
                    const Spacer(),
                    Text('ClearSkin AI', style: _type(3 * u, alpha: 0.75)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// First scan and this one side by side, the change in big numerals across
/// the seam. The most convincing thing an app like this can show.
class _BeforeAfterCard extends StatelessWidget {
  const _BeforeAfterCard({required this.card, required this.u});
  final ResultCard card;
  final double u;

  @override
  Widget build(BuildContext context) {
    final before = card.first ?? card.previous;
    final now = card.scan;
    final days = before == null
        ? 0
        : now.createdAt.difference(before.createdAt).inDays.abs();
    final from = before?.analysis.overallScore;
    final to = now.analysis.overallScore;
    Widget half(SkinScan? s, String label) => Stack(
      fit: StackFit.expand,
      children: [
        _photo(s),
        Positioned(
          left: 4 * u,
          top: 4 * u,
          child: _eyebrow(label, u, alpha: 0.9),
        ),
      ],
    );
    return ColoredBox(
      color: _charcoal,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: half(
                        before,
                        card.first != null ? 'Day 1' : 'Before',
                      ),
                    ),
                    SizedBox(width: 0.6 * u),
                    Expanded(
                      child: half(
                        now,
                        card.first != null ? 'Day ${days + 1}' : 'Now',
                      ),
                    ),
                  ],
                ),
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: 0.35,
                    widthFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00232321), Color(0xFF232321)],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(7 * u, 2 * u, 7 * u, 7 * u),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    if (from != null) ...[
                      Text(
                        '$from',
                        style: _type(
                          16 * u,
                          alpha: 0.5,
                          weight: FontWeight.w200,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 3 * u),
                        child: Text('→', style: _type(8 * u, alpha: 0.5)),
                      ),
                    ],
                    Text('$to', style: _type(16 * u, weight: FontWeight.w200)),
                    const Spacer(),
                    if (from != null)
                      Text(
                        '${to >= from ? '+' : '−'}${(to - from).abs()} in ${(days / 7).ceil()} weeks',
                        style: _type(4 * u),
                      ),
                  ],
                ),
                if (card.proof?.improvements case final better?
                    when better.isNotEmpty) ...[
                  SizedBox(height: 2.5 * u),
                  Text(
                    [
                      for (final c in better.take(2))
                        '${ProgressProof.noun(c.lens)} −${(c.change.abs() * 100).round()}%',
                    ].join('   ·   '),
                    style: _type(3.6 * u, alpha: 0.85),
                  ),
                  SizedBox(height: 0.8 * u),
                  Text(
                    'Measured from the photos',
                    style: _type(2.8 * u, alpha: 0.5),
                  ),
                ],
                SizedBox(height: 5 * u),
                _Footer(u: u),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
