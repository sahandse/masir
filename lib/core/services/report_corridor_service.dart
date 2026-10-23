import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/report_service.dart';

class RouteReportMatch {
  const RouteReportMatch({
    required this.report,
    required this.routeIndex,
    required this.routeOffsetMeters,
  });

  final RoadReport report;
  final int routeIndex;
  final double routeOffsetMeters;
}

class ReportAhead {
  const ReportAhead({
    required this.match,
    required this.distanceAheadMeters,
  });

  final RouteReportMatch match;
  final double distanceAheadMeters;

  RoadReport get report => match.report;
}

class ReportCorridorIndex {
  ReportCorridorIndex._({
    required this.route,
    required this.matches,
    required this.cumulativeMeters,
  });

  final List<LatLng> route;
  final List<RouteReportMatch> matches;
  final List<double> cumulativeMeters;

  static const _distance = Distance();

  factory ReportCorridorIndex.build({
    required List<LatLng> route,
    required List<RoadReport> reports,
    double corridorMeters = 70,
  }) {
    if (route.length < 2 || reports.isEmpty) {
      return ReportCorridorIndex._(
        route: route,
        matches: const [],
        cumulativeMeters: const [],
      );
    }

    final cumulative = <double>[0];
    for (var i = 1; i < route.length; i++) {
      cumulative.add(
        cumulative[i - 1] +
            _distance.as(LengthUnit.Meter, route[i - 1], route[i]),
      );
    }

    final matches = <RouteReportMatch>[];
    for (final report in reports) {
      if (!report.isFresh) continue;
      var nearestIndex = 0;
      var nearestMeters = double.infinity;
      for (var i = 0; i < route.length; i++) {
        final meters = _distance.as(LengthUnit.Meter, route[i], report.position);
        if (meters < nearestMeters) {
          nearestMeters = meters;
          nearestIndex = i;
        }
      }
      if (nearestMeters > corridorMeters) continue;
      matches.add(
        RouteReportMatch(
          report: report,
          routeIndex: nearestIndex,
          routeOffsetMeters: cumulative[nearestIndex],
        ),
      );
    }

    matches.sort((a, b) => a.routeOffsetMeters.compareTo(b.routeOffsetMeters));
    return ReportCorridorIndex._(
      route: route,
      matches: matches,
      cumulativeMeters: cumulative,
    );
  }

  int nearestRouteIndex(LatLng point) {
    if (route.isEmpty) return 0;
    var nearestIndex = 0;
    var nearestMeters = double.infinity;
    for (var i = 0; i < route.length; i++) {
      final meters = _distance.as(LengthUnit.Meter, route[i], point);
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearestIndex = i;
      }
    }
    return nearestIndex;
  }

  List<ReportAhead> aheadOf(
    LatLng current, {
    double maxAheadMeters = 1500,
    double behindToleranceMeters = 20,
    int limit = 3,
    Set<String> excludedIds = const {},
  }) {
    if (matches.isEmpty || route.isEmpty || limit <= 0) return const [];

    final currentOffset = cumulativeMeters[nearestRouteIndex(current)];
    final out = <ReportAhead>[];
    for (final match in matches) {
      if (excludedIds.contains(match.report.id)) continue;
      final ahead = match.routeOffsetMeters - currentOffset;
      if (ahead < -behindToleranceMeters || ahead > maxAheadMeters) continue;
      out.add(
        ReportAhead(
          match: match,
          distanceAheadMeters: ahead < 0 ? 0 : ahead,
        ),
      );
    }

    if (out.length > limit) {
      out.removeRange(limit, out.length);
    }
    return out;
  }
}
