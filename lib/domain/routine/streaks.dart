import '../../core/utils/dates.dart';

abstract final class Streaks {
  /// Consecutive days (ending today, or yesterday if today isn't done yet)
  /// on which at least one routine was completed.
  static int current(Set<String> completedDays, {DateTime? now}) {
    var day = Dates.startOfDay(now ?? DateTime.now());
    if (!completedDays.contains(Dates.dayKey(day))) {
      day = day.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (completedDays.contains(Dates.dayKey(day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static int longest(Set<String> completedDays) {
    if (completedDays.isEmpty) return 0;
    final sorted = completedDays.map(Dates.parseDay).toList()..sort();
    var best = 1, run = 1;
    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i].difference(sorted[i - 1]).inDays;
      if (gap == 1) {
        run++;
        if (run > best) best = run;
      } else if (gap > 1) {
        run = 1;
      }
    }
    return best;
  }
}
