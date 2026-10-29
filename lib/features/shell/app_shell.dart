import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../ads/ad_banner.dart';

/// Bottom navigation: a flat bar on the page colour, a hairline above it,
/// icon and label per tab. The only filled shape is Scan, the app's main
/// action; it opens the scan flow instead of switching tabs.
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
    final banner =
        shell.currentIndex == _routineBranch && ref.watch(showAdsProvider);

    return Scaffold(
      body: shell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (banner) const AdBanner(),
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.background,
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: Space.navHeight,
                child: Row(
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      Expanded(
                        child: _NavButton(
                          icon: i == _navIndex ? _items[i].$2 : _items[i].$1,
                          label: _items[i].$3,
                          selected: i == _navIndex,
                          isScan: i == _scanIndex,
                          onTap: () => _onTap(context, i),
                        ),
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
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool isScan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Widget child;
    if (isScan) {
      child = Center(
        child: Container(
          width: 52,
          height: 44,
          decoration: BoxDecoration(
            color: dark ? BrandColors.cream : BrandColors.charcoal,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Icon(
            icon,
            size: 24,
            color: dark ? BrandColors.charcoal : BrandColors.cream,
          ),
        ),
      );
    } else {
      final fg = selected ? c.ink : c.inkFaint;
      child = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: fg),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }
}
