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

class MapExperiencePage extends StatefulWidget {
  const MapExperiencePage({super.key});

  @override
  State<MapExperiencePage> createState() => _MapExperiencePageState();
}

class _MapExperiencePageState extends State<MapExperiencePage> {
  final _location = LocationService();
  final _osm = OsmDataService();
  final _session = NavigationSessionService();
  final _routing = ValhallaService();
  final _progressService = NavigationProgressService();
  final _persian = PersianGuidanceService();
  final _voice = VoiceGuidanceService();

  StreamSubscription<dynamic>? _positionSubscription;
  Timer? _sessionTimer;
  DateTime? _lastRoadRefresh;
  DateTime? _lastRerouteAt;
  double _speedKmh = 0;
  OsmRoadInfo? _roadInfo;
  bool _locationReady = false;

  NavigationSession? _activeSession;
  RouteResult? _liveRoute;
  NavigationProgress? _progress;
  int _maneuverIndex = 0;
  bool _routingNow = false;
  bool _rerouting = false;
  bool _arrived = false;
  String? _lastSessionKey;
  final Set<String> _spokenStages = <String>{};

  @override
  void initState() {
    super.initState();
    _startPassiveRoadContext();
    _sessionTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _syncNavigationSession(),
    );
    unawaited(_syncNavigationSession());
  }

  Future<void> _startPassiveRoadContext() async {
    try {
      final permission = await _location.currentPermission();
      if (permission == null) return;
      if (!mounted) return;
      setState(() => _locationReady = true);

      await _positionSubscription?.cancel();
      _positionSubscription = _location.positionStream().listen((position) {
        if (!mounted) return;
        final point = LatLng(position.latitude, position.longitude);
        final speed = position.speed.isFinite && position.speed > 0
            ? position.speed * 3.6
            : 0.0;
        setState(() => _speedKmh = speed);
        unawaited(_refreshRoadContext(point));
        unawaited(_updateLiveNavigation(point));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _locationReady = false);
    }
  }

  Future<void> _syncNavigationSession() async {
    final session = await _session.load();
    if (!mounted) return;

    if (session == null) {
      if (_activeSession != null || _liveRoute != null || _progress != null) {
        setState(() {
          _activeSession = null;
          _liveRoute = null;
          _progress = null;
          _maneuverIndex = 0;
          _rerouting = false;
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

    if (_lastSessionKey == key) return;

    setState(() {
      _activeSession = session;
      _liveRoute = null;
      _progress = null;
      _maneuverIndex = 0;
      _arrived = false;
      _lastSessionKey = key;
      _spokenStages.clear();
    });

    if (!_locationReady) {
      unawaited(_startPassiveRoadContext());
    }
  }

  Future<void> _updateLiveNavigation(LatLng current) async {
    final session = _activeSession;
    if (session == null || _arrived) return;

    var route = _liveRoute;
    if (route == null) {
      if (_routingNow || !_routing.isConfigured) return;
      setState(() => _routingNow = true);
      try {
        route = await _routing.route(
          current,
          session.destination.position,
          viaPoints: session.viaPoints.map((e) => e.position).toList(),
        );
        if (!mounted || _activeSession == null) return;
        setState(() {
          _liveRoute = route;
          _maneuverIndex = 0;
          _progress = null;
          _spokenStages.clear();
        });
      } catch (_) {
        return;
      } finally {
        if (mounted) setState(() => _routingNow = false);
      }
    }

    route = _liveRoute;
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
        _spokenStages.removeWhere((key) => !key.startsWith('$_maneuverIndex:'));
      });
      progress = _progressService.calculate(
        current: current,
        destination: session.destination.position,
        route: route,
        maneuverIndex: _maneuverIndex,
      );
    }

    if (mounted) setState(() => _progress = progress);

    await _maybeSpeakGuidance(route, progress);
    unawaited(_maybeReroute(current, progress));
  }

  Future<void> _maybeSpeakGuidance(
    RouteResult route,
    NavigationProgress progress,
  ) async {
    if (route.maneuvers.isEmpty || _maneuverIndex >= route.maneuvers.length) return;

    final stage = _progressService.promptStageForDistance(
      progress.distanceToNextManeuverMeters,
    );
    if (stage == null) return;

    final key = '$_maneuverIndex:${stage.name}';
    if (_spokenStages.contains(key)) return;
    _spokenStages.add(key);

    final text = _persian.stagedInstruction(
      route.maneuvers[_maneuverIndex],
      stage,
      distanceMeters: progress.distanceToNextManeuverMeters,
    );
    await _voice.speak(text, force: stage == VoicePromptStage.now);
  }

  Future<void> _maybeReroute(
    LatLng current,
    NavigationProgress progress,
  ) async {
    final session = _activeSession;
    final route = _liveRoute;
    if (session == null || route == null || _rerouting) return;
    if (progress.offRouteMeters < NavigationProgressService.rerouteThresholdMeters) {
      return;
    }

    final now = DateTime.now();
    if (_lastRerouteAt != null &&
        now.difference(_lastRerouteAt!) < const Duration(seconds: 18)) {
      return;
    }

    _lastRerouteAt = now;
    if (mounted) setState(() => _rerouting = true);

    try {
      final newRoute = await _routing.route(
        current,
        session.destination.position,
        viaPoints: session.viaPoints.map((e) => e.position).toList(),
      );
      if (!mounted || _activeSession == null) return;
      setState(() {
        _liveRoute = newRoute;
        _maneuverIndex = 0;
        _progress = null;
        _spokenStages.clear();
      });
      await _voice.speak('مسیر دوباره محاسبه شد', force: true);
    } catch (_) {
      // Keep the last valid route. No fake fallback route is created.
    } finally {
      if (mounted) setState(() => _rerouting = false);
    }
  }

  Future<void> _handleArrival() async {
    if (_arrived) return;
    setState(() {
      _arrived = true;
      _rerouting = false;
    });
    await _voice.announceArrival();
    await _session.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('به مقصد رسیدید'),
        duration: Duration(seconds: 5),
      ),
    );
  }

  Future<void> _refreshRoadContext(LatLng point) async {
    final now = DateTime.now();
    if (_lastRoadRefresh != null &&
        now.difference(_lastRoadRefresh!) < const Duration(seconds: 25)) {
      return;
    }
    _lastRoadRefresh = now;

    try {
      final info = await _osm.roadInfo(point);
      if (!mounted) return;
      setState(() => _roadInfo = info);
    } catch (_) {
      // Keep the last valid road context instead of fabricating data.
    }
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
    final showRoadContext = _locationReady && _roadInfo != null;
    final showLiveProgress = _activeSession != null &&
        (_liveRoute != null || _routingNow) &&
        !_arrived;

    return Stack(
      children: [
        const MapPage(),
        if (showLiveProgress)
          Positioned(
            left: 12,
            right: 12,
            bottom: MediaQuery.paddingOf(context).bottom +
                (showRoadContext ? 88 : 12),
            child: IgnorePointer(
              child: _LiveNavigationStatusBar(
                progress: _progress,
                maneuver: _liveRoute != null &&
                        _liveRoute!.maneuvers.isNotEmpty &&
                        _maneuverIndex < _liveRoute!.maneuvers.length
                    ? _liveRoute!.maneuvers[_maneuverIndex]
                    : null,
                routing: _routingNow,
                rerouting: _rerouting,
              ),
            ),
          ),
        if (showRoadContext)
          Positioned(
            left: 12,
            right: 12,
            bottom: MediaQuery.paddingOf(context).bottom + 12,
            child: IgnorePointer(
              child: _RoadContextBar(
                speedKmh: _speedKmh,
                roadInfo: _roadInfo!,
              ),
            ),
          ),
      ],
    );
  }
}

