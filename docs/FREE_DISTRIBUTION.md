# مسیر — انتشار تولید

مسیر (Masir) یک مسیریاب فارسی **رایگان و قابل انتشار** است.

## تضمین‌ها
- بدون حساب کاربری اجباری
- بدون تبلیغ داخل صفحهٔ رانندگی
- بدون قفل پولی برای مسیریابی پایه
- بدون وابستگی اجباری به Google Maps Platform
- بدون دادهٔ Demo/جعلی برای ETA یا ترافیک
- امضای release با upload keystore (نه debug)

## بسته‌های انتشار `1.0.0+10`
- `masir-1.0.0-release.apk` — نصب مستقیم / انتشار خارج از فروشگاه
- `masir-1.0.0-release.aab` — Google Play
- package: `ir.sahand.masir`
- امضا: upload keystore اختصاصی پروژه

## الزامات سرور تولید
قبل از ساخت نهایی باید این‌ها تنظیم شوند:
- `VALHALLA_BASE_URL` — سرور Valhalla اختصاصی/تولید (نه instance عمومی آزمایشی)
- اختیاری: `REPORT_API_BASE_URL` برای گزارش جامعه

## GitHub Secrets برای CI
- `MASIR_UPLOAD_KEYSTORE_BASE64`
- `MASIR_KEY_PROPERTIES`
- `VALHALLA_BASE_URL`
