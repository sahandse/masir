import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/offline_place_cache_service.dart';
import 'package:masir/features/search/models/place_result.dart';

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
  final _offlineCache = OfflinePlaceCacheService();

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

    Response<Map<String, dynamic>> res;
    try {
      res = await _postOverpass(q);
    } catch (_) {
      final cached = await _offlineCache.nearby(
        center,
        radiusMeters: 3000,
        limit: 80,
      );
      return cached
          .map(
            (place) => OsmPoi(
              name: place.title,
              category: 'offline',
              position: place.position,
            ),
          )
          .toList(growable: false);
    }

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
    await _offlineCache.merge(
      items.map(
        (poi) => PlaceResult(
          title: poi.name,
          subtitle: _persianCategoryName(poi.category),
          position: poi.position,
        ),
      ),
    );
    if (_poiCache.length > 40) {
      final oldest = _poiCache.entries.toList()
        ..sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));
      for (final entry in oldest.take(_poiCache.length - 30)) {
        _poiCache.remove(entry.key);
      }
    }
    return items;
  }

  Future<List<OsmPoi>> poisAlongRoute(
    List<LatLng> route, {
    Set<String>? categories,
    double maxDistanceMeters = 1200,
  }) async {
    if (route.length < 2) return const [];

    final sampleIndexes = <int>{
      (route.length * 0.2).floor(),
      (route.length * 0.5).floor(),
      (route.length * 0.8).floor(),
    }.map((i) => i.clamp(0, route.length - 1)).toList();

    final batches = await Future.wait(
      sampleIndexes.map((index) => nearbyPois(route[index])),
    );

    final seen = <String>{};
    final candidates = <OsmPoi>[];
    for (final batch in batches) {
      for (final poi in batch) {
        if (categories != null &&
            categories.isNotEmpty &&
            !categories.contains(poi.category)) {
          continue;
        }
        final key =
            '${poi.name.toLowerCase()}|${poi.position.latitude.toStringAsFixed(5)},${poi.position.longitude.toStringAsFixed(5)}';
        if (seen.add(key)) candidates.add(poi);
      }
    }

    final distance = const Distance();
    final routeStep = route.length > 240 ? (route.length / 120).floor() : 1;

    double distanceToRoute(OsmPoi poi) {
      var nearest = double.infinity;
      for (var i = 0; i < route.length; i += routeStep) {
        final meters = distance(poi.position, route[i]);
        if (meters < nearest) nearest = meters;
        if (nearest < 40) break;
      }
      final lastMeters = distance(poi.position, route.last);
      if (lastMeters < nearest) nearest = lastMeters;
      return nearest;
    }

    final scored = <({OsmPoi poi, double distance})>[];
    for (final poi in candidates) {
      final meters = distanceToRoute(poi);
      if (meters <= maxDistanceMeters) {
        scored.add((poi: poi, distance: meters));
      }
    }

    scored.sort((a, b) => a.distance.compareTo(b.distance));
    return scored.take(60).map((e) => e.poi).toList(growable: false);
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
      'offline': 'ذخیره آفلاین',
    };
    return labels[category] ?? 'مکان';
  }
}

class _PoiCache {
  const _PoiCache(this.createdAt, this.items);

  final DateTime createdAt;
  final List<OsmPoi> items;
}
