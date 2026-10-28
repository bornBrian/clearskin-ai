import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../services/telemetry.dart';

/// "Shop gentle cleansers at Amazon ↗": a search in the person's regional
/// store with our affiliate tag, disclosed as a paid link. Nothing renders
/// when no store is configured for their region.
class ShopLinkRow extends ConsumerWidget {
  const ShopLinkRow({super.key, required this.query, this.source = 'routine'});

  /// What to search for ("niacinamide serum").
  final String query;
  final String source;

  /// The phone's region. Device locale rather than IP: no third-party
  /// lookup, and it's where their store account usually is.
  static String? get region => PlatformDispatcher.instance.locale.countryCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(accountStatusProvider).value?.shop;
    final store = shop?.storeFor(region);
    final uri = store?.search(query);
    if (store == null || uri == null) return const SizedBox.shrink();
    final c = context.colors;
    return InkWell(
      onTap: () {
        ref.read(telemetryProvider).track(Ev.shopLinkOpened, {
          'source': source,
          'store': store.name,
        });
        launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Shop $query at ${store.name}',
                    style: context.text.titleSmall?.copyWith(color: c.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Paid link. We may earn a commission; it never changes what we recommend.',
                    style: context.text.bodySmall?.copyWith(color: c.inkFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            Icon(Icons.north_east_rounded, size: 18, color: c.inkMuted),
          ],
        ),
      ),
    );
  }
}
