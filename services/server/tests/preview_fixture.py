"""Additional disposable media and read faults for native return-position tests."""

import shutil

from fastapi import Header, HTTPException
from fastapi.responses import JSONResponse


def install(app, base, portrait, key):
    controls = {"fail_anchor_reads": False}

    @app.middleware("http")
    async def anchor_fault(request, call_next):
        if (
            controls["fail_anchor_reads"]
            and request.url.path == "/api/v1/videos"
            and "anchor_ids" in request.query_params
        ):
            return JSONResponse(
                {
                    "error": {
                        "code": "fixture_anchor_unavailable",
                        "message": "测试返回定位暂不可用",
                    }
                },
                status_code=503,
            )
        return await call_next(request)

    @app.post("/__fixture/preview/{action}")
    def preview_action(action: str, x_fixture_key: str | None = Header(default=None)):
        if x_fixture_key != key:
            raise HTTPException(status_code=403)
        folder = base / "shorts" / "自然" / "花卉"
        if action == "extend":
            names = [f"片段{index:02d}.mp4" for index in range(26, 74)]
        elif action == "insert":
            names = ["000-new.mp4"]
        elif action in {"fail", "recover"}:
            controls["fail_anchor_reads"] = action == "fail"
            return {"status": "ok"}
        else:
            raise HTTPException(status_code=404)
        for name in names:
            target = folder / name
            if not target.exists():
                with target.open("xb") as output, portrait.open("rb") as source:
                    shutil.copyfileobj(source, output)
        return {"status": "ok", "files": len(names)}
