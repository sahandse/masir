import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/report_corridor_service.dart';
import 'package:masir/core/services/report_service.dart';

void main() {
  const route = <LatLng>[
    LatLng(35.6892, 51.3890),
    LatLng(35.6892, 51.3900),
    LatLng(35.6892, 51.3910),
    LatLng(35.6892, 51.3920),
    LatLng(35.6892, 51.3930),
    LatLng(35.6892, 51.3940),
  ];

  RoadReport report({
    required String id,
    required RoadReportType type,
    required LatLng position,
    Duration age = Duration.zero,
  }) {
    return RoadReport(
      id: id,
      type: type,
      position: position,
      createdAt: DateTime.now().toUtc().subtract(age),
    );
  }

  test('keeps only fresh reports inside the route corridor', () {
    final index = ReportCorridorIndex.build(
      route: route,
      reports: [
        report(
          id: 'on-route',
          type: RoadReportType.accident,
          position: const LatLng(35.68925, 51.3920),
        ),
        report(
          id: 'far-away',
          type: RoadReportType.hazard,
          position: const LatLng(35.6905, 51.3920),
        ),
        report(
          id: 'expired-traffic',
          type: RoadReportType.traffic,
          position: const LatLng(35.6892, 51.3930),
          age: const Duration(hours: 2),
        ),
      ],
    );

    expect(index.matches.map((match) => match.report.id), ['on-route']);
    expect(index.matches.single.routeIndex, 3);
  });

  test('orders reports ahead of the driver by distance', () {
    final index = ReportCorridorIndex.build(
      route: route,
      reports: [
        report(
          id: 'near',
          type: RoadReportType.police,
          position: const LatLng(35.6892, 51.3905),
        ),
        report(
          id: 'far',
          type: RoadReportType.roadwork,
          position: const LatLng(35.6892, 51.3930),
        ),
        report(
          id: 'behind',
          type: RoadReportType.hazard,
          position: const LatLng(35.6892, 51.3880),
        ),
      ],
    );

    final ahead = index.aheadOf(route.first, maxAheadMeters: 1500);

    expect(ahead.map((item) => item.report.id), ['near', 'far']);
    expect(ahead.first.distanceAheadMeters, closeTo(90, 12));
    expect(ahead.last.distanceAheadMeters, closeTo(362, 18));
  });

  test('honours max ahead distance, exclusions and progress position', () {
    final index = ReportCorridorIndex.build(
      route: route,
      reports: [
        report(
          id: 'at-300m',
          type: RoadReportType.accident,
          position: const LatLng(35.6892, 51.3925),
        ),
        report(
          id: 'at-180m',
          type: RoadReportType.accident,
          position: const LatLng(35.6892, 51.3910),
        ),
      ],
    );

    expect(
      index.aheadOf(route.first, maxAheadMeters: 100),
      isEmpty,
    );
    expect(
      index
          .aheadOf(
            route.first,
            maxAheadMeters: 1000,
            excludedIds: const {'at-300m'},
          )
          .map((item) => item.report.id),
      ['at-180m'],
    );
    expect(
      index
          .aheadOf(
            const LatLng(35.6892, 51.3930),
            maxAheadMeters: 1000,
          )
          .map((item) => item.report.id),
      isEmpty,
    );
  });

  test('reports immediately beside the driver are still returned', () {
    final index = ReportCorridorIndex.build(
      route: route,
      reports: [
        report(
          id: 'beside',
          type: RoadReportType.traffic,
          position: const LatLng(35.6892, 51.3901),
        ),
      ],
    );

    final ahead = index.aheadOf(
      const LatLng(35.6892, 51.3900),
      behindToleranceMeters: 20,
    );

    expect(ahead.single.report.id, 'beside');
    expect(ahead.single.distanceAheadMeters, lessThan(20));
  });
}
