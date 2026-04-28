"""Database initialization and helpers."""
import aiosqlite
import json
import os

DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
os.makedirs(DATA_DIR, exist_ok=True)
DB_PATH = os.path.join(DATA_DIR, "monitor.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS projects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK(type IN ('shell', 'docker')),
    config TEXT NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'stopped' CHECK(status IN ('running','stopped','crashed','restarting','failed')),
    pid INTEGER,
    container_id TEXT,
    max_restarts INTEGER NOT NULL DEFAULT 3,
    restart_count INTEGER NOT NULL DEFAULT 0,
    restart_reset_minutes INTEGER NOT NULL DEFAULT 5,
    last_started_at TEXT,
    last_stopped_at TEXT,
    total_uptime_seconds INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK(type IN ('start','stop','restart','crash','recovered','failed_permanent')),
    message TEXT,
    timestamp TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS push_tokens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    token TEXT NOT NULL UNIQUE,
    platform TEXT NOT NULL DEFAULT 'android',
    registered_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""


async def get_db() -> aiosqlite.Connection:
    db = await aiosqlite.connect(DB_PATH)
    db.row_factory = aiosqlite.Row
    await db.execute("PRAGMA foreign_keys = ON")
    await db.execute("PRAGMA journal_mode = WAL")
    return db


async def init_db():
    db = await get_db()
    try:
        await db.executescript(SCHEMA)
        # Auto-generate API key if not set
        row = await db.execute_fetchall("SELECT value FROM settings WHERE key = 'api_key'")
        if not row:
            import secrets
            api_key = secrets.token_hex(32)
            await db.execute("INSERT INTO settings (key, value) VALUES ('api_key', ?)", (api_key,))
            await db.commit()
            print(f"Generated API key: {api_key}")
    finally:
        await db.close()
