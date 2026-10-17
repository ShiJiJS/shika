import sqlite3
import threading
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated, Literal

from fastapi import Depends, FastAPI, Header, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, ConfigDict, Field, SecretStr, model_validator
from sqlalchemy import select
from starlette.concurrency import run_in_threadpool

from .backups import Backups
from .catalog import Catalog
from .config import Settings
from .db import Database
from .errors import LibraryError
from .file_operations import FileOperations
from .file_state import reserved_video_ids
from .library_state import library_state
from .metadata_cleanup import forget_missing
from .models import FileOperation, RequestRecord, Root, Setting, Video, uid
from .playback import Playback
from .scanner import Scanner
from .security import Authentication
from .streaming import MediaStreams
from .tags import Tags


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Login(Input):
    passphrase: SecretStr = Field(min_length=1, max_length=1024)


class RootInput(Input):
    name: str = Field(min_length=1, max_length=100)
    path: str = Field(min_length=1, max_length=4096)


class PlaybackScope(Input):
    directory_id: str | None = Field(default=None, min_length=1, max_length=128)
    orientation: Literal["portrait", "landscape"] | None = None
    duration: Literal["short", "long"] | None = None
    file_type: str | None = Field(default=None, max_length=16)
    tag_ids: list[str] = Field(default_factory=list, max_length=256)


class RoundInput(Input):
    request_id: str = Field(min_length=1, max_length=128)
    order: Literal["random", "sequential"] = "random"
    scope: PlaybackScope = Field(default_factory=PlaybackScope)
    anchor_video_id: str | None = None


class PositionInput(Input):
    expected_revision: int = Field(ge=0)
    video_id: str | None = Field(default=None, min_length=1, max_length=128)
    finish: bool = False

    @model_validator(mode="after")
    def exactly_one_action(self):
        if bool(self.video_id) == self.finish:
            raise ValueError("Specify either video_id or finish")
        return self


class WriteInput(Input):
    request_id: str = Field(min_length=1, max_length=128)


class TagInput(WriteInput):
    name: str = Field(min_length=1, max_length=100)


class TagAssignment(WriteInput):
    video_ids: list[Annotated[str, Field(min_length=1, max_length=128)]] = Field(
        min_length=1, max_length=1000
    )
    tag_ids: list[Annotated[str, Field(min_length=1, max_length=128)]] = Field(
        default_factory=list, max_length=256
    )
    mode: Literal["add", "remove", "replace"] = "add"


class DeleteInput(WriteInput):
    video_ids: list[Annotated[str, Field(min_length=1, max_length=128)]] = Field(
        min_length=1, max_length=1000
    )


class TrashInput(WriteInput):
    trash_ids: list[Annotated[str, Field(min_length=1, max_length=128)]] = Field(
        min_length=1, max_length=1000
    )


class PermanentInput(TrashInput):
    confirmed: Literal[True]


class ForgetMissingInput(WriteInput):
    confirmed: Literal[True]


class RestoreInput(WriteInput):
    preview_id: str = Field(min_length=1, max_length=128)
    root_mapping: dict[str, str | None] = Field(max_length=256)
    confirmed: Literal[True]


