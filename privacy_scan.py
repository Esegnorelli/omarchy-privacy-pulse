#!/usr/bin/env python3
"""Privacy Pulse scanner for Omarchy.

Reports processes currently using the microphone, camera, or a screen capture
stream. Output is a single JSON object on stdout.

No network calls. Read-only inspection of PipeWire (pw-dump) and /proc fd links.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

SKIP_COMMS = {
    "pipewire",
    "wireplumber",
    "pipewire-pulse",
    "privacy_scan.py",
    "python3",
    "python",
    "pw-dump",
    "fuser",
    "lsof",
}

SKIP_APPS = {
    "pipewire",
    "wireplumber",
    "pipewire-pulse",
    "Dummy-Driver",
    "Freewheel-Driver",
    "Midi-Bridge",
}


def _read_text(path: Path) -> str:
    try:
        return path.read_text(errors="replace").strip()
    except Exception:
        return ""


def _exe_name(pid: int) -> str:
    try:
        return Path(os.readlink(f"/proc/{pid}/exe")).name
    except Exception:
        return _read_text(Path(f"/proc/{pid}/comm")) or f"pid:{pid}"


def _comm(pid: int) -> str:
    return _read_text(Path(f"/proc/{pid}/comm")) or f"pid:{pid}"


def _cmdline(pid: int) -> str:
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    except Exception:
        return ""
    return raw.replace(b"\x00", b" ").decode("utf-8", "replace").strip()[:160]


def _display_name(app: str, binary: str = "", comm: str = "") -> str:
    for candidate in (app, binary, comm):
        value = (candidate or "").strip()
        if value and value not in SKIP_APPS:
            return value
    return app or binary or comm or "unknown"


def scan_camera() -> list[dict]:
    hits: dict[tuple[str, str], dict] = {}
    try:
        pids = [int(p) for p in os.listdir("/proc") if p.isdigit()]
    except Exception:
        return []

    for pid in pids:
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except Exception:
            continue

        devices: set[str] = set()
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except Exception:
                continue
            if target.startswith("/dev/video"):
                devices.add(target)

        if not devices:
            continue

        comm = _comm(pid)
        exe = _exe_name(pid)
        if comm in SKIP_COMMS or exe in SKIP_COMMS:
            continue

        app = _display_name(exe, comm=comm)
        key = (app.lower(), ",".join(sorted(devices)))
        hits[key] = {
            "kind": "camera",
            "app": app,
            "detail": ", ".join(sorted(devices)),
            "pid": pid,
            "source": "v4l2",
        }
    return list(hits.values())


def _looks_like_screen(props: dict, media_class: str) -> bool:
    blob = " ".join(
        str(props.get(k, ""))
        for k in (
            "media.role",
            "media.name",
            "media.category",
            "node.name",
            "node.description",
            "application.name",
            "window.title",
        )
    ).lower()
    role = str(props.get("media.role", "")).lower()
    if role in {"screen", "monitor", "screencast"}:
        return True
    if any(token in blob for token in ("screencast", "screen share", "screen-share", "xdg-desktop-portal")):
        # portal client alone is not enough; require stream-ish class
        if "stream" in media_class.lower() or "input" in media_class.lower():
            return True
    if "screen" in blob and ("stream/input" in media_class.lower() or "video" in media_class.lower()):
        return True
    return False


def scan_pipewire() -> tuple[list[dict], list[dict], list[dict]]:
    mics: list[dict] = []
    screens: list[dict] = []
    cams_pw: list[dict] = []

    try:
        dump = subprocess.check_output(
            ["pw-dump"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=4,
        )
        data = json.loads(dump)
    except Exception:
        return mics, screens, cams_pw

    for obj in data:
        if not str(obj.get("type", "")).endswith("Node"):
            continue

        info = obj.get("info") or {}
        props = info.get("props") or {}
        media_class = str(props.get("media.class") or "")
        state = str(info.get("state") or "")
        app = str(props.get("application.name") or props.get("node.name") or "unknown")
        binary = str(props.get("application.process.binary") or "")
        if app in SKIP_APPS or binary in SKIP_APPS:
            continue

        pid_raw = props.get("application.process.id")
        try:
            pid = int(pid_raw) if pid_raw is not None else None
        except Exception:
            pid = None

        media_name = str(props.get("media.name") or "")
        role = str(props.get("media.role") or "")
        detail_parts = [p for p in (media_name, role, media_class) if p]
        detail = " · ".join(detail_parts) if detail_parts else media_class or state
        entry = {
            "app": _display_name(app, binary=binary),
            "detail": detail,
            "pid": pid,
            "state": state,
            "source": "pipewire",
        }

        active_enough = state in {"running", "creating"} or str(props.get("stream.is-live")).lower() in {
            "true",
            "1",
        }

        if media_class == "Stream/Input/Audio" and active_enough:
            item = dict(entry)
            item["kind"] = "mic"
            mics.append(item)
            continue

        if _looks_like_screen(props, media_class) and active_enough:
            item = dict(entry)
            item["kind"] = "screen"
            screens.append(item)
            continue

        # App-side camera consumers via PipeWire (not the V4L2 source node itself)
        if media_class == "Stream/Input/Video" and active_enough and not _looks_like_screen(props, media_class):
            if "v4l2" in str(props.get("node.name", "")).lower():
                continue
            item = dict(entry)
            item["kind"] = "camera"
            item["source"] = "pipewire-video"
            cams_pw.append(item)

    return mics, screens, cams_pw


def _dedupe(items: list[dict]) -> list[dict]:
    seen: set[tuple] = set()
    out: list[dict] = []
    for item in items:
        key = (
            item.get("kind"),
            str(item.get("app", "")).lower(),
            str(item.get("detail", "")),
            item.get("pid"),
        )
        if key in seen:
            continue
        seen.add(key)
        out.append(item)
    out.sort(key=lambda x: (str(x.get("app", "")).lower(), str(x.get("detail", ""))))
    return out


def main() -> int:
    camera = scan_camera()
    mics, screens, cams_pw = scan_pipewire()
    camera = _dedupe(camera + cams_pw)
    mics = _dedupe(mics)
    screens = _dedupe(screens)

    payload = {
        "ok": True,
        "mic": mics,
        "camera": camera,
        "screen": screens,
        "counts": {
            "mic": len(mics),
            "camera": len(camera),
            "screen": len(screens),
            "total": len(mics) + len(camera) + len(screens),
        },
        "active": bool(mics or camera or screens),
    }
    json.dump(payload, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        raise SystemExit(0)
