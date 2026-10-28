import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/repositories.dart';
import 'features/lock/lock_screen.dart';
import 'features/lock/tampered_screen.dart';
import 'services/security_service.dart';

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
  bool _tampered = false;
  StreamSubscription<String>? _taps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkTrust());
    unawaited(_recordFirstOpen());
    final notifications = ref.read(notificationServiceProvider);
    _taps = notifications.taps.listen(_openFromNotification);
    unawaited(
      notifications.takeLaunchRoute().then((route) {
        if (route != null) _openFromNotification(route);
      }),
    );
    if (widget.startLocked) {
      unawaited(ref.read(securityServiceProvider).setPrivateWindow(true));
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
      unawaited(ref.read(accountStatusProvider.notifier).refresh());
    }
  }

  /// A re-signed APK (someone unpacked and modified the app) stops here.
  Future<void> _checkTrust() async {
    final trust = await ref.read(securityServiceProvider).appTrust();
    if (trust == AppTrust.tampered && mounted) {
      setState(() => _tampered = true);
    }
  }

  Future<void> _recordFirstOpen() async {
    final kv = ref.read(kvProvider);
    if (await kv.get(KvKeys.firstOpen) == null) {
      await kv.set(KvKeys.firstOpen, DateTime.now().toIso8601String());
    }
  }

  /// Opens the screen a reminder points at ("Morning, Sam" → the morning
  /// checklist), once onboarding state is known so redirects don't eat it.
  Future<void> _openFromNotification(String route) async {
    await ref.read(profileProvider.future);
    await ref.read(accountProvider.future);
    if (!mounted) return;
    final router = ref.read(routerProvider);
    // Tabs are switched to; everything else opens on top.
    route.startsWith('/routine') || route.startsWith('/today')
        ? router.go(route)
        : router.push(route);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _taps?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(purchasesServiceProvider).refresh());
      // Re-plans renewal reminders against today's date.
      ref.invalidate(renewalPlanProvider);
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
    ref.watch(routineRemindersProvider);
    // Renewal reminders follow the subscription; ads start for free users.
    ref.watch(renewalRemindersProvider);
    ref.watch(milestonesProvider);
    ref.watch(expiryRemindersProvider);
    ref.watch(adsBootstrapProvider);
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
              if (_tampered) const Positioned.fill(child: TamperedScreen()),
            ],
          ),
        );
      },
    );
  }
}
