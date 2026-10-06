import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:masir/features/search/models/place_result.dart';

class OfflinePlaceCacheService {
  static const _key = 'offline_place_cache_v1';
  static const _limit = 1200;

  Future<void> merge(Iterable<PlaceResult> places) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await _loadMap(prefs);

    for (final place in places) {
      final key =
          '${place.position.latitude.toStringAsFixed(5)},${place.position.longitude.toStringAsFixed(5)}|${place.title.toLowerCase()}';
      current[key] = {
        'title': place.title,
        'subtitle': place.subtitle,
        'lat': place.position.latitude,
        'lon': place.position.longitude,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
    }

    if (current.length > _limit) {
      final entries = current.entries.toList()
        ..sort((a, b) {
          final ad = DateTime.tryParse(
                (a.value as Map<String, dynamic>)['updated_at'] as String? ?? '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bd = DateTime.tryParse(
                (b.value as Map<String, dynamic>)['updated_at'] as String? ?? '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bd.compareTo(ad);
        });
      final trimmed = <String, dynamic>{
        for (final entry in entries.take(_limit)) entry.key: entry.value,
      };
      await prefs.setString(_key, jsonEncode(trimmed));
      return;
    }

    await prefs.setString(_key, jsonEncode(current));
  }

  Future<List<PlaceResult>> search(String query, {int limit = 20}) async {
    final q = _normalize(query);
    if (q.length < 2) return const [];

    final prefs = await SharedPreferences.getInstance();
    final current = await _loadMap(prefs);
    final scored = <({PlaceResult place, int score})>[];

    for (final value in current.values) {
      final item = value as Map<String, dynamic>;
      final title = item['title'] as String? ?? '';
      final subtitle = item['subtitle'] as String? ?? '';
      final haystack = _normalize('$title $subtitle');
      if (!haystack.contains(q)) continue;

      var score = 1;
      if (_normalize(title) == q) {
        score = 5;
      } else if (_normalize(title).startsWith(q)) {
        score = 4;
      } else if (_normalize(title).contains(q)) {
        score = 3;
      } else if (_normalize(subtitle).contains(q)) {
        score = 2;
      }

      final lat = (item['lat'] as num?)?.toDouble();
      final lon = (item['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;

      scored.add((
        place: PlaceResult(
          title: title.isEmpty ? 'مکان ذخیره‌شده' : title,
          subtitle: subtitle.isEmpty ? 'ذخیره آفلاین' : subtitle,
          position: LatLng(lat, lon),
        ),
        score: score,
      ));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((e) => e.place).toList(growable: false);
  }

  Future<int> count() async {
    final prefs = await SharedPreferences.getInstance();
    final current = await _loadMap(prefs);
    return current.length;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<Map<String, dynamic>> _loadMap(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _normalize(String input) => input
      .toLowerCase()
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
