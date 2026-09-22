import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class RouteResult {
  const RouteResult({required this.points, required this.seconds, required this.kilometers});
  final List<LatLng> points;
  final double seconds;
  final double kilometers;
}

class ValhallaService {
  ValhallaService({Dio? dio}) : _dio = dio ?? Dio();
  final Dio _dio;

  static const _baseUrl = String.fromEnvironment('VALHALLA_BASE_URL');

  bool get isConfigured => _baseUrl.trim().isNotEmpty;

  Future<RouteResult> route(LatLng from, LatLng to) async {
    if (!isConfigured) {
      throw StateError('VALHALLA_BASE_URL is not configured');
    }
    final body = {
      'locations': [
        {'lat': from.latitude, 'lon': from.longitude},
        {'lat': to.latitude, 'lon': to.longitude},
      ],
      'costing': 'auto',
      'directions_options': {'units': 'kilometers'},
    };
    final response = await _dio.get<Map<String, dynamic>>(
      '$_baseUrl/route',
      queryParameters: {'json': jsonEncode(body)},
    );
    final trip = response.data!['trip'] as Map<String, dynamic>;
    final summary = trip['summary'] as Map<String, dynamic>;
    final legs = trip['legs'] as List<dynamic>;
    final shape = (legs.first as Map<String, dynamic>)['shape'] as String;
    return RouteResult(
      points: _decodePolyline6(shape),
      seconds: (summary['time'] as num).toDouble(),
      kilometers: (summary['length'] as num).toDouble(),
    );
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
