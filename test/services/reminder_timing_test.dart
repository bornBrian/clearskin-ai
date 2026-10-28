import 'package:clearskin_ai/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Tuesday 28 Oct 2025, 07:00.
  final tueMorning = DateTime(2025, 10, 28, 7);

  group('first reminder time', () {
    test('later today when the time has not passed', () {
      expect(
        NotificationService.firstFire(tueMorning, 8, 0),
        DateTime(2025, 10, 28, 8),
      );
    });

    test('tomorrow when the time has passed', () {
      expect(
        NotificationService.firstFire(DateTime(2025, 10, 28, 8, 1), 8, 0),
        DateTime(2025, 10, 29, 8),
      );
    });

    test('done already today: starts tomorrow, not in an hour', () {
      expect(
        NotificationService.firstFire(tueMorning, 8, 0, skipToday: true),
        DateTime(2025, 10, 29, 8),
      );
    });

    test(
      'done today after the time passed: still tomorrow, not the day after',
      () {
        expect(
          NotificationService.firstFire(
            DateTime(2025, 10, 28, 22),
            21,
            0,
            skipToday: true,
          ),
          DateTime(2025, 10, 29, 21),
        );
      },
    );

    test('rolls over the end of the month and year', () {
      expect(
        NotificationService.firstFire(DateTime(2025, 12, 31, 23), 8, 0),
        DateTime(2026, 1, 1, 8),
      );
    });

    test('weekly: the next matching weekday', () {
      expect(
        NotificationService.firstFire(
          tueMorning,
          21,
          0,
          weekday: DateTime.friday,
        ),
        DateTime(2025, 10, 31, 21),
      );
    });

    test('weekly on today: tonight, or next week when done', () {
      expect(
        NotificationService.firstFire(
          tueMorning,
          21,
          0,
          weekday: DateTime.tuesday,
        ),
        DateTime(2025, 10, 28, 21),
      );
      expect(
        NotificationService.firstFire(
          tueMorning,
          21,
          0,
          weekday: DateTime.tuesday,
          skipToday: true,
        ),
        DateTime(2025, 11, 4, 21),
      );
    });

    test('skipping today never skips another day of the week', () {
      expect(
        NotificationService.firstFire(
          tueMorning,
          21,
          0,
          weekday: DateTime.wednesday,
          skipToday: true,
        ),
        DateTime(2025, 10, 29, 21),
      );
    });

    test('keeps the wall-clock time across a DST change', () {
      // Europe/US clocks change around these dates; calendar arithmetic
      // keeps 08:00 at 08:00 whatever the device zone.
      for (final now in [DateTime(2025, 3, 29, 9), DateTime(2025, 10, 25, 9)]) {
        final next = NotificationService.firstFire(now, 8, 0);
        expect((next.hour, next.minute), (8, 0));
        expect(next.day, now.day + 1);
      }
    });
  });
}
