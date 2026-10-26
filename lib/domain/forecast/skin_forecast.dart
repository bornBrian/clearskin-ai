import '../../data/models/profile.dart';

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.uvIndexMax,
    required this.humidity,
    required this.temperatureC,
    this.usAqi,
    required this.fetchedAt,
  });

  final double uvIndexMax;
  final double humidity;
  final double temperatureC;
  final int? usAqi;
  final DateTime fetchedAt;

  Map<String, Object?> toJson() => {
    'uv': uvIndexMax,
    'hum': humidity,
    'temp': temperatureC,
    'aqi': usAqi,
    'at': fetchedAt.toIso8601String(),
  };

  factory WeatherSnapshot.fromJson(Map<String, dynamic> j) => WeatherSnapshot(
    uvIndexMax: (j['uv'] as num).toDouble(),
    humidity: (j['hum'] as num).toDouble(),
    temperatureC: (j['temp'] as num).toDouble(),
    usAqi: (j['aqi'] as num?)?.toInt(),
    fetchedAt: DateTime.parse(j['at'] as String),
  );
}

enum ForecastKind { uv, dry, humid, cold, heat, pollution }

class ForecastTip {
  const ForecastTip({
    required this.kind,
    required this.title,
    required this.body,
    required this.priority,
  });

  final ForecastKind kind;
  final String title;
  final String body;

  /// Higher shows first.
  final int priority;
}

class SkinForecast {
  const SkinForecast({required this.headline, required this.tips});
  final String headline;
  final List<ForecastTip> tips;
}

/// Turns today's weather into concrete skincare adjustments.
abstract final class SkinForecaster {
  static SkinForecast build(WeatherSnapshot w, UserProfile? profile) {
    final tips = <ForecastTip>[];
    final deepTone = profile?.skinTone?.pihProne ?? false;
    final marks = profile?.concerns.contains(Concern.darkSpots) ?? false;

    final uv = w.uvIndexMax;
    if (uv >= 8) {
      tips.add(
        ForecastTip(
          kind: ForecastKind.uv,
          title: 'Very high UV (${uv.round()})',
          body: 'SPF 50, reapply every 2 hours outside, and seek shade 11am–4pm. A hat does a lot of work today.',
          priority: 10,
        ),
      );
    } else if (uv >= 6) {
      tips.add(
        ForecastTip(
          kind: ForecastKind.uv,
          title: 'High UV (${uv.round()})',
          body: 'SPF 30–50 and reapply if you\'re out for more than 2 hours.',
          priority: 8,
        ),
      );
    } else if (uv >= 3) {
      tips.add(
        ForecastTip(
          kind: ForecastKind.uv,
          title: 'Moderate UV (${uv.round()})',
          body: (deepTone || marks)
              ? 'Still enough to darken marks. Wear your SPF even if it\'s cloudy.'
              : 'Your morning SPF has you covered for normal daily exposure.',
          priority: 5,
        ),
      );
    }

    if (w.humidity < 35) {
      tips.add(
        const ForecastTip(
          kind: ForecastKind.dry,
          title: 'Dry air',
          body: 'Apply serums to damp skin and seal with a richer moisturiser. Consider pausing exfoliants if you feel tight.',
          priority: 7,
        ),
      );
    } else if (w.humidity > 75 && w.temperatureC > 22) {
      tips.add(
        const ForecastTip(
          kind: ForecastKind.humid,
          title: 'Humid day',
          body: 'Switch to a lighter gel moisturiser and cleanse after sweating to keep pores clear.',
          priority: 4,
        ),
      );
    }

    if (w.temperatureC <= 5) {
      tips.add(
        const ForecastTip(
          kind: ForecastKind.cold,
          title: 'Cold weather',
          body: 'Cold and wind strip moisture. Use a barrier cream and a balm on lips; avoid very hot showers.',
          priority: 6,
        ),
      );
    } else if (w.temperatureC >= 32) {
      tips.add(
        const ForecastTip(
          kind: ForecastKind.heat,
          title: 'Hot day',
          body: 'Heat increases oil and sweat. Use a water-resistant sunscreen and rinse after you sweat.',
          priority: 5,
        ),
      );
    }

    final aqi = w.usAqi;
    if (aqi != null && aqi > 100) {
      tips.add(
        ForecastTip(
          kind: ForecastKind.pollution,
          title: 'Poor air quality (AQI $aqi)',
          body: 'Pollution adds oxidative stress. An antioxidant serum in the morning and a thorough cleanse tonight help.',
          priority: 6,
        ),
      );
    }

    tips.sort((a, b) => b.priority.compareTo(a.priority));

    final headline = tips.isEmpty
        ? 'Easy skin day. Stick to your routine.'
        : switch (tips.first.kind) {
            ForecastKind.uv => 'Sunscreen day',
            ForecastKind.dry => 'Hydration day',
            ForecastKind.humid => 'Keep it light today',
            ForecastKind.cold => 'Protect your barrier',
            ForecastKind.heat => 'Stay fresh today',
            ForecastKind.pollution => 'Antioxidant day',
          };

    return SkinForecast(headline: headline, tips: tips);
  }
}
