import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/location_service.dart';
import 'package:masir/core/services/navigation_progress_service.dart';
import 'package:masir/core/services/navigation_session_service.dart';
import 'package:masir/core/services/osm_data_service.dart';
import 'package:masir/core/services/persian_guidance_service.dart';
import 'package:masir/core/services/valhalla_service.dart';
import 'package:masir/core/services/voice_guidance_service.dart';
import 'package:masir/features/map/presentation/map_page.dart';

class NavigationExperiencePage extends StatefulWidget {
  const NavigationExperiencePage({super.key});

  @override
  State<NavigationExperiencePage> createState() => _NavigationExperiencePageState();
}

class _NavigationExperiencePageState extends State<NavigationExperiencePage> {
  final _location = LocationService();
  final _session = NavigationSessionService();
  final _routing = ValhallaService();
  final _progressService = NavigationProgressService();
  final _persian = PersianGuidanceService();
  final _voice = VoiceGuidanceService();
  final _osm = OsmDataService();

  StreamSubscription<dynamic>? _positionSubscription;
  Timer? _sessionTimer;
  NavigationSession? _activeSession;
  RouteResult? _route;
  NavigationProgress? _progress;
  OsmRoadInfo? _roadInfo;
  int _maneuverIndex = 0;
  double _speedKmh = 0;
  bool _routingNow = false;
  bool _rerouting = false;
  bool _arrived = false;
  String? _lastSessionKey;
  DateTime? _lastRerouteAt;
  DateTime? _lastRoadInfoAt;
  final Set<String> _spokenStages = {};

