import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:masir/core/services/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('road report type maps API values safely', () {
    expect(RoadReportType.fromApi('accident'), RoadReportType.accident);
    expect(RoadReportType.fromApi('speed_bump'), RoadReportType.speedBump);
    expect(RoadReportType.fromApi('unknown'), isNull);
  });

  test('report is queued when live report backend is not configured', () async {
    final service = ReportService();

    final result = await service.submit(
      type: RoadReportType.hazard,
      position: const LatLng(35.6892, 51.3890),
    );

    expect(result.sent, isFalse);
    expect(result.queued, isTrue);
    expect(await service.pendingCount(), 1);
  });

  test('submitted reports are kept locally and returned as nearby', () async {
    final service = ReportService();
    const position = LatLng(35.6892, 51.3890);

    final result = await service.submit(
      type: RoadReportType.accident,
      position: position,
    );
    final nearby = await service.nearby(position, radiusMeters: 500);
    final ownIds = await service.localReportIds();

    expect(result.reportId, isNotNull);
    expect(nearby.map((report) => report.id), contains(result.reportId));
    expect(ownIds, contains(result.reportId));
    expect(
      await service.nearby(const LatLng(35.7000, 51.4000), radiusMeters: 200),
      isEmpty,
    );
  });

  test('rapid reports get unique identifiers', () async {
    final service = ReportService();
    const position = LatLng(35.6892, 51.3890);

    final first = await service.submit(
      type: RoadReportType.police,
      position: position,
    );
    final second = await service.submit(
      type: RoadReportType.police,
      position: position,
    );

    expect(first.reportId, isNot(second.reportId));
    expect(await service.pendingCount(), 2);
  });

  test('offline votes are queued once per report and can be replaced', () async {
    final service = ReportService();

    final confirm = await service.confirm('report-1');
    expect(confirm.sent, isFalse);
    expect(confirm.queued, isTrue);

    await service.deny('report-1');
    await service.confirm('report-2');

    expect(await service.pendingVotesCount(), 2);
  });

  test('freshness follows the per-type expiry window', () {
    final now = DateTime.now().toUtc();

    final oldTraffic = RoadReport(
      id: 'traffic',
      type: RoadReportType.traffic,
      position: const LatLng(35.6892, 51.3890),
      createdAt: now.subtract(const Duration(minutes: 46)),
    );
    final oldCamera = RoadReport(
      id: 'camera',
      type: RoadReportType.camera,
      position: const LatLng(35.6892, 51.3890),
      createdAt: now.subtract(const Duration(minutes: 46)),
    );

    expect(oldTraffic.isFresh, isFalse);
    expect(oldCamera.isFresh, isTrue);
  });

  test('server payload exposes votes and verification', () {
    final report = RoadReport.fromJson(const {
      'id': 'abc',
      'type': 'speed_bump',
      'lat': 35.6892,
      'lon': 51.3890,
      'created_at': '2026-10-22T10:00:00Z',
      'confirmations': 4,
      'denies': 1,
      'verified': true,
    });

    expect(report.type, RoadReportType.speedBump);
    expect(report.confirmations, 4);
    expect(report.denies, 1);
    expect(report.verified, isTrue);
  });
}
