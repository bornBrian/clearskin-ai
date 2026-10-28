import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/product.dart';
import '../../domain/ingredients/conflict_checker.dart';
import '../../domain/ingredients/product_analyzer.dart';
import '../../services/device_services.dart';
import '../../domain/products/shelf_life.dart';

class ShelfScreen extends ConsumerStatefulWidget {
  const ShelfScreen({super.key});

  @override
  ConsumerState<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends ConsumerState<ShelfScreen> {
  int _filter = 0; // All, Morning, Evening

  bool _matches(Product p) => switch (_filter) {
    1 => p.usage != ProductUsage.pm,
    2 => p.usage != ProductUsage.am,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);
    final conflicts = ref.watch(conflictsProvider);
    final c = context.colors;
    return Scaffold(
      body: AuraBackground(
        intensity: 0.6,
        child: SafeArea(
          bottom: false,
          child: AsyncBody(
            value: products,
            data: (list) {
              final active = list
                  .where((p) => p.status == ProductStatus.active)
                  .toList();
              final inactive = list
                  .where((p) => p.status != ProductStatus.active)
                  .toList();
              final shown = active.where(_matches).toList();
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.md,
                      Space.gutter,
                      0,
                    ),
                    sliver: SliverList.list(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Eyebrow(
                                    [
                                      '${active.length} product${active.length == 1 ? '' : 's'}',
                                      if (conflicts.isEmpty &&
                                          active.length >= 2)
                                        'no clashes',
                                    ].join(' · '),
                                  ),
                                  const SizedBox(height: Space.xs),
                                  Text(
                                    'Shelf',
                                    style: context.text.displaySmall,
                                  ),
                                ],
                              ),
                            ),
                            CircleButton(
                              icon: Icons.add_rounded,
                              filled: true,
                              tooltip: 'Add product',
                              onTap: () => showAddProductSheet(context, ref),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.lg),
                        if (list.isEmpty)
                          _EmptyShelf(
                            onAdd: () => showAddProductSheet(context, ref),
                          )
                        else ...[
                          if (conflicts.isNotEmpty) ...[
                            _Conflicts(conflicts: conflicts),
                            const SizedBox(height: Space.lg),
                          ],
                          TextTabs(
                            labels: const ['All', 'Morning', 'Evening'],
                            index: _filter,
                            style: context.text.titleMedium,
                            onChanged: (i) => setState(() => _filter = i),
                          ),
                          const SizedBox(height: Space.md),
                        ],
                      ],
                    ),
                  ),
                  if (shown.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.gutter,
                      ),
                      sliver: SliverGrid.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: Space.lg,
                          crossAxisSpacing: Space.md,
                          // Taller tiles when the person uses larger text, so
                          // names and labels never get cut off.
                          childAspectRatio:
                              0.58 /
                              (MediaQuery.textScalerOf(context).scale(14) / 14)
                                  .clamp(1.0, 1.3),
                        ),
                        itemCount: shown.length,
                        itemBuilder: (_, i) => _ProductCard(product: shown[i]),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.lg,
                      Space.gutter,
                      Space.navClearance(context),
                    ),
                    sliver: SliverList.list(
                      children: [
                        if (inactive.isNotEmpty) ...[
                          Eyebrow('Paused & finished · ${inactive.length}'),
                          const SizedBox(height: Space.xs),
                          for (final p in inactive)
                            LineItem(
                              title: p.name,
                              subtitle: [
                                if (p.brand.isNotEmpty) p.brand,
                                p.status.name,
                              ].join(' · '),
                              leading: ProductGlyph(
                                category: p.category,
                                size: 36,
                                color: c.inkFaint,
                              ),
                              onTap: () => context.push('/product/${p.id}'),
                            ),
                          const SizedBox(height: Space.lg),
                        ],
                        if (list.isNotEmpty)
                          Text(
                            'Barcode data: Open Beauty Facts (ODbL).',
                            style: context.text.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Space.xl),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final cat in [
              ProductCategory.cleanser,
              ProductCategory.serum,
              ProductCategory.moisturizer,
            ])
              ProductGlyph(category: cat, size: 84, color: c.inkMuted),
          ],
        ),
        const SizedBox(height: Space.xl),
        Text('Your shelf, checked', style: context.text.headlineMedium),
        const SizedBox(height: Space.xs),
        Text(
          'Scan a barcode to see if a product suits your skin — and if it clashes with anything else.',
          style: context.text.bodyMedium,
        ),
        const SizedBox(height: Space.lg),
        ArrowPill(label: 'Add a product', dark: true, onTap: onAdd),
      ],
    );
  }
}

class _Conflicts extends StatelessWidget {
  const _Conflicts({required this.conflicts});
  final List<RoutineConflict> conflicts;

