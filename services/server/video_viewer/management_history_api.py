"""Read-only exact-graph history; no route here can enqueue an old command."""

import json
import uuid
from typing import Annotated, Literal

from fastapi import APIRouter, Query, Request
from fastapi.responses import FileResponse

from .authority import valid_epoch
from .errors import LibraryError
from .maintenance_tasks import MaintenanceTasks
from .management_history import EPOCHS_KEY, current_history
from .models import Setting


def selected(session, graph_id, epoch):
    if graph_id is not None:
        try:
            if str(uuid.UUID(graph_id)) != graph_id:
                raise ValueError()
        except (ValueError, TypeError):
            raise LibraryError("invalid_history_graph", "原历史图标识不正确", 422) from None
    if epoch is not None:
        if not valid_epoch(epoch):
            raise LibraryError("invalid_management_epoch", "原管理代次标识不正确", 422)
        row = session.get(Setting, EPOCHS_KEY)
        resolved = json.loads(row.value).get(epoch) if row else None
        if not resolved:
            raise LibraryError(
                "history_not_found", "未找到该原管理代次；没有查询其他代次或补执行", 404
            )
        if graph_id is not None and graph_id != resolved:
            raise LibraryError("invalid_history_graph", "原代次与历史图不一致", 422)
        graph_id = resolved
    return graph_id


def required(session):
    value = current_history(session)
    if value is None:
        raise LibraryError("history_not_found", "尚无已提交的管理历史", 404)
    return value


def router(auth_required):
    route = APIRouter(prefix="/api/v1/management-history", dependencies=auth_required)

    @route.get("/epochs/{epoch}")
    def epoch(epoch: str, request: Request):
        with request.app.state.db.read() as session:
            graph = selected(session, None, epoch)
            required(session)
        return {"epoch": epoch, "graph_id": graph, "historical": True}

    @route.get("/tasks")
    def tasks(
        request: Request,
        offset: Annotated[int, Query(ge=0)] = 0,
        limit: Annotated[int, Query(ge=1, le=100)] = 24,
        family: str = "all",
        graph_id: str | None = None,
        epoch: str | None = None,
    ):
        with request.app.state.db.read() as session:
            graph = selected(session, graph_id, epoch)
            history = current_history(session)
        if history is None:
            if graph is not None:
                raise LibraryError("history_not_found", "原历史图尚不存在", 404)
            return MaintenanceTasks(request.app.state.db).page(offset, limit, family, "historical")
        try:
            return history.tasks(
                offset=offset,
                limit=limit,
                family=family,
                graph_id=graph,
                current_database=request.app.state.db.path,
            )
        except ValueError:
            raise LibraryError("invalid_history_query", "历史查询范围不正确", 422) from None

    @route.get("/tasks/{identity}")
    def task(
        identity: str, request: Request, graph_id: str | None = None, epoch: str | None = None
    ):
        with request.app.state.db.read() as session:
            history, graph = required(session), selected(session, graph_id, epoch)
        return history.task(identity, graph_id=graph)

    @route.get("/tasks/{identity}/record")
    def original_task(
        identity: str, request: Request, graph_id: str | None = None, epoch: str | None = None
    ):
        with request.app.state.db.read() as session:
            history, graph = required(session), selected(session, graph_id, epoch)
        return history.task_record(identity, graph_id=graph)

    @route.get("/tasks/{identity}/items")
    def members(
        identity: str,
        request: Request,
        offset: Annotated[int, Query(ge=0)] = 0,
        limit: Annotated[int, Query(ge=1, le=100)] = 24,
        unfinished: bool = False,
        graph_id: str | None = None,
        epoch: str | None = None,
    ):
        with request.app.state.db.read() as session:
            history, graph = required(session), selected(session, graph_id, epoch)
        return history.members(
            identity, offset=offset, limit=limit, unfinished=unfinished, graph_id=graph
        )

    @route.get("/tasks/{identity}/download")
    def download(
        identity: str, request: Request, graph_id: str | None = None, epoch: str | None = None
    ):
        with request.app.state.db.read() as session:
            history, graph = required(session), selected(session, graph_id, epoch)
        if graph is None:
            raise LibraryError("invalid_history_graph", "历史文件必须明确原代次或历史图", 422)
        original = history.task_record(identity, graph_id=graph)
        backups = request.app.state.backups
        if original["kind"] in ("backup_export_v2", "backup_snapshot_v2"):
            path = backups.archives.artifact(identity, original=original)
            return FileResponse(
                path,
                media_type="application/x-ndjson",
                filename=f"video-viewer-{identity}.vvbackup",
            )
        path = backups.artifact(identity, original=original)
        return FileResponse(
            path, media_type="application/json", filename=f"video-viewer-{identity}.json"
        )

    @route.get("/tasks/{identity}/purge-review")
    def purge_review(
        identity: str,
        request: Request,
        offset: Annotated[int, Query(ge=0, lt=2**63)] = 0,
        limit: Annotated[int, Query(ge=1, le=100)] = 24,
        graph_id: str | None = None,
        epoch: str | None = None,
    ):
        with request.app.state.db.read() as session:
            history, graph = required(session), selected(session, graph_id, epoch)
        return history.purge_review(identity, offset=offset, limit=limit, graph_id=graph)

    @route.get("/tasks/{identity}/purge-review/files")
    def purge_files(
        identity: str,
        request: Request,
        trash_id: str = Query(min_length=1, max_length=128),
        offset: Annotated[int, Query(ge=0, lt=2**63)] = 0,
        limit: Annotated[int, Query(ge=1, le=100)] = 100,
        graph_id: str | None = None,
        epoch: str | None = None,
    ):
        with request.app.state.db.read() as session:
            history, graph = required(session), selected(session, graph_id, epoch)
        return history.purge_files(identity, trash_id, offset=offset, limit=limit, graph_id=graph)

    @route.get("/tasks/{identity}/purge-pages")
    def purge_pages(
        identity: str,
        request: Request,
        offset: Annotated[int, Query(ge=0, lt=2**63)] = 0,
        limit: Annotated[int, Query(ge=1, le=100)] = 24,
        kind: Literal["all", "image", "directory"] = "all",
        outcome: Literal["all", "unfinished"] = "all",
        graph_id: str | None = None,
        epoch: str | None = None,
    ):
        with request.app.state.db.read() as session:
            history, graph = required(session), selected(session, graph_id, epoch)
        return history.purge_pages(
            identity, offset=offset, limit=limit, kind=kind, outcome=outcome, graph_id=graph
        )

    @route.get("/operations/{namespace}/{identity}")
    def operation(
        namespace: str,
        identity: str,
        request: Request,
        graph_id: str | None = None,
        epoch: str | None = None,
    ):
        with request.app.state.db.read() as session:
            history, graph = required(session), selected(session, graph_id, epoch)
        try:
            return history.operation(namespace, identity, graph_id=graph)
        except ValueError:
            raise LibraryError("invalid_history_query", "历史操作类型不正确", 422) from None

    @route.get("/receipts/{namespace}/{key:path}")
    def receipt(
        namespace: str,
        key: str,
        request: Request,
        graph_id: str | None = None,
        epoch: str | None = None,
    ):
        if not 1 <= len(key) <= 8192:
            raise LibraryError("invalid_history_query", "原请求标识不正确", 422)
        with request.app.state.db.read() as session:
            history, graph = required(session), selected(session, graph_id, epoch)
        try:
            return history.receipt(namespace, key, graph_id=graph)
        except ValueError:
            raise LibraryError("invalid_history_query", "历史请求类型不正确", 422) from None

    return route
