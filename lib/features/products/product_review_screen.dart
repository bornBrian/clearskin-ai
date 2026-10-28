import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/product.dart';
import '../../domain/ingredients/product_analyzer.dart';
import '../../services/product_lookup_service.dart';
import '../../services/telemetry.dart';
import 'product_analysis_view.dart';

/// Review a looked-up / OCR'd / manual product, see the personalised
/// analysis live, then add it to the shelf.
class ProductReviewScreen extends ConsumerStatefulWidget {
  const ProductReviewScreen({super.key, required this.draft});
  final ProductDraft draft;

  @override
  ConsumerState<ProductReviewScreen> createState() =>
      _ProductReviewScreenState();
}

class _ProductReviewScreenState extends ConsumerState<ProductReviewScreen> {
  late final _name = TextEditingController(text: widget.draft.name);
  late final _brand = TextEditingController(text: widget.draft.brand);
  late final _ingredients = TextEditingController(
    text: widget.draft.ingredientsRaw,
  );
  late ProductCategory _category = widget.draft.category;
  ProductUsage _usage = ProductUsage.both;
  Timer? _debounce;
  bool _counted = false;

  @override
  void initState() {
    super.initState();
    if (_category == ProductCategory.other && widget.draft.name.isNotEmpty) {
      _category = ProductLookupService.guessCategory(widget.draft.name);
    }
    _usage = _defaultUsage(_category);
    _ingredients.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 400),
        () => mounted ? setState(() {}) : null,
      );
    });
    // A check is counted against the free quota once it shows a result.
    if (widget.draft.ingredientsRaw.isNotEmpty) _countCheck();
  }

  void _countCheck() {
    if (_counted || ref.read(premiumProvider)) return;
    _counted = true;
    unawaited(ref.read(productQuotaProvider).increment());
  }

  ProductUsage _defaultUsage(ProductCategory c) => switch (c) {
    ProductCategory.sunscreen => ProductUsage.am,
    ProductCategory.exfoliant ||
    ProductCategory.treatment ||
    ProductCategory.mask => ProductUsage.pm,
    _ => ProductUsage.both,
  };

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _brand.dispose();
    _ingredients.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'Give the product a name.');
      return;
    }
    _countCheck();
    await ref
        .read(productsProvider.notifier)
        .upsert(
          Product(
            id: newId(),
            name: _name.text.trim(),
            brand: _brand.text.trim(),
            category: _category,
            usage: _usage,
            ingredientsRaw: _ingredients.text.trim(),
            addedAt: clock.now(),
            barcode: widget.draft.barcode,
            imageUrl: widget.draft.imageUrl,
          ),
        );
    if (!mounted) return;
    ref.read(telemetryProvider).track(Ev.productAdded, {
      'source': widget.draft.barcode != null ? 'barcode' : 'manual_or_ocr',
      'category': _category.name,
    });
    showSnack(context, 'Added to your shelf');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final analysis = ProductAnalyzer.analyze(_ingredients.text, profile);
    return Scaffold(
      appBar: AppBar(title: const Text('Check product')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.xs,
          Space.gutter,
          Space.xl,
        ),
        children: [
          ProductAnalysisView(analysis: analysis),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Product name'),
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _brand,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Brand (optional)'),
          ),
          const SizedBox(height: Space.sm),
          DropdownButtonFormField<ProductCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final c in ProductCategory.values)
                DropdownMenuItem(value: c, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() {
              _category = v ?? _category;
              _usage = _defaultUsage(_category);
            }),
          ),
          const SizedBox(height: Space.sm),
          DropdownButtonFormField<ProductUsage>(
            initialValue: _usage,
            decoration: const InputDecoration(labelText: 'When do you use it?'),
            items: [
              for (final u in ProductUsage.values)
                DropdownMenuItem(value: u, child: Text(u.label)),
            ],
            onChanged: (v) => setState(() => _usage = v ?? _usage),
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _ingredients,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Ingredients (INCI list)',
              alignLabelWithHint: true,
              hintText: 'Water, Glycerin, Niacinamide, …',
            ),
            onEditingComplete: _countCheck,
          ),
          const SizedBox(height: Space.lg),
          FilledButton(onPressed: _save, child: const Text('Add to my shelf')),
          const SizedBox(height: Space.xs),
          OutlinedButton(
            onPressed: () => context.pop(),
            child: const Text('Just checking — don\'t save'),
          ),
        ],
      ),
    );
  }
}