class _LiveNavigationStatusBar extends StatelessWidget {
  const _LiveNavigationStatusBar({
    required this.progress,
    required this.maneuver,
    required this.routing,
    required this.rerouting,
  });

  final NavigationProgress? progress;
  final RouteManeuver? maneuver;
  final bool routing;
  final bool rerouting;

  String _distance(double meters) {
    if (meters < 1000) return '${meters.round()} متر';
    return '${(meters / 1000).toStringAsFixed(1)} کیلومتر';
  }

  String _duration(double seconds) {
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '$minutes دقیقه';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours ساعت' : '$hours ساعت و $rest دقیقه';
  }

  String _time(DateTime value) {
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = progress;

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: const [
              BoxShadow(
                blurRadius: 18,
                offset: Offset(0, 7),
                color: Color(0x22000000),
              ),
            ],
          ),
          child: routing && p == null
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('در حال آماده‌سازی مسیریابی زنده…'),
                  ],
                )
              : Row(
                  children: [
                    Icon(
                      rerouting ? Icons.sync_rounded : Icons.navigation_rounded,
                      color: rerouting
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            rerouting
                                ? 'در حال محاسبه مسیر جدید…'
                                : maneuver == null
                                    ? 'مسیریابی زنده'
                                    : '${_distance(p?.distanceToNextManeuverMeters ?? 0)} تا حرکت بعدی',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (p != null)
                            Text(
                              '${p.remainingKilometers.toStringAsFixed(1)} km · ${_duration(p.remainingSeconds)} · رسیدن ${_time(p.arrivalTime)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    if (p != null && p.offRouteMeters >= 50)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: Text(
                          '${p.offRouteMeters.round()}m',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: p.offRouteMeters >=
                                    NavigationProgressService.rerouteThresholdMeters
                                ? theme.colorScheme.error
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _RoadContextBar extends StatelessWidget {
  const _RoadContextBar({
    required this.speedKmh,
    required this.roadInfo,
  });

  final double speedKmh;
  final OsmRoadInfo roadInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roadTitle = [
      roadInfo.roadName,
      roadInfo.roadRef,
    ].whereType<String>().where((e) => e.trim().isNotEmpty).join(' · ');

    final speeding = roadInfo.maxSpeedKmh != null &&
        speedKmh > roadInfo.maxSpeedKmh! + 4;

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: const [
              BoxShadow(
                blurRadius: 18,
                offset: Offset(0, 7),
                color: Color(0x22000000),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: speeding
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
                child: Text(
                  speedKmh.round().toString(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: speeding ? theme.colorScheme.error : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      roadTitle.isEmpty ? 'جاده فعلی' : roadTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Text(
                          roadInfo.maxSpeedKmh == null
                              ? 'حد سرعت: نامشخص'
                              : 'حد سرعت: ${roadInfo.maxSpeedKmh} km/h',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (roadInfo.surface?.trim().isNotEmpty == true)
                          Text(
                            'سطح: ${roadInfo.surface}',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (roadInfo.speedCameraNearby)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 10),
                  child: Icon(
                    Icons.photo_camera_outlined,
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
