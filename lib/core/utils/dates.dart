import 'package:clock/clock.dart';
import 'package:intl/intl.dart';

abstract final class Dates {
  static final _dayFmt = DateFormat('yyyy-MM-dd');

  /// Local calendar-day key used for check-ins and routine logs.
  static String dayKey(DateTime d) => _dayFmt.format(d);

  static String today() => dayKey(clock.now());

  static DateTime parseDay(String key) => _dayFmt.parse(key);

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static String relative(DateTime d, {DateTime? now}) {
    final n = startOfDay(now ?? clock.now());
    final diff = n.difference(startOfDay(d)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '$diff days ago';
    if (diff < 14) return '1 week ago';
    if (diff < 60) return '${diff ~/ 7} weeks ago';
    return DateFormat.yMMMd().format(d);
  }

  static String short(DateTime d) => DateFormat.MMMd().format(d);

  static String greeting([DateTime? now]) {
    final h = (now ?? clock.now()).hour;
    if (h < 5) return 'Good night';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }
}
