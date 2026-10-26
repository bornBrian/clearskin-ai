import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/product.dart';
import '../../domain/ingredients/product_analyzer.dart';
import '../../domain/insights/insights_engine.dart';
import 'product_analysis_view.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider).value ?? const <Product>[];
    final product = products.where((p) => p.id == productId).firstOrNull;
    if (product == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Product not found')),
      );
    }
    final profile = ref.watch(profileProvider).value;
    final analysis = ProductAnalyzer.analyze(product.ingredientsRaw, profile);
    final checkIns = ref.watch(checkInsProvider).value ?? const [];
    final breakoutDelta = InsightsEngine.productBreakoutDelta(
      checkIns,
      product.addedAt,
    );
    final c = context.colors;

    Future<void> update(Product p) =>
        ref.read(productsProvider.notifier).upsert(p);

    return Scaffold(
      appBar: AppBar(
        title: Text(product.brand.isEmpty ? 'Product' : product.brand),
        actions: [
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              final ok = await confirm(
                context,
                title: 'Remove from shelf?',
                body: '${product.displayName} will be removed.',
                confirmLabel: 'Remove',
                destructive: true,
              );
              if (!ok) return;
              await ref.read(productsProvider.notifier).remove(product.id);
              if (context.mounted) context.pop();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.xs,
          Space.gutter,
          Space.xl,
        ),
        children: [
          Text(product.name, style: context.text.headlineSmall),
          const SizedBox(height: 2),
          Text(
            '${product.category.label} · added ${Dates.relative(product.addedAt).toLowerCase()}',
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: Space.md),
          if (breakoutDelta != null) ...[
            AppCard(
              color: (breakoutDelta > 0.4 ? c.warn : c.good).withValues(
                alpha: 0.08,
              ),
              borderColor: breakoutDelta > 0.4 ? c.warn : c.good,
              child: Row(
                children: [
                  Icon(
                    breakoutDelta > 0.4
                        ? Icons.trending_up_rounded
                        : Icons.trending_flat_rounded,
                    color: breakoutDelta > 0.4 ? c.warn : c.good,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      breakoutDelta > 0.4
                          ? 'Breakouts rose after you started this. If it contains retinoids or acids this may be purging (usually 4–6 weeks); otherwise consider pausing it for 2 weeks.'
                          : 'No rise in breakouts since you started this product.',
                      style: context.text.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.md),
          ],
          SegmentedButton<ProductStatus>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ProductStatus.active, label: Text('In use')),
              ButtonSegment(value: ProductStatus.paused, label: Text('Paused')),
              ButtonSegment(
                value: ProductStatus.finished,
                label: Text('Finished'),
              ),
            ],
            selected: {product.status},
            onSelectionChanged: (s) =>
                update(product.copyWith(status: s.first)),
          ),
          const SizedBox(height: Space.sm),
          DropdownButtonFormField<ProductUsage>(
            initialValue: product.usage,
            decoration: const InputDecoration(labelText: 'When do you use it?'),
            items: [
              for (final u in ProductUsage.values)
                DropdownMenuItem(value: u, child: Text(u.label)),
            ],
            onChanged: (v) {
              if (v != null) update(product.copyWith(usage: v));
            },
          ),
          const SizedBox(height: Space.lg),
          ProductAnalysisView(analysis: analysis),
        ],
      ),
    );
  }
}
