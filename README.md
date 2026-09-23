# مسیر (Masir) — مسیریاب رایگان شبیه Waze

مسیریاب فارسی Flutter با دادهٔ واقعی و رایگان برای کاربر نهایی. هدف: حس و جریان کاری نزدیک به Waze، بدون هزینهٔ اجباری یا قفل پولی.

## وضعیت نسخه
نسخه فعلی پایهٔ **Real Data Only** است. هیچ مقصد، مختصات، ETA، فاصله یا Route نمونه در رابط کاربری نمایش داده نمی‌شود.

## مثل Waze — رایگان
- جستجوی مقصد + میانبر خانه / محل کار / گزارش
- مسیر واقعی + مسیرهای جایگزین با زمان و فاصله
- رانندگی زنده با GPS، HUD، ETA باقیمانده، زمان رسیدن
- دکمهٔ گزارش هنگام رانندگی (ترافیک، تصادف، پلیس، …)
- نمایش گزارش‌ها و توقف‌ها روی نقشه
- راهنمای صوتی فارسی
- تنظیمات مسیر: عوارضی / بزرگراه / فری / زوم / هشدار سرعت

جزئیات شکاف‌ها: [`docs/WAZE_GAP_ANALYSIS.md`](docs/WAZE_GAP_ANALYSIS.md)

## منابع داده
- نقشه: OpenStreetMap
- موقعیت: GPS واقعی دستگاه
- جستجو: Nominatim / OpenStreetMap
- مسیریابی: Valhalla واقعی از `VALHALLA_BASE_URL`
- گزارش: ذخیره محلی (+ `REPORT_API_BASE_URL` اختیاری برای جامعه)
- داده شخصی: فقط داده‌ای که خود کاربر ذخیره کند

## امکانات فعلی
- UI فارسی و RTL
- Light/Dark mode
- OpenStreetMap
- GPS واقعی + Permission handling
- Search واقعی با Nominatim
- Marker مقصد / توقف / گزارش واقعی
- Route واقعی از Valhalla
- Polyline واقعی + انتخاب مسیر جایگزین
- ETA و فاصله واقعی برگشتی از routing engine
- بدون fallback location و بدون fake/demo data

## Android build
GitHub Actions برای ساخت خودکار APK و AAB فعال شده است.

## اجرا
```bash
flutter create --platforms=android --org ir.sahand .
flutter pub get
flutter run --dart-define=VALHALLA_BASE_URL=https://YOUR-PRODUCTION-VALHALLA
```

اختیاری برای اشتراک گزارش بین کاربران:
```bash
--dart-define=REPORT_API_BASE_URL=https://YOUR-REPORT-API
```

## Package
`ir.sahand.masir`

## Roadmap
1. Backend جامعه برای گزارش‌های زنده بین کاربران
2. ترافیک با منبع معتبر و رایگان/خودمیزبان
3. MapLibre vector map + offline regions
4. بهبود rerouting و هشدار رویداد نزدیک مسیر
5. Nearby POI غنی‌تر روی مسیر
