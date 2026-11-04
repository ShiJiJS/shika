"""Opt-in original purge history App fixture, separate from 8760/8761/8762."""

import errno
import json
import os
import threading
from collections import deque
from contextlib import asynccontextmanager
from dataclasses import replace
from pathlib import Path

from fastapi import Header, HTTPException
from fastapi.responses import JSONResponse
from PIL import Image

from shika.app import create_app
from shika.authority import Authority
from shika.config import Settings
from shika.models import PackPurgeStep


def create_history_app():
    settings = replace(Settings.from_env(), startup_scan=False)
    if (
        os.environ.get("VV_HISTORY_APP_FIXTURE") != "enabled"
        or settings.passphrase != "history-purge-isolated-only"
        or str(settings.data_dir) != "/data"
        or {str(m.path) for m in settings.mounts} != {"/media/videos", "/media/packs"}
    ):
        raise RuntimeError("Requires dedicated purge history fixture mounts and passphrase")
    settings.data_dir.mkdir(parents=True, exist_ok=True)
    generated = settings.data_dir / "history-fixture-generated"
    if not generated.exists():
        for n in range(27):
            base = Path("/media/packs") / f"原图包 {n:02d}"
            base.mkdir(parents=True, exist_ok=True)
            for i in range(127 if n == 0 else 1):
                Image.new("RGB", (32, 48), "#a8b790").save(base / f"{i + 1:04d}.png")
            (base / "保留附件.txt").write_text("isolated history fixture attachment")
            (base / "空目录").mkdir(exist_ok=True)
        generated.write_text("27 packs, 153 images; never recreate after purging")
    app = create_app(settings)
    trace = deque(maxlen=20000)
    lock = threading.Lock()
    state = {"display": None, "display_ack": False, "fail_next": None}

    def guard(value):
        if value != "history-purge-isolated-control":
            raise HTTPException(403)

    def fault(phase, identity):
        if phase == "purge_purging":
            with app.state.db.read() as db:
                row = db.get(PackPurgeStep, identity)
                if row.relative_path == "0101.png":
                    raise OSError(errno.EACCES, "isolated historical permission failure")

    original_lifespan = app.router.lifespan_context

    @asynccontextmanager
    async def lifespan(instance):
        async with original_lifespan(instance):
            instance.state.pack_purge.fault_hook = fault
            yield

    app.router.lifespan_context = lifespan

    @app.middleware("http")
    async def observe(request, call_next):
        record = None
        if request.url.path.startswith("/api/"):
            record = {
                "method": request.method,
                "path": request.url.path,
                "query": dict(request.query_params),
                "epoch": request.headers.get("X-Management-Epoch"),
            }
            trace.append(record)
        with lock:
            fail = state["fail_next"]
            match = (
                fail
                and request.method == "GET"
                and request.url.path.endswith(
                    {
                        "review": "/purge-review",
                        "files": "/purge-review/files",
                        "pages": "/purge-pages",
                    }[fail]
                )
            )
            if match:
                state["fail_next"] = None
        if match:
            with app.state.db.read() as session:
                epoch = Authority.current(session)
            response = JSONResponse(
                {
                    "error": {
                        "code": "fixture_history_unavailable",
                        "message": "原历史结果暂时无法读取，请重试原查询",
                    }
                },
                status_code=503,
                headers={"X-Management-Epoch": epoch},
            )
        else:
            response = await call_next(request)
        if record is not None:
            record["status"] = response.status_code
        return response

    @app.post("/__history_fixture/reset")
    def reset(x_fixture_key: str = Header()):
        guard(x_fixture_key)
        with lock:
            state.update(display=None, display_ack=False, fail_next=None)
        return {"reset": True}

    @app.get("/__history_fixture/status")
    def status(x_fixture_key: str = Header()):
        guard(x_fixture_key)
        with lock:
            return {"fixture": "purge-history-owned-8763", **state}

    @app.get("/__history_fixture/trace")
    def requests(x_fixture_key: str = Header()):
        guard(x_fixture_key)
        return {"items": list(trace)}

    @app.get("/__history_fixture/setup")
    def setup(x_fixture_key: str = Header()):
        guard(x_fixture_key)
        path = settings.data_dir / "app-setup.json"
        if not path.is_file():
            raise HTTPException(404)
        return json.loads(path.read_text())

    @app.post("/__history_fixture/fail-next/{kind}")
    def fail_next(kind: str, x_fixture_key: str = Header()):
        guard(x_fixture_key)
        if kind not in {"review", "files", "pages"}:
            raise HTTPException(422)
        with lock:
            state["fail_next"] = kind
        return {"fail_next": kind}

    @app.post("/__history_fixture/checkpoint/{name}")
    def checkpoint(name: str, x_fixture_key: str = Header()):
        guard(x_fixture_key)
        with lock:
            state.update(display=name, display_ack=False)
        return {"display": name}

    @app.post("/__history_fixture/ack/{name}")
    def acknowledge(name: str, x_fixture_key: str = Header()):
        guard(x_fixture_key)
        with lock:
            if state["display"] != name:
                raise HTTPException(409)
            state["display_ack"] = True
        return {"acknowledged": name}

    return app
