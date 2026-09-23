import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:masir/core/services/navigation_progress_service.dart';
import 'package:masir/core/services/navigation_session_service.dart';
import 'package:masir/core/services/osm_data_service.dart';
import 'package:masir/core/services/route_awareness_service.dart';
import 'package:masir/core/services/valhalla_service.dart';

class NavigationViewState extends Equatable {
  const NavigationViewState({
    this.session,
    this.route,
    this.progress,
    this.roadInfo,
    this.alerts = const [],
    this.maneuverIndex = 0,
    this.speedKmh = 0,
    this.routing = false,
    this.rerouting = false,
    this.arrived = false,
  });

  final NavigationSession? session;
  final RouteResult? route;
  final NavigationProgress? progress;
  final OsmRoadInfo? roadInfo;
  final List<RouteAlert> alerts;
  final int maneuverIndex;
  final double speedKmh;
  final bool routing;
  final bool rerouting;
  final bool arrived;

  RouteManeuver? get currentManeuver {
    final r = route;
    if (r == null || r.maneuvers.isEmpty || maneuverIndex >= r.maneuvers.length) {
      return null;
    }
    return r.maneuvers[maneuverIndex];
  }

  RouteManeuver? get nextManeuver {
    final r = route;
    final next = maneuverIndex + 1;
    if (r == null || next >= r.maneuvers.length) return null;
    return r.maneuvers[next];
  }

  NavigationViewState copyWith({
    NavigationSession? session,
    bool clearSession = false,
    RouteResult? route,
    bool clearRoute = false,
    NavigationProgress? progress,
    bool clearProgress = false,
    OsmRoadInfo? roadInfo,
    List<RouteAlert>? alerts,
    int? maneuverIndex,
    double? speedKmh,
    bool? routing,
    bool? rerouting,
    bool? arrived,
  }) {
    return NavigationViewState(
      session: clearSession ? null : session ?? this.session,
      route: clearRoute ? null : route ?? this.route,
      progress: clearProgress ? null : progress ?? this.progress,
      roadInfo: roadInfo ?? this.roadInfo,
      alerts: alerts ?? this.alerts,
      maneuverIndex: maneuverIndex ?? this.maneuverIndex,
      speedKmh: speedKmh ?? this.speedKmh,
      routing: routing ?? this.routing,
      rerouting: rerouting ?? this.rerouting,
      arrived: arrived ?? this.arrived,
    );
  }

  @override
  List<Object?> get props => [
        session?.destination.position.latitude,
        session?.destination.position.longitude,
        route,
        progress,
        roadInfo?.roadName,
        roadInfo?.maxSpeedKmh,
        alerts,
        maneuverIndex,
        speedKmh.round(),
        routing,
        rerouting,
        arrived,
      ];
}

class NavigationController extends Cubit<NavigationViewState> {
  NavigationController() : super(const NavigationViewState());

  void setSession(NavigationSession session) => emit(state.copyWith(
        session: session,
        clearRoute: true,
        clearProgress: true,
        maneuverIndex: 0,
        arrived: false,
        alerts: const [],
      ));

  void clearSession() => emit(const NavigationViewState());

  void setRouting(bool value) => emit(state.copyWith(routing: value));
  void setRerouting(bool value) => emit(state.copyWith(rerouting: value));
  void setRoute(RouteResult route) => emit(state.copyWith(
        route: route,
        clearProgress: true,
        maneuverIndex: 0,
        routing: false,
      ));
  void setProgress(NavigationProgress progress) =>
      emit(state.copyWith(progress: progress));
  void setManeuverIndex(int index) => emit(state.copyWith(
        maneuverIndex: index,
        clearProgress: true,
      ));
  void setSpeed(double kmh) => emit(state.copyWith(speedKmh: kmh));
  void setRoadInfo(OsmRoadInfo value) => emit(state.copyWith(roadInfo: value));
  void setAlerts(List<RouteAlert> value) => emit(state.copyWith(alerts: value));
  void setArrived() => emit(state.copyWith(arrived: true, rerouting: false));
}
