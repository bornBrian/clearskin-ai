import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import '../data/models/profile.dart';
import '../data/repositories/repositories.dart';
import '../domain/forecast/skin_forecast.dart';

/// Today's UV, humidity, temperature and air quality from Open-Meteo.
/// The user picks a city (no location permission needed); results are cached
/// for 3 hours to keep the Today screen instant and offline-tolerant.
class WeatherService {
  WeatherService(this._kv, {http.Client? client})
    : _http = client ?? http.Client();

  final KeyValueStore _kv;
  final http.Client _http;

  static const _ttl = Duration(hours: 3);

  String get _forecastHost => Env.openMeteoApiKey.isEmpty
      ? 'api.open-meteo.com'
      : 'customer-api.open-meteo.com';
  String get _airHost => Env.openMeteoApiKey.isEmpty
      ? 'air-quality-api.open-meteo.com'
      : 'customer-air-quality-api.open-meteo.com';

  Map<String, String> _withKey(Map<String, String> q) => {
    ...q,
    if (Env.openMeteoApiKey.isNotEmpty) 'apikey': Env.openMeteoApiKey,
  };

  Future<WeatherSnapshot?> today(Location loc, {bool force = false}) async {
    final cached = await _kv.getJson(KvKeys.weather);
    if (!force && cached != null) {
      final snap = WeatherSnapshot.fromJson(
        cached['snapshot'] as Map<String, dynamic>,
      );
      final sameLoc = cached['loc'] == loc.name;
      if (sameLoc && clock.now().difference(snap.fetchedAt) < _ttl) {
        return snap;
      }
    }
    try {
      final coords = {
        'latitude': loc.latitude.toStringAsFixed(3),
        'longitude': loc.longitude.toStringAsFixed(3),
        'timezone': 'auto',
      };
      final forecastF = _http
          .get(
            Uri.https(
              _forecastHost,
              '/v1/forecast',
              _withKey({
                ...coords,
                'current': 'temperature_2m,relative_humidity_2m',
                'daily': 'uv_index_max',
                'forecast_days': '1',
              }),
            ),
          )
          .timeout(const Duration(seconds: 10));
      final airF = _http
          .get(
            Uri.https(
              _airHost,
              '/v1/air-quality',
              _withKey({...coords, 'current': 'us_aqi'}),
            ),
          )
          .timeout(const Duration(seconds: 10));

      final forecast = await forecastF;
      if (forecast.statusCode != 200) return _fallback(cached);
      final f = jsonDecode(forecast.body) as Map<String, dynamic>;
      final current = f['current'] as Map<String, dynamic>;
      final daily = f['daily'] as Map<String, dynamic>;

      int? aqi;
      try {
        final air = await airF;
        if (air.statusCode == 200) {
          final a = jsonDecode(air.body) as Map<String, dynamic>;
          aqi = ((a['current'] as Map<String, dynamic>?)?['us_aqi'] as num?)
              ?.round();
        }
      } catch (_) {
        // Air quality is optional.
      }

      final snap = WeatherSnapshot(
        uvIndexMax:
            ((daily['uv_index_max'] as List).first as num?)?.toDouble() ?? 0,
        humidity: (current['relative_humidity_2m'] as num).toDouble(),
        temperatureC: (current['temperature_2m'] as num).toDouble(),
        usAqi: aqi,
        fetchedAt: clock.now(),
      );
      await _kv.setJson(KvKeys.weather, {
        'loc': loc.name,
        'snapshot': snap.toJson(),
      });
      return snap;
    } catch (_) {
      return _fallback(cached);
    }
  }

  WeatherSnapshot? _fallback(Map<String, dynamic>? cached) {
    if (cached == null) return null;
    final snap = WeatherSnapshot.fromJson(
      cached['snapshot'] as Map<String, dynamic>,
    );
    // Stale-but-same-day data is still useful; older is misleading.
    return clock.now().difference(snap.fetchedAt) < const Duration(hours: 18)
        ? snap
        : null;
  }

  Future<List<Location>> searchCity(String query) async {
    if (query.trim().length < 2) return const [];
    final res = await _http
        .get(
          Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
            'name': query.trim(),
            'count': '8',
            'language': 'en',
            'format': 'json',
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return const [];
    final results =
        (jsonDecode(res.body) as Map<String, dynamic>)['results'] as List? ??
        const [];
    return results.whereType<Map<String, dynamic>>().map((r) {
      final parts = [
        r['name'],
        r['admin1'],
        r['country'],
      ].whereType<String>().where((s) => s.isNotEmpty).toList();
      return Location(
        name: parts.join(', '),
        latitude: (r['latitude'] as num).toDouble(),
        longitude: (r['longitude'] as num).toDouble(),
      );
    }).toList();
  }
}
