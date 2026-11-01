import '../../core/utils/dates.dart';
import '../../data/models/check_in.dart';
import '../../data/models/profile.dart';
import '../journey/journey_engine.dart';
import '../routine/routine_engine.dart';

enum NudgeKind {
  welcomeBack,
  newWeek,
  scanDue,
  sun,
  tonight,
  streak,
  checkIn,
  freshStart,
}

class Nudge {
  const Nudge({
    required this.kind,
    required this.title,
    required this.body,
    required this.route,
    required this.action,
  });

  final NudgeKind kind;

  /// Five words or fewer.
  final String title;

  /// One short sentence.
  final String body;
  final String route;
  final String action;
}

/// Everything the engine looks at. Built from providers in the app and by
/// hand in tests.
class NudgeContext {
  const NudgeContext({
    required this.now,
    required this.profile,
    required this.routine,
    required this.amDone,
    required this.pmDone,
    required this.completedDays,
    required this.streak,
    required this.lastScanAt,
    required this.previousOpenAt,
    required this.checkedInToday,
    required this.uvIndex,
    required this.journey,
    this.scanCount = 0,
  });

  final DateTime now;
  final UserProfile profile;
  final Routine? routine;
  final Set<String> amDone;
  final Set<String> pmDone;
  final Set<String> completedDays;
  final int streak;
  final DateTime? lastScanAt;

  /// When the app was opened before this session (null on first launch).
  final DateTime? previousOpenAt;
  final bool checkedInToday;
  final int? uvIndex;
  final Journey? journey;

  /// Scans taken so far. The second one gets its own words: it's the scan
  /// that first shows change, and the step that turns a try into a habit.
  final int scanCount;
}

/// Picks the in-app alerts that matter right now: aware of the time of day,
/// the routine's schedule (retinoid vs rest nights), what the person has or
/// hasn't done, and how long they've been away. Ordered most useful first.
abstract final class NudgeEngine {
  static List<Nudge> pick(NudgeContext x) {
    final out = <Nudge>[];
    final h = x.now.hour;
    final today = Dates.startOfDay(x.now);

    List<RoutineStep> required(RoutineSlot s) =>
        x.routine?.stepsFor(s, x.now).where((st) => !st.optional).toList() ??
        const [];
    int left(RoutineSlot s, Set<String> done) =>
        required(s).where((st) => !done.contains(st.id)).length;

    // Back after a break: no guilt, one small step.
    final away = x.previousOpenAt == null
        ? 0
        : today.difference(Dates.startOfDay(x.previousOpenAt!)).inDays;
    if (away >= 3) {
      out.add(
        Nudge(
          kind: NudgeKind.welcomeBack,
          title: 'Welcome back',
          body: away >= 7
              ? 'Skin forgives. Start again with tonight\'s routine.'
              : 'No catching up needed — just the next routine.',
          route: h >= 15 ? '/routine?slot=pm' : '/routine?slot=am',
          action: 'Start',
        ),
      );
    }

    final j = x.journey;
    if (j != null && j.isNewWeek) {
      out.add(
        Nudge(
          kind: NudgeKind.newWeek,
          title: 'Week ${j.week} · ${j.phase.name}',
          body: j.phase.focus.first,
          route: '/journey',
          action: 'See plan',
        ),
      );
    }

    final daysSinceScan = x.lastScanAt == null
        ? null
        : today.difference(Dates.startOfDay(x.lastScanAt!)).inDays;
    final accountAgeDays = today
        .difference(Dates.startOfDay(x.profile.createdAt))
        .inDays;
    if ((daysSinceScan == null && accountAgeDays >= 1) ||
        (daysSinceScan != null && daysSinceScan >= 7)) {
      out.add(
        Nudge(
          kind: NudgeKind.scanDue,
          title: daysSinceScan == null
              ? 'Take your first scan'
              : x.scanCount == 1
              ? 'Your second scan'
              : 'Scan day',
          body: daysSinceScan == null
              ? 'Your baseline makes every result measurable.'
              : x.scanCount == 1
              ? 'The one that shows change. Same light and angle as your first.'
              : 'Same light, same angle. See this week\'s change.',
          route: '/scan',
          action: 'Scan',
        ),
      );
    }

    if (x.uvIndex != null && x.uvIndex! >= 6 && h >= 6 && h < 15) {
      out.add(
        Nudge(
          kind: NudgeKind.sun,
          title: 'UV ${x.uvIndex} today',
          body: 'Reapply SPF at lunch if you\'re outside.',
          route: '/routine?slot=am',
          action: 'Routine',
        ),
      );
    }

    if (h >= 17) {
      final pmLeft = left(RoutineSlot.pm, x.pmDone);
      final todayKey = Dates.dayKey(x.now);
      if (x.streak > 1 && !x.completedDays.contains(todayKey) && pmLeft > 0) {
        out.add(
          Nudge(
            kind: NudgeKind.streak,
            title: 'Keep your ${x.streak}-day streak',
            body: '$pmLeft step${pmLeft == 1 ? '' : 's'} left tonight.',
            route: '/routine?slot=pm',
            action: 'Finish',
          ),
        );
      } else if (pmLeft > 0) {
        final active = required(RoutineSlot.pm)
            .where((s) => s.days.isNotEmpty)
            .firstOrNull;
        final anyActiveThisWeek =
            x.routine?.pm.any((s) => s.days.isNotEmpty) ?? false;
        out.add(
          Nudge(
            kind: NudgeKind.tonight,
            title: active != null
                ? 'Tonight: ${active.title}'
                : anyActiveThisWeek
                ? 'Tonight is a rest night'
                : 'Evening routine',
            body: active != null
                ? 'On dry skin, then moisturise.'
                : 'Cleanse and moisturise. That\'s it.',
            route: '/routine?slot=pm',
            action: 'Open',
          ),
        );
      }
      if (!x.checkedInToday && h >= 18) {
        out.add(
          const Nudge(
            kind: NudgeKind.checkIn,
            title: 'How was your skin?',
            body: 'Ten seconds. It finds your triggers.',
            route: '/checkin',
            action: 'Check in',
          ),
        );
      }
    }

    // Morning after a missed day (not a long absence — that's welcomeBack).
    if (h < 12 && away < 3 && accountAgeDays >= 1) {
      final yesterday = Dates.dayKey(today.subtract(const Duration(days: 1)));
      if (!x.completedDays.contains(yesterday) && x.amDone.isEmpty) {
        out.add(
          const Nudge(
            kind: NudgeKind.freshStart,
            title: 'Fresh start',
            body: 'Yesterday slipped. Today counts more.',
            route: '/routine?slot=am',
            action: 'Start',
          ),
        );
      }
    }

    return out;
  }
}
