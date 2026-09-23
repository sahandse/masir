import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class RouteAlert {
  const RouteAlert({
    required this.kind,
    required this.label,
    required this.position,
    this.detail,
  });

  final String kind;
  final String label;
  final LatLng position;
  final String? detail;
}

class RouteAwarenessService {
  RouteAwarenessService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 14),
              sendTimeout: const Duration(seconds: 8),
              headers: const {
                'User-Agent': 'MasirNavigation/0.9 (ir.sahand.masir)',
              },
            ));

  final Dio _dio;

  static const _endpoints = <String>[
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  Future<List<RouteAlert>> nearbyAlerts(LatLng point) async {
    final query = '[out:json][timeout:15];('
        'nwr(around:600,${point.latitude},${point.longitude})["highway"="construction"];'
        'nwr(around:600,${point.latitude},${point.longitude})["construction"];'
        'nwr(around:450,${point.latitude},${point.longitude})["access"~"no|private"];'
        'nwr(around:450,${point.latitude},${point.longitude})["barrier"];'
        'nwr(around:600,${point.latitude},${point.longitude})["toll"="yes"];'
        'nwr(around:800,${point.latitude},${point.longitude})["route"="ferry"];'
        ');out center tags;';

    final response = await _post(query);
    final elements = (response.data?['elements'] as List<dynamic>?) ?? const [];
    final out = <RouteAlert>[];
    final seen = <String>{};

    for (final raw in elements) {
      final item = raw as Map<String, dynamic>;
      final tags = (item['tags'] as Map<String, dynamic>?) ?? const {};
      final center = item['center'] as Map<String, dynamic>?;
      final lat = (item['lat'] as num?)?.toDouble() ??
          (center?['lat'] as num?)?.toDouble();
      final lon = (item['lon'] as num?)?.toDouble() ??
          (center?['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;

      final info = _describe(tags);
      if (info == null) continue;
      final key = '${info.$1}:${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
      if (!seen.add(key)) continue;

      out.add(RouteAlert(
        kind: info.$1,
        label: info.$2,
        position: LatLng(lat, lon),
        detail: (tags['name:fa'] ?? tags['name'] ?? tags['description'])?.toString(),
      ));
    }

    return out.take(12).toList(growable: false);
  }

  (String, String)? _describe(Map<String, dynamic> tags) {
    if (tags['highway'] == 'construction' || tags.containsKey('construction')) {
      return ('construction', 'عملیات عمرانی');
    }
    if (tags['toll'] == 'yes') return ('toll', 'عوارضی');
    if (tags['route'] == 'ferry') return ('ferry', 'مسیر آبی');
    final access = tags['access']?.toString();
    if (access == 'no' || access == 'private') {
      return ('restricted', 'محدودیت عبور');
    }
    if (tags.containsKey('barrier')) return ('barrier', 'مانع مسیر');
    return null;
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
    throw StateError('Route awareness unavailable: $lastError');
  }
}
