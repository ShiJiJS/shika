"""Guarded, synthetic reader-image faults on a dedicated localhost instance."""

import os
from collections import deque
from dataclasses import replace
from pathlib import Path

from fastapi import Header, HTTPException
from fastapi.responses import JSONResponse, Response
from PIL import Image
from sqlalchemy import select

from video_viewer.app import create_app
from video_viewer.authority import Authority
from video_viewer.config import Settings
from video_viewer.models import ImagePack, PackPage

KEY = "reader-image-errors-owned-control"


def create_reader_error_app():
    settings = replace(Settings.from_env(), startup_scan=False)
    if (
        os.environ.get("VV_READER_ERROR_FIXTURE") != "enabled"
        or settings.passphrase != "reader-image-errors-owned-only"
        or settings.data_dir != Path("/data")
        or {str(m.path) for m in settings.mounts} != {"/media/packs"}
    ):
        raise RuntimeError("Requires dedicated reader-error fixture settings")
    for name, color in (("异常图包 A", "#a8b790"), ("正常图包 B", "#dbb38d")):
        base = Path("/media/packs") / name
        base.mkdir(parents=True, exist_ok=True)
        for i in range(3):
            path = base / f"{i + 1:04d}.png"
            if not path.exists():
                Image.new("RGB", (720, 1080), color).save(path)
    app = create_app(settings)
    state = {"mode": "none", "pages": [], "display": None, "ack": False}
    trace = deque(maxlen=5000)

    def guard(key):
        if key != KEY:
            raise HTTPException(403)

    @app.middleware("http")
    async def image_fault(request, call_next):
        path = request.url.path
        record = None
        if path.startswith("/api/"):
            record = {"method": request.method, "path": path}
            trace.append(record)
        matching = request.method == "GET" and path in {
            f"/api/v1/pages/{identity}/image" for identity in state["pages"]
        }
        mode = state["mode"]
        if matching and mode != "none":
            with app.state.db.read() as db:
                epoch = Authority.current(db)
            headers = {"X-Management-Epoch": epoch}
            response = (
                JSONResponse(
                    {"error": {"code": "image_not_found", "message": "图片不存在"}},
                    status_code=404,
                    headers=headers,
                )
                if mode == "missing"
                else Response(b"invalid image bytes", media_type="image/png", headers=headers)
            )
            record["fault"] = mode
        else:
            response = await call_next(request)
        if record is not None:
            record["status"] = response.status_code
        return response

    @app.post("/__reader_errors/arm/{mode}")
    def arm(mode: str, pack_id: str, x_fixture_key: str = Header()):
        guard(x_fixture_key)
        if mode not in {"missing", "corrupt", "none"}:
            raise HTTPException(422)
        with app.state.db.read() as db:
            pack = db.get(ImagePack, pack_id)
            if pack is None or pack.path != "/media/packs/异常图包 A":
                raise HTTPException(409)
            state.update(
                mode=mode,
                pages=[
                    p.id for p in db.scalars(select(PackPage).where(PackPage.pack_id == pack_id))
                ],
            )
        return {"mode": mode, "page_ids": state["pages"]}

    @app.get("/__reader_errors/state")
    def status(x_fixture_key: str = Header()):
        guard(x_fixture_key)
        return {"fixture": "reader-errors-owned-8764", **state, "requests": list(trace)}

    @app.post("/__reader_errors/checkpoint/{name}")
    def checkpoint(name: str, x_fixture_key: str = Header()):
        guard(x_fixture_key)
        state.update(display=name, ack=False)
        return {"display": name}

    @app.post("/__reader_errors/ack/{name}")
    def ack(name: str, x_fixture_key: str = Header()):
        guard(x_fixture_key)
        if state["display"] != name:
            raise HTTPException(409)
        state["ack"] = True
        return {"ack": True}

    return app
