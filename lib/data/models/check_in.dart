import 'dart:convert';

/// Lifestyle factors users can tag on a daily check-in. The insights engine
/// correlates these with breakouts and skin feel over time.
enum LifeTag {
  dairy('Dairy', '🥛'),
  sugar('Sugary food', '🍩'),
  fastFood('Greasy / fast food', '🍟'),
  alcohol('Alcohol', '🍷'),
  workout('Workout / sweat', '🏃'),
  sunExposure('Lots of sun', '☀️'),
  heavyMakeup('Heavy makeup', '💄'),
  shaved('Shaved', '🪒'),
  newProduct('New product', '🧴'),
  travel('Travel', '✈️'),
  period('Period', '🩸'),
  touchedFace('Touched face a lot', '✋'),
  pillowChanged('Fresh pillowcase', '🛏️');

  const LifeTag(this.label, this.emoji);
  final String label;
  final String emoji;
}

/// One daily check-in. `day` is a local calendar date (yyyy-MM-dd) and is
/// unique: re-checking-in on the same day updates the entry.
class CheckIn {
  const CheckIn({
    required this.day,
    required this.skinFeel,
    required this.breakouts,
    required this.sleepHours,
    required this.stress,
    required this.waterGlasses,
    required this.tags,
    required this.note,
  });

  final String day;

  /// 1 (rough day) .. 5 (great skin day)
  final int skinFeel;

  /// 0 none, 1 one or two, 2 several, 3 many
  final int breakouts;
  final double sleepHours;

  /// 1 (calm) .. 5 (very stressed)
  final int stress;
  final int waterGlasses;
  final Set<LifeTag> tags;
  final String note;

  Map<String, Object?> toRow() => {
    'day': day,
    'skin_feel': skinFeel,
    'breakouts': breakouts,
    'sleep_hours': sleepHours,
    'stress': stress,
    'water': waterGlasses,
    'tags': jsonEncode(tags.map((t) => t.name).toList()),
    'note': note,
  };

  factory CheckIn.fromRow(Map<String, Object?> r) => CheckIn(
    day: r['day'] as String,
    skinFeel: r['skin_feel'] as int,
    breakouts: r['breakouts'] as int,
    sleepHours: (r['sleep_hours'] as num).toDouble(),
    stress: r['stress'] as int,
    waterGlasses: r['water'] as int,
    tags: ((jsonDecode(r['tags'] as String) as List?) ?? const [])
        .map((n) => LifeTag.values.where((t) => t.name == n).firstOrNull)
        .whereType<LifeTag>()
        .toSet(),
    note: r['note'] as String? ?? '',
  );
}

enum RoutineSlot { am, pm }

/// Which routine steps were completed in a slot on a given day.
class RoutineLog {
  const RoutineLog({
    required this.day,
    required this.slot,
    required this.completedStepIds,
  });

  final String day;
  final RoutineSlot slot;
  final Set<String> completedStepIds;

  Map<String, Object?> toRow() => {
    'day': day,
    'slot': slot.name,
    'steps': jsonEncode(completedStepIds.toList()),
  };

  factory RoutineLog.fromRow(Map<String, Object?> r) => RoutineLog(
    day: r['day'] as String,
    slot: RoutineSlot.values.byName(r['slot'] as String),
    completedStepIds: ((jsonDecode(r['steps'] as String) as List?) ?? const [])
        .whereType<String>()
        .toSet(),
  );
}
