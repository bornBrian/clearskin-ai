import 'package:clearskin_ai/core/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nothing saved follows the phone', () {
    expect(ThemeModeNotifier.parse(null), ThemeMode.system);
    expect(ThemeModeNotifier.parse('nonsense'), ThemeMode.system);
  });

  test('a saved choice is restored', () {
    expect(ThemeModeNotifier.parse('dark'), ThemeMode.dark);
    expect(ThemeModeNotifier.parse('light'), ThemeMode.light);
  });

  test('the app starts in the saved mode', () {
    final c = ProviderContainer(
      overrides: [initialThemeModeProvider.overrideWithValue(ThemeMode.dark)],
    );
    addTearDown(c.dispose);
    expect(c.read(themeModeProvider), ThemeMode.dark);
  });
}
