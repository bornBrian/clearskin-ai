import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/dates.dart';
import '../data/db/app_database.dart';
import '../data/models/chat.dart';
import '../data/models/check_in.dart';
import '../data/models/product.dart';
import '../data/models/profile.dart';
import '../data/models/scan.dart';
import '../data/repositories/repositories.dart';
import '../domain/forecast/skin_forecast.dart';
import '../domain/ingredients/conflict_checker.dart';
import '../domain/insights/insights_engine.dart';
import '../domain/journey/journey_engine.dart';
import '../domain/nudges/nudge_engine.dart';
import '../domain/routine/routine_engine.dart';
import '../domain/routine/streaks.dart';
import '../domain/scan/skin_maps.dart';
import '../services/auth_service.dart';
import '../services/backend_api.dart';
import '../services/device_services.dart';
import '../services/notification_service.dart';
import '../services/photo_service.dart';
import '../services/product_lookup_service.dart';
import '../services/purchases_service.dart';
import '../services/telemetry.dart';
import '../services/weather_service.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

// ── Infrastructure (overridden in main with initialised instances) ─────

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('Override in main()'),
);
final purchasesServiceProvider = Provider<PurchasesService>(
  (ref) => throw UnimplementedError('Override in main()'),
);
final telemetryProvider = Provider<Telemetry>(
  (ref) => throw UnimplementedError('Override in main()'),
);
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError('Override in main()'),
);

final kvProvider = Provider(
  (ref) => KeyValueStore(ref.watch(databaseProvider)),
);
final profileRepoProvider = Provider(
  (ref) => ProfileRepository(ref.watch(kvProvider)),
);
final scanRepoProvider = Provider(
  (ref) => ScanRepository(ref.watch(databaseProvider)),
);
final checkInRepoProvider = Provider(
  (ref) => CheckInRepository(ref.watch(databaseProvider)),
);
final routineLogRepoProvider = Provider(
  (ref) => RoutineLogRepository(ref.watch(databaseProvider)),
);
final productRepoProvider = Provider(
  (ref) => ProductRepository(ref.watch(databaseProvider)),
);
final chatRepoProvider = Provider(
  (ref) => ChatRepository(ref.watch(databaseProvider)),
);

final backendApiProvider = Provider((ref) => BackendApi());
final weatherServiceProvider = Provider(
  (ref) => WeatherService(ref.watch(kvProvider)),
);
final productLookupProvider = Provider((ref) => ProductLookupService());
final photoServiceProvider = Provider((ref) {
  final s = PhotoService();
  ref.onDispose(s.dispose);
  return s;
});
final ocrServiceProvider = Provider((ref) {
  final s = OcrService();
  ref.onDispose(s.dispose);
  return s;
});
final appLockServiceProvider = Provider((ref) => AppLockService());
final reviewServiceProvider = Provider(
  (ref) => ReviewService(ref.watch(kvProvider)),
);
final exportServiceProvider = Provider(
  (ref) => ExportService(
    profile: ref.watch(profileRepoProvider),
    scans: ref.watch(scanRepoProvider),
    checkIns: ref.watch(checkInRepoProvider),
    products: ref.watch(productRepoProvider),
    logs: ref.watch(routineLogRepoProvider),
  ),
);

// ── Account ────────────────────────────────────────────────────────────

final authServiceProvider = Provider(
  (ref) => AuthService(ref.watch(kvProvider)),
);

class AccountNotifier extends AsyncNotifier<Account?> {
  @override
  Future<Account?> build() => ref.read(authServiceProvider).current();

  /// Signs [a] in on this phone: remembers the account and marks the skin
  /// data here as theirs. Check [ownerOfLocalData] first — data that belongs
  /// to someone else must be erased, never handed over.
  Future<void> set(Account? a) async {
    if (a != null) {
      final kv = ref.read(kvProvider);
      await kv.setJson(KvKeys.account, a.toJson());
      await kv.set(KvKeys.dataOwner, a.key);
    }
    state = AsyncData(a);
  }

  /// The account key the skin data on this phone belongs to, or null when
  /// there is no data, or it predates accounts (then it's whoever signs in).
  Future<String?> ownerOfLocalData() async {
    final hasProfile = await ref.read(profileProvider.future) != null;
    final hasScans = (await ref.read(scansProvider.future)).isNotEmpty;
    if (!hasProfile && !hasScans) return null;
    return ref.read(kvProvider).get(KvKeys.dataOwner);
  }

  Future<void> signOut() async {
    await ref.read(authServiceProvider).signOut();
    state = const AsyncData(null);
  }
}

