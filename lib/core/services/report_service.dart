import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RoadReport {
  const RoadReport({
    required this.id,
    required this.type,
    required this.position,
    required this.createdAt,
  });

  final String id;
  final String type;
  final LatLng position;
  final DateTime createdAt;

  String get labelFa {
    switch (type) {
      case 'traffic':
        return 'ترافیک';
      case 'accident':
        return 'تصادف';
      case 'closure':
        return 'مسیر بسته';
      case 'hazard':
        return 'خطر';
      case 'police':
        return 'پلیس';
      case 'roadwork':
        return 'عملیات جاده‌ای';
      default:
        return 'گزارش';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'lat': position.latitude,
        'lon': position.longitude,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory RoadReport.fromJson(Map<String, dynamic> json) => RoadReport(
        id: json['id'] as String? ??
            '${json['lat']}_${json['lon']}_${json['created_at']}',
        type: json['type'] as String? ?? 'hazard',
        position: LatLng(
          (json['lat'] as num).toDouble(),
          (json['lon'] as num).toDouble(),
        ),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now().toUtc(),
      );
}

/// Community-style reports: always persist locally (free, offline-capable).
/// When [REPORT_API_BASE_URL] is set, also sync to the project backend.
class ReportService {
  ReportService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const _localKey = 'local_road_reports_v1';
  static const _maxAge = Duration(hours: 6);
  static const _maxStored = 80;
  static const _baseUrl = String.fromEnvironment('REPORT_API_BASE_URL');

  bool get isConfigured => _baseUrl.trim().isNotEmpty;

  /// Always available: saves on-device. Optionally posts to backend.
  Future<RoadReport> submit({
    required String type,
    required LatLng position,
  }) async {
    final report = RoadReport(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      position: position,
      createdAt: DateTime.now().toUtc(),
    );

    await _saveLocal(report);

    if (isConfigured) {
      try {
        await _dio.post(
          '$_baseUrl/reports',
          data: report.toJson(),
          options: Options(
            contentType: Headers.jsonContentType,
            receiveTimeout: const Duration(seconds: 12),
            sendTimeout: const Duration(seconds: 12),
          ),
        );
      } catch (_) {
        // Local report remains; remote sync can fail without blocking UX.
      }
    }

    return report;
  }

  Future<List<RoadReport>> nearby({
    required LatLng center,
    double radiusMeters = 8000,
  }) async {
    final local = await _loadLocalFresh();
    final distance = const Distance();
    final fromLocal = local
        .where((r) => distance(center, r.position) <= radiusMeters)
        .toList();

    if (!isConfigured) return fromLocal;

    try {
      final response = await _dio.get<List<dynamic>>(
        '$_baseUrl/reports',
        queryParameters: {
          'lat': center.latitude,
          'lon': center.longitude,
          'radius_m': radiusMeters.round(),
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 12),
          sendTimeout: const Duration(seconds: 12),
        ),
      );
      final remote = (response.data ?? const [])
          .whereType<Map>()
          .map((e) => RoadReport.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return _mergeUnique([...fromLocal, ...remote]);
    } catch (_) {
      return fromLocal;
    }
  }

  Future<List<RoadReport>> _loadLocalFresh() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList(_localKey) ?? const [];
    final now = DateTime.now().toUtc();
    final fresh = <RoadReport>[];
    for (final row in rows) {
      try {
        final report = RoadReport.fromJson(
          jsonDecode(row) as Map<String, dynamic>,
        );
        if (now.difference(report.createdAt) <= _maxAge) {
          fresh.add(report);
        }
      } catch (_) {
        // Skip corrupt rows.
      }
    }
    if (fresh.length != rows.length) {
      await prefs.setStringList(
        _localKey,
        fresh.map((e) => jsonEncode(e.toJson())).toList(),
      );
    }
    return fresh;
  }

  Future<void> _saveLocal(RoadReport report) async {
    final current = await _loadLocalFresh();
    current.insert(0, report);
    if (current.length > _maxStored) {
      current.removeRange(_maxStored, current.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _localKey,
      current.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  List<RoadReport> _mergeUnique(List<RoadReport> items) {
    final seen = <String>{};
    final out = <RoadReport>[];
    for (final item in items) {
      final key =
          '${item.type}_${item.position.latitude.toStringAsFixed(4)}_${item.position.longitude.toStringAsFixed(4)}';
      if (seen.add(key)) out.add(item);
    }
    return out;
  }
}
