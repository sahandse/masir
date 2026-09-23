import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class OsmPoi {
  const OsmPoi({
    required this.name,
    required this.category,
    required this.position,
  });

  final String name;
  final String category;
  final LatLng position;
}

class OsmRoadInfo {
  const OsmRoadInfo({
    this.maxSpeedKmh,
    this.speedCameraNearby = false,
    this.roadName,
    this.roadRef,
    this.surface,
  });

  final int? maxSpeedKmh;
  final bool speedCameraNearby;
  final String? roadName;
  final String? roadRef;
  final String? surface;
}

class OsmDataService {
  OsmDataService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 18),
                sendTimeout: const Duration(seconds: 10),
                headers: const {
                  'User-Agent': 'MasirNavigation/0.7 (ir.sahand.masir)',
                },
              ),
            );

  final Dio _dio;

  static const _overpassEndpoints = <String>[
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  static final Map<String, _PoiCache> _poiCache = {};
  static const _poiCacheTtl = Duration(minutes: 5);

  Future<List<OsmPoi>> nearbyPois(LatLng center) async {
    final cacheKey = '${center.latitude.toStringAsFixed(3)},${center.longitude.toStringAsFixed(3)}';
    final cached = _poiCache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.createdAt) < _poiCacheTtl) {
      return cached.items;
    }

    final q = '[out:json][timeout:20];('
        'nwr(around:2500,${center.latitude},${center.longitude})'
        '["amenity"~"fuel|parking|hospital|clinic|restaurant|cafe|atm|bank|pharmacy|police|fire_station|charging_station"];'
        'nwr(around:2500,${center.latitude},${center.longitude})'
        '["shop"~"convenience|supermarket"];'
        'nwr(around:2500,${center.latitude},${center.longitude})'
        '["tourism"~"hotel"];'
        ');out center tags;';

    final res = await _postOverpass(q);
    final elements = (res.data?['elements'] as List<dynamic>?) ?? const [];
    final out = <OsmPoi>[];

    for (final raw in elements) {
      final e = raw as Map<String, dynamic>;
      final tags = (e['tags'] as Map<String, dynamic>?) ?? const {};
      final centerData = e['center'] as Map<String, dynamic>?;
      final lat = (e['lat'] as num?)?.toDouble() ?? (centerData?['lat'] as num?)?.toDouble();
      final lon = (e['lon'] as num?)?.toDouble() ?? (centerData?['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;

      final category = (tags['amenity'] ?? tags['shop'] ?? tags['tourism'] ?? 'poi').toString();
      out.add(
        OsmPoi(
          name: (tags['name:fa'] ?? tags['name'] ?? _persianCategoryName(category)).toString(),
          category: category,
          position: LatLng(lat, lon),
        ),
      );
    }

    final items = out.take(80).toList(growable: false);
    _poiCache[cacheKey] = _PoiCache(DateTime.now(), items);
    if (_poiCache.length > 40) {
      final oldest = _poiCache.entries.toList()
        ..sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));
      for (final entry in oldest.take(_poiCache.length - 30)) {
        _poiCache.remove(entry.key);
      }
    }
    return items;
  }

  Future<OsmRoadInfo> roadInfo(LatLng point) async {
    final q = '[out:json][timeout:12];('
        'way(around:50,${point.latitude},${point.longitude})["highway"];'
        'node(around:150,${point.latitude},${point.longitude})["highway"="speed_camera"];'
        ');out tags center;';

    final res = await _postOverpass(q);
    final elements = (res.data?['elements'] as List<dynamic>?) ?? const [];
    int? maxSpeed;
    var camera = false;
    String? roadName;
    String? roadRef;
    String? surface;

    for (final raw in elements) {
      final e = raw as Map<String, dynamic>;
      final tags = (e['tags'] as Map<String, dynamic>?) ?? const {};
      if (tags['highway'] == 'speed_camera') {
        camera = true;
        continue;
      }

      roadName ??= (tags['name:fa'] ?? tags['name'])?.toString();
      roadRef ??= tags['ref']?.toString();
      surface ??= tags['surface']?.toString();

      final value = tags['maxspeed']?.toString();
      if (value != null) {
        final match = RegExp(r'\d+').firstMatch(value);
        if (match != null) {
          var parsed = int.tryParse(match.group(0)!);
          if (parsed != null && value.toLowerCase().contains('mph')) {
            parsed = (parsed * 1.60934).round();
          }
          maxSpeed ??= parsed;
        }
      }
    }

    return OsmRoadInfo(
      maxSpeedKmh: maxSpeed,
      speedCameraNearby: camera,
      roadName: roadName,
      roadRef: roadRef,
      surface: surface,
    );
  }

  Future<Response<Map<String, dynamic>>> _postOverpass(String query) async {
    Object? lastError;
    for (final endpoint in _overpassEndpoints) {
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

  String _persianCategoryName(String category) {
    const labels = <String, String>{
      'fuel': 'پمپ بنزین',
      'parking': 'پارکینگ',
      'hospital': 'بیمارستان',
      'clinic': 'درمانگاه',
      'restaurant': 'رستوران',
      'cafe': 'کافه',
      'atm': 'خودپرداز',
      'bank': 'بانک',
      'pharmacy': 'داروخانه',
      'police': 'پلیس',
      'fire_station': 'آتش‌نشانی',
      'charging_station': 'شارژ خودرو برقی',
      'convenience': 'فروشگاه',
      'supermarket': 'سوپرمارکت',
      'hotel': 'هتل',
    };
    return labels[category] ?? 'مکان';
  }
}

class _PoiCache {
  const _PoiCache(this.createdAt, this.items);

  final DateTime createdAt;
  final List<OsmPoi> items;
}
