"""Library-first scopes are snapshots; reads and prefetch never create history."""

import sqlite3
import uuid

from video_viewer.models import RecentEntry, Root

from .conftest import put, scan
from .test_file_operations import operation, trash
from .test_playback import create_round, move
from .test_tags import assign, tag


def begin(client, scope=None, **context):
    return create_round(client, "sequential", scope, membership="fixed", **context)


def entries(client, round):
    return client.get(f"/api/v1/rounds/{round['id']}/entries", params={"limit": 200}).json()[
        "items"
    ]


def opened(client, round, key=None):
    body = {
        "video_id": round["current"]["id"],
        "expected_revision": round["revision"],
        "request_id": key or str(uuid.uuid4()),
    }
    response = client.post(f"/api/v1/rounds/{round['id']}/opened", json=body)
    assert response.status_code == 200, response.text
    return response.json(), body


def reorder(client, round, order, key=None):
    body = {
        "order": order,
        "expected_revision": round["revision"],
        "request_id": key or str(uuid.uuid4()),
    }
    response = client.patch(f"/api/v1/rounds/{round['id']}/order", json=body)
    assert response.status_code == 200, response.text
    return response.json(), body


def test_search_directory_tags_and_attributes_freeze_all_pages(library, samples):
    client, media = library
    for i in range(28):
        put(samples / "h264.mov", media / "筛选目录" / f"item-{i:02d}.mov")
    put(samples / "h264.mov", media / "other" / "outside.mov")
    put(samples / "portrait.mp4", media / "筛选目录" / "different.mp4")
    scan(client)
    selected = client.get(
        "/api/v1/videos", params={"search": "筛选目录", "file_type": "MOV", "limit": 200}
    ).json()
    assert selected["total"] == 28
    a, b = tag(client, "A"), tag(client, "B")
    ids = [video["id"] for video in selected["items"]]
    assign(client, ids, [a["id"], b["id"]])
    root = client.get("/api/v1/roots").json()["items"][0]
    folder = next(
        item
        for item in client.get(
            "/api/v1/directories", params={"parent_id": root["directory_id"]}
        ).json()["items"]
        if item["name"] == "筛选目录"
    )
    scope = {
        "directory_id": folder["id"],
        "search": "筛选目录",
        "tag_ids": [a["id"], b["id"]],
        "orientation": "landscape",
        "duration": "short",
        "file_type": "MOV",
    }
    page = client.get(
        "/api/v1/videos",
        params=[
            *((k, v) for k, v in scope.items() if k != "tag_ids"),
            *(("tag_ids", value) for value in scope["tag_ids"]),
            ("limit", 24),
        ],
    ).json()
    assert len(page["items"]) == 24 and page["total"] == 28
    round, _ = begin(client, scope, source="tags", sort="name", anchor_video_id=ids[6])
    queue = entries(client, round)
    assert {item["video"]["id"] for item in queue} == set(ids)
    assert round["total"] == round["candidate_count"] == 28
    assert round["current"]["id"] == ids[6] and round["source"] == "tags"
    assert round["scope"]["search"] == "筛选目录" and round["membership"] == "fixed"
    # Absolute host mount prefixes are not user-facing search terms.
    assert client.get("/api/v1/videos", params={"search": str(media.parent)}).json()["total"] == 0


def test_tag_edits_deletion_new_files_and_root_policy_do_not_expand_fixed_scope(library, samples):
    client, media = library
    for name in ("a.mov", "b.mov", "outside.mov"):
        put(samples / "h264.mov", media / name)
    scan(client)
    videos = client.get("/api/v1/videos").json()["items"]
    label = tag(client, "Selected")
    ids = [video["id"] for video in videos[:2]]
    assign(client, ids, [label["id"]])
    round, _ = begin(client, {"tag_ids": [label["id"]]})
    assign(client, [ids[0]], [], "replace")
    assign(client, [videos[2]["id"]], [label["id"]])
    current = client.get("/api/v1/playback").json()
    assert current["id"] == round["id"] and current["current"]["id"] == ids[0]
    assert {item["video"]["id"] for item in entries(client, round)} == set(ids)
    deleted = client.request(
        "DELETE", f"/api/v1/tags/{label['id']}", json={"request_id": "delete-filter"}
    )
    assert deleted.status_code == 200 and deleted.json()["replacement_round_id"] is None
    put(samples / "h264.mov", media / "new.mov")
    scan(client)
    assert client.get("/api/v1/playback").json()["id"] == round["id"]
    assert client.get("/api/v1/playback").json()["total"] == 2
    with client.app.state.db.write() as session:
        root = session.get(Root, videos[0]["root_id"])
        root.enabled = False
    assert client.get("/api/v1/playback").json()["total"] == 0
    with client.app.state.db.write() as session:
        session.get(Root, videos[0]["root_id"]).enabled = True
    assert {item["video"]["id"] for item in entries(client, round)} == set(ids)
    assert client.get("/api/v1/playback").json()["candidate_count"] == 2


