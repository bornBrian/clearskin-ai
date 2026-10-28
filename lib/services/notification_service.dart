import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/config/app_store.dart';
import '../data/models/profile.dart';
import '../domain/premium/renewal.dart';
import '../domain/routine/routine_engine.dart';

/// Local reminders and alerts, one Android channel (and sound) per kind so
/// people can silence any of them on its own.
///
/// Scheduled:
///  - morning routine (daily) and evening routine (per weekday, so the copy
///    can say "retinoid night" or "rest night"), skipped for today once
///    that routine is done
///  - daily check-in and weekly scan, at the times the person picked
///  - smart alerts, re-planned on every app open and routine change:
///    streak at risk tonight, high UV at lunchtime, come-back after 3 and 7
///    quiet days
///  - the honest trial-ending reminder
///  - Premium renewal reminders (a week and a day before a cancelled or
///    prepaid plan ends, or when the person asked to be reminded)
///
/// Every notification carries the route it should open as its payload, so
/// tapping "Morning, Sam" lands on the morning checklist, not the home tab.
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
  static const _renewalBaseId = 210; // +0..4
  static const _milestoneBaseId = 310; // +0..2
  static const _expiryBaseId = 400; // +0..19

  final _taps = StreamController<String>.broadcast();

  /// Routes from notifications tapped while the app is running.
  Stream<String> get taps => _taps.stream;

  /// The route of the notification that launched the app, if any. Read once.
  Future<String?> takeLaunchRoute() async {
    await init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return _route(details!.notificationResponse?.payload);
  }

  /// Only in-app routes are accepted from a payload.
  static String? _route(String? payload) =>
      payload != null && payload.startsWith('/') ? payload : null;

  /// One channel per sound, like fitness apps: people learn what a sound
  /// means before they look, and can mute each kind separately in Android
  /// settings. Sounds come from scripts/brand/generate_sounds.py. Android
  /// fixes a channel's sound when it's first created, so changing a sound
  /// means a new channel id; old ids go in [_retiredChannels].
  static NotificationDetails _channel(
    String id,
    String name,
    String description,
    String sound,
  ) => NotificationDetails(
    android: AndroidNotificationDetails(
      id,
      name,
      channelDescription: description,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(sound),
    ),
    // iOS falls back to the default sound if the file isn't in the bundle.
    iOS: DarwinNotificationDetails(sound: '$sound.wav'),
  );

  /// Three bright rising notes.
  static final _morning = _channel(
    'morning_v1',
    'Morning routine',
    'Your morning routine reminder',
    'clearskin_morning',
  );

  /// Two soft falling notes, quieter.
  static final _evening = _channel(
    'evening_v1',
    'Evening routine',
    'Your evening routine and daily check-in',
    'clearskin_evening',
  );

  /// "Da-da-ding": noticeable, never an alarm.
  static final _streak = _channel(
    'streak_v1',
    'Streak alerts',
    'When your streak is about to end',
    'clearskin_streak',
  );

  /// A rising run with a sparkle.
  static final _milestone = _channel(
    'milestones_v1',
    'Milestones',
    'Day 30, 60 and 90 progress moments',
    'clearskin_milestone',
  );

  /// The neutral two-note chime for everything else.
  static final _general = _channel(
    'updates_v1',
    'Tips & updates',
    'Scan day, sun alerts, product expiry and Premium',
    'clearskin_chime',
  );

  static const _retiredChannels = [
    'routine_reminders',
    'smart_alerts',
    'routine_reminders_v2',
    'smart_alerts_v2',
  ];

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
        android: AndroidInitializationSettings('@drawable/ic_stat_clearskin'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final route = _route(r.payload);
        if (route != null) _taps.add(route);
      },
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    for (final id in _retiredChannels) {
      try {
        await android?.deleteNotificationChannel(channelId: id);
      } catch (_) {
        // Never existed on this install.
      }
    }
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

  Future<void> _routineQueue = Future.value();

  /// (Re)schedules every recurring reminder from the profile's settings.
  /// A reminder for something already done today starts tomorrow instead:
  /// nobody wants "Morning routine" after they've finished it. Calls are
  /// queued so overlapping re-plans can't leave a stale one behind.
  Future<void> scheduleRoutineReminders(
    UserProfile profile, {
    Routine? routine,
    bool amDoneToday = false,
    bool pmDoneToday = false,
    bool checkedInToday = false,
  }) => _routineQueue = _routineQueue.then(
    (_) => _scheduleRoutineReminders(
      profile,
      routine: routine,
      amDoneToday: amDoneToday,
      pmDoneToday: pmDoneToday,
      checkedInToday: checkedInToday,
    ),
    onError: (_) {},
  );

  Future<void> _scheduleRoutineReminders(
    UserProfile profile, {
    Routine? routine,
    required bool amDoneToday,
    required bool pmDoneToday,
    required bool checkedInToday,
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
        details: _morning,
        skipToday: amDoneToday,
        payload: '/routine?slot=am',
      );
      for (var weekday = 1; weekday <= 7; weekday++) {
        final (title, body) = eveningCopy(routine, weekday);
        await _at(
          _pmBaseId + weekday,
          profile.pmReminder,
          title,
          body,
          weekday: weekday,
          details: _evening,
          skipToday: pmDoneToday,
          payload: '/routine?slot=pm',
        );
      }
    }
    if (r.checkIn) {
      await _at(
        _checkInId,
        r.checkInTime,
        'How was your skin today?',
        'Ten seconds. It helps find your triggers.',
        details: _evening,
        skipToday: checkedInToday,
        payload: '/checkin',
      );
    }
    if (r.weeklyScan) {
      await _at(
        _scanId,
        r.scanTime,
        'Scan day',
        'Same light, same angle. See this week\'s change.',
        weekday: r.scanWeekday,
        details: _general,
        payload: '/scan',
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
      payload: '/routine?slot=pm',
    );
    await _once(
      _comebackLongId,
      dayAt(7, 10, 0),
      'A fresh start for your skin',
      'One quick scan shows where you are now.',
      payload: '/scan',
    );

    // Streak at risk: 75 minutes after the evening reminder.
    if (streak >= 2 && !routineDoneToday) {
      final mins = pm.hour * 60 + pm.minute + 75;
      if (mins < 24 * 60) {
        await _once(
          _streakId,
          dayAt(0, mins ~/ 60, mins % 60),
          '🔥 Keep your $streak-day streak',
          'Your evening routine takes two minutes.',
          details: _streak,
          payload: '/routine?slot=pm',
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
      'No surprises: if ClearSkin isn\'t for you, cancel anytime in ${AppStore.subscriptionsPath}.',
      details: _general,
    );
  }

  /// Two weeks before each opened product passes its use-by date.
  Future<void> scheduleExpiryReminders(
    List<(String name, DateTime useBy)> products,
  ) async {
    await init();
    for (var i = 0; i < 20; i++) {
      await _plugin.cancel(id: _expiryBaseId + i);
    }
    for (final (i, (name, useBy)) in products.take(20).indexed) {
      final at = useBy.subtract(const Duration(days: 14));
      await _once(
        _expiryBaseId + i,
        tz.TZDateTime(tz.local, at.year, at.month, at.day, 10),
        '$name expires in 2 weeks',
        'Opened products lose strength. Time to plan a replacement.',
        details: _general,
        payload: '/shelf',
      );
    }
  }

  /// Day 30, 60 and 90 since the first scan: the moments a re-scan shows
  /// real, measurable change. Safe to call often.
  Future<void> scheduleMilestones(DateTime? firstScanAt) async {
    await init();
    const days = [30, 60, 90];
    for (var i = 0; i < days.length; i++) {
      await _plugin.cancel(id: _milestoneBaseId + i);
    }
    if (firstScanAt == null) return;
    for (final (i, d) in days.indexed) {
      final day = firstScanAt.add(Duration(days: d));
      await _once(
        _milestoneBaseId + i,
        tz.TZDateTime(tz.local, day.year, day.month, day.day, 10),
        '$d days since your first scan',
        'Scan today to see exactly what changed since day 1.',
        details: _milestone,
        payload: '/scan',
      );
    }
  }

  /// Replaces the renewal reminders with [plan]'s. Safe to call often.
  Future<void> scheduleRenewalReminders(List<RenewalReminder> plan) async {
    await init();
    for (var i = 0; i < 5; i++) {
      await _plugin.cancel(id: _renewalBaseId + i);
    }
    for (final (i, r) in plan.take(5).indexed) {
      await _once(
        _renewalBaseId + i,
        tz.TZDateTime.from(r.at, tz.local),
        r.title,
        r.body,
        details: _general,
        payload: '/paywall?source=renewal',
      );
    }
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
    NotificationDetails? details,
    String? payload,
  }) async {
    if (!at.isAfter(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: at,
      notificationDetails: details ?? _general,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
      payload: payload,
    );
  }

  /// When a reminder at [hour]:[minute] (daily, or weekly on [weekday])
  /// should first fire. With [skipToday], today's is left out; the repeat
  /// carries on from the next one. Calendar days, so DST can't shift it.
  @visibleForTesting
  static DateTime firstFire(
    DateTime now,
    int hour,
    int minute, {
    int? weekday,
    bool skipToday = false,
  }) {
    var day = DateTime(now.year, now.month, now.day);
    if (weekday != null) {
      day = DateTime(
        day.year,
        day.month,
        day.day + (weekday - day.weekday) % 7,
      );
    }
    final at = DateTime(day.year, day.month, day.day, hour, minute);
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    if (at.isAfter(now) && !(skipToday && isToday)) return at;
    final step = weekday == null ? 1 : 7;
    return DateTime(day.year, day.month, day.day + step, hour, minute);
  }

  /// Daily at [t], or weekly on [weekday] at [t].
  Future<void> _at(
    int id,
    ReminderTime t,
    String title,
    String body, {
    required NotificationDetails details,
    int? weekday,
    bool skipToday = false,
    String? payload,
  }) async {
    // Wall-clock components in the reminder's zone, compared as such.
    final n = tz.TZDateTime.now(tz.local);
    final first = firstFire(
      DateTime(n.year, n.month, n.day, n.hour, n.minute, n.second),
      t.hour,
      t.minute,
      weekday: weekday,
      skipToday: skipToday,
    );
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: tz.TZDateTime(
        tz.local,
        first.year,
        first.month,
        first.day,
        first.hour,
        first.minute,
      ),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: weekday == null
          ? DateTimeComponents.time
          : DateTimeComponents.dayOfWeekAndTime,
      title: title,
      body: body,
      payload: payload,
    );
  }
}