final accountProvider = AsyncNotifierProvider<AccountNotifier, Account?>(
  AccountNotifier.new,
);

// ── Premium ────────────────────────────────────────────────────────────

class PremiumNotifier extends Notifier<bool> {
  StreamSubscription<bool>? _sub;

  @override
  bool build() {
    final svc = ref.watch(purchasesServiceProvider);
    _sub = svc.premiumChanges.listen((v) => state = v);
    ref.onDispose(() => _sub?.cancel());
    return svc.isPremium;
  }
}

final premiumProvider = NotifierProvider<PremiumNotifier, bool>(
  PremiumNotifier.new,
);

/// Free-tier limits. The server enforces AI limits independently; these
/// drive the UI so users see the paywall before a wasted request.
abstract final class FreeLimits {
  static const lifetimeScans = 1;
  static const productChecksPerDay = 3;
}

// ── Profile ────────────────────────────────────────────────────────────

class ProfileNotifier extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() => ref.read(profileRepoProvider).load();

  Future<void> save(UserProfile profile) async {
    await ref.read(profileRepoProvider).save(profile);
    state = AsyncData(profile);
    unawaited(
      ref
          .read(notificationServiceProvider)
          .scheduleRoutineReminders(
            profile,
            routine: ref.read(routineProvider),
          ),
    );
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, UserProfile?>(
  ProfileNotifier.new,
);

// ── Scans ──────────────────────────────────────────────────────────────

class ScansNotifier extends AsyncNotifier<List<SkinScan>> {
  @override
  Future<List<SkinScan>> build() => ref.read(scanRepoProvider).all();

  Future<void> add(SkinScan scan) async {
    await ref.read(scanRepoProvider).insert(scan);
    final current = state.value ?? const [];
    state = AsyncData([scan, ...current]);
  }

  Future<void> remove(String id) async {
    await ref.read(scanRepoProvider).delete(id);
    state = AsyncData([...?state.value?.where((s) => s.id != id)]);
  }

  Future<void> saveRadiance(String id, Radiance r) async {
    await ref.read(scanRepoProvider).setRadiance(id, r);
    state = AsyncData([
      for (final s in state.value ?? const <SkinScan>[])
        s.id == id ? s.withRadiance(r) : s,
    ]);
  }
}

final scansProvider = AsyncNotifierProvider<ScansNotifier, List<SkinScan>>(
  ScansNotifier.new,
);

/// Scans that can be trusted for trends (good photo quality), newest first.
final usableScansProvider = Provider<List<SkinScan>>(
  (ref) => (ref.watch(scansProvider).value ?? const [])
      .where((s) => s.analysis.usable)
      .toList(),
);

final latestScanProvider = Provider<SkinScan?>(
  (ref) => ref.watch(usableScansProvider).firstOrNull,
);

// ── Products ───────────────────────────────────────────────────────────

class ProductsNotifier extends AsyncNotifier<List<Product>> {
  @override
  Future<List<Product>> build() => ref.read(productRepoProvider).all();

  Future<void> upsert(Product p) async {
    await ref.read(productRepoProvider).upsert(p);
    final rest = (state.value ?? const []).where((x) => x.id != p.id);
    state = AsyncData([p, ...rest]);
  }

  Future<void> remove(String id) async {
    await ref.read(productRepoProvider).delete(id);
    state = AsyncData([...?state.value?.where((p) => p.id != id)]);
  }
}

final productsProvider = AsyncNotifierProvider<ProductsNotifier, List<Product>>(
  ProductsNotifier.new,
);

final conflictsProvider = Provider<List<RoutineConflict>>((ref) {
  final products = ref.watch(productsProvider).value ?? const [];
  final profile = ref.watch(profileProvider).value;
  return ConflictChecker.check(products, profile);
});

// ── Routine ────────────────────────────────────────────────────────────

final routineProvider = Provider<Routine?>((ref) {
  final profile = ref.watch(profileProvider).value;
  if (profile == null) return null;
  return RoutineEngine.build(
    profile: profile,
    latest: ref.watch(latestScanProvider)?.analysis,
    shelf: ref.watch(productsProvider).value ?? const [],
  );
});

class RoutineLogsNotifier extends AsyncNotifier<List<RoutineLog>> {
  @override
  Future<List<RoutineLog>> build() => ref.read(routineLogRepoProvider).all();

  Future<void> toggle(String day, RoutineSlot slot, String stepId) async {
    final logs = state.value ?? const <RoutineLog>[];
    final existing = logs
        .where((l) => l.day == day && l.slot == slot)
        .firstOrNull;
    final steps = {...?existing?.completedStepIds};
    steps.contains(stepId) ? steps.remove(stepId) : steps.add(stepId);
    final updated = RoutineLog(day: day, slot: slot, completedStepIds: steps);
    await ref.read(routineLogRepoProvider).upsert(updated);
    state = AsyncData([
      updated,
      ...logs.where((l) => !(l.day == day && l.slot == slot)),
    ]);
  }
}

final routineLogsProvider =
    AsyncNotifierProvider<RoutineLogsNotifier, List<RoutineLog>>(
      RoutineLogsNotifier.new,
    );

/// Completed step ids for a slot today.
final todayCompletedProvider = Provider.family<Set<String>, RoutineSlot>((
  ref,
  slot,
) {
  final today = Dates.today();
  return ref
          .watch(routineLogsProvider)
          .value
          ?.where((l) => l.day == today && l.slot == slot)
          .firstOrNull
          ?.completedStepIds ??
      const {};
});

/// Days on which every required step of at least one slot was completed.
final completedDaysProvider = Provider<Set<String>>((ref) {
  final routine = ref.watch(routineProvider);
  final logs = ref.watch(routineLogsProvider).value ?? const [];
  if (routine == null) return const {};
  final days = <String>{};
  for (final log in logs) {
    final date = Dates.parseDay(log.day);
    final required = routine
        .stepsFor(log.slot, date)
        .where((s) => !s.optional)
        .map((s) => s.id)
        .toSet();
    if (required.isNotEmpty && log.completedStepIds.containsAll(required)) {
      days.add(log.day);
    }
  }
  return days;
});

final streakProvider = Provider<int>(
  (ref) => Streaks.current(ref.watch(completedDaysProvider)),
);

// ── Check-ins & insights ───────────────────────────────────────────────

class CheckInsNotifier extends AsyncNotifier<List<CheckIn>> {
  @override
  Future<List<CheckIn>> build() => ref.read(checkInRepoProvider).all();

  Future<void> save(CheckIn c) async {
    await ref.read(checkInRepoProvider).upsert(c);
    final rest = (state.value ?? const []).where((x) => x.day != c.day);
    state = AsyncData([c, ...rest]..sort((a, b) => b.day.compareTo(a.day)));
  }
}

final checkInsProvider = AsyncNotifierProvider<CheckInsNotifier, List<CheckIn>>(
  CheckInsNotifier.new,
);

final todayCheckInProvider = Provider<CheckIn?>((ref) {
  final today = Dates.today();
  return ref
      .watch(checkInsProvider)
      .value
      ?.where((c) => c.day == today)
      .firstOrNull;
});

final insightsProvider = Provider<InsightsReport>(
  (ref) =>
      InsightsEngine.analyze(ref.watch(checkInsProvider).value ?? const []),
);

// ── Weather forecast ───────────────────────────────────────────────────

final weatherProvider = FutureProvider<WeatherSnapshot?>((ref) async {
  final loc = ref.watch(profileProvider.select((p) => p.value?.location));
  if (loc == null) return null;
  return ref.read(weatherServiceProvider).today(loc);
});

final forecastProvider = Provider<SkinForecast?>((ref) {
  final w = ref.watch(weatherProvider).value;
  if (w == null) return null;
  return SkinForecaster.build(w, ref.watch(profileProvider).value);
});

// ── Coach chat ─────────────────────────────────────────────────────────

class ChatState {
  const ChatState({required this.messages, this.sending = false, this.error});
  final List<ChatMessage> messages;
  final bool sending;
  final String? error;
}

class ChatNotifier extends AsyncNotifier<ChatState> {
  @override
  Future<ChatState> build() async =>
      ChatState(messages: await ref.read(chatRepoProvider).all());

  Future<void> send(String text) async {
    final trimmed = text.trim();
    final current = state.value;
    if (trimmed.isEmpty || current == null || current.sending) return;

    final profile = ref.read(profileProvider).value;
    if (profile == null) return;

    final userMsg = ChatMessage(
      id: newId(),
      role: ChatRole.user,
      text: trimmed,
      createdAt: DateTime.now(),
    );
    await ref.read(chatRepoProvider).insert(userMsg);
    final history = [...current.messages, userMsg];
    state = AsyncData(ChatState(messages: history, sending: true));
    ref.read(telemetryProvider).track(Ev.coachMessageSent, {
      'turn': history.length,
    });

    try {
      final routine = ref.read(routineProvider);
      final reply = await ref
          .read(backendApiProvider)
          .coachReply(
            history: history,
            profile: profile,
            latestScan: ref.read(latestScanProvider)?.analysis,
            routineSummary: [
              if (routine != null) ...[
                for (final s in routine.am) 'AM: ${s.title}',
                for (final s in routine.pm)
                  'PM: ${s.title}${s.days.isEmpty ? '' : ' (${s.days.length}x/week)'}',
              ],
            ],
            shelf: [
              for (final p
                  in ref.read(productsProvider).value ?? const <Product>[])
                if (p.status == ProductStatus.active)
                  '${p.displayName} (${p.category.label}, ${p.usage.label})',
            ],
          );
      final botMsg = ChatMessage(
        id: newId(),
        role: ChatRole.assistant,
        text: reply,
        createdAt: DateTime.now(),
      );
      await ref.read(chatRepoProvider).insert(botMsg);
      state = AsyncData(ChatState(messages: [...history, botMsg]));
    } on ApiException catch (e) {
      state = AsyncData(ChatState(messages: history, error: e.message));
    }
  }

  Future<void> clear() async {
    await ref.read(chatRepoProvider).clear();
    state = const AsyncData(ChatState(messages: []));
  }
}

final chatProvider = AsyncNotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);

