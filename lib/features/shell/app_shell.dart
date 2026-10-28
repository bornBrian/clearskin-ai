import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../ads/ad_banner.dart';

/// Floating dark pill navigation. The active tab is a light circle; the
/// centre item opens the scan flow instead of switching tabs.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _scanIndex = 2;

  /// Branch index of the Routine tab, the one screen with a banner.
  static const _routineBranch = 1;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Today'),
    (Icons.event_note_outlined, Icons.event_note_rounded, 'Routine'),
    (Icons.center_focus_weak_rounded, Icons.center_focus_weak_rounded, 'Scan'),
    (Icons.show_chart_rounded, Icons.show_chart_rounded, 'Progress'),
    (Icons.spa_outlined, Icons.spa_rounded, 'Shelf'),
  ];

  int get _navIndex => shell.currentIndex >= _scanIndex
      ? shell.currentIndex + 1
      : shell.currentIndex;

  void _onTap(BuildContext context, int i) {
    HapticFeedback.selectionClick();
    if (i == _scanIndex) {
      context.push('/scan');
      return;
    }
    final branch = i > _scanIndex ? i - 1 : i;
    shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final banner =
        shell.currentIndex == _routineBranch && ref.watch(showAdsProvider);
    final barColor = dark ? c.surfaceAlt : c.ink;
    final iconColor = dark ? c.inkMuted : Colors.white.withValues(alpha: 0.75);

    final bg = c.background;
    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (banner) const AdBanner(),
          DecoratedBox(
            // Content fades out beneath the bar instead of being cut by it.
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bg.withValues(alpha: 0), bg.withValues(alpha: 0.92)],
                stops: const [0, 0.45],
              ),
            ),
            child: SafeArea(
              minimum: const EdgeInsets.fromLTRB(
                28,
                Space.lg,
                28,
                Space.navBottomGap,
              ),
              child: Container(
                height: Space.navHeight,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(Radii.pill),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      _NavButton(
                        icon: i == _navIndex ? _items[i].$2 : _items[i].$1,
                        label: _items[i].$3,
                        selected: i == _navIndex,
                        isScan: i == _scanIndex,
                        idleColor: iconColor,
                        onTap: () => _onTap(context, i),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.isScan,
    required this.idleColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool isScan;
  final Color idleColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final activeBg = dark ? c.ink : Colors.white;
    final activeFg = dark ? c.background : c.ink;

    final Color bg;
    final Color fg;
    if (selected) {
      bg = activeBg;
      fg = activeFg;
    } else if (isScan) {
      bg = BrandColors.cream;
      fg = BrandColors.charcoal;
    } else {
      bg = Colors.transparent;
      fg = idleColor;
    }

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.normal,
            curve: Curves.easeOutCubic,
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: fg, size: isScan ? 24 : 22),
          ),
        ),
      ),
    );
  }
}
