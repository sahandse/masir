import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/location_service.dart';
import 'package:masir/core/services/valhalla_service.dart';
import 'package:masir/features/search/models/place_result.dart';
import 'package:masir/features/search/presentation/search_sheet.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _mapController = MapController();
  final _location = LocationService();
  final _routing = ValhallaService();

  LatLng? _user;
  PlaceResult? _destination;
  RouteResult? _route;
  bool _locating = false;
  bool _routingNow = false;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final position = await _location.currentPosition();
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _user = point);
      _mapController.move(point, 16);
    } catch (_) {
      if (!mounted) return;
      setState(() => _locationError = 'برای نمایش نقشه، دسترسی موقعیت مکانی را فعال کنید.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _openSearch() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => SearchSheet(
        onSelected: (place) {
          setState(() {
            _destination = place;
            _route = null;
          });
          _mapController.move(place.position, 16);
        },
      ),
    );
  }

  Future<void> _buildRoute() async {
    if (_user == null || _destination == null || _routingNow) return;
    if (!_routing.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سرور مسیریابی واقعی هنوز تنظیم نشده است.')),
      );
      return;
    }

    setState(() => _routingNow = true);
    try {
      final result = await _routing.route(_user!, _destination!.position);
      if (!mounted) return;
      setState(() => _route = result);
      if (result.points.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: result.points,
            padding: const EdgeInsets.fromLTRB(36, 110, 36, 230),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('دریافت مسیر واقعی انجام نشد. اتصال یا سرور مسیریابی را بررسی کنید.')),
      );
    } finally {
      if (mounted) setState(() => _routingNow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (_user == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.my_location_rounded, size: 52),
                  const SizedBox(height: 18),
                  Text(
                    _locationError ?? 'در حال دریافت موقعیت واقعی شما…',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 18),
                  if (_locating)
                    const CircularProgressIndicator()
                  else
                    FilledButton.icon(
                      onPressed: _locate,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('تلاش دوباره'),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: _user!, initialZoom: 16),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ir.sahand.masir',
              ),
              if (_route != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route!.points,
                      strokeWidth: 6,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              MarkerLayer(markers: [
                Marker(
                  point: _user!,
                  width: 44,
                  height: 44,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
                    ),
                    child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 21),
                  ),
                ),
                if (_destination != null)
                  Marker(
                    point: _destination!.position,
                    width: 48,
                    height: 48,
                    child: Icon(Icons.location_on_rounded, size: 48, color: Theme.of(context).colorScheme.error),
                  ),
              ]),
              const RichAttributionWidget(
                attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
              ),
            ],
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            left: 16,
            right: 16,
            child: Material(
              color: dark ? const Color(0xEE171B20) : const Color(0xF7FFFFFF),
              borderRadius: BorderRadius.circular(24),
              elevation: 8,
              shadowColor: Colors.black12,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _openSearch,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded),
                      SizedBox(width: 12),
                      Expanded(child: Text('کجا می‌خوای بری؟', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: _destination == null ? 112 : 210,
            child: _RoundButton(
              icon: _locating ? Icons.hourglass_top_rounded : Icons.my_location_rounded,
              onTap: _locate,
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: _destination == null
                ? _QuickPlaces(onSearch: _openSearch)
                : _DestinationCard(
                    place: _destination!,
                    route: _route,
                    loading: _routingNow,
                    onRoute: _buildRoute,
                    onClose: () => setState(() {
                      _destination = null;
                      _route = null;
                    }),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 5,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 50, height: 50, child: Icon(icon)),
      ),
    );
  }
}

class _QuickPlaces extends StatelessWidget {
  const _QuickPlaces({required this.onSearch});
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _QuickItem(icon: Icons.home_rounded, label: 'خانه', onTap: onSearch),
            _QuickItem(icon: Icons.work_rounded, label: 'کار', onTap: onSearch),
            _QuickItem(icon: Icons.star_rounded, label: 'ذخیره‌ها', onTap: onSearch),
            _QuickItem(icon: Icons.history_rounded, label: 'اخیر', onTap: onSearch),
          ],
        ),
      ),
    );
  }
}

class _QuickItem extends StatelessWidget {
  const _QuickItem({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 19, child: Icon(icon, size: 20)),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.place,
    required this.route,
    required this.loading,
    required this.onRoute,
    required this.onClose,
  });

  final PlaceResult place;
  final RouteResult? route;
  final bool loading;
  final VoidCallback onRoute;
  final VoidCallback onClose;

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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.place_rounded)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(place.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      if (place.subtitle.isNotEmpty)
                        Text(place.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
              ],
            ),
            if (route != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 18),
                  const SizedBox(width: 6),
                  Text(_duration(route!.seconds)),
                  const SizedBox(width: 18),
                  const Icon(Icons.route_rounded, size: 18),
                  const SizedBox(width: 6),
                  Text('${route!.kilometers.toStringAsFixed(1)} کیلومتر'),
                ],
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: loading ? null : onRoute,
                icon: loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.navigation_rounded),
                label: Text(route == null ? 'دریافت مسیر واقعی' : 'به‌روزرسانی مسیر', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
