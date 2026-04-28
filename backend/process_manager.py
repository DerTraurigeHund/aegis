"""Shell and Docker process management."""
import asyncio
import os
import signal
import subprocess
import json
import logging
from pathlib import Path

import aiofiles

log = logging.getLogger(__name__)

LOGS_DIR = os.path.join(os.path.dirname(__file__), "logs")
os.makedirs(LOGS_DIR, exist_ok=True)


def _log_path(project_id: int) -> str:
    return os.path.join(LOGS_DIR, f"project_{project_id}.log")


# ─── Shell ───

async def start_shell(project_id: int, config: dict) -> int:
    """Start a shell process on the host via nsenter, return PID."""
    command = config.get("command", "")
    cwd = config.get("cwd") or None
    env_raw = config.get("env") or {}
    host_env = {str(k): str(v) for k, v in env_raw.items()}

    log_path = _log_path(project_id)
    log_file = await aiofiles.open(log_path, "a")

    # Build nsenter command to run on the host (PID 1 = host init)
    env_prefix = "".join(f"{k}={v} " for k, v in host_env.items())
    full_command = f"{env_prefix}{command}"

    nsenter_cmd = [
        "nsenter", "--target", "1",
        "--mount", "--uts", "--ipc", "--net", "--pid",
        "--", "/bin/sh", "-c", full_command,
    ]
    if cwd:
        nsenter_cmd = [
            "nsenter", "--target", "1",
            "--mount", "--uts", "--ipc", "--net", "--pid",
            "--", "/bin/sh", "-c", f"cd {cwd} && {full_command}",
        ]

    proc = await asyncio.create_subprocess_exec(
        *nsenter_cmd,
        stdout=log_file,
        stderr=asyncio.subprocess.STDOUT,
        start_new_session=True,
    )

    # Give it a moment to start
    await asyncio.sleep(0.1)

    # The PID we track is the host PID — nsenter's child runs in host namespace
    # We need the actual host PID, not the nsenter wrapper PID
    host_pid = proc.pid  # This is the PID inside the container
    # Since pid:host mode, container PIDs == host PIDs
    log.info("Shell project %d started: pid=%d cmd=%s", project_id, host_pid, command)
    return host_pid


def _pid_exists(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


async def stop_shell(pid: int, timeout: float = 10.0) -> bool:
    """Stop a shell process and its entire process group."""
    if pid is None:
        return True
    try:
        # Kill the entire process group (negative PID)
        os.killpg(os.getpgid(pid), signal.SIGTERM)
    except ProcessLookupError:
        return True
    except PermissionError:
        # Fallback: try killing just the PID
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            return True

    # Wait for process to die
    for _ in range(int(timeout * 10)):
        try:
            os.kill(pid, 0)
            await asyncio.sleep(0.1)
        except ProcessLookupError:
            return True

    # Force kill
    try:
        os.killpg(os.getpgid(pid), signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            return True
    return True


async def is_shell_running(pid: int) -> bool:
    """Check if a shell process is still alive."""
    if pid is None:
        return False
    try:
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, PermissionError):
        return False


async def get_shell_logs(project_id: int, lines: int = 50) -> list[str]:
    """Read last N lines from shell log file."""
    log_path = _log_path(project_id)
    if not os.path.exists(log_path):
        return []
    async with aiofiles.open(log_path, "r") as f:
        content = await f.read()
    all_lines = content.strip().splitlines()
    return all_lines[-lines:]


# ─── Docker ───

def _docker_client():
    import docker
    return docker.from_env()


async def start_docker(project_id: int, config: dict) -> str:
    """Start a Docker container. Returns container ID."""
    container_name = config.get("container_name", "")
    run_command = config.get("run_command", "")
    image = config.get("image", "")

    loop = asyncio.get_event_loop()

    def _sync():
        client = _docker_client()
        # Check if container already exists
        try:
            container = client.containers.get(container_name)
            if container.status != "running":
                container.start()
            return container.id
        except Exception:
            pass

        # Create and run new container
        # Parse run_command into args
        import shlex
        extra_args = shlex.split(run_command) if run_command else []

        # Extract image from run_command if not explicitly set
        if not image and extra_args:
            # Image is typically the last arg
            image = extra_args[-1]
            extra_args = extra_args[:-1]

        container = client.containers.run(
            image or "alpine",
            command=None,
            name=container_name,
            detach=True,
            **_parse_docker_args(extra_args),
        )
        return container.id

    container_id = await loop.run_in_executor(None, _sync)
    log.info("Docker project %d started: container=%s", project_id, container_id)
    return container_id


def _parse_docker_args(args: list[str]) -> dict:
    """Parse common docker run flags into docker-py kwargs."""
    kwargs = {}
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "-p" and i + 1 < len(args):
            ports = kwargs.get("ports", {})
            parts = args[i + 1].split(":")
            if len(parts) == 2:
                ports[f"{parts[1]}/tcp"] = int(parts[0])
            elif len(parts) == 3:
                ports[f"{parts[2]}/tcp"] = (parts[0], int(parts[1]))
            kwargs["ports"] = ports
            i += 2
            continue
        elif arg == "-e" and i + 1 < len(args):
            envs = kwargs.get("environment", {})
            k, _, v = args[i + 1].partition("=")
            envs[k] = v
            kwargs["environment"] = envs
            i += 2
            continue
        elif arg == "-v" and i + 1 < len(args):
            vols = kwargs.get("volumes", {})
            vols[args[i + 1]] = {"bind": args[i + 1].split(":")[1] if ":" in args[i + 1] else args[i + 1], "mode": "rw"}
            kwargs["volumes"] = vols
            i += 2
            continue
        elif arg == "--restart" and i + 1 < len(args):
            kwargs["restart_policy"] = {"Name": args[i + 1]}
            i += 2
            continue
        elif arg == "-d":
            i += 1
            continue
        i += 1
    return kwargs


async def stop_docker(container_id: str, timeout: int = 10) -> bool:
    """Stop a Docker container."""
    if not container_id:
        return True
    loop = asyncio.get_event_loop()

    def _sync():
        try:
            client = _docker_client()
            container = client.containers.get(container_id)
            container.stop(timeout=timeout)
            return True
        except Exception as e:
            log.warning("Failed to stop container %s: %s", container_id, e)
            try:
                container.kill()
                return True
            except Exception:
                return False

    return await loop.run_in_executor(None, _sync)


async def is_docker_running(container_id: str) -> bool:
    """Check if Docker container is running."""
    if not container_id:
        return False
    loop = asyncio.get_event_loop()

    def _sync():
        try:
            client = _docker_client()
            container = client.containers.get(container_id)
            return container.status == "running"
        except Exception:
            return False

    return await loop.run_in_executor(None, _sync)


async def get_docker_logs(container_id: str, lines: int = 50) -> list[str]:
    """Get Docker container logs."""
    if not container_id:
        return []
    loop = asyncio.get_event_loop()

    def _sync():
        try:
            client = _docker_client()
            container = client.containers.get(container_id)
            logs = container.logs(tail=lines).decode("utf-8", errors="replace")
            return logs.strip().splitlines()
        except Exception as e:
            return [f"Error fetching logs: {e}"]

    return await loop.run_in_executor(None, _sync)
