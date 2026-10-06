import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/transit_service.dart';
import 'package:masir/features/search/models/place_result.dart';

class TransitNearbySheet extends StatefulWidget {
  const TransitNearbySheet({
    super.key,
    required this.center,
    required this.onSelected,
  });

  final LatLng center;
  final ValueChanged<PlaceResult> onSelected;

  @override
  State<TransitNearbySheet> createState() => _TransitNearbySheetState();
}

class _TransitNearbySheetState extends State<TransitNearbySheet> {
  final _service = TransitService();
  final _distance = const Distance();
  late Future<List<TransitStop>> _future;
  TransitStopType? _filter;

  @override
  void initState() {
    super.initState();
    _future = _service.nearby(widget.center);
  }

  String _distanceLabel(TransitStop stop) {
    final meters = _distance(widget.center, stop.position);
    if (meters < 1000) return '${meters.round()} متر';
    return '${(meters / 1000).toStringAsFixed(1)} کیلومتر';
  }

  IconData _icon(TransitStopType type) => switch (type) {
        TransitStopType.metro => Icons.subway_rounded,
        TransitStopType.metroEntrance => Icons.directions_subway_outlined,
        TransitStopType.bus => Icons.directions_bus_outlined,
        TransitStopType.platform => Icons.commute_outlined,
        TransitStopType.station => Icons.train_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: FutureBuilder<List<TransitStop>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'دریافت ایستگاه‌های حمل‌ونقل عمومی انجام نشد.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final all = snapshot.data ?? const <TransitStop>[];
            final items = _filter == null
                ? all
                : all.where((e) => e.type == _filter).toList();

            return Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.directions_transit_rounded),
                  title: Text(
                    'حمل‌ونقل عمومی نزدیک',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    'ایستگاه‌های واقعی OpenStreetMap؛ بدون زمان‌بندی ساختگی',
                  ),
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
                          selected: _filter == null,
                          onSelected: (_) => setState(() => _filter = null),
                        ),
                      ),
                      for (final type in TransitStopType.values)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ChoiceChip(
                            avatar: Icon(_icon(type), size: 16),
                            label: Text(type.label),
                            selected: _filter == type,
                            onSelected: (_) => setState(() => _filter = type),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: items.isEmpty
                      ? const Center(
                          child: Text('ایستگاه مرتبطی در OSM پیدا نشد.'),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final stop = items[index];
                            final details = <String>[
                              stop.type.label,
                              _distanceLabel(stop),
                              if (stop.ref?.isNotEmpty == true)
                                'خط/شناسه ${stop.ref}',
                              if (stop.operatorName?.isNotEmpty == true)
                                stop.operatorName!,
                            ];
                            return ListTile(
                              leading: CircleAvatar(
                                child: Icon(_icon(stop.type)),
                              ),
                              title: Text(stop.name),
                              subtitle: Text(details.join(' · ')),
                              trailing:
                                  const Icon(Icons.chevron_left_rounded),
                              onTap: () {
                                widget.onSelected(
                                  PlaceResult(
                                    title: stop.name,
                                    subtitle: details.join(' · '),
                                    position: stop.position,
                                  ),
                                );
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'داده ایستگاه‌ها: © OpenStreetMap contributors',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
