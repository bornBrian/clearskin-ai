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
import 'package:clearskin_ai/features/home/today_screen.dart';
import 'package:clearskin_ai/features/journey/journey_screen.dart';
import 'package:clearskin_ai/features/settings/reminders_screen.dart';
import 'package:clearskin_ai/features/checkin/checkin_screen.dart';
import 'package:clearskin_ai/features/coach/coach_screen.dart';
import 'package:clearskin_ai/features/products/product_detail_screen.dart';
import 'package:clearskin_ai/features/settings/settings_screen.dart';
import 'package:clearskin_ai/services/auth_service.dart';
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

Widget _app({
  required String initial,
  required List<RouteBase> routes,
  bool withScans = true,
  UserProfile? profile,
  bool dark = false,
  List<dynamic> extra = const [],
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
      accountProvider.overrideWith(_Account.new),
      previousOpenProvider.overrideWith(
        (ref) async => _now.subtract(const Duration(hours: 20)),
      ),
      purchasesServiceProvider.overrideWithValue(_Purchases()),
      // No ad network in renders.
      showAdsProvider.overrideWithValue(false),
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

Future<void> _shot(
  WidgetTester tester,
  Widget app,
  String name, {
  DateTime? at,
}) => withClock(Clock.fixed(at ?? _now), () => _shotNow(tester, app, name));

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
const _recW = 390.0;
const _recH = 390.0 * 1920 / 1080;

class _Recorder {
  _Recorder(this.t, this.key, this.dir);
  final WidgetTester t;
  final GlobalKey key;
  final Directory dir;
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

  Future<void> tap(Finder f) async {
    final c = t.getCenter(f);
    taps.add({'frame': n, 'x': c.dx / _recW, 'y': c.dy / _recH});
    await t.tap(f, warnIfMissed: false);
  }
}

Future<void> _record(
  WidgetTester t,
  Widget app,
  String name,
  Future<void> Function(_Recorder r) script,
) async {
  debugDisableShadows = false;
  t.view
    ..physicalSize = const Size(1080, 1920)
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
  final r = _Recorder(t, key, dir);
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
      _app(initial: '/today', routes: _shellRoutes(), withScans: false),
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
      // A second later: the sign-in screen's other portrait.
      at: _now.add(const Duration(seconds: 1)),
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
