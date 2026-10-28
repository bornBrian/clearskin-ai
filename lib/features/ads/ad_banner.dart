import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/providers.dart';
import '../../services/ads_service.dart';

/// Anchored adaptive banner for free users. Takes no space until an ad has
/// actually loaded, and never renders for Premium.
class AdBanner extends ConsumerStatefulWidget {
  const AdBanner({super.key});

  /// Height to reserve below scrolling content while a banner shows.
  static const reserve = 64.0;

  @override
  ConsumerState<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends ConsumerState<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      _load();
    }
  }

  Future<void> _load() async {
    final ads = ref.read(adsServiceProvider);
    final unit = AdsService.unitFor(AdPlacement.banner);
    if (unit == null || !ads.canRequestAds || !ref.read(showAdsProvider)) {
      return;
    }
    final width = MediaQuery.sizeOf(context).width.truncate();
    final size =
        await AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation(
          Orientation.portrait,
          width,
        );
    if (size == null || !mounted) return;
    final ad = BannerAd(
      adUnitId: unit,
      size: size,
      request: ads.request,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!ref.watch(showAdsProvider) || !_loaded || ad == null) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      bottom: false,
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
