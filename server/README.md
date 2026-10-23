# سرور گزارش‌های مردمی مسیر

API خودمیزبان و بدون حساب کاربری برای گزارش‌های جاده‌ای مسیر (ترافیک، تصادف، پلیس، دوربین، سرعت‌گیر، مسیر بسته، عملیات جاده‌ای و خطر).

- فقط داده واقعی ذخیره می‌شود؛ هیچ ترافیک یا رویداد ساختگی تولید نمی‌شود.
- هر نوع گزارش عمر مشخص دارد و بعد از آن از پاسخ‌ها حذف می‌شود.
- هر رأی به ازای هر کلاینت (هدر `X-Client-Id` یا IP) یک بار ثبت می‌شود و قابل تغییر است.
- گزارش با ۲ تأیید «تأییدشده» و با ۳ تکذیب پنهان می‌شود.

## اجرا با Docker

```bash
cd server
docker compose up -d --build
```

سرویس روی `http://localhost:8080` بالا می‌آید و دیتابیس SQLite در Volume با نام `reports-data` نگهداری می‌شود.

## اجرای مستقیم

```bash
cd server
python -m venv .venv
source .venv/bin/activate   # ویندوز: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 8080
```

متغیرهای محیطی:

| متغیر | پیش‌فرض | توضیح |
| --- | --- | --- |
| `REPORT_DB_PATH` | `server/data/reports.db` | مسیر فایل SQLite |
| `CORS_ORIGINS` | `*` | لیست مبدأهای مجاز با کاما |

## اتصال اپلیکیشن

آدرس سرور را هنگام Build با `--dart-define` بدهید:

```bash
flutter build apk --release \
  --dart-define=REPORT_API_BASE_URL=https://reports.example.com
```

بدون این مقدار، اپ در «حالت محلی» کار می‌کند: گزارش‌ها روی دستگاه ذخیره می‌شوند، روی نقشه دیده می‌شوند و در صف ارسال می‌مانند.

## API

### `GET /health`

```json
{ "status": "ok", "service": "masir-reports", "types": ["accident", "..."] }
```

### `GET /reports?lat=35.6892&lon=51.3890&radius_m=5000`

لیست گزارش‌های تازه و پنهان‌نشده در شعاع مشخص (حداکثر ۵۰ کیلومتر):

```json
[
  {
    "id": "1730000000000000-a1b2c3",
    "type": "traffic",
    "lat": 35.6892,
    "lon": 51.389,
    "created_at": "2026-10-22T10:15:00Z",
    "expires_at": "2026-10-22T11:00:00Z",
    "confirmations": 3,
    "denies": 0,
    "verified": true
  }
]
```

### `POST /reports`

```json
{
  "id": "1730000000000000-a1b2c3",
  "type": "accident",
  "lat": 35.6892,
  "lon": 51.389,
  "created_at": "2026-10-22T10:15:00Z"
}
```

`id` و `created_at` اختیاری‌اند. ارسال دوباره همان `id` گزارش تکراری نمی‌سازد (Idempotent).

### `POST /reports/{id}/confirm`

### `POST /reports/{id}/deny`

بدنه لازم نیست. برای تفکیک دستگاه‌ها می‌توانید هدر زیر را بفرستید:

```
X-Client-Id: <random-install-id>
```

پاسخ، وضعیت به‌روز گزارش را برمی‌گرداند.

## عمر گزارش‌ها

| نوع | عمر |
| --- | --- |
| `traffic` | ۴۵ دقیقه |
| `police` | ۲ ساعت |
| `accident` | ۳ ساعت |
| `hazard` | ۳ ساعت |
| `camera` | ۲۴ ساعت |
| `speed_bump` | ۲۴ ساعت |
| `closure` | ۲۴ ساعت |
| `roadwork` | ۲۴ ساعت |

## محدودیت‌ها

- احراز هویت ندارد؛ پشت Reverse Proxy با HTTPS و در صورت نیاز Rate Limit لایه شبکه اجرا شود.
- در چند Instance هم‌زمان از یک فایل SQLite استفاده نکنید؛ برای مقیاس بیشتر PostgreSQL لازم است.
- محدودیت نرخ ساده در حافظه است و با ری‌استارت پاک می‌شود.
