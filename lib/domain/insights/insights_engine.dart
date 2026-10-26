import 'dart:math' as math;

import '../../core/utils/dates.dart';
import '../../data/models/check_in.dart';

enum InsightDirection { worse, better }

class Insight {
  const Insight({
    required this.title,
    required this.detail,
    required this.direction,
    required this.effect,
    required this.withCount,
    required this.withoutCount,
    this.emoji,
  });

  final String title;
  final String detail;
  final InsightDirection direction;

  /// Difference in average breakout level (0-3 scale) or skin feel (1-5).
  final double effect;
  final int withCount;
  final int withoutCount;
  final String? emoji;

  /// Rough confidence 0..1 from sample size and effect size.
  double get confidence {
    final n = math.min(withCount, withoutCount);
    final sampleFactor = (n / 8).clamp(0.0, 1.0);
    final effectFactor = (effect.abs() / 1.0).clamp(0.0, 1.0);
    return (0.5 * sampleFactor + 0.5 * effectFactor).clamp(0.0, 1.0);
  }
}

class InsightsReport {
  const InsightsReport({
    required this.insights,
    required this.daysLogged,
    required this.daysNeeded,
  });

  final List<Insight> insights;
  final int daysLogged;

  /// Check-ins still needed before patterns can be trusted.
  final int daysNeeded;

  bool get ready => daysNeeded == 0;
}

/// Finds personal trigger patterns in daily check-ins.
///
/// Many triggers (dairy, sugar, stress, poor sleep) show up as breakouts one
/// to three days later, so each factor is compared against the breakout level
/// over the following window. Results are framed as patterns, never as
/// proof, and require minimum samples on both sides.
abstract final class InsightsEngine {
  static const minDays = 14;
  static const _minGroup = 3;
  static const _minEffect = 0.35;

  static InsightsReport analyze(List<CheckIn> checkIns) {
    final byDay = {for (final c in checkIns) c.day: c};
    final days = byDay.keys.toList()..sort();
    if (days.length < minDays) {
      return InsightsReport(
        insights: const [],
        daysLogged: days.length,
        daysNeeded: minDays - days.length,
      );
    }

    /// Mean breakouts on days d+1..d+2 (whichever were logged).
    double? laggedBreakouts(String day) {
      final d = Dates.parseDay(day);
      final vals = [1, 2]
          .map((o) => byDay[Dates.dayKey(d.add(Duration(days: o)))]?.breakouts)
          .whereType<int>()
          .toList();
      if (vals.isEmpty) return null;
      return vals.reduce((a, b) => a + b) / vals.length;
    }

    final insights = <Insight>[];

    Insight? compare({
      required bool Function(CheckIn) present,
      required String title,
      required String worseDetail,
      required String betterDetail,
      String? emoji,
      bool lagged = true,
    }) {
      final withVals = <double>[];
      final withoutVals = <double>[];
      for (final day in days) {
        final c = byDay[day]!;
        final outcome = lagged ? laggedBreakouts(day) : c.breakouts.toDouble();
        if (outcome == null) continue;
        (present(c) ? withVals : withoutVals).add(outcome);
      }
      if (withVals.length < _minGroup || withoutVals.length < _minGroup) {
        return null;
      }
      final effect = _mean(withVals) - _mean(withoutVals);
      if (effect.abs() < _minEffect) return null;
      final worse = effect > 0;
      return Insight(
        title: title,
        detail: worse ? worseDetail : betterDetail,
        direction: worse ? InsightDirection.worse : InsightDirection.better,
        effect: effect,
        withCount: withVals.length,
        withoutCount: withoutVals.length,
        emoji: emoji,
      );
    }

    for (final tag in LifeTag.values) {
      if (tag == LifeTag.pillowChanged) continue;
      final i = compare(
        present: (c) => c.tags.contains(tag),
        title: tag.label,
        emoji: tag.emoji,
        worseDetail:
            'You tend to have more breakouts 1–2 days after logging "${tag.label.toLowerCase()}".',
        betterDetail:
            'Breakouts tend to be lower after days you log "${tag.label.toLowerCase()}".',
      );
      if (i != null) insights.add(i);
    }

    final sleep = compare(
      present: (c) => c.sleepHours < 6,
      title: 'Short sleep',
      emoji: '😴',
      worseDetail:
          'Nights under 6 hours are followed by more breakouts for you.',
      betterDetail: 'Short nights don\'t seem to affect your breakouts much.',
    );
    if (sleep != null && sleep.direction == InsightDirection.worse) {
      insights.add(sleep);
    }

    final stress = compare(
      present: (c) => c.stress >= 4,
      title: 'High stress',
      emoji: '😣',
      worseDetail: 'Stressful days are followed by more breakouts for you.',
      betterDetail: 'Stress doesn\'t seem to drive your breakouts.',
    );
    if (stress != null && stress.direction == InsightDirection.worse) {
      insights.add(stress);
    }

    final water = compare(
      present: (c) => c.waterGlasses >= 6,
      title: 'Hydration',
      emoji: '💧',
      lagged: false,
      worseDetail:
          'Higher water intake days don\'t line up with clearer skin for you.',
      betterDetail:
          'Days you drink 6+ glasses of water line up with fewer breakouts.',
    );
    if (water != null && water.direction == InsightDirection.better) {
      insights.add(water);
    }

    insights.sort((a, b) => b.confidence.compareTo(a.confidence));
    return InsightsReport(
      insights: insights,
      daysLogged: days.length,
      daysNeeded: 0,
    );
  }

  /// Breakouts in the 2–21 days after starting a product, compared with the
  /// 14 days before. Helps users tell a reaction from coincidence.
  static double? productBreakoutDelta(
    List<CheckIn> checkIns,
    DateTime startedAt,
  ) {
    final start = Dates.startOfDay(startedAt);
    final before = <int>[];
    final after = <int>[];
    for (final c in checkIns) {
      final diff = Dates.parseDay(c.day).difference(start).inDays;
      if (diff >= -14 && diff < 0) before.add(c.breakouts);
      if (diff >= 2 && diff <= 21) after.add(c.breakouts);
    }
    if (before.length < 4 || after.length < 4) return null;
    return _mean(after.map((e) => e.toDouble()).toList()) -
        _mean(before.map((e) => e.toDouble()).toList());
  }

  static double _mean(List<double> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
}
