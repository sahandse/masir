import 'dart:convert';
import 'dart:math';

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

  Duration get maxAge => switch (this) {
        RoadReportType.traffic => const Duration(minutes: 45),
        RoadReportType.accident => const Duration(hours: 3),
        RoadReportType.police => const Duration(hours: 2),
        RoadReportType.camera => const Duration(hours: 24),
        RoadReportType.speedBump => const Duration(hours: 24),
        RoadReportType.closure => const Duration(hours: 24),
        RoadReportType.roadwork => const Duration(hours: 24),
        RoadReportType.hazard => const Duration(hours: 3),
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
    this.denies = 0,
    this.verified = false,
  });

  final String id;
  final RoadReportType type;
  final LatLng position;
  final DateTime createdAt;
  final int confirmations;
  final int denies;
  final bool verified;

  bool get isFresh =>
      DateTime.now().toUtc().difference(createdAt) <= type.maxAge;

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
      denies: (json['denies'] as num?)?.toInt() ?? 0,
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

class QueuedReportVote {
  const QueuedReportVote({
    required this.reportId,
    required this.confirm,
    required this.createdAt,
  });

  final String reportId;
  final bool confirm;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'report_id': reportId,
        'vote': confirm ? 'confirm' : 'deny',
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory QueuedReportVote.fromJson(Map<String, dynamic> json) {
    final id = (json['report_id'] ?? '').toString();
    if (id.isEmpty) throw const FormatException('Invalid queued vote');
    return QueuedReportVote(
      reportId: id,
      confirm: json['vote'] != 'deny',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
    );
  }
}

class ReportSubmitResult {
  const ReportSubmitResult({
    required this.sent,
    required this.queued,
    this.reportId,
  });

  final bool sent;
  final bool queued;
  final String? reportId;
}

