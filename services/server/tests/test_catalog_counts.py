"""Type totals are catalog membership, not cache size or scan task counters."""

import pytest
from sqlalchemy import event, select

from shika.models import ImagePack, PackPage, Root, Video

from .test_media_types import pack_root, seed_pack


def video(client, media, name="video"):
    with client.app.state.db.write() as db:
        root = db.get(Root, "main")
        root.available = True
        item = Video(
            root_id=root.id,
            path=str(media / f"{name}.mp4"),
            name=name,
            size=1,
            device="1",
            inode=name,
            mtime_ns="1",
            ctime_ns="1",
            sha256=name,
            quick_hash=name,
            duration=6,
            width=100,
            height=100,
            type="MP4",
            video_codec="h264",
            container="mp4",
            seen_scan="seed",
        )
        db.add(item)
        db.flush()
        return item.id


def counts(client):
    response = client.get("/api/v1/library-state")
    assert response.status_code == 200, response.text
    body = response.json()
    return tuple(body["media"][kind]["indexed"] for kind in ("video", "pack"))


def seed(client, media, number=2):
    root = pack_root(client, media)
    vids = [video(client, media, f"video-{i:02d}") for i in range(number)]
    packs = [seed_pack(client, root, f"pack-{i:02d}") for i in range(number)]
    return root, vids, packs


def test_counts_auth_full_library_not_page_search_or_viewing_state(library, monkeypatch):
    client, media = library
    seed(client, media, 27)
    assert "media_catalog_counts" in client.get("/api/v1/info").json()["capabilities"]
    assert client.get("/api/v1/library-state", headers={"Authorization": ""}).status_code == 401
    assert len(client.get("/api/v1/videos", params={"limit": 24}).json()["items"]) == 24
    assert len(client.get("/api/v1/packs", params={"limit": 24}).json()["items"]) == 24
    assert client.get("/api/v1/videos", params={"search": "video-00"}).json()["total"] == 1
    assert client.get("/api/v1/packs", params={"search": "pack-00"}).json()["total"] == 1
    # A count must not enumerate summaries, access source media or create ranges.
    monkeypatch.setattr(client.app.state.packs, "summary", lambda *_: pytest.fail("pack summary"))
    with client.app.state.db.read() as db:
        before = {
            t: db.connection().exec_driver_sql(f"SELECT count(*) FROM {t}").scalar()
            for t in ["recent_entries", "pack_progress", "pack_sessions", "playback_rounds"]
        }
    for _ in range(3):
        assert counts(client) == (27, 27)
    with client.app.state.db.read() as db:
        after = {
            t: db.connection().exec_driver_sql(f"SELECT count(*) FROM {t}").scalar() for t in before
        }
    assert before == after == dict.fromkeys(before, 0)


@pytest.mark.parametrize(
    "mode,expected",
    [
        ("video-offline", (0, 2)),
        ("video-disabled", (0, 2)),
        ("video-error", (1, 2)),
        ("video-trash", (1, 2)),
        ("video-missing", (1, 2)),
        ("pack-offline", (2, 0)),
        ("pack-disabled", (2, 0)),
        ("pack-error", (2, 1)),
        ("pack-trash", (2, 1)),
        ("pack-missing", (2, 1)),
        ("pack-unreadable", (2, 1)),
        ("pack-wrong-kind", (2, 0)),
        ("pack-outside-owner", (2, 1)),
    ],
)
def test_totals_share_the_actual_catalog_availability_rules(library, mode, expected):
    client, media = library
    root, videos, packs = seed(client, media)
    assert counts(client) == (2, 2)
    with client.app.state.db.write() as db:
        kind, action = mode.split("-", 1)
        owner = db.get(Root, "main" if kind == "video" else root["id"])
        item = db.get(
            Video if kind == "video" else ImagePack, (videos if kind == "video" else packs)[0]
        )
        if action in {"offline", "disabled"}:
            setattr(owner, "available" if action == "offline" else "enabled", False)
        elif action == "error":
            item.error = "fixture-unreadable"
        elif action == "unreadable":
            for page in db.scalars(select(PackPage).where(PackPage.pack_id == item.id)):
                page.error = "fixture-unreadable"
        elif action == "wrong-kind":
            owner.kind = "video"
        elif action == "outside-owner":
            item.path = str(media / "not-in-pack-root")
        else:
            item.status = action
    assert counts(client) == expected
    assert counts(client) == (
        client.get("/api/v1/videos").json()["total"],
        client.get("/api/v1/packs").json()["total"],
    )


def test_both_totals_are_from_one_sqlite_snapshot_during_a_concurrent_commit(library):
    client, media = library
    root, _, _ = seed(client, media)
    db = client.app.state.db
    injected = False

    def insert_between_counts(_conn, _cursor, statement, _params, _context, _many):
        nonlocal injected
        if injected or "count(" not in statement.lower() or "videos." not in statement:
            return
        injected = True
        video(client, media, "concurrent")
        seed_pack(client, root, "concurrent")

    event.listen(db.engine, "after_cursor_execute", insert_between_counts)
    try:
        # Both additions commit after the video total was read. The pack total
        # must still be from its original read snapshot, not a later moment.
        assert counts(client) == (2, 2)
        assert injected
    finally:
        event.remove(db.engine, "after_cursor_execute", insert_between_counts)
    assert counts(client) == (3, 3)


def test_an_empty_readable_library_has_real_zero_totals(library):
    client, _ = library
    assert counts(client) == (0, 0)
