import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/location_service.dart';
import 'package:masir/core/services/valhalla_service.dart';
import 'package:masir/features/search/models/place_result.dart';
import 'package:masir/features/search/presentation/search_sheet.dart';

enum _PickTarget { origin, destination }

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _mapController = MapController();
  final _location = LocationService();
  final _routing = ValhallaService();
  final _distance = const Distance();

  PlaceResult? _origin;
  PlaceResult? _destination;
  RouteResult? _route;
  LatLng? _gpsPoint;
  double _speedKmh = 0;
  DateTime? _lastRerouteAt;

  bool _routingNow = false;
  bool _routeConfirmed = false;
  bool _liveNavigation = false;
  bool _simulation = false;
  int _maneuverIndex = 0;
  _PickTarget? _pickTarget;
  StreamSubscription<dynamic>? _positionSubscription;

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _openSearch(_PickTarget target) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => SearchSheet(
        onSelected: (place) {
          setState(() {
            if (target == _PickTarget.origin) {
              _origin = place;
            } else {
              _destination = place;
            }
            _route = null;
            _routeConfirmed = false;
            _simulation = false;
            _liveNavigation = false;
            _maneuverIndex = 0;
          });
          _mapController.move(place.position, 15);
        },
      ),
    );
  }

  Future<void> _useGpsAsOrigin() async {
    try {
      final position = await _location.currentPosition();
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _gpsPoint = point;
        _origin = PlaceResult(
          title: 'موقعیت فعلی من',
          subtitle: '${position.latitude.toStringAsFixed(5)}، ${position.longitude.toStringAsFixed(5)}',
          position: point,
        );
        _route = null;
        _routeConfirmed = false;
      });
      _mapController.move(point, 16);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برای استفاده از موقعیت فعلی، GPS و دسترسی موقعیت را فعال کنید.')),
      );
    }
  }

  void _setMapPoint(LatLng point) {
    final target = _pickTarget;
    if (target == null) return;

    final place = PlaceResult(
      title: target == _PickTarget.origin ? 'مبدا انتخاب‌شده روی نقشه' : 'مقصد انتخاب‌شده روی نقشه',
      subtitle: '${point.latitude.toStringAsFixed(5)}، ${point.longitude.toStringAsFixed(5)}',
      position: point,
    );

    setState(() {
      if (target == _PickTarget.origin) {
        _origin = place;
      } else {
        _destination = place;
      }
      _pickTarget = null;
      _route = null;
      _routeConfirmed = false;
      _simulation = false;
      _liveNavigation = false;
      _maneuverIndex = 0;
    });
  }

  Future<void> _buildRoute() async {
    if (_origin == null || _destination == null || _routingNow) return;

    if (!_routing.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سرور مسیریابی واقعی تنظیم نشده است.')),
      );
      return;
    }

    setState(() => _routingNow = true);

    try {
      final result = await _routing.route(_origin!.position, _destination!.position);
      if (!mounted) return;

      setState(() {
        _route = result;
        _routeConfirmed = false;
        _simulation = false;
        _liveNavigation = false;
        _maneuverIndex = 0;
      });

      if (result.points.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: result.points,
            padding: const EdgeInsets.fromLTRB(36, 150, 36, 260),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('دریافت مسیر واقعی انجام نشد. اتصال یا سرویس مسیریابی را بررسی کنید.')),
      );
    } finally {
      if (mounted) setState(() => _routingNow = false);
    }
  }

  void _confirmRoute() {
    if (_route == null) return;
    setState(() => _routeConfirmed = true);
  }

  void _startSimulation() {
    final route = _route;
    if (route == null || route.maneuvers.isEmpty) return;
    setState(() {
      _simulation = true;
      _liveNavigation = false;
      _maneuverIndex = 0;
    });
    _focusManeuver(0);
  }

  void _focusManeuver(int index) {
    final route = _route;
    if (route == null || route.maneuvers.isEmpty) return;

    final safeIndex = index.clamp(0, route.maneuvers.length - 1);
    final maneuver = route.maneuvers[safeIndex];
    final pointIndex = maneuver.beginShapeIndex.clamp(0, route.points.length - 1);
    _mapController.move(route.points[pointIndex], 17);
  }

  void _nextManeuver() {
    final route = _route;
    if (route == null || route.maneuvers.isEmpty) return;

    final next = (_maneuverIndex + 1).clamp(0, route.maneuvers.length - 1);
    setState(() => _maneuverIndex = next);
    _focusManeuver(next);
  }

  void _previousManeuver() {
    final route = _route;
    if (route == null || route.maneuvers.isEmpty) return;

    final previous = (_maneuverIndex - 1).clamp(0, route.maneuvers.length - 1);
    setState(() => _maneuverIndex = previous);
    _focusManeuver(previous);
  }

  Future<void> _startLiveNavigation() async {
    final destination = _destination;
    if (destination == null) return;

    try {
      final position = await _location.currentPosition();
      final current = LatLng(position.latitude, position.longitude);
      final liveRoute = await _routing.route(current, destination.position);
      if (!mounted) return;

      setState(() {
        _gpsPoint = current;
        _origin = PlaceResult(
          title: 'موقعیت فعلی من',
          subtitle: '${position.latitude.toStringAsFixed(5)}، ${position.longitude.toStringAsFixed(5)}',
          position: current,
        );
        _route = liveRoute;
        _routeConfirmed = true;
        _liveNavigation = true;
        _simulation = false;
        _maneuverIndex = 0;
      });

      await _positionSubscription?.cancel();
      _positionSubscription = _location.positionStream().listen((position) {
        if (!mounted || !_liveNavigation) return;
        final point = LatLng(position.latitude, position.longitude);
        setState(() {
          _gpsPoint = point;
          _speedKmh = position.speed.isFinite && position.speed > 0 ? position.speed * 3.6 : 0;
        });
        _mapController.move(point, 17);
        _advanceLiveManeuver(point);
        unawaited(_maybeReroute(point));
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('شروع مسیریابی زنده نیاز به GPS و دسترسی موقعیت دارد.')),
      );
    }
  }

  Future<void> _maybeReroute(LatLng current) async {
    final route = _route;
    final destination = _destination;
    if (!_liveNavigation || route == null || destination == null || route.points.isEmpty) return;

    final now = DateTime.now();
    if (_lastRerouteAt != null && now.difference(_lastRerouteAt!) < const Duration(seconds: 20)) {
      return;
    }

    var nearest = double.infinity;
    final step = route.points.length > 500 ? 5 : 1;
    for (var i = 0; i < route.points.length; i += step) {
      final meters = _distance(current, route.points[i]);
      if (meters < nearest) nearest = meters;
      if (nearest < 45) return;
    }

    if (nearest < 80) return;
    _lastRerouteAt = now;

    try {
      final newRoute = await _routing.route(current, destination.position);
      if (!mounted || !_liveNavigation) return;
      setState(() {
        _route = newRoute;
        _maneuverIndex = 0;
      });
    } catch (_) {
      // Keep the last valid route; never fabricate a replacement.
    }
  }

  void _advanceLiveManeuver(LatLng current) {
    final route = _route;
    if (route == null || route.maneuvers.isEmpty) return;
    if (_maneuverIndex >= route.maneuvers.length - 1) return;

    final maneuver = route.maneuvers[_maneuverIndex];
    final endIndex = maneuver.endShapeIndex.clamp(0, route.points.length - 1);
    final meters = _distance(current, route.points[endIndex]);

    if (meters < 35) {
      setState(() => _maneuverIndex++);
    }
  }

  void _stopNavigation() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    setState(() {
      _simulation = false;
      _liveNavigation = false;
      _maneuverIndex = 0;
    });

    final route = _route;
    if (route != null && route.points.isNotEmpty) {
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: route.points,
          padding: const EdgeInsets.fromLTRB(36, 150, 36, 260),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final navigating = _simulation || _liveNavigation;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(20, 0),
              initialZoom: 2.5,
              onLongPress: (_, point) => _setMapPoint(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ir.sahand.masir',
              ),
              if (route != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: route.points,
                      strokeWidth: 6,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_origin != null)
                    Marker(
                      point: _origin!.position,
                      width: 46,
                      height: 46,
                      child: const _MapMarker(icon: Icons.trip_origin_rounded),
                    ),
                  if (_destination != null)
                    Marker(
                      point: _destination!.position,
                      width: 48,
                      height: 48,
                      child: const _MapMarker(icon: Icons.flag_rounded),
                    ),
                  if (_gpsPoint != null)
                    Marker(
                      point: _gpsPoint!,
                      width: 46,
                      height: 46,
                      child: const _GpsMarker(),
                    ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
              ),
            ],
          ),
          if (!navigating)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 12,
              left: 12,
              right: 12,
              child: _RouteInputs(
                origin: _origin,
                destination: _destination,
                onOriginSearch: () => _openSearch(_PickTarget.origin),
                onDestinationSearch: () => _openSearch(_PickTarget.destination),
                onOriginMapPick: () => setState(() => _pickTarget = _PickTarget.origin),
                onDestinationMapPick: () => setState(() => _pickTarget = _PickTarget.destination),
                onGpsOrigin: _useGpsAsOrigin,
              ),
            ),
          if (_pickTarget != null && !navigating)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 148,
              left: 24,
              right: 24,
              child: Material(
                borderRadius: BorderRadius.circular(18),
                color: Theme.of(context).colorScheme.surface,
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Text(
                    _pickTarget == _PickTarget.origin
                        ? 'روی نقشه لمس طولانی کن تا مبدا انتخاب شود.'
                        : 'روی نقشه لمس طولانی کن تا مقصد انتخاب شود.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          if (navigating && route != null && route.maneuvers.isNotEmpty)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 12,
              left: 12,
              right: 12,
              child: _NavigationBanner(
                maneuver: route.maneuvers[_maneuverIndex],
                index: _maneuverIndex,
                count: route.maneuvers.length,
                live: _liveNavigation,
                speedKmh: _speedKmh,
                onClose: _stopNavigation,
              ),
            ),
          if (!navigating && _origin != null && _destination != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 18,
              child: _RouteCard(
                route: route,
                loading: _routingNow,
                confirmed: _routeConfirmed,
                onBuild: _buildRoute,
                onConfirm: _confirmRoute,
                onLive: _startLiveNavigation,
                onSimulation: _startSimulation,
              ),
            ),
          if (_simulation && route != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 18,
              child: _SimulationControls(
                index: _maneuverIndex,
                count: route.maneuvers.length,
                onPrevious: _previousManeuver,
                onNext: _nextManeuver,
                onClose: _stopNavigation,
              ),
            ),
          if (_liveNavigation)
            Positioned(
              left: 12,
              right: 12,
              bottom: 18,
              child: SafeArea(
                top: false,
                child: FilledButton.icon(
                  onPressed: _stopNavigation,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('پایان مسیریابی'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RouteInputs extends StatelessWidget {
  const _RouteInputs({
    required this.origin,
    required this.destination,
    required this.onOriginSearch,
    required this.onDestinationSearch,
    required this.onOriginMapPick,
    required this.onDestinationMapPick,
    required this.onGpsOrigin,
  });

  final PlaceResult? origin;
  final PlaceResult? destination;
  final VoidCallback onOriginSearch;
  final VoidCallback onDestinationSearch;
  final VoidCallback onOriginMapPick;
  final VoidCallback onDestinationMapPick;
  final VoidCallback onGpsOrigin;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            _LocationRow(
              icon: Icons.trip_origin_rounded,
              label: origin?.title ?? 'انتخاب مبدا',
              onSearch: onOriginSearch,
              onMapPick: onOriginMapPick,
              trailing: IconButton(
                tooltip: 'موقعیت فعلی',
                onPressed: onGpsOrigin,
                icon: const Icon(Icons.my_location_rounded),
              ),
            ),
            const Divider(height: 8),
            _LocationRow(
              icon: Icons.flag_rounded,
              label: destination?.title ?? 'انتخاب مقصد',
              onSearch: onDestinationSearch,
              onMapPick: onDestinationMapPick,
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.icon,
    required this.label,
    required this.onSearch,
    required this.onMapPick,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSearch;
  final VoidCallback onMapPick;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onSearch,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        IconButton(
          tooltip: 'انتخاب روی نقشه',
          onPressed: onMapPick,
          icon: const Icon(Icons.add_location_alt_outlined),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.route,
    required this.loading,
    required this.confirmed,
    required this.onBuild,
    required this.onConfirm,
    required this.onLive,
    required this.onSimulation,
  });

  final RouteResult? route;
  final bool loading;
  final bool confirmed;
  final VoidCallback onBuild;
  final VoidCallback onConfirm;
  final VoidCallback onLive;
  final VoidCallback onSimulation;

  String _duration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes دقیقه';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours ساعت' : '$hours ساعت و $rest دقیقه';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (route != null)
              Row(
                children: [
                  const Icon(Icons.schedule_rounded),
                  const SizedBox(width: 6),
                  Text(_duration(route!.seconds)),
                  const SizedBox(width: 18),
                  const Icon(Icons.route_rounded),
                  const SizedBox(width: 6),
                  Text('${route!.kilometers.toStringAsFixed(1)} کیلومتر'),
                ],
              ),
            if (route != null) const SizedBox(height: 12),
            if (route == null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: loading ? null : onBuild,
                  icon: const Icon(Icons.alt_route_rounded),
                  label: Text(loading ? 'در حال دریافت مسیر…' : 'نمایش مسیر واقعی'),
                ),
              )
            else if (!confirmed)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onBuild,
                      child: const Text('محاسبه دوباره'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onConfirm,
                      child: const Text('تأیید مسیر'),
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onLive,
                      icon: const Icon(Icons.navigation_rounded),
                      label: const Text('شروع رانندگی با GPS'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 46,
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onSimulation,
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      label: const Text('مرور مرحله‌به‌مرحله مسیر'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _NavigationBanner extends StatelessWidget {
  const _NavigationBanner({
    required this.maneuver,
    required this.index,
    required this.count,
    required this.live,
    required this.speedKmh,
    required this.onClose,
  });

  final RouteManeuver maneuver;
  final int index;
  final int count;
  final bool live;
  final double speedKmh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 10,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(live ? Icons.navigation_rounded : Icons.route_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    maneuver.instruction,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.35),
                  ),
                  const SizedBox(height: 4),
                  Text('مرحله ${index + 1} از $count • ${maneuver.kilometers.toStringAsFixed(1)} کیلومتر'),
                ],
              ),
            ),
            IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
          ],
        ),
      ),
    );
  }
}

class _SimulationControls extends StatelessWidget {
  const _SimulationControls({
    required this.index,
    required this.count,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final int index;
  final int count;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            IconButton(
              onPressed: index > 0 ? onPrevious : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            Expanded(
              child: FilledButton(
                onPressed: index < count - 1 ? onNext : onClose,
                child: Text(index < count - 1 ? 'مرحله بعد' : 'پایان مسیر'),
              ),
            ),
            IconButton(
              onPressed: index < count - 1 ? onNext : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
      ),
      child: Icon(icon, color: Theme.of(context).colorScheme.primary),
    );
  }
}

class _GpsMarker extends StatelessWidget {
  const _GpsMarker();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
      ),
      child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 21),
    );
  }
}
