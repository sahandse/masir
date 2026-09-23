# مسیر (Masir) — مسیریاب رایگان شبیه Waze

مسیریاب فارسی Flutter با دادهٔ واقعی. هدف: حس نزدیک به Waze، **کاملاً رایگان** برای کاربر نهایی، بدون Google Maps اجباری و بدون دادهٔ جعلی.

## نسخه 0.8
- Backend خودمیزبان گزارش جامعه (`server/`)
- هشدار رویداد واقعی روی مسیر + پیشنهاد مسیر جایگزین
- صفحه شروع ساده: «کجا می‌روی؟» + خانه/کار
- پرهیز مسیریابی از گزارش‌های واقعی ترافیک/تصادف/بسته بودن
- MapLibre + دانلود منطقه آفلاین
- APK رایگان بدون حساب اجباری و بدون تبلیغ در رانندگی

جزئیات: [`docs/WAZE_GAP_ANALYSIS.md`](docs/WAZE_GAP_ANALYSIS.md) · [`docs/FREE_DISTRIBUTION.md`](docs/FREE_DISTRIBUTION.md)

## منابع داده
- نقشه برداری: MapLibre + OpenFreeMap / OSM
- موقعیت: GPS واقعی دستگاه
- جستجو: Nominatim
- مسیریابی: Valhalla (`VALHALLA_BASE_URL`)
- گزارش: محلی + اختیاری `REPORT_API_BASE_URL`
- ترافیک: فقط از گزارش واقعی کاربران (بدون ترافیک جعلی)

## اجرا — اپ
```bash
flutter create --platforms=android --org ir.sahand .
flutter pub get
flutter run \
  --dart-define=VALHALLA_BASE_URL=https://YOUR-PRODUCTION-VALHALLA \
  --dart-define=REPORT_API_BASE_URL=http://YOUR-HOST:8080
```

## اجرا — سرور گزارش
```bash
cd server
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 8080
```

## Package
`ir.sahand.masir`