class ReportVoteResult {
  const ReportVoteResult({
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
  final _random = Random();
  final _distance = const Distance();

  static const _configuredBaseUrl =
      String.fromEnvironment('REPORT_API_BASE_URL');
  static const _queueKey = 'road_report_queue_v1';
  static const _localKey = 'road_report_local_v1';
  static const _votesKey = 'road_report_votes_v1';
  static const _clientKey = 'road_report_client_id_v1';

  String? _clientId;

  String get _baseUrl => _configuredBaseUrl.trim().replaceFirst(
        RegExp(r'/+$'),
        '',
      );

  bool get isConfigured => _baseUrl.isNotEmpty;

  Future<ReportSubmitResult> submit({
    required RoadReportType type,
    required LatLng position,
  }) async {
    final item = QueuedRoadReport(
      id: '${DateTime.now().microsecondsSinceEpoch}'
          '-${_random.nextInt(0xFFFFFF).toRadixString(16)}',
      type: type,
      position: position,
      createdAt: DateTime.now().toUtc(),
    );

    await _saveLocal(item);

    if (!isConfigured) {
      await _enqueue(item);
      return ReportSubmitResult(
        sent: false,
        queued: true,
        reportId: item.id,
      );
    }

    try {
      await _send(item);
      await _removeQueued(item.id);
      return ReportSubmitResult(
        sent: true,
        queued: false,
        reportId: item.id,
      );
    } catch (error) {
      final permanent = _isPermanentFailure(error);
      if (!permanent) await _enqueue(item);
      return ReportSubmitResult(
        sent: false,
        queued: !permanent,
        reportId: item.id,
      );
    }
  }

  Future<Set<String>> localReportIds() async {
    final items = await _loadLocal();
    return items
        .where(_isFresh)
        .map((item) => item.id)
        .toSet();
  }

  Future<List<RoadReport>> nearby(
    LatLng position, {
    int radiusMeters = 5000,
  }) async {
    final local = await _localReportsNear(position, radiusMeters);
    if (!isConfigured) return local;

    List<RoadReport> serverReports;
    try {
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

      serverReports = <RoadReport>[];
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        try {
          final report = RoadReport.fromJson(item);
          if (report.isFresh) serverReports.add(report);
        } catch (_) {
          // Ignore malformed server rows.
        }
      }
    } catch (_) {
      return local;
    }

    final merged = <String, RoadReport>{
      for (final report in serverReports) report.id: report,
    };
    for (final report in local) {
      merged.putIfAbsent(report.id, () => report);
    }
    final out = merged.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<ReportVoteResult> confirm(String reportId) =>
      _vote(reportId, confirm: true);

  Future<ReportVoteResult> deny(String reportId) =>
      _vote(reportId, confirm: false);

  Future<int> pendingCount() async => (await _loadQueue()).length;

  Future<int> pendingVotesCount() async => (await _loadVotes()).length;

  Future<int> syncPending() async {
    final queue = await _loadQueue();
    var sent = 0;
    final remaining = <QueuedRoadReport>[];
    for (final item in queue) {
      try {
        await _send(item);
        sent++;
      } catch (error) {
        if (!_isPermanentFailure(error)) remaining.add(item);
      }
    }
    if (queue.isNotEmpty) await _saveQueue(remaining);

    final votes = await _loadVotes();
    final remainingVotes = <QueuedReportVote>[];
    for (final vote in votes) {
      try {
        await _sendVote(vote);
        sent++;
      } catch (error) {
        if (!_isPermanentFailure(error)) remainingVotes.add(vote);
      }
    }
    if (votes.isNotEmpty) await _saveVotes(remainingVotes);
    return sent;
  }

  Future<ReportVoteResult> _vote(String reportId, {required bool confirm}) async {
    final vote = QueuedReportVote(
      reportId: reportId,
      confirm: confirm,
      createdAt: DateTime.now().toUtc(),
    );

    if (!isConfigured) {
      await _enqueueVote(vote);
      return const ReportVoteResult(sent: false, queued: true);
    }

    try {
      await _sendVote(vote);
      return const ReportVoteResult(sent: true, queued: false);
    } catch (error) {
      if (_isPermanentFailure(error)) {
        return const ReportVoteResult(sent: false, queued: false);
      }
      await _enqueueVote(vote);
      return const ReportVoteResult(sent: false, queued: true);
    }
  }

  bool _isPermanentFailure(Object error) {
    if (error is! DioException) return false;
    final status = error.response?.statusCode ?? 0;
    return status >= 400 && status < 500 && status != 408 && status != 429;
  }

  Future<void> _send(QueuedRoadReport item) async {
    await _dio.post(
      '$_baseUrl/reports',
      data: item.toJson(),
      options: Options(headers: {'X-Client-Id': await _ensureClientId()}),
    );
  }

  Future<void> _sendVote(QueuedReportVote vote) async {
    await _dio.post(
      '$_baseUrl/reports/${vote.reportId}/${vote.confirm ? 'confirm' : 'deny'}',
      data: const <String, dynamic>{},
      options: Options(headers: {'X-Client-Id': await _ensureClientId()}),
    );
  }

  Future<String> _ensureClientId() async {
    final cached = _clientId;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_clientKey);
    if (id == null || id.isEmpty) {
      id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
          '-${_random.nextInt(0x7FFFFFFF).toRadixString(36)}';
      await prefs.setString(_clientKey, id);
    }
    _clientId = id;
    return id;
  }

  Future<void> _enqueue(QueuedRoadReport item) async {
    final queue = await _loadQueue();
    if (queue.any((entry) => entry.id == item.id)) return;
    queue.add(item);
    if (queue.length > 30) {
      queue.removeRange(0, queue.length - 30);
    }
    await _saveQueue(queue);
  }

  Future<void> _removeQueued(String id) async {
    final queue = await _loadQueue();
    final next = queue.where((item) => item.id != id).toList();
    if (next.length != queue.length) await _saveQueue(next);
  }

  Future<void> _enqueueVote(QueuedReportVote vote) async {
    final votes = await _loadVotes();
    votes.removeWhere((item) => item.reportId == vote.reportId);
    votes.add(vote);
    if (votes.length > 50) {
      votes.removeRange(0, votes.length - 50);
    }
    await _saveVotes(votes);
  }

  Future<void> _saveLocal(QueuedRoadReport item) async {
    final items = await _loadLocal();
    items.removeWhere((entry) => entry.id == item.id);
    items.add(item);
    final fresh = items.where(_isFresh).toList();
    if (fresh.length > 50) {
      fresh.removeRange(0, fresh.length - 50);
    }
    await _saveLocalItems(fresh);
  }

  Future<List<RoadReport>> _localReportsNear(
    LatLng position,
    int radiusMeters,
  ) async {
    final items = await _loadLocal();
    final fresh = items.where(_isFresh).toList(growable: false);
    if (fresh.length != items.length) {
      await _saveLocalItems(fresh);
    }
    return fresh
        .where(
          (item) =>
              _distance.as(LengthUnit.Meter, position, item.position) <=
              radiusMeters,
        )
        .map(
          (item) => RoadReport(
            id: item.id,
            type: item.type,
            position: item.position,
            createdAt: item.createdAt,
          ),
        )
        .toList(growable: false);
  }

  bool _isFresh(QueuedRoadReport item) =>
      DateTime.now().toUtc().difference(item.createdAt) <= item.type.maxAge;

  Future<List<QueuedRoadReport>> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(_queueKey), QueuedRoadReport.fromJson);
  }

  Future<void> _saveQueue(List<QueuedRoadReport> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _queueKey,
      jsonEncode(queue.map((item) => item.toJson()).toList()),
    );
  }

  Future<List<QueuedRoadReport>> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(_localKey), QueuedRoadReport.fromJson);
  }

  Future<void> _saveLocalItems(List<QueuedRoadReport> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _localKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<List<QueuedReportVote>> _loadVotes() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(_votesKey), QueuedReportVote.fromJson);
  }

  Future<void> _saveVotes(List<QueuedReportVote> votes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _votesKey,
      jsonEncode(votes.map((item) => item.toJson()).toList()),
    );
  }

  List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null || raw.isEmpty) return <T>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(fromJson)
          .toList();
    } catch (_) {
      return <T>[];
    }
  }
}
