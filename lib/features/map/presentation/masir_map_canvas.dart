import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as geo;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:masir/core/services/offline_map_service.dart';
import 'package:masir/core/services/osm_data_service.dart';
import 'package:masir/core/services/report_service.dart';
import 'package:masir/features/search/models/place_result.dart';

typedef MapPointCallback = void Function(geo.LatLng point);

/// MapLibre canvas for Masir — free OpenFreeMap style, optional offline regions.
class MasirMapCanvas extends StatefulWidget {
  const MasirMapCanvas({
    super.key,
    required this.origin,
    required this.destination,
    required this.viaPoints,
    required this.gpsPoint,
    required this.routePoints,
    required this.alternativeRoutes,
    required this.selectedRouteIndex,
    required this.pois,
    required this.reports,
    required this.onTap,
    required this.onLongPress,
    required this.onControllerReady,
  });

  final PlaceResult? origin;
  final PlaceResult? destination;
  final List<PlaceResult> viaPoints;
  final geo.LatLng? gpsPoint;
  final List<geo.LatLng> routePoints;
  final List<List<geo.LatLng>> alternativeRoutes;
  final int selectedRouteIndex;
  final List<OsmPoi> pois;
  final List<RoadReport> reports;
  final MapPointCallback onTap;
  final MapPointCallback onLongPress;
  final ValueChanged<MapLibreMapController> onControllerReady;

  @override
  State<MasirMapCanvas> createState() => MasirMapCanvasState();
}

class MasirMapCanvasState extends State<MasirMapCanvas> {
  MapLibreMapController? _controller;
  bool _styleReady = false;
  final _lines = <Line>[];
  final _circles = <Circle>[];
  final _symbols = <Symbol>[];

  @override
  void didUpdateWidget(covariant MasirMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_styleReady) {
      unawaitedRedraw();
    }
  }

  void unawaitedRedraw() {
    // ignore: discarded_futures
    _redrawAnnotations();
  }

  Future<void> moveTo(geo.LatLng point, {double zoom = 16}) async {
    final c = _controller;
    if (c == null) return;
    await c.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(point.latitude, point.longitude),
          zoom: zoom,
        ),
      ),
    );
  }

  Future<void> fitPoints(List<geo.LatLng> points) async {
    final c = _controller;
    if (c == null || points.isEmpty) return;
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLon = points.first.longitude;
    var maxLon = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    await c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLon),
          northeast: LatLng(maxLat, maxLon),
        ),
        left: 40,
        top: 160,
        right: 40,
        bottom: 260,
      ),
    );
  }

  Future<void> setBearing(double bearingDeg) async {
    final c = _controller;
    if (c == null) return;
    final cam = c.cameraPosition;
    if (cam == null) return;
    await c.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: cam.target,
          zoom: cam.zoom,
          bearing: bearingDeg,
          tilt: cam.tilt,
        ),
      ),
    );
  }

  Future<void> _onStyleLoaded() async {
    _styleReady = true;
    await _redrawAnnotations();
  }

  Future<void> _clearAnnotations() async {
    final c = _controller;
    if (c == null) return;
    for (final line in _lines) {
      await c.removeLine(line);
    }
    for (final circle in _circles) {
      await c.removeCircle(circle);
    }
    for (final symbol in _symbols) {
      await c.removeSymbol(symbol);
    }
    _lines.clear();
    _circles.clear();
    _symbols.clear();
  }

  LatLng _ml(geo.LatLng p) => LatLng(p.latitude, p.longitude);

  Future<void> _redrawAnnotations() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    await _clearAnnotations();

    if (widget.alternativeRoutes.isNotEmpty) {
      for (var i = 0; i < widget.alternativeRoutes.length; i++) {
        final pts = widget.alternativeRoutes[i];
        if (pts.length < 2) continue;
        final selected = i == widget.selectedRouteIndex;
        final line = await c.addLine(
          LineOptions(
            geometry: pts.map(_ml).toList(),
            lineWidth: selected ? 7.0 : 4.0,
            lineColor: selected ? '#16A36A' : '#94A3B8',
            lineOpacity: selected ? 0.95 : 0.55,
          ),
        );
        _lines.add(line);
      }
    } else if (widget.routePoints.length >= 2) {
      final line = await c.addLine(
        LineOptions(
          geometry: widget.routePoints.map(_ml).toList(),
          lineWidth: 6.5,
          lineColor: '#16A36A',
          lineOpacity: 0.95,
        ),
      );
      _lines.add(line);
    }

    for (final poi in widget.pois.take(40)) {
      final circle = await c.addCircle(
        CircleOptions(
          geometry: _ml(poi.position),
          circleRadius: 6,
          circleColor: '#64748B',
          circleStrokeWidth: 1.5,
          circleStrokeColor: '#FFFFFF',
        ),
      );
      _circles.add(circle);
    }

    for (final report in widget.reports) {
      final circle = await c.addCircle(
        CircleOptions(
          geometry: _ml(report.position),
          circleRadius: 8,
          circleColor: '#E4572E',
          circleStrokeWidth: 2,
          circleStrokeColor: '#FFFFFF',
        ),
      );
      _circles.add(circle);
    }

    for (var i = 0; i < widget.viaPoints.length; i++) {
      final circle = await c.addCircle(
        CircleOptions(
          geometry: _ml(widget.viaPoints[i].position),
          circleRadius: 8,
          circleColor: '#0EA5E9',
          circleStrokeWidth: 2,
          circleStrokeColor: '#FFFFFF',
        ),
      );
      _circles.add(circle);
    }

    if (widget.origin != null) {
      _circles.add(
        await c.addCircle(
          CircleOptions(
            geometry: _ml(widget.origin!.position),
            circleRadius: 9,
            circleColor: '#0F766E',
            circleStrokeWidth: 2.5,
            circleStrokeColor: '#FFFFFF',
          ),
        ),
      );
    }
    if (widget.destination != null) {
      _circles.add(
        await c.addCircle(
          CircleOptions(
            geometry: _ml(widget.destination!.position),
            circleRadius: 10,
            circleColor: '#B45309',
            circleStrokeWidth: 2.5,
            circleStrokeColor: '#FFFFFF',
          ),
        ),
      );
    }
    if (widget.gpsPoint != null) {
      _circles.add(
        await c.addCircle(
          CircleOptions(
            geometry: _ml(widget.gpsPoint!),
            circleRadius: 10,
            circleColor: '#16A36A',
            circleStrokeWidth: 3,
            circleStrokeColor: '#FFFFFF',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.gpsPoint ??
        widget.origin?.position ??
        widget.destination?.position ??
        const geo.LatLng(32.4279, 53.6880);

    return MapLibreMap(
      styleString: kMasirMapStyleUrl,
      initialCameraPosition: CameraPosition(
        target: LatLng(initial.latitude, initial.longitude),
        zoom: widget.gpsPoint == null ? 5.2 : 14.5,
      ),
      compassEnabled: true,
      myLocationEnabled: false,
      trackCameraPosition: true,
      attributionButtonPosition: AttributionButtonPosition.bottomLeft,
      onMapCreated: (controller) {
        _controller = controller;
        widget.onControllerReady(controller);
      },
      onStyleLoadedCallback: _onStyleLoaded,
      onMapClick: (point, latLng) {
        widget.onTap(geo.LatLng(latLng.latitude, latLng.longitude));
      },
      onMapLongClick: (point, latLng) {
        widget.onLongPress(geo.LatLng(latLng.latitude, latLng.longitude));
      },
    );
  }
}
