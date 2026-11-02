// Renders real app screens with real fonts and sample data to PNGs, so the
// design can be reviewed without a device:
//
//   flutter test tool/screenshots --update-goldens
//
// Output: design/renders/*.png. Not part of the normal test suite.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:clearskin_ai/core/providers.dart';
import 'package:clearskin_ai/core/theme/app_theme.dart';
import 'package:clearskin_ai/core/widgets/visuals.dart';
import 'package:clearskin_ai/data/models/chat.dart';
import 'package:clearskin_ai/data/models/check_in.dart';
import 'package:clearskin_ai/data/models/product.dart';
import 'package:clearskin_ai/data/models/profile.dart';
import 'package:clearskin_ai/data/models/scan.dart';
import 'package:clearskin_ai/domain/forecast/skin_forecast.dart';
import 'package:clearskin_ai/domain/scan/face_zones.dart';
import 'package:clearskin_ai/domain/scan/skin_maps.dart';
import 'package:clearskin_ai/domain/scan/skin_measure.dart';
import 'package:clearskin_ai/features/auth/auth_screen.dart';
import 'package:clearskin_ai/features/home/get_started.dart';
import 'package:clearskin_ai/features/home/today_screen.dart';
import 'package:clearskin_ai/features/journey/journey_screen.dart';
import 'package:clearskin_ai/features/settings/reminders_screen.dart';
import 'package:clearskin_ai/features/checkin/checkin_screen.dart';
import 'package:clearskin_ai/features/coach/coach_screen.dart';
import 'package:clearskin_ai/features/products/product_detail_screen.dart';
import 'package:clearskin_ai/features/settings/settings_screen.dart';
import 'package:clearskin_ai/features/share/invite_screen.dart';
import 'package:clearskin_ai/services/auth_service.dart';
import 'package:clearskin_ai/services/backend_api.dart';
import 'package:clearskin_ai/domain/premium/renewal.dart';
import 'package:clearskin_ai/domain/routine/routine_engine.dart';
import 'package:clearskin_ai/features/onboarding/medical_disclaimer_screen.dart';
import 'package:clearskin_ai/features/onboarding/onboarding_flow.dart';
import 'package:clearskin_ai/features/share/share_card.dart';
import 'package:clearskin_ai/features/paywall/paywall_screen.dart';
import 'package:clearskin_ai/features/products/shelf_screen.dart';
import 'package:clearskin_ai/features/progress/progress_screen.dart';
import 'package:clearskin_ai/features/routine/routine_screen.dart';
import 'package:clearskin_ai/domain/routine/streaks.dart';
import 'package:clearskin_ai/features/routine/streak_flame.dart';
import 'package:clearskin_ai/features/routine/streak_widgets.dart';
import 'package:clearskin_ai/features/scan/face_map.dart';
import 'package:clearskin_ai/features/scan/scan_result_screen.dart';
import 'package:clearskin_ai/features/scan/skin_lens.dart';
import 'package:clearskin_ai/features/shell/app_shell.dart';
import 'package:clearskin_ai/services/notification_service.dart';
import 'package:clearskin_ai/services/purchases_service.dart';
import 'package:clearskin_ai/services/telemetry.dart';
import 'package:clearskin_ai/features/onboarding/plan_reveal_screen.dart';
import 'package:clearskin_ai/features/tips/tips_widgets.dart';
import 'package:clearskin_ai/domain/guidance/hydration.dart';
import 'package:clearskin_ai/features/guides/guides_screen.dart';
import 'package:clearskin_ai/features/guides/water_screen.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ── Sample data ────────────────────────────────────────────────────────

final _profile = UserProfile(
  name: 'Amara',
  gender: Gender.woman,
  ageRange: AgeRange.a25,
  skinType: SkinType.combination,
  sensitivity: Sensitivity.medium,
  concerns: {Concern.acne, Concern.darkSpots, Concern.texture},
  goals: {Goal.clearSkin, Goal.evenTone},
  complexity: RoutineComplexity.balanced,
  budget: Budget.mid,
  skinTone: SkinTone.v,
  location: const Location(
    name: 'Nairobi, Kenya',
    latitude: -1.29,
    longitude: 36.82,
  ),
  createdAt: DateTime(2026, 9, 1),
);

/// The same person on their second day, when Get started still shows.
final _newProfile = UserProfile(
  name: _profile.name,
  gender: _profile.gender,
  ageRange: _profile.ageRange,
  skinType: _profile.skinType,
  sensitivity: _profile.sensitivity,
  concerns: _profile.concerns,
  goals: _profile.goals,
  complexity: _profile.complexity,
  budget: _profile.budget,
  skinTone: _profile.skinTone,
  location: _profile.location,
  createdAt: _now.subtract(const Duration(days: 1)),
);

