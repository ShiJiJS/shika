"""Complete selection shares catalogue filters and never creates viewing state."""

from sqlalchemy import select

from shika import catalog_selection
from shika.models import PackProgress, RecentEntry, Root

from .conftest import put, scan
from .test_media_types import pack_root, pack_tag
from .test_packs import image, packs, sync
from .test_tags import assign, tag


def selected(client, kind, params=None):
    response = client.get(f"/api/v1/{kind}s/selection", params=params or {})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["kind"] == kind
    assert body["total"] == len(body["ids"]) == len(set(body["ids"]))
    return body["ids"]


def test_video_selection_full_scope_recent_auth_and_no_viewing_writes(
    library, samples, monkeypatch
):
    client, media = library
    for i in range(29):
        put(samples / "portrait.mp4", media / "selected" / f"clip-{i:02d}.mp4")
    put(samples / "h264.mov", media / "outside" / "one.mov")
    scan(client)
    videos = client.get("/api/v1/videos", params={"limit": 200, "search": "selected"}).json()[
        "items"
    ]
    ids = [v["id"] for v in videos]
    first, second = tag(client, "first"), tag(client, "second")
    assign(client, ids, [first["id"]])
    assign(client, ids[:27], [second["id"]])
    params = {
        "search": "selected",
        "tag_ids": [first["id"], second["id"]],
        "orientation": "portrait",
        "duration": "short",
        "file_type": "mp4",
        "sort": "name",
        "source": "tags",
    }
    assert selected(client, "video", params) == ids[:27]
    assert selected(client, "video", {"source": "recent", "sort": "recent"}) == []
    with client.app.state.db.write() as session:
        session.add(RecentEntry(kind="video", video_id=ids[3]))
    assert selected(client, "video", {"source": "recent", "sort": "recent"}) == [ids[3]]
    assert client.get("/api/v1/videos/selection", headers={"Authorization": ""}).status_code == 401
    assert (
        client.get("/api/v1/videos/selection", params={"directory_id": "gone"}).status_code == 404
    )
    with client.app.state.db.read() as session:
        assert (
            session.connection().exec_driver_sql("SELECT count(*) FROM playback_rounds").scalar()
            == 0
        )
        assert (
            session.connection().exec_driver_sql("SELECT count(*) FROM recent_entries").scalar()
            == 1
        )
    monkeypatch.setattr(catalog_selection, "MAX_SELECTION_ITEMS", 2)
    response = client.get("/api/v1/videos/selection", params=params)
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "selection_too_large"
    assert "ids" not in response.json()
    with client.app.state.db.write() as session:
        for root in session.scalars(select(Root)):
            root.enabled = False
    assert selected(client, "video") == []


def test_pack_selection_full_scope_read_state_and_typed_roots(library):
    client, media = library
    root = pack_root(client, media)
    from pathlib import Path

    for i in range(27):
        image(Path(root["path"]) / f"pack-{i:02d}" / "1.jpg")
    sync(client)
    items = packs(client, limit=200)["items"]
    ids = [p["id"] for p in items]
    label = pack_tag(client)
    response = client.patch(
        "/api/v1/pack-tag-links",
        json={"pack_ids": ids[:25], "tag_ids": [label["id"]], "request_id": "select-pack-links"},
    )
    assert response.status_code == 200
    with client.app.state.db.write() as session:
        session.add(PackProgress(pack_id=ids[2], completed=True))
    assert selected(
        client, "pack", {"search": "pack-", "tag_ids": [label["id"]], "read_state": "unread"}
    ) == [i for i in ids[:25] if i != ids[2]]
    assert selected(client, "pack", {"read_state": "completed"}) == [ids[2]]
    assert selected(client, "video") == []
    assert client.get("/api/v1/packs/selection", headers={"Authorization": ""}).status_code == 401
    assert client.get("/api/v1/packs/selection", params={"directory_id": "gone"}).status_code == 404
    with client.app.state.db.read() as session:
        assert (
            session.connection().exec_driver_sql("SELECT count(*) FROM pack_sessions").scalar() == 0
        )
        assert (
            session.connection().exec_driver_sql("SELECT count(*) FROM recent_entries").scalar()
            == 0
        )
    with client.app.state.db.write() as session:
        session.get(Root, root["id"]).enabled = False
    assert selected(client, "pack") == []
