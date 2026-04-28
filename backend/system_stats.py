"""System statistics collection (CPU, RAM, Disk, Network)."""
import asyncio
import logging
from datetime import datetime, timezone
from functools import lru_cache
from typing import Optional

import psutil

log = logging.getLogger(__name__)


async def get_system_stats() -> dict:
    """Collect current system stats asynchronously."""
    loop = asyncio.get_event_loop()

    def _collect() -> dict:
        # CPU
        cpu_percent = psutil.cpu_percent(interval=0.3)
        cpu_count = psutil.cpu_count()
        cpu_count_logical = psutil.cpu_count(logical=True)
        load_avg = [round(x, 2) for x in psutil.getloadavg()] if hasattr(psutil, "getloadavg") else [0.0, 0.0, 0.0]
        cpu_per_core = psutil.cpu_percent(interval=0.1, percpu=True)

        # Memory
        mem = psutil.virtual_memory()
        swap = psutil.swap_memory()

        # Disk
        disks = []
        for part in psutil.disk_partitions():
            try:
                usage = psutil.disk_usage(part.mountpoint)
                disks.append({
                    "device": part.device,
                    "mount_point": part.mountpoint,
                    "fstype": part.fstype,
                    "total": usage.total,
                    "used": usage.used,
                    "free": usage.free,
                    "percent": round(usage.percent, 1),
                })
            except (PermissionError, OSError):
                pass

        # Network I/O
        net = psutil.net_io_counters()
        # Disk I/O
        disk_io = psutil.disk_io_counters()

        # Uptime
        boot_time = datetime.fromtimestamp(psutil.boot_time(), tz=timezone.utc)
        uptime_seconds = int((datetime.now(timezone.utc) - boot_time).total_seconds())

        # Processes
        process_count = len(psutil.pids())

        return {
            "cpu": {
                "percent": round(cpu_percent, 1),
                "core_count": cpu_count,
                "core_count_logical": cpu_count_logical,
                "per_core": [round(p, 1) for p in cpu_per_core],
                "load_average_1m": load_avg[0],
                "load_average_5m": load_avg[1],
                "load_average_15m": load_avg[2],
            },
            "memory": {
                "total": mem.total,
                "available": mem.available,
                "used": mem.used,
                "free": mem.free,
                "percent": round(mem.percent, 1),
                "swap_total": swap.total,
                "swap_used": swap.used,
                "swap_percent": round(swap.percent, 1) if swap.total > 0 else 0.0,
            },
            "disk": disks,
            "network": {
                "bytes_sent": net.bytes_sent,
                "bytes_recv": net.bytes_recv,
                "packets_sent": net.packets_sent,
                "packets_recv": net.packets_recv,
            },
            "disk_io": {
                "read_bytes": disk_io.read_bytes,
                "write_bytes": disk_io.write_bytes,
                "read_count": disk_io.read_count,
                "write_count": disk_io.write_count,
            } if disk_io else None,
            "uptime_seconds": uptime_seconds,
            "process_count": process_count,
            "hostname": _get_hostname(),
            "os": _get_os_info(),
            "collected_at": datetime.now(timezone.utc).isoformat(),
        }

    return await loop.run_in_executor(None, _collect)


@lru_cache(maxsize=1)
def _get_hostname() -> str:
    import socket
    try:
        return socket.gethostname()
    except Exception:
        return "unknown"


@lru_cache(maxsize=1)
def _get_os_info() -> dict:
    import platform
    return {
        "system": platform.system(),
        "release": platform.release(),
        "version": platform.version(),
        "machine": platform.machine(),
    }
