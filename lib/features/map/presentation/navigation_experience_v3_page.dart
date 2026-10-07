import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/location_service.dart';
import 'package:masir/core/services/navigation_progress_service.dart';
import 'package:masir/core/services/navigation_session_service.dart';
import 'package:masir/core/services/offline_route_store_service.dart';
import 'package:masir/core/services/osm_data_service.dart';
import 'package:masir/core/services/persian_guidance_service.dart';
import 'package:masir/core/services/route_awareness_service.dart';
import 'package:masir/core/services/route_poi_service.dart';
import 'package:masir/core/services/valhalla_service.dart';
import 'package:masir/core/services/voice_guidance_service.dart';
import 'package:masir/features/map/presentation/map_page.dart';
import 'package:masir/features/map/presentation/navigation_controller.dart';

class NavigationExperienceV3Page extends StatefulWidget {
  const NavigationExperienceV3Page({super.key});

  @override
  State<NavigationExperienceV3Page> createState() =>
      _NavigationExperienceV3PageState();
}

class _NavigationExperienceV3PageState
    extends State<NavigationExperienceV3Page> {
  final _controller = NavigationController();
  final _location = LocationService();
  final _session = NavigationSessionService();
  final _offlineRoutes = OfflineRouteStoreService();
  final _routing = ValhallaService();
  final _progressService = NavigationProgressService();
  final _persian = PersianGuidanceService();
  final _voice = VoiceGuidanceService();
  final _osm = OsmDataService();
  final _awareness = RouteAwarenessService();
  final _routePois = RoutePoiService();

  StreamSubscription<dynamic>? _positionSubscription;
  Timer? _sessionTimer;
  DateTime? _lastRoadRefresh;
  DateTime? _lastRerouteAt;
  LatLng? _lastCurrent;
  bool _voiceMuted = false;
  String? _lastSessionKey;
  final Set<String> _spokenStages = <String>{};

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
      _lastCurrent = current;
      final speed = position.speed.isFinite && position.speed > 0
          ? position.speed * 3.6
          : 0.0;
      _controller.setSpeed(speed);
      unawaited(_updateNavigation(current));
      unawaited(_refreshRoadContext(current));
    });
  }

  Future<void> _syncSession() async {
    final session = await _session.load();
    if (!mounted) return;
    if (session == null) {
      if (_controller.state.session != null) {
        _lastSessionKey = null;
        _spokenStages.clear();
        _controller.clearSession();
      }
      return;
    }

    final key = '${session.destination.position.latitude.toStringAsFixed(6)},'
        '${session.destination.position.longitude.toStringAsFixed(6)}|'
        '${session.viaPoints.length}';
    if (key == _lastSessionKey) return;

    _lastSessionKey = key;
    _spokenStages.clear();
    _controller.setSession(session);

    final permission = await _location.currentPermission();
    if (permission != null && _positionSubscription == null) {
      unawaited(_startPassiveTracking());
    }
  }

  Future<void> _updateNavigation(LatLng current) async {
    final state = _controller.state;
    final session = state.session;
    if (session == null || state.arrived) return;

    var route = state.route;
    if (route == null) {
      if (state.routing || !_routing.isConfigured) return;
      _controller.setRouting(true);
      try {
        route = await _routing.route(
          current,
          session.destination.position,
          viaPoints: session.viaPoints.map((e) => e.position).toList(),
          mode: session.mode,
        );
        await _offlineRoutes.save(
          destination: session.destination.position,
          mode: session.mode,
          route: route,
        );
        if (!mounted || _controller.state.session == null) return;
        _controller.setRoute(route);
      } catch (_) {
        final savedRoute = await _offlineRoutes.loadForTrip(
          current: current,
          destination: session.destination.position,
          mode: session.mode,
        );
        if (savedRoute == null) {
          _controller.setRouting(false);
          return;
        }
        route = savedRoute;
        if (!mounted || _controller.state.session == null) return;
        _controller.setRoute(savedRoute);
      }
    }

    route = _controller.state.route;
    if (route == null) return;

    var index = _controller.state.maneuverIndex;
    var progress = _progressService.calculate(
      current: current,
      destination: session.destination.position,
      route: route,
      maneuverIndex: index,
    );

    if (progress.hasArrived) {
      await _handleArrival();
      return;
    }

    if (route.maneuvers.isNotEmpty &&
        progress.distanceToNextManeuverMeters <= 28 &&
        index < route.maneuvers.length - 1) {
      index++;
      _controller.setManeuverIndex(index);
      _spokenStages.clear();
      progress = _progressService.calculate(
        current: current,
        destination: session.destination.position,
        route: route,
        maneuverIndex: index,
      );
    }

    _controller.setProgress(progress);
    await _speakIfNeeded(route, progress, index);
    unawaited(_maybeReroute(current, progress));
  }

  Future<void> _speakIfNeeded(
    RouteResult route,
    NavigationProgress progress,
    int index,
  ) async {
    if (_voiceMuted) return;
    if (route.maneuvers.isEmpty || index >= route.maneuvers.length) return;
    final stage = _progressService.promptStageForDistance(
      progress.distanceToNextManeuverMeters,
    );
    if (stage == null) return;
    final key = '$index:${stage.name}';
    if (!_spokenStages.add(key)) return;

    final next = index + 1 < route.maneuvers.length
        ? route.maneuvers[index + 1]
        : null;
    await _voice.speak(
      _persian.stagedInstruction(
        route.maneuvers[index],
        stage,
        distanceMeters: progress.distanceToNextManeuverMeters,
        nextManeuver: next,
      ),
      force: stage == VoicePromptStage.now,
    );
  }

  Future<void> _maybeReroute(
    LatLng current,
    NavigationProgress progress,
  ) async {
    final state = _controller.state;
    final session = state.session;
    if (session == null ||
        state.rerouting ||
        progress.offRouteMeters <
            NavigationProgressService.rerouteThresholdMeters) {
      return;
    }

    final now = DateTime.now();
    if (_lastRerouteAt != null &&
        now.difference(_lastRerouteAt!) < const Duration(seconds: 18)) {
      return;
    }
    _lastRerouteAt = now;
    _controller.setRerouting(true);
    try {
      final newRoute = await _routing.route(
        current,
        session.destination.position,
        viaPoints: session.viaPoints.map((e) => e.position).toList(),
        mode: session.mode,
      );
      await _offlineRoutes.save(
        destination: session.destination.position,
        mode: session.mode,
        route: newRoute,
      );
      if (!mounted || _controller.state.session == null) return;
      _spokenStages.clear();
      _controller.setRoute(newRoute);
      await _voice.speak('مسیر دوباره محاسبه شد', force: true);
    } catch (_) {
      // Keep the last valid route. No fabricated fallback data.
    } finally {
      _controller.setRerouting(false);
    }
  }

  Future<void> _refreshRoadContext(LatLng current) async {
    final now = DateTime.now();
    if (_lastRoadRefresh != null &&
        now.difference(_lastRoadRefresh!) < const Duration(seconds: 25)) {
      return;
    }
    _lastRoadRefresh = now;
    try {
      final results = await Future.wait([
        _osm.roadInfo(current),
        _awareness.nearbyAlerts(current),
      ]);
      if (!mounted) return;
      _controller.setRoadInfo(results[0] as OsmRoadInfo);
      _controller.setAlerts(results[1] as List<RouteAlert>);
    } catch (_) {
      // Preserve last real data when external public services are unavailable.
    }
  }

  Future<void> _handleArrival() async {
    if (_controller.state.arrived) return;
    _controller.setArrived();
    await _voice.announceArrival();
    await _session.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('به مقصد رسیدید')),
    );
  }

  void _openAlongRouteSearch(RouteResult route) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _AlongRouteSheet(
        route: route,
        service: _routePois,
      ),
    );
  }

  Future<void> _forceReroute() async {
    final current = _lastCurrent;
    final session = _controller.state.session;
    if (current == null || session == null || _controller.state.rerouting) {
      return;
    }

    _controller.setRerouting(true);
    try {
      final route = await _routing.route(
        current,
        session.destination.position,
        viaPoints: session.viaPoints.map((e) => e.position).toList(),
        mode: session.mode,
      );
      await _offlineRoutes.save(
        destination: session.destination.position,
        mode: session.mode,
        route: route,
      );
      if (!mounted || _controller.state.session == null) return;
      _spokenStages.clear();
      _controller.setRoute(route);
      if (!_voiceMuted) {
        await _voice.speak('برگشت به مسیر انجام شد', force: true);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('محاسبه دوباره مسیر انجام نشد.')),
      );
    } finally {
      _controller.setRerouting(false);
    }
  }

  Future<void> _toggleVoice() async {
    setState(() => _voiceMuted = !_voiceMuted);
    if (_voiceMuted) await _voice.stop();
  }

  Future<void> _stopDriverNavigation() async {
    await _voice.stop();
    await _session.clear();
    _lastSessionKey = null;
    _spokenStages.clear();
    _controller.clearSession();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _positionSubscription?.cancel();
    _voice.stop();
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _controller,
      child: BlocBuilder<NavigationController, NavigationViewState>(
        builder: (context, state) {
          final active = state.session != null && !state.arrived;
          final offRoute = state.progress?.offRouteMeters ?? 0;

          return Stack(
            children: [
              const MapPage(showNavigationChrome: false),
              if (active)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 6,
                  left: 6,
                  right: 6,
                  child: _DriverBanner(
                    state: state,
                  ),
                ),
              if (active && offRoute >= 45)
                Positioned(
                  left: 18,
                  bottom: MediaQuery.paddingOf(context).bottom + 136,
                  child: FilledButton.icon(
                    onPressed: state.rerouting ? null : _forceReroute,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 13,
                      ),
                    ),
                    icon: state.rerouting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.navigation_rounded),
                    label: const Text(
                      'برگرد به مسیر',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              if (active && state.roadInfo?.maxSpeedKmh != null)
                Positioned(
                  right: 16,
                  top: MediaQuery.paddingOf(context).top + 194,
                  child: _SpeedLimitBadge(
                    limit: state.roadInfo!.maxSpeedKmh!,
                    speed: state.speedKmh,
                  ),
                ),
              if (active)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: MediaQuery.paddingOf(context).bottom + 8,
                  child: _DriverBottomBar(
                    state: state,
                    muted: _voiceMuted,
                    onToggleVoice: _toggleVoice,
                    onStop: _stopDriverNavigation,
                    onSearchAlongRoute: state.route == null
                        ? null
                        : () => _openAlongRouteSearch(state.route!),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DriverBanner extends StatelessWidget {
  const _DriverBanner({required this.state});

  final NavigationViewState state;

  @override
  Widget build(BuildContext context) {
    final current = state.currentManeuver;
    final next = state.nextManeuver;
    final progress = state.progress;
    final distance = progress?.distanceToNextManeuverMeters;
    final showLanes = current != null &&
        current.lanes.isNotEmpty &&
        distance != null &&
        distance <= 700;

    return Material(
      elevation: 12,
      color: const Color(0xFF101012),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              textDirection: TextDirection.rtl,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _maneuverIcon(current?.type),
                  size: 72,
                  color: Colors.white,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        state.rerouting
                            ? 'مسیر جدید…'
                            : state.routing && current == null
                                ? 'در حال آماده‌سازی…'
                                : _formatDistance(distance),
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 31,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        current?.primaryStreetName ??
                            _maneuverTitle(current?.type),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          color: Color(0xFF78C7F4),
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (current?.exitLabel case final exit?) ...[
                        const SizedBox(height: 7),
                        _ExitBadge(text: exit),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showLanes)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: _LaneGuidance(lanes: current.lanes),
            ),
          if (next != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Container(
                margin: const EdgeInsets.only(left: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF2A292F),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  textDirection: TextDirection.rtl,
                  children: [
                    const Text(
                      'و بعد',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      _maneuverIcon(next.type),
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 185),
                      child: Text(
                        next.primaryStreetName ??
                            _maneuverTitle(next.type),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 5),
        ],
      ),
    );
  }
}

class _ExitBadge extends StatelessWidget {
  const _ExitBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 3),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _LaneGuidance extends StatelessWidget {
  const _LaneGuidance({required this.lanes});
  final List<RouteLane> lanes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1B20),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final lane in lanes.take(7))
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: lane.active
                    ? const Color(0xFF8B2CF5)
                    : const Color(0xFF2A292F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: lane.active
                      ? const Color(0xFFB77CFF)
                      : const Color(0xFF4B4950),
                ),
              ),
              child: Icon(
                _laneIcon(lane.directions),
                size: 24,
                color: lane.active ? Colors.white : Colors.white54,
              ),
            ),
        ],
      ),
    );
  }
}

