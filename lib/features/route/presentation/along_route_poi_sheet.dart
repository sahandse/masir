import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/osm_data_service.dart';
import 'package:masir/features/search/models/place_result.dart';

class AlongRoutePoiSheet extends StatefulWidget {
  const AlongRoutePoiSheet({
    super.key,
    required this.route,
    required this.onSelected,
  });

  final List<LatLng> route;
  final ValueChanged<PlaceResult> onSelected;

  @override
  State<AlongRoutePoiSheet> createState() => _AlongRoutePoiSheetState();
}

class _AlongRoutePoiSheetState extends State<AlongRoutePoiSheet> {
  final _service = OsmDataService();
  String? _category;
  late Future<List<OsmPoi>> _future;

  static const _categories = <String, String>{
    'fuel': 'پمپ بنزین',
    'parking': 'پارکینگ',
    'pharmacy': 'داروخانه',
    'hospital': 'بیمارستان',
    'cafe': 'کافه',
    'restaurant': 'رستوران',
    'charging_station': 'شارژ خودرو',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final categories =
        _category == null ? _categories.keys.toSet() : {_category!};
    _future = _service.poisAlongRoute(
      widget.route,
      categories: categories,
    );
  }

  void _setCategory(String? category) {
    setState(() {
      _category = category;
      _load();
    });
  }

  IconData _icon(String category) => switch (category) {
        'fuel' => Icons.local_gas_station_outlined,
        'parking' => Icons.local_parking_rounded,
        'pharmacy' => Icons.local_pharmacy_outlined,
        'hospital' => Icons.local_hospital_outlined,
        'cafe' => Icons.local_cafe_outlined,
        'restaurant' => Icons.restaurant_outlined,
        'charging_station' => Icons.ev_station_outlined,
        _ => Icons.place_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            const ListTile(
              leading: Icon(Icons.add_road_rounded),
              title: Text(
                'توقف در امتداد مسیر',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('مکان‌های واقعی OSM نزدیک مسیر فعلی'),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: const Text('همه'),
                      selected: _category == null,
                      onSelected: (_) => _setCategory(null),
                    ),
                  ),
                  for (final entry in _categories.entries)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        avatar: Icon(_icon(entry.key), size: 16),
                        label: Text(entry.value),
                        selected: _category == entry.key,
                        onSelected: (_) => _setCategory(entry.key),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<OsmPoi>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text('دریافت توقف‌های مسیر انجام نشد.'),
                    );
                  }
                  final items = snapshot.data ?? const <OsmPoi>[];
                  if (items.isEmpty) {
                    return const Center(
                      child: Text('مکان مرتبطی نزدیک مسیر پیدا نشد.'),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final poi = items[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Icon(_icon(poi.category)),
                        ),
                        title: Text(poi.name),
                        subtitle: Text(
                          _categories[poi.category] ?? 'مکان نزدیک مسیر',
                        ),
                        trailing: const Icon(Icons.add_rounded),
                        onTap: () {
                          widget.onSelected(
                            PlaceResult(
                              title: poi.name,
                              subtitle:
                                  _categories[poi.category] ?? 'توقف بین‌راه',
                              position: poi.position,
                            ),
                          );
                          Navigator.pop(context);
                        },
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
