import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class TrafficSegment {
  const TrafficSegment({
    required this.id,
    required this.points,
    required this.congestion,
    required this.updatedAt,
    this.speedKmh,
    this.freeFlowKmh,
  });

  final String id;
  final List<LatLng> points;
  final double congestion;
  final double? speedKmh;
  final double? freeFlowKmh;
  final DateTime updatedAt;

  factory TrafficSegment.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'] as List<dynamic>? ?? const [];
    final points = <LatLng>[];
    for (final raw in rawPoints) {
      if (raw is List && raw.length >= 2 && raw[0] is num && raw[1] is num) {
        points.add(
          LatLng(
            (raw[0] as num).toDouble(),
            (raw[1] as num).toDouble(),
          ),
        );
      } else if (raw is Map<String, dynamic>) {
        final lat = (raw['lat'] as num?)?.toDouble();
        final lon = (raw['lon'] as num?)?.toDouble();
        if (lat != null && lon != null) points.add(LatLng(lat, lon));
      }
    }

    final rawCongestion = (json['congestion'] as num?)?.toDouble() ?? 0;
    return TrafficSegment(
      id: (json['id'] ?? '').toString(),
      points: points,
      congestion: rawCongestion.clamp(0.0, 1.0),
      speedKmh: (json['speed_kmh'] as num?)?.toDouble(),
      freeFlowKmh: (json['free_flow_kmh'] as num?)?.toDouble(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
    );
  }
}

class TrafficService {
  TrafficService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12),
                sendTimeout: const Duration(seconds: 8),
              ),
            );

  final Dio _dio;

  static const _baseUrl = String.fromEnvironment('TRAFFIC_API_BASE_URL');

  bool get isConfigured => _baseUrl.trim().isNotEmpty;

  Future<List<TrafficSegment>> nearby(
    LatLng center, {
    int radiusMeters = 7000,
  }) async {
    if (!isConfigured) return const [];
    final response = await _dio.get<dynamic>(
      '$_baseUrl/traffic/nearby',
      queryParameters: {
        'lat': center.latitude,
        'lon': center.longitude,
        'radius_m': radiusMeters,
      },
    );

    final raw = response.data is List
        ? response.data as List<dynamic>
        : ((response.data as Map<String, dynamic>?)?['segments']
                as List<dynamic>?) ??
            const <dynamic>[];

    final now = DateTime.now().toUtc();
    final out = <TrafficSegment>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final segment = TrafficSegment.fromJson(item);
        if (segment.points.length < 2) continue;
        if (now.difference(segment.updatedAt) > const Duration(minutes: 10)) {
          continue;
        }
        out.add(segment);
      } catch (_) {
        // Ignore malformed provider rows.
      }
    }
    return out;
  }
}
