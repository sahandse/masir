import 'package:masir/core/services/navigation_progress_service.dart';
import 'package:masir/core/services/valhalla_service.dart';

class PersianGuidanceService {
  String instruction(RouteManeuver m) {
    final km = m.kilometers;
    final distance = km >= 1
        ? '${km.toStringAsFixed(km >= 10 ? 0 : 1)} کیلومتر'
        : '${(km * 1000).round()} متر';

    return _instructionFor(m, distance: distance);
  }

  String stagedInstruction(
    RouteManeuver maneuver,
    VoicePromptStage stage, {
    required double distanceMeters,
  }) {
    switch (stage) {
      case VoicePromptStage.far:
        return _instructionFor(
          maneuver,
          distance: 'حدود ۸۰۰ متر',
        );
      case VoicePromptStage.medium:
        return _instructionFor(
          maneuver,
          distance: 'حدود ۳۰۰ متر',
        );
      case VoicePromptStage.near:
        return _instructionFor(
          maneuver,
          distance: 'حدود ۱۰۰ متر',
        );
      case VoicePromptStage.now:
        return _nowInstruction(maneuver);
    }
  }

  String _instructionFor(RouteManeuver m, {required String distance}) {
    switch (m.type) {
      case 1:
        return 'حرکت را آغاز کنید';
      case 2:
        return 'به مسیر خود ادامه دهید';
      case 4:
      case 5:
      case 6:
        return '$distance دیگر به راست بپیچید';
      case 8:
      case 9:
      case 10:
        return '$distance دیگر به چپ بپیچید';
      case 15:
      case 16:
        return '$distance دیگر وارد خروجی سمت راست شوید';
      case 17:
      case 18:
        return '$distance دیگر وارد خروجی سمت چپ شوید';
      case 26:
        return '$distance دیگر وارد میدان شوید';
      case 27:
        return '$distance دیگر از میدان خارج شوید';
      case 31:
        return 'به مقصد رسیدید';
      default:
        return 'برای $distance مسیر را ادامه دهید';
    }
  }

  String _nowInstruction(RouteManeuver m) {
    switch (m.type) {
      case 4:
      case 5:
      case 6:
        return 'اکنون به راست بپیچید';
      case 8:
      case 9:
      case 10:
        return 'اکنون به چپ بپیچید';
      case 15:
      case 16:
        return 'اکنون وارد خروجی سمت راست شوید';
      case 17:
      case 18:
        return 'اکنون وارد خروجی سمت چپ شوید';
      case 26:
        return 'اکنون وارد میدان شوید';
      case 27:
        return 'اکنون از میدان خارج شوید';
      case 31:
        return 'به مقصد رسیدید';
      default:
        return 'مسیر را ادامه دهید';
    }
  }
}
