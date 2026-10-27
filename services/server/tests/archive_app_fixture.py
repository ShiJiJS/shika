"""Opt-in isolated Android archive fixture; never used by production startup."""

import asyncio
import os
import threading
import uuid
from collections import deque
from pathlib import Path

from fastapi import Header, HTTPException
from PIL import Image

from video_viewer.app import create_app
from video_viewer.authority import Authority
from video_viewer.config import Settings
from video_viewer.models import RequestRecord, Task


def create_archive_app():
    settings = Settings.from_env()
    if (
        os.environ.get("VV_ARCHIVE_APP_FIXTURE") != "enabled"
        or settings.passphrase != "archive-app-isolated-only"
        or {str(m.path) for m in settings.mounts} != {"/media/videos", "/media/packs"}
    ):
        raise RuntimeError("Requires dedicated archive App fixture configuration")
    image = Path("/media/packs/示例图包/001.png")
    image.parent.mkdir(parents=True, exist_ok=True)
    if not image.exists():
        Image.new("RGB", (320, 480), "#b8a47c").save(image)
        image.with_name("保留附件.txt").write_text("isolated fixture attachment")
    for n in range(25):
        Path(f"/media/videos/目录{n:02d}").mkdir(parents=True, exist_ok=True)
    lock = threading.Lock()
    phase_gate, response_gate = threading.Event(), threading.Event()
    phase_gate.set()
    response_gate.set()
    controls = {
        "armed": None,
        "hit": None,
        "task_id": None,
        "request_id": None,
        "response_held": False,
        "display": None,
        "display_ack": False,
        "large_seeded": False,
    }

    def backup_fault(phase, task_id):
        with lock:
            if controls["armed"] != phase:
                return
            controls.update(hit=phase, task_id=task_id)
        if not phase_gate.wait(120):
            raise RuntimeError("Archive restart fixture gate timed out")

    app = create_app(settings, backup_fault_hook=backup_fault)
    trace = deque(maxlen=20000)

    def guard(key):
        if key != "archive-app-isolated-control":
            raise HTTPException(403)

    @app.middleware("http")
    async def fixture_only(request, call_next):
        trace_entry = None
        if request.url.path.startswith("/api/"):
            trace_entry = {
                "method": request.method,
                "path": request.url.path,
                "query": dict(request.query_params),
                "epoch": request.headers.get("X-Management-Epoch"),
            }
            if request.method == "POST" and request.url.path.startswith(
                "/api/v1/management-backups"
            ):
                if request.url.path.endswith("/imports"):
                    trace_entry["idempotency_key"] = request.headers.get("Idempotency-Key")
                elif (
                    request.url.path
                    in {"/api/v1/management-backups", "/api/v1/management-backups/restores"}
                    or "/from-snapshot/" in request.url.path
                ):
                    trace_entry["body"] = await request.json()
            trace.append(trace_entry)
        restoring = (
            request.method == "POST" and request.url.path == "/api/v1/management-backups/restores"
        )
        if restoring:
            payload = await request.json()
            with lock:
                if controls["armed"]:
                    controls["request_id"] = payload.get("request_id")
        response = await call_next(request)
        if restoring and response.status_code == 202:
            with lock:
                held = controls["armed"] is not None
                controls["response_held"] = held
            if held and not await asyncio.to_thread(response_gate.wait, 120):
                raise RuntimeError("Archive restart response gate timed out")
        return response

    @app.get("/__archive_fixture/trace")
    def events(x_fixture_key: str = Header()):
        guard(x_fixture_key)
        return {"items": list(trace)}

    @app.post("/__archive_fixture/seed-large")
    def seed_large(x_fixture_key: str = Header()):
        guard(x_fixture_key)
        if os.environ.get("VV_ARCHIVE_NATIVE_LARGE") != "enabled" or settings.data_dir != Path(
            "/data"
        ):
            raise HTTPException(404)
        with lock:
            if controls["large_seeded"]:
                raise HTTPException(409)
            with app.state.db.write() as session:
                for start in range(0, 18000, 100):
                    session.execute(
                        Task.__table__.insert(),
                        [
                            {
                                "id": str(uuid.uuid4()),
                                "kind": "scan",
                                "status": "completed",
                                "phase": "completed",
                                "result": {"note": "x" * 2048},
                            }
                            for _ in range(start, start + 100)
                        ],
                    )
            controls["large_seeded"] = True
        return {"task_rows": 18000, "note_bytes_each": 2048}

    @app.post("/__archive_fixture/arm/{phase}")
    def arm(phase: str, x_fixture_key: str = Header()):
        guard(x_fixture_key)
        if phase not in {"snapshot_written", "after_replace_before_commit", "restore_committed"}:
            raise HTTPException(422)
        with lock:
            if controls["armed"]:
                raise HTTPException(409)
            controls.update(
                armed=phase,
                hit=None,
                task_id=None,
                request_id=None,
                response_held=False,
                display=None,
                display_ack=False,
            )
            phase_gate.clear()
            response_gate.clear()
        return {"armed": phase}

    @app.post("/__archive_fixture/release")
    def release(x_fixture_key: str = Header()):
        guard(x_fixture_key)
        with lock:
            controls["armed"] = None
        phase_gate.set()
        response_gate.set()
        return {"released": True}

    @app.get("/__archive_fixture/status")
    def status(x_fixture_key: str = Header()):
        guard(x_fixture_key)
        with lock:
            result = dict(controls)
        with app.state.db.read() as session:
            result["epoch"] = Authority.current(session)
            record = (
                session.get(RequestRecord, "management.restore:" + result["request_id"])
                if result["request_id"]
                else None
            )
            result["original_task_id"] = record.result["id"] if record else None
            row = session.get(Task, result["task_id"]) if result["task_id"] else None
            result["task"] = (
                {
                    "id": row.id,
                    "kind": row.kind,
                    "status": row.status,
                    "phase": row.phase,
                    "result": row.result,
                    "error": row.error,
                }
                if row
                else None
            )
        return result

    @app.post("/__archive_fixture/checkpoint/{name}")
    def checkpoint(name: str, x_fixture_key: str = Header()):
        guard(x_fixture_key)
        with lock:
            controls.update(display=name, display_ack=False)
        return {"display": name}

    @app.post("/__archive_fixture/ack/{name}")
    def ack(name: str, x_fixture_key: str = Header()):
        guard(x_fixture_key)
        with lock:
            if controls["display"] != name:
                raise HTTPException(409)
            controls["display_ack"] = True
        return {"acknowledged": name}

    return app
