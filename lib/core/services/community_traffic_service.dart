import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/report_service.dart';

/// Builds routing avoid-points from **real** community reports only.
/// Never invents congestion, speeds, or ETA penalties.
class CommunityTrafficService {
  const CommunityTrafficService();

  /// Locations Valhalla should try to exclude when computing a route.
  List<LatLng> avoidLocations(List<RoadReport> reports) {
    final out = <LatLng>[];
    final seen = <String>{};
    for (final report in reports) {
      if (!_affectsRouting(report.type)) continue;
      final key =
          '${report.position.latitude.toStringAsFixed(4)}_${report.position.longitude.toStringAsFixed(4)}';
      if (!seen.add(key)) continue;
      out.add(report.position);
      if (out.length >= 12) break;
    }
    return out;
  }

  bool _affectsRouting(String type) {
    switch (type) {
      case 'traffic':
      case 'accident':
      case 'closure':
      case 'roadwork':
      case 'hazard':
        return true;
      default:
        return false;
    }
  }
}