class _DriverBottomBar extends StatelessWidget {
  const _DriverBottomBar({
    required this.state,
    required this.muted,
    required this.onToggleVoice,
    required this.onStop,
    required this.onSearchAlongRoute,
  });

  final NavigationViewState state;
  final bool muted;
  final VoidCallback onToggleVoice;
  final VoidCallback onStop;
  final VoidCallback? onSearchAlongRoute;

  @override
  Widget build(BuildContext context) {
    final p = state.progress;
    final remainingMinutes =
        p == null ? null : (p.remainingSeconds / 60).round();
    final road = state.roadInfo;

    return Material(
      elevation: 14,
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF17171A)
          : Colors.white,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _DriverSquareButton(
                  icon: muted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  tooltip: muted ? 'فعال کردن صدا' : 'بی‌صدا',
                  onPressed: onToggleVoice,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        textDirection: TextDirection.rtl,
                        children: [
                          const Text(
                            'رسیدن',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Text(
                            p == null ? '—' : _clock(p.arrivalTime),
                            style: const TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        p == null
                            ? 'در حال محاسبه…'
                            : '${p.remainingKilometers.toStringAsFixed(1)} کیلومتر   ${remainingMinutes ?? 0} دقیقه',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (road?.roadName?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            [road?.roadName, road?.roadRef]
                                .whereType<String>()
                                .where((e) => e.isNotEmpty)
                                .join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.rtl,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                ),
                _DriverSquareButton(
                  icon: Icons.search_rounded,
                  tooltip: 'جستجو در مسیر',
                  onPressed: onSearchAlongRoute,
                ),
              ],
            ),
            if (state.alerts.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: state.alerts.length.clamp(0, 4),
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final alert = state.alerts[index];
                    return Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(_alertIcon(alert.kind), size: 15),
                      label: Text(alert.label),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 2),
            TextButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('پایان مسیریابی'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverSquareButton extends StatelessWidget {
  const _DriverSquareButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 58,
            height: 58,
            child: Icon(icon, size: 29),
          ),
        ),
      ),
    );
  }
}

