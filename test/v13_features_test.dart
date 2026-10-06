import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:masir/core/services/environment_service.dart';
import 'package:masir/core/services/map_feedback_service.dart';
import 'package:masir/core/services/traffic_zone_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('traffic zone detects a point inside the polygon', () {
    final zone = TrafficZone(
      id: 'test',
      name: 'test',
      kind: 'restricted',
      rings: const [
        [
          LatLng(35.0, 51.0),
          LatLng(35.0, 52.0),
          LatLng(36.0, 52.0),
          LatLng(36.0, 51.0),
          LatLng(35.0, 51.0),
        ],
      ],
    );

    expect(zone.contains(const LatLng(35.5, 51.5)), isTrue);
    expect(zone.contains(const LatLng(34.5, 51.5)), isFalse);
  });

  test('AQI label follows standard US AQI breakpoints', () {
    EnvironmentSnapshot snapshot(int aqi) => EnvironmentSnapshot(
          temperatureC: 20,
          apparentTemperatureC: 20,
          windKmh: 5,
          weatherCode: 0,
          usAqi: aqi,
          pm25: 10,
          pm10: 20,
          fetchedAt: DateTime(2026),
        );

    expect(snapshot(40).aqiLabel, 'پاک');
    expect(snapshot(90).aqiLabel, 'قابل قبول');
    expect(snapshot(180).aqiLabel, 'ناسالم');
    expect(snapshot(320).aqiLabel, 'خطرناک');
  });

  test('map feedback is queued without a configured moderation backend', () async {
    final service = MapFeedbackService();
    final sent = await service.submit(
      type: MapFeedbackType.wrongName,
      position: const LatLng(35.6892, 51.3890),
      note: 'نام صحیح',
    );

    expect(sent, isFalse);
    expect(await service.pendingCount(), 1);
  });
}