SkinAnalysis _analysis(int base) => SkinAnalysis(
  usable: true,
  qualityIssues: const [],
  overallScore: base,
  metrics: [
    MetricScore(
      metric: SkinMetric.acne,
      score: base - 12,
      note: 'A few small blemishes along the jawline.',
    ),
    MetricScore(
      metric: SkinMetric.texture,
      score: base - 4,
      note: 'Mild unevenness on the cheeks.',
    ),
    MetricScore(
      metric: SkinMetric.pores,
      score: base - 6,
      note: 'Pores more visible on the nose.',
    ),
    MetricScore(
      metric: SkinMetric.redness,
      score: base + 6,
      note: 'Very little redness.',
    ),
    MetricScore(
      metric: SkinMetric.pigmentation,
      score: base - 9,
      note: 'Some post-blemish marks on the cheeks.',
    ),
    MetricScore(
      metric: SkinMetric.hydration,
      score: base + 4,
      note: 'Looks well hydrated.',
    ),
    MetricScore(
      metric: SkinMetric.oilBalance,
      score: base - 2,
      note: 'Light shine on the T-zone.',
    ),
    MetricScore(
      metric: SkinMetric.fineLines,
      score: 92,
      note: 'Very few visible lines.',
    ),
    MetricScore(
      metric: SkinMetric.underEyes,
      score: base + 1,
      note: 'Mild, likely genetic, shadowing.',
    ),
  ],
  skinTypeEstimate: 'combination',
  summary: 'Your skin looks healthy and well hydrated. The main focus is calming breakouts along the jaw and fading the marks they leave behind — both respond well to consistent care.',
  strengths: const ['Good hydration', 'Even redness', 'Smooth forehead'],
  priorities: const [
    'Calm jawline breakouts',
    'Fade post-blemish marks',
    'Balance T-zone oil',
  ],
  findings: const [
    Finding(
      title: 'Small inflamed bumps',
      detail: '3–4 papules along the jawline.',
      area: 'jaw',
      severity: 2,
    ),
    Finding(
      title: 'Post-blemish marks',
      detail: 'Flat brown marks where spots healed.',
      area: 'cheeks',
      severity: 2,
    ),
  ],
  recommendedIngredients: const [
    IngredientTip(
      name: 'Azelaic acid',
      why: 'Calms breakouts and fades marks gently.',
    ),
    IngredientTip(name: 'Niacinamide', why: 'Balances oil and evens tone.'),
  ],
  ingredientsToAvoid: const [
    IngredientTip(
      name: 'Coconut oil',
      why: 'Highly pore-clogging for breakout-prone skin.',
    ),
  ],
  redFlags: const [],
  model: 'sample',
  focus: SkinFocus.cure,
  routineAdjustments: const [
    'Move niacinamide to the morning, after toner',
    'Azelaic acid on non-retinoid nights only',
  ],
  ingredientWarnings: const [
    'Don\'t layer adapalene and a strong acid on the same night',
  ],
  recommendedProductTypes: const ['spot_treatment', 'sunscreen', 'moisturizer'],
  beyondProducts: const [
    IngredientTip(
      name: 'Rinse after training',
      why: 'Sweat under a cap strap matches the jawline breakouts; rinse within 30 minutes.',
    ),
    IngredientTip(
      name: 'Pillowcase twice a week',
      why: 'The marks sit on the side you sleep on.',
    ),
  ],
);

// Renders are taken at a fixed moment (a Wednesday morning), so the
// greeting, dates and streaks are the same whenever they're run.
final _now = DateTime(2026, 10, 28, 9, 30);

// A sample selfie with landmarks detected by a real face-landmark model
// (scripts: see tool/screenshots/fixtures/README.md). Test-only; never
// bundled with the app.
final _samplePhoto = File('tool/screenshots/fixtures/sample_face.jpg')
    .absolute
    .path;
final _sampleFace = FaceGeometry.decode(
  File('tool/screenshots/fixtures/sample_face.json').readAsStringSync(),
);

// Newest first, weekly-ish, with the small wobbles real data has.
final _scans = [
  for (final (i, days, score) in [
    (6, 2, 76),
    (5, 9, 73),
    (4, 16, 70),
    (3, 23, 71),
    (2, 30, 67),
    (1, 37, 64),
  ])
    SkinScan(
      id: 's$i',
      createdAt: _now.subtract(Duration(days: days)),
      photoPath: i == 6 ? _samplePhoto : '/none.jpg',
      face: i == 6 || i == 1 ? _sampleFace : null,
      // Day one and today, as the on-device lenses measured them.
      measure: switch (i) {
        6 => const SkinMeasure(
          skinLightness: 66,
          coverage: {
            SkinLens.redness: 0.11,
            SkinLens.tone: 0.08,
            SkinLens.shine: 0.09,
            SkinLens.texture: 0.13,
          },
          zones: {
            SkinLens.redness: {'cheeks': 0.12, 'jaw': 0.16},
            SkinLens.tone: {'cheeks': 0.09},
          },
        ),
        1 => const SkinMeasure(
          skinLightness: 63,
          coverage: {
            SkinLens.redness: 0.19,
            SkinLens.tone: 0.12,
            SkinLens.shine: 0.10,
            SkinLens.texture: 0.15,
          },
          zones: {
            SkinLens.redness: {'cheeks': 0.27, 'jaw': 0.21},
            SkinLens.tone: {'cheeks': 0.16},
          },
        ),
        _ => null,
      },
      analysis: _analysis(score),
      // s6 is what the on-device measurement gives for the sample photo;
      // the earlier ones are a plausible history.
      radiance: i == 6
          ? const Radiance(score: 75, evenness: 74, clarity: 89, sheen: 57)
          : Radiance(
              score: score - 3,
              evenness: score - 4,
              clarity: score + 8,
              sheen: score - 18,
            ),
    ),
];

