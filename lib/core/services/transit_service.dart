import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

enum TransitStopType {
  metro,
  metroEntrance,
  bus,
  platform,
  station;

  String get label => switch (this) {
        TransitStopType.metro => 'مترو',
        TransitStopType.metroEntrance => 'ورودی مترو',
        TransitStopType.bus => 'اتوبوس',
        TransitStopType.platform => 'ایستگاه حمل‌ونقل',
        TransitStopType.station => 'ایستگاه',
      };
}

class TransitStop {
  const TransitStop({
    required this.name,
    required this.type,
    required this.position,
    this.ref,
    this.operatorName,
  });

  final String name;
  final TransitStopType type;
  final LatLng position;
  final String? ref;
  final String? operatorName;
}

class TransitService {
  TransitService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 24),
                sendTimeout: const Duration(seconds: 10),
                headers: const {
                  'User-Agent': 'MasirNavigation/1.3 (ir.sahand.masir)',
                },
              ),
            );

  final Dio _dio;

  static const _endpoints = <String>[
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  Future<List<TransitStop>> nearby(
    LatLng center, {
    int radiusMeters = 5000,
  }) async {
    final lat = center.latitude;
    final lon = center.longitude;
    final query = '[out:json][timeout:25];('
        'nwr(around:$radiusMeters,$lat,$lon)["railway"="station"]["station"="subway"];'
        'node(around:$radiusMeters,$lat,$lon)["railway"="subway_entrance"];'
        'nwr(around:$radiusMeters,$lat,$lon)["highway"="bus_stop"];'
        'nwr(around:$radiusMeters,$lat,$lon)["public_transport"="platform"];'
        'nwr(around:$radiusMeters,$lat,$lon)["public_transport"="station"];'
        ');out center tags;';

    final response = await _post(query);
    final elements =
        (response.data?['elements'] as List<dynamic>?) ?? const <dynamic>[];
    final out = <TransitStop>[];
    final seen = <String>{};

    for (final raw in elements) {
      if (raw is! Map<String, dynamic>) continue;
      final tags =
          raw['tags'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      final centerData = raw['center'] as Map<String, dynamic>?;
      final latValue = (raw['lat'] as num?)?.toDouble() ??
          (centerData?['lat'] as num?)?.toDouble();
      final lonValue = (raw['lon'] as num?)?.toDouble() ??
          (centerData?['lon'] as num?)?.toDouble();
      if (latValue == null || lonValue == null) continue;

      final type = _type(tags);
      final name =
          (tags['name:fa'] ?? tags['name'] ?? tags['ref'] ?? type.label)
              .toString()
              .trim();
      final key =
          '${type.name}|${latValue.toStringAsFixed(5)}|${lonValue.toStringAsFixed(5)}';
      if (!seen.add(key)) continue;

      out.add(
        TransitStop(
          name: name.isEmpty ? type.label : name,
          type: type,
          position: LatLng(latValue, lonValue),
          ref: tags['ref']?.toString(),
          operatorName: tags['operator']?.toString(),
        ),
      );
    }

    final distance = const Distance();
    out.sort(
      (a, b) => distance(center, a.position)
          .compareTo(distance(center, b.position)),
    );
    return out.take(100).toList(growable: false);
  }

  TransitStopType _type(Map<String, dynamic> tags) {
    if (tags['railway'] == 'subway_entrance') {
      return TransitStopType.metroEntrance;
    }
    if (tags['station'] == 'subway' || tags['subway'] == 'yes') {
      return TransitStopType.metro;
    }
    if (tags['highway'] == 'bus_stop' || tags['bus'] == 'yes') {
      return TransitStopType.bus;
    }
    if (tags['public_transport'] == 'platform') {
      return TransitStopType.platform;
    }
    return TransitStopType.station;
  }

  Future<Response<Map<String, dynamic>>> _post(String query) async {
    Object? lastError;
    for (final endpoint in _endpoints) {
      try {
        return await _dio.post<Map<String, dynamic>>(
          endpoint,
          data: query,
          options: Options(contentType: Headers.textPlainContentType),
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('Overpass unavailable: $lastError');
  }
}
