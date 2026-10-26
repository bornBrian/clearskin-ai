import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/models/profile.dart';
import '../domain/routine/routine_engine.dart';

/// Local reminders and alerts. Two Android channels so people can silence
/// smart alerts without losing their routine reminders.
///
/// Scheduled:
///  - morning routine (daily) and evening routine (per weekday, so the copy
///    can say "retinoid night" or "rest night")
///  - daily check-in and weekly scan, at the times the person picked
///  - smart alerts, re-planned on every app open and routine change:
///    streak at risk tonight, high UV at lunchtime, come-back after 3 and 7
///    quiet days
///  - the honest trial-ending reminder
///
/// Inexact scheduling on Android, so no exact-alarm permission is needed
/// (Play restricts that permission to alarm apps).
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _amId = 100;
  static const _pmBaseId = 110; // +1..7 per ISO weekday
  static const _legacyPmId = 101;
  static const _checkInId = 102;
  static const _scanId = 103;
  static const _comebackId = 300;
  static const _comebackLongId = 301;
  static const _streakId = 302;
  static const _sunId = 303;
  static const _trialId = 200;

  static const _routine = NotificationDetails(
    android: AndroidNotificationDetails(
      'routine_reminders',
      'Routine reminders',
      channelDescription: 'Morning, evening, check-in and weekly scan',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
  );
  static const _smart = NotificationDetails(
    android: AndroidNotificationDetails(
      'smart_alerts',
      'Smart alerts',
      channelDescription: 'Streaks, UV and gentle come-back reminders',
      importance: Importance.low,
      priority: Priority.low,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (e) {
      debugPrint('Timezone init failed, using UTC: $e');
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  /// Asks for notification permission (Android 13+ / iOS). Call from a
  /// moment where the value is obvious, e.g. after the user picks reminder
  /// times, never on cold start.
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return false;
  }

  /// (Re)schedules every recurring reminder from the profile's settings.
  Future<void> scheduleRoutineReminders(
    UserProfile profile, {
    Routine? routine,
  }) async {
    await init();
    for (final id in [
      _amId,
      _legacyPmId,
      _checkInId,
      _scanId,
      for (var d = 1; d <= 7; d++) _pmBaseId + d,
    ]) {
      await _plugin.cancel(id: id);
    }

    final r = profile.reminders;
    if (profile.remindersEnabled) {
      final name = profile.firstName;
      await _at(
        _amId,
        profile.amReminder,
        name.isEmpty ? 'Morning routine' : 'Morning, $name',
        'Two minutes. Finish with SPF.',
      );
      for (var weekday = 1; weekday <= 7; weekday++) {
        final (title, body) = eveningCopy(routine, weekday);
        await _at(
          _pmBaseId + weekday,
          profile.pmReminder,
          title,
          body,
          weekday: weekday,
        );
      }
    }
    if (r.checkIn) {
      await _at(
        _checkInId,
        r.checkInTime,
        'How was your skin today?',
        'Ten seconds. It helps find your triggers.',
      );
    }
    if (r.weeklyScan) {
      await _at(
        _scanId,
        r.scanTime,
        'Scan day',
        'Same light, same angle. See this week\'s change.',
        weekday: r.scanWeekday,
      );
    }
  }

  /// Evening copy for a weekday, named after that night's active step.
  @visibleForTesting
  static (String, String) eveningCopy(Routine? routine, int weekday) {
    final scheduled = routine?.pm.where((s) => s.days.isNotEmpty) ?? const [];
    final tonight = scheduled
        .where((s) => s.days.contains(weekday))
        .firstOrNull;
    if (tonight != null) {
      return ('Tonight: ${tonight.title}', 'Cleanse, then your active.');
    }
    if (scheduled.isNotEmpty) {
      return ('Rest night', 'Cleanse and moisturise. Skin repairs tonight.');
    }
    return ('Evening routine', 'Two minutes before bed.');
  }

  /// Re-plans context-aware alerts. Cheap and idempotent: call on app open,
  /// on resume and whenever a routine step is ticked.
  Future<void> scheduleSmartAlerts({
    required UserProfile profile,
    required bool routineDoneToday,
    required int streak,
    int? uvIndex,
    DateTime? now,
  }) async {
    await init();
    for (final id in [_comebackId, _comebackLongId, _streakId, _sunId]) {
      await _plugin.cancel(id: id);
    }
    if (!profile.reminders.smart) return;
    final t = now == null
        ? tz.TZDateTime.now(tz.local)
        : tz.TZDateTime.from(now, tz.local);
    final pm = profile.pmReminder;

    // Come-back: only fires if they don't open the app again before then
    // (every open re-plans these further out).
    tz.TZDateTime dayAt(int addDays, int hour, int minute) =>
        tz.TZDateTime(tz.local, t.year, t.month, t.day + addDays, hour, minute);
    await _once(
      _comebackId,
      dayAt(3, pm.hour, pm.minute),
      'Your plan is waiting',
      'Pick up with tonight\'s routine. No catching up needed.',
    );
    await _once(
      _comebackLongId,
      dayAt(7, 10, 0),
      'A fresh start for your skin',
      'One quick scan shows where you are now.',
    );

    // Streak at risk: 75 minutes after the evening reminder.
    if (streak >= 2 && !routineDoneToday) {
      final mins = pm.hour * 60 + pm.minute + 75;
      if (mins < 24 * 60) {
        await _once(
          _streakId,
          dayAt(0, mins ~/ 60, mins % 60),
          'Keep your $streak-day streak',
          'Your evening routine takes two minutes.',
        );
      }
    }

    if (uvIndex != null && uvIndex >= 6) {
      await _once(
        _sunId,
        dayAt(0, 13, 0),
        'UV $uvIndex right now',
        'Outside today? Reapply your SPF.',
      );
    }
  }

  /// Honest reminder before a free trial converts. Builds trust and cuts
  /// refund requests and chargebacks.
  Future<void> scheduleTrialEndingReminder(int trialDays) async {
    await init();
    if (trialDays < 2) return;
    final at = tz.TZDateTime.now(tz.local).add(Duration(days: trialDays - 1));
    await _once(
      _trialId,
      at,
      'Your free trial ends tomorrow',
      'No surprises: if ClearSkin isn\'t for you, cancel anytime in Google Play → Subscriptions.',
      details: _routine,
    );
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  Future<void> _once(
    int id,
    tz.TZDateTime at,
    String title,
    String body, {
    NotificationDetails details = _smart,
  }) async {
    if (!at.isAfter(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: at,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
    );
  }

  /// Daily at [t], or weekly on [weekday] at [t].
  Future<void> _at(
    int id,
    ReminderTime t,
    String title,
    String body, {
    int? weekday,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      t.hour,
      t.minute,
    );
    if (weekday != null) {
      at = at.add(Duration(days: (weekday - at.weekday) % 7));
    }
    if (!at.isAfter(now)) {
      at = at.add(Duration(days: weekday == null ? 1 : 7));
    }
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: at,
      notificationDetails: _routine,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: weekday == null
          ? DateTimeComponents.time
          : DateTimeComponents.dayOfWeekAndTime,
      title: title,
      body: body,
    );
  }
}
