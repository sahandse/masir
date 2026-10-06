import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MapFeedbackType {
  wrongName,
  missingPlace,
  placeClosed,
  roadClosed,
  wrongRoad,
  accessIssue,
  other;

  String get apiValue => switch (this) {
        MapFeedbackType.wrongName => 'wrong_name',
        MapFeedbackType.missingPlace => 'missing_place',
        MapFeedbackType.placeClosed => 'place_closed',
        MapFeedbackType.roadClosed => 'road_closed',
        MapFeedbackType.wrongRoad => 'wrong_road',
        MapFeedbackType.accessIssue => 'access_issue',
        MapFeedbackType.other => 'other',
      };

  String get label => switch (this) {
        MapFeedbackType.wrongName => 'نام اشتباه است',
        MapFeedbackType.missingPlace => 'مکان در نقشه نیست',
        MapFeedbackType.placeClosed => 'این مکان تعطیل/حذف شده',
        MapFeedbackType.roadClosed => 'مسیر بسته است',
        MapFeedbackType.wrongRoad => 'اطلاعات خیابان اشتباه است',
        MapFeedbackType.accessIssue => 'محدودیت دسترسی اشتباه است',
        MapFeedbackType.other => 'مورد دیگر',
      };
}

class MapFeedbackService {
  MapFeedbackService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _baseUrl = String.fromEnvironment('MAP_FEEDBACK_API_BASE_URL');
  static const _queueKey = 'map_feedback_queue_v1';

  bool get isConfigured => _baseUrl.trim().isNotEmpty;

  Future<bool> submit({
    required MapFeedbackType type,
    required LatLng position,
    required String note,
  }) async {
    final payload = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'type': type.apiValue,
      'lat': position.latitude,
      'lon': position.longitude,
      'note': note.trim(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (!isConfigured) {
      await _enqueue(payload);
      return false;
    }

    try {
      await _dio.post('$_baseUrl/feedback', data: payload);
      return true;
    } catch (_) {
      await _enqueue(payload);
      return false;
    }
  }

  Future<int> pendingCount() async => (await _load()).length;

  Future<int> syncPending() async {
    if (!isConfigured) return 0;
    final queue = await _load();
    if (queue.isEmpty) return 0;

    final remaining = <Map<String, dynamic>>[];
    var sent = 0;
    for (final payload in queue) {
      try {
        await _dio.post('$_baseUrl/feedback', data: payload);
        sent++;
      } catch (_) {
        remaining.add(payload);
      }
    }
    await _save(remaining);
    return sent;
  }

  Future<void> _enqueue(Map<String, dynamic> payload) async {
    final queue = await _load();
    queue.add(payload);
    if (queue.length > 40) queue.removeRange(0, queue.length - 40);
    await _save(queue);
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _save(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, jsonEncode(items));
  }
}
