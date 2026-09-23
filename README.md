# مسیر (Masir) — v0.2.0

مسیریاب فارسی Flutter با داده‌های واقعی و بدون Mock/Demo Data.

## وضعیت نسخه
نسخه 0.2.0 پایه‌ی Real Data Only است. هیچ مقصد، مختصات، ETA، فاصله یا Route نمونه در رابط کاربری نمایش داده نمی‌شود.

## منابع داده
- نقشه: OpenStreetMap
- موقعیت: GPS واقعی دستگاه
- جستجو: Nominatim / OpenStreetMap
- مسیریابی: Valhalla واقعی از `VALHALLA_BASE_URL`
- داده شخصی: فقط داده‌ای که خود کاربر ذخیره کند

## امکانات فعلی
- UI فارسی و RTL
- Light/Dark mode
- OpenStreetMap
- GPS واقعی + Permission handling
- Search واقعی با Nominatim
- Marker مقصد واقعی
- Route واقعی از Valhalla
- Polyline واقعی
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

## Package
`ir.sahand.masir`

## Roadmap
1. Alternative Routes واقعی
2. Live Navigation و Turn-by-Turn فارسی
3. GPS stream و rerouting
4. Favorites / Home / Work / History واقعی
5. Nearby POI واقعی
6. گزارش کاربران و backend
7. Traffic با منبع معتبر
8. MapLibre vector map + offline regions
