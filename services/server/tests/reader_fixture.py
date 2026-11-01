"""Read/receipt faults for the disposable Android flower-pack fixture only."""

import hashlib
from collections import deque
from pathlib import Path

from fastapi import Header, HTTPException
from fastapi.responses import JSONResponse

from video_viewer.models import ImagePack, PackPage, Root


def install(app, key):
    state = {"page_id": None, "remaining": 0, "pack_id": None, "progress": None}
    images, progress = deque(maxlen=32), deque(maxlen=64)

    def failure(message):
        return JSONResponse(
            {"error": {"code": "fixture_reader_unavailable", "message": message}},
            status_code=503,
        )

    @app.middleware("http")
    async def reading_fault(request, call_next):
        path = request.url.path
        if request.method == "GET" and path == f"/api/v1/pages/{state['page_id']}/image":
            if state["remaining"]:
                state["remaining"] -= 1
                images.append({"page_id": state["page_id"], "status": 503})
                return failure("这一张暂时无法载入")
            response = await call_next(request)
            images.append({"page_id": state["page_id"], "status": response.status_code})
            return response
        if request.method != "PATCH" or path != f"/api/v1/packs/{state['pack_id']}/progress":
            return await call_next(request)
        body = await request.json()
        mode, state["progress"] = state["progress"], None
        record = {
            "request_hash": hashlib.sha256(str(body.get("request_id")).encode()).hexdigest(),
            "page_id": body.get("page_id"),
            "expected_revision": body.get("expected_revision"),
            "mode": mode or "normal",
        }
        progress.append(record)
        if mode == "before":
            record.update({"status": 503, "committed": False})
            return failure("进度保存结果待确认，请查询操作结果")
        response = await call_next(request)
        record["status"] = response.status_code
        if mode == "after" and response.status_code == 200:
            # Consume the actual committed response before substituting a lost
            # acknowledgement. Never fabricate a successful database operation.
            async for _ in response.body_iterator:
                pass
            record.update({"status": 503, "committed": True})
            return failure("进度保存结果待确认，请查询操作结果")
        return response

    @app.post("/__fixture/reader/{action}")
    def reader_action(
        action: str,
        pack_id: str | None = None,
        page_id: str | None = None,
        x_fixture_key: str | None = Header(default=None),
    ):
        if x_fixture_key != key:
            raise HTTPException(status_code=403)
        if action == "stats":
            return {
                "images": list(images),
                "progress": list(progress),
                "remaining": state["remaining"],
            }
        with app.state.db.read() as session:
            pack = session.get(ImagePack, pack_id)
            root = session.get(Root, pack.root_id) if pack else None
            if (
                root is None
                or root.kind != "pack"
                or root.path != "/media/shorts/图包"
                or Path(pack.path).parent != Path(root.path)
            ):
                raise HTTPException(status_code=409, detail="Expected isolated flower pack")
            if action == "fail-page":
                page = session.get(PackPage, page_id)
                if page is None or page.pack_id != pack.id:
                    raise HTTPException(status_code=409, detail="Expected owned fixture page")
                state.update({"page_id": page_id, "remaining": 3})
            elif action in {"drop-progress", "lose-progress"}:
                if state["progress"]:
                    raise HTTPException(
                        status_code=409, detail="An isolated fault is already armed"
                    )
                state.update(
                    {
                        "pack_id": pack_id,
                        "progress": "before" if action == "drop-progress" else "after",
                    }
                )
            else:
                raise HTTPException(status_code=404)
        return {"status": "ok"}
