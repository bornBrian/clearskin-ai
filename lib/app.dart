import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/repositories.dart';
import 'features/lock/lock_screen.dart';

/// Whether the app is currently behind the biometric lock.
class LockNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void lock() => state = true;
  void unlock() => state = false;
}

final lockProvider = NotifierProvider<LockNotifier, bool>(LockNotifier.new);

class ClearSkinApp extends ConsumerStatefulWidget {
  const ClearSkinApp({super.key, this.startLocked = false});
  final bool startLocked;

  @override
  ConsumerState<ClearSkinApp> createState() => _ClearSkinAppState();
}

class _ClearSkinAppState extends ConsumerState<ClearSkinApp>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.startLocked) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(lockProvider.notifier).lock(),
      );
    }
    unawaited(_linkIdentity());
  }

  /// Creates the anonymous backend session and links it to RevenueCat so
  /// purchases are verifiable server-side. Runs after first frame so a slow
  /// network never delays startup.
  Future<void> _linkIdentity() async {
    final uid = await ref.read(backendApiProvider).ensureSession();
    if (uid != null) {
      await ref.read(purchasesServiceProvider).identify(uid);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(purchasesServiceProvider).refresh());
      final away = _backgroundedAt == null
          ? Duration.zero
          : DateTime.now().difference(_backgroundedAt!);
      if (away > const Duration(seconds: 60)) {
        unawaited(_relockIfEnabled());
      }
    }
  }

  Future<void> _relockIfEnabled() async {
    final enabled = await ref.read(kvProvider).get(KvKeys.appLock) == '1';
    if (enabled && mounted) ref.read(lockProvider.notifier).lock();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final locked = ref.watch(lockProvider);
    // Keeps streak / UV / come-back alerts planned against the latest state.
    ref.watch(smartAlertsProvider);
    return MaterialApp.router(
      title: 'ClearSkin AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) {
        // Respect user font scaling but cap it so layouts stay intact.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(maxScaleFactor: 1.3),
          ),
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              if (locked) const Positioned.fill(child: LockScreen()),
            ],
          ),
        );
      },
    );
  }
}
