import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/community_traffic_service.dart';
import 'package:masir/core/services/report_service.dart';
import 'package:masir/core/services/route_alert_service.dart';

void main() {
  test('corridor alert finds real report near route', () {
    const service = RouteAlertService();
    final route = [
      const LatLng(35.70, 51.40),
      const LatLng(35.71, 51.41),
      const LatLng(35.72, 51.42),
    ];
    final reports = [
      RoadReport(
        id: '1',
        type: 'accident',
        position: const LatLng(35.7101, 51.4101),
        createdAt: DateTime.now().toUtc(),
      ),
      RoadReport(
        id: '2',
        type: 'traffic',
        position: const LatLng(36.0, 52.0),
        createdAt: DateTime.now().toUtc(),
      ),
    ];

    final alerts = service.alertsOnRoute(routePoints: route, reports: reports);
    expect(alerts.length, 1);
    expect(alerts.first.report.type, 'accident');
  });

  test('community traffic avoids only routing-relevant real reports', () {
    const service = CommunityTrafficService();
    final points = service.avoidLocations([
      RoadReport(
        id: 'a',
        type: 'police',
        position: const LatLng(35.7, 51.4),
        createdAt: DateTime.now().toUtc(),
      ),
      RoadReport(
        id: 'b',
        type: 'closure',
        position: const LatLng(35.8, 51.5),
        createdAt: DateTime.now().toUtc(),
      ),
    ]);
    expect(points.length, 1);
    expect(points.first.latitude, closeTo(35.8, 0.001));
  });
}