  @override
  void initState() {
    super.initState();
    unawaited(_startPassiveTracking());
    unawaited(_syncSession());
    _sessionTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _syncSession(),
    );
  }

  Future<void> _startPassiveTracking() async {
    final permission = await _location.currentPermission();
    if (permission == null) return;

    await _positionSubscription?.cancel();
    _positionSubscription = _location.positionStream().listen((position) {
      if (!mounted) return;
      final current = LatLng(position.latitude, position.longitude);
      setState(() {
        _speedKmh = position.speed.isFinite && position.speed > 0
            ? position.speed * 3.6
            : 0;
      });
      unawaited(_refreshRoadInfo(current));
      unawaited(_updateNavigation(current));
    });
  }

  Future<void> _syncSession() async {
    final session = await _session.load();
    if (!mounted) return;

    if (session == null) {
      if (_activeSession != null) {
        setState(() {
          _activeSession = null;
          _route = null;
          _progress = null;
          _maneuverIndex = 0;
          _arrived = false;
          _lastSessionKey = null;
          _spokenStages.clear();
        });
      }
      return;
    }

    final key = '${session.destination.position.latitude.toStringAsFixed(6)},'
        '${session.destination.position.longitude.toStringAsFixed(6)}|'
        '${session.viaPoints.length}';
    if (key == _lastSessionKey) return;

    setState(() {
      _activeSession = session;
      _route = null;
      _progress = null;
      _maneuverIndex = 0;
      _arrived = false;
      _lastSessionKey = key;
      _spokenStages.clear();
    });

    final permission = await _location.currentPermission();
    if (permission != null && _positionSubscription == null) {
      unawaited(_startPassiveTracking());
    }
  }

  Future<void> _updateNavigation(LatLng current) async {
    final session = _activeSession;
    if (session == null || _arrived) return;

    var route = _route;
    if (route == null) {
      if (_routingNow || !_routing.isConfigured) return;
      setState(() => _routingNow = true);
      try {
        route = await _routing.route(
          current,
          session.destination.position,
          viaPoints: session.viaPoints.map((e) => e.position).toList(),
        );
        if (!mounted) return;
        setState(() {
          _route = route;
          _maneuverIndex = 0;
          _spokenStages.clear();
        });
      } finally {
        if (mounted) setState(() => _routingNow = false);
      }
    }

    route = _route;
    if (route == null) return;

    var progress = _progressService.calculate(
      current: current,
      destination: session.destination.position,
      route: route,
      maneuverIndex: _maneuverIndex,
    );

    if (progress.hasArrived) {
      await _handleArrival();
      return;
    }

    if (route.maneuvers.isNotEmpty &&
        progress.distanceToNextManeuverMeters <= 28 &&
        _maneuverIndex < route.maneuvers.length - 1) {
      setState(() {
        _maneuverIndex++;
        _spokenStages.clear();
      });
      progress = _progressService.calculate(
        current: current,
        destination: session.destination.position,
        route: route,
        maneuverIndex: _maneuverIndex,
      );
    }

    if (mounted) setState(() => _progress = progress);
    await _speakIfNeeded(route, progress);
    unawaited(_maybeReroute(current, progress));
  }

  Future<void> _speakIfNeeded(
    RouteResult route,
    NavigationProgress progress,
  ) async {
    if (route.maneuvers.isEmpty || _maneuverIndex >= route.maneuvers.length) return;
    final stage = _progressService.promptStageForDistance(
      progress.distanceToNextManeuverMeters,
    );
    if (stage == null) return;

    final key = '$_maneuverIndex:${stage.name}';
    if (!_spokenStages.add(key)) return;

    await _voice.speak(
      _persian.stagedInstruction(
        route.maneuvers[_maneuverIndex],
        stage,
        distanceMeters: progress.distanceToNextManeuverMeters,
      ),
      force: stage == VoicePromptStage.now,
    );
  }

  Future<void> _maybeReroute(
    LatLng current,
    NavigationProgress progress,
  ) async {
    final session = _activeSession;
    if (session == null || _rerouting ||
        progress.offRouteMeters < NavigationProgressService.rerouteThresholdMeters) {
      return;
    }

    final now = DateTime.now();
    if (_lastRerouteAt != null &&
        now.difference(_lastRerouteAt!) < const Duration(seconds: 18)) {
      return;
    }
    _lastRerouteAt = now;
    setState(() => _rerouting = true);

    try {
      final route = await _routing.route(
        current,
        session.destination.position,
        viaPoints: session.viaPoints.map((e) => e.position).toList(),
      );
      if (!mounted) return;
      setState(() {
        _route = route;
        _maneuverIndex = 0;
        _progress = null;
        _spokenStages.clear();
      });
      await _voice.speak('مسیر دوباره محاسبه شد', force: true);
    } catch (_) {
      // Keep last valid route; never fabricate navigation data.
    } finally {
      if (mounted) setState(() => _rerouting = false);
    }
  }

  Future<void> _refreshRoadInfo(LatLng current) async {
    final now = DateTime.now();
    if (_lastRoadInfoAt != null &&
        now.difference(_lastRoadInfoAt!) < const Duration(seconds: 25)) {
      return;
    }
    _lastRoadInfoAt = now;
    try {
      final info = await _osm.roadInfo(current);
      if (mounted) setState(() => _roadInfo = info);
    } catch (_) {}
  }

  Future<void> _handleArrival() async {
    if (_arrived) return;
    setState(() => _arrived = true);
    await _voice.announceArrival();
    await _session.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('به مقصد رسیدید')),
    );
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _positionSubscription?.cancel();
    _voice.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final maneuver = route != null &&
            route.maneuvers.isNotEmpty &&
            _maneuverIndex < route.maneuvers.length
        ? route.maneuvers[_maneuverIndex]
        : null;

    return Stack(
      children: [
        const MapPage(),
        if (_activeSession != null && !_arrived)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 10,
            left: 10,
            right: 10,
            child: _NavigationBannerV2(
              maneuver: maneuver,
              progress: _progress,
              routing: _routingNow,
              rerouting: _rerouting,
            ),
          ),
        if (_activeSession != null && !_arrived)
          Positioned(
            left: 12,
            right: 12,
            bottom: MediaQuery.paddingOf(context).bottom + 12,
            child: _NavigationBottomBar(
              progress: _progress,
              speedKmh: _speedKmh,
              roadInfo: _roadInfo,
            ),
          ),
      ],
    );
  }
}

class _NavigationBannerV2 extends StatelessWidget {
  const _NavigationBannerV2({
    required this.maneuver,
    required this.progress,
    required this.routing,
    required this.rerouting,
  });

