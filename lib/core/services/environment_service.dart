import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class EnvironmentSnapshot {
  const EnvironmentSnapshot({
    required this.temperatureC,
    required this.apparentTemperatureC,
    required this.windKmh,
    required this.weatherCode,
    required this.usAqi,
    required this.pm25,
    required this.pm10,
    required this.fetchedAt,
  });

  final double? temperatureC;
  final double? apparentTemperatureC;
  final double? windKmh;
  final int? weatherCode;
  final int? usAqi;
  final double? pm25;
  final double? pm10;
  final DateTime fetchedAt;

  String get weatherLabel => switch (weatherCode) {
        0 => 'صاف',
        1 || 2 => 'کمی ابری',
        3 => 'ابری',
        45 || 48 => 'مه',
        51 || 53 || 55 || 56 || 57 => 'نم‌نم باران',
        61 || 63 || 65 || 66 || 67 => 'باران',
        71 || 73 || 75 || 77 => 'برف',
        80 || 81 || 82 => 'رگبار',
        85 || 86 => 'رگبار برف',
        95 || 96 || 99 => 'رعدوبرق',
        _ => 'نامشخص',
      };

  String get aqiLabel {
    final value = usAqi;
    if (value == null) return 'نامشخص';
    if (value <= 50) return 'پاک';
    if (value <= 100) return 'قابل قبول';
    if (value <= 150) return 'ناسالم برای گروه‌های حساس';
    if (value <= 200) return 'ناسالم';
    if (value <= 300) return 'بسیار ناسالم';
    return 'خطرناک';
  }
}

class EnvironmentService {
  EnvironmentService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<EnvironmentSnapshot> current(LatLng position) async {
    final weatherFuture = _dio.get<Map<String, dynamic>>(
      'https://api.open-meteo.com/v1/forecast',
      queryParameters: {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'current':
            'temperature_2m,apparent_temperature,weather_code,wind_speed_10m',
        'timezone': 'auto',
      },
    );
    final airFuture = _dio.get<Map<String, dynamic>>(
      'https://air-quality-api.open-meteo.com/v1/air-quality',
      queryParameters: {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'current': 'us_aqi,pm2_5,pm10',
        'timezone': 'auto',
      },
    );

    final responses = await Future.wait([weatherFuture, airFuture]);
    final weather = responses[0].data?['current'] as Map<String, dynamic>?;
    final air = responses[1].data?['current'] as Map<String, dynamic>?;

    return EnvironmentSnapshot(
      temperatureC: (weather?['temperature_2m'] as num?)?.toDouble(),
      apparentTemperatureC:
          (weather?['apparent_temperature'] as num?)?.toDouble(),
      windKmh: (weather?['wind_speed_10m'] as num?)?.toDouble(),
      weatherCode: (weather?['weather_code'] as num?)?.toInt(),
      usAqi: (air?['us_aqi'] as num?)?.toInt(),
      pm25: (air?['pm2_5'] as num?)?.toDouble(),
      pm10: (air?['pm10'] as num?)?.toDouble(),
      fetchedAt: DateTime.now(),
    );
  }
}
