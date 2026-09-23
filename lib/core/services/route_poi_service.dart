import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/osm_data_service.dart';
import 'package:masir/core/services/valhalla_service.dart';

class RoutePoiService {
  RoutePoiService({OsmDataService? osm}) : _osm = osm ?? OsmDataService();

  final OsmDataService _osm;

  Future<List<OsmPoi>> searchAlongRoute(
    RouteResult route, {
    required Set<String> categories,
  }) async {
    if (route.points.isEmpty) return const [];

    final indexes = _sampleIndexes(route.points.length);
    final found = <OsmPoi>[];
    final seen = <String>{};

    for (final index in indexes) {
      final point = route.points[index];
      final pois = await _osm.nearbyPois(point);
      for (final poi in pois) {
        if (!categories.contains(poi.category)) continue;
        final key = '${poi.category}:${poi.position.latitude.toStringAsFixed(5)},${poi.position.longitude.toStringAsFixed(5)}';
        if (seen.add(key)) found.add(poi);
      }
    }

    const distance = Distance();
    found.sort((a, b) {
      final da = _distanceToPolyline(distance, a.position, route.points);
      final db = _distanceToPolyline(distance, b.position, route.points);
      return da.compareTo(db);
    });
    return found.take(24).toList(growable: false);
  }

  List<int> _sampleIndexes(int length) {
    if (length <= 1) return const [0];
    final indexes = <int>{0, length - 1};
    for (var i = 1; i <= 3; i++) {
      indexes.add(((length - 1) * i / 4).round());
    }
    return indexes.toList()..sort();
  }

  double _distanceToPolyline(
    Distance distance,
    LatLng point,
    List<LatLng> route,
  ) {
    var best = double.infinity;
    final step = route.length > 600 ? 5 : route.length > 250 ? 3 : 1;
    for (var i = 0; i < route.length; i += step) {
      final meters = distance(point, route[i]);
      if (meters < best) best = meters;
      if (best < 30) break;
    }
    return best;
  }
}
