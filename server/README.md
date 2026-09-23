# Masir Reports API

Backend خودمیزبان برای گزارش‌های جامعه (ترافیک، تصادف، پلیس، …).

- بدون حساب کاربری
- بدون دادهٔ جعلی
- نگهداری حداکثر ۶ ساعت
- SQLite محلی

## اجرا

```bash
cd server
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 8080
```

## اتصال اپ

```bash
flutter run \
  --dart-define=VALHALLA_BASE_URL=https://YOUR-VALHALLA \
  --dart-define=REPORT_API_BASE_URL=http://YOUR-HOST:8080
```

## API

- `GET /health`
- `POST /reports` — بدنه: `{ "type", "lat", "lon" }`
- `GET /reports?lat=&lon=&radius_m=`
