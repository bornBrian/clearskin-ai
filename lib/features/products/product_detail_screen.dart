import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/product.dart';
import '../../domain/ingredients/product_analyzer.dart';
import '../../domain/insights/insights_engine.dart';
import '../../domain/products/shelf_life.dart';
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
          TextTabs(
            labels: const ['In use', 'Paused', 'Finished'],
            index: product.status.index,
            style: context.text.titleMedium,
            onChanged: (i) =>
                update(product.copyWith(status: ProductStatus.values[i])),
          ),
          const SizedBox(height: Space.lg),
          const Eyebrow('When'),
          const SizedBox(height: Space.xs),
          TextTabs(
            labels: const ['Morning', 'Night', 'Both', 'Sometimes'],
            index: product.usage.index,
            style: context.text.titleMedium,
            onChanged: (i) =>
                update(product.copyWith(usage: ProductUsage.values[i])),
          ),
          const SizedBox(height: Space.md),
          _ShelfLifeRow(
            product: product,
            suggested: ShelfLife.suggestedMonths(
              product.category,
              analysis.families,
            ),
            onChanged: update,
          ),
          const SizedBox(height: Space.lg),
          ProductAnalysisView(analysis: analysis),
        ],
      ),
    );
  }
}

/// Opened on · use within · use by. Setting the date is one tap; the
/// months default to what's typical for this kind of product.
class _ShelfLifeRow extends StatelessWidget {
  const _ShelfLifeRow({
    required this.product,
    required this.suggested,
    required this.onChanged,
  });

  final Product product;
  final int suggested;
  final Future<void> Function(Product) onChanged;

  Future<void> _pickOpened(BuildContext context) async {
    final now = clock.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: product.openedAt ?? now,
      firstDate: now.subtract(const Duration(days: 730)),
      lastDate: now,
      helpText: 'Opened on',
    );
    if (picked == null) return;
    await onChanged(
      product.copyWith(
        openedAt: picked,
        paoMonths: product.paoMonths ?? suggested,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final useBy = ShelfLife.useBy(product);
    final fresh = ShelfLife.freshness(product, clock.now());
    final date = DateFormat('d MMM y');
    if (product.openedAt == null) {
      return LineItem(
        title: 'When did you open it?',
        subtitle: 'Get a reminder before it stops working',
        trailing: Icon(Icons.chevron_right_rounded, color: c.inkFaint),
        divider: false,
        onTap: () => _pickOpened(context),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LineItem(
          title: 'Opened ${date.format(product.openedAt!)}',
          subtitle: useBy == null
              ? null
              : switch (fresh) {
                  Freshness.expired =>
                    'Past its best since ${date.format(useBy)}. Replace it.',
                  Freshness.endingSoon => 'Use by ${date.format(useBy)}',
                  _ => 'Good until ${date.format(useBy)}',
                },
          trailing: Icon(Icons.edit_calendar_outlined, color: c.inkFaint),
          onTap: () => _pickOpened(context),
        ),
        DropdownButtonFormField<int>(
          initialValue: product.paoMonths ?? suggested,
          decoration: const InputDecoration(
            labelText: 'Good for after opening (on the pack: 6M, 12M…)',
          ),
          items: [
            for (final m in ShelfLife.choices)
              DropdownMenuItem(value: m, child: Text('$m months')),
          ],
          onChanged: (v) {
            if (v != null) onChanged(product.copyWith(paoMonths: v));
          },
        ),
      ],
    );
  }
}
