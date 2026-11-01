import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/product.dart';
import '../../data/models/profile.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/checkin/checkin_screen.dart';
import '../../features/coach/coach_screen.dart';
import '../../features/home/today_screen.dart';
import '../../features/journey/journey_screen.dart';
import '../../features/guides/guides_screen.dart';
import '../../features/guides/water_screen.dart';
import '../../features/onboarding/medical_disclaimer_screen.dart';
import '../../features/onboarding/onboarding_flow.dart';
import '../../features/onboarding/plan_reveal_screen.dart';
import '../../features/tips/tips_widgets.dart';
import '../../features/paywall/paywall_screen.dart';
import '../../features/products/barcode_scanner_screen.dart';
import '../../features/products/product_detail_screen.dart';
import '../../features/products/product_review_screen.dart';
import '../../features/products/shelf_screen.dart';
import '../../features/progress/compare_screen.dart';
import '../../features/progress/progress_screen.dart';
import '../../features/routine/routine_screen.dart';
import '../../features/scan/scan_capture_screen.dart';
import '../../features/scan/scan_result_screen.dart';
import '../../features/share/invite_screen.dart';
import '../../features/settings/edit_profile_screen.dart';
import '../../features/settings/reminders_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/app_shell.dart';
import '../providers.dart';
import '../theme/tokens.dart';
import '../widgets/widgets.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects when onboarding completes, data is wiped, or the
  // person signs in or out.
  final refresh = ValueNotifier<int>(0);
  ref.listen(profileProvider, (_, _) => refresh.value++);
  ref.listen(accountProvider, (prev, next) {
    // Signing in happens on top of setup and needs no redirect. Refreshing
    // then would rebuild the sign-in page while it finishes, so it never
    // closes and the person lands on "Continue with" again.
    final signedIn =
        prev != null &&
        !prev.isLoading &&
        prev.value == null &&
        next.value != null;
    if (!signedIn) refresh.value++;
  });
  ref.listen(disclaimerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/today',
    refreshListenable: refresh,
    redirect: (context, state) {
      final profile = ref.read(profileProvider);
      final account = ref.read(accountProvider);
      final disclaimer = ref.read(disclaimerProvider);
      final atLoading = state.matchedLocation == '/loading';
      if (profile.isLoading || account.isLoading || disclaimer.isLoading) {
        return atLoading ? null : '/loading';
      }
      // The medical disclaimer comes before everything, for new and
      // existing users alike, and again whenever its wording changes.
      final atDisclaimer = state.matchedLocation == '/disclaimer';
      if (disclaimer.value != true) return atDisclaimer ? null : '/disclaimer';
      // The app belongs to an account: signed out, everyone starts at the
      // welcome screen. Their scans stay on the phone for when they're back.
      final onboarded = profile.value != null && account.value != null;
      if (atLoading || atDisclaimer) {
        return onboarded ? '/today' : '/onboarding';
      }
      final atOnboarding = state.matchedLocation == '/onboarding';
      // The plan reveal, account and paywall screens are part of onboarding.
      final atPaywall =
          state.matchedLocation == '/paywall' ||
          state.matchedLocation == '/plan' ||
          state.matchedLocation == '/auth';
      if (!onboarded && !atOnboarding && !atPaywall) return '/onboarding';
      if (onboarded && atOnboarding) return '/today';
      return null;
    },
    routes: [
      GoRoute(
        path: '/loading',
        // Continues the native launch screen exactly: charcoal, the mark
        // centred, so the handoff to the app is seamless.
        builder: (_, _) => const Scaffold(
          backgroundColor: BrandColors.charcoal,
          body: Center(child: BrandMark(size: 112, color: BrandColors.cream)),
        ),
      ),
      GoRoute(
        path: '/disclaimer',
        builder: (_, _) => const MedicalDisclaimerScreen(),
      ),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingFlow()),
      GoRoute(
        path: '/plan',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            PlanRevealScreen(profile: state.extra! as UserProfile),
      ),
      GoRoute(
        path: '/paywall',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, state) => MaterialPage(
          fullscreenDialog: true,
          child: PaywallScreen(
            source: state.uri.queryParameters['source'] ?? 'unknown',
          ),
        ),
      ),
      GoRoute(
        path: '/auth',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, state) => MaterialPage(
          fullscreenDialog: true,
          child: AuthScreen(
            mode: switch (state.uri.queryParameters['mode']) {
              'signin' => AuthMode.signIn,
              'create' => AuthMode.create,
              _ => AuthMode.save,
            },
          ),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/today', builder: (_, _) => const TodayScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/routine',
                builder: (_, _) => const RoutineScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/progress',
                builder: (_, _) => const ProgressScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/shelf', builder: (_, _) => const ShelfScreen()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/scan',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, _) => const MaterialPage(
          fullscreenDialog: true,
          child: ScanCaptureScreen(),
        ),
      ),
      GoRoute(
        path: '/scan/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => ScanResultScreen(
          scanId: state.pathParameters['id']!,
          fresh: state.uri.queryParameters['fresh'] == '1',
        ),
      ),
      GoRoute(
        path: '/compare',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const CompareScreen(),
      ),
      GoRoute(
        path: '/checkin',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, _) =>
            const MaterialPage(fullscreenDialog: true, child: CheckInScreen()),
      ),
      GoRoute(
        path: '/coach',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const CoachScreen(),
      ),
      GoRoute(
        path: '/barcode',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const BarcodeScannerScreen(),
      ),
      GoRoute(
        path: '/product/review',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => ProductReviewScreen(
          draft: state.extra as ProductDraft? ?? const ProductDraft(),
        ),
      ),
      GoRoute(
        path: '/product/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            ProductDetailScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/guides',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const GuidesScreen(),
      ),
      GoRoute(
        path: '/guide/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            GuideScreen(guideId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/water',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const WaterScreen(),
      ),
      GoRoute(
        path: '/tip/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => TipScreen(tipId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/journey',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const JourneyScreen(),
      ),
      GoRoute(
        path: '/settings/reminders',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const RemindersScreen(),
      ),
      GoRoute(
        path: '/invite',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const InviteScreen(),
      ),
      GoRoute(
        path: '/settings/profile',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const EditProfileScreen(),
      ),
    ],
  );
});