// ── Free-tier usage counters ───────────────────────────────────────────

class ProductQuota {
  ProductQuota(this._kv);
  final KeyValueStore _kv;

  Future<int> usedToday() async {
    final j = await _kv.getJson(KvKeys.productQuota);
    if (j == null || j['day'] != Dates.today()) return 0;
    return (j['count'] as num).toInt();
  }

  Future<void> increment() async {
    final used = await usedToday();
    await _kv.setJson(KvKeys.productQuota, {
      'day': Dates.today(),
      'count': used + 1,
    });
  }
}

final productQuotaProvider = Provider(
  (ref) => ProductQuota(ref.watch(kvProvider)),
);

// ── Journey, alerts & reminders ────────────────────────────────────────

final journeyProvider = Provider<Journey?>((ref) {
  final profile = ref.watch(profileProvider).value;
  if (profile == null) return null;
  return JourneyEngine.build(
    profile: profile,
    usableScans: ref.watch(usableScansProvider),
  );
});

/// When the app was last opened before this session. Read once per launch;
/// the stored value is moved to "now" at the same time.
final previousOpenProvider = FutureProvider<DateTime?>((ref) async {
  final kv = ref.read(kvProvider);
  final raw = await kv.get(KvKeys.lastOpen);
  await kv.set(KvKeys.lastOpen, DateTime.now().toIso8601String());
  return raw == null ? null : DateTime.tryParse(raw);
});