final _products = [
  Product(
    id: 'p1',
    name: 'Hydrating Cleanser',
    brand: 'CeraVe',
    category: ProductCategory.cleanser,
    usage: ProductUsage.both,
    addedAt: _now,
    ingredientsRaw: 'Water, Glycerin, Cetearyl Alcohol, Ceramide NP, Ceramide AP, Sodium Hyaluronate, Cholesterol, Phenoxyethanol',
  ),
  Product(
    id: 'p2',
    name: 'Azelaic Acid Suspension 10%',
    brand: 'The Ordinary',
    category: ProductCategory.treatment,
    usage: ProductUsage.pm,
    addedAt: _now,
    ingredientsRaw: 'Water, Isodecyl Neopentanoate, Dimethicone, Azelaic Acid, Dimethicone/Bis-Isobutyl PPG-20 Crosspolymer, Polysilicone-11',
  ),
  Product(
    id: 'p3',
    name: 'Daily Fluid SPF 50',
    brand: 'Altruist',
    category: ProductCategory.sunscreen,
    usage: ProductUsage.am,
    addedAt: _now,
    ingredientsRaw: 'Water, Ethylhexyl Salicylate, Bis-Ethylhexyloxyphenol Methoxyphenyl Triazine, Glycerin, Diethylamino Hydroxybenzoyl Hexyl Benzoate, Tocopherol',
  ),
];

// ── Fakes ──────────────────────────────────────────────────────────────

class _Profile extends ProfileNotifier {
  _Profile(this.p);
  final UserProfile? p;
  @override
  Future<UserProfile?> build() async => p;
}

class _Scans extends ScansNotifier {
  _Scans(this.s);
  final List<SkinScan> s;
  @override
  Future<List<SkinScan>> build() async => s;
}

class _Products extends ProductsNotifier {
  @override
  Future<List<Product>> build() async => _products;
}

class _Logs extends RoutineLogsNotifier {
  @override
  Future<List<RoutineLog>> build() async => [
    RoutineLog(
      day: _key(_now),
      slot: RoutineSlot.am,
      completedStepIds: const {'am.cleanse', 'am.niacinamide'},
    ),
  ];

  // In memory only: the recorded ad flows tick steps off.
  @override
  Future<void> toggle(String day, RoutineSlot slot, String stepId) async {
    final logs = state.value ?? const <RoutineLog>[];
    final existing = logs
        .where((l) => l.day == day && l.slot == slot)
        .firstOrNull;
    final steps = {...?existing?.completedStepIds};
    steps.contains(stepId) ? steps.remove(stepId) : steps.add(stepId);
    state = AsyncData([
      RoutineLog(day: day, slot: slot, completedStepIds: steps),
      ...logs.where((l) => !(l.day == day && l.slot == slot)),
    ]);
  }
}

class _CheckIns extends CheckInsNotifier {
  @override
  Future<List<CheckIn>> build() async => const [];
}

class _Chat extends ChatNotifier {
  @override
  Future<ChatState> build() async => const ChatState(messages: <ChatMessage>[]);
}

class _Account extends AccountNotifier {
  @override
  Future<Account?> build() async => null;
}

class _SignedIn extends AccountNotifier {
  @override
  Future<Account?> build() async =>
      const Account(provider: 'google', email: 'amara@example.com');
}

class _Purchases extends PurchasesService {
  @override
  Future<List<Plan>> plans() async => const [
    Plan(
      package: null,
      title: 'Yearly',
      priceString: r'$39.99',
      periodLabel: 'year',
      pricePerWeek: 0.77,
      pricePerWeekString: r'$0.77',
      trialDays: 3,
    ),
    Plan(
      package: null,
      title: 'Monthly',
      priceString: r'$9.99',
      periodLabel: 'month',
      pricePerWeek: 2.31,
      pricePerWeekString: r'$2.31',
    ),
  ];
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ── Harness ────────────────────────────────────────────────────────────

Future<void> _loadFonts() async {
  final jakarta = FontLoader('PlusJakartaSans');
  for (final w in [
    'ExtraLight',
    'Light',
    'Regular',
    'Medium',
    'SemiBold',
    'Bold',
    'ExtraBold',
  ]) {
    jakarta.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-$w.ttf'));
  }
  await jakarta.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

class _Hydration extends HydrationSettingsNotifier {
  @override
  Future<HydrationSettings> build() async =>
      const HydrationSettings(weightKg: 64, heightCm: 168, activeMinutes: 30);
}

class _Water extends WaterTodayNotifier {
  @override
  Future<int> build() async => 3;

  @override
  Future<void> add(int delta) async =>
      state = AsyncData((state.value ?? 0) + delta);
}

Widget _app({
  required String initial,
  required List<RouteBase> routes,
  bool withScans = true,
  UserProfile? profile,
  bool dark = false,
  List<dynamic> extra = const [],
  bool signedIn = false,
}) {
  final router = GoRouter(initialLocation: initial, routes: routes);
  return ProviderScope(
    overrides: [
      profileProvider.overrideWith(() => _Profile(profile ?? _profile)),
      scansProvider.overrideWith(() => _Scans(withScans ? _scans : const [])),
      productsProvider.overrideWith(_Products.new),
      routineLogsProvider.overrideWith(_Logs.new),
      checkInsProvider.overrideWith(_CheckIns.new),
      chatProvider.overrideWith(_Chat.new),
      hydrationSettingsProvider.overrideWith(_Hydration.new),
      waterTodayProvider.overrideWith(_Water.new),
      accountProvider.overrideWith(signedIn ? _SignedIn.new : _Account.new),
      previousOpenProvider.overrideWith(
        (ref) async => _now.subtract(const Duration(hours: 20)),
      ),
      purchasesServiceProvider.overrideWithValue(_Purchases()),
      // No ad network in renders.
      showAdsProvider.overrideWithValue(false),
      getStartedFlagsProvider.overrideWith(
        (ref) async => (hidden: false, invited: false),
      ),
      ...extra.cast(),
      notificationServiceProvider.overrideWithValue(NotificationService()),
      telemetryProvider.overrideWithValue(Telemetry.noop()),
      weatherProvider.overrideWith(
        (ref) async => WeatherSnapshot(
          uvIndexMax: 9,
          humidity: 58,
          temperatureC: 24,
          usAqi: 42,
          fetchedAt: _now,
        ),
      ),
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
    ),
  );
}

List<RouteBase> _shellRoutes() => [
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
          GoRoute(path: '/routine', builder: (_, _) => const RoutineScreen()),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(path: '/progress', builder: (_, _) => const ProgressScreen()),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(path: '/shelf', builder: (_, _) => const ShelfScreen()),
        ],
      ),
    ],
  ),
];

