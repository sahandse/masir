import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class ReportService {
  ReportService({Dio? dio}) : _dio = dio ?? Dio();
  final Dio _dio;

  static const _baseUrl = String.fromEnvironment('REPORT_API_BASE_URL');

  bool get isConfigured => _baseUrl.trim().isNotEmpty;

  Future<void> submit({required String type, required LatLng position}) async {
    if (!isConfigured) throw StateError('REPORT_API_BASE_URL is not configured');
    await _dio.post(
      '$_baseUrl/reports',
      data: {
        'type': type,
        'lat': position.latitude,
        'lon': position.longitude,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }
}
