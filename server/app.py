"""Masir community road-report API.

Self-hosted, account-free and real-data-only. Reports expire per type, votes
are deduplicated per client and reports are hidden once enough drivers deny
them.

Run locally:
    pip install -r requirements.txt
    uvicorn app:app --reload --port 8080
"""

from __future__ import annotations

import hashlib
import math
import os
import sqlite3
import time
from contextlib import asynccontextmanager, contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

from fastapi import FastAPI, Header, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator

DB_PATH = Path(
    os.environ.get(
        "REPORT_DB_PATH",
        Path(__file__).resolve().parent / "data" / "reports.db",
    )
)

TYPE_MAX_AGE_SECONDS: dict[str, int] = {
    "traffic": 45 * 60,
    "accident": 3 * 60 * 60,
    "police": 2 * 60 * 60,
    "camera": 24 * 60 * 60,
    "speed_bump": 24 * 60 * 60,
    "closure": 24 * 60 * 60,
    "roadwork": 24 * 60 * 60,
    "hazard": 3 * 60 * 60,
}

VERIFY_CONFIRMATIONS = 2
HIDE_DENIES = 3
DEFAULT_RADIUS_M = 5000
MAX_RADIUS_M = 50000
MAX_REPORTS_PER_QUERY = 200
REPORT_RATE_LIMIT = 10
VOTE_RATE_LIMIT = 40
RATE_WINDOW_SECONDS = 60


class ReportIn(BaseModel):
    id: str | None = Field(default=None, max_length=80)
    type: str
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    created_at: str | None = None

    @field_validator("type")
    @classmethod
    def _known_type(cls, value: str) -> str:
        if value not in TYPE_MAX_AGE_SECONDS:
            raise ValueError(f"unsupported report type: {value}")
        return value


@asynccontextmanager
async def _lifespan(_: FastAPI):
    _init_db()
    yield


app = FastAPI(
    title="Masir Reports API",
    description="Community road reports for the Masir navigator",
    version="2.0.0",
    lifespan=_lifespan,
)

