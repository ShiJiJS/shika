"""Owned synthetic long-reader fixture; never loaded by the production image."""

import os
import time
from collections import deque
from dataclasses import replace
from pathlib import Path

from fastapi import Header, HTTPException, Request

from shika.app import create_app
from shika.config import Settings

KEY = "reader-long-pack-owned-control"
PASSWORD = "reader-long-pack-owned-only"


def create_long_reader_app():
    settings = replace(Settings.from_env(), startup_scan=False)
    if (
        os.environ.get("VV_LONG_READER_FIXTURE") != "enabled"
        or settings.passphrase != PASSWORD
        or settings.data_dir != Path("/data")
        or {str(m.path) for m in settings.mounts} != {"/media/packs"}
        or not (Path("/media/packs") / "manifest.json").is_file()
    ):
        raise RuntimeError("Requires dedicated generated long-reader fixture")
    app = create_app(settings)
    state = {
        "display": None,
        "ack": False,
        "measurements": [],
        "active_images": 0,
        "peak_active_images": 0,
    }
    trace = deque(maxlen=30000)

    def guard(key):
        if key != KEY:
            raise HTTPException(403)

    @app.get("/__long_reader/state")
    def status(include_requests: bool = False, x_fixture_key: str = Header()):
        guard(x_fixture_key)
        return {
            "fixture": "reader-long-pack-owned-8769",
            **state,
            **({"requests": list(trace)} if include_requests else {}),
        }

    @app.post("/__long_reader/checkpoint/{name}")
    async def checkpoint(name: str, request: Request, x_fixture_key: str = Header()):
        guard(x_fixture_key)
        if len(name) > 100 or not all(c.isalnum() or c == "-" for c in name):
            raise HTTPException(422)
        value = await request.json()
        if not isinstance(value, dict):
            raise HTTPException(422)
        state["measurements"].append({"name": name, "client": value})
        state.update(display=name, ack=False)
        return {"display": name}

    @app.post("/__long_reader/ack/{name}")
    def ack(name: str, x_fixture_key: str = Header()):
        guard(x_fixture_key)
        if state["display"] != name:
            raise HTTPException(409)
        state["ack"] = True
        return {"ack": True}

    class Trace:
        def __init__(self, app):
            self.app = app

        async def __call__(self, scope, receive, send):
            path = scope.get("path", "")
            if scope["type"] != "http" or not path.startswith("/api/"):
                return await self.app(scope, receive, send)
            image = path.startswith("/api/v1/pages/") and path.endswith(("/image", "/thumbnail"))
            record = {
                "method": scope["method"],
                "path": path,
                "query": scope["query_string"].decode(),
                "phase": state["display"],
                "bytes": 0,
            }
            trace.append(record)
            started = time.monotonic()
            if image:
                state["active_images"] += 1
                state["peak_active_images"] = max(
                    state["peak_active_images"], state["active_images"]
                )

            async def observed(message):
                if message["type"] == "http.response.start":
                    record["status"] = message["status"]
                if message["type"] == "http.response.body":
                    record["bytes"] += len(message.get("body", b""))
                await send(message)

            try:
                await self.app(scope, receive, observed)
            finally:
                record["elapsed_ms"] = round((time.monotonic() - started) * 1000, 3)
                if image:
                    state["active_images"] -= 1

    app.add_middleware(Trace)
    return app