/// Decodes every on-screen image for real; the fake-async test clock never
/// finishes image decoding on its own, which would leave photos blank.
Future<void> _precacheImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      final image = (e.widget as Image).image;
      if (image is FileImage) continue; // warmed before pumping
      await precacheImage(image, e);
    }
  });
}

/// Loads the sample selfie into the image cache in real async time, so
/// Image.file finds it decoded instead of waiting on the fake test clock.
Future<void> _warmSamplePhoto(WidgetTester tester) async {
  await tester.runAsync(() async {
    final stream = FileImage(File(_samplePhoto))
        .resolve(ImageConfiguration.empty);
    final done = Completer<void>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) {
        if (!done.isCompleted) done.complete();
        stream.removeListener(listener);
      },
      onError: (_, _) {
        if (!done.isCompleted) done.complete();
      },
    );
    stream.addListener(listener);
    await done.future;
    // The on-device skin measurement runs in an isolate; finish it here so
    // the face map's lenses are ready when the screen is pumped.
    await SkinLensStore.load(_samplePhoto, _sampleFace!);
  });
}

/// `QA=small` renders every screen on a small phone (320 dp wide) at the
/// largest text size the app allows, without comparing goldens: any layout
/// overflow fails the test. The stress pass testers do by hand.
final _qa = Platform.environment['QA'];

Future<void> _shot(WidgetTester tester, Widget app, String name) =>
    withClock(Clock.fixed(_now), () => _shotNow(tester, app, name));

Future<void> _shotNow(WidgetTester tester, Widget app, String name) async {
  if (_qa == 'small') {
    final tall = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = Size(640, math.max(568, tall) * 2);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  }
  // Real blurred shadows (the test default draws them hard-edged); must be
  // restored before the test body ends.
  debugDisableShadows = false;
  await _warmSamplePhoto(tester);
  await tester.pumpWidget(app);
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (i == 2 || i == 20) await _precacheImages(tester);
  }
  if (_qa == null) {
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../design/renders/$name.png'),
    );
  } else {
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  }
  // Tear down so repeating animations don't leak into the next test.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  debugDisableShadows = true;
}

// ── Recorded flows for the ads ────────────────────────────────────────

/// Set `RECORD=<dir>` to record the app flows the ad renderers in tool/ads
/// cut from: 30 fps PNG frames at 1080×1920, plus where each tap lands.
final _recordDir = Platform.environment['RECORD'];
final _touchDir = Platform.environment['TOUCH'];
const _recW = 390.0;
const _recH = 390.0 * 1920 / 1080;

class _Recorder {
  _Recorder(this.t, this.key, this.dir, {this.height = _recH});
  final WidgetTester t;
  final GlobalKey key;
  final Directory dir;

  /// Logical height of the recorded screen (width is always [_recW]).
  final double height;
  int n = 0;
  final taps = <Map<String, num>>[];

  Future<void> frame() async {
    await t.pump(const Duration(microseconds: 33333));
    await t.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1080 / _recW);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${dir.path}/f_${n.toString().padLeft(5, '0')}.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
    n++;
  }

  Future<void> hold(double seconds) async {
    for (var i = 0; i < (seconds * 30).round(); i++) {
      await frame();
    }
  }

  ScrollPosition get _scroll =>
      t.state<ScrollableState>(find.byType(Scrollable).first).position;

  /// Smooth, eased scroll so the top of [target] sits [margin] below the top.
  Future<void> scrollTo(
    Finder target,
    double seconds, {
    double margin = 80,
  }) async {
    final pos = _scroll;
    final to = (pos.pixels + t.getTopLeft(target).dy - margin).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    final from = pos.pixels;
    final frames = (seconds * 30).round();
    for (var i = 1; i <= frames; i++) {
      final p = i / frames;
      final e = p < 0.5 ? 4 * p * p * p : 1 - math.pow(-2 * p + 2, 3) / 2;
      pos.jumpTo(from + (to - from) * e);
      await frame();
    }
  }

  /// Smooth, eased scroll by [pixels], for content not built yet.
  Future<void> scrollBy(double pixels, double seconds) async {
    final pos = _scroll;
    final from = pos.pixels;
    final to = (from + pixels).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    final frames = (seconds * 30).round();
    for (var i = 1; i <= frames; i++) {
      final p = i / frames;
      final e = p < 0.5 ? 4 * p * p * p : 1 - math.pow(-2 * p + 2, 3) / 2;
      pos.jumpTo(from + (to - from) * e);
      await frame();
    }
  }

  /// Starts the recording already scrolled so [target] sits [margin] down.
  void jumpTo(Finder target, {double margin = 80}) {
    final pos = _scroll;
    pos.jumpTo(
      (pos.pixels + t.getTopLeft(target).dy - margin).clamp(
        pos.minScrollExtent,
        pos.maxScrollExtent,
      ),
    );
  }

  Future<void> tap(Finder f) async {
    final c = t.getCenter(f);
    taps.add({'frame': n, 'x': c.dx / _recW, 'y': c.dy / height});
    await t.tap(f, warnIfMissed: false);
  }
}

