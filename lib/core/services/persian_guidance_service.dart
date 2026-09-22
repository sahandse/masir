import 'package:masir/core/services/valhalla_service.dart';

class PersianGuidanceService {
  String instruction(RouteManeuver m) {
    final km = m.kilometers;
    final distance = km >= 1
        ? '${km.toStringAsFixed(km >= 10 ? 0 : 1)} کیلومتر'
        : '${(km * 1000).round()} متر';

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
        return 'وارد میدان شوید و مسیر مشخص‌شده را ادامه دهید';
      case 27:
        return 'از میدان خارج شوید';
      case 31:
        return 'به مقصد رسیدید';
      default:
        return 'برای $distance مسیر را ادامه دهید';
    }
  }
}
