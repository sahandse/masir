import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/city_guide_service.dart';
import 'package:masir/features/search/models/place_result.dart';

class CityGuideSheet extends StatefulWidget {
  const CityGuideSheet({
    super.key,
    required this.center,
    required this.onSelected,
  });

  final LatLng center;
  final ValueChanged<PlaceResult> onSelected;

  @override
  State<CityGuideSheet> createState() => _CityGuideSheetState();
}

class _CityGuideSheetState extends State<CityGuideSheet> {
  final _service = CityGuideService();
  final _distance = const Distance();
  late Future<List<CityGuidePlace>> _future;
  CityGuideSection _section = CityGuideSection.sights;

  @override
  void initState() {
    super.initState();
    _future = _service.load(widget.center);
  }

  String _distanceLabel(CityGuidePlace place) {
    final meters = _distance(widget.center, place.position);
    if (meters < 1000) return '${meters.round()} متر';
    return '${(meters / 1000).toStringAsFixed(1)} کیلومتر';
  }

  String _categoryLabel(String category) {
    const labels = <String, String>{
      'attraction': 'جاذبه',
      'museum': 'موزه',
      'viewpoint': 'چشم‌انداز',
      'gallery': 'گالری',
      'information': 'اطلاعات گردشگری',
      'park': 'پارک',
      'garden': 'باغ',
      'restaurant': 'رستوران',
      'cafe': 'کافه',
      'hotel': 'هتل',
      'hostel': 'هاستل',
      'guest_house': 'مهمان‌پذیر',
      'hospital': 'بیمارستان',
      'clinic': 'درمانگاه',
      'pharmacy': 'داروخانه',
      'fuel': 'پمپ بنزین',
      'parking': 'پارکینگ',
      'supermarket': 'سوپرمارکت',
      'mall': 'مرکز خرید',
      'convenience': 'فروشگاه',
    };
    return labels[category] ?? 'مکان';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            const ListTile(
              leading: Icon(Icons.travel_explore_rounded),
              title: Text(
                'راهنمای شهر',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('مکان‌های واقعی OpenStreetMap در اطراف شما'),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final section in CityGuideSection.values)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(section.label),
                        selected: _section == section,
                        onSelected: (_) => setState(() => _section = section),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<CityGuidePlace>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'دریافت راهنمای شهر انجام نشد. اتصال اینترنت را بررسی کنید.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    );
                  }

                  final items = (snapshot.data ?? const <CityGuidePlace>[])
                      .where((item) => item.section == _section)
                      .toList()
                    ..sort(
                      (a, b) => _distance(widget.center, a.position)
                          .compareTo(_distance(widget.center, b.position)),
                    );

                  if (items.isEmpty) {
                    return const Center(
                      child: Text('برای این دسته مکانی در OSM پیدا نشد.'),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final place = items[index];
                      final opening = place.openingHours?.trim();
                      return ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(place.name),
                        subtitle: Text(
                          '${_categoryLabel(place.category)} · ${_distanceLabel(place)}'
                          '${place.offline ? ' · آفلاین' : ''}'
                          '${opening?.isNotEmpty == true ? ' · $opening' : ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: () {
                          widget.onSelected(
                            PlaceResult(
                              title: place.name,
                              subtitle:
                                  '${_categoryLabel(place.category)} · ${_distanceLabel(place)}',
                              position: place.position,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'داده مکان‌ها: © OpenStreetMap contributors',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
