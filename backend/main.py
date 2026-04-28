"""FastAPI application – Distributed Server Monitor Backend (Agent)."""
from contextlib import asynccontextmanager
from datetime import datetime, timezone
import asyncio
import json

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
import os

import database as db
import process_manager as pm
import e2e_middleware
import system_stats as sysstats


# ─── Static file paths ───
WEB_STATIC = {"/style.css", "/app.js"}
STATIC_DIR = os.path.join(os.path.dirname(__file__), "web")


# --- Lifespan ---
@asynccontextmanager
async def lifespan(app: FastAPI):
    await db.init_db()
    # Boot recovery
    import monitor
    await monitor.recover_on_boot()
    # Start background monitor
    monitor_task = asyncio.create_task(monitor.monitor_loop())
    yield
    monitor_task.cancel()


app = FastAPI(title="Server Monitor Agent", version="0.2.0", lifespan=lifespan)
app.add_middleware(e2e_middleware.E2EEncryptionMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serve web frontend
if os.path.isdir(STATIC_DIR):
    app.mount("/web", StaticFiles(directory=STATIC_DIR, html=True), name="web")


@app.get("/")
async def index():
    web_index = os.path.join(STATIC_DIR, "index.html")
    if os.path.exists(web_index):
        return FileResponse(web_index)
    return {"message": "Server Monitor Agent running. Install the web frontend in backend/web/", "docs": "/docs"}


@app.get("/dashboard")
async def dashboard():
    """Alias for the web dashboard."""
    return await index()


@app.get("/style.css")
async def style_css():
    return FileResponse(os.path.join(STATIC_DIR, "style.css"), media_type="text/css")


@app.get("/app.js")
async def app_js():
    return FileResponse(os.path.join(STATIC_DIR, "app.js"), media_type="application/javascript")

# Override starlette BaseHTTPMiddleware HTTPException handling
@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    return JSONResponse(status_code=exc.status_code, content={"success": False, "error": exc.detail})


# --- Auth dependency ---
PUBLIC_PATHS = {"/health", "/docs", "/openapi.json", "/redoc", "/", "/dashboard"} | WEB_STATIC


@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    if request.url.path in PUBLIC_PATHS or request.method == "OPTIONS" or request.url.path.startswith("/web/"):
        return await call_next(request)

    api_key = request.headers.get("X-API-Key")
    if not api_key:
        return JSONResponse(status_code=401, content={"success": False, "error": "Missing X-API-Key header"})

    con = await db.get_db()
    try:
        row = await con.execute_fetchall("SELECT value FROM settings WHERE key = 'api_key'")
        if not row or row[0]["value"] != api_key:
            return JSONResponse(status_code=401, content={"success": False, "error": "Invalid API key"})
    finally:
        await con.close()

    return await call_next(request)


# --- Schemas ---
class ProjectConfig(BaseModel):
    command: Optional[str] = None
    cwd: Optional[str] = None
    env: Optional[dict] = None
    container_name: Optional[str] = None
    run_command: Optional[str] = None
    image: Optional[str] = None


class ProjectCreate(BaseModel):
    name: str
    type: str
    config: ProjectConfig
    max_restarts: int = 3
    restart_reset_minutes: int = 5


class ProjectUpdate(BaseModel):
    name: Optional[str] = None
    config: Optional[ProjectConfig] = None
    max_restarts: Optional[int] = None
    restart_reset_minutes: Optional[int] = None


class DeviceRegister(BaseModel):
    token: str
    platform: str = "android"


class SystemStatsResponse(BaseModel):
    pass  # dynamic, validated via response model


# --- Helpers ---
def row_to_dict(row) -> dict:
    d = dict(row)
    if d.get("config") and isinstance(d["config"], str):
        try:
            d["config"] = json.loads(d["config"])
        except (json.JSONDecodeError, TypeError):
            pass
    return d


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


async def log_event(con, project_id: int, event_type: str, message: str = None):
    await con.execute(
        "INSERT INTO events (project_id, type, message) VALUES (?, ?, ?)",
        (project_id, event_type, message),
    )


# --- Routes ---

@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/projects")
async def list_projects():
    con = await db.get_db()
    try:
        rows = await con.execute_fetchall("SELECT * FROM projects ORDER BY created_at DESC")
        return {"success": True, "data": [row_to_dict(r) for r in rows]}
    finally:
        await con.close()


@app.post("/projects", status_code=201)
async def create_project(body: ProjectCreate):
    con = await db.get_db()
    try:
        cursor = await con.execute(
            """INSERT INTO projects (name, type, config, max_restarts, restart_reset_minutes)
               VALUES (?, ?, ?, ?, ?)""",
            (body.name, body.type, body.config.model_dump_json(), body.max_restarts, body.restart_reset_minutes),
        )
        project_id = cursor.lastrowid
        await log_event(con, project_id, "stop", "Project created")
        await con.commit()
        row = await con.execute_fetchall("SELECT * FROM projects WHERE id = ?", (project_id,))
        return {"success": True, "data": row_to_dict(row[0])}
    finally:
        await con.close()


@app.get("/projects/{project_id}")
async def get_project(project_id: int):
    con = await db.get_db()
    try:
        rows = await con.execute_fetchall("SELECT * FROM projects WHERE id = ?", (project_id,))
        if not rows:
            raise HTTPException(404, "Project not found")
        return {"success": True, "data": row_to_dict(rows[0])}
    finally:
        await con.close()


@app.put("/projects/{project_id}")
async def update_project(project_id: int, body: ProjectUpdate):
    con = await db.get_db()
    try:
        rows = await con.execute_fetchall("SELECT * FROM projects WHERE id = ?", (project_id,))
        if not rows:
            raise HTTPException(404, "Project not found")
        project = row_to_dict(rows[0])
        if project["status"] == "running":
            raise HTTPException(400, "Cannot edit a running project. Stop it first.")

        updates, values = [], []
        if body.name is not None:
            updates.append("name = ?"); values.append(body.name)
        if body.config is not None:
            updates.append("config = ?"); values.append(body.config.model_dump_json())
        if body.max_restarts is not None:
            updates.append("max_restarts = ?"); values.append(body.max_restarts)
        if body.restart_reset_minutes is not None:
            updates.append("restart_reset_minutes = ?"); values.append(body.restart_reset_minutes)

        if not updates:
            return {"success": True, "data": project}

        values.append(project_id)
        await con.execute(f"UPDATE projects SET {', '.join(updates)} WHERE id = ?", values)
        await con.commit()
        rows = await con.execute_fetchall("SELECT * FROM projects WHERE id = ?", (project_id,))
        return {"success": True, "data": row_to_dict(rows[0])}
    finally:
        await con.close()


@app.delete("/projects/{project_id}")
async def delete_project(project_id: int):
    con = await db.get_db()
    try:
        rows = await con.execute_fetchall("SELECT * FROM projects WHERE id = ?", (project_id,))
        if not rows:
            raise HTTPException(404, "Project not found")
        await con.execute("DELETE FROM events WHERE project_id = ?", (project_id,))
        await con.execute("DELETE FROM projects WHERE id = ?", (project_id,))
        await con.commit()
        return {"success": True, "data": None}
    finally:
        await con.close()


@app.get("/projects/{project_id}/events")
async def get_events(project_id: int):
    con = await db.get_db()
    try:
        rows = await con.execute_fetchall(
            "SELECT * FROM events WHERE project_id = ? ORDER BY timestamp DESC LIMIT 100",
            (project_id,),
        )
        return {"success": True, "data": [dict(r) for r in rows]}
    finally:
        await con.close()


# --- Start / Stop / Restart / Logs ---

@app.post("/projects/{project_id}/start")
async def start_project(project_id: int):
    con = await db.get_db()
    try:
        rows = await con.execute_fetchall("SELECT * FROM projects WHERE id = ?", (project_id,))
        if not rows:
            raise HTTPException(404, "Project not found")
        project = row_to_dict(rows[0])
        if project["status"] == "running":
            raise HTTPException(400, "Project is already running")

        now = now_iso()
        if project["type"] == "shell":
            pid = await pm.start_shell(project_id, project["config"])
            await con.execute(
                "UPDATE projects SET status='running', pid=?, last_started_at=?, restart_count=0 WHERE id=?",
                (pid, now, project_id),
            )
        elif project["type"] == "docker":
            container_id = await pm.start_docker(project_id, project["config"])
            await con.execute(
                "UPDATE projects SET status='running', container_id=?, last_started_at=?, restart_count=0 WHERE id=?",
                (container_id, now, project_id),
            )
        else:
            raise HTTPException(400, f"Unknown project type: {project['type']}")

        await log_event(con, project_id, "start", f"Manual start ({project['type']})")
        await con.commit()
        rows = await con.execute_fetchall("SELECT * FROM projects WHERE id = ?", (project_id,))
        return {"success": True, "data": row_to_dict(rows[0])}
    finally:
        await con.close()


@app.post("/projects/{project_id}/stop")
async def stop_project(project_id: int):
    con = await db.get_db()
    try:
        rows = await con.execute_fetchall("SELECT * FROM projects WHERE id = ?", (project_id,))
        if not rows:
            raise HTTPException(404, "Project not found")
        project = row_to_dict(rows[0])
        if project["status"] != "running" and project["status"] != "restarting":
            raise HTTPException(400, f"Project is not running (status: {project['status']})")

        now = now_iso()
        # Calculate uptime delta
        uptime_delta = 0
        if project.get("last_started_at"):
            try:
                from datetime import datetime as dt
                started = dt.fromisoformat(project["last_started_at"])
                uptime_delta = int((dt.now(timezone.utc) - started).total_seconds())
            except Exception:
                pass

        new_uptime = project.get("total_uptime_seconds", 0) + uptime_delta

        if project["type"] == "shell":
            await pm.stop_shell(project["pid"])
            await con.execute(
                "UPDATE projects SET status='stopped', pid=NULL, last_stopped_at=?, total_uptime_seconds=? WHERE id=?",
                (now, new_uptime, project_id),
            )
        elif project["type"] == "docker":
            await pm.stop_docker(project["container_id"])
            await con.execute(
                "UPDATE projects SET status='stopped', last_stopped_at=?, total_uptime_seconds=? WHERE id=?",
                (now, new_uptime, project_id),
            )

        await log_event(con, project_id, "stop", f"Manual stop (uptime +{uptime_delta}s)")
        await con.commit()
        rows = await con.execute_fetchall("SELECT * FROM projects WHERE id = ?", (project_id,))
        return {"success": True, "data": row_to_dict(rows[0])}
    finally:
        await con.close()


@app.post("/projects/{project_id}/restart")
async def restart_project(project_id: int):
    con = await db.get_db()
    try:
        rows = await con.execute_fetchall("SELECT * FROM projects WHERE id = ?", (project_id,))
        if not rows:
            raise HTTPException(404, "Project not found")
        project = row_to_dict(rows[0])
    finally:
        await con.close()

    # Stop if running
    if project["status"] in ("running", "restarting"):
        if project["type"] == "shell":
            await pm.stop_shell(project["pid"])
        elif project["type"] == "docker":
            await pm.stop_docker(project["container_id"])

    await asyncio.sleep(1)

    # Start again
    con = await db.get_db()
    try:
        now = now_iso()
        if project["type"] == "shell":
            pid = await pm.start_shell(project_id, project["config"])
            await con.execute(
                "UPDATE projects SET status='running', pid=?, last_started_at=?, last_stopped_at=?, restart_count=0 WHERE id=?",
                (pid, now, now, project_id),
            )
        elif project["type"] == "docker":
            container_id = await pm.start_docker(project_id, project["config"])
            await con.execute(
                "UPDATE projects SET status='running', container_id=?, last_started_at=?, last_stopped_at=?, restart_count=0 WHERE id=?",
                (container_id, now, now, project_id),
            )
        await log_event(con, project_id, "restart", "Manual restart")
        await con.commit()
        rows = await con.execute_fetchall("SELECT * FROM projects WHERE id = ?", (project_id,))
        return {"success": True, "data": row_to_dict(rows[0])}
    finally:
        await con.close()


@app.get("/projects/{project_id}/logs")
async def get_logs(project_id: int, lines: int = 50):
    con = await db.get_db()
    try:
        rows = await con.execute_fetchall("SELECT * FROM projects WHERE id = ?", (project_id,))
        if not rows:
            raise HTTPException(404, "Project not found")
        project = row_to_dict(rows[0])
    finally:
        await con.close()

    if project["type"] == "shell":
        logs = await pm.get_shell_logs(project_id, lines)
    elif project["type"] == "docker":
        logs = await pm.get_docker_logs(project.get("container_id", ""), lines)
    else:
        logs = []

    return {"success": True, "data": logs}


# --- Stats ---

@app.get("/projects/{project_id}/stats")
async def get_stats(project_id: int):
    con = await db.get_db()
    try:
        rows = await con.execute_fetchall("SELECT * FROM projects WHERE id = ?", (project_id,))
        if not rows:
            raise HTTPException(404, "Project not found")
        project = row_to_dict(rows[0])

        # Total crashes
        crash_rows = await con.execute_fetchall(
            "SELECT COUNT(*) as cnt FROM events WHERE project_id=? AND type='crash'", (project_id,)
        )
        total_crashes = crash_rows[0]["cnt"] if crash_rows else 0

        # Total restarts
        restart_rows = await con.execute_fetchall(
            "SELECT COUNT(*) as cnt FROM events WHERE project_id=? AND type='restart'", (project_id,)
        )
        total_restarts = restart_rows[0]["cnt"] if restart_rows else 0

        # Last crash
        last_crash_rows = await con.execute_fetchall(
            "SELECT timestamp, message FROM events WHERE project_id=? AND type='crash' ORDER BY timestamp DESC LIMIT 1",
            (project_id,)
        )
        last_crash = {"timestamp": last_crash_rows[0]["timestamp"], "message": last_crash_rows[0]["message"]} if last_crash_rows else None

        # Current uptime (if running)
        current_uptime = 0
        if project["status"] == "running" and project.get("last_started_at"):
            try:
                started = datetime.fromisoformat(project["last_started_at"])
                current_uptime = int((datetime.now(timezone.utc) - started).total_seconds())
            except Exception:
                pass

        # Last 7 days: crashes per day
        daily_rows = await con.execute_fetchall(
            """SELECT DATE(timestamp) as day, COUNT(*) as crashes
               FROM events WHERE project_id=? AND type='crash'
               AND timestamp >= datetime('now', '-7 days')
               GROUP BY DATE(timestamp) ORDER BY day""",
            (project_id,)
        )
        daily_crashes = [{"date": r["day"], "crashes": r["crashes"]} for r in daily_rows]

        # Recent events (last 20)
        recent_rows = await con.execute_fetchall(
            "SELECT type, message, timestamp FROM events WHERE project_id=? ORDER BY timestamp DESC LIMIT 20",
            (project_id,)
        )
        recent_events = [dict(r) for r in recent_rows]

        return {
            "success": True,
            "data": {
                "project": {"id": project["id"], "name": project["name"], "type": project["type"], "status": project["status"]},
                "total_uptime_seconds": project["total_uptime_seconds"] + current_uptime,
                "current_uptime_seconds": current_uptime,
                "total_crashes": total_crashes,
                "total_restarts": total_restarts,
                "last_crash": last_crash,
                "daily_crashes_last_7d": daily_crashes,
                "recent_events": recent_events,
            }
        }
    finally:
        await con.close()


# --- System Stats ---

@app.get("/system/stats")
async def get_system_stats():
    """Get current CPU, RAM, Disk, and network statistics."""
    stats = await sysstats.get_system_stats()
    return {"success": True, "data": stats}


# --- Device registration ---

@app.post("/devices/register")
async def register_device(body: DeviceRegister):
    con = await db.get_db()
    try:
        await con.execute(
            "INSERT OR REPLACE INTO push_tokens (token, platform) VALUES (?, ?)",
            (body.token, body.platform),
        )
        await con.commit()
        return {"success": True, "data": None}
    finally:
        await con.close()


@app.post("/devices/unregister")
async def unregister_device(body: DeviceRegister):
    con = await db.get_db()
    try:
        await con.execute("DELETE FROM push_tokens WHERE token = ?", (body.token,))
        await con.commit()
        return {"success": True, "data": None}
    finally:
        await con.close()
