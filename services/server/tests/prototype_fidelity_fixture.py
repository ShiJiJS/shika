"""Disposable public media for native/reference comparison; never production."""

import json
import os
import shutil
from collections import deque
from dataclasses import replace
from pathlib import Path

from fastapi import Header, HTTPException
from fastapi.responses import JSONResponse
from sqlalchemy import select

from video_viewer.app import create_app
from video_viewer.authority import Authority
from video_viewer.config import Settings
from video_viewer.models import (
    ImagePack,
    PackPage,
    PackProgress,
    PackTag,
    PackTagLink,
    Root,
    Tag,
    Video,
    VideoTag,
)

KEY = "prototype-fidelity-owned-control"


def create_fidelity_app():
    settings = replace(Settings.from_env(), startup_scan=False)
    if (
        os.environ.get("VV_FIDELITY_FIXTURE") != "enabled"
        or settings.passphrase != "prototype-fidelity-owned-only"
        or settings.data_dir != Path("/data")
        or {str(m.path) for m in settings.mounts} != {"/media/videos", "/media/packs"}
    ):
        raise RuntimeError("Requires dedicated prototype-fidelity fixture")
    descriptions = json.loads(Path("/fixture/packs.json").read_text())
    for pack in descriptions:
        target = Path("/media/packs") / pack["folder"]
        target.mkdir(parents=True, exist_ok=False)
        # The final frozen UI uses six actual public samples per pack.
        for index, page in enumerate(pack["pages"]):
            source = Path("/fixture/raster") / Path(page).with_suffix(".png").name
            shutil.copyfile(source, target / f"{index + 1:04d}.png")
    for orientation, folder, title in (
        ("landscape", "横屏", "风里的花园"),
        ("portrait", "竖屏", "水边的花"),
    ):
        target = Path("/media/videos") / folder
        target.mkdir(parents=True, exist_ok=False)
        shutil.copyfile(Path("/public") / f"flower-{orientation}.mp4", target / f"{title}.mp4")
    app = create_app(settings)
    state = {"display": None, "ack": False, "prepared": False, "continuation_failure": False}
    trace = deque(maxlen=5000)

    def guard(key):
        if key != KEY:
            raise HTTPException(403)

    @app.middleware("http")
    async def record(request, call_next):
        body = (
            await request.json()
            if request.url.path == "/api/v1/pack-sessions" and request.method == "POST"
            else None
        )
        if (
            state["continuation_failure"]
            and request.method == "GET"
            and request.url.path == "/api/v1/packs"
            and request.query_params.get("source") == "recent"
            and request.query_params.get("limit") == "1"
            and request.headers.get("Authorization")
        ):
            with app.state.db.read() as db:
                epoch = Authority.current(db)
            response = JSONResponse(
                {"error": {"code": "fixture_unavailable", "message": "续读摘要暂不可用"}},
                status_code=503,
                headers={"X-Management-Epoch": epoch},
            )
        else:
            response = await call_next(request)
        if request.url.path.startswith("/api/"):
            trace.append(
                {
                    "method": request.method,
                    "path": request.url.path,
                    "status": response.status_code,
                    "phase": state["display"],
                    **({"body": body} if body is not None else {}),
                }
            )
        return response

    @app.post("/__fidelity/prepare")
    def prepare(x_fixture_key: str = Header()):
        guard(x_fixture_key)
        if state["prepared"]:
            raise HTTPException(409)
        with app.state.db.write() as db:
            for root in db.scalars(select(Root)):
                root.kind = "pack" if root.path == "/media/packs" else "video"
        # The scanner may legitimately defer a just-created directory snapshot.
        # Rescan the same disposable source; do not forge missing scan results.
        for _ in range(3):
            app.state.scanner.submit()
            app.state.scanner.future.result(timeout=90)
            with app.state.db.read() as db:
                if len(db.scalars(select(ImagePack)).all()) == 4:
                    break
        with app.state.db.write() as db:
            videos = db.scalars(select(Video)).all()
            packs = db.scalars(select(ImagePack)).all()
            assert len(videos) == 2 and len(packs) == 4
            video_tags = {name: Tag(name=name) for name in ("户外", "自然", "喜欢")}
            pack_tags = {
                name: PackTag(name=name) for name in ("和服", "户外", "白裙", "角色", "喜欢")
            }
            db.add_all([*video_tags.values(), *pack_tags.values()])
            db.flush()
            for video in videos:
                video.name = Path(video.name).stem
                landscape = "风里" in video.name
                orientation = "landscape" if landscape else "portrait"
                poster = f"fidelity-{orientation}.jpg"
                shutil.copyfile(
                    Path("/public") / f"flower-{orientation}.jpg",
                    settings.data_dir / "thumbnails" / poster,
                )
                video.thumbnail = poster
                for name in ("户外", "喜欢" if landscape else "自然"):
                    db.add(VideoTag(video_id=video.id, tag_id=video_tags[name].id))
            for pack in packs:
                description = next(p for p in descriptions if p["folder"] == pack.name)
                assert pack.page_count == len(description["pages"])
                for name in description["tags"]:
                    db.add(PackTagLink(pack_id=pack.id, tag_id=pack_tags[name].id))
                if description["id"] == "summer":
                    page = db.scalar(
                        select(PackPage).where(PackPage.pack_id == pack.id, PackPage.ordinal == 2)
                    )
                    db.add(
                        PackProgress(
                            pack_id=pack.id,
                            page_id=page.id,
                            content_version=pack.content_version,
                            revision=1,
                            offset_ratio=0,
                            updated_at=1000,
                        )
                    )
        state["prepared"] = True
        return {"videos": 2, "packs": 4, "pages": sum(len(p["pages"]) for p in descriptions)}

    @app.get("/__fidelity/state")
    def status(x_fixture_key: str = Header()):
        guard(x_fixture_key)
        return {"fixture": "prototype-fidelity-owned-8768", **state, "requests": list(trace)}

    @app.post("/__fidelity/continuation-failure/{mode}")
    def continuation_failure(mode: str, x_fixture_key: str = Header()):
        guard(x_fixture_key)
        if mode not in {"on", "off"}:
            raise HTTPException(422)
        state["continuation_failure"] = mode == "on"
        return {"failure": state["continuation_failure"]}

    @app.post("/__fidelity/checkpoint/{name}")
    def checkpoint(name: str, x_fixture_key: str = Header()):
        guard(x_fixture_key)
        state.update(display=name, ack=False)
        return {"display": name}

    @app.post("/__fidelity/ack/{name}")
    def acknowledge(name: str, x_fixture_key: str = Header()):
        guard(x_fixture_key)
        if state["display"] != name:
            raise HTTPException(409)
        state["ack"] = True
        return {"ack": True}

    return app
