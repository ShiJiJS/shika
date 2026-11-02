"""Streaming v2 management files and bounded preview/control endpoints."""

import os
import tempfile
from pathlib import Path
from typing import Annotated, Literal

from fastapi import APIRouter, Header, Query, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from starlette.concurrency import run_in_threadpool

from .errors import LibraryError
from .management_history import current_history
from .models import RequestRecord, Task


class Command(BaseModel):
    model_config = ConfigDict(extra="forbid")
    request_id: str = Field(min_length=1, max_length=128)


class Restore(Command):
    preview_id: str = Field(min_length=1, max_length=128)
    root_mapping: dict[str, str | None] = Field(max_length=256)
    confirmed: Literal[True]


def _write(fd, chunk):
    pending = memoryview(chunk)
    while pending:
        count = os.write(fd, pending)
        if count <= 0:
            raise OSError("short management upload")
        pending = pending[count:]


def router(auth_required):
    route = APIRouter(prefix="/api/v1/management-backups", dependencies=auth_required)

    @route.post("", status_code=202)
    def export(body: Command, request: Request):
        archives = request.app.state.backups.archives
        identity = archives.submit("backup_export_v2", body.request_id)
        return request.app.state.scanner.task(identity)

    @route.post("/imports", status_code=202)
    async def inspect(
        request: Request, idempotency_key: Annotated[str, Header(min_length=1, max_length=128)]
    ):
        archives = request.app.state.backups.archives
        descriptor, filename = tempfile.mkstemp(prefix=".incoming-", dir=archives.store)
        try:
            size = 0
            async for chunk in request.stream():
                size += len(chunk)
                if size > archives.settings.backup_max_bytes:
                    raise LibraryError("backup_too_large", "管理备份超过大小限制", 413)
                await run_in_threadpool(_write, descriptor, chunk)
            await run_in_threadpool(os.fsync, descriptor)
            os.close(descriptor)
            descriptor = None
            identity = await run_in_threadpool(
                archives.submit, "backup_inspect_v2", idempotency_key, Path(filename)
            )
            return await run_in_threadpool(request.app.state.scanner.task, identity)
        finally:
            if descriptor is not None:
                os.close(descriptor)
            Path(filename).unlink(missing_ok=True)

    @route.get("/latest-restore")
    def latest_restore(request: Request):
        with request.app.state.db.read() as session:
            parent = (
                session.execute(
                    select(Task.id, Task.result["pre_snapshot_id"].as_string().label("snapshot_id"))
                    .where(
                        Task.kind.in_(("backup_restore", "backup_restore_v2")),
                        Task.status == "completed",
                        Task.error.is_distinct_from("restored_history"),
                    )
                    .order_by(Task.finished_at.desc(), Task.created_at.desc(), Task.id.desc())
                    .limit(1)
                )
                .mappings()
                .first()
            )
            if parent is None or not parent["snapshot_id"]:
                return {"item": None}
            snapshot = (
                session.execute(
                    select(
                        Task.id.label("snapshot_id"),
                        Task.kind,
                        Task.created_at,
                        Task.result["bytes"].as_integer().label("bytes"),
                        Task.result["file_sha256"].as_string().label("file_sha256"),
                    ).where(
                        Task.id == parent["snapshot_id"],
                        Task.kind.in_(("backup_snapshot", "backup_snapshot_v2")),
                        Task.status == "completed",
                        Task.error.is_distinct_from("restored_history"),
                    )
                )
                .mappings()
                .first()
            )
            return {"item": {"restore_id": parent["id"], **dict(snapshot)} if snapshot else None}

    @route.post("/from-snapshot/{identity}", status_code=202)
    def inspect_snapshot(identity: str, body: Command, request: Request):
        backups = request.app.state.backups
        with request.app.state.db.read() as session:
            row = session.get(Task, identity)
            if (
                row is None
                or row.kind not in ("backup_snapshot", "backup_snapshot_v2")
                or row.status != "completed"
                or row.error == "restored_history"
            ):
                raise LibraryError("backup_not_found", "原恢复前快照尚未完成或在本服务不可用", 404)
            version = 2 if row.kind == "backup_snapshot_v2" else 1
        source = backups.archives.artifact(identity) if version == 2 else backups.artifact(identity)
        accepted = backups.archives.submit("backup_inspect_v2", body.request_id, source)
        return request.app.state.scanner.task(accepted)

    @route.post("/restores", status_code=202)
    def restore(body: Restore, request: Request):
        identity = request.app.state.backups.archives.submit_restore(
            body.preview_id, body.root_mapping, body.request_id
        )
        return request.app.state.scanner.task(identity)

    @route.get("/requests/{kind}/{request_id}")
    def receipt(kind: Literal["export", "inspect", "restore"], request_id: str, request: Request):
        namespace = {
            "export": "management.backup_export_v2:",
            "inspect": "management.backup_inspect_v2:",
            "restore": "management.restore:",
        }[kind]
        with request.app.state.db.read() as session:
            identity = session.scalar(
                select(RequestRecord.result).where(RequestRecord.id == namespace + request_id)
            )
            if identity is None:
                history = current_history(session)
                if history:
                    try:
                        identity = history.receipt("request_records", namespace + request_id)[
                            "record"
                        ]["result"]
                    except LibraryError as error:
                        if error.code != "history_not_found":
                            raise
        if identity is None:
            raise LibraryError("backup_request_not_found", "未找到原管理请求；没有补执行", 404)
        return request.app.state.scanner.task(identity["id"])

    @route.get("/{identity}/roots")
    def roots(
        identity: str,
        request: Request,
        offset: Annotated[int, Query(ge=0)] = 0,
        limit: Annotated[int, Query(ge=1, le=100)] = 24,
    ):
        return request.app.state.backups.archives.preview_roots(
            identity, offset=offset, limit=limit
        )

    @route.get("/{identity}/download")
    def download(identity: str, request: Request):
        path = request.app.state.backups.archives.artifact(identity)
        return FileResponse(
            path, media_type="application/x-ndjson", filename=f"video-viewer-{identity}.vvbackup"
        )

    return route
