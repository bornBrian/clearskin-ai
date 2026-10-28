import 'package:clearskin_ai/core/providers.dart';
import 'package:clearskin_ai/core/theme/app_theme.dart';
import 'package:clearskin_ai/core/utils/dates.dart';
import 'package:clearskin_ai/features/routine/streak_flame.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {Set<String> done = const {}, bool still = false}) =>
    ProviderScope(
      overrides: [completedDaysProvider.overrideWithValue(done)],
      child: MaterialApp(
        theme: AppTheme.light(),
        // App-wide, so sheets opened from here get it too.
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: still),
          child: app!,
        ),
        home: Scaffold(body: Center(child: child)),
      ),
    );

Set<String> _lastDays(int n, {bool includeToday = true}) {
  final today = clock.now();
  return {
    for (var i = includeToday ? 0 : 1; i < n + (includeToday ? 0 : 1); i++)
      Dates.dayKey(DateTime(today.year, today.month, today.day - i)),
  };
}

void main() {
  testWidgets('a lit flame flickers, but holds still with reduce motion', (
    t,
  ) async {
    await t.pumpWidget(_app(const StreakFlame(lit: true), still: true));
    await t.pumpAndSettle(); // Would time out if it kept animating.

    await t.pumpWidget(_app(const StreakFlame(lit: true)));
    await t.pump(const Duration(milliseconds: 500));
    expect(t.hasRunningAnimations, isTrue);

    await t.pumpWidget(_app(const StreakFlame(lit: false)));
    await t.pumpAndSettle();
  });

  testWidgets('top bar flame says whether today is safe', (t) async {
    final semantics = t.ensureSemantics();
    await t.pumpWidget(
      _app(const StreakFlameCount(), done: _lastDays(5), still: true),
    );
    expect(find.text('5'), findsOneWidget);
    expect(find.bySemanticsLabel('5 day streak, safe today'), findsOneWidget);

    await t.pumpWidget(
      _app(
        const StreakFlameCount(),
        done: _lastDays(4, includeToday: false),
        still: true,
      ),
    );
    expect(find.text('4'), findsOneWidget);
    expect(
      find.bySemanticsLabel('4 day streak, finish a routine today to keep it'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('tapping the top bar flame opens the streak week', (t) async {
    await t.pumpWidget(
      _app(const StreakFlameCount(), done: _lastDays(3), still: true),
    );
    await t.tap(find.byType(StreakFlameCount));
    await t.pumpAndSettle();
    expect(find.text('3 day streak'), findsOneWidget);
    expect(find.text('Safe for today.'), findsOneWidget);
    expect(find.byType(StreakWeek), findsOneWidget);
  });
}
