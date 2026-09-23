import 'dart:async';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/features/search/models/place_result.dart';

class NominatimService {
  NominatimService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                headers: const {
                  'User-Agent': 'MasirNavigation/0.7 (ir.sahand.masir)',
                  'Accept-Language': 'fa,en',
                },
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 12),
                sendTimeout: const Duration(seconds: 10),
              ),
            );

  final Dio _dio;

  static final Map<String, _CachedSearch> _cache = {};
  static DateTime? _lastRequestAt;
  static Future<void>? _rateLimitGate;
  static const _cacheTtl = Duration(minutes: 15);
  static const _minRequestGap = Duration(milliseconds: 1100);

  Future<List<PlaceResult>> search(String query) async {
    final normalized = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length < 2) return const [];

    final cacheKey = normalized.toLowerCase();
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.createdAt) < _cacheTtl) {
      return cached.items;
    }

    await _waitForRateLimit();

    final response = await _dio.get<List<dynamic>>(
      'https://nominatim.openstreetmap.org/search',
      queryParameters: {
        'q': normalized,
        'format': 'jsonv2',
        'addressdetails': 1,
        'namedetails': 1,
        'accept-language': 'fa,en',
        'limit': 10,
        'dedupe': 1,
      },
    );

    final items = (response.data ?? const []).map((raw) {
      final item = raw as Map<String, dynamic>;
      final display = (item['display_name'] as String?) ?? 'بدون نام';
      final parts = display.split(',');
      final namedetails = item['namedetails'] as Map<String, dynamic>?;
      final title = (namedetails?['name:fa'] ?? namedetails?['name'] ?? parts.first).toString().trim();

      return PlaceResult(
        title: title.isEmpty ? parts.first.trim() : title,
        subtitle: parts.skip(1).take(4).join('،').trim(),
        position: LatLng(
          double.parse(item['lat'] as String),
          double.parse(item['lon'] as String),
        ),
      );
    }).toList(growable: false);

    _cache[cacheKey] = _CachedSearch(DateTime.now(), items);
    _trimCache();
    return items;
  }

  Future<void> _waitForRateLimit() async {
    while (_rateLimitGate != null) {
      await _rateLimitGate;
    }

    final completer = Completer<void>();
    _rateLimitGate = completer.future;
    try {
      final last = _lastRequestAt;
      if (last != null) {
        final elapsed = DateTime.now().difference(last);
        if (elapsed < _minRequestGap) {
          await Future<void>.delayed(_minRequestGap - elapsed);
        }
      }
      _lastRequestAt = DateTime.now();
    } finally {
      completer.complete();
      _rateLimitGate = null;
    }
  }

  void _trimCache() {
    if (_cache.length <= 80) return;
    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));
    for (final entry in entries.take(_cache.length - 60)) {
      _cache.remove(entry.key);
    }
  }
}

class _CachedSearch {
  const _CachedSearch(this.createdAt, this.items);

  final DateTime createdAt;
  final List<PlaceResult> items;
}
