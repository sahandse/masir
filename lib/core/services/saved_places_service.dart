import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:masir/features/search/models/place_result.dart';

class SavedPlacesService {
  static const _homeKey = 'saved_home';
  static const _workKey = 'saved_work';
  static const _favoritesKey = 'saved_favorites';
  static const _historyKey = 'saved_history';

  Future<void> saveHome(PlaceResult place) => _saveSingle(_homeKey, place);
  Future<void> saveWork(PlaceResult place) => _saveSingle(_workKey, place);

  Future<PlaceResult?> getHome() => _readSingle(_homeKey);
  Future<PlaceResult?> getWork() => _readSingle(_workKey);

  Future<void> addFavorite(PlaceResult place) => _appendUnique(_favoritesKey, place, 30);
  Future<void> addHistory(PlaceResult place) => _appendUnique(_historyKey, place, 30);

  Future<List<PlaceResult>> getFavorites() => _readList(_favoritesKey);
  Future<List<PlaceResult>> getHistory() => _readList(_historyKey);

  Future<void> _saveSingle(String key, PlaceResult place) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(_toJson(place)));
  }

  Future<PlaceResult?> _readSingle(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    return _fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _appendUnique(String key, PlaceResult place, int limit) async {
    final current = await _readList(key);
    current.removeWhere((e) =>
        e.position.latitude == place.position.latitude &&
        e.position.longitude == place.position.longitude);
    current.insert(0, place);
    if (current.length > limit) current.removeRange(limit, current.length);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      key,
      current.map((e) => jsonEncode(_toJson(e))).toList(),
    );
  }

  Future<List<PlaceResult>> _readList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList(key) ?? const [];
    return rows
        .map((row) => _fromJson(jsonDecode(row) as Map<String, dynamic>))
        .toList();
  }

  Map<String, dynamic> _toJson(PlaceResult place) => {
        'title': place.title,
        'subtitle': place.subtitle,
        'lat': place.position.latitude,
        'lon': place.position.longitude,
      };

  PlaceResult _fromJson(Map<String, dynamic> json) => PlaceResult(
        title: json['title'] as String? ?? 'مکان ذخیره‌شده',
        subtitle: json['subtitle'] as String? ?? '',
        position: LatLng(
          (json['lat'] as num).toDouble(),
          (json['lon'] as num).toDouble(),
        ),
      );
}
