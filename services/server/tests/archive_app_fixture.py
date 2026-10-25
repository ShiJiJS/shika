"""Opt-in isolated Android archive fixture; never used by production startup."""

import json
import os
from collections import deque
from pathlib import Path

from fastapi import Header, HTTPException
from fastapi.responses import JSONResponse
from PIL import Image

from video_viewer.app import create_app
from video_viewer.config import Settings


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
    app = create_app(settings)
    trace = deque(maxlen=20000)

    @app.middleware("http")
    async def fixture_only(request, call_next):
        if request.url.path.startswith("/api/"):
            trace.append(
                {
                    "method": request.method,
                    "path": request.url.path,
                    "query": dict(request.query_params),
                    "epoch": request.headers.get("X-Management-Epoch"),
                }
            )
        response = await call_next(request)
        if request.url.path == "/api/v1/info" and response.status_code == 200:
            # Exercise the unreleased App path without advertising production
            # readiness before native UI/history/restart acceptance is complete.
            payload = json.loads(b"".join([part async for part in response.body_iterator]))
            payload["capabilities"].append("backup_v2")
            headers = {k: v for k, v in response.headers.items() if k.lower() != "content-length"}
            return JSONResponse(payload, headers=headers)
        return response

    @app.get("/__archive_fixture/trace")
    def events(x_fixture_key: str = Header()):
        if x_fixture_key != "archive-app-isolated-control":
            raise HTTPException(403)
        return {"items": list(trace)}

    return app
