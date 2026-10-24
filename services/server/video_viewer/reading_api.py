"""Authenticated fixed-range reader commands, with separate progress/pref revisions."""

from typing import Annotated, Literal

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel, ConfigDict, Field, model_validator


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True, allow_inf_nan=False)


Identity = Annotated[str, Field(min_length=1, max_length=128)]


class Command(Input):
    request_id: Identity


class Scope(Input):
    directory_id: Identity | None = None
    search: str = Field(default="", max_length=200)
    tag_ids: list[Identity] = Field(default_factory=list, max_length=256)
    read_state: Literal["all", "unread", "reading", "completed"] = "all"


class Create(Command):
    scope: Scope = Field(default_factory=Scope)
    source: Literal["library", "tags", "recent"] = "library"
    sort: Literal["name", "newest", "recent"] = "name"
    order: Literal["sequential", "random"] = "sequential"
    anchor_pack_id: Identity | None = None


class Position(Command):
    expected_revision: int = Field(ge=0)
    pack_id: Identity | None = None
    finish: bool = False

    @model_validator(mode="after")
    def one_action(self):
        if bool(self.pack_id) == self.finish:
            raise ValueError("Specify either pack_id or finish")
        return self


class PageWrite(Command):
    page_id: Identity
    content_version: int = Field(ge=1)
    expected_session_revision: int = Field(ge=0)
    expected_revision: int = Field(ge=0)


class Opened(PageWrite):
    pack_id: Identity


class Progress(PageWrite):
    session_id: Identity
    offset_ratio: float = Field(ge=0, le=1)
    completed: bool = False


class Preferences(Input):
    mode: Literal["horizontal", "vertical"] = "horizontal"
    direction: Literal["ltr", "rtl"] = "ltr"
    gap: bool = False
    fit: Literal["contain", "width"] = "contain"


class Defaults(Command):
    expected_revision: int = Field(ge=0)
    values: Preferences


class PackPreferences(Defaults):
    session_id: Identity
    expected_session_revision: int = Field(ge=0)


def router(auth_required):
    api = APIRouter(prefix="/api/v1", dependencies=auth_required)

    @api.post("/pack-sessions", status_code=201)
    def create(body: Create, request: Request):
        return request.app.state.reading.create(**body.model_dump())

    @api.get("/pack-sessions/{identity}")
    def read(identity: str, request: Request):
        return request.app.state.reading.read(identity)

    @api.get("/pack-sessions/{identity}/entries")
    def entries(
        identity: str,
        request: Request,
        offset: Annotated[int, Query(ge=0)] = 0,
        limit: Annotated[int, Query(ge=1, le=200)] = 50,
    ):
        return request.app.state.reading.entries(identity, offset, limit)

    @api.patch("/pack-sessions/{identity}/position")
    def position(identity: str, body: Position, request: Request):
        return request.app.state.reading.position(identity, **body.model_dump())

    @api.post("/pack-sessions/{identity}/opened")
    def opened(identity: str, body: Opened, request: Request):
        fields = body.model_dump()
        pack_id = fields.pop("pack_id")
        return request.app.state.reading.write_state(identity, pack_id, opened=True, **fields)

    @api.patch("/packs/{pack_id}/progress")
    def progress(pack_id: str, body: Progress, request: Request):
        fields = body.model_dump()
        identity = fields.pop("session_id")
        return request.app.state.reading.write_state(identity, pack_id, **fields)

    @api.patch("/packs/{pack_id}/preferences")
    def preferences(pack_id: str, body: PackPreferences, request: Request):
        return request.app.state.reading.preferences(pack_id, **body.model_dump())

    @api.get("/pack-reading-requests/{kind}/{request_id}")
    def receipt(
        kind: Literal["session", "position", "opened", "progress", "preferences", "defaults"],
        request_id: Identity,
        request: Request,
    ):
        return request.app.state.reading.receipt(kind, request_id)

    @api.get("/reading-defaults")
    def defaults(request: Request):
        return request.app.state.reading.defaults()

    @api.patch("/reading-defaults")
    def set_defaults(body: Defaults, request: Request):
        return request.app.state.reading.defaults(**body.model_dump())

    return api
