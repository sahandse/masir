"""Masir community road-report API.

Self-hosted, free, no user accounts.
Stores real reports only — never fabricates traffic or events.
"""

from __future__ import annotations

import math
import sqlite3
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

DB_PATH = Path(__file__).resolve().parent / "data" / "reports.db"
MAX_AGE_SECONDS = 6 * 60 * 60
ALLOWED_TYPES = {
    "traffic",
    "accident",
    "police",
    "closure",
    "hazard",
    "roadwork",
}

app = FastAPI(
    title="Masir Reports API",
    description="Community road reports for the free Masir navigator",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class ReportIn(BaseModel):
    type: str
    lat: float = Field(..., ge=-90, le=90)
    lon: float = Field(..., ge=-180, le=180)
    id: str | None = None
    created_at: str | None = None


def _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


@contextmanager
def _db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def _init_db() -> None:
    with _db() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS reports (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                lat REAL NOT NULL,
                lon REAL NOT NULL,
                created_at REAL NOT NULL
            )
            """
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_reports_created ON reports(created_at)"
        )


def _purge_old(conn: sqlite3.Connection) -> None:
    cutoff = time.time() - MAX_AGE_SECONDS
    conn.execute("DELETE FROM reports WHERE created_at < ?", (cutoff,))


def _row_to_dict(row: sqlite3.Row) -> dict[str, Any]:
    created = float(row["created_at"])
    return {
        "id": row["id"],
        "type": row["type"],
        "lat": row["lat"],
        "lon": row["lon"],
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(created)),
    }


@app.on_event("startup")
def on_startup() -> None:
    _init_db()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "masir-reports"}


@app.post("/reports")
def create_report(payload: ReportIn) -> dict[str, Any]:
    report_type = payload.type.strip().lower()
    if report_type not in ALLOWED_TYPES:
        raise HTTPException(status_code=400, detail="unsupported report type")

    report_id = (payload.id or "").strip() or str(uuid.uuid4())
    created_at = time.time()
    if payload.created_at:
        try:
            # Accept ISO strings; fall back to now on parse issues.
            from datetime import datetime

            created_at = datetime.fromisoformat(
                payload.created_at.replace("Z", "+00:00")
            ).timestamp()
        except ValueError:
            created_at = time.time()

    with _db() as conn:
        _purge_old(conn)
        conn.execute(
            """
            INSERT OR REPLACE INTO reports (id, type, lat, lon, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (report_id, report_type, payload.lat, payload.lon, created_at),
        )

    return {
        "id": report_id,
        "type": report_type,
        "lat": payload.lat,
        "lon": payload.lon,
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(created_at)),
    }


@app.get("/reports")
def list_reports(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    radius_m: int = Query(8000, ge=100, le=50000),
) -> list[dict[str, Any]]:
    with _db() as conn:
        _purge_old(conn)
        rows = conn.execute(
            "SELECT id, type, lat, lon, created_at FROM reports ORDER BY created_at DESC"
        ).fetchall()

    out: list[dict[str, Any]] = []
    for row in rows:
        if _haversine_m(lat, lon, float(row["lat"]), float(row["lon"])) <= radius_m:
            out.append(_row_to_dict(row))
    return out
