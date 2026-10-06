import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/location_service.dart';
import 'package:masir/core/services/navigation_preferences_service.dart';
import 'package:masir/core/services/navigation_session_service.dart';
import 'package:masir/core/services/offline_map_catalog_service.dart';
import 'package:masir/core/services/offline_route_store_service.dart';
import 'package:masir/core/services/persian_guidance_service.dart';
import 'package:masir/core/services/osm_data_service.dart';
import 'package:masir/core/services/report_service.dart';
import 'package:masir/core/services/traffic_zone_service.dart';
import 'package:masir/core/services/traffic_service.dart';
import 'package:masir/core/services/map_feedback_service.dart';
import 'package:masir/core/services/saved_places_service.dart';
import 'package:masir/core/services/valhalla_service.dart';
import 'package:masir/core/services/voice_guidance_service.dart';
import 'package:masir/features/search/models/place_result.dart';
import 'package:masir/features/search/presentation/search_sheet.dart';
import 'package:masir/features/travel/presentation/city_guide_sheet.dart';
import 'package:masir/features/offline/presentation/offline_maps_sheet.dart';
import 'package:masir/features/offline/presentation/offline_pmtiles_layer.dart';
import 'package:masir/features/environment/presentation/environment_sheet.dart';
import 'package:masir/features/place/presentation/place_details_sheet.dart';
import 'package:masir/features/map_feedback/presentation/map_feedback_sheet.dart';
import 'package:masir/features/transit/presentation/transit_nearby_sheet.dart';
import 'package:masir/features/route/presentation/along_route_poi_sheet.dart';