class _SpeedLimitBadge extends StatelessWidget {
  const _SpeedLimitBadge({
    required this.limit,
    required this.speed,
  });

  final int limit;
  final double speed;

  @override
  Widget build(BuildContext context) {
    final speeding = speed > limit + 4;
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: speeding ? Colors.red : const Color(0xFF2B2B2B),
          width: 4,
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            offset: Offset(0, 3),
            color: Color(0x33000000),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$limit',
        style: TextStyle(
          color: speeding ? Colors.red : Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AlongRouteSheet extends StatefulWidget {
  const _AlongRouteSheet({required this.route, required this.service});
  final RouteResult route;
  final RoutePoiService service;

  @override
  State<_AlongRouteSheet> createState() => _AlongRouteSheetState();
}

class _AlongRouteSheetState extends State<_AlongRouteSheet> {
  String _category = 'fuel';

  static const _labels = <String, String>{
    'fuel': 'سوخت',
    'parking': 'پارکینگ',
    'pharmacy': 'داروخانه',
    'hospital': 'بیمارستان',
    'cafe': 'کافه',
    'restaurant': 'رستوران',
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'جستجو در امتداد مسیر',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final entry in _labels.entries)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: ChoiceChip(
                        selected: _category == entry.key,
                        label: Text(entry.value),
                        onSelected: (_) => setState(() => _category = entry.key),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: FutureBuilder<List<OsmPoi>>(
                key: ValueKey(_category),
                future: widget.service.searchAlongRoute(
                  widget.route,
                  categories: {_category},
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(28),
                      child: CircularProgressIndicator(),
                    );
                  }
                  final items = snapshot.data ?? const <OsmPoi>[];
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('موردی با داده واقعی OSM در امتداد مسیر پیدا نشد.'),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final poi = items[index];
                      return ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(poi.name),
                        subtitle: Text(_labels[poi.category] ?? poi.category),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDistance(double? meters) {
  if (meters == null) return 'مسیریابی زنده';
  if (meters < 1000) return '${meters.round()} متر';
  return '${(meters / 1000).toStringAsFixed(1)} کیلومتر';
}

String _clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

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
      return 'ورود به میدان';
    case 27:
      return 'خروج از میدان';
    case 31:
      return 'مقصد';
    default:
      return 'ادامه مسیر';
  }
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
      return Icons.subdirectory_arrow_right_rounded;
    case 17:
    case 18:
      return Icons.subdirectory_arrow_left_rounded;
    case 26:
    case 27:
      return Icons.roundabout_right_rounded;
    case 31:
      return Icons.flag_rounded;
    default:
      return Icons.straight_rounded;
  }
}

IconData _laneIcon(List<String> directions) {
  final text = directions.join(' ').toLowerCase();
  if (text.contains('slight_right')) return Icons.turn_slight_right_rounded;
  if (text.contains('slight_left')) return Icons.turn_slight_left_rounded;
  if (text.contains('right')) return Icons.turn_right_rounded;
  if (text.contains('left')) return Icons.turn_left_rounded;
  if (text.contains('uturn')) return Icons.u_turn_left_rounded;
  return Icons.straight_rounded;
}

IconData _alertIcon(String kind) {
  switch (kind) {
    case 'construction':
      return Icons.construction_rounded;
    case 'toll':
      return Icons.toll_rounded;
    case 'ferry':
      return Icons.directions_boat_rounded;
    case 'restricted':
      return Icons.block_rounded;
    case 'barrier':
      return Icons.block_rounded;
    default:
      return Icons.warning_amber_rounded;
  }
}