def create_app(settings: Settings | None = None, file_fault_hook=None, backup_fault_hook=None):
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
        app.state.streams = MediaStreams(db, configured)
        app.state.playback = Playback(db, catalog, app.state.streams)
        app.state.tags = Tags(db, app.state.playback)
        app.state.files = FileOperations(
            db, configured, catalog, app.state.playback, file_fault_hook
        )
        app.state.backups = Backups(db, configured, scanner, app.state.files, backup_fault_hook)
        app.state.login_attempts = {}
        app.state.login_lock = threading.Lock()

        def start_regular():
            app.state.files.start()
            scanner.start()

        app.state.backups.start(start_regular)
        try:
            yield
        finally:
            app.state.backups.close()
            scanner.close()
            app.state.files.close()
            db.close()

    app = FastAPI(title="Video Viewer", version="0.1.2", lifespan=lifespan)

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

    @app.get("/api/v1/library-state", dependencies=auth_required)
    def preparation(request: Request):
        return library_state(request.app.state.db)

    def save_root(body, request, root_id=None):
        scanner = request.app.state.scanner
        with scanner.lock:
            if scanner.future and not scanner.future.done():
                raise LibraryError("scan_busy", "扫描进行中，请完成后再修改媒体目录")
            with request.app.state.db.read() as session:
                if session.scalar(
                    select(Video.id).where(Video.id.in_(reserved_video_ids())).limit(1)
                ):
                    raise LibraryError("operation_busy", "文件操作进行中，请完成后再修改媒体目录")
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

    @app.get("/api/v1/directories/resolve", dependencies=auth_required)
    def resolve_directory(
        request: Request, path: Annotated[str, Query(min_length=1, max_length=4096)]
    ):
        return request.app.state.catalog.directory(path=path)

    @app.get("/api/v1/directories/{directory_id}", dependencies=auth_required)
    def directory(directory_id: str, request: Request):
        return request.app.state.catalog.directory(directory_id=directory_id)

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
        tag_ids: Annotated[list[str] | None, Query(max_length=256)] = None,
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
            tag_ids=tag_ids or (),
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

    @app.get("/api/v1/videos/{video_id}/stream", dependencies=auth_required)
    @app.head(
        "/api/v1/videos/{video_id}/stream", dependencies=auth_required, include_in_schema=False
    )
    def stream(video_id: str, request: Request):
        return request.app.state.streams.response(video_id)

    @app.get("/api/v1/playback", dependencies=auth_required)
    def playback(request: Request):
        return request.app.state.playback.current()

    @app.post("/api/v1/rounds", dependencies=auth_required, status_code=201)
    def create_round(body: RoundInput, request: Request):
        return request.app.state.playback.create(
            body.order,
            body.scope.model_dump(exclude_none=True),
            body.anchor_video_id,
            body.request_id,
        )

    @app.patch("/api/v1/rounds/{round_id}/position", dependencies=auth_required)
    def position(round_id: str, body: PositionInput, request: Request):
        return request.app.state.playback.move(
            round_id, body.expected_revision, body.video_id, body.finish
        )

    @app.get("/api/v1/rounds/{round_id}/entries", dependencies=auth_required)
    def round_entries(
        round_id: str,
        request: Request,
        offset: Annotated[int, Query(ge=0)] = 0,
        limit: Annotated[int, Query(ge=1, le=200)] = 50,
    ):
        return request.app.state.playback.entries(round_id, offset, limit)

    @app.get("/api/v1/tags", dependencies=auth_required)
    def tags(
        request: Request,
        search: Annotated[str, Query(max_length=200)] = "",
        offset: Annotated[int, Query(ge=0)] = 0,
        limit: Annotated[int, Query(ge=1, le=200)] = 200,
    ):
        return request.app.state.tags.list(search, offset, limit)

    @app.post("/api/v1/tags", dependencies=auth_required, status_code=201)
    def create_tag(body: TagInput, request: Request):
        return request.app.state.tags.create(body.name, body.request_id)

    @app.patch("/api/v1/tags/{tag_id}", dependencies=auth_required)
    def rename_tag(tag_id: str, body: TagInput, request: Request):
        return request.app.state.tags.rename(tag_id, body.name, body.request_id)

    @app.delete("/api/v1/tags/{tag_id}", dependencies=auth_required)
    def delete_tag(tag_id: str, body: WriteInput, request: Request):
        return request.app.state.tags.delete(tag_id, body.request_id)

    @app.patch("/api/v1/video-tags", dependencies=auth_required)
    def assign_tags(body: TagAssignment, request: Request):
        return request.app.state.tags.assign(
            body.video_ids, body.tag_ids, body.mode, body.request_id
        )

    @app.get("/api/v1/trash", dependencies=auth_required)
    def trash(
        request: Request,
        offset: Annotated[int, Query(ge=0)] = 0,
        limit: Annotated[int, Query(ge=1, le=200)] = 50,
    ):
        return request.app.state.files.trash(offset, limit)

    @app.post("/api/v1/backups", dependencies=auth_required, status_code=202)
    def export_backup(body: WriteInput, request: Request):
        task_id = request.app.state.backups.submit("backup_export", body.request_id)
        return request.app.state.scanner.task(task_id)

    @app.get("/api/v1/backups", dependencies=auth_required)
    def list_backups(request: Request, limit: Annotated[int, Query(ge=1, le=100)] = 20):
        return {"items": request.app.state.backups.exports(limit)}

    @app.get("/api/v1/backups/{backup_id}/download", dependencies=auth_required)
    def download_backup(backup_id: str, request: Request):
        path = request.app.state.backups.artifact(backup_id)
        return FileResponse(
            path, media_type="application/json", filename=f"video-viewer-backup-{path.stem}.json"
        )

    @app.post("/api/v1/backup-imports", dependencies=auth_required, status_code=202)
    async def inspect_backup(
        request: Request,
        idempotency_key: Annotated[str | None, Header(min_length=1, max_length=128)] = None,
    ):
        maximum = request.app.state.settings.backup_max_bytes
        body = bytearray()
        async for chunk in request.stream():
            if len(body) + len(chunk) > maximum:
                raise LibraryError("backup_too_large", "备份超过当前大小限制", 413)
            body.extend(chunk)
        # JSON parsing and schema validation run in the bounded backup executor.
        task_id = await run_in_threadpool(
            request.app.state.backups.submit,
            "backup_inspect",
            idempotency_key or uid(),
            bytes(body),
        )
        return request.app.state.scanner.task(task_id)

    @app.post("/api/v1/backup-restores", dependencies=auth_required, status_code=202)
    def restore_backup(body: RestoreInput, request: Request):
        task_id = request.app.state.backups.submit_restore(
            body.preview_id, body.root_mapping, body.request_id
        )
        return request.app.state.scanner.task(task_id)

    @app.get("/api/v1/backup-requests/{kind}/{request_id}", dependencies=auth_required)
    def backup_request(kind: Literal["export", "inspect", "restore"], request_id: str, request: Request):
        namespace = {"export": "backup.backup_export", "inspect": "backup.backup_inspect", "restore": "backup.restore"}[kind]
        with request.app.state.db.read() as session:
            record = session.get(RequestRecord, namespace + ":" + request_id)
            if not record:
                raise LibraryError("backup_request_not_found", "未查询到已受理的备份任务", 404)
            task_id = record.result["id"]
        return request.app.state.scanner.task(task_id)

    def operation_task(request, operation_id):
        return request.app.state.scanner.task(operation_id)

    @app.post("/api/v1/videos/trash", dependencies=auth_required, status_code=202)
    def delete_videos(body: DeleteInput, request: Request):
        return operation_task(
            request, request.app.state.files.submit("trash", body.video_ids, body.request_id)
        )

    @app.post("/api/v1/trash/restore", dependencies=auth_required, status_code=202)
    def restore_trash(body: TrashInput, request: Request):
        return operation_task(
            request, request.app.state.files.submit("restore", body.trash_ids, body.request_id)
        )

    @app.post("/api/v1/videos/forget-missing", dependencies=auth_required)
    def forget_missing_videos(body: ForgetMissingInput, request: Request):
        return forget_missing(request.app.state.db, body.request_id)

    @app.post("/api/v1/trash/permanent", dependencies=auth_required, status_code=202)
    def permanent_trash(body: PermanentInput, request: Request):
        return operation_task(
            request, request.app.state.files.submit("permanent", body.trash_ids, body.request_id)
        )

    @app.post("/api/v1/operations/{operation_id}/undo", dependencies=auth_required, status_code=202)
    def undo_delete(operation_id: str, body: WriteInput, request: Request):
        return operation_task(
            request,
            request.app.state.files.submit("undo", [], body.request_id, undo_of=operation_id),
        )

    @app.post(
        "/api/v1/operations/{operation_id}/retry", dependencies=auth_required, status_code=202
    )
    def retry_operation(operation_id: str, body: WriteInput, request: Request):
        return operation_task(request, request.app.state.files.retry(operation_id, body.request_id))

    @app.get("/api/v1/operations/{operation_id}", dependencies=auth_required)
    def operation(operation_id: str, request: Request):
        with request.app.state.db.read() as session:
            if not session.get(FileOperation, operation_id):
                raise LibraryError("operation_not_found", "文件操作不存在", 404)
        return operation_task(request, operation_id)

    @app.get("/api/v1/file-requests/{request_id}", dependencies=auth_required)
    def file_request(request_id: str, request: Request):
        # Read-only reconciliation after a lost submit response. Never enqueue
        # a missing or historical command merely because a client reopened.
        with request.app.state.db.read() as session:
            operation = session.scalar(
                select(FileOperation).where(FileOperation.request_key == "files:" + request_id)
            )
            if not operation:
                raise LibraryError("operation_not_found", "未查询到已受理的文件操作", 404)
            operation_id = operation.id
        return operation_task(request, operation_id)

    return app
