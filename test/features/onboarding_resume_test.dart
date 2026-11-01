import 'package:clearskin_ai/services/telemetry.dart';
import 'package:clearskin_ai/core/providers.dart';
import 'package:clearskin_ai/core/theme/app_theme.dart';
import 'package:clearskin_ai/data/repositories/repositories.dart';
import 'package:clearskin_ai/features/onboarding/onboarding_flow.dart';
import 'package:clearskin_ai/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The key-value store in memory.
class _MemoryKv implements KeyValueStore {
  final values = <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>?> getJson(String key) async => values[key];

  @override
  Future<void> setJson(String key, Map<String, Object?> value) async =>
      values[key] = Map<String, dynamic>.from(value);

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<String?> get(String key) async => null;

  @override
  Future<void> set(String key, String value) async {}
}

class _SignedIn extends AccountNotifier {
  @override
  Future<Account?> build() async =>
      const Account(provider: 'google', email: 'amara@example.com');
}

class _SignedOut extends AccountNotifier {
  @override
  Future<Account?> build() async => null;
}

Future<void> _pump(
  WidgetTester t,
  _MemoryKv kv,
  AccountNotifier account,
) async {
  final container = ProviderContainer(
    overrides: [
      telemetryProvider.overrideWithValue(Telemetry.noop()),
      kvProvider.overrideWithValue(kv),
      accountProvider.overrideWith(() => account),
    ],
  );
  addTearDown(container.dispose);
  // The router only shows setup once the account has loaded.
  await container.read(accountProvider.future);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light(), home: const OnboardingFlow()),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('signed in: no welcome or sign-in screen again', (t) async {
    await _pump(t, _MemoryKv(), _SignedIn());
    expect(find.text('I have an account'), findsNothing);
    expect(find.text('Get started'), findsNothing);
  });

  testWidgets('signed out: the welcome screen', (t) async {
    await _pump(t, _MemoryKv(), _SignedOut());
    expect(find.text('I have an account'), findsOneWidget);
  });

  testWidgets('setup resumes at the question it stopped on', (t) async {
    final kv = _MemoryKv()
      ..values[KvKeys.onboardingDraft] = {
        'index': 5,
        'name': 'Amara',
        'gender': 'woman',
      };
    await _pump(t, kv, _SignedIn());
    expect(find.text('By midday, your skin feels…'), findsOneWidget);
  });
}
