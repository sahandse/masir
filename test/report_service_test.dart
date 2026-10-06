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
}
