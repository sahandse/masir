import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:masir/core/services/navigation_preferences_service.dart';
import 'package:masir/core/services/valhalla_service.dart';

class OfflineRouteStoreService {
  static const _key = 'offline_route_snapshots_v1';
  static const _maxSnapshots = 10;
  static const _distance = Distance();

  Future<void> save({
    required LatLng destination,
    required TravelMode mode,
    required RouteResult route,
  }) async {
    if (route.points.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = await _loadRaw(prefs);
    final id = _id(destination, mode);

    list.removeWhere((item) => item['id'] == id);
    list.insert(0, {
      'id': id,
      'mode': mode.name,
      'destination': {
        'lat': destination.latitude,
        'lon': destination.longitude,
      },
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'route': _routeToJson(route),
    });

    if (list.length > _maxSnapshots) {
      list.removeRange(_maxSnapshots, list.length);
    }

    await prefs.setString(_key, jsonEncode(list));
  }

  Future<RouteResult?> loadForTrip({
    required LatLng current,
    required LatLng destination,
    required TravelMode mode,
    double maxDistanceFromRouteMeters = 1800,
    double destinationToleranceMeters = 250,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _loadRaw(prefs);

    for (final item in list) {
      if (item['mode'] != mode.name) continue;
      final dest = item['destination'] as Map<String, dynamic>?;
      if (dest == null) continue;
      final savedDestination = LatLng(
        (dest['lat'] as num).toDouble(),
        (dest['lon'] as num).toDouble(),
      );
      if (_distance(destination, savedDestination) >
          destinationToleranceMeters) {
        continue;
      }

      final routeJson = item['route'] as Map<String, dynamic>?;
      if (routeJson == null) continue;
      final route = _routeFromJson(routeJson);
      if (route.points.isEmpty) continue;

      var nearest = double.infinity;
      final step = route.points.length > 1000 ? 6 : route.points.length > 400 ? 3 : 1;
      for (var i = 0; i < route.points.length; i += step) {
        final meters = _distance(current, route.points[i]);
        if (meters < nearest) nearest = meters;
        if (nearest <= 60) break;
      }
      if (nearest <= maxDistanceFromRouteMeters) return route;
    }
    return null;
  }

  Future<int> count() async {
    final prefs = await SharedPreferences.getInstance();
    return (await _loadRaw(prefs)).length;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  String _id(LatLng destination, TravelMode mode) =>
      '${mode.name}|${destination.latitude.toStringAsFixed(5)},${destination.longitude.toStringAsFixed(5)}';

  Future<List<Map<String, dynamic>>> _loadRaw(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Map<String, dynamic> _routeToJson(RouteResult route) => {
        'seconds': route.seconds,
        'kilometers': route.kilometers,
        'points': [
          for (final point in route.points)
            [point.latitude, point.longitude],
        ],
        'maneuvers': [
          for (final m in route.maneuvers)
            {
              'instruction': m.instruction,
              'kilometers': m.kilometers,
              'seconds': m.seconds,
              'begin_shape_index': m.beginShapeIndex,
              'end_shape_index': m.endShapeIndex,
              'type': m.type,
              'street_names': m.streetNames,
              'begin_street_names': m.beginStreetNames,
              'exit_number': m.exitNumber,
              'exit_branch': m.exitBranch,
              'exit_toward': m.exitToward,
              'exit_name': m.exitName,
              'lanes': [
                for (final lane in _typedLanes(m.lanes))
                  {
                    'directions': lane.directions,
                    'active': lane.active,
                  },
              ],
            },
        ],
      };

  RouteResult _routeFromJson(Map<String, dynamic> json) => RouteResult(
        seconds: (json['seconds'] as num?)?.toDouble() ?? 0,
        kilometers: (json['kilometers'] as num?)?.toDouble() ?? 0,
        points: ((json['points'] as List<dynamic>?) ?? const [])
            .map(
              (raw) => LatLng(
                ((raw as List<dynamic>)[0] as num).toDouble(),
                (raw[1] as num).toDouble(),
              ),
            )
            .toList(growable: false),
        maneuvers: ((json['maneuvers'] as List<dynamic>?) ?? const [])
            .map((raw) {
              final item = raw as Map<String, dynamic>;
              return RouteManeuver(
                instruction: item['instruction'] as String? ?? 'ادامه مسیر',
                kilometers:
                    (item['kilometers'] as num?)?.toDouble() ?? 0,
                seconds: (item['seconds'] as num?)?.toDouble() ?? 0,
                beginShapeIndex:
                    (item['begin_shape_index'] as num?)?.toInt() ?? 0,
                endShapeIndex:
                    (item['end_shape_index'] as num?)?.toInt() ?? 0,
                type: (item['type'] as num?)?.toInt() ?? 0,
                lanes: ((item['lanes'] as List<dynamic>?) ?? const [])
                    .map(
                      (laneRaw) {
                        final lane = laneRaw as Map<String, dynamic>;
                        return RouteLane(
                          directions: ((lane['directions']
                                      as List<dynamic>?) ??
                                  const [])
                              .map((e) => e.toString())
                              .toList(growable: false),
                          active: lane['active'] == true,
                        );
                      },
                    )
                    .toList(growable: false),
                streetNames: ((item['street_names'] as List<dynamic>?) ??
                        const [])
                    .map((e) => e.toString())
                    .toList(growable: false),
                beginStreetNames:
                    ((item['begin_street_names'] as List<dynamic>?) ??
                            const [])
                        .map((e) => e.toString())
                        .toList(growable: false),
                exitNumber: item['exit_number'] as String?,
                exitBranch: item['exit_branch'] as String?,
                exitToward: item['exit_toward'] as String?,
                exitName: item['exit_name'] as String?,
              );
            })
            .toList(growable: false),
      );

  List<RouteLane> _typedLanes(dynamic lanes) {
    if (lanes is List<RouteLane>) return lanes;
    if (lanes is! List) return const [];
    return lanes.whereType<RouteLane>().toList(growable: false);
  }
}
