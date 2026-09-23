import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/location_service.dart';
import 'package:masir/core/services/navigation_progress_service.dart';
import 'package:masir/core/services/navigation_session_service.dart';
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
        );
        if (!mounted || _controller.state.session == null) return;
        _controller.setRoute(route);
      } catch (_) {
        _controller.setRouting(false);
        return;
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
          return Stack(
            children: [
              const MapPage(),
              if (state.session != null && !state.arrived)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  left: 10,
                  right: 10,
                  child: _DriverBanner(
                    state: state,
                  ),
                ),
              if (state.session != null && !state.arrived)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: MediaQuery.paddingOf(context).bottom + 12,
                  child: _DriverBottomBar(
                    state: state,
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
    final theme = Theme.of(context);
    final current = state.currentManeuver;
    final next = state.nextManeuver;
    final progress = state.progress;
    final distance = progress?.distanceToNextManeuverMeters;
    final showLanes = current != null &&
        current.lanes.isNotEmpty &&
        distance != null &&
        distance <= 700;

    return Material(
      elevation: 9,
      color: theme.colorScheme.surface.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
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
                    _maneuverIcon(current?.type),
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
                        state.rerouting
                            ? 'محاسبه مسیر جدید…'
                            : state.routing && current == null
                                ? 'آماده‌سازی مسیر…'
                                : _formatDistance(distance),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        current?.primaryStreetName ??
                            _maneuverTitle(current?.type),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (current?.exitLabel case final exit?)
                        _ExitBadge(text: exit),
                    ],
                  ),
                ),
              ],
            ),
            if (showLanes) ...[
              const SizedBox(height: 9),
              _LaneGuidance(lanes: current.lanes),
            ],
            if (next != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    Icon(_maneuverIcon(next.type), size: 18),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'سپس ${next.primaryStreetName ?? _maneuverTitle(next.type)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
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
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final lane in lanes.take(7))
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: lane.active
                    ? theme.colorScheme.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: lane.active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: Icon(
                _laneIcon(lane.directions),
                size: 23,
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

class _DriverBottomBar extends StatelessWidget {
  const _DriverBottomBar({
    required this.state,
    required this.onSearchAlongRoute,
  });

  final NavigationViewState state;
  final VoidCallback? onSearchAlongRoute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = state.progress;
    final road = state.roadInfo;
    final limit = road?.maxSpeedKmh;
    final speeding = limit != null && state.speedKmh > limit + 4;

    return Material(
      elevation: 8,
      color: theme.colorScheme.surface.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.alerts.isNotEmpty)
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
                      avatar: Icon(_alertIcon(alert.kind), size: 16),
                      label: Text(alert.label),
                    );
                  },
                ),
              ),
            Row(
              children: [
                _Metric(
                  value: p == null ? '—' : _clock(p.arrivalTime),
                  label: 'رسیدن',
                ),
                const _VerticalDivider(),
                _Metric(
                  value: p == null
                      ? '—'
                      : '${p.remainingKilometers.toStringAsFixed(1)} km',
                  label: 'باقی‌مانده',
                ),
                const _VerticalDivider(),
                _Metric(
                  value: '${state.speedKmh.round()}',
                  label: limit == null ? 'km/h' : 'حد $limit',
                  emphasis: speeding,
                ),
                IconButton.filledTonal(
                  onPressed: onSearchAlongRoute,
                  tooltip: 'جستجو در مسیر',
                  icon: const Icon(Icons.search_rounded),
                ),
              ],
            ),
            if (road?.roadName?.isNotEmpty == true)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  [road?.roadName, road?.roadRef]
                      .whereType<String>()
                      .where((e) => e.isNotEmpty)
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }
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
            style: theme.textTheme.titleSmall?.copyWith(
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

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 30,
        color: Theme.of(context).colorScheme.outlineVariant,
      );
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
      return Icons.do_not_enter_rounded;
    case 'barrier':
      return Icons.block_rounded;
    default:
      return Icons.warning_amber_rounded;
  }
}