Future<void> _record(
  WidgetTester t,
  Widget app,
  String name,
  Future<void> Function(_Recorder r) script, {
  double height = _recH,
}) async {
  debugDisableShadows = false;
  t.view
    ..physicalSize = Size(1080, 1080 * height / _recW)
    ..devicePixelRatio = 1080 / _recW;
  await _warmSamplePhoto(t);
  final key = GlobalKey();
  await t.pumpWidget(RepaintBoundary(key: key, child: app));
  await t.pump();
  await _precacheImages(t);
  final dir = Directory('$_recordDir/$name')..createSync(recursive: true);
  for (final f in dir.listSync()) {
    f.deleteSync();
  }
  final r = _Recorder(t, key, dir, height: height);
  await script(r);
  File('${dir.path}/taps.json').writeAsStringSync(jsonEncode(r.taps));
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
  debugDisableShadows = true;
}

void main() {
  setUpAll(_loadFonts);

  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
  });

  testWidgets('01 welcome', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => const OnboardingFlow())],
        profile: null,
      ),
      '01-welcome',
    );
  });

  testWidgets('02 today', (t) async {
    await _shot(t, _app(initial: '/today', routes: _shellRoutes()), '02-today');
  });

  testWidgets('03 today first run', (t) async {
    await _shot(
      t,
      _app(
        initial: '/today',
        routes: _shellRoutes(),
        withScans: false,
        profile: _newProfile,
      ),
      '03-today-first-run',
    );
  });

  testWidgets('04 routine', (t) async {
    await _shot(
      t,
      _app(initial: '/routine?slot=am', routes: _shellRoutes()),
      '04-routine',
    );
  });

  testWidgets('05 scan report', (t) async {
    await _shot(
      t,
      _app(
        initial: '/scan/s6',
        routes: [
          GoRoute(
            path: '/scan/:id',
            builder: (_, s) =>
                ScanResultScreen(scanId: s.pathParameters['id']!),
          ),
        ],
      ),
      '05-scan-report',
    );
  });

  testWidgets('05b scan report, full length', (t) async {
    t.view.physicalSize = const Size(1170, 7800);
    await _shot(
      t,
      _app(
        initial: '/scan/s6',
        routes: [
          GoRoute(
            path: '/scan/:id',
            builder: (_, s) =>
                ScanResultScreen(scanId: s.pathParameters['id']!),
          ),
        ],
      ),
      '05b-scan-report-full',
    );
  });

  testWidgets('06 paywall', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const PaywallScreen(source: 'onboarding'),
          ),
        ],
      ),
      '06-paywall',
    );
  });

  testWidgets('42 scan report, just scanned', (t) async {
    await _shot(
      t,
      _app(
        initial: '/scan/s6',
        routes: [
          GoRoute(
            path: '/scan/:id',
            builder: (_, s) =>
                ScanResultScreen(scanId: s.pathParameters['id']!, fresh: true),
          ),
        ],
      ),
      '42-scan-report-fresh',
    );
  });

  testWidgets('43 paywall after the first scan', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const PaywallScreen(source: 'first_scan'),
          ),
        ],
      ),
      '43-paywall-first-scan',
    );
  });

  testWidgets('44 paywall from the coach', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const PaywallScreen(source: 'coach'),
          ),
        ],
      ),
      '44-paywall-coach',
    );
  });

  testWidgets('07 shelf', (t) async {
    await _shot(t, _app(initial: '/shelf', routes: _shellRoutes()), '07-shelf');
  });

  testWidgets('08 progress', (t) async {
    await _shot(
      t,
      _app(initial: '/progress', routes: _shellRoutes()),
      '08-progress',
    );
  });

  testWidgets('09 today dark', (t) async {
    await _shot(
      t,
      _app(initial: '/today', routes: _shellRoutes(), dark: true),
      '09-today-dark',
    );
  });

  testWidgets('10 plan reveal', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => PlanRevealScreen(profile: _profile),
          ),
        ],
      ),
      '10-plan-reveal',
    );
  });

  testWidgets('11 tip article', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const TipScreen(tipId: 'pih-deeper-skin'),
          ),
        ],
      ),
      '11-tip',
    );
  });

  testWidgets('12 scan report face map', (t) async {
    await _shot(
      t,
      _app(
        initial: '/scan/s6',
        routes: [
          GoRoute(
            path: '/scan/:id',
            builder: (_, s) => Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 40),
                child: FaceMap(scan: _scans.first),
              ),
            ),
          ),
        ],
      ),
      '12-face-map',
    );
  });

  testWidgets('19 face map lens', (t) async {
    await _shot(
      t,
      _app(
        initial: '/scan/s6',
        routes: [
          GoRoute(
            path: '/scan/:id',
            builder: (_, s) => Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 40),
                child: FaceMap(
                  scan: _scans.first,
                  initialLens: SkinLens.radiance,
                  previousRadiance: _scans[1].radiance,
                ),
              ),
            ),
          ),
        ],
      ),
      '19-face-map-lens',
    );
  });

  testWidgets('13 sign in', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => const AuthScreen())],
      ),
      '13-auth',
    );
  });

  testWidgets('13b create account', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const AuthScreen(mode: AuthMode.create),
          ),
        ],
        profile: null,
      ),
      '13b-create-account',
    );
  });

  testWidgets('14 journey', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => const JourneyScreen())],
      ),
      '14-journey',
    );
  });

  testWidgets('36 routine before the first scan', (t) async {
    await _shot(
      t,
      _app(
        initial: '/routine?slot=am',
        routes: _shellRoutes(),
        withScans: false,
      ),
      '36-routine-first-run',
    );
  });

  testWidgets('37 guides', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => const GuidesScreen())],
      ),
      '37-guides',
    );
  });

  testWidgets('38 guide: kitchen remedies', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const GuideScreen(guideId: 'kitchen'),
          ),
        ],
      ),
      '38-guide-kitchen',
    );
  });

  testWidgets('39 water', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => const WaterScreen())],
      ),
      '39-water',
    );
  });

  testWidgets('15 reminders', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const RemindersScreen()),
        ],
      ),
      '15-reminders',
    );
  });

  testWidgets('40 invite', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => const InviteScreen())],
        signedIn: true,
        extra: [
          referralStatusProvider.overrideWith(
            (_) async => const ReferralStatus(
              code: 'K7QAMX',
              rewarded: 2,
              redeemed: false,
            ),
          ),
        ],
      ),
      '40-invite',
    );
  });

  testWidgets('41 get started', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: GetStartedCard(),
                ),
              ),
            ),
          ),
        ],
        profile: _newProfile,
      ),
      '41-get-started',
    );
  });

  testWidgets('30 settings', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => const SettingsScreen())],
      ),
      '30-settings',
    );
  });

  testWidgets('31 coach', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => const CoachScreen())],
      ),
      '31-coach',
    );
  });

  testWidgets('32 check-in', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => const CheckInScreen())],
      ),
      '32-checkin',
    );
  });

  testWidgets('33 setup question, skin type', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const OnboardingFlow(startAt: 5),
          ),
        ],
        profile: null,
      ),
      '33-setup-skin-type',
    );
  });

  testWidgets('34 setup question, concerns', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const OnboardingFlow(startAt: 7),
          ),
        ],
        profile: null,
      ),
      '34-setup-concerns',
    );
  });

  testWidgets('35 product detail', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const ProductDetailScreen(productId: 'p2'),
          ),
        ],
      ),
      '35-product-detail',
    );
  });

  testWidgets('16 today man first run', (t) async {
    await _shot(
      t,
      _app(
        initial: '/today',
        routes: _shellRoutes(),
        withScans: false,
        profile: _profile.copyWith(
          name: 'Daniel',
          gender: Gender.man,
          shaves: true,
          concerns: {Concern.acne, Concern.razorBumps, Concern.oiliness},
        ),
      ),
      '16-today-man',
    );
  });

  testWidgets('20 medical disclaimer', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const MedicalDisclaimerScreen(),
          ),
        ],
        profile: null,
      ),
      '20-disclaimer',
    );
  });

  // The first scan, pointed at the sample photo so before/after has two.
  final first = SkinScan(
    id: 's1',
    createdAt: _scans.last.createdAt,
    photoPath: _samplePhoto,
    analysis: _scans.last.analysis,
  );
  for (final (style, name) in [
    (CardStyle.score, '21-share-score'),
    (CardStyle.photo, '22-share-photo'),
    (CardStyle.beforeAfter, '23-share-before-after'),
  ]) {
    testWidgets(name, (t) async {
      await _shot(
        t,
        _app(
          initial: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Scaffold(
                backgroundColor: const Color(0xFFE9E6DF),
                body: Center(
                  child: SizedBox(
                    width: 300,
                    child: ResultCard(
                      scan: _scans.first,
                      previous: _scans[1],
                      first: first,
                      style: style,
                      proof: ProgressProof.compare(
                        _scans.last.measure!,
                        _scans.first.measure!,
                        days: 35,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        name,
      );
    });
  }

  testWidgets('24 step guide', (t) async {
    final step = RoutineEngine.build(profile: _profile).pm
        .firstWhere((s) => s.id == 'pm.retinoid');
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => _OpenSheet(step: step),
          ),
        ],
      ),
      '24-step-guide',
    );
  });

  testWidgets('25 today, Premium ending', (t) async {
    await _shot(
      t,
      _app(
        initial: '/today',
        routes: _shellRoutes(),
        extra: [
          renewalPlanProvider.overrideWithValue(
            const RenewalPlan(banner: RenewalBanner.endingSoon, daysLeft: 5),
          ),
        ],
      ),
      '25-today-renewal',
    );
  });

  // 13 of the last 14 days done, with day 6 covered by a streak saver.
  final streakDays = {
    for (var i = 0; i < 14; i++)
      if (i != 6) _key(_now.subtract(Duration(days: 13 - i))),
  };

  testWidgets('26 today with a streak', (t) async {
    await _shot(
      t,
      _app(
        initial: '/today',
        routes: _shellRoutes(),
        extra: [completedDaysProvider.overrideWithValue(streakDays)],
      ),
      '26-today-streak',
    );
  });

  testWidgets('27 streak card', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              backgroundColor: Color(0xFFE9E6DF),
              body: Center(
                child: SizedBox(width: 300, child: StreakCard(days: 14)),
              ),
            ),
          ),
        ],
      ),
      '27-streak-card',
    );
  });

  testWidgets('28 streak extended', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        extra: [completedDaysProvider.overrideWithValue(streakDays)],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              backgroundColor: const Color(0xFF4A4C49),
              body: StreakExtendedCard(
                state: Streaks.compute(streakDays, now: _now),
              ),
            ),
          ),
        ],
      ),
      '28-streak-extended',
    );
  });

  testWidgets('29 streak week, not done today', (t) async {
    final notToday = {...streakDays}..remove(_key(_now));
    await _shot(
      t,
      _app(
        initial: '/',
        extra: [completedDaysProvider.overrideWithValue(notToday)],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: Material(child: StreakWeekSheet()),
              ),
            ),
          ),
        ],
      ),
      '29-streak-week',
    );
  });

  testWidgets('17 journey intro', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => JourneyIntro(onDone: () {}),
          ),
        ],
        profile: null,
      ),
      '17-journey-intro',
    );
  });

  testWidgets('18 day one', (t) async {
    await _shot(
      t,
      _app(
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const BuildingPlanStep(name: 'Amara'),
          ),
        ],
        profile: null,
      ),
      '18-day-one',
    );
  });

  group('ad recordings', skip: _recordDir == null, () {
    testWidgets('report', (t) async {
      await _record(
        t,
        _app(
          initial: '/scan/s6',
          routes: [
            GoRoute(
              path: '/scan/:id',
              builder: (_, s) =>
                  ScanResultScreen(scanId: s.pathParameters['id']!),
            ),
          ],
        ),
        'report',
        (r) async {
          await r.hold(1.8);
          await r.scrollTo(find.byType(FaceMap), 0.9, margin: 40);
          await r.hold(0.4);
          for (final lens in ['Radiance', 'Redness', 'Tone']) {
            await r.tap(
              find.descendant(
                of: find.byType(FaceMap),
                matching: find.text(lens),
              ),
            );
            await r.hold(1.5);
          }
          await r.scrollTo(find.text('BREAKDOWN'), 0.9, margin: 60);
          await r.hold(1.4);
        },
      );
    });

    testWidgets('routine', (t) async {
      await _record(
        t,
        _app(initial: '/routine?slot=am', routes: _shellRoutes()),
        'routine',
        (r) async {
          await r.hold(0.8);
          final open = find.byWidgetPredicate(
            (w) => w is CheckCircle && !w.done,
          );
          for (var i = 0; i < 2; i++) {
            await r.tap(open.first);
            await r.hold(0.6);
          }
          await r.hold(0.6);
        },
      );
    });

    testWidgets('plan', (t) async {
      await _record(
        t,
        _app(
          initial: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => PlanRevealScreen(profile: _profile),
            ),
          ],
        ),
        'plan',
        (r) async {
          await r.hold(1.2);
          await r.scrollTo(find.text('YOUR ROUTINE'), 1.0, margin: 60);
          await r.hold(0.4);
          await r.tap(find.text('Evening'));
          await r.hold(1.0);
        },
      );
    });

    testWidgets('shelf', (t) async {
      await _record(
        t,
        _app(initial: '/shelf', routes: _shellRoutes()),
        'shelf',
        (r) async {
          await r.hold(2.0);
        },
      );
    });

    testWidgets('progress', (t) async {
      await _record(
        t,
        _app(initial: '/progress', routes: _shellRoutes()),
        'progress',
        (r) async {
          await r.hold(0.4);
          await r.tap(find.text('Radiance'));
          await r.hold(1.8);
        },
      );
    });
  });

  // Phone-shaped (390×844, a modern phone's screen) flows for ad 14, which
  // puts them on real phones in real hands. Nothing here shows the render
  // fixture's face: it has no model release.
  group('ad recordings, phone-shaped', skip: _recordDir == null, () {
    const h = 844.0;
    Future<void> rec(
      WidgetTester t,
      Widget app,
      String name,
      Future<void> Function(_Recorder r) script,
    ) => _record(t, app, 'phone/$name', script, height: h);

    testWidgets('today', (t) async {
      await rec(t, _app(initial: '/today', routes: _shellRoutes()), 'today', (
        r,
      ) async {
        await r.hold(1.6);
        await r.scrollBy(760, 1.6);
        await r.hold(0.5);
        await r.tap(find.text('Add a glass'));
        await r.hold(1.2);
      });
    });

    testWidgets('report', (t) async {
      await rec(
        t,
        _app(
          initial: '/scan/s6',
          routes: [
            GoRoute(
              path: '/scan/:id',
              builder: (_, s) =>
                  ScanResultScreen(scanId: s.pathParameters['id']!),
            ),
          ],
        ),
        'report',
        (r) async => r.hold(2.6),
      );
    });

    testWidgets('breakdown', (t) async {
      await rec(
        t,
        _app(
          initial: '/scan/s6',
          routes: [
            GoRoute(
              path: '/scan/:id',
              builder: (_, s) =>
                  ScanResultScreen(scanId: s.pathParameters['id']!),
            ),
          ],
        ),
        'breakdown',
        (r) async {
          r.jumpTo(find.text('BREAKDOWN'), margin: 120);
          await r.hold(1.0);
          await r.scrollTo(find.text('YOUR POTENTIAL'), 1.6, margin: 140);
          await r.hold(0.8);
        },
      );
    });

    testWidgets('routine', (t) async {
      await rec(
        t,
        _app(initial: '/routine?slot=am', routes: _shellRoutes()),
        'routine',
        (r) async {
          await r.hold(0.9);
          final open = find.byWidgetPredicate(
            (w) => w is CheckCircle && !w.done,
          );
          for (var i = 0; i < 3; i++) {
            await r.tap(open.first);
            await r.hold(0.7);
          }
          await r.hold(0.8);
        },
      );
    });

    testWidgets('reminders', (t) async {
      await rec(
        t,
        _app(
          initial: '/',
          profile: _profile.copyWith(
            reminders: _profile.reminders.copyWith(alarm: true),
          ),
          routes: [
            GoRoute(path: '/', builder: (_, _) => const RemindersScreen()),
          ],
        ),
        'reminders',
        (r) async => r.hold(2.4),
      );
    });

    testWidgets('guides', (t) async {
      await rec(
        t,
        _app(
          initial: '/',
          routes: [GoRoute(path: '/', builder: (_, _) => const GuidesScreen())],
        ),
        'guides',
        (r) async {
          await r.hold(1.0);
          await r.scrollTo(find.text('Water and your skin'), 1.6, margin: 300);
          await r.hold(0.8);
        },
      );
    });

    testWidgets('kitchen', (t) async {
      await rec(
        t,
        _app(
          initial: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const GuideScreen(guideId: 'kitchen'),
            ),
          ],
        ),
        'kitchen',
        (r) async {
          await r.hold(0.8);
          await r.scrollBy(1500, 2.4);
          await r.hold(1.4);
        },
      );
    });

    testWidgets('water', (t) async {
      await rec(
        t,
        _app(
          initial: '/',
          routes: [GoRoute(path: '/', builder: (_, _) => const WaterScreen())],
        ),
        'water',
        (r) async {
          await r.hold(0.9);
          for (var i = 0; i < 2; i++) {
            await r.tap(find.text('Add a glass'));
            await r.hold(0.8);
          }
        },
      );
    });

    testWidgets('progress', (t) async {
      await rec(
        t,
        _app(initial: '/progress', routes: _shellRoutes()),
        'progress',
        (r) async {
          await r.hold(0.6);
          await r.tap(find.text('Radiance'));
          await r.hold(1.8);
        },
      );
    });
  });

  // Ad 14's touched phones: the finger in each stock clip (tool/ads/motion
  // fingers.py, touch.py) replayed as real touch gestures, one plate frame
  // per recorded frame, so the app scrolls and flings under that finger.
  // Set TOUCH=<dir of touch/*.json>; frames go to RECORD/phone/follow/<name>.
  group(
    'ad recordings, following a finger',
    skip: _recordDir == null || _touchDir == null,
    () {
      final List<File> touched = _touchDir == null
          ? const []
          : Directory(_touchDir!).listSync().whereType<File>().toList();
      for (final file in touched) {
        final name = file.uri.pathSegments.last.replaceAll('.json', '');
        testWidgets(name, (t) async {
          final spec =
              jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
          final initial = switch (spec['screen']) {
            'today' => '/today',
            'routine' => '/routine?slot=am',
            'progress' => '/progress',
            final s => throw ArgumentError('no screen $s'),
          };
          await _record(
            t,
            _app(initial: initial, routes: _shellRoutes()),
            'phone/follow/$name',
            (r) async {
              await r.hold(0.8); // the screen's own entrance
              TestGesture? finger;
              for (final p in spec['touch'] as List) {
                if (p != null) {
                  final at = Offset(
                    (p[0] as num).toDouble(),
                    (p[1] as num).toDouble(),
                  );
                  if (finger == null) {
                    finger = await t.startGesture(at);
                  } else {
                    await finger.moveTo(at);
                  }
                } else if (finger != null) {
                  await finger.up();
                  finger = null;
                }
                await r.frame();
              }
              await finger?.up();
            },
            height: 844,
          );
        });
      }
    },
  );
}

/// Opens a routine step's detail sheet over the routine, as a tap would.
class _OpenSheet extends StatefulWidget {
  const _OpenSheet({required this.step});
  final RoutineStep step;

  @override
  State<_OpenSheet> createState() => _OpenSheetState();
}

class _OpenSheetState extends State<_OpenSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => showStepSheet(context, widget.step),
    );
  }

  @override
  Widget build(BuildContext context) => const RoutineScreen();
}
