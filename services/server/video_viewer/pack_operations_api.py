"""Authenticated logical pack operation commands and read-only reconciliation."""

from typing import Annotated

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel, ConfigDict, Field

Identity = Annotated[str, Field(min_length=1, max_length=128)]


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True, allow_inf_nan=False)
    request_id: Identity


class ReadingScene(BaseModel):
    model_config = ConfigDict(extra="forbid")
    session_id: Identity
    expected_session_revision: int = Field(ge=0)
    pack_id: Identity
    content_version: int = Field(ge=1)
    expected_progress_revision: int = Field(ge=0)


class Trash(Input):
    pack_ids: list[Identity] = Field(min_length=1, max_length=1000)
    reading: ReadingScene | None = None


class Restore(Input):
    trash_ids: list[Identity] = Field(min_length=1, max_length=1000)


def router(auth_required):
    api = APIRouter(prefix="/api/v1", dependencies=auth_required)

    @api.post("/packs/trash", status_code=202)
    def trash(body: Trash, request: Request):
        ops = request.app.state.pack_files
        return ops.task(
            ops.submit(
                "trash",
                body.pack_ids,
                body.request_id,
                scene=body.reading.model_dump() if body.reading else None,
            )
        )

    @api.get("/pack-trash/selection")
    def select_trash(request: Request, search: str = Query(default="", max_length=200)):
        return request.app.state.pack_files.selection(search)

    @api.get("/pack-trash")
    def list_trash(
        request: Request,
        offset: Annotated[int, Query(ge=0)] = 0,
        limit: Annotated[int, Query(ge=1, le=200)] = 24,
        search: str = Query(default="", max_length=200),
    ):
        return request.app.state.pack_files.trash(offset, limit, search)

    @api.post("/pack-trash/restore", status_code=202)
    def restore(body: Restore, request: Request):
        ops = request.app.state.pack_files
        return ops.task(ops.submit("restore", body.trash_ids, body.request_id))

    @api.post("/pack-operations/{identity}/undo", status_code=202)
    def undo(identity: str, body: Input, request: Request):
        ops = request.app.state.pack_files
        return ops.task(ops.submit("undo", [], body.request_id, undo_of=identity))

    @api.post("/pack-operations/{identity}/retry", status_code=202)
    def retry(identity: str, body: Input, request: Request):
        ops = request.app.state.pack_files
        return ops.task(ops.retry(identity, body.request_id))

    @api.get("/pack-operations/{identity}")
    def operation(identity: str, request: Request):
        return request.app.state.pack_files.task(identity)

    @api.get("/pack-file-requests/{request_id}")
    def receipt(request_id: str, request: Request):
        return request.app.state.pack_files.task(request_id=request_id)

    @api.get("/pack-retry-requests/{request_id}")
    def retry_receipt(request_id: str, request: Request):
        return request.app.state.pack_files.retry_receipt(request_id)

    return api
