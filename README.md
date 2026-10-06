# مسیر (Masir) — v1.2.0

مسیریاب فارسی Flutter با داده‌های واقعی OpenStreetMap و بدون Mock/Demo Data.

## وضعیت نسخه

نسخه فعلی: **1.2.0+13**

- Package: `ir.sahand.masir`
- داده ساختگی برای مقصد، Route، ETA، POI یا راهنمای شهر استفاده نمی‌شود.
- انتشار Android فقط با Tag نسخه انجام می‌شود؛ Push یا Merge به `main` به‌تنهایی Release نمی‌سازد.
- نسخه Release فقط با Keystore ثابت ساخته می‌شود تا روی نسخه قبلی قابل Update باشد.

## منابع داده

- نقشه آنلاین: OpenStreetMap
- نقشه آفلاین: PMTiles ساخته‌شده از OSM / Geofabrik
- موقعیت: GPS واقعی دستگاه
- جستجو: Nominatim / OpenStreetMap + Cache آفلاین داده‌های واقعی دیده‌شده
- POI و راهنمای شهر: OpenStreetMap / Overpass + Cache آفلاین
- مسیریابی: Valhalla
- حالت‌های مسیر: خودرو، پیاده و دوچرخه
- داده شخصی: فقط داده‌ای که خود کاربر روی دستگاه ذخیره کند

## امکانات

- UI فارسی و RTL
- Light / Dark mode
- Driver Mode و Navigation Banner
- Lane Guidance در صورت وجود داده Valhalla
- نام خیابان و خروجی بعدی
- ETA، فاصله و زمان باقی‌مانده زنده
- Voice Guidance فارسی چندمرحله‌ای
- Re-route و تشخیص رسیدن به مقصد
- سرعت، محدودیت سرعت و دوربین ثبت‌شده در OSM
- مسیر خودرو / پیاده / دوچرخه
- Alternative Routes
- Favorites / Home / Work / History
- POI واقعی: پمپ‌بنزین، پارکینگ، بیمارستان، درمانگاه، داروخانه، رستوران، کافه، ATM، فروشگاه و...
- راهنمای شهر: دیدنی‌ها، غذا، اقامت، خدمات و خرید
- جستجوی آفلاین روی مکان‌های واقعی قبلاً ذخیره‌شده
- POI و راهنمای شهر با fallback آفلاین
- مدیر نقشه آفلاین: دانلود، Progress، SHA-256، فعال‌سازی، بروزرسانی و حذف
- رندر مستقیم PMTiles از حافظه دستگاه
- برگشت سریع بین نقشه آنلاین و آفلاین

## نقشه آفلاین

Catalog پیش‌فرض:

`https://raw.githubusercontent.com/sahandse/masir/main/offline_maps/catalog.json`

بسته‌ها با Workflow زیر از داده واقعی OSM ساخته می‌شوند:

`.github/workflows/offline-map-build.yml`

این Workflow به‌صورت دستی اجرا می‌شود و Android App را منتشر نمی‌کند.

## Android CI

روی Pull Request و Push به `main`:

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- Compile APK Release برای اطمینان از سالم بودن Build

## Android Release

Release فقط با Tagهایی مثل `v1.2.0` انجام می‌شود.

Secrets موردنیاز:

- `MASIR_KEYSTORE_BASE64`
- `MASIR_KEYSTORE_PASSWORD`
- `MASIR_KEY_ALIAS`
- `MASIR_KEY_PASSWORD`

بدون این Secrets، Release متوقف می‌شود تا APK با کلید موقت منتشر نشود.

## اجرا

```bash
flutter create --no-pub --platforms=android --org ir.sahand .
flutter pub get
flutter run \
  --dart-define=VALHALLA_BASE_URL=https://YOUR-PRODUCTION-VALHALLA \
  --dart-define=MASIR_OFFLINE_CATALOG_URL=https://YOUR-CATALOG/catalog.json
```

## Attribution

- © OpenStreetMap contributors
- معماری Offline و تجربه سفر از Organic Maps الهام گرفته شده است.
- فایل‌های رسمی Organic Maps به‌عنوان White-label بازتوزیع نمی‌شوند.
