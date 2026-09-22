import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/features/search/models/place_result.dart';

class NominatimService {
  NominatimService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(headers: {
              'User-Agent': 'MasirNavigation/0.2 (Flutter)',
            }));

  final Dio _dio;

  Future<List<PlaceResult>> search(String query) async {
    if (query.trim().length < 2) return const [];
    final response = await _dio.get<List<dynamic>>(
      'https://nominatim.openstreetmap.org/search',
      queryParameters: {
        'q': query.trim(),
        'format': 'jsonv2',
        'addressdetails': 1,
        'accept-language': 'fa,en',
        'limit': 8,
      },
    );
    return (response.data ?? const []).map((raw) {
      final item = raw as Map<String, dynamic>;
      final display = (item['display_name'] as String?) ?? 'بدون نام';
      final parts = display.split(',');
      return PlaceResult(
        title: parts.first.trim(),
        subtitle: parts.skip(1).take(3).join('،').trim(),
        position: LatLng(
          double.parse(item['lat'] as String),
          double.parse(item['lon'] as String),
        ),
      );
    }).toList();
  }
}
