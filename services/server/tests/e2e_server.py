"""Disposable emulator fixture, excluded from the production runtime image."""

import asyncio
import hashlib
import os
import shutil
import time
from collections import deque
from pathlib import Path

from fastapi import Header, HTTPException
from fastapi.responses import JSONResponse
from sqlalchemy import select

from video_viewer import scanner as scan_module
from video_viewer.app import create_app
from video_viewer.config import Settings
from video_viewer.file_transfer import rename_new
from video_viewer.media import MediaInspectionError
from video_viewer.models import Root, Video

from .generate_media import encode, generate
from .preview_fixture import install as install_preview_fixture
from .workspace_fixture import seed_workspace_packs

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
    controls = {"slow": False, "lose_tag_response": False, "lose_file_response": False,
                "fail_restore": False, "slow_restore": False, "slow_page": False,
                "fail_streams": 0, "busy_covers": 0, "fail_tag_page": False}

    def backup_fault(phase, _task_id):
        if controls["fail_restore"] and phase == "after_replace_before_commit":
            controls["fail_restore"] = False
            raise RuntimeError("Isolated restore rollback fixture")
        if controls["slow_restore"] and phase == "snapshot_written":
            time.sleep(6)

    app = create_app(settings, backup_fault_hook=backup_fault)
    install_preview_fixture(app, BASE, PORTRAIT, FIXTURE_KEY)
    trace = deque(maxlen=300)
    checkpoint = {"phase": "ready"}

    @app.middleware("http")
    async def observe(request, call_next):
        if request.url.path.startswith("/api/"):
            entry = {
                "method": request.method,
                "path": request.url.path,
                "query": dict(request.query_params),
                "authenticated": bool(request.headers.get("authorization")),
                "range": request.headers.get("range"),
            }
            if (request.method == "PATCH" and request.url.path == "/api/v1/video-tags") or (
                request.method == "POST" and request.url.path in {
                    "/api/v1/videos/trash", "/api/v1/trash/restore", "/api/v1/trash/permanent"
                }
            ):
                body = await request.json()
                entry["command_hash"] = hashlib.sha256(
                    str(body.get("request_id")).encode()
                ).hexdigest()
            trace.append(entry)
            if controls["busy_covers"] and request.url.path.endswith("/cover"):
                controls["busy_covers"] -= 1
                entry["status"] = 503
                return JSONResponse({"error": {"code": "image_busy", "message": "Isolated transient cover failure"}}, status_code=503)
            if controls["fail_tag_page"] and request.method == "GET" and request.url.path == "/api/v1/tags" and request.query_params.get("offset") == "50":
                controls["fail_tag_page"] = False
                entry["status"] = 503
                return JSONResponse({"error": {"code": "fixture_tag_page", "message": "Isolated tag page failure"}}, status_code=503)
            if controls["slow_page"] and request.url.path == "/api/v1/videos" and int(request.query_params.get("offset", "0")) > 0:
                await asyncio.sleep(3)
            if controls["fail_streams"] and request.url.path.endswith("/stream"):
                controls["fail_streams"] -= 1
                entry["status"] = 503
                return JSONResponse({"error": {"code": "media_busy", "message": "Isolated transient stream failure"}}, status_code=503)
            if request.query_params.get("search") == "片":
                await asyncio.sleep(0.75)
        response = await call_next(request)
        if (
            controls["lose_tag_response"]
            and request.method == "PATCH"
            and request.url.path == "/api/v1/video-tags"
            and response.status_code == 200
        ):
            controls["lose_tag_response"] = False
            response = JSONResponse(
                {"error": {"code": "fixture_response_lost", "message": "测试连接已中断，请重试"}},
                status_code=503,
            )
        if request.url.path.startswith("/api/"):
            entry["status"] = response.status_code
        if (
            controls["lose_file_response"]
            and request.method == "POST"
            and request.url.path == "/api/v1/videos/trash"
            and response.status_code == 202
        ):
            controls["lose_file_response"] = False
            response = JSONResponse(
                {"error": {"code": "fixture_response_lost", "message": "删除结果待确认，请查询结果"}},
                status_code=503,
            )
            entry["status"] = 503
        if controls["slow"] and request.method == "GET" and request.url.path.endswith("/stream"):
            original = response.body_iterator

            async def throttled():
                async for chunk in original:
                    for start in range(0, len(chunk), 16384):
                        if controls["slow"]:
                            await asyncio.sleep(0.06)
                        yield chunk[start : start + 16384]

            response.body_iterator = throttled()
        return response

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
        if phase not in {
            "ready",
            "library",
            "roots",
            "outage",
            "recovered",
            "done",
            "playback",
            "formats",
            "error",
            "preview",
            "fresh-instance",
            "fresh-done",
            "preparing",
            "loading-more",
            "prepared",
            "workspace-video", "workspace-packs", "workspace-video-tags",
            "workspace-pack-tags", "workspace-settings", "workspace-dark",
            "tag-catalog-retry", "tag-catalog-paged", "tag-catalog-renamed",
        }:
            raise HTTPException(status_code=422)
        checkpoint["phase"] = phase
        return checkpoint

    @app.post("/__fixture/actions/{action}")
    def action(action: str, x_fixture_key: str | None = Header(default=None)):
        controlled(x_fixture_key)
        details = {}
        if action == "reset-login-limit":
            with app.state.login_lock:
                app.state.login_attempts.clear()
        elif action == "workspace-packs":
            details = seed_workspace_packs(BASE, Path("/fixture-assets"))
            controls["busy_covers"] = 2
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
                (BASE / "shorts" / "改名").mkdir(exist_ok=True)
                rename_new(str(source), str(BASE / "shorts" / "改名" / "新的名称.mp4"))
        elif action == "rename-in-place":
            folder = BASE / "shorts" / "自然" / "花卉"
            rename_new(str(folder / "片段04.mp4"), str(folder / "片段04_改名.mp4"))
        elif action == "move-cross":
            source = BASE / "shorts" / "改名" / "新的名称.mp4"
            destination = BASE / "camera" / "移动" / "跨目录片段.mp4"
            destination.parent.mkdir(exist_ok=True)
            rename_new(str(source), str(destination))
        elif action == "return-removed":
            source = BASE / "detached-samples" / "片段03.mp4"
            destination = BASE / "shorts" / "自然" / "花卉" / "片段03.mp4"
            rename_new(str(source), str(destination))
        elif action == "move-many-out":
            sources = sorted(
                p for root in [BASE / "shorts", BASE / "camera"]
                for p in root.rglob("*") if p.is_file() and p.suffix.lower() in {".mp4", ".mov"}
            )[:25]
            if len(sources) != 25:
                raise HTTPException(status_code=409, detail="Expected 25 disposable media files")
            moved = []
            for source in sources:
                destination = BASE / "detached-bulk" / source.relative_to(BASE)
                destination.parent.mkdir(parents=True, exist_ok=True)
                rename_new(str(source), str(destination))
                moved.append({"from": str(source), "to": str(destination)})
            details["moved"] = moved
        elif action == "prepare-library":
            with app.state.db.write() as session:
                for root in session.scalars(select(Root)):
                    root.last_scan = None
                video = session.scalar(select(Video).where(Video.status == 'available').order_by(Video.path).limit(1))
                if video:
                    if video.thumbnail:
                        (settings.data_dir / 'thumbnails' / video.thumbnail).unlink(missing_ok=True)
                    video.thumbnail = None
                    details['warning_video_id'] = video.id
            original_thumbnail = scan_module.make_thumbnail
            def optional_poster_failure(*args):
                scan_module.make_thumbnail = original_thumbnail
                raise MediaInspectionError('thumbnail_timeout')
            scan_module.make_thumbnail = optional_poster_failure
            scanner = app.state.scanner
            original = scanner.check_stop
            deadline = time.monotonic() + 15
            def preparation_check():
                if time.monotonic() < deadline:
                    time.sleep(0.08)
                else:
                    scanner.check_stop = original
                original()
            scanner.check_stop = preparation_check
            scanner.submit()
        elif action == "fail-tag-page":
            controls["fail_tag_page"] = True
        elif action == "slow-pages":
            controls["slow_page"] = True
        elif action == "normal-pages":
            controls["slow_page"] = False
        elif action == "busy-streams":
            controls["fail_streams"] = 4
        elif action in {"fail-next-scan", "slow-next-scan"}:
            scanner = app.state.scanner
            original = scanner.check_stop

            def controlled_check():
                if action == "fail-next-scan":
                    scanner.check_stop = original
                    raise RuntimeError("Isolated fixture scan failure")
                time.sleep(0.2)
                original()

            scanner.check_stop = controlled_check
        elif action == "remove":
            source = BASE / "shorts" / "自然" / "花卉" / "片段03.mp4"
            destination = BASE / "detached-samples" / "片段03.mp4"
            if source.exists():
                destination.parent.mkdir(exist_ok=True)
                rename_new(str(source), str(destination))
        elif action == "slow-streams":
            controls["slow"] = True
        elif action == "normal-streams":
            controls["slow"] = False
        elif action == "lose-tag-response":
            controls["lose_tag_response"] = True
        elif action == "lose-file-response":
            controls["lose_file_response"] = True
        elif action == "fail-next-restore":
            controls["fail_restore"] = True
        elif action == "slow-next-restore":
            controls["slow_restore"] = True
        elif action == "relocate-shorts-root":
            root = BASE / "shorts"
            sources = list(root.iterdir())
            destination = root / "重新映射"
            destination.mkdir()
            for source in sources:
                rename_new(str(source), str(destination / source.name))
            details["mapped_path"] = str(destination)
        elif action in {"lock-flower", "unlock-flower"}:
            (BASE / "shorts" / "自然" / "花卉").chmod(
                0o555 if action == "lock-flower" else 0o755
            )
        elif action == "conflict-first":
            copy_new(LANDSCAPE, BASE / "shorts" / "自然" / "花卉" / "片段01.mp4")
        elif action == "clear-conflict-first":
            target = BASE / "shorts" / "自然" / "花卉" / "片段01.mp4"
            if target.read_bytes() != LANDSCAPE.read_bytes():
                raise HTTPException(status_code=409, detail="Unexpected fixture conflict bytes")
            target.unlink()
        elif action == "seek-sample":
            destination = BASE / "camera" / "长视频" / "拖动验证.mp4"
            if not destination.exists():
                destination.parent.mkdir(exist_ok=True)
                encode(
                    destination,
                    size="320x180",
                    duration=120,
                    extra=("-b:v", "600k", "-pix_fmt", "yuv420p", "-movflags", "+faststart"),
                )
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
        return {"action": action, "completed": True, **details}

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
