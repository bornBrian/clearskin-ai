import 'package:clock/clock.dart';

import '../../core/utils/dates.dart';

/// Where someone's streak stands today.
class StreakState {
  const StreakState({
    required this.current,
    required this.best,
    required this.savers,
    required this.savedDays,
    required this.doneToday,
  });

  static const empty = StreakState(
    current: 0,
    best: 0,
    savers: 0,
    savedDays: {},
    doneToday: false,
  );

  /// Days in the current streak (saved days don't add to the count).
  final int current;
  final int best;

  /// Streak savers held right now (0–[Streaks.maxSavers]).
  final int savers;

  /// Missed days a saver covered, as day keys.
  final Set<String> savedDays;
  final bool doneToday;
}

/// Consistency is what changes skin, and nothing kills it faster than a
/// streak lost to one busy day. So every 7 days in a row earns a streak
/// saver (hold up to 2), and a saver covers a single missed day
/// automatically. Two missed days in a row still end the streak.
abstract final class Streaks {
  static const saverEvery = 7;
  static const maxSavers = 2;

  /// Streak lengths worth a moment.
  static const milestones = {3, 7, 14, 21, 30, 60, 90, 100, 180, 365};

  static StreakState compute(Set<String> completedDays, {DateTime? now}) {
    if (completedDays.isEmpty) return StreakState.empty;
    final today = Dates.startOfDay(now ?? clock.now());
    final todayKey = Dates.dayKey(today);
    final first = completedDays
        .map(Dates.parseDay)
        .reduce((a, b) => a.isBefore(b) ? a : b);

    var streak = 0, best = 0, savers = 0;
    var savedYesterday = false;
    final saved = <String>{};
    // Calendar days (not 24-hour steps), so DST changes can't skip one.
    for (
      var d = Dates.startOfDay(first);
      !d.isAfter(today);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      final key = Dates.dayKey(d);
      if (completedDays.contains(key)) {
        streak++;
        savedYesterday = false;
        if (streak % saverEvery == 0 && savers < maxSavers) savers++;
        if (streak > best) best = streak;
      } else if (key == todayKey) {
        // Today isn't over: not done yet doesn't break anything.
      } else if (streak > 0 && savers > 0 && !savedYesterday) {
        savers--;
        saved.add(key);
        savedYesterday = true;
      } else {
        streak = 0;
        savedYesterday = false;
        saved.clear();
      }
    }
    return StreakState(
      current: streak,
      best: best,
      savers: savers,
      savedDays: saved,
      doneToday: completedDays.contains(todayKey),
    );
  }

  /// Consecutive days ending today (or yesterday if today isn't done yet),
  /// with savers covering single missed days.
  static int current(Set<String> completedDays, {DateTime? now}) =>
      compute(completedDays, now: now).current;

  static int longest(Set<String> completedDays) => compute(completedDays).best;
}
