import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrafficZone {
  const TrafficZone({
    required this.id,
    required this.name,
    required this.kind,
    required this.rings,
    this.description,
  });

  final String id;
  final String name;
  final String kind;
  final List<List<LatLng>> rings;
  final String? description;

  bool contains(LatLng point) {
    if (rings.isEmpty || rings.first.length < 3) return false;
    return _containsInRing(point, rings.first);
  }

  bool _containsInRing(LatLng point, List<LatLng> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i];
      final b = ring[j];
      final intersect = ((a.latitude > point.latitude) !=
              (b.latitude > point.latitude)) &&
          (point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      ((b.latitude - a.latitude).abs() < 1e-12
                          ? 1e-12
                          : (b.latitude - a.latitude)) +
                  a.longitude);
      if (intersect) inside = !inside;
    }
    return inside;
  }
}

class TrafficZoneService {
  TrafficZoneService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 18),
                sendTimeout: const Duration(seconds: 10),
                headers: const {
                  'User-Agent': 'MasirNavigation/1.3 (ir.sahand.masir)',
                },
              ),
            );

  final Dio _dio;

  static const dataUrl = String.fromEnvironment('TRAFFIC_ZONE_DATA_URL');
  static const _cacheKey = 'traffic_zone_geojson_v1';

  bool get isConfigured => dataUrl.trim().isNotEmpty;

  Future<List<TrafficZone>> load() async {
    if (isConfigured) {
      try {
        final response = await _dio.get<dynamic>(dataUrl);
        final root = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        if (root is Map<String, dynamic>) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_cacheKey, jsonEncode(root));
          return _parse(root);
        }
      } catch (_) {
        // Fall back to the last verified download.
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached == null || cached.isEmpty) return const [];
    try {
      final root = jsonDecode(cached);
      if (root is Map<String, dynamic>) return _parse(root);
    } catch (_) {
      // Ignore broken local cache.
    }
    return const [];
  }

  List<TrafficZone> _parse(Map<String, dynamic> root) {
    if (root['type'] != 'FeatureCollection') return const [];
    final features = root['features'] as List<dynamic>? ?? const [];
    final out = <TrafficZone>[];

    for (final raw in features) {
      if (raw is! Map<String, dynamic>) continue;
      final geometry = raw['geometry'];
      if (geometry is! Map<String, dynamic>) continue;
      final properties =
          raw['properties'] as Map<String, dynamic>? ?? const {};
      final type = geometry['type'] as String?;
      final coordinates = geometry['coordinates'];
      if (coordinates is! List) continue;

      final polygons = <List<List<LatLng>>>[];
      if (type == 'Polygon') {
        final polygon = _polygon(coordinates);
        if (polygon.isNotEmpty) polygons.add(polygon);
      } else if (type == 'MultiPolygon') {
        for (final polygonRaw in coordinates) {
          if (polygonRaw is! List) continue;
          final polygon = _polygon(polygonRaw);
          if (polygon.isNotEmpty) polygons.add(polygon);
        }
      }

      for (var i = 0; i < polygons.length; i++) {
        final id = (raw['id'] ?? properties['id'] ?? 'zone').toString();
        out.add(
          TrafficZone(
            id: polygons.length == 1 ? id : '$id-$i',
            name: (properties['name:fa'] ??
                    properties['name'] ??
                    'محدوده ترافیکی')
                .toString(),
            kind: (properties['kind'] ??
                    properties['zone_type'] ??
                    'restricted')
                .toString(),
            description: properties['description:fa']?.toString() ??
                properties['description']?.toString(),
            rings: polygons[i],
          ),
        );
      }
    }
    return out;
  }

  List<List<LatLng>> _polygon(List<dynamic> raw) {
    final rings = <List<LatLng>>[];
    for (final ringRaw in raw) {
      if (ringRaw is! List) continue;
      final ring = <LatLng>[];
      for (final pointRaw in ringRaw) {
        if (pointRaw is! List || pointRaw.length < 2) continue;
        final lon = pointRaw[0];
        final lat = pointRaw[1];
        if (lon is num && lat is num) {
          ring.add(LatLng(lat.toDouble(), lon.toDouble()));
        }
      }
      if (ring.length >= 3) rings.add(ring);
    }
    return rings;
  }
}
