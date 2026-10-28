import 'dart:convert';

import 'package:clock/clock.dart';

/// Enums are persisted by `name`; never rename a value without a migration.
enum Gender {
  woman('Woman'),
  man('Man'),
  nonBinary('Non-binary'),
  preferNotToSay('Prefer not to say');

  const Gender(this.label);
  final String label;
}

enum AgeRange {
  teen('13–17'),
  a18('18–24'),
  a25('25–34'),
  a35('35–44'),
  a45('45–54'),
  a55('55+');

  const AgeRange(this.label);
  final String label;

  bool get isMinor => this == AgeRange.teen;
}

enum SkinType {
  oily('Oily', 'Shiny by midday, visible pores'),
  dry('Dry', 'Feels tight, can flake'),
  combination('Combination', 'Oily T-zone, normal or dry cheeks'),
  normal('Normal', 'Balanced, rarely reactive'),
  unsure('Not sure', 'We\'ll figure it out from your scan');

  const SkinType(this.label, this.hint);
  final String label;
  final String hint;
}

enum Sensitivity {
  low('Rarely reacts'),
  medium('Sometimes stings or reddens'),
  high('Reacts to many products');

  const Sensitivity(this.label);
  final String label;
}

enum Concern {
  acne('Breakouts & acne'),
  blackheads('Blackheads & clogged pores'),
  darkSpots('Dark spots & marks'),
  unevenTone('Uneven tone'),
  redness('Redness'),
  dryness('Dryness & flaking'),
  oiliness('Excess oil & shine'),
  texture('Rough texture'),
  largePores('Large pores'),
  fineLines('Fine lines & firmness'),
  darkCircles('Dark circles & puffiness'),
  razorBumps('Razor bumps & shaving irritation'),
  sensitivity('Sensitivity & irritation');

  const Concern(this.label);
  final String label;
}

enum Goal {
  clearSkin('Clearer skin'),
  glow('Healthy glow'),
  evenTone('Even tone'),
  antiAging('Prevent & soften aging'),
  barrier('Calm, comfortable skin'),
  simplify('A simpler routine');

  const Goal(this.label);
  final String label;
}

enum RoutineComplexity {
  minimal('Minimal', '2–3 steps. Fast and done.'),
  balanced('Balanced', '3–5 steps. The sweet spot.'),
  enthusiast('Enthusiast', 'Full routine with targeted actives.');

  const RoutineComplexity(this.label, this.hint);
  final String label;
  final String hint;
}

enum Budget {
  low('Budget-friendly'),
  mid('Mid-range'),
  high('Premium');

  const Budget(this.label);
  final String label;
}

/// Self-reported skin tone on the Fitzpatrick scale. Used to tailor sunscreen
/// advice (white cast), pigmentation risk (post-inflammatory marks) and
/// treatment caution. Optional.
enum SkinTone {
  i('Very fair', 0xFFF6E3D3),
  ii('Fair', 0xFFEACBB0),
  iii('Medium', 0xFFD3A27A),
  iv('Olive / tan', 0xFFB27D55),
  v('Brown', 0xFF8A5A3B),
  vi('Deep brown', 0xFF5A3825);

  const SkinTone(this.label, this.swatch);
  final String label;
  final int swatch;

  /// Deeper tones are more prone to post-inflammatory hyperpigmentation.
  bool get pihProne => index >= SkinTone.iv.index;
}