  final RouteManeuver? maneuver;
  final NavigationProgress? progress;
  final bool routing;
  final bool rerouting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = maneuver;
    final p = progress;
    final street = m?.primaryStreetName;
    final exit = m?.exitLabel;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(22),
      color: theme.colorScheme.surface.withValues(alpha: 0.97),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    _maneuverIcon(m?.type),
                    size: 38,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rerouting
                            ? 'در حال محاسبه مسیر جدید…'
                            : routing && m == null
                                ? 'در حال آماده‌سازی مسیر…'
                                : _distance(p?.distanceToNextManeuverMeters),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        street?.isNotEmpty == true
                            ? street!
                            : _maneuverTitle(m?.type),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (exit?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            exit!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (m != null && m.lanes.isNotEmpty) ...[
              const SizedBox(height: 10),
              _LaneGuidance(lanes: m.lanes),
            ],
          ],
        ),
      ),
    );
  }

  static String _distance(double? meters) {
    if (meters == null) return 'مسیریابی زنده';
    if (meters < 1000) return '${meters.round()} متر';
    return '${(meters / 1000).toStringAsFixed(1)} کیلومتر';
  }
}

class _LaneGuidance extends StatelessWidget {
  const _LaneGuidance({required this.lanes});
  final List<RouteLane> lanes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final lane in lanes)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Icon(
                _laneIcon(lane.directions),
                size: 27,
                color: lane.active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
            ),
        ],
      ),
    );
  }
}

class _NavigationBottomBar extends StatelessWidget {
  const _NavigationBottomBar({
    required this.progress,
    required this.speedKmh,
    required this.roadInfo,
  });

  final NavigationProgress? progress;
  final double speedKmh;
  final OsmRoadInfo? roadInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = progress;
    final limit = roadInfo?.maxSpeedKmh;
    final speeding = limit != null && speedKmh > limit + 4;

    return Material(
      elevation: 7,
      borderRadius: BorderRadius.circular(20),
      color: theme.colorScheme.surface.withValues(alpha: 0.97),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            _Metric(value: p == null ? '—' : _eta(p.arrivalTime), label: 'رسیدن'),
            const _Divider(),
            _Metric(
              value: p == null ? '—' : '${p.remainingKilometers.toStringAsFixed(1)} km',
              label: 'باقی‌مانده',
            ),
            const _Divider(),
            _Metric(
              value: '${speedKmh.round()}',
              label: limit == null ? 'km/h' : 'حد $limit',
              emphasis: speeding,
            ),
          ],
        ),
      ),
    );
  }

  static String _eta(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    this.emphasis = false,
  });
  final String value;
  final String label;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: emphasis ? theme.colorScheme.error : null,
            ),
          ),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 34,
        color: Theme.of(context).colorScheme.outlineVariant,
      );
}

IconData _maneuverIcon(int? type) {
  switch (type) {
    case 4:
    case 5:
    case 6:
      return Icons.turn_right_rounded;
    case 8:
    case 9:
    case 10:
      return Icons.turn_left_rounded;
    case 15:
    case 16:
      return Icons.fork_right_rounded;
    case 17:
    case 18:
      return Icons.fork_left_rounded;
    case 26:
    case 27:
      return Icons.roundabout_right_rounded;
    case 31:
      return Icons.flag_rounded;
    default:
      return Icons.straight_rounded;
  }
}

String _maneuverTitle(int? type) {
  switch (type) {
    case 4:
    case 5:
    case 6:
      return 'به راست بپیچید';
    case 8:
    case 9:
    case 10:
      return 'به چپ بپیچید';
    case 15:
    case 16:
      return 'خروجی سمت راست';
    case 17:
    case 18:
      return 'خروجی سمت چپ';
    case 26:
      return 'وارد میدان شوید';
    case 27:
      return 'از میدان خارج شوید';
    case 31:
      return 'مقصد';
    default:
      return 'مستقیم ادامه دهید';
  }
}

IconData _laneIcon(List<String> directions) {
  final values = directions.map((e) => e.toLowerCase()).toList();
  if (values.any((e) => e.contains('left'))) return Icons.arrow_upward_rounded;
  if (values.any((e) => e.contains('right'))) return Icons.arrow_upward_rounded;
  if (values.any((e) => e.contains('uturn'))) return Icons.u_turn_left_rounded;
  return Icons.arrow_upward_rounded;
}
