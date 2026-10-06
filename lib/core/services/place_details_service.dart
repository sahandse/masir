import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class PlaceDetails {
  const PlaceDetails({
    required this.title,
    required this.address,
    required this.category,
    required this.type,
    this.phone,
    this.website,
    this.openingHours,
    this.wikipedia,
    this.wikidata,
    this.wheelchair,
  });

  final String title;
  final String address;
  final String category;
  final String type;
  final String? phone;
  final String? website;
  final String? openingHours;
  final String? wikipedia;
  final String? wikidata;
  final String? wheelchair;
}

class PlaceDetailsService {
  PlaceDetailsService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 15),
                headers: const {
                  'User-Agent': 'MasirNavigation/1.3 (ir.sahand.masir)',
                },
              ),
            );

  final Dio _dio;

  Future<PlaceDetails> reverse(LatLng position) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://nominatim.openstreetmap.org/reverse',
      queryParameters: {
        'format': 'jsonv2',
        'lat': position.latitude,
        'lon': position.longitude,
        'zoom': 18,
        'addressdetails': 1,
        'extratags': 1,
        'namedetails': 1,
        'accept-language': 'fa,en',
      },
    );

    final data = response.data ?? const <String, dynamic>{};
    final names =
        data['namedetails'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final extra =
        data['extratags'] as Map<String, dynamic>? ?? const <String, dynamic>{};

    final title = (names['name:fa'] ??
            names['name'] ??
            data['name'] ??
            data['display_name'] ??
            'مکان')
        .toString();

    String? firstExtra(List<String> keys) {
      for (final key in keys) {
        final value = extra[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    return PlaceDetails(
      title: title,
      address: (data['display_name'] ?? '').toString(),
      category: (data['category'] ?? '').toString(),
      type: (data['type'] ?? '').toString(),
      phone: firstExtra(['phone', 'contact:phone', 'mobile', 'contact:mobile']),
      website: firstExtra(['website', 'contact:website']),
      openingHours: firstExtra(['opening_hours']),
      wikipedia: firstExtra(['wikipedia']),
      wikidata: firstExtra(['wikidata']),
      wheelchair: firstExtra(['wheelchair']),
    );
  }
}
