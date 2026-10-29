import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/ingredients/product_analyzer.dart';

/// Renders a personalised product analysis: verdict, why it fits, flags and
/// the full decoded ingredient list.
class ProductAnalysisView extends StatelessWidget {
  const ProductAnalysisView({super.key, required this.analysis});
  final ProductAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = analysis;
    if (a.ingredients.isEmpty) {
      return Text(
        'Add the ingredient list to see how this product suits you.',
        style: context.text.bodyMedium,
      );
    }
    final color = a.verdict.color(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The fit as a big light number beside a word: no tinted card, no
        // ring.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (a.verdict != Verdict.unknown) ...[
              Text(
                '${a.fitScore}',
                style: context.text.displayMedium?.copyWith(
                  fontWeight: FontWeight.w200,
                  height: 1,
                ),
              ),
              const SizedBox(width: Space.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.verdict.label,
                    style: context.text.titleLarge?.copyWith(
                      color:
                          a.verdict == Verdict.avoid ||
                              a.verdict == Verdict.caution
                          ? color
                          : c.ink,
                    ),
                  ),
                  Text(
                    a.verdict == Verdict.unknown
                        ? 'Only ${a.recognizedCount} ingredients recognised.'
                        : 'For your skin · ${a.recognizedCount} ingredients read',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (a.highlights.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          Text('Good for you', style: context.text.titleMedium),
          const SizedBox(height: Space.xs),
          for (final h in a.highlights)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_rounded, color: c.ink, size: 18),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${h.ingredient.name}: ',
                            style: context.text.titleSmall,
                          ),
                          TextSpan(
                            text: h.ingredient.summary,
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (a.flags.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          Text('Worth knowing', style: context.text.titleMedium),
          const SizedBox(height: Space.xs),
          for (final f in a.flags)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(f.severity.icon, color: f.severity.color(c), size: 18),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.title, style: context.text.titleSmall),
                        Text(f.message, style: context.text.bodySmall),
                        Text(
                          f.ingredients.join(', '),
                          style: context.text.labelSmall?.copyWith(
                            color: f.severity.color(c),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: Space.md),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(
            'All ingredients (${a.ingredients.length})',
            style: context.text.titleMedium,
          ),
          children: [
            for (final i in a.ingredients)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Text(
                  '${i.position + 1}',
                  style: context.text.labelMedium,
                ),
                title: Text(
                  i.raw,
                  style: context.text.bodyMedium?.copyWith(color: c.ink),
                ),
                subtitle: i.match == null
                    ? null
                    : Text(i.match!.summary, style: context.text.bodySmall),
              ),
          ],
        ),
      ],
    );
  }
}
