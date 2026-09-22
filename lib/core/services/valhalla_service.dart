import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class RouteManeuver {
  const RouteManeuver({
    required this.instruction,
    required this.kilometers,
    required this.seconds,
    required this.beginShapeIndex,
    required this.endShapeIndex,
    required this.type,
    required this.lanes,
  });

  final String instruction;
  final double kilometers;
  final double seconds;
  final int beginShapeIndex;
  final int endShapeIndex;
  final int type;
  final List<String> lanes;
}

class RouteResult {
  const RouteResult({
    required this.points,
    required this.seconds,
    required this.kilometers,
    required this.maneuvers,
  });

  final List<LatLng> points;
  final double seconds;
  final double kilometers;
  final List<RouteManeuver> maneuvers;
}

class ValhallaService {
  ValhallaService({Dio? dio}) : _dio = dio ?? Dio();
  final Dio _dio;

  static const _baseUrl = String.fromEnvironment('VALHALLA_BASE_URL');

  bool get isConfigured => _baseUrl.trim().isNotEmpty;

  Future<RouteResult> route(
    LatLng from,
    LatLng to, {
    double useHighways = 1.0,
    double useTolls = 1.0,
  }) async {
    if (!isConfigured) {
      throw StateError('VALHALLA_BASE_URL is not configured');
    }

    final body = {
      'locations': [
        {'lat': from.latitude, 'lon': from.longitude},
        {'lat': to.latitude, 'lon': to.longitude},
      ],
      'costing': 'auto',
      'costing_options': {
        'auto': {
          'use_highways': useHighways,
          'use_tolls': useTolls,
        },
      },
      'directions_options': {
        'units': 'kilometers',
        'language': 'en-US',
      },
    };

    final response = await _dio.post<Map<String, dynamic>>(
      '$_baseUrl/route',
      data: body,
      options: Options(
        contentType: Headers.jsonContentType,
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
      ),
    );

    final trip = response.data!['trip'] as Map<String, dynamic>;
    final summary = trip['summary'] as Map<String, dynamic>;
    final legs = trip['legs'] as List<dynamic>;
    final firstLeg = legs.first as Map<String, dynamic>;
    final shape = firstLeg['shape'] as String;
    final rawManeuvers = (firstLeg['maneuvers'] as List<dynamic>?) ?? const [];

    final maneuvers = rawManeuvers.map((raw) {
      final item = raw as Map<String, dynamic>;
      return RouteManeuver(
        instruction: (item['instruction'] as String?)?.trim().isNotEmpty == true
            ? item['instruction'] as String
            : 'ادامه مسیر',
        kilometers: (item['length'] as num?)?.toDouble() ?? 0,
        seconds: (item['time'] as num?)?.toDouble() ?? 0,
        beginShapeIndex: (item['begin_shape_index'] as num?)?.toInt() ?? 0,
        endShapeIndex: (item['end_shape_index'] as num?)?.toInt() ?? 0,
        type: (item['type'] as num?)?.toInt() ?? 0,
        lanes: ((item['lanes'] as List<dynamic>?) ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
      );
    }).toList(growable: false);

    return RouteResult(
      points: _decodePolyline6(shape),
      seconds: (summary['time'] as num).toDouble(),
      kilometers: (summary['length'] as num).toDouble(),
      maneuvers: maneuvers,
    );
  }

  Future<List<RouteResult>> routeAlternatives(LatLng from, LatLng to) async {
    final results = await Future.wait([
      route(from, to),
      route(from, to, useHighways: 0.35, useTolls: 1.0),
      route(from, to, useHighways: 0.75, useTolls: 0.0),
    ]);

    final unique = <RouteResult>[];
    for (final candidate in results) {
      final duplicate = unique.any((r) =>
          (r.kilometers - candidate.kilometers).abs() < 0.05 &&
          (r.seconds - candidate.seconds).abs() < 20);
      if (!duplicate) unique.add(candidate);
    }
    return unique;
  }

  List<LatLng> _decodePolyline6(String encoded) {
    final coordinates = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var result = 0;
      var shift = 0;
      int byte;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      result = 0;
      shift = 0;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      coordinates.add(LatLng(lat / 1e6, lng / 1e6));
    }

    return coordinates;
  }
}