class Location {
  const Location({
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final double latitude;
  final double longitude;

  Map<String, Object?> toJson() => {
    'name': name,
    'lat': latitude,
    'lon': longitude,
  };

  factory Location.fromJson(Map<String, dynamic> j) => Location(
    name: j['name'] as String,
    latitude: (j['lat'] as num).toDouble(),
    longitude: (j['lon'] as num).toDouble(),
  );
}

/// Ingredients someone knows their skin reacts to. Products containing
/// them are flagged and the routine leaves them out.
enum Reaction {
  fragrance('Fragrance & perfume'),
  essentialOils('Essential oils'),
  alcohol('Drying alcohol'),
  retinoids('Retinoids (retinol, adapalene)'),
  acids('Exfoliating acids (AHA, BHA)'),
  vitaminC('Vitamin C'),
  niacinamide('Niacinamide'),
  benzoylPeroxide('Benzoyl peroxide'),
  sulfates('Sulfates (SLS, SLES)'),
  preservatives('Strong preservatives (MI, MCI)'),
  coconut('Coconut oil'),
  lanolin('Lanolin');

  const Reaction(this.label);
  final String label;
}

class UserProfile {
  const UserProfile({
    required this.name,
    required this.gender,
    required this.ageRange,
    required this.skinType,
    required this.sensitivity,
    required this.concerns,
    required this.goals,
    required this.complexity,
    required this.budget,
    required this.createdAt,
    this.skinTone,
    this.pregnantOrNursing = false,
    this.shaves = false,
    this.tracksCycle = false,
    this.location,
    this.amReminder = const ReminderTime(7, 30),
    this.pmReminder = const ReminderTime(21, 30),
    this.remindersEnabled = true,
    this.reminders = const ReminderSettings(),
    this.reactsTo = const {},
  });

  final String name;
  final Gender gender;
  final AgeRange ageRange;
  final SkinType skinType;
  final Sensitivity sensitivity;
  final Set<Concern> concerns;
  final Set<Goal> goals;
  final RoutineComplexity complexity;
  final Budget budget;
  final SkinTone? skinTone;
  final bool pregnantOrNursing;
  final bool shaves;
  final bool tracksCycle;
  final Location? location;
  final ReminderTime amReminder;
  final ReminderTime pmReminder;

  /// Morning/evening routine reminders.
  final bool remindersEnabled;

  /// Check-in, weekly scan and smart alerts.
  final ReminderSettings reminders;
  final DateTime createdAt;

  /// Ingredients this person has reacted to before.
  final Set<Reaction> reactsTo;

  String get firstName {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  bool get acneProne =>
      concerns.contains(Concern.acne) || concerns.contains(Concern.blackheads);
  bool get isSensitive =>
      sensitivity == Sensitivity.high || concerns.contains(Concern.sensitivity);

  UserProfile copyWith({
    String? name,
    Gender? gender,
    AgeRange? ageRange,
    SkinType? skinType,
    Sensitivity? sensitivity,
    Set<Concern>? concerns,
    Set<Goal>? goals,
    RoutineComplexity? complexity,
    Budget? budget,
    SkinTone? skinTone,
    bool clearSkinTone = false,
    bool? pregnantOrNursing,
    bool? shaves,
    bool? tracksCycle,
    Location? location,
    bool clearLocation = false,
    ReminderTime? amReminder,
    ReminderTime? pmReminder,
    bool? remindersEnabled,
    ReminderSettings? reminders,
    Set<Reaction>? reactsTo,
  }) {
    return UserProfile(
      name: name ?? this.name,
      gender: gender ?? this.gender,
      ageRange: ageRange ?? this.ageRange,
      skinType: skinType ?? this.skinType,
      sensitivity: sensitivity ?? this.sensitivity,
      concerns: concerns ?? this.concerns,
      goals: goals ?? this.goals,
      complexity: complexity ?? this.complexity,
      budget: budget ?? this.budget,
      skinTone: clearSkinTone ? null : (skinTone ?? this.skinTone),
      pregnantOrNursing: pregnantOrNursing ?? this.pregnantOrNursing,
      shaves: shaves ?? this.shaves,
      tracksCycle: tracksCycle ?? this.tracksCycle,
      location: clearLocation ? null : (location ?? this.location),
      amReminder: amReminder ?? this.amReminder,
      pmReminder: pmReminder ?? this.pmReminder,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      reminders: reminders ?? this.reminders,
      createdAt: createdAt,
      reactsTo: reactsTo ?? this.reactsTo,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'gender': gender.name,
    'ageRange': ageRange.name,
    'skinType': skinType.name,
    'sensitivity': sensitivity.name,
    'concerns': concerns.map((e) => e.name).toList(),
    'goals': goals.map((e) => e.name).toList(),
    'complexity': complexity.name,
    'budget': budget.name,
    'skinTone': skinTone?.name,
    'pregnantOrNursing': pregnantOrNursing,
    'shaves': shaves,
    'tracksCycle': tracksCycle,
    'location': location?.toJson(),
    'amReminder': amReminder.toJson(),
    'pmReminder': pmReminder.toJson(),
    'remindersEnabled': remindersEnabled,
    'reminders': reminders.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'reactsTo': reactsTo.map((e) => e.name).toList(),
  };

  String encode() => jsonEncode(toJson());

  factory UserProfile.decode(String raw) =>
      UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  factory UserProfile.fromJson(Map<String, dynamic> j) {
    T byName<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    Set<T> setOf<T extends Enum>(List<T> values, Object? names) =>
        ((names as List?) ?? const [])
            .map((n) => values.where((v) => v.name == n).firstOrNull)
            .whereType<T>()
            .toSet();

    return UserProfile(
      name: j['name'] as String? ?? '',
      gender: byName(Gender.values, j['gender'], Gender.preferNotToSay),
      ageRange: byName(AgeRange.values, j['ageRange'], AgeRange.a25),
      skinType: byName(SkinType.values, j['skinType'], SkinType.unsure),
      sensitivity: byName(
        Sensitivity.values,
        j['sensitivity'],
        Sensitivity.medium,
      ),
      concerns: setOf(Concern.values, j['concerns']),
      goals: setOf(Goal.values, j['goals']),
      complexity: byName(
        RoutineComplexity.values,
        j['complexity'],
        RoutineComplexity.balanced,
      ),
      budget: byName(Budget.values, j['budget'], Budget.mid),
      skinTone: j['skinTone'] == null
          ? null
          : byName(SkinTone.values, j['skinTone'], SkinTone.iii),
      pregnantOrNursing: j['pregnantOrNursing'] as bool? ?? false,
      shaves: j['shaves'] as bool? ?? false,
      tracksCycle: j['tracksCycle'] as bool? ?? false,
      location: j['location'] == null
          ? null
          : Location.fromJson(j['location'] as Map<String, dynamic>),
      amReminder: j['amReminder'] == null
          ? const ReminderTime(7, 30)
          : ReminderTime.fromJson(j['amReminder'] as Map<String, dynamic>),
      pmReminder: j['pmReminder'] == null
          ? const ReminderTime(21, 30)
          : ReminderTime.fromJson(j['pmReminder'] as Map<String, dynamic>),
      remindersEnabled: j['remindersEnabled'] as bool? ?? true,
      reminders: j['reminders'] == null
          ? const ReminderSettings()
          : ReminderSettings.fromJson(j['reminders'] as Map<String, dynamic>),
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '') ?? clock.now(),
      reactsTo: setOf(Reaction.values, j['reactsTo']),
    );
  }

  /// Compact, non-identifying context sent to the AI backend. Excludes name
  /// and location by design.
  Map<String, Object?> toAiContext() => {
    'gender': gender.name,
    'ageRange': ageRange.label,
    'selfReportedSkinType': skinType.name,
    'sensitivity': sensitivity.name,
    'concerns': concerns.map((e) => e.name).toList(),
    'goals': goals.map((e) => e.name).toList(),
    'fitzpatrick': skinTone?.name.toUpperCase(),
    'pregnantOrNursing': pregnantOrNursing,
    'shavesFace': shaves,
    'routineComplexity': complexity.name,
    'budget': budget.name,
    if (reactsTo.isNotEmpty)
      'knownReactionsToAvoid': reactsTo.map((e) => e.label).toList(),
  };
}

class ReminderTime {
  const ReminderTime(this.hour, this.minute);
  final int hour;
  final int minute;

  Map<String, Object?> toJson() => {'h': hour, 'm': minute};
  factory ReminderTime.fromJson(Map<String, dynamic> j) =>
      ReminderTime(j['h'] as int, j['m'] as int);

  String format() {
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final mm = minute.toString().padLeft(2, '0');
    return '$h12:$mm ${hour < 12 ? 'AM' : 'PM'}';
  }
}

/// Everything besides the AM/PM routine reminders. Every alert can be
/// turned off individually; defaults are on because consistency is what
/// changes skin.
class ReminderSettings {
  const ReminderSettings({
    this.checkIn = true,
    this.checkInTime = const ReminderTime(20, 30),
    this.weeklyScan = true,
    this.scanWeekday = DateTime.sunday,
    this.scanTime = const ReminderTime(10, 0),
    this.smart = true,
  });

  final bool checkIn;
  final ReminderTime checkInTime;
  final bool weeklyScan;

  /// ISO weekday, 1 = Monday … 7 = Sunday.
  final int scanWeekday;
  final ReminderTime scanTime;

  /// Context-aware alerts: streak at risk, high UV, come-back after a break.
  final bool smart;

  ReminderSettings copyWith({
    bool? checkIn,
    ReminderTime? checkInTime,
    bool? weeklyScan,
    int? scanWeekday,
    ReminderTime? scanTime,
    bool? smart,
  }) => ReminderSettings(
    checkIn: checkIn ?? this.checkIn,
    checkInTime: checkInTime ?? this.checkInTime,
    weeklyScan: weeklyScan ?? this.weeklyScan,
    scanWeekday: scanWeekday ?? this.scanWeekday,
    scanTime: scanTime ?? this.scanTime,
    smart: smart ?? this.smart,
  );

  Map<String, Object?> toJson() => {
    'checkIn': checkIn,
    'checkInTime': checkInTime.toJson(),
    'weeklyScan': weeklyScan,
    'scanWeekday': scanWeekday,
    'scanTime': scanTime.toJson(),
    'smart': smart,
  };

  factory ReminderSettings.fromJson(Map<String, dynamic> j) {
    const d = ReminderSettings();
    ReminderTime time(Object? v, ReminderTime fallback) =>
        v is Map<String, dynamic> ? ReminderTime.fromJson(v) : fallback;
    final day = j['scanWeekday'];
    return ReminderSettings(
      checkIn: j['checkIn'] as bool? ?? d.checkIn,
      checkInTime: time(j['checkInTime'], d.checkInTime),
      weeklyScan: j['weeklyScan'] as bool? ?? d.weeklyScan,
      scanWeekday: day is int && day >= 1 && day <= 7 ? day : d.scanWeekday,
      scanTime: time(j['scanTime'], d.scanTime),
      smart: j['smart'] as bool? ?? d.smart,
    );
  }
}
