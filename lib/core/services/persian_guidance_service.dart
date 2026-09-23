import 'package:masir/core/services/navigation_progress_service.dart';
import 'package:masir/core/services/valhalla_service.dart';

class PersianGuidanceService {
  String instruction(RouteManeuver m) {
    final km = m.kilometers;
    final distance = km >= 1
        ? '${km.toStringAsFixed(km >= 10 ? 0 : 1)} کیلومتر'
        : '${(km * 1000).round()} متر';
    return _instructionFor(m, distance: distance, includeStreet: true);
  }

  String stagedInstruction(
    RouteManeuver maneuver,
    VoicePromptStage stage, {
    required double distanceMeters,
    RouteManeuver? nextManeuver,
  }) {
    final current = switch (stage) {
      VoicePromptStage.far => _instructionFor(
          maneuver,
          distance: 'حدود ۸۰۰ متر',
          includeStreet: true,
        ),
      VoicePromptStage.medium => _instructionFor(
          maneuver,
          distance: 'حدود ۳۰۰ متر',
          includeStreet: true,
        ),
      VoicePromptStage.near => _instructionFor(
          maneuver,
          distance: 'حدود ۱۰۰ متر',
          includeStreet: true,
        ),
      VoicePromptStage.now => _nowInstruction(maneuver, includeStreet: true),
    };

    if (nextManeuver == null ||
        (stage != VoicePromptStage.near && stage != VoicePromptStage.now)) {
      return current;
    }

    final next = _nowInstruction(nextManeuver, includeStreet: true)
        .replaceFirst('اکنون ', '')
        .replaceFirst('مسیر را ادامه دهید', 'مسیر را ادامه دهید');
    return '$current. سپس $next';
  }

  String _streetSuffix(RouteManeuver m) {
    final exit = m.exitLabel;
    if (exit?.trim().isNotEmpty == true) return '، $exit';
    final street = m.primaryStreetName;
    if (street?.trim().isNotEmpty == true) return '، وارد $street شوید';
    return '';
  }

  String _instructionFor(
    RouteManeuver m, {
    required String distance,
    required bool includeStreet,
  }) {
    final suffix = includeStreet ? _streetSuffix(m) : '';
    switch (m.type) {
      case 1:
        return 'حرکت را آغاز کنید$suffix';
      case 2:
        return 'به مسیر خود ادامه دهید$suffix';
      case 4:
      case 5:
      case 6:
        return '$distance دیگر به راست بپیچید$suffix';
      case 8:
      case 9:
      case 10:
        return '$distance دیگر به چپ بپیچید$suffix';
      case 15:
      case 16:
        return '$distance دیگر وارد خروجی سمت راست شوید$suffix';
      case 17:
      case 18:
        return '$distance دیگر وارد خروجی سمت چپ شوید$suffix';
      case 26:
        return '$distance دیگر وارد میدان شوید$suffix';
      case 27:
        return '$distance دیگر از میدان خارج شوید$suffix';
      case 31:
        return 'به مقصد رسیدید';
      default:
        return 'برای $distance مسیر را ادامه دهید$suffix';
    }
  }

  String _nowInstruction(RouteManeuver m, {required bool includeStreet}) {
    final suffix = includeStreet ? _streetSuffix(m) : '';
    switch (m.type) {
      case 4:
      case 5:
      case 6:
        return 'اکنون به راست بپیچید$suffix';
      case 8:
      case 9:
      case 10:
        return 'اکنون به چپ بپیچید$suffix';
      case 15:
      case 16:
        return 'اکنون وارد خروجی سمت راست شوید$suffix';
      case 17:
      case 18:
        return 'اکنون وارد خروجی سمت چپ شوید$suffix';
      case 26:
        return 'اکنون وارد میدان شوید$suffix';
      case 27:
        return 'اکنون از میدان خارج شوید$suffix';
      case 31:
        return 'به مقصد رسیدید';
      default:
        return 'مسیر را ادامه دهید$suffix';
    }
  }
}