enum _PickTarget { origin, destination }

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _mapController = MapController();
  final _location = LocationService();
  final _navPrefsService = NavigationPreferencesService();
  final _session = NavigationSessionService();
  final _offlineRoutes = OfflineRouteStoreService();
  final _persian = PersianGuidanceService();
  final _routing = ValhallaService();
  final _osm = OsmDataService();
  final _reports = ReportService();
  final _trafficZoneService = TrafficZoneService();
  final _traffic = TrafficService();
  final _mapFeedback = MapFeedbackService();
  final _saved = SavedPlacesService();
  final _voice = VoiceGuidanceService();
  final _offlineMaps = OfflineMapCatalogService();
  final _distance = const Distance();

  PlaceResult? _origin;
  PlaceResult? _destination;
  final List<PlaceResult> _viaPoints = [];
  RouteResult? _route;
  List<RouteResult> _alternatives = const [];
  int _routeIndex = 0;
  List<OsmPoi> _pois = const [];
  List<RoadReport> _roadReports = const [];
  int _pendingReportCount = 0;
  DateTime? _lastReportRefreshAt;
  List<TrafficZone> _trafficZones = const [];
  List<TrafficSegment> _trafficSegments = const [];
  DateTime? _lastTrafficAt;
  String? _activeTrafficZoneId;
  int _pendingMapFeedback = 0;
  LatLng? _gpsPoint;
  double _speedKmh = 0;
  int? _maxSpeedKmh;
  bool _speedCameraNearby = false;
  bool _voiceEnabled = true;
  bool _directionUp = true;
  NavigationPreferences _navPrefs = const NavigationPreferences();
  DateTime? _lastRerouteAt;
  DateTime? _lastRoadInfoAt;
  String? _offlineMapPath;
  bool _usingOfflineRoute = false;

  bool _routingNow = false;
  bool _startingNavigation = false;
  bool _routeConfirmed = false;
  bool _liveNavigation = false;
  bool _simulation = false;
  int _maneuverIndex = 0;
  _PickTarget? _pickTarget;
  StreamSubscription<dynamic>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _loadNavigationPreferences();
    _loadOfflineMap();
    _loadReportState();
    _loadTrafficZones();
    _loadMapFeedbackState();
    _restoreNavigationSession();
  }

  Future<void> _restoreNavigationSession() async {
    final saved = await _session.load();
    if (!mounted || saved == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('مسیر قبلی ذخیره شده است.'),
          action: SnackBarAction(
            label: 'ادامه',
            onPressed: () {
              setState(() {
                _destination = saved.destination;
                _viaPoints
                  ..clear()
                  ..addAll(saved.viaPoints);
              });
              _useGpsAsOrigin().then((_) => _buildRoute());
            },
          ),
        ),
      );
    });
  }
  Future<void> _loadNavigationPreferences() async {
    final value = await _navPrefsService.load();
    if (!mounted) return;
    setState(() => _navPrefs = value);
  }

  Future<void> _setNavigationPreferences(NavigationPreferences value) async {
    await _navPrefsService.save(value);
    if (!mounted) return;
    setState(() => _navPrefs = value);
  }

  Future<void> _loadOfflineMap() async {
    final path = await _offlineMaps.activeMapPath();
    if (!mounted) return;
    setState(() => _offlineMapPath = path);
  }

  Future<void> _loadMapFeedbackState() async {
    if (_mapFeedback.isConfigured) {
      await _mapFeedback.syncPending();
    }
    final pending = await _mapFeedback.pendingCount();
    if (!mounted) return;
    setState(() => _pendingMapFeedback = pending);
  }

  void _showMapFeedback() {
    final position = _destination?.position ?? _gpsPoint ?? _origin?.position;
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('برای اصلاح نقشه، ابتدا یک موقعیت یا مقصد انتخاب کنید.'),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MapFeedbackSheet(position: position),
    ).then((_) => _loadMapFeedbackState());
  }

  Future<void> _refreshLiveTraffic(LatLng point, {bool force = false}) async {
    if (!_traffic.isConfigured) return;
    final now = DateTime.now();
    if (!force &&
        _lastTrafficAt != null &&
        now.difference(_lastTrafficAt!) < const Duration(seconds: 35)) {
      return;
    }
    _lastTrafficAt = now;
    try {
      final segments = await _traffic.nearby(point);
      if (!mounted) return;
      setState(() => _trafficSegments = segments);
    } catch (_) {
      // Keep last valid traffic snapshot; never fabricate live traffic.
    }
  }

  Color _trafficColor(double congestion) {
    if (congestion >= 0.75) return Colors.red;
    if (congestion >= 0.45) return Colors.orange;
    if (congestion >= 0.2) return Colors.amber;
    return Colors.green;
  }

  Future<void> _loadTrafficZones() async {
    final zones = await _trafficZoneService.load();
    if (!mounted) return;
    setState(() => _trafficZones = zones);
    final point = _gpsPoint;
    if (point != null) _checkTrafficZone(point);
  }

  void _checkTrafficZone(LatLng point) {
    TrafficZone? active;
    for (final zone in _trafficZones) {
      if (zone.contains(point)) {
        active = zone;
        break;
      }
    }

    final nextId = active?.id;
    if (nextId == _activeTrafficZoneId) return;
    _activeTrafficZoneId = nextId;
    if (active == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'وارد \${active.name} شدی\${active.description == null ? '' : ' · \${active.description}'}',
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _loadReportState() async {
    final pending = await _reports.pendingCount();
    if (!mounted) return;
    setState(() => _pendingReportCount = pending);
  }

  Future<void> _refreshReports(LatLng point, {bool force = false}) async {
    if (!_reports.isConfigured) return;
    final now = DateTime.now();
    if (!force &&
        _lastReportRefreshAt != null &&
        now.difference(_lastReportRefreshAt!) < const Duration(seconds: 35)) {
      return;
    }
    _lastReportRefreshAt = now;

    try {
      await _reports.syncPending();
      final reports = await _reports.nearby(point);
      final pending = await _reports.pendingCount();
      if (!mounted) return;
      setState(() {
        _roadReports = reports;
        _pendingReportCount = pending;
      });
    } catch (_) {
      // Keep the last valid live reports and pending queue.
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _voice.stop();
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
            _alternatives = const [];
            _routeIndex = 0;
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
      unawaited(_refreshReports(point, force: true));
      _checkTrafficZone(point);
      unawaited(_refreshLiveTraffic(point, force: true));
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
      _usingOfflineRoute = false;
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
      final options = await _routing.routeAlternatives(
        _origin!.position,
        _destination!.position,
        viaPoints: _viaPoints.map((e) => e.position).toList(),
        useHighways: _navPrefs.avoidHighways ? 0.0 : 1.0,
        useTolls: _navPrefs.avoidTolls ? 0.0 : 1.0,
        useFerries: _navPrefs.avoidFerries ? 0.0 : 0.5,
        mode: _navPrefs.mode,
      );
      final result = options.first;
      if (mounted) setState(() => _usingOfflineRoute = false);
      await _offlineRoutes.save(
        destination: _destination!.position,
        mode: _navPrefs.mode,
        route: result,
      );
      await _saved.addHistory(_destination!);
      if (!mounted) return;

      setState(() {
        _alternatives = options;
        _routeIndex = 0;
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
    if (destination == null || _startingNavigation) return;

    setState(() => _startingNavigation = true);

    try {
      final position = await _location.currentPosition();
      final current = LatLng(position.latitude, position.longitude);

      RouteResult liveRoute;
      var usingOfflineSnapshot = false;
      try {
        liveRoute = await _routing.route(
          current,
          destination.position,
          viaPoints: _viaPoints.map((e) => e.position).toList(),
          useHighways: _navPrefs.avoidHighways ? 0.0 : 1.0,
          useTolls: _navPrefs.avoidTolls ? 0.0 : 1.0,
          useFerries: _navPrefs.avoidFerries ? 0.0 : 0.5,
          mode: _navPrefs.mode,
        );
        await _offlineRoutes.save(
          destination: destination.position,
          mode: _navPrefs.mode,
          route: liveRoute,
        );
      } catch (_) {
        final savedRoute = await _offlineRoutes.loadForTrip(
          current: current,
          destination: destination.position,
          mode: _navPrefs.mode,
        );
        if (savedRoute == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'مسیر آنلاین در دسترس نیست و مسیر ذخیره‌شده مناسبی هم پیدا نشد.',
              ),
            ),
          );
          return;
        }
        liveRoute = savedRoute;
        usingOfflineSnapshot = true;
      }

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
        _speedKmh = position.speed.isFinite && position.speed > 0
            ? position.speed * 3.6
            : 0;
        _usingOfflineRoute = usingOfflineSnapshot;
      });

      _mapController.move(current, 17);

      if (usingOfflineSnapshot && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ادامه مسیر با نسخه ذخیره‌شده آفلاین'),
          ),
        );
      }

      await _session.save(
        destination: destination,
        viaPoints: _viaPoints,
        mode: _navPrefs.mode,
      );
      if (_voiceEnabled && liveRoute.maneuvers.isNotEmpty) {
        unawaited(_voice.speak(_persian.instruction(liveRoute.maneuvers.first)));
      }

      await _positionSubscription?.cancel();
      _positionSubscription = _location.positionStream().listen(
        (position) {
          if (!mounted || !_liveNavigation) return;
          final point = LatLng(position.latitude, position.longitude);
          setState(() {
            _gpsPoint = point;
            _speedKmh = position.speed.isFinite && position.speed > 0
                ? position.speed * 3.6
                : 0;
          });
          if (_directionUp &&
              position.heading.isFinite &&
              position.heading >= 0 &&
              position.speed > 1.5) {
            _mapController.rotate(-position.heading);
          } else if (!_directionUp) {
            _mapController.rotate(0);
          }
          final zoom = _navPrefs.autoZoom
              ? (position.speed * 3.6 >= 80
                  ? 15.4
                  : position.speed * 3.6 >= 40
                      ? 16.1
                      : 17.0)
              : 17.0;
          _mapController.move(point, zoom);
          _advanceLiveManeuver(point);
          unawaited(_maybeReroute(point));
          unawaited(_refreshRoadInfo(point));
          unawaited(_refreshReports(point));
          _checkTrafficZone(point);
          unawaited(_refreshLiveTraffic(point));
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _liveNavigation = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ارتباط زنده با GPS قطع شد.')),
          );
        },
      );
    } on LocationServiceDisabledException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location دستگاه خاموش است. آن را روشن و دوباره شروع کنید.')),
      );
    } on PermissionDeniedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('دسترسی Location برای حالت راننده لازم است.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GPS نتوانست موقعیت فعلی را دریافت کند.')),
      );
    } finally {
      if (mounted) setState(() => _startingNavigation = false);
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
      final newRoute = await _routing.route(
        current,
        destination.position,
        viaPoints: _viaPoints.map((e) => e.position).toList(),
        useHighways: _navPrefs.avoidHighways ? 0.0 : 1.0,
        useTolls: _navPrefs.avoidTolls ? 0.0 : 1.0,
        useFerries: _navPrefs.avoidFerries ? 0.0 : 0.5,
      );
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
      if (_voiceEnabled && _maneuverIndex < route.maneuvers.length) {
        unawaited(_voice.speak(_persian.instruction(route.maneuvers[_maneuverIndex])));
      }
    }
  }


  Future<void> _refreshRoadInfo(LatLng point) async {
    final now = DateTime.now();
    if (_lastRoadInfoAt != null &&
        now.difference(_lastRoadInfoAt!) < const Duration(seconds: 25)) {
      return;
    }
    _lastRoadInfoAt = now;
    try {
      final info = await _osm.roadInfo(point);
      if (!mounted) return;
      setState(() {
        _maxSpeedKmh = info.maxSpeedKmh;
        _speedCameraNearby = info.speedCameraNearby;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _maxSpeedKmh = null;
        _speedCameraNearby = false;
      });
    }
  }

  Future<void> _loadPois() async {
    final center = _gpsPoint ?? _origin?.position ?? _destination?.position;
    if (center == null) return;
    try {
      final items = await _osm.nearbyPois(center);
      if (!mounted) return;
      setState(() => _pois = items);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('دریافت مکان‌های اطراف انجام نشد.')),
      );
    }
  }


  Future<void> _saveDestinationAsHome() async {
    final place = _destination;
    if (place == null) return;
    await _saved.saveHome(place);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('خانه ذخیره شد.')),
    );
  }

  Future<void> _saveDestinationAsWork() async {
    final place = _destination;
    if (place == null) return;
    await _saved.saveWork(place);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('محل کار ذخیره شد.')),
    );
  }

  Future<void> _showSavedPlaces() async {
    final home = await _saved.getHome();
    final work = await _saved.getWork();
    final favorites = await _saved.getFavorites();
    final history = await _saved.getHistory();
    if (!mounted) return;

    final items = <PlaceResult>[
      if (home != null) home,
      if (work != null) work,
      ...favorites,
      ...history,
    ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: items.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('هنوز مکانی ذخیره نشده است.')),
              )
            : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final place = items[index];
                  return ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(place.title),
                    subtitle: place.subtitle.isEmpty ? null : Text(place.subtitle),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      setState(() {
                        _destination = place;
                        _route = null;
                        _alternatives = const [];
                        _routeConfirmed = false;
                      });
                      _mapController.move(place.position, 15);
                    },
                  );
                },
              ),
      ),
    );
  }

  Future<void> _saveDestinationAsFavorite() async {
    final place = _destination;
    if (place == null) return;
    await _saved.addFavorite(place);
    await _saved.addHistory(place);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('مقصد ذخیره شد.')),
    );
  }

  void _selectRouteFromMap(LatLng point) {
    if (_alternatives.length < 2 || _routeConfirmed || _liveNavigation) return;
    var bestIndex = -1;
    var bestMeters = double.infinity;
    for (var routeIndex = 0; routeIndex < _alternatives.length; routeIndex++) {
      final points = _alternatives[routeIndex].points;
      final step = points.length > 500 ? 4 : 1;
      for (var i = 0; i < points.length; i += step) {
        final meters = _distance(point, points[i]);
        if (meters < bestMeters) {
          bestMeters = meters;
          bestIndex = routeIndex;
        }
      }
    }
    if (bestIndex >= 0 && bestMeters < 120) {
      _selectAlternative(bestIndex);
    }
  }
  void _selectAlternative(int index) {
    if (index < 0 || index >= _alternatives.length) return;
    setState(() {
      _routeIndex = index;
      _route = _alternatives[index];
      _routeConfirmed = false;
      _maneuverIndex = 0;
    });
  }


  void _recenterOnDriver() {
    final point = _gpsPoint;
    if (point == null) return;
    _mapController.move(point, _speedKmh >= 80 ? 15.4 : _speedKmh >= 40 ? 16.1 : 17.0);
  }

  void _showRouteOverview() {
    final route = _route;
    if (route == null || route.points.isEmpty) return;
    _mapController.rotate(0);
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: route.points,
        padding: const EdgeInsets.fromLTRB(34, 140, 34, 140),
      ),
    );
  }

  void _showNavigationPreferences() {
    var draft = _navPrefs;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
            children: [
              const ListTile(
                title: Text('تنظیمات مسیر'),
                subtitle: Text('همه تنظیمات فقط روی همین دستگاه ذخیره می‌شوند'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: SegmentedButton<TravelMode>(
                  segments: const [
                    ButtonSegment(
                      value: TravelMode.driving,
                      icon: Icon(Icons.directions_car_filled_outlined),
                      label: Text('خودرو'),
                    ),
                    ButtonSegment(
                      value: TravelMode.walking,
                      icon: Icon(Icons.directions_walk_rounded),
                      label: Text('پیاده'),
                    ),
                    ButtonSegment(
                      value: TravelMode.cycling,
                      icon: Icon(Icons.directions_bike_rounded),
                      label: Text('دوچرخه'),
                    ),
                  ],
                  selected: {draft.mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (values) {
                    setSheetState(() {
                      draft = draft.copyWith(mode: values.first);
                    });
                  },
                ),
              ),
              SwitchListTile(
                value: draft.avoidTolls,
                onChanged: (value) => setSheetState(() => draft = draft.copyWith(avoidTolls: value)),
                title: const Text('پرهیز از عوارضی'),
                secondary: const Icon(Icons.toll_outlined),
              ),
              SwitchListTile(
                value: draft.avoidHighways,
                onChanged: (value) => setSheetState(() => draft = draft.copyWith(avoidHighways: value)),
                title: const Text('پرهیز از بزرگراه'),
                secondary: const Icon(Icons.add_road_outlined),
              ),
              SwitchListTile(
                value: draft.avoidFerries,
                onChanged: (value) => setSheetState(() => draft = draft.copyWith(avoidFerries: value)),
                title: const Text('پرهیز از فِری'),
                secondary: const Icon(Icons.directions_boat_outlined),
              ),
              const Divider(),
              SwitchListTile(
                value: draft.autoZoom,
                onChanged: (value) => setSheetState(() => draft = draft.copyWith(autoZoom: value)),
                title: const Text('زوم خودکار هنگام رانندگی'),
                secondary: const Icon(Icons.zoom_in_map_outlined),
              ),
              SwitchListTile(
                value: draft.speedWarning,
                onChanged: (value) => setSheetState(() => draft = draft.copyWith(speedWarning: value)),
                title: const Text('هشدار سرعت'),
                secondary: const Icon(Icons.speed_rounded),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await _setNavigationPreferences(draft);
                  if (_origin != null && _destination != null && _route != null) {
                    unawaited(_buildRoute());
                  }
                },
                child: const Text('ذخیره تنظیمات'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addViaPoint() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => SearchSheet(
        onSelected: (place) {
          setState(() {
            _viaPoints.add(place);
            _route = null;
            _alternatives = const [];
            _routeConfirmed = false;
          });
        },
      ),
    );
  }

  void _manageViaPoints() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('توقف‌های بین راه'),
                subtitle: Text('ترتیب توقف‌ها را تغییر بده یا حذف کن'),
              ),
              if (_viaPoints.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('توقفی اضافه نشده است.'),
                ),
              for (var i = 0; i < _viaPoints.length; i++)
                ListTile(
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text(_viaPoints[i].title),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        onPressed: i > 0 ? () {
                          setState(() {
                            final item = _viaPoints.removeAt(i);
                            _viaPoints.insert(i - 1, item);
                            _route = null;
                            _routeConfirmed = false;
                          });
                          setSheetState(() {});
                        } : null,
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                      IconButton(
                        onPressed: i < _viaPoints.length - 1 ? () {
                          setState(() {
                            final item = _viaPoints.removeAt(i);
                            _viaPoints.insert(i + 1, item);
                            _route = null;
                            _routeConfirmed = false;
                          });
                          setSheetState(() {});
                        } : null,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _viaPoints.removeAt(i);
                            _route = null;
                            _routeConfirmed = false;
                          });
                          setSheetState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _addViaPoint();
                  },
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('افزودن توقف'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  void _showCityGuide() {
    final center = _gpsPoint ?? _destination?.position ?? _origin?.position;
    if (center == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('برای نمایش راهنمای شهر، یک موقعیت یا مقصد انتخاب کنید.'),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CityGuideSheet(
        center: center,
        onSelected: (place) {
          setState(() {
            _destination = place;
            _route = null;
            _alternatives = const [];
            _routeIndex = 0;
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

  Future<void> _showOfflineMaps() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const OfflineMapsSheet(),
    );
    await _loadOfflineMap();
  }

  void _showEnvironment() {
    final position = _gpsPoint ?? _destination?.position ?? _origin?.position;
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('برای نمایش آب‌وهوا، ابتدا یک موقعیت یا مقصد انتخاب کنید.'),
        ),
      );
      return;
    }
    final title = _gpsPoint != null
        ? 'شرایط اطراف من'
        : (_destination?.title ?? _origin?.title ?? 'موقعیت انتخاب‌شده');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EnvironmentSheet(
        position: position,
        title: title,
      ),
    );
  }

  void _showDestinationDetails() {
    final place = _destination;
    if (place == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ابتدا یک مقصد انتخاب کنید.')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PlaceDetailsSheet(
        position: place.position,
        fallbackTitle: place.title,
      ),
    );
  }

  void _showTransitNearby() {
    final center = _gpsPoint ?? _destination?.position ?? _origin?.position;
    if (center == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('برای نمایش حمل‌ونقل عمومی، یک موقعیت انتخاب کنید.'),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TransitNearbySheet(
        center: center,
        onSelected: (place) {
          setState(() {
            _destination = place;
            _route = null;
            _alternatives = const [];
            _routeConfirmed = false;
          });
          _mapController.move(place.position, 16);
        },
      ),
    );
  }

  void _showAlongRouteStops() {
    final route = _route;
    if (route == null || route.points.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ابتدا یک مسیر بسازید.')),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AlongRoutePoiSheet(
        route: route.points,
        onSelected: (place) {
          setState(() {
            _viaPoints.add(place);
            _route = null;
            _alternatives = const [];
            _routeConfirmed = false;
          });
          unawaited(_buildRoute());
        },
      ),
    );
  }

  void _showToolsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_road_rounded),
                title: const Text('توقف نزدیک مسیر'),
                subtitle: const Text('پمپ‌بنزین، پارکینگ، داروخانه، بیمارستان و غذا'),
                onTap: _route == null
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        _showAlongRouteStops();
                      },
              ),
              ListTile(
                leading: const Icon(Icons.add_location_alt_outlined),
                title: const Text('توقف‌های بین راه'),
                subtitle: Text(_viaPoints.isEmpty ? 'بدون توقف' : '${_viaPoints.length} توقف'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _manageViaPoints();
                },
              ),
              ListTile(
                leading: const Icon(Icons.route_outlined),
                title: const Text('تنظیمات مسیر'),
                subtitle: const Text('عوارضی، بزرگراه، فری، زوم و هشدار سرعت'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showNavigationPreferences();
                },
              ),
              ListTile(
                leading: const Icon(Icons.local_gas_station_outlined),
                title: const Text('مکان‌های اطراف'),
                subtitle: const Text('پمپ بنزین، پارکینگ، بیمارستان، رستوران و ATM'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _loadPois();
                },
              ),
              ListTile(
                leading: const Icon(Icons.traffic_outlined),
                title: const Text('ترافیک زنده'),
                subtitle: Text(
                  _traffic.isConfigured
                      ? (_trafficSegments.isEmpty
                          ? 'Provider واقعی متصل است؛ داده تازه‌ای نزدیک نیست'
                          : '${_trafficSegments.length} قطعه ترافیکی تازه')
                      : 'بدون Provider واقعی غیرفعال است',
                ),
                onTap: _traffic.isConfigured
                    ? () async {
                        Navigator.pop(sheetContext);
                        final point =
                            _gpsPoint ?? _destination?.position ?? _origin?.position;
                        if (point != null) {
                          await _refreshLiveTraffic(point, force: true);
                        }
                      }
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: const Text('محدوده‌های ترافیکی'),
                subtitle: Text(
                  _trafficZones.isNotEmpty
                      ? '\${_trafficZones.length} محدوده واقعی بارگذاری شده'
                      : (_trafficZoneService.isConfigured
                          ? 'در منبع فعلی محدوده‌ای دریافت نشد'
                          : 'فقط با منبع GeoJSON واقعی فعال می‌شود'),
                ),
                onTap: _trafficZoneService.isConfigured
                    ? () async {
                        Navigator.pop(sheetContext);
                        await _loadTrafficZones();
                      }
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.edit_location_alt_outlined),
                title: const Text('اصلاح نقشه'),
                subtitle: Text(
                  _pendingMapFeedback > 0
                      ? '\${_pendingMapFeedback} پیشنهاد در صف ارسال'
                      : 'نام، مکان، مسیر بسته یا محدودیت دسترسی اشتباه',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showMapFeedback();
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('جزئیات مقصد'),
                subtitle: const Text('آدرس، ساعت کاری، تلفن و اطلاعات واقعی OSM'),
                onTap: _destination == null
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        _showDestinationDetails();
                      },
              ),
              ListTile(
                leading: const Icon(Icons.directions_transit_outlined),
                title: const Text('حمل‌ونقل عمومی نزدیک'),
                subtitle: const Text('مترو، ورودی مترو و ایستگاه اتوبوس واقعی OSM'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showTransitNearby();
                },
              ),
              ListTile(
                leading: const Icon(Icons.wb_cloudy_outlined),
                title: const Text('آب‌وهوا و کیفیت هوا'),
                subtitle: const Text('دما، باد، AQI و ذرات معلق واقعی'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showEnvironment();
                },
              ),
              ListTile(
                leading: const Icon(Icons.travel_explore_rounded),
                title: const Text('راهنمای شهر'),
                subtitle: const Text('دیدنی‌ها، اقامت، غذا، خرید و خدمات واقعی OSM'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showCityGuide();
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_for_offline_outlined),
                title: const Text('نقشه‌های آفلاین'),
                subtitle: const Text('دانلود، بروزرسانی و حذف بسته‌های منطقه‌ای'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showOfflineMaps();
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmarks_outlined),
                title: const Text('ذخیره‌ها و تاریخچه'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showSavedPlaces();
                },
              ),
              ListTile(
                leading: const Icon(Icons.star_outline_rounded),
                title: const Text('ذخیره مقصد'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _saveDestinationAsFavorite();
                },
              ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('ذخیره مقصد به‌عنوان خانه'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _saveDestinationAsHome();
                },
              ),
              ListTile(
                leading: const Icon(Icons.work_outline_rounded),
                title: const Text('ذخیره مقصد به‌عنوان محل کار'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _saveDestinationAsWork();
                },
              ),
              SwitchListTile(
                value: _voiceEnabled,
                onChanged: (value) {
                  setState(() => _voiceEnabled = value);
                  if (!value) _voice.stop();
                  Navigator.pop(sheetContext);
                },
                title: const Text('راهنمای صوتی فارسی'),
                secondary: const Icon(Icons.volume_up_outlined),
              ),
              ListTile(
                leading: const Icon(Icons.report_gmailerrorred_rounded),
                title: const Text('گزارش مسیر'),
                subtitle: Text(
                  _reports.isConfigured
                      ? (_pendingReportCount > 0
                          ? 'گزارش‌های زنده + $_pendingReportCount گزارش در صف ارسال'
                          : 'تصادف، پلیس، دوربین، سرعت‌گیر و بسته بودن مسیر')
                      : (_pendingReportCount > 0
                          ? '$_pendingReportCount گزارش روی دستگاه در صف اتصال سرور'
                          : 'گزارش روی دستگاه ذخیره می‌شود تا سرور واقعی متصل شود'),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showReportSheet();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReportSheet() {
    final point = _gpsPoint ?? _origin?.position;
    if (point == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('برای ثبت گزارش، ابتدا موقعیت فعلی را مشخص کنید.'),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const ListTile(
              title: Text(
                'گزارش اتفاق مسیر',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                'فقط اتفاقی را گزارش کن که همین حالا در این موقعیت وجود دارد.',
              ),
            ),
            for (final type in RoadReportType.values)
              ListTile(
                leading: Icon(_roadReportIcon(type)),
                title: Text(type.label),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final result = await _reports.submit(
                    type: type,
                    position: point,
                  );
                  final pending = await _reports.pendingCount();
                  if (!mounted) return;
                  setState(() => _pendingReportCount = pending);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        result.sent
                            ? 'گزارش ارسال شد.'
                            : 'گزارش ذخیره شد و پس از اتصال سرور واقعی ارسال می‌شود.',
                      ),
                    ),
                  );
                  if (result.sent) {
                    unawaited(_refreshReports(point, force: true));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  IconData _roadReportIcon(RoadReportType type) => switch (type) {
        RoadReportType.traffic => Icons.traffic_rounded,
        RoadReportType.accident => Icons.car_crash_outlined,
        RoadReportType.police => Icons.local_police_outlined,
        RoadReportType.camera => Icons.videocam_outlined,
        RoadReportType.speedBump => Icons.speed_rounded,
        RoadReportType.closure => Icons.block_rounded,
        RoadReportType.roadwork => Icons.construction_rounded,
        RoadReportType.hazard => Icons.warning_amber_rounded,
      };

  void _stopNavigation() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _session.clear();
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
              onTap: (_, point) => _selectRouteFromMap(point),
            ),
            children: [
              if (_offlineMapPath != null)
                OfflinePmTilesLayer(
                  key: ValueKey(_offlineMapPath),
                  path: _offlineMapPath!,
                )
              else
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'ir.sahand.masir',
                ),
              if (_trafficSegments.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    for (final segment in _trafficSegments)
                      Polyline(
                        points: segment.points,
                        strokeWidth: 5,
                        color: _trafficColor(segment.congestion),
                      ),
                  ],
                ),
              if (_trafficZones.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    for (final zone in _trafficZones)
                      for (final ring in zone.rings.take(1))
                        Polygon(
                          points: ring,
                          color: Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withValues(alpha: 0.24),
                          borderColor: Theme.of(context).colorScheme.error,
                          borderStrokeWidth: 1.5,
                        ),
                  ],
                ),
              if (_alternatives.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    for (var i = 0; i < _alternatives.length; i++)
                      Polyline(
                        points: _alternatives[i].points,
                        strokeWidth: i == _routeIndex ? 7 : 4,
                        color: i == _routeIndex
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline.withValues(alpha: 0.55),
                      ),
                  ],
                )
              else if (route != null)
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
                  for (final poi in _pois)
                    Marker(
                      point: poi.position,
                      width: 36,
                      height: 36,
                      child: Tooltip(
                        message: poi.name,
                        child: const _PoiMarker(),
                      ),
                    ),
                  for (final report in _roadReports)
                    Marker(
                      point: report.position,
                      width: 40,
                      height: 40,
                      child: Tooltip(
                        message: report.type.label,
                        child: _RoadReportMarker(
                          icon: _roadReportIcon(report.type),
                          verified: report.verified,
                        ),
                      ),
                    ),
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
          if (_liveNavigation && (DateTime.now().hour >= 19 || DateTime.now().hour < 6))
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black26),
              ),
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
          if (!navigating && _pickTarget == null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 128,
              right: 14,
              child: Wrap(
                spacing: 6,
                children: [
                  _MapStatusChip(
                    icon: switch (_navPrefs.mode) {
                      TravelMode.driving => Icons.directions_car_filled_outlined,
                      TravelMode.walking => Icons.directions_walk_rounded,
                      TravelMode.cycling => Icons.directions_bike_rounded,
                    },
                    label: _navPrefs.mode.label,
                  ),
                  if (_offlineMapPath != null)
                    const _MapStatusChip(
                      icon: Icons.offline_pin_rounded,
                      label: 'نقشه آفلاین',
                    ),
                ],
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
                maxSpeedKmh: _maxSpeedKmh,
                speedCameraNearby: _speedCameraNearby,
                speedWarning: _navPrefs.speedWarning,
                remainingKilometers: route.maneuvers
                    .skip(_maneuverIndex)
                    .fold<double>(0, (sum, item) => sum + item.kilometers),
                remainingSeconds: route.maneuvers
                    .skip(_maneuverIndex)
                    .fold<double>(0, (sum, item) => sum + item.seconds),
                onClose: _stopNavigation,
              ),
            ),
          if (_liveNavigation && _usingOfflineRoute)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 128,
              right: 14,
              child: const _MapStatusChip(
                icon: Icons.cloud_off_rounded,
                label: 'مسیر ذخیره‌شده آفلاین',
              ),
            ),
          if (!navigating && _origin != null && _destination != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 18,
              child: _RouteCard(
                route: route,
                alternatives: _alternatives,
                selectedRouteIndex: _routeIndex,
                onSelectRoute: _selectAlternative,
                loading: _routingNow,
                confirmed: _routeConfirmed,
                onBuild: _buildRoute,
                onConfirm: _confirmRoute,
                onLive: _startLiveNavigation,
                startingNavigation: _startingNavigation,
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
          if (!navigating)
            Positioned(
              right: 12,
              bottom: _origin != null && _destination != null ? 210 : 20,
              child: FloatingActionButton.small(
                heroTag: 'tools',
                onPressed: _showToolsSheet,
                child: const Icon(Icons.tune_rounded),
              ),
            ),
          if (_liveNavigation)
            Positioned(
              right: 12,
              top: MediaQuery.paddingOf(context).top + 150,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'recenter',
                    onPressed: _recenterOnDriver,
                    child: const Icon(Icons.my_location_rounded),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'orientation',
                    onPressed: () {
                      setState(() => _directionUp = !_directionUp);
                      if (!_directionUp) _mapController.rotate(0);
                    },
                    child: Icon(_directionUp ? Icons.navigation_rounded : Icons.explore_outlined),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'overview',
                    onPressed: _showRouteOverview,
                    child: const Icon(Icons.alt_route_rounded),
                  ),
                ],
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

class _RoadReportMarker extends StatelessWidget {
  const _RoadReportMarker({
    required this.icon,
    required this.verified,
  });

  final IconData icon;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: verified ? scheme.errorContainer : scheme.surface,
        border: Border.all(
          color: verified ? scheme.error : scheme.outlineVariant,
          width: verified ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 8,
            offset: Offset(0, 2),
            color: Color(0x22000000),
          ),
        ],
      ),
      child: Icon(
        icon,
        size: 20,
        color: verified ? scheme.onErrorContainer : scheme.onSurface,
      ),
    );
  }
}