_origins = os.environ.get("CORS_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[origin.strip() for origin in _origins if origin.strip()],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


@contextmanager
def _db() -> Iterator[sqlite3.Connection]:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def _init_db() -> None:
    with _db() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS reports (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                lat REAL NOT NULL,
                lon REAL NOT NULL,
                created_at REAL NOT NULL,
                confirmations INTEGER NOT NULL DEFAULT 0,
                denies INTEGER NOT NULL DEFAULT 0,
                verified INTEGER NOT NULL DEFAULT 0,
                hidden INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS votes (
                report_id TEXT NOT NULL,
                voter TEXT NOT NULL,
                value INTEGER NOT NULL,
                created_at REAL NOT NULL,
                PRIMARY KEY (report_id, voter)
            );
            CREATE INDEX IF NOT EXISTS idx_reports_created
                ON reports(created_at);
            CREATE INDEX IF NOT EXISTS idx_reports_position
                ON reports(lat, lon);
            """
        )
        _purge_expired(conn)


def _purge_expired(conn: sqlite3.Connection) -> None:
    longest = max(TYPE_MAX_AGE_SECONDS.values())
    conn.execute("DELETE FROM reports WHERE created_at < ?", (time.time() - longest,))
    conn.execute(
        "DELETE FROM votes WHERE report_id NOT IN (SELECT id FROM reports)"
    )


def _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * radius * math.asin(math.sqrt(a))


def _parse_created_at(raw: str | None) -> float:
    if not raw:
        return time.time()
    try:
        value = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return time.time()
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    epoch = value.timestamp()
    now = time.time()
    if epoch > now + 600:
        return now
    if epoch < now - 7 * 24 * 60 * 60:
        return now
    return epoch


def _iso_utc(epoch: float) -> str:
    return datetime.fromtimestamp(epoch, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _public(row: sqlite3.Row) -> dict[str, Any]:
    max_age = TYPE_MAX_AGE_SECONDS.get(row["type"], 3 * 60 * 60)
    return {
        "id": row["id"],
        "type": row["type"],
        "lat": row["lat"],
        "lon": row["lon"],
        "created_at": _iso_utc(float(row["created_at"])),
        "expires_at": _iso_utc(float(row["created_at"]) + max_age),
        "confirmations": row["confirmations"],
        "denies": row["denies"],
        "verified": bool(row["verified"]),
    }


_recent_requests: dict[str, list[float]] = {}


def _rate_limit(bucket: str, key: str, limit: int) -> None:
    now = time.time()
    ident = f"{bucket}:{key}"
    entries = [t for t in _recent_requests.get(ident, []) if now - t < RATE_WINDOW_SECONDS]
    if len(entries) >= limit:
        raise HTTPException(status_code=429, detail="Too many requests")
    entries.append(now)
    _recent_requests[ident] = entries
    if len(_recent_requests) > 5000:
        for stale in [
            name
            for name, stamps in _recent_requests.items()
            if not stamps or now - stamps[-1] >= RATE_WINDOW_SECONDS
        ]:
            _recent_requests.pop(stale, None)


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def _voter_key(request: Request, client_id: str | None) -> str:
    raw = (client_id or "").strip() or _client_ip(request)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:32]


def _recount(conn: sqlite3.Connection, report_id: str) -> sqlite3.Row:
    confirmations = conn.execute(
        "SELECT COUNT(*) FROM votes WHERE report_id = ? AND value = 1",
        (report_id,),
    ).fetchone()[0]
    denies = conn.execute(
        "SELECT COUNT(*) FROM votes WHERE report_id = ? AND value = -1",
        (report_id,),
    ).fetchone()[0]
    verified = int(
        confirmations >= VERIFY_CONFIRMATIONS and confirmations > denies
    )
    hidden = int(denies >= HIDE_DENIES and denies > confirmations)
    conn.execute(
        "UPDATE reports SET confirmations = ?, denies = ?, verified = ?, hidden = ? "
        "WHERE id = ?",
        (confirmations, denies, verified, hidden, report_id),
    )
    row = conn.execute("SELECT * FROM reports WHERE id = ?", (report_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Report not found")
    return row


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "service": "masir-reports",
        "types": sorted(TYPE_MAX_AGE_SECONDS),
    }


@app.get("/reports")
def list_reports(
    lat: float = Query(ge=-90, le=90),
    lon: float = Query(ge=-180, le=180),
    radius_m: int = Query(default=DEFAULT_RADIUS_M, ge=50, le=MAX_RADIUS_M),
    limit: int = Query(default=MAX_REPORTS_PER_QUERY, ge=1, le=MAX_REPORTS_PER_QUERY),
) -> list[dict[str, Any]]:
    lat_delta = radius_m / 111320.0
    lon_scale = max(math.cos(math.radians(lat)), 0.01)
    lon_delta = radius_m / (111320.0 * lon_scale)

    with _db() as conn:
        rows = conn.execute(
            """
            SELECT * FROM reports
            WHERE hidden = 0
              AND lat BETWEEN ? AND ?
              AND lon BETWEEN ? AND ?
            ORDER BY created_at DESC
            LIMIT ?
            """,
            (
                lat - lat_delta,
                lat + lat_delta,
                lon - lon_delta,
                lon + lon_delta,
                MAX_REPORTS_PER_QUERY,
            ),
        ).fetchall()

    now = time.time()
    out: list[dict[str, Any]] = []
    for row in rows:
        max_age = TYPE_MAX_AGE_SECONDS.get(row["type"], 3 * 60 * 60)
        if now - float(row["created_at"]) > max_age:
            continue
        if _haversine_m(lat, lon, row["lat"], row["lon"]) > radius_m:
            continue
        out.append(_public(row))
        if len(out) >= limit:
            break
    return out


@app.post("/reports", status_code=201)
def create_report(payload: ReportIn, request: Request) -> dict[str, Any]:
    _rate_limit("report", _client_ip(request), REPORT_RATE_LIMIT)
    now = time.time()
    report_id = (payload.id or "").strip() or hashlib.sha1(
        f"{payload.type}:{payload.lat}:{payload.lon}:{now}".encode("utf-8")
    ).hexdigest()
    created_at = _parse_created_at(payload.created_at)

    with _db() as conn:
        _purge_expired(conn)
        conn.execute(
            """
            INSERT INTO reports (id, type, lat, lon, created_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO NOTHING
            """,
            (report_id, payload.type, payload.lat, payload.lon, created_at),
        )
        row = conn.execute(
            "SELECT * FROM reports WHERE id = ?", (report_id,)
        ).fetchone()

    if row is None:
        raise HTTPException(status_code=500, detail="Could not store report")
    return _public(row)


def _vote(
    report_id: str,
    value: int,
    request: Request,
    client_id: str | None,
) -> dict[str, Any]:
    _rate_limit("vote", _client_ip(request), VOTE_RATE_LIMIT)
    voter = _voter_key(request, client_id)
    now = time.time()

    with _db() as conn:
        exists = conn.execute(
            "SELECT 1 FROM reports WHERE id = ?", (report_id,)
        ).fetchone()
        if exists is None:
            raise HTTPException(status_code=404, detail="Report not found")
        conn.execute(
            """
            INSERT INTO votes (report_id, voter, value, created_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(report_id, voter)
            DO UPDATE SET value = excluded.value, created_at = excluded.created_at
            """,
            (report_id, voter, value, now),
        )
        row = _recount(conn, report_id)

    return _public(row)


@app.post("/reports/{report_id}/confirm")
def confirm_report(
    report_id: str,
    request: Request,
    x_client_id: str | None = Header(default=None),
) -> dict[str, Any]:
    return _vote(report_id, 1, request, x_client_id)


@app.post("/reports/{report_id}/deny")
def deny_report(
    report_id: str,
    request: Request,
    x_client_id: str | None = Header(default=None),
) -> dict[str, Any]:
    return _vote(report_id, -1, request, x_client_id)