def test_reorder_keeps_members_selection_and_original_sequence_with_idempotency(library, samples):
    client, media = library
    for name in ("c.mov", "a.mov", "b.mov"):
        put(samples / "h264.mov", media / name)
    scan(client)
    round, _ = begin(client, sort="name")
    original = entries(client, round)
    selected = original[1]["video"]["id"]
    round = move(client, round, selected)
    assert round["sequence_revision"] == 0
    shuffled, body = reorder(client, round, "random", "shuffle")
    assert shuffled["id"] == round["id"] and shuffled["current"]["id"] == selected
    assert shuffled["revision"] > round["revision"]
    assert shuffled["sequence_revision"] == 1
    stale = client.get(f"/api/v1/rounds/{round['id']}/entries", params={"v": 0})
    assert stale.status_code == 409 and stale.json()["error"]["code"] == "round_order_changed"
    assert (
        client.get(f"/api/v1/rounds/{round['id']}/entries", params={"v": 1}).json()[
            "sequence_revision"
        ]
        == 1
    )
    assert {row["video"]["id"] for row in entries(client, shuffled)} == {
        row["video"]["id"] for row in original
    }
    retry = client.patch(f"/api/v1/rounds/{round['id']}/order", json=body)
    assert retry.json() == shuffled
    assert (
        client.patch(
            f"/api/v1/rounds/{round['id']}/order", json={**body, "order": "sequential"}
        ).status_code
        == 409
    )
    ordered, _ = reorder(client, shuffled, "sequential")
    assert ordered["sequence_revision"] == 2
    assert ordered["current"]["id"] == selected
    assert [row["video"]["id"] for row in entries(client, ordered)] == [
        row["video"]["id"] for row in original
    ]
    assert (
        client.patch(
            f"/api/v1/rounds/{round['id']}/position",
            json={"video_id": original[0]["video"]["id"], "expected_revision": round["revision"]},
        ).status_code
        == 409
    )
    final = move(client, ordered, original[-1]["video"]["id"])
    final = move(client, final, finish=True)
    assert final["sequence_revision"] == 2
    assert final["finished"] and client.get("/api/v1/playback").json()["id"] == round["id"]
    put(samples / "h264.mov", media / "added-after-entry.mov")
    scan(client)
    response = client.patch(
        f"/api/v1/rounds/{round['id']}/order",
        json={
            "order": "sequential",
            "expected_revision": final["revision"],
            "request_id": "restart-fixed",
            "restart": True,
        },
    )
    restarted = response.json()
    assert response.status_code == 200, response.text
    assert restarted["id"] == round["id"] and restarted["total"] == 3
    assert restarted["sequence_revision"] == 3
    assert restarted["current"]["id"] == original[0]["video"]["id"] and not restarted["finished"]