final nudgesProvider = Provider<List<Nudge>>((ref) {
  final profile = ref.watch(profileProvider).value;
  if (profile == null) return const [];
  return NudgeEngine.pick(
    NudgeContext(
      now: DateTime.now(),
      profile: profile,
      routine: ref.watch(routineProvider),
      amDone: ref.watch(todayCompletedProvider(RoutineSlot.am)),
      pmDone: ref.watch(todayCompletedProvider(RoutineSlot.pm)),
      completedDays: ref.watch(completedDaysProvider),
      streak: ref.watch(streakProvider),
      lastScanAt: ref.watch(latestScanProvider)?.createdAt,
      previousOpenAt: ref.watch(previousOpenProvider).value,
      checkedInToday: ref.watch(todayCheckInProvider) != null,
      uvIndex: ref.watch(weatherProvider).value?.uvIndexMax.round(),
      journey: ref.watch(journeyProvider),
    ),
  );
});

/// Keeps smart alerts (streak, UV, come-back) planned against the latest
/// state. Watched once from the app root.
final smartAlertsProvider = Provider<void>((ref) {
  final profile = ref.watch(profileProvider).value;
  if (profile == null) return;
  unawaited(
    ref
        .read(notificationServiceProvider)
        .scheduleSmartAlerts(
          profile: profile,
          routineDoneToday: ref
              .watch(completedDaysProvider)
              .contains(Dates.today()),
          streak: ref.watch(streakProvider),
          uvIndex: ref.watch(weatherProvider).value?.uvIndexMax.round(),
        ),
  );
});

/// Wipes local data and resets every in-memory provider.
Future<void> wipeAllLocalData(WidgetRef ref) async {
  await ref.read(databaseProvider).clearAll();
  await ref.read(photoServiceProvider).deleteAllPhotos();
  await ref.read(notificationServiceProvider).cancelAll();
  ref.invalidate(profileProvider);
  ref.invalidate(scansProvider);
  ref.invalidate(productsProvider);
  ref.invalidate(routineLogsProvider);
  ref.invalidate(checkInsProvider);
  ref.invalidate(chatProvider);
  ref.invalidate(weatherProvider);
  ref.invalidate(accountProvider);
}
