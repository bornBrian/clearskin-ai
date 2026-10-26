import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/content/tips.dart';
import '../../services/telemetry.dart';

/// "For you" row on Today: image above, words below — magazine style.
class ForYouCarousel extends ConsumerWidget {
  const ForYouCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tips = TipLibrary.forProfile(ref.watch(profileProvider).value);
    if (tips.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('For you'),
        const SizedBox(height: Space.md),
        SizedBox(
          height: 236,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: tips.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) => _TipCard(tip: tips[i]),
          ),
        ),
      ],
    );
  }
}

class _TipCard extends ConsumerWidget {
  const _TipCard({required this.tip});
  final Tip tip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 172,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ref.read(telemetryProvider).track(Ev.tipOpened, {'id': tip.id});
          context.push('/tip/${tip.id}');
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.md),
              child: SizedBox(
                height: 150,
                width: double.infinity,
                child: PhotoFill(tip.image, scrim: 0),
              ),
            ),
            const SizedBox(height: Space.sm),
            Eyebrow(tip.kind.label),
            const SizedBox(height: 4),
            Text(
              tip.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleSmall?.copyWith(height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editorial reader: title first, a calm image, the one-line takeaway, three
/// numbered points and what to skip. Readable in under a minute.
class TipScreen extends StatelessWidget {
  const TipScreen({super.key, required this.tipId});
  final String tipId;

  @override
  Widget build(BuildContext context) {
    final tip = TipLibrary.byId(tipId);
    if (tip == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Not found')),
      );
    }
    final c = context.colors;
    final next = TipLibrary.all
        .where((t) => t.id != tip.id && t.kind == tip.kind)
        .firstOrNull;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.xs,
            Space.gutter,
            Space.xxl,
          ),
          children:
              [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: 'Back',
                        onPressed: () => context.pop(),
                        icon: Icon(Icons.arrow_back_rounded, color: c.ink),
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    Eyebrow('${tip.kind.label}  ·  1 min read'),
                    const SizedBox(height: Space.sm),
                    Text(
                      tip.title,
                      style: context.text.displaySmall?.copyWith(height: 1.1),
                    ),
                    const SizedBox(height: Space.lg),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: PhotoFill(tip.image, scrim: 0),
                      ),
                    ),
                    const SizedBox(height: Space.xl),
                    const Eyebrow('In short'),
                    const SizedBox(height: Space.sm),
                    Text(
                      tip.teaser,
                      style: context.text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w300,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: Space.xl),
                    const Eyebrow('What to do'),
                    const SizedBox(height: Space.xs),
                    for (var i = 0; i < tip.points.length; i++)
                      _Point(
                        n: i + 1,
                        point: tip.points[i],
                        last: i == tip.points.length - 1,
                      ),
                    if (tip.avoid != null) ...[
                      const SizedBox(height: Space.lg),
                      Container(
                        padding: const EdgeInsets.all(Space.md + 2),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(Radii.md),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.close_rounded, size: 18, color: c.bad),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Eyebrow('Skip'),
                                  const SizedBox(height: 4),
                                  Text(tip.avoid!, style: context.text.bodyLarge),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (next != null) ...[
                      const SizedBox(height: Space.xl),
                      const Eyebrow('Next read'),
                      const SizedBox(height: Space.sm),
                      InkWell(
                        onTap: () => context.pushReplacement('/tip/${next.id}'),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(Radii.sm),
                              child: SizedBox.square(
                                dimension: 72,
                                child: PhotoFill(next.image, scrim: 0),
                              ),
                            ),
                            const SizedBox(width: Space.md),
                            Expanded(
                              child: Text(
                                next.title,
                                style: context.text.titleMedium,
                              ),
                            ),
                            Icon(Icons.arrow_forward_rounded, color: c.ink),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.xl),
                    const Disclaimer(text: 'General guidance, not a diagnosis.'),
                  ]
                  .animate(interval: 40.ms)
                  .fadeIn(duration: Motion.normal)
                  .slideY(begin: 0.04, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.n, required this.point, required this.last});
  final int n;
  final TipPoint point;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              n.toString().padLeft(2, '0'),
              style: context.text.headlineMedium?.copyWith(
                color: c.inkFaint,
                fontWeight: FontWeight.w200,
                height: 1,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(point.title, style: context.text.titleMedium),
                const SizedBox(height: 2),
                Text(point.detail, style: context.text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
