"""Background monitoring loop — crash detection, auto-restart, push notifications."""
import asyncio
import logging
import os
from datetime import datetime, timezone
from pathlib import Path

import database as db
import process_manager as pm

log = logging.getLogger(__name__)

CHECK_INTERVAL = int(os.getenv("CHECK_INTERVAL_SECONDS", "30"))


async def monitor_loop():
    """Main monitoring loop — runs every CHECK_INTERVAL seconds."""
    while True:
        try:
            await _check_all_projects()
        except Exception as e:
            log.error("Monitor loop error: %s", e)
        await asyncio.sleep(CHECK_INTERVAL)


async def _check_all_projects():
    con = await db.get_db()
    try:
        rows = await con.execute_fetchall("SELECT * FROM projects")
        for row in rows:
            project = _row_to_dict(row)
            try:
                await _check_project(con, project)
            except Exception as e:
                log.error("Error checking project %d (%s): %s", project["id"], project["name"], e)
        await con.commit()
    finally:
        await con.close()


async def _check_project(con, project: dict):
    project_id = project["id"]
    ptype = project["type"]
    status = project["status"]

    # Determine if actually running
    if ptype == "shell":
        actually_running = await pm.is_shell_running(project.get("pid"))
    elif ptype == "docker":
        actually_running = await pm.is_docker_running(project.get("container_id") or "")
    else:
        return

    now = now_iso()

    # ─── Reset logic (if running and healthy) ───
    if actually_running and status == "running":
        reset_minutes = project.get("restart_reset_minutes", 5) or 5
        last_started = project.get("last_started_at")
        if last_started:
            try:
                started = datetime.fromisoformat(last_started)
                elapsed_minutes = (datetime.now(timezone.utc) - started).total_seconds() / 60
                if elapsed_minutes >= reset_minutes and project.get("restart_count", 0) > 0:
                    log.info("Project %d running stable for %.0f min — resetting restart_count", project_id, elapsed_minutes)
                    await con.execute("UPDATE projects SET restart_count = 0 WHERE id = ?", (project_id,))
            except Exception:
                pass
        return  # Healthy, nothing to do

    # ─── Crash detection ───
    if not actually_running and status == "running":
        log.warning("Project %d (%s) crashed!", project_id, project["name"])

        # Calculate uptime delta
        uptime_delta = 0
        if project.get("last_started_at"):
            try:
                started = datetime.fromisoformat(project["last_started_at"])
                uptime_delta = max(0, int((datetime.now(timezone.utc) - started).total_seconds()))
            except Exception:
                pass

        new_uptime = project.get("total_uptime_seconds", 0) + uptime_delta
        restart_count = (project.get("restart_count") or 0)
        max_restarts = project.get("max_restarts", 3)

        await con.execute(
            "UPDATE projects SET status='crashed', pid=NULL, last_stopped_at=?, total_uptime_seconds=? WHERE id=?",
            (now, new_uptime, project_id),
        )
        await _log_event(con, project_id, "crash", f"Process died unexpectedly (uptime +{uptime_delta}s)")

        # ─── Auto-heal ───
        if restart_count < max_restarts:
            restart_count += 1
            log.info("Auto-restarting project %d (attempt %d/%d)", project_id, restart_count, max_restarts)

            await con.execute(
                "UPDATE projects SET status='restarting', restart_count=? WHERE id=?",
                (restart_count, project_id),
            )
            await _log_event(con, project_id, "restart", f"Auto-restart attempt {restart_count}/{max_restarts}")

            # Actually start
            try:
                if ptype == "shell":
                    pid = await pm.start_shell(project_id, project["config"])
                    await con.execute(
                        "UPDATE projects SET status='running', pid=?, last_started_at=? WHERE id=?",
                        (pid, now_iso(), project_id),
                    )
                elif ptype == "docker":
                    container_id = await pm.start_docker(project_id, project["config"])
                    await con.execute(
                        "UPDATE projects SET status='running', container_id=?, last_started_at=? WHERE id=?",
                        (container_id, now_iso(), project_id),
                    )
                await _log_event(con, project_id, "recovered", f"Recovered after {restart_count} attempt(s)")
            except Exception as e:
                log.error("Auto-restart failed for project %d: %s", project_id, e)
                await con.execute("UPDATE projects SET status='crashed' WHERE id=?", (project_id,))
                await _log_event(con, project_id, "crash", f"Auto-restart failed: {e}")
        else:
            # Permanent failure
            log.error("Project %d permanently failed after %d restarts", project_id, max_restarts)
            await con.execute("UPDATE projects SET status='failed' WHERE id=?", (project_id,))
            await _log_event(con, project_id, "failed_permanent", f"Failed after {max_restarts} restart attempts")

            # Send push notification
            await _send_failure_push(con, project)

    # ─── Restarting but died again ───
    elif not actually_running and status == "restarting":
        # Already being handled by the crash logic above on next tick
        pass


