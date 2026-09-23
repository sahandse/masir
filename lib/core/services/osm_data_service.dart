import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class OsmPoi {
  const OsmPoi({required this.name, required this.category, required this.position});
  final String name;
  final String category;
  final LatLng position;
}

class OsmRoadInfo {
  const OsmRoadInfo({this.maxSpeedKmh, this.speedCameraNearby = false});
  final int? maxSpeedKmh;
  final bool speedCameraNearby;
}

class OsmDataService {
  OsmDataService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(headers: {
              'User-Agent': 'MasirNavigation/0.2 (Flutter)',
            }));
  final Dio _dio;
  static const _overpass = 'https://overpass-api.de/api/interpreter';

  Future<List<OsmPoi>> nearbyPois(LatLng center) async {
    final q = '[out:json][timeout:20];('
        'nwr(around:2500,${center.latitude},${center.longitude})'
        '["amenity"~"fuel|parking|hospital|restaurant|atm|pharmacy"];'
        ');out center tags;';
    final res = await _dio.post<Map<String, dynamic>>(
      _overpass,
      data: q,
      options: Options(contentType: Headers.textPlainContentType),
    );
    final elements = (res.data?['elements'] as List<dynamic>?) ?? const [];
    final out = <OsmPoi>[];
    for (final raw in elements) {
      final e = raw as Map<String, dynamic>;
      final tags = (e['tags'] as Map<String, dynamic>?) ?? const {};
      final centerData = e['center'] as Map<String, dynamic>?;
      final lat = (e['lat'] as num?)?.toDouble() ?? (centerData?['lat'] as num?)?.toDouble();
      final lon = (e['lon'] as num?)?.toDouble() ?? (centerData?['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      out.add(OsmPoi(
        name: (tags['name:fa'] ?? tags['name'] ?? tags['amenity'] ?? 'مکان').toString(),
        category: (tags['amenity'] ?? 'poi').toString(),
        position: LatLng(lat, lon),
      ));
    }
    return out.take(60).toList();
  }

  Future<OsmRoadInfo> roadInfo(LatLng point) async {
    final q = '[out:json][timeout:12];('
        'way(around:45,${point.latitude},${point.longitude})["highway"]["maxspeed"];'
        'node(around:120,${point.latitude},${point.longitude})["highway"="speed_camera"];'
        ');out tags center;';
    final res = await _dio.post<Map<String, dynamic>>(
      _overpass,
      data: q,
      options: Options(contentType: Headers.textPlainContentType),
    );
    final elements = (res.data?['elements'] as List<dynamic>?) ?? const [];
    int? maxSpeed;
    var camera = false;
    for (final raw in elements) {
      final e = raw as Map<String, dynamic>;
      final tags = (e['tags'] as Map<String, dynamic>?) ?? const {};
      if (tags['highway'] == 'speed_camera') camera = true;
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
    return OsmRoadInfo(maxSpeedKmh: maxSpeed, speedCameraNearby: camera);
  }
}
