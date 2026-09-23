import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/navigation_progress_service.dart';
import 'package:masir/core/services/valhalla_service.dart';

void main() {
  const service = NavigationProgressService();

  RouteResult route() => const RouteResult(
        points: [
          LatLng(35.7000, 51.4000),
          LatLng(35.7010, 51.4010),
          LatLng(35.7020, 51.4020),
        ],
        seconds: 180,
        kilometers: 1.2,
        maneuvers: [
          RouteManeuver(
            instruction: 'turn right',
            kilometers: 0.5,
            seconds: 60,
            beginShapeIndex: 0,
            endShapeIndex: 1,
            type: 4,
            lanes: [],
          ),
          RouteManeuver(
            instruction: 'continue',
            kilometers: 0.7,
            seconds: 120,
            beginShapeIndex: 1,
            endShapeIndex: 2,
            type: 2,
            lanes: [],
          ),
        ],
      );

  test('detects arrival near destination', () {
    final result = service.calculate(
      current: const LatLng(35.7020, 51.4020),
      destination: const LatLng(35.7020, 51.4020),
      route: route(),
      maneuverIndex: 1,
      now: DateTime(2026, 9, 23, 12),
    );

    expect(result.hasArrived, isTrue);
    expect(result.remainingKilometers, closeTo(0.7, 0.001));
    expect(result.remainingSeconds, closeTo(120, 0.001));
  });

  test('maps voice prompt distances to stages', () {
    expect(service.promptStageForDistance(800), VoicePromptStage.far);
    expect(service.promptStageForDistance(300), VoicePromptStage.medium);
    expect(service.promptStageForDistance(100), VoicePromptStage.near);
    expect(service.promptStageForDistance(20), VoicePromptStage.now);
    expect(service.promptStageForDistance(1200), isNull);
  });

  test('detects large off-route distance', () {
    final shouldReroute = service.shouldReroute(
      current: const LatLng(35.7200, 51.4200),
      route: route(),
    );

    expect(shouldReroute, isTrue);
  });
}
