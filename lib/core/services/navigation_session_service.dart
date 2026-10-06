import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:masir/core/services/navigation_preferences_service.dart';
import 'package:masir/features/search/models/place_result.dart';

class NavigationSession {
  const NavigationSession({
    required this.destination,
    required this.viaPoints,
    this.mode = TravelMode.driving,
  });

  final PlaceResult destination;
  final List<PlaceResult> viaPoints;
  final TravelMode mode;
}

class NavigationSessionService {
  static const _key = 'active_navigation_session';

  Future<void> save({
    required PlaceResult destination,
    required List<PlaceResult> viaPoints,
    TravelMode mode = TravelMode.driving,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({
      'destination': _toJson(destination),
      'via': viaPoints.map(_toJson).toList(),
      'mode': mode.name,
    }));
  }

  Future<NavigationSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final destination = _fromJson(data['destination'] as Map<String, dynamic>);
      final via = ((data['via'] as List<dynamic>?) ?? const [])
          .map((e) => _fromJson(e as Map<String, dynamic>))
          .toList();
      return NavigationSession(
        destination: destination,
        viaPoints: via,
        mode: TravelMode.fromStorage(data['mode'] as String?),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Map<String, dynamic> _toJson(PlaceResult p) => {
        'title': p.title,
        'subtitle': p.subtitle,
        'lat': p.position.latitude,
        'lon': p.position.longitude,
      };

  PlaceResult _fromJson(Map<String, dynamic> j) => PlaceResult(
        title: j['title'] as String? ?? 'مکان',
        subtitle: j['subtitle'] as String? ?? '',
        position: LatLng(
          (j['lat'] as num).toDouble(),
          (j['lon'] as num).toDouble(),
        ),
      );
}
