"""Authenticated HTTP contract for pack catalogues and page bytes."""

from typing import Annotated, Literal

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel
from starlette.responses import Response


class ReadingProgress(BaseModel):
    page_id: str | None
    offset_ratio: float
    completed: bool
    revision: int
    updated_at: float


class PackSummary(BaseModel):
    id: str
    root_id: str
    path: str
    name: str
    status: str
    error: str | None
    page_count: int
    readable_count: int
    content_version: int
    tag_ids: list[str]
    tag_names: dict[str, str]
    created_at: float
    cover_url: str | None
    progress: ReadingProgress | None


class PackList(BaseModel):
    items: list[PackSummary]
    total: int
    offset: int
    limit: int


class PageSummary(BaseModel):
    id: str
    pack_id: str
    name: str
    relative_path: str
    ordinal: int
    width: int
    height: int
    size: int
    format: str
    sha256: str | None
    error: str | None
    content_version: int
    image_url: str | None
    thumbnail_url: str | None


class PageList(BaseModel):
    items: list[PageSummary]
    total: int
    offset: int
    limit: int
    content_version: int


def router(auth_required):
    api = APIRouter(prefix="/api/v1", dependencies=auth_required)

    @api.get("/packs", response_model=PackList)
    def packs(
        request: Request,
        offset: Annotated[int, Query(ge=0)] = 0,
        limit: Annotated[int, Query(ge=1, le=200)] = 24,
        directory_id: str | None = None,
        search: Annotated[str, Query(max_length=200)] = "",
        tag_ids: Annotated[list[str] | None, Query(max_length=256)] = None,
        read_state: Literal["all", "unread", "reading", "completed"] = "all",
        sort: Literal["name", "newest"] = "name",
        status: Literal["available", "missing", "trash", "unreadable"] = "available",
    ):
        return request.app.state.packs.list(
            offset=offset,
            limit=limit,
            directory_id=directory_id,
            search=search,
            tag_ids=tag_ids or (),
            read_state=read_state,
            sort=sort,
            status=status,
        )

    @api.get("/packs/selection")
    def pack_selection(
        request: Request,
        directory_id: str | None = None,
        search: Annotated[str, Query(max_length=200)] = "",
        tag_ids: Annotated[list[str] | None, Query(max_length=256)] = None,
        read_state: Literal["all", "unread", "reading", "completed"] = "all",
        sort: Literal["name", "newest"] = "name",
    ):
        return request.app.state.packs.selection(
            directory_id=directory_id, search=search, tag_ids=tag_ids or (),
            read_state=read_state, sort=sort,
        )

    @api.get("/packs/{pack_id}", response_model=PackSummary)
    def pack(pack_id: str, request: Request):
        return request.app.state.packs.get(pack_id)

    @api.get("/packs/{pack_id}/pages", response_model=PageList)
    def pages(
        pack_id: str,
        request: Request,
        offset: Annotated[int, Query(ge=0)] = 0,
        limit: Annotated[int, Query(ge=1, le=200)] = 100,
        v: Annotated[int | None, Query(ge=1)] = None,
    ):
        return request.app.state.packs.pages(pack_id, offset=offset, limit=limit, version=v)

    @api.get(
        "/packs/{pack_id}/cover",
        response_class=Response,
        responses={
            200: {"content": {"image/jpeg": {}}},
            206: {"description": "Partial image bytes"},
        },
    )
    @api.head("/packs/{pack_id}/cover", include_in_schema=False)
    def cover(pack_id: str, request: Request, v: Annotated[int | None, Query(ge=1)] = None):
        page_id = request.app.state.packs.cover(pack_id, v)
        return request.app.state.images.response(page_id, thumbnail=True, version=v)

    @api.get(
        "/pages/{page_id}/image",
        response_class=Response,
        responses={
            200: {"content": {"image/jpeg": {}, "image/png": {}, "image/webp": {}}},
            206: {"description": "Partial image bytes"},
        },
    )
    @api.head("/pages/{page_id}/image", include_in_schema=False)
    def image(page_id: str, request: Request, v: Annotated[int | None, Query(ge=1)] = None):
        return request.app.state.images.response(page_id, version=v)

    @api.get(
        "/pages/{page_id}/thumbnail",
        response_class=Response,
        responses={
            200: {"content": {"image/jpeg": {}}},
            206: {"description": "Partial image bytes"},
        },
    )
    @api.head("/pages/{page_id}/thumbnail", include_in_schema=False)
    def thumbnail(page_id: str, request: Request, v: Annotated[int | None, Query(ge=1)] = None):
        return request.app.state.images.response(page_id, thumbnail=True, version=v)

    return api
