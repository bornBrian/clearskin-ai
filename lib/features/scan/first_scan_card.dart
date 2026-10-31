import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

/// The call to take the first scan: on Today, and in place of the routine
/// until there is one, because the routine is built from that scan.
class FirstScanCard extends StatelessWidget {
  const FirstScanCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BrandColors.charcoal,
      borderRadius: BorderRadius.circular(Radii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/scan'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.xl,
            Space.lg,
            Space.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: SizedBox.square(
                  dimension: 190,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ScoreDial(
                        score: 0,
                        size: 190,
                        trackColor: BrandColors.cream.withValues(alpha: 0.28),
                        color: BrandColors.cream,
                        textColor: Colors.transparent,
                      ),
                      const LogoMark(size: 70, color: BrandColors.cream),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.xl),
              Eyebrow(
                'Front and both sides',
                color: BrandColors.cream.withValues(alpha: 0.6),
              ),
              const SizedBox(height: Space.xs),
              Text(
                'Your first scan',
                style: context.text.displaySmall?.copyWith(
                  color: BrandColors.cream,
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                'Your routine is built from what it sees, not from guesses.',
                style: context.text.bodyMedium?.copyWith(
                  color: BrandColors.cream.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: Space.lg),
              Container(
                height: 54,
                decoration: const ShapeDecoration(
                  color: BrandColors.cream,
                  shape: StadiumBorder(),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Start scan',
                  style: context.text.titleMedium?.copyWith(
                    color: BrandColors.charcoal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
