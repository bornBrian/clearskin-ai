import 'package:clearskin_ai/core/providers.dart';
import 'package:clearskin_ai/core/router/app_router.dart';
import 'package:clearskin_ai/core/theme/app_theme.dart';
import 'package:clearskin_ai/data/models/profile.dart';
import 'package:clearskin_ai/data/models/scan.dart';
import 'package:clearskin_ai/data/repositories/repositories.dart';
import 'package:clearskin_ai/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The key-value store in memory.
class _MemoryKv implements KeyValueStore {
  final json = <String, Map<String, dynamic>>{};
  final strings = <String, String>{};

  @override
  Future<Map<String, dynamic>?> getJson(String key) async => json[key];

  @override
  Future<void> setJson(String key, Map<String, Object?> value) async =>
      json[key] = Map<String, dynamic>.from(value);

  @override
  Future<void> remove(String key) async {
    json.remove(key);
    strings.remove(key);
  }

  @override
  Future<String?> get(String key) async => strings[key];

  @override
  Future<void> set(String key, String value) async => strings[key] = value;
}

/// Google always says yes, after a moment, like the real account picker.
class _Google extends AuthService {
  _Google(super.kv);

  @override
  Future<Account> signInWithGoogle() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const Account(provider: 'google', email: 'amara@example.com');
  }
}

class _NoProfile extends ProfileNotifier {
  @override
  Future<UserProfile?> build() async => null;
}

class _NoScans extends ScansNotifier {
  @override
  Future<List<SkinScan>> build() async => const [];
}

class _Accepted extends DisclaimerNotifier {
  @override
  Future<bool> build() async => true;
}

void main() {
  testWidgets('after Google sign-in, setup moves on and never asks again', (
    t,
  ) async {
    final kv = _MemoryKv();
    final container = ProviderContainer(
      overrides: [
        kvProvider.overrideWithValue(kv),
        authServiceProvider.overrideWith((ref) => _Google(kv)),
        profileProvider.overrideWith(_NoProfile.new),
        scansProvider.overrideWith(_NoScans.new),
        disclaimerProvider.overrideWith(_Accepted.new),
      ],
    );
    addTearDown(container.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: container.read(routerProvider),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await t.tap(find.text('Get started'));
    await settle();
    await t.tap(find.text('Skip'));
    await settle();
    expect(find.text('Continue with Google'), findsOneWidget);

    await t.tap(find.text('Continue with Google'));
    await settle();

    expect(find.text('Continue with Google'), findsNothing);
    expect(find.text('What should we call you?'), findsOneWidget);
  });
}
