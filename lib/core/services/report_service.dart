import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum RoadReportType {
  traffic,
  accident,
  police,
  camera,
  speedBump,
  closure,
  roadwork,
  hazard;

  String get apiValue => switch (this) {
        RoadReportType.traffic => 'traffic',
        RoadReportType.accident => 'accident',
        RoadReportType.police => 'police',
        RoadReportType.camera => 'camera',
        RoadReportType.speedBump => 'speed_bump',
        RoadReportType.closure => 'closure',
        RoadReportType.roadwork => 'roadwork',
        RoadReportType.hazard => 'hazard',
      };

  String get label => switch (this) {
        RoadReportType.traffic => 'ترافیک',
        RoadReportType.accident => 'تصادف',
        RoadReportType.police => 'پلیس',
        RoadReportType.camera => 'دوربین',
        RoadReportType.speedBump => 'سرعت‌گیر',
        RoadReportType.closure => 'مسیر بسته',
        RoadReportType.roadwork => 'عملیات جاده‌ای',
        RoadReportType.hazard => 'خطر در مسیر',
      };

  static RoadReportType? fromApi(String? value) {
    for (final type in RoadReportType.values) {
      if (type.apiValue == value) return type;
    }
    return null;
  }
}

class RoadReport {
  const RoadReport({
    required this.id,
    required this.type,
    required this.position,
    required this.createdAt,
    this.confirmations = 0,
    this.verified = false,
  });

  final String id;
  final RoadReportType type;
  final LatLng position;
  final DateTime createdAt;
  final int confirmations;
  final bool verified;

  factory RoadReport.fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lon = (json['lon'] as num?)?.toDouble();
    final type = RoadReportType.fromApi(json['type'] as String?);
    if (lat == null || lon == null || type == null) {
      throw const FormatException('Invalid road report payload');
    }
    return RoadReport(
      id: (json['id'] ?? '').toString(),
      type: type,
      position: LatLng(lat, lon),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
      confirmations: (json['confirmations'] as num?)?.toInt() ?? 0,
      verified: json['verified'] == true,
    );
  }
}

class QueuedRoadReport {
  const QueuedRoadReport({
    required this.id,
    required this.type,
    required this.position,
    required this.createdAt,
  });

  final String id;
  final RoadReportType type;
  final LatLng position;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.apiValue,
        'lat': position.latitude,
        'lon': position.longitude,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory QueuedRoadReport.fromJson(Map<String, dynamic> json) {
    final type = RoadReportType.fromApi(json['type'] as String?);
    final lat = (json['lat'] as num?)?.toDouble();
    final lon = (json['lon'] as num?)?.toDouble();
    if (type == null || lat == null || lon == null) {
      throw const FormatException('Invalid queued report');
    }
    return QueuedRoadReport(
      id: (json['id'] ?? '').toString(),
      type: type,
      position: LatLng(lat, lon),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
    );
  }
}

class ReportSubmitResult {
  const ReportSubmitResult({
    required this.sent,
    required this.queued,
  });

  final bool sent;
  final bool queued;
}

class ReportService {
  ReportService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12),
                sendTimeout: const Duration(seconds: 8),
              ),
            );

  final Dio _dio;

  static const _baseUrl = String.fromEnvironment('REPORT_API_BASE_URL');
  static const _queueKey = 'road_report_queue_v1';

  bool get isConfigured => _baseUrl.trim().isNotEmpty;

  Future<ReportSubmitResult> submit({
    required RoadReportType type,
    required LatLng position,
  }) async {
    final item = QueuedRoadReport(
      id: '\${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      position: position,
      createdAt: DateTime.now().toUtc(),
    );

    if (!isConfigured) {
      await _enqueue(item);
      return const ReportSubmitResult(sent: false, queued: true);
    }

    try {
      await _send(item);
      return const ReportSubmitResult(sent: true, queued: false);
    } catch (_) {
      await _enqueue(item);
      return const ReportSubmitResult(sent: false, queued: true);
    }
  }

  Future<List<RoadReport>> nearby(
    LatLng position, {
    int radiusMeters = 5000,
  }) async {
    if (!isConfigured) return const [];
    final response = await _dio.get<dynamic>(
      '$_baseUrl/reports',
      queryParameters: {
        'lat': position.latitude,
        'lon': position.longitude,
        'radius_m': radiusMeters,
      },
    );
    final raw = response.data is List
        ? response.data as List<dynamic>
        : ((response.data as Map<String, dynamic>?)?['reports']
                as List<dynamic>?) ??
            const <dynamic>[];

    final out = <RoadReport>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final report = RoadReport.fromJson(item);
        if (DateTime.now().toUtc().difference(report.createdAt) <=
            const Duration(hours: 6)) {
          out.add(report);
        }
      } catch (_) {
        // Ignore malformed server rows.
      }
    }
    return out;
  }

  Future<int> pendingCount() async => (await _loadQueue()).length;

  Future<int> syncPending() async {
    if (!isConfigured) return 0;
    final queue = await _loadQueue();
    if (queue.isEmpty) return 0;

    final remaining = <QueuedRoadReport>[];
    var sent = 0;
    for (final item in queue) {
      try {
        await _send(item);
        sent++;
      } catch (_) {
        remaining.add(item);
      }
    }
    await _saveQueue(remaining);
    return sent;
  }

  Future<void> _send(QueuedRoadReport item) async {
    await _dio.post(
      '$_baseUrl/reports',
      data: item.toJson(),
    );
  }

  Future<void> _enqueue(QueuedRoadReport item) async {
    final queue = await _loadQueue();
    queue.add(item);
    if (queue.length > 30) {
      queue.removeRange(0, queue.length - 30);
    }
    await _saveQueue(queue);
  }

  Future<List<QueuedRoadReport>> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return <QueuedRoadReport>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(QueuedRoadReport.fromJson)
          .toList();
    } catch (_) {
      return <QueuedRoadReport>[];
    }
  }

  Future<void> _saveQueue(List<QueuedRoadReport> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _queueKey,
      jsonEncode(queue.map((item) => item.toJson()).toList()),
    );
  }
}
