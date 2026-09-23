import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/valhalla_service.dart';

class NavigationProgress {
  const NavigationProgress({
    required this.distanceToNextManeuverMeters,
    required this.remainingKilometers,
    required this.remainingSeconds,
    required this.arrivalTime,
    required this.hasArrived,
    required this.offRouteMeters,
  });

  final double distanceToNextManeuverMeters;
  final double remainingKilometers;
  final double remainingSeconds;
  final DateTime arrivalTime;
  final bool hasArrived;
  final double offRouteMeters;
}

enum VoicePromptStage { far, medium, near, now }

class NavigationProgressService {
  NavigationProgressService({Distance? distance})
      : _distance = distance ?? const Distance();

  final Distance _distance;

  static const double arrivalRadiusMeters = 30;
  static const double rerouteThresholdMeters = 85;

  NavigationProgress calculate({
    required LatLng current,
    required LatLng destination,
    required RouteResult route,
    required int maneuverIndex,
    DateTime? now,
  }) {
    final safeManeuverIndex = route.maneuvers.isEmpty
        ? 0
        : maneuverIndex.clamp(0, route.maneuvers.length - 1);

    var distanceToNext = 0.0;
    if (route.maneuvers.isNotEmpty && route.points.isNotEmpty) {
      final maneuver = route.maneuvers[safeManeuverIndex];
      final pointIndex = maneuver.endShapeIndex.clamp(0, route.points.length - 1);
      distanceToNext = _distance(current, route.points[pointIndex]);
    }

    final remainingManeuvers = route.maneuvers.isEmpty
        ? const <RouteManeuver>[]
        : route.maneuvers.skip(safeManeuverIndex);

    final remainingKm = remainingManeuvers.fold<double>(
      0,
      (sum, item) => sum + item.kilometers,
    );
    final remainingSeconds = remainingManeuvers.fold<double>(
      0,
      (sum, item) => sum + item.seconds,
    );

    final offRouteMeters = distanceFromRoute(current, route.points);
    final arrived = _distance(current, destination) <= arrivalRadiusMeters;
    final clock = now ?? DateTime.now();

    return NavigationProgress(
      distanceToNextManeuverMeters: distanceToNext,
      remainingKilometers: remainingKm,
      remainingSeconds: remainingSeconds,
      arrivalTime: clock.add(Duration(seconds: remainingSeconds.round())),
      hasArrived: arrived,
      offRouteMeters: offRouteMeters,
    );
  }

  double distanceFromRoute(LatLng current, List<LatLng> points) {
    if (points.isEmpty) return double.infinity;

    var nearest = double.infinity;
    final step = points.length > 1000
        ? 8
        : points.length > 500
            ? 5
            : points.length > 250
                ? 3
                : 1;

    for (var i = 0; i < points.length; i += step) {
      final meters = _distance(current, points[i]);
      if (meters < nearest) nearest = meters;
      if (nearest < 20) break;
    }
    return nearest;
  }

  bool shouldReroute({
    required LatLng current,
    required RouteResult route,
  }) {
    return distanceFromRoute(current, route.points) >= rerouteThresholdMeters;
  }

  VoicePromptStage? promptStageForDistance(double meters) {
    if (meters <= 25) return VoicePromptStage.now;
    if (meters <= 110) return VoicePromptStage.near;
    if (meters <= 320) return VoicePromptStage.medium;
    if (meters <= 850) return VoicePromptStage.far;
    return null;
  }
}
