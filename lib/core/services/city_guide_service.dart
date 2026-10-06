import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/offline_place_cache_service.dart';
import 'package:masir/features/search/models/place_result.dart';

enum CityGuideSection {
  sights,
  food,
  stay,
  services,
  shopping;

  String get label => switch (this) {
        CityGuideSection.sights => 'دیدنی‌ها',
        CityGuideSection.food => 'خوردنی',
        CityGuideSection.stay => 'اقامت',
        CityGuideSection.services => 'خدمات',
        CityGuideSection.shopping => 'خرید',
      };
}

class CityGuidePlace {
  const CityGuidePlace({
    required this.name,
    required this.category,
    required this.section,
    required this.position,
    this.openingHours,
    this.wikipedia,
    this.offline = false,
  });

  final String name;
  final String category;
  final CityGuideSection section;
  final LatLng position;
  final String? openingHours;
  final String? wikipedia;
  final bool offline;
}

class CityGuideService {
  CityGuideService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 24),
                sendTimeout: const Duration(seconds: 10),
                headers: const {
                  'User-Agent': 'MasirNavigation/1.2 (ir.sahand.masir)',
                },
              ),
            );

  final Dio _dio;
  final _offlineCache = OfflinePlaceCacheService();

  static const _endpoints = <String>[
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  Future<List<CityGuidePlace>> load(
    LatLng center, {
    int radiusMeters = 7000,
  }) async {
    final lat = center.latitude;
    final lon = center.longitude;
    final q = '[out:json][timeout:25];('
        'nwr(around:$radiusMeters,$lat,$lon)["tourism"~"attraction|museum|viewpoint|gallery|information|hotel|hostel|guest_house"];'
        'nwr(around:$radiusMeters,$lat,$lon)["historic"];'
        'nwr(around:$radiusMeters,$lat,$lon)["leisure"~"park|garden"];'
        'nwr(around:$radiusMeters,$lat,$lon)["amenity"~"restaurant|cafe|hospital|clinic|pharmacy|fuel|parking"];'
        'nwr(around:$radiusMeters,$lat,$lon)["shop"~"supermarket|mall|convenience"];'
        ');out center tags;';

    Response<Map<String, dynamic>> response;
    try {
      response = await _post(q);
    } catch (_) {
      return _offlineFallback(center, radiusMeters: radiusMeters);
    }

    final elements =
        (response.data?['elements'] as List<dynamic>?) ?? const <dynamic>[];
    final out = <CityGuidePlace>[];
    final seen = <String>{};

    for (final raw in elements) {
      final e = raw as Map<String, dynamic>;
      final tags = (e['tags'] as Map<String, dynamic>?) ?? const {};
      final centerData = e['center'] as Map<String, dynamic>?;
      final latValue = (e['lat'] as num?)?.toDouble() ??
          (centerData?['lat'] as num?)?.toDouble();
      final lonValue = (e['lon'] as num?)?.toDouble() ??
          (centerData?['lon'] as num?)?.toDouble();
      if (latValue == null || lonValue == null) continue;

      final rawCategory =
          (tags['tourism'] ?? tags['historic'] ?? tags['leisure'] ??
                  tags['amenity'] ?? tags['shop'])
              ?.toString();
      if (rawCategory == null || rawCategory.isEmpty) continue;

      final name =
          (tags['name:fa'] ?? tags['name'] ?? _fallbackName(rawCategory))
              .toString()
              .trim();
      final key =
          '${name.toLowerCase()}|${latValue.toStringAsFixed(5)}|${lonValue.toStringAsFixed(5)}';
      if (!seen.add(key)) continue;

      out.add(
        CityGuidePlace(
          name: name,
          category: rawCategory,
          section: _sectionFor(rawCategory),
          position: LatLng(latValue, lonValue),
          openingHours: tags['opening_hours']?.toString(),
          wikipedia: tags['wikipedia']?.toString(),
        ),
      );
    }

    final items = out.take(180).toList(growable: false);
    await _offlineCache.merge(
      items.map(
        (place) => PlaceResult(
          title: place.name,
          subtitle: '${place.section.label} · ${place.category}',
          position: place.position,
        ),
      ),
    );
    return items;
  }

  Future<List<CityGuidePlace>> _offlineFallback(
    LatLng center, {
    required int radiusMeters,
  }) async {
    final cached = await _offlineCache.nearby(
      center,
      radiusMeters: radiusMeters.toDouble(),
      limit: 160,
    );
    return cached
        .map(
          (place) {
            final category = _categoryFromSubtitle(place.subtitle);
            return CityGuidePlace(
              name: place.title,
              category: category,
              section: _sectionFor(category),
              position: place.position,
              offline: true,
            );
          },
        )
        .toList(growable: false);
  }

  String _categoryFromSubtitle(String subtitle) {
    final value = subtitle.toLowerCase();
    if (value.contains('رستوران')) return 'restaurant';
    if (value.contains('کافه')) return 'cafe';
    if (value.contains('هتل')) return 'hotel';
    if (value.contains('هاستل')) return 'hostel';
    if (value.contains('مهمان')) return 'guest_house';
    if (value.contains('بیمارستان')) return 'hospital';
    if (value.contains('درمانگاه')) return 'clinic';
    if (value.contains('داروخانه')) return 'pharmacy';
    if (value.contains('پمپ')) return 'fuel';
    if (value.contains('پارکینگ')) return 'parking';
    if (value.contains('فروشگاه') || value.contains('سوپر')) {
      return 'convenience';
    }
    if (value.contains('مرکز خرید')) return 'mall';
    if (value.contains('پارک')) return 'park';
    if (value.contains('موزه')) return 'museum';
    return 'attraction';
  }

  Future<Response<Map<String, dynamic>>> _post(String query) async {
    Object? lastError;
    for (final endpoint in _endpoints) {
      try {
        return await _dio.post<Map<String, dynamic>>(
          endpoint,
          data: query,
          options: Options(contentType: Headers.textPlainContentType),
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('Overpass unavailable: $lastError');
  }

  CityGuideSection _sectionFor(String category) {
    if (const {'restaurant', 'cafe'}.contains(category)) {
      return CityGuideSection.food;
    }
    if (const {'hotel', 'hostel', 'guest_house'}.contains(category)) {
      return CityGuideSection.stay;
    }
    if (const {'hospital', 'clinic', 'pharmacy', 'fuel', 'parking'}
        .contains(category)) {
      return CityGuideSection.services;
    }
    if (const {'supermarket', 'mall', 'convenience'}.contains(category)) {
      return CityGuideSection.shopping;
    }
    return CityGuideSection.sights;
  }

  String _fallbackName(String category) {
    const labels = <String, String>{
      'attraction': 'جاذبه گردشگری',
      'museum': 'موزه',
      'viewpoint': 'چشم‌انداز',
      'gallery': 'گالری',
      'information': 'اطلاعات گردشگری',
      'historic': 'مکان تاریخی',
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
}
