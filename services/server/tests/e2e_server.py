"""Disposable emulator fixture, excluded from the production runtime image."""

import asyncio
import hashlib
import os
import shutil
from collections import deque
from pathlib import Path

from fastapi import Header, HTTPException

from video_viewer.app import create_app
from video_viewer.config import Settings
from video_viewer.file_transfer import rename_new

from .generate_media import generate

FIXTURE_PASSPHRASE = "video-viewer-emulator-fixture-only"
FIXTURE_KEY = "isolated-emulator-control"
BASE = Path("/media")
PORTRAIT = Path("/fixture-assets/flower-portrait.mp4")
LANDSCAPE = Path("/fixture-assets/flower-landscape.mp4")


def create_e2e_app():
    settings = Settings.from_env()
    if os.environ.get("VV_E2E_FIXTURE") != "enabled" or {
        (mount.id, str(mount.path)) for mount in settings.mounts
    } != {("shorts", "/media/shorts"), ("camera", "/media/camera")}:
        raise RuntimeError("This fixture requires the dedicated emulator Compose configuration")
    if settings.passphrase != FIXTURE_PASSPHRASE:
        raise RuntimeError("Unexpected fixture credentials")
    marker = settings.data_dir / "e2e-seeded"
    if not marker.exists():
        for index in range(1, 26):
            destination = BASE / "shorts" / "自然" / "花卉" / f"片段{index:02d}.mp4"
            destination.parent.mkdir(parents=True, exist_ok=True)
            with destination.open("xb") as output, PORTRAIT.open("rb") as source:
                shutil.copyfileobj(source, output)
        (BASE / "shorts" / "空目录").mkdir()
        camera = BASE / "camera" / "旅行"
        camera.mkdir(parents=True)
        shutil.copyfile(LANDSCAPE, camera / "横版片段.mp4")
        samples = generate(Path("/tmp/e2e-formats"))
        shutil.copyfile(samples / "h264.mov", camera / "相机片段.mov")
        marker.write_text("dedicated generated emulator fixture")
    app = create_app(settings)
    trace = deque(maxlen=300)
    checkpoint = {"phase": "ready"}

    @app.middleware("http")
    async def observe(request, call_next):
        if request.url.path.startswith("/api/"):
            trace.append(
                {
                    "method": request.method,
                    "path": request.url.path,
                    "query": dict(request.query_params),
                    "authenticated": bool(request.headers.get("authorization")),
                }
            )
            if request.query_params.get("search") == "片":
                await asyncio.sleep(0.75)
        return await call_next(request)

    def controlled(key):
        if key != FIXTURE_KEY:
            raise HTTPException(status_code=403)

    def copy_new(source, destination):
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            return
        with destination.open("xb") as output, source.open("rb") as original:
            shutil.copyfileobj(original, output)

    @app.get("/__fixture/trace")
    def requests(x_fixture_key: str | None = Header(default=None)):
        controlled(x_fixture_key)
        return {"items": list(trace)}

    @app.get("/__fixture/checkpoint")
    def current_checkpoint(x_fixture_key: str | None = Header(default=None)):
        controlled(x_fixture_key)
        return checkpoint

    @app.post("/__fixture/checkpoint/{phase}")
    def set_checkpoint(phase: str, x_fixture_key: str | None = Header(default=None)):
        controlled(x_fixture_key)
        if phase not in {"ready", "library", "roots", "outage", "recovered", "done"}:
            raise HTTPException(status_code=422)
        checkpoint["phase"] = phase
        return checkpoint

    @app.post("/__fixture/actions/{action}")
    def action(action: str, x_fixture_key: str | None = Header(default=None)):
        controlled(x_fixture_key)
        if action == "reset-login-limit":
            with app.state.login_lock:
                app.state.login_attempts.clear()
        elif action == "add":
            copy_new(PORTRAIT, BASE / "shorts" / "新增" / "新到片段.mp4")
        elif action == "disconnect":
            if (BASE / "camera").exists():
                rename_new(str(BASE / "camera"), str(BASE / "camera-detached"))
        elif action == "reconnect":
            if (BASE / "camera-detached").exists():
                rename_new(str(BASE / "camera-detached"), str(BASE / "camera"))
        elif action == "rename":
            source = BASE / "shorts" / "自然" / "花卉" / "片段01.mp4"
            if source.exists():
                rename_new(str(source), str(BASE / "shorts" / "改名" / "新的名称.mp4"))
        elif action == "duplicate":
            copy_new(PORTRAIT, BASE / "shorts" / "副本" / "重复副本.mp4")
        elif action == "replace":
            target = BASE / "shorts" / "自然" / "花卉" / "片段02.mp4"
            with target.open("wb") as output, LANDSCAPE.open("rb") as source:
                shutil.copyfileobj(source, output)
        elif action == "formats":
            for source in generate(Path("/tmp/e2e-formats")).iterdir():
                copy_new(source, BASE / "camera" / "格式" / source.name)
        else:
            raise HTTPException(status_code=404)
        return {"action": action, "completed": True}

    @app.get("/__fixture/files")
    def files(x_fixture_key: str | None = Header(default=None)):
        controlled(x_fixture_key)
        return {
            "items": [
                {
                    "path": str(path),
                    "size": path.stat().st_size,
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                }
                for path in BASE.rglob("*")
                if path.is_file()
                and path.suffix.lower() in {".mp4", ".mov", ".mkv", ".webm", ".avi"}
            ]
        }

    return app
