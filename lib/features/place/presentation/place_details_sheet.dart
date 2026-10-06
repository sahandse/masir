import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/place_details_service.dart';

class PlaceDetailsSheet extends StatefulWidget {
  const PlaceDetailsSheet({
    super.key,
    required this.position,
    required this.fallbackTitle,
  });

  final LatLng position;
  final String fallbackTitle;

  @override
  State<PlaceDetailsSheet> createState() => _PlaceDetailsSheetState();
}

class _PlaceDetailsSheetState extends State<PlaceDetailsSheet> {
  final _service = PlaceDetailsService();
  late Future<PlaceDetails> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.reverse(widget.position);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<PlaceDetails>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 320,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'جزئیات این مکان از OpenStreetMap دریافت نشد.',
                textAlign: TextAlign.center,
              ),
            );
          }

          final item = snapshot.data!;
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.place_outlined),
                ),
                title: Text(
                  item.title.isEmpty ? widget.fallbackTitle : item.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: item.address.isEmpty ? null : Text(item.address),
              ),
              if (item.category.isNotEmpty || item.type.isNotEmpty)
                _DetailRow(
                  icon: Icons.category_outlined,
                  title: 'دسته‌بندی',
                  value: [item.category, item.type]
                      .where((e) => e.isNotEmpty)
                      .join(' · '),
                ),
              if (item.openingHours != null)
                _DetailRow(
                  icon: Icons.schedule_rounded,
                  title: 'ساعت کاری',
                  value: item.openingHours!,
                ),
              if (item.phone != null)
                _DetailRow(
                  icon: Icons.call_outlined,
                  title: 'تلفن',
                  value: item.phone!,
                ),
              if (item.website != null)
                _DetailRow(
                  icon: Icons.language_rounded,
                  title: 'وب‌سایت',
                  value: item.website!,
                ),
              if (item.wheelchair != null)
                _DetailRow(
                  icon: Icons.accessible_outlined,
                  title: 'دسترسی ویلچر',
                  value: item.wheelchair!,
                ),
              if (item.wikipedia != null)
                _DetailRow(
                  icon: Icons.menu_book_outlined,
                  title: 'ویکی‌پدیا',
                  value: item.wikipedia!,
                ),
              if (item.wikidata != null)
                _DetailRow(
                  icon: Icons.dataset_linked_outlined,
                  title: 'Wikidata',
                  value: item.wikidata!,
                ),
              const SizedBox(height: 8),
              Text(
                'اطلاعات مکان: © OpenStreetMap contributors / Nominatim',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: SelectableText(value),
    );
  }
}