async def recover_on_boot():
    """Called at backend startup — reconcile DB state with actual processes."""
    log.info("Boot recovery: checking all projects marked as running...")
    con = await db.get_db()
    try:
        rows = await con.execute_fetchall("SELECT * FROM projects WHERE status IN ('running', 'restarting')")
        recovered = 0
        crashed = 0
        for row in rows:
            project = _row_to_dict(row)
            project_id = project["id"]

            if project["type"] == "shell":
                alive = await pm.is_shell_running(project.get("pid"))
            elif project["type"] == "docker":
                alive = await pm.is_docker_running(project.get("container_id") or "")
            else:
                continue

            if alive:
                log.info("Project %d (%s) still running — OK", project_id, project["name"])
                recovered += 1
            else:
                log.warning("Project %d (%s) died while backend was down — marking crashed", project_id, project["name"])
                now = now_iso()
                await con.execute(
                    "UPDATE projects SET status='crashed', pid=NULL, last_stopped_at=? WHERE id=?",
                    (now, project_id),
                )
                await _log_event(con, project_id, "crash", "Process died while backend was offline")
                crashed += 1

        await con.commit()
        log.info("Boot recovery done: %d alive, %d crashed", recovered, crashed)
    finally:
        await con.close()


async def _send_failure_push(con, project: dict):
    """Send push notification for permanent failure."""
    try:
        rows = await con.execute_fetchall("SELECT token FROM push_tokens")
        if not rows:
            log.info("No push tokens registered — skipping notification")
            return

        # Import FCM sender (Phase 4 will flesh this out)
        fcm_path = await _get_setting(con, "fcm_service_account_path")
        if not fcm_path or not os.path.exists(fcm_path):
            log.warning("FCM not configured — cannot send push for project %d", project["id"])
            return

        from firebase_admin import messaging as fcm_messaging

        tokens = [r["token"] for r in rows]
        title = f"⚠️ {project['name']} failed"
        body = f"After {project['max_restarts']} attempts the service could not be started."

        for token in tokens:
            try:
                message = fcm_messaging.Message(
                    notification=fcm_messaging.Notification(title=title, body=body),
                    token=token,
                )
                fcm_messaging.send(message)
            except Exception as e:
                if "NotRegistered" in str(e):
                    await con.execute("DELETE FROM push_tokens WHERE token = ?", (token,))
                    log.info("Removed invalid push token")
                else:
                    log.error("Push send error: %s", e)

        await con.commit()
    except ImportError:
        log.info("firebase_admin not installed — skipping push")
    except Exception as e:
        log.error("Push notification error: %s", e)


async def _get_setting(con, key: str) -> str | None:
    rows = await con.execute_fetchall("SELECT value FROM settings WHERE key = ?", (key,))
    return rows[0]["value"] if rows else None


def _row_to_dict(row) -> dict:
    import json
    d = dict(row)
    if d.get("config") and isinstance(d["config"], str):
        try:
            d["config"] = json.loads(d["config"])
        except Exception:
            pass
    return d


async def _log_event(con, project_id: int, event_type: str, message: str = None):
    await con.execute(
        "INSERT INTO events (project_id, type, message) VALUES (?, ?, ?)",
        (project_id, event_type, message),
    )


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()
