# مسیر — انتشار تولید

مسیر (Masir) مسیریاب فارسی **رایگان و قابل انتشار** است.

## بسته‌های تولید `1.0.0+10`
- `masir-1.0.0-release.apk` — نصب مستقیم
- `masir-1.0.0-release.aab` — Google Play
- package: `ir.sahand.masir`
- امضا: upload keystore اختصاصی (`CN=Masir`) — **نه debug**

## تضمین‌ها
- بدون حساب کاربری اجباری
- بدون تبلیغ داخل رانندگی
- بدون قفل پولی
- بدون Google Maps اجباری
- بدون دادهٔ Demo/جعلی
- حالت شبیه‌سازی فقط در debug؛ در release نیست

## GitHub Secrets برای CI تولید
- `MASIR_UPLOAD_KEYSTORE_BASE64`
- `MASIR_KEY_PROPERTIES`
- `VALHALLA_BASE_URL` (سرور مسیریابی تولید)
