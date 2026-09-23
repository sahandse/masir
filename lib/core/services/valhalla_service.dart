import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class RouteLane {
  const RouteLane({
    required this.directions,
    required this.active,
  });

  final List<String> directions;
  final bool active;
}

class RouteManeuver {
  const RouteManeuver({
    required this.instruction,
    required this.kilometers,
    required this.seconds,
    required this.beginShapeIndex,
    required this.endShapeIndex,
    required this.type,
    required this.lanes,
    this.streetNames = const [],
    this.beginStreetNames = const [],
    this.exitNumber,
    this.exitBranch,
    this.exitToward,
    this.exitName,
  });

  final String instruction;
  final double kilometers;
  final double seconds;
  final int beginShapeIndex;
  final int endShapeIndex;
  final int type;
  final dynamic lanes;
  final List<String> streetNames;
  final List<String> beginStreetNames;
  final String? exitNumber;
  final String? exitBranch;
  final String? exitToward;
  final String? exitName;

  String? get primaryStreetName {
    if (streetNames.isNotEmpty) return streetNames.first;
    if (beginStreetNames.isNotEmpty) return beginStreetNames.first;
    return null;
  }

  String? get exitLabel {
    final parts = <String>[
      if (exitNumber?.trim().isNotEmpty == true) 'خروجی $exitNumber',
      if (exitBranch?.trim().isNotEmpty == true) exitBranch!,
      if (exitToward?.trim().isNotEmpty == true) 'به سمت $exitToward',
      if (exitName?.trim().isNotEmpty == true) exitName!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
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
    List<LatLng> viaPoints = const [],
    double useHighways = 1.0,
    double useTolls = 1.0,
    double useFerries = 0.5,
  }) async {
    if (!isConfigured) {
      throw StateError('VALHALLA_BASE_URL is not configured');
    }

    final body = {
      'locations': [
        {'lat': from.latitude, 'lon': from.longitude},
        for (final via in viaPoints)
          {'lat': via.latitude, 'lon': via.longitude, 'type': 'break'},
        {'lat': to.latitude, 'lon': to.longitude},
      ],
      'costing': 'auto',
      'costing_options': {
        'auto': {
          'use_highways': useHighways,
          'use_tolls': useTolls,
          'use_ferry': useFerries,
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
        headers: const {'X-Client-Id': 'ir.sahand.masir'},
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
      ),
    );

    final trip = response.data!['trip'] as Map<String, dynamic>;
    final summary = trip['summary'] as Map<String, dynamic>;
    final legs = trip['legs'] as List<dynamic>;
    final points = <LatLng>[];
    final maneuvers = <RouteManeuver>[];
    var pointOffset = 0;

    for (var legIndex = 0; legIndex < legs.length; legIndex++) {
      final leg = legs[legIndex] as Map<String, dynamic>;
      final legPoints = _decodePolyline6(leg['shape'] as String);
      if (legIndex > 0 && legPoints.isNotEmpty) {
        legPoints.removeAt(0);
      }
      final rawManeuvers = (leg['maneuvers'] as List<dynamic>?) ?? const [];

      for (final raw in rawManeuvers) {
        final item = raw as Map<String, dynamic>;
        final sign = item['sign'] as Map<String, dynamic>?;
        maneuvers.add(
          RouteManeuver(
            instruction: (item['instruction'] as String?)?.trim().isNotEmpty == true
                ? item['instruction'] as String
                : 'ادامه مسیر',
            kilometers: (item['length'] as num?)?.toDouble() ?? 0,
            seconds: (item['time'] as num?)?.toDouble() ?? 0,
            beginShapeIndex:
                pointOffset + ((item['begin_shape_index'] as num?)?.toInt() ?? 0),
            endShapeIndex:
                pointOffset + ((item['end_shape_index'] as num?)?.toInt() ?? 0),
            type: (item['type'] as num?)?.toInt() ?? 0,
            lanes: _parseLanes(item['lanes']),
            streetNames: _stringList(item['street_names']),
            beginStreetNames: _stringList(item['begin_street_names']),
            exitNumber: _signText(sign?['exit_number_elements']),
            exitBranch: _signText(sign?['exit_branch_elements']),
            exitToward: _signText(sign?['exit_toward_elements']),
            exitName: _signText(sign?['exit_name_elements']),
          ),
        );
      }

      points.addAll(legPoints);
      pointOffset = points.length - 1;
    }

    return RouteResult(
      points: points,
      seconds: (summary['time'] as num).toDouble(),
      kilometers: (summary['length'] as num).toDouble(),
      maneuvers: maneuvers,
    );
  }

  Future<List<RouteResult>> routeAlternatives(
    LatLng from,
    LatLng to, {
    List<LatLng> viaPoints = const [],
    double useHighways = 1.0,
    double useTolls = 1.0,
    double useFerries = 0.5,
  }) async {
    final results = await Future.wait([
      route(
        from,
        to,
        viaPoints: viaPoints,
        useHighways: useHighways,
        useTolls: useTolls,
        useFerries: useFerries,
      ),
      route(
        from,
        to,
        viaPoints: viaPoints,
        useHighways: useHighways < 0.5 ? useHighways : 0.35,
        useTolls: useTolls,
        useFerries: useFerries,
      ),
      route(
        from,
        to,
        viaPoints: viaPoints,
        useHighways: useHighways,
        useTolls: useTolls < 0.5 ? useTolls : 0.0,
        useFerries: useFerries,
      ),
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

  List<RouteLane> _parseLanes(dynamic raw) {
    final list = raw as List<dynamic>?;
    if (list == null) return const [];

    return list.map((entry) {
      if (entry is Map<String, dynamic>) {
        final directions = _stringList(entry['directions']);
        final active = entry['active'] == true ||
            entry['state'] == 'active' ||
            entry['state'] == 'valid';
        return RouteLane(directions: directions, active: active);
      }
      final text = entry.toString().trim();
      return RouteLane(
        directions: text.isEmpty ? const [] : [text],
        active: false,
      );
    }).toList(growable: false);
  }

  List<String> _stringList(dynamic raw) {
    final list = raw as List<dynamic>?;
    if (list == null) return const [];
    return list
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  String? _signText(dynamic raw) {
    final list = raw as List<dynamic>?;
    if (list == null || list.isEmpty) return null;
    final texts = <String>[];
    for (final entry in list) {
      if (entry is Map<String, dynamic>) {
        final text = (entry['text'] ?? entry['value'])?.toString().trim();
        if (text?.isNotEmpty == true) texts.add(text!);
      } else {
        final text = entry.toString().trim();
        if (text.isNotEmpty) texts.add(text);
      }
    }
    return texts.isEmpty ? null : texts.join(' / ');
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
