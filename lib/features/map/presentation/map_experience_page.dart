import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/location_service.dart';
import 'package:masir/core/services/osm_data_service.dart';
import 'package:masir/features/map/presentation/map_page.dart';

class MapExperiencePage extends StatefulWidget {
  const MapExperiencePage({super.key});

  @override
  State<MapExperiencePage> createState() => _MapExperiencePageState();
}

class _MapExperiencePageState extends State<MapExperiencePage> {
  final _location = LocationService();
  final _osm = OsmDataService();

  StreamSubscription<dynamic>? _positionSubscription;
  DateTime? _lastRoadRefresh;
  double _speedKmh = 0;
  OsmRoadInfo? _roadInfo;
  bool _locationReady = false;

  @override
  void initState() {
    super.initState();
    _startPassiveRoadContext();
  }

  Future<void> _startPassiveRoadContext() async {
    try {
      await _location.ensurePermission();
      if (!mounted) return;
      setState(() => _locationReady = true);

      await _positionSubscription?.cancel();
      _positionSubscription = _location.positionStream().listen((position) {
        if (!mounted) return;
        final speed = position.speed.isFinite && position.speed > 0
            ? position.speed * 3.6
            : 0.0;
        setState(() => _speedKmh = speed);
        _refreshRoadContext(LatLng(position.latitude, position.longitude));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _locationReady = false);
    }
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
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const MapPage(),
        if (_locationReady && _roadInfo != null)
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
