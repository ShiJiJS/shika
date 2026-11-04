"""The continuation uses the existing authenticated, authoritative recent query."""

import pytest
from sqlalchemy import select

from shika.models import ImagePack, PackPage, PackProgress, RecentEntry, Root

from .test_reading import create, opened, progress_body, setup


def latest(client):
    result = client.get(
        "/api/v1/packs", params={"source": "recent", "sort": "recent", "limit": 1, "offset": 0}
    )
    assert result.status_code == 200, result.text
    return result.json()


def snapshot(client):
    with client.app.state.db.read() as db:
        return {
            "progress": list(
                db.execute(
                    select(
                        PackProgress.pack_id,
                        PackProgress.page_id,
                        PackProgress.offset_ratio,
                        PackProgress.completed,
                        PackProgress.revision,
                        PackProgress.updated_at,
                    ).order_by(PackProgress.pack_id)
                )
            ),
            "recent": list(
                db.execute(
                    select(RecentEntry.kind, RecentEntry.pack_id, RecentEntry.opened_at).order_by(
                        RecentEntry.pack_id
                    )
                )
            ),
        }


def test_latest_read_is_not_limited_to_the_first_catalog_page(library):
    client, media = library
    _, ids = setup(client, media, count=27)
    page = client.get("/api/v1/packs", params={"limit": 24}).json()
    assert len(page["items"]) == 24 and ids[26] not in {p["id"] for p in page["items"]}
    value = create(client, anchor_pack_id=ids[26])
    assert value["candidate_count"] == 27
    opened(client, value)
    before = snapshot(client)
    assert latest(client)["items"][0]["id"] == ids[26]
    assert snapshot(client) == before


def test_latest_is_actual_open_not_prefetch_or_progress_update_and_reads_do_not_write(library):
    client, media = library
    _, ids = setup(client, media, count=3)
    assert latest(client)["items"] == []
    first = create(client, request_id="first", anchor_pack_id=ids[0])
    first_state = opened(client, first, request_id="first-open")
    create(client, request_id="preload", anchor_pack_id=ids[2])
    assert latest(client)["items"][0]["id"] == ids[0]
    second = create(client, request_id="second", anchor_pack_id=ids[1])
    second_state = opened(client, second, request_id="second-open")
    with client.app.state.db.read() as db:
        last_first = db.scalar(
            select(PackPage.id).where(PackPage.pack_id == ids[0], PackPage.ordinal == 2)
        )
        last_second = db.scalar(
            select(PackPage.id).where(PackPage.pack_id == ids[1], PackPage.ordinal == 2)
        )
    changed = client.patch(
        f"/api/v1/packs/{ids[0]}/progress",
        json=progress_body(first, first_state, page_id=last_first),
    )
    # Creating another range supersedes the first owner. A delayed write must
    # remain rejected; do not relax that production rule for this fixture.
    assert changed.status_code == 409
    with client.app.state.db.write() as db:
        imported = db.get(PackProgress, ids[0])
        imported.page_id = last_first
        imported.updated_at = (
            db.scalar(select(RecentEntry.opened_at).where(RecentEntry.pack_id == ids[1])) + 1000
        )
    complete = client.patch(
        f"/api/v1/packs/{ids[1]}/progress",
        json=progress_body(second, second_state, page_id=last_second, completed=True),
    )
    assert complete.status_code == 200, complete.text
    before = snapshot(client)
    for _ in range(3):
        value = latest(client)
        assert value["total"] == 2 and len(value["items"]) == 1
        assert value["items"][0]["id"] == ids[1]
        assert value["items"][0]["progress"]["page_index"] == 2
        assert value["items"][0]["progress"]["completed"] is True
    assert snapshot(client) == before


@pytest.mark.parametrize("mode", ["trashed", "missing", "unreadable", "disabled", "offline"])
def test_unavailable_last_open_is_not_returned_or_replaced_with_unopened_pack(library, mode):
    client, media = library
    root, ids = setup(client, media, count=3)
    opened(client, create(client, request_id="first", anchor_pack_id=ids[0]), request_id="open-0")
    opened(client, create(client, request_id="second", anchor_pack_id=ids[1]), request_id="open-1")
    with client.app.state.db.write() as db:
        if mode in {"disabled", "offline"}:
            setattr(
                db.get(Root, root["id"]), "enabled" if mode == "disabled" else "available", False
            )
        elif mode == "unreadable":
            for page in db.scalars(select(PackPage).where(PackPage.pack_id == ids[1])):
                page.error = "fixture_unreadable"
        else:
            db.get(ImagePack, ids[1]).status = mode
    before = snapshot(client)
    value = latest(client)
    if mode in {"disabled", "offline"}:
        assert value["total"] == 0 and value["items"] == []
    else:
        assert value["total"] == 1 and value["items"][0]["id"] == ids[0]
    assert snapshot(client) == before
