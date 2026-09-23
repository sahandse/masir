# منابع داده مسیر

## اصل اصلی
تمام داده‌هایی که کاربر در اپ می‌بیند باید واقعی باشند. هیچ Mock، Demo Data، مختصات ساختگی، ETA ساختگی یا مسیر نمونه در UI وجود ندارد.

## استک اصلی
- نقشه و داده جغرافیایی: OpenStreetMap
- رندر فعلی: flutter_map
- رندر پیشنهادی فاز بعد: MapLibre
- موقعیت: GPS واقعی دستگاه
- جستجوی مکان: Nominatim
- مسیریابی: Valhalla
- POI: OSM/Overpass
- گزارش کاربران: ذخیره محلی روی دستگاه + Backend اختیاری (`REPORT_API_BASE_URL`)

## Google Maps Platform
Google Maps Platform سهمیه رایگان ماهانه دارد، اما برای این اپ منبع اصلی نیست. بخش‌های مختلف پس از سقف رایگان Pay-as-you-go هستند و محتوای Google باید مطابق Terms خود Google استفاده شود. بنابراین Google فقط در آینده به‌عنوان integration جداگانه و اختیاری بررسی می‌شود و داده آن با نقشه OSM مخلوط نمی‌شود.

## Production checklist
- [ ] Valhalla اختصاصی
- [ ] Tile/vector tile provider مناسب Production یا self-host
- [ ] Nominatim اختصاصی یا سرویس production-grade
- [ ] rate limit و cache سمت backend
- [ ] مانیتورینگ uptime سرویس‌های نقشه/route/search
- [ ] Privacy Policy و Terms
- [ ] attribution کامل OpenStreetMap و providerها
