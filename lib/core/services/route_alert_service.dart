import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/report_service.dart';

class RouteCorridorAlert {
  const RouteCorridorAlert({
    required this.report,
    required this.distanceMeters,
  });

  final RoadReport report;
  final double distanceMeters;
}

/// Finds real community reports that sit on / near the active route.
class RouteAlertService {
  const RouteAlertService();

  static const _distance = Distance();

  List<RouteCorridorAlert> alertsOnRoute({
    required List<LatLng> routePoints,
    required List<RoadReport> reports,
    double corridorMeters = 90,
  }) {
    if (routePoints.isEmpty || reports.isEmpty) return const [];

    final step = routePoints.length > 600 ? 4 : 1;
    final alerts = <RouteCorridorAlert>[];

    for (final report in reports) {
      var nearest = double.infinity;
      for (var i = 0; i < routePoints.length; i += step) {
        final meters = _distance(report.position, routePoints[i]);
        if (meters < nearest) nearest = meters;
        if (nearest <= corridorMeters) break;
      }
      if (nearest <= corridorMeters) {
        alerts.add(RouteCorridorAlert(report: report, distanceMeters: nearest));
      }
    }

    alerts.sort((a, b) {
      final severity = _severity(b.report.type).compareTo(_severity(a.report.type));
      if (severity != 0) return severity;
      return a.distanceMeters.compareTo(b.distanceMeters);
    });
    return alerts;
  }

  int _severity(String type) {
    switch (type) {
      case 'closure':
        return 5;
      case 'accident':
        return 4;
      case 'hazard':
        return 3;
      case 'police':
        return 3;
      case 'roadwork':
        return 2;
      case 'traffic':
        return 2;
      default:
        return 1;
    }
  }
}
