import sqlite3
import threading
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated, Literal

from fastapi import Depends, FastAPI, Header, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, ConfigDict, Field, SecretStr

from .catalog import Catalog
from .config import Settings
from .db import Database
from .errors import LibraryError
from .models import Root, Setting, Video
from .scanner import Scanner
from .security import Authentication


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Login(Input):
    passphrase: SecretStr = Field(min_length=1, max_length=1024)


class RootInput(Input):
    name: str = Field(min_length=1, max_length=100)
    path: str = Field(min_length=1, max_length=4096)


def create_app(settings: Settings | None = None):
    @asynccontextmanager
    async def lifespan(app):
        configured = settings or Settings.from_env()
        db = Database(configured.data_dir)
        db.migrate()
        auth = Authentication(db, configured)
        catalog = Catalog(db, configured)
        scanner = Scanner(db, configured, catalog)
        app.state.settings, app.state.db, app.state.auth = configured, db, auth
        app.state.catalog, app.state.scanner = catalog, scanner
        app.state.login_attempts = {}
        app.state.login_lock = threading.Lock()
        scanner.start()
        try:
            yield
        finally:
            scanner.close()
            db.close()

    app = FastAPI(title="Video Viewer", version="0.1.0", lifespan=lifespan)

    @app.exception_handler(LibraryError)
    async def library_error(_request, error):
        return JSONResponse(
            {"error": {"code": error.code, "message": error.message}},
            status_code=error.status,
            headers={"WWW-Authenticate": "Bearer"} if error.status == 401 else None,
        )

    @app.exception_handler(RequestValidationError)
    async def validation_error(_request, error):
        # Validation errors may contain the original password/body by default.
        return JSONResponse(
            {
                "error": {
                    "code": "invalid_request",
                    "message": "请求参数格式不正确",
                    "fields": [".".join(map(str, e["loc"])) for e in error.errors()],
                }
            },
            status_code=422,
        )

    def authorized(request: Request, authorization: Annotated[str | None, Header()] = None):
        return request.app.state.auth.require(authorization)

    auth_required = [Depends(authorized)]

    @app.get("/health")
    def health():
        return {"status": "ok", "api_version": 1}

    @app.post("/api/v1/auth/login")
    def login(body: Login, request: Request):
        state = request.app.state
        address = request.client.host if request.client else "local"
        # Bounded, expiring per-address attempts; nothing logs the supplied secret.
        now = time.monotonic()
        with state.login_lock:
            state.login_attempts = {
                key: values
                for key, values in state.login_attempts.items()
                if values and now - values[-1] < 60
            }
            attempts = [t for t in state.login_attempts.get(address, []) if now - t < 60]
            if len(attempts) >= 10 or len(state.login_attempts) > 1000:
                raise LibraryError("login_rate_limited", "尝试过于频繁，请稍后重试", 429)
            attempts.append(now)
            state.login_attempts[address] = attempts
        return state.auth.login(body.passphrase.get_secret_value())

    @app.delete("/api/v1/auth/session", status_code=204)
    def revoke(request: Request, digest=Depends(authorized)):
        request.app.state.auth.revoke(digest)

    @app.get("/api/v1/info", dependencies=auth_required)
    def info(request: Request):
        with request.app.state.db.read() as session:
            server_id = session.get(Setting, "server_id").value
        return {"server_id": server_id, "api_version": 1, "sqlite_version": sqlite3.sqlite_version}

    @app.get("/api/v1/mounts", dependencies=auth_required)
    def mounts(request: Request):
        return {
            "items": [
                {"id": m.id, "name": m.name, "path": str(m.path)}
                for m in request.app.state.settings.mounts
            ]
        }

    @app.get("/api/v1/roots", dependencies=auth_required)
    def roots(request: Request):
        return {"items": request.app.state.catalog.roots()}

    def save_root(body, request, root_id=None):
        scanner = request.app.state.scanner
        with scanner.lock:
            if scanner.future and not scanner.future.done():
                raise LibraryError("scan_busy", "扫描进行中，请完成后再修改媒体目录")
            return request.app.state.catalog.save_root(body.name, body.path, root_id)

    @app.post("/api/v1/roots", dependencies=auth_required, status_code=201)
    def add_root(body: RootInput, request: Request):
        return save_root(body, request)

    @app.put("/api/v1/roots/{root_id}", dependencies=auth_required)
    def edit_root(root_id: str, body: RootInput, request: Request):
        return save_root(body, request, root_id)

    @app.get("/api/v1/directories", dependencies=auth_required)
    def directories(request: Request, parent_id: str | None = None):
        return {"items": request.app.state.catalog.directories(parent_id)}

    @app.post("/api/v1/scans", dependencies=auth_required, status_code=202)
    def scan(request: Request):
        return request.app.state.scanner.submit()

    @app.get("/api/v1/tasks/{task_id}", dependencies=auth_required)
    def task(task_id: str, request: Request):
        return request.app.state.scanner.task(task_id)

    @app.get("/api/v1/tasks", dependencies=auth_required)
    def tasks(request: Request, limit: Annotated[int, Query(ge=1, le=100)] = 20):
        return {"items": request.app.state.scanner.tasks(limit)}

    @app.get("/api/v1/videos", dependencies=auth_required)
    def videos(
        request: Request,
        offset: Annotated[int, Query(ge=0)] = 0,
        limit: Annotated[int, Query(ge=1, le=200)] = 50,
        directory_id: str | None = None,
        status: Literal["available", "missing", "trash"] = "available",
        search: Annotated[str, Query(max_length=200)] = "",
        orientation: Literal["portrait", "landscape"] | None = None,
        duration: Literal["short", "long"] | None = None,
        file_type: Annotated[str | None, Query(max_length=16)] = None,
    ):
        return request.app.state.catalog.videos(
            offset=offset,
            limit=limit,
            directory_id=directory_id,
            status=status,
            search=search,
            orientation=orientation,
            duration=duration,
            file_type=file_type,
        )

    @app.get("/api/v1/videos/{video_id}/thumbnail", dependencies=auth_required)
    def thumbnail(video_id: str, request: Request):
        state = request.app.state
        with state.db.read() as session:
            video = session.get(Video, video_id)
            if not video or not video.thumbnail:
                raise LibraryError("video_not_found", "视频缩略图不存在", 404)
            root = session.get(Root, video.root_id)
            if not root.available:
                raise LibraryError("root_unavailable", "媒体目录暂不可用")
            path = state.settings.data_dir / "thumbnails" / Path(video.thumbnail).name
        if not path.is_file():
            raise LibraryError("thumbnail_unavailable", "缩略图尚未生成，请刷新")
        return FileResponse(
            path, media_type="image/jpeg", headers={"Cache-Control": "private, max-age=300"}
        )

    return app