def test_read_only_connection_and_prefetch_do_not_create_rounds_or_recents(library, samples):
    client, media = library
    put(samples / "h264.mov", media / "one.mov")
    scan(client)
    assert client.get("/api/v1/playback", params={"create": "false"}).status_code == 404
    with client.app.state.db.read() as session:
        assert (
            session.connection().exec_driver_sql("SELECT count(*) FROM playback_rounds").scalar()
            == 0
        )
    round, _ = begin(client)
    client.get("/api/v1/videos")
    entries(client, round)
    client.get(round["current"]["thumbnail_url"])
    assert client.get("/api/v1/recent").json()["total"] == 0
    recorded, body = opened(client, round, "visible")
    assert client.post(f"/api/v1/rounds/{round['id']}/opened", json=body).json() == recorded
    assert client.get("/api/v1/recent").json()["total"] == 1
    with client.app.state.db.read() as session:
        assert (
            session.connection().exec_driver_sql("SELECT count(*) FROM recent_entries").scalar()
            == 1
        )
    assert (
        client.post(
            f"/api/v1/rounds/{round['id']}/opened", json={**body, "video_id": "other"}
        ).status_code
        == 409
    )


def test_recent_entry_scope_and_sequence_do_not_follow_later_history_updates(library, samples):
    client, media = library
    for name in ("a.mov", "b.mov", "never-opened.mov"):
        put(samples / "h264.mov", media / name)
    scan(client)
    library_round, _ = begin(client)
    queue = entries(client, library_round)
    opened(client, library_round)
    library_round = move(client, library_round, queue[1]["video"]["id"])
    opened(client, library_round)
    recent, _ = begin(client, source="recent", sort="recent")
    initial = [row["video"]["id"] for row in entries(client, recent)]
    assert initial == [queue[1]["video"]["id"], queue[0]["video"]["id"]]
    recent = move(client, recent, initial[1])
    opened(client, recent)
    assert [row["id"] for row in client.get("/api/v1/recent").json()["items"]] == initial[::-1]
    recent, _ = reorder(client, recent, "random")
    recent, _ = reorder(client, recent, "sequential")
    assert [row["video"]["id"] for row in entries(client, recent)] == initial
    assert recent["total"] == 2
    with client.app.state.db.write() as session:
        session.add(RecentEntry(kind="video", video_id=queue[2]["video"]["id"]))
    assert client.get("/api/v1/recent").json()["total"] == 3
    assert client.get("/api/v1/playback").json()["total"] == 2


def test_fixed_round_blocks_lossy_v1_backup_and_legacy_calls_remain_compatible(library, samples):
    client, media = library
    put(samples / "h264.mov", media / "one.mov")
    scan(client)
    legacy, _ = create_round(client)
    assert legacy["membership"] == "legacy" and "search" not in legacy["scope"]
    with client.app.state.db.read() as session:
        from video_viewer.backup_format import require_legacy_backup

        require_legacy_backup(session)
    begin(client, {"search": "one"})
    response = client.post("/api/v1/backups", json={"request_id": "v1-guard"})
    assert response.status_code == 409, response.text
    assert response.json()["error"]["code"] == "backup_upgrade_required"
    assert (
        client.post(
            "/api/v1/rounds", json={"request_id": "legacy-search", "scope": {"search": "one"}}
        ).status_code
        == 422
    )
    with sqlite3.connect(client.app.state.settings.data_dir / "library.sqlite3") as connection:
        assert connection.execute(
            "SELECT membership FROM playback_rounds WHERE id=?", (legacy["id"],)
        ).fetchone() == ("legacy",)


def test_fixed_undo_tracks_original_video_after_reorder_and_deleted_tag(
    library, samples, monkeypatch
):
    import random

    monkeypatch.setattr(random.SystemRandom, "shuffle", lambda self, items: items.reverse())
    client, media = library
    for name in ("a.mov", "b.mov", "c.mov"):
        put(samples / "h264.mov", media / name)
    scan(client)
    videos = client.get("/api/v1/videos").json()["items"]
    label = tag(client, "before-delete")
    assign(client, [row["id"] for row in videos], [label["id"]])
    round, _ = begin(client, {"tag_ids": [label["id"]]}, sort="name")
    original_id = round["current"]["id"]
    deleted, _ = trash(client, [original_id])
    round = client.get("/api/v1/playback").json()
    reorder(client, round, "random")
    client.request(
        "DELETE", f"/api/v1/tags/{label['id']}", json={"request_id": "delete-after-trash"}
    )
    undo, _ = operation(client, f"/api/v1/operations/{deleted['id']}/undo", {})
    assert undo["result"]["playback_restored"] is True, undo
    assert client.get("/api/v1/playback").json()["current"]["id"] == original_id
