import 'package:clearskin_ai/core/theme/app_theme.dart';
import 'package:clearskin_ai/core/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {bool reduce = false}) => MaterialApp(
  theme: AppTheme.light(),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('a count-up builds to its value', (t) async {
    await t.pumpWidget(_app(const CountUp(76)));
    expect(find.text('76'), findsNothing);
    await t.pumpAndSettle();
    expect(find.text('76'), findsOneWidget);
  });

  testWidgets('with reduced motion, numbers and the dial show at once', (
    t,
  ) async {
    await t.pumpWidget(
      _app(
        const Column(children: [CountUp(64), ScoreDial(score: 82)]),
        reduce: true,
      ),
    );
    await t.pump();
    expect(find.text('64'), findsOneWidget);
    expect(find.text('82'), findsOneWidget);
  });

  testWidgets('a pressed control presses in and settles back', (t) async {
    await t.pumpWidget(_app(ArrowPill(label: 'Start', onTap: () {})));
    double scale() =>
        t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    expect(scale(), 1);
    final g = await t.startGesture(t.getCenter(find.text('Start')));
    await t.pump(const Duration(milliseconds: 120));
    expect(scale(), lessThan(1));
    await g.up();
    await t.pumpAndSettle();
    expect(scale(), 1);
  });

  testWidgets('the score dial flies between two screens', (t) async {
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Hero(
            tag: 'dial-s1',
            flightShuttleBuilder: ScoreDial.flight,
            child: ScoreDial(score: 76, size: 150),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Hero(
              tag: 'dial-s1',
              flightShuttleBuilder: ScoreDial.flight,
              child: ScoreDial(
                score: 76,
                size: 236,
                color: Colors.white,
                textColor: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 150));
    // mid-flight: both looks are drawn, still, at the score
    expect(find.text('76'), findsWidgets);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('76'), findsOneWidget);
  });
}