class _MapStatusChip extends StatelessWidget {
  const _MapStatusChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            offset: Offset(0, 3),
            color: Color(0x18000000),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
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
    required this.alternatives,
    required this.selectedRouteIndex,
    required this.onSelectRoute,
    required this.loading,
    required this.confirmed,
    required this.onBuild,
    required this.onConfirm,
    required this.onLive,
    required this.startingNavigation,
    required this.onSimulation,
  });

  final RouteResult? route;
  final List<RouteResult> alternatives;
  final int selectedRouteIndex;
  final ValueChanged<int> onSelectRoute;
  final bool loading;
  final bool confirmed;
  final VoidCallback onBuild;
  final VoidCallback onConfirm;
  final VoidCallback onLive;
  final bool startingNavigation;
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
            if (route != null && alternatives.length > 1) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: alternatives.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => ChoiceChip(
                    selected: index == selectedRouteIndex,
                    onSelected: (_) => onSelectRoute(index),
                    label: Text('مسیر ${index + 1}'),
                  ),
                ),
              ),
            ],
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
                      onPressed: startingNavigation ? null : onLive,
                      icon: startingNavigation
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.navigation_rounded),
                      label: Text(startingNavigation ? 'در حال آماده‌سازی…' : 'شروع رانندگی با GPS'),
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
    required this.maxSpeedKmh,
    required this.speedCameraNearby,
    required this.speedWarning,
    required this.remainingKilometers,
    required this.remainingSeconds,
    required this.onClose,
  });

  final RouteManeuver maneuver;
  final int index;
  final int count;
  final bool live;
  final double speedKmh;
  final int? maxSpeedKmh;
  final bool speedCameraNearby;
  final bool speedWarning;
  final double remainingKilometers;
  final double remainingSeconds;
  final VoidCallback onClose;

  String _arrivalTime(double seconds) {
    final arrival = DateTime.now().add(Duration(seconds: seconds.round()));
    final hour = arrival.hour.toString().padLeft(2, '0');
    final minute = arrival.minute.toString().padLeft(2, '0');
    return 'رسیدن $hour:$minute';
  }

  String _formatEta(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes دقیقه';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours ساعت' : '$hours:${rest.toString().padLeft(2, '0')}';
  }

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
                  if (maneuver.lanes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      children: [
                        for (final lane in maneuver.lanes.take(5))
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(lane, style: const TextStyle(fontSize: 11)),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: count <= 1 ? 1 : (index + 1) / count,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('مرحله ${index + 1} از $count • ${maneuver.kilometers.toStringAsFixed(1)} کیلومتر'),
                      if (live)
                        Text('${speedKmh.round()} km/h', style: TextStyle(fontWeight: FontWeight.w900, color: speedWarning && maxSpeedKmh != null && speedKmh > maxSpeedKmh! ? Theme.of(context).colorScheme.error : null)),
                      if (live)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(maxSpeedKmh == null ? 'حد —' : 'حد $maxSpeedKmh', style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      Text('${remainingKilometers.toStringAsFixed(1)} km', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(_formatEta(remainingSeconds), style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(_arrivalTime(remainingSeconds), style: const TextStyle(fontWeight: FontWeight.w800)),
                      if (speedCameraNearby) const Icon(Icons.photo_camera_outlined, size: 18),
                    ],
                  ),
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

class _PoiMarker extends StatelessWidget {
  const _PoiMarker();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: const Icon(Icons.place_outlined, size: 18),
    );
  }
}