  @override
  Widget build(BuildContext context) {
    const cream = BrandColors.cream;
    return Container(
      padding: const EdgeInsets.all(Space.md + 2),
      decoration: BoxDecoration(
        color: BrandColors.charcoal,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(
            '${conflicts.length} to fix',
            color: cream.withValues(alpha: 0.6),
          ),
          for (final x in conflicts) ...[
            const SizedBox(height: Space.sm),
            Text(
              x.title,
              style: context.text.titleSmall?.copyWith(color: cream),
            ),
            const SizedBox(height: 2),
            Text(
              x.advice,
              style: context.text.bodySmall?.copyWith(
                color: cream.withValues(alpha: 0.65),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductCard extends ConsumerWidget {
  const _ProductCard({required this.product});
  final Product product;

  /// A quiet tone per kind of container, so a shelf reads like a shelf.
  static Color _tile(ProductCategory cat, AppColors c, bool dark) {
    if (dark) return c.surfaceAlt;
    return switch (cat) {
      ProductCategory.cleanser ||
      ProductCategory.sunscreen ||
      ProductCategory.shaving => const Color(0xFFF2EDE3),
      ProductCategory.serum ||
      ProductCategory.treatment ||
      ProductCategory.exfoliant ||
      ProductCategory.toner => const Color(0xFFE2EAE1),
      ProductCategory.moisturizer ||
      ProductCategory.mask ||
      ProductCategory.eyeCream => const Color(0xFFECE4D8),
      ProductCategory.makeup ||
      ProductCategory.other => const Color(0xFFE7E7E1),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final profile = ref.watch(profileProvider).value;
    final verdict = ProductAnalyzer.analyze(
      product.ingredientsRaw,
      profile,
    ).verdict;
    final when = switch (product.usage) {
      ProductUsage.am => 'AM',
      ProductUsage.pm => 'PM',
      ProductUsage.both => 'AM · PM',
      ProductUsage.occasional => 'Weekly',
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/product/${product.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 0.86,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: _tile(product.category, c, dark),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Stack(
                children: [
                  Center(
                    child: product.imageUrl == null
                        ? ProductGlyph(category: product.category, size: 92)
                        : Padding(
                            padding: const EdgeInsets.all(Space.lg),
                            child: Image.network(
                              product.imageUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => ProductGlyph(
                                category: product.category,
                                size: 92,
                              ),
                            ),
                          ),
                  ),
                  Positioned(
                    left: Space.sm,
                    top: Space.sm,
                    child: Text(
                      when,
                      style: context.text.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        color: c.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            product.brand.isEmpty ? product.category.label : product.brand,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelMedium?.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: 2),
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.text.titleSmall?.copyWith(height: 1.25),
          ),
          if (ShelfLife.freshness(product, clock.now()) case final f?
              when f != Freshness.fresh) ...[
            const SizedBox(height: 4),
            Text(
              f == Freshness.expired ? 'Past its best' : 'Use soon',
              style: context.text.labelMedium?.copyWith(
                color: f == Freshness.expired ? c.bad : c.warn,
              ),
            ),
          ] else if (verdict != Verdict.unknown) ...[
            const SizedBox(height: 4),
            Text(
              verdict.label,
              style: context.text.labelMedium?.copyWith(
                color: switch (verdict) {
                  Verdict.caution => c.warn,
                  Verdict.avoid => c.bad,
                  _ => c.inkFaint,
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Entry point for adding/checking a product. Free users get a few checks
/// per day; the paywall appears before work is wasted.
Future<void> showAddProductSheet(BuildContext context, WidgetRef ref) async {
  final premium = ref.read(premiumProvider);
  final quota = ref.read(productQuotaProvider);
  if (!premium && await quota.usedToday() >= FreeLimits.productChecksPerDay) {
    if (context.mounted) await context.push('/paywall?source=products');
    return;
  }
  if (!context.mounted) return;
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.qr_code_scanner_rounded),
            title: const Text('Scan barcode'),
            subtitle: const Text('Fastest — looks up the ingredient list'),
            onTap: () => Navigator.pop(ctx, 'barcode'),
          ),
          ListTile(
            leading: const Icon(Icons.document_scanner_outlined),
            title: const Text('Photograph the ingredients'),
            subtitle: const Text('Reads the label on the back, on your phone'),
            onTap: () => Navigator.pop(ctx, 'ocr'),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Enter manually'),
            onTap: () => Navigator.pop(ctx, 'manual'),
          ),
          const SizedBox(height: Space.sm),
        ],
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  switch (choice) {
    case 'barcode':
      await context.push('/barcode');
    case 'ocr':
      await _ocrFlow(context, ref);
    case 'manual':
      await context.push('/product/review', extra: const ProductDraft());
  }
}

Future<void> _ocrFlow(BuildContext context, WidgetRef ref) async {
  final shot = await ImagePicker().pickImage(
    source: ImageSource.camera,
    maxWidth: 2000,
    requestFullMetadata: false,
  );
  if (shot == null || !context.mounted) return;
  try {
    final text = await ref.read(ocrServiceProvider).readText(shot.path);
    final ingredients = OcrService.extractIngredients(text);
    if (!context.mounted) return;
    if (ingredients.length < 20) {
      showSnack(
        context,
        'Couldn\'t read an ingredient list. Try again closer, in good light.',
      );
      return;
    }
    await context.push(
      '/product/review',
      extra: ProductDraft(ingredientsRaw: ingredients),
    );
  } catch (_) {
    if (context.mounted) {
      showSnack(context, 'Couldn\'t read the label. Try entering it manually.');
    }
  }
}
