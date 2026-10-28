import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

/// Shown over everything when the APK's signature isn't ours: someone
/// unpacked, modified and re-signed the app. Modified copies can carry
/// malware, and they can't reach Premium or the AI anyway (the server
/// checks Play Integrity), so the honest move is to send people to the
/// real app.
class TamperedScreen extends StatelessWidget {
  const TamperedScreen({super.key});

  static final _store = Uri.parse(
    'https://play.google.com/store/apps/details?id=com.clearskinai.app',
  );

  @override
  Widget build(BuildContext context) {
    const cream = BrandColors.cream;
    return Material(
      color: BrandColors.charcoal,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const BrandMark(size: 56, color: cream),
              const SizedBox(height: Space.xl),
              Text(
                'This copy of ClearSkin\nhas been modified.',
                style: context.text.headlineMedium?.copyWith(
                  color: cream,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: Space.sm),
              Text(
                'Modified apps can hide malware and put your photos at risk. Install ClearSkin from Google Play to keep your skin data safe.',
                style: context.text.bodyLarge?.copyWith(
                  color: cream.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: cream,
                    foregroundColor: BrandColors.charcoal,
                  ),
                  onPressed: () =>
                      launchUrl(_store, mode: LaunchMode.externalApplication),
                  child: const Text('Open Google Play'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
