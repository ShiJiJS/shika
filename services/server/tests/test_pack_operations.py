"""LF6 logical pack operations over authenticated HTTP, SQLite and disposable media."""

import hashlib
import threading
import time
from pathlib import Path

import pytest
from sqlalchemy import func, select

from video_viewer.models import (
    ImagePack,
    PackTrashItem,
)
from video_viewer.pack_scanner import PackScanner

from .conftest import connect
from .test_media_types import pack_root, pack_tag
from .test_packs import image, packs, sync
from .test_reading import create, opened, progress_body, setup


def wait(client, identity):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        response = client.get(f"/api/v1/pack-operations/{identity}")
        assert response.status_code == 200, response.text
        task = response.json()
        if task["status"] not in ("queued", "running"):
            return task
        time.sleep(0.01)
    raise AssertionError(task)


def command(client, path, body, status=202):
    response = client.post("/api/v1/" + path, json=body)
    assert response.status_code == status, response.text
    return response.json()


def trash(client, ids, key="trash", **extra):
    value = command(client, "packs/trash", {"pack_ids": ids, "request_id": key, **extra})
    return wait(client, value["id"])


def restore(client, ids, key="restore"):
    value = command(client, "pack-trash/restore", {"trash_ids": ids, "request_id": key})
    return wait(client, value["id"])


def undo(client, identity, key="undo", status=202):
    value = command(client, f"pack-operations/{identity}/undo", {"request_id": key}, status)
    return wait(client, value["id"]) if status == 202 else value


def scene(value, state):
    return {
        "session_id": value["id"],
        "expected_session_revision": value["revision"],
        "pack_id": value["current"]["id"],
        "content_version": state["content_version"],
        "expected_progress_revision": state["revision"],
    }


def tree(root):
    return {
        str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in root.rglob("*")
        if p.is_file()
    }


def state(client, identity):
    with client.app.state.db.read() as db:
        pack = db.get(ImagePack, identity)
        return pack.status, pack.generation, pack.content_version


def test_real_tree_roundtrip_preserves_pages_tags_progress_preferences_and_recent(library):
    client, media = library
    root = pack_root(client, media)
    base = Path(root["path"]) / "whole"
    image(base / "1.png")
    image(base / "nested/2.jpg", color="blue")
    (base / "notes.txt").write_text("retain attachment")
    sync(client)
    before = tree(media)
    pack = packs(client)["items"][0]
    identity = pack["id"]
    tag = pack_tag(client)
    assert (
        client.patch(
            "/api/v1/pack-tag-links",
            json={"request_id": "assign", "pack_ids": [identity], "tag_ids": [tag["id"]]},
        ).status_code
        == 200
    )
    reading = create(client)
    saved = opened(client, reading)
    response = client.patch(
        f"/api/v1/packs/{identity}/progress", json=progress_body(reading, saved)
    )
    assert response.status_code == 200, response.text
    saved = response.json()
    before_state = state(client, identity)
    task = trash(client, [identity])
    assert task["status"] == "completed", task
    assert task["result"]["reading_transition"] is None
    assert packs(client)["total"] == 0
    assert client.get("/api/v1/recent", params={"kind": "pack"}).json()["total"] == 0
    assert tree(media) == before
    listing = client.get("/api/v1/pack-trash").json()
    assert listing["total"] == 1 and listing["items"][0]["page_count"] == 2
    selected = client.get("/api/v1/pack-trash/selection").json()
    assert selected == {"kind": "pack-trash", "ids": [listing["items"][0]["id"]], "total": 1}
    result = restore(client, selected["ids"])
    assert result["result"]["succeeded"] == 1
    assert state(client, identity) == ("available", before_state[1] + 2, before_state[2])
    assert packs(client, tag_ids=tag["id"])["total"] == 1
    assert client.get("/api/v1/recent", params={"kind": "pack"}).json()["total"] == 1
    current = client.get(f"/api/v1/pack-sessions/{reading['id']}").json()["resume"]
    assert current["page"]["id"] == saved["page"]["id"]
    assert current["offset_ratio"] == saved["offset_ratio"] == 0.37
    assert current["preferences"] == saved["preferences"]
    assert tree(media) == before
    # A logical restore does not regrant the old opened lease.
    stale = client.patch(
        f"/api/v1/packs/{identity}/progress", json=progress_body(reading, saved, request_id="stale")
    )
    assert stale.status_code == 422
    assert stale.json()["error"]["code"] == "pack_not_opened"


def test_wrong_types_atomic_validation_and_idempotency(library):
    client, media = library
    _, ids = setup(client, media)

    def count():
        return len(client.get("/api/v1/tasks").json()["items"])

    before = count()
    command(client, "packs/trash", {"pack_ids": [ids[0], "unknown"], "request_id": "bad"}, 404)
    assert count() == before and state(client, ids[0])[0] == "available"
    command(client, "pack-trash/restore", {"trash_ids": [ids[0]], "request_id": "wrong"}, 404)
    original = trash(client, [ids[0], ids[0]])
    assert trash(client, [ids[0]])["id"] == original["id"]
    command(client, "packs/trash", {"pack_ids": [ids[1]], "request_id": "trash"}, 409)
    assert client.get("/api/v1/pack-file-requests/trash").json()["id"] == original["id"]
    assert client.get("/api/v1/pack-file-requests/unknown").status_code == 404
    assert "pack_logical_trash" in client.get("/api/v1/info").json()["capabilities"]


def test_quick_trash_fixed_range_and_undo_exact_reading_state(library):
    client, media = library
    _, ids = setup(client, media, count=27)
    value = create(client)
    saved = opened(client, value)
    second = client.get(f"/api/v1/packs/{ids[0]}/pages").json()["items"][1]
    response = client.patch(
        f"/api/v1/packs/{ids[0]}/progress", json=progress_body(value, saved, page_id=second["id"])
    )
    assert response.status_code == 200, response.text
    saved = response.json()
    task = trash(client, [ids[0]], reading=scene(value, saved))
    assert task["result"]["succeeded"] == 1, task
    transition = task["result"]["reading_transition"]
    assert transition["cursor"] == 1 and transition["pack_id"] == ids[1]
    assert not transition["finished"]
    current = client.get(f"/api/v1/pack-sessions/{value['id']}").json()
    assert current["candidate_count"] == 27 and current["available_count"] == 26
    assert current["current"]["id"] == ids[1]
    assert client.get("/api/v1/recent", params={"kind": "pack"}).json()["total"] == 0
    result = undo(client, task["id"])
    assert result["result"]["reading_restored"] is True, result
    restored = client.get(f"/api/v1/pack-sessions/{value['id']}").json()
    assert restored["cursor"] == 0 and restored["current"]["id"] == ids[0]
    assert restored["revision"] == transition["revision"] + 1
    assert restored["resume"]["page"]["id"] == second["id"]
    assert restored["resume"]["offset_ratio"] == 0.37
    assert restored["resume"]["preferences"] == saved["preferences"]


@pytest.mark.parametrize("count", [1, 3])
def test_quick_trash_tail_finishes_without_wrapping(library, count):
    client, media = library
    _, ids = setup(client, media, count=count)
    value = create(client, anchor_pack_id=ids[-1])
    saved = opened(client, value)
    result = trash(client, [ids[-1]], reading=scene(value, saved))["result"]
    assert result["reading_transition"]["finished"] is True
    assert result["reading_transition"]["pack_id"] is None
    assert undo(client, result["operation_id"])["result"]["reading_restored"] is True


def test_undo_does_not_replace_new_reading_session(library):
    client, media = library
    _, ids = setup(client, media)
    value = create(client)
    saved = opened(client, value)
    task = trash(client, [ids[0]], reading=scene(value, saved))
    new = create(client, request_id="new")
    result = undo(client, task["id"])
    assert result["result"]["succeeded"] == 1
    assert result["result"]["reading_restored"] is False
    current = client.get(f"/api/v1/pack-sessions/{new['id']}").json()
    assert current["revision"] == new["revision"] and current["current"]["id"] == ids[1]


def test_undo_expiry_and_latest_accepted_intent(library, monkeypatch):
    client, media = library
    _, ids = setup(client, media, count=3)
    ops = client.app.state.pack_files
    clock = [100.0]
    ops.clock = lambda: clock[0]
    first = trash(client, [ids[0]])
    clock[0] = 108.01
    assert undo(client, first["id"], status=409)["error"]["code"] == "undo_expired"
    clock[0] = 107
    enqueue = ops.enqueue
    monkeypatch.setattr(ops, "enqueue", lambda _: None)
    second = command(client, "packs/trash", {"pack_ids": [ids[1]], "request_id": "second"})
    assert second["status"] == "queued"
    # Replaying first's key cannot make it the latest accepted intent again.
    assert trash(client, [ids[0]])["id"] == first["id"]
    assert undo(client, first["id"], key="old", status=409)["error"]["code"] == "stale_delete"
    monkeypatch.setattr(ops, "enqueue", enqueue)
    enqueue(second["id"])
    assert wait(client, second["id"])["status"] == "completed"
    monkeypatch.setattr(ops, "enqueue", lambda _: None)
    accepted = command(client, f"pack-operations/{second['id']}/undo", {"request_id": "accepted"})
    clock[0] = 300
    monkeypatch.setattr(ops, "enqueue", enqueue)
    enqueue(accepted["id"])
    assert wait(client, accepted["id"])["result"]["succeeded"] == 1


def test_pending_reservations_root_edits_and_readonly_receipts(library, monkeypatch):
    client, media = library
    root, ids = setup(client, media)
    ops = client.app.state.pack_files
    monkeypatch.setattr(ops, "enqueue", lambda _: None)
    first = command(client, "packs/trash", {"pack_ids": [ids[0]], "request_id": "first"})
    duplicate = command(client, "packs/trash", {"pack_ids": [ids[0]], "request_id": "compete"})
    ops.run(duplicate["id"])
    assert wait(client, duplicate["id"])["error"] == "operation_busy"
    assert (
        client.put(
            f"/api/v1/roots/{root['id']}",
            json={"name": "disabled", "path": root["path"], "enabled": False},
        ).status_code
        == 409
    )
    db = client.app.state.db
    db.maintenance_task, db.maintenance_owner = "restore", None
    try:
        for _ in range(2):
            assert client.get("/api/v1/pack-file-requests/first").json()["status"] == "queued"
            assert (
                command(client, "packs/trash", {"pack_ids": [ids[0]], "request_id": "first"})["id"]
                == first["id"]
            )
        assert client.get("/api/v1/pack-file-requests/absent").status_code == 404
    finally:
        db.maintenance_task = None
    assert state(client, ids[0])[0] == "available"
    ops.run(first["id"])
    assert wait(client, first["id"])["result"]["succeeded"] == 1


def test_restore_partial_retry_does_not_repeat_successes_and_disabled_root_stays_hidden(library):
    client, media = library
    root, ids = setup(client, media)
    original = trash(client, ids)
    records = {item["pack_id"]: item["trash_id"] for item in original["result"]["items"]}
    restore(client, [records[ids[0]]], "earlier")
    result = restore(client, list(records.values()))
    assert result["result"]["partial"] is True and result["result"]["succeeded"] == 1
    before = state(client, ids[1])
    retry = command(client, f"pack-operations/{result['id']}/retry", {"request_id": "retry"})
    assert wait(client, retry["id"])["result"]["succeeded"] == 1
    assert state(client, ids[1]) == before
    again = trash(client, ids, "again")
    assert (
        client.put(
            f"/api/v1/roots/{root['id']}",
            json={"name": "disabled", "path": root["path"], "enabled": False},
        ).status_code
        == 200
    )
    restored = restore(client, [i["trash_id"] for i in again["result"]["items"]], "disabled")
    assert restored["result"]["succeeded"] == 2
    assert packs(client)["total"] == 0
    assert all(state(client, identity)[0] == "available" for identity in ids)


@pytest.mark.parametrize("checkpoint", ["queued", "logical_committed"])
def test_restart_recovers_without_repeating_marks_or_advancing_twice(
    environment, checkpoint, monkeypatch
):
    settings, media = environment
    client, token = connect(settings)
    try:
        _, ids = setup(client, media)
        value = create(client)
        saved = opened(client, value)
        ops = client.app.state.pack_files
        if checkpoint == "queued":
            monkeypatch.setattr(ops, "enqueue", lambda _: None)
        else:

            def fault(phase, _):
                if phase == checkpoint:
                    raise InterruptedError()

            ops.fault_hook = fault
        task = command(
            client,
            "packs/trash",
            {"request_id": "recover", "pack_ids": [ids[0]], "reading": scene(value, saved)},
        )
        if checkpoint != "queued":
            interrupted = wait(client, task["id"])
            assert interrupted["status"] == "interrupted"
        identity = task["id"]
    finally:
        client.__exit__(None, None, None)
    client, _ = connect(settings, token=token)
    try:
        recovered = wait(client, identity)
        assert recovered["result"]["succeeded"] == 1, recovered
        assert state(client, ids[0])[1] == 1
        current = client.get(f"/api/v1/pack-sessions/{value['id']}").json()
        assert current["revision"] == value["revision"] + 1
        assert current["current"]["id"] == ids[1]
        with client.app.state.db.read() as db:
            assert db.scalar(select(func.count()).select_from(PackTrashItem)) == 1
        expiry = recovered["result"]["undo_expires_at"]
        assert (
            client.get("/api/v1/pack-file-requests/recover").json()["result"]["undo_expires_at"]
            == expiry
        )
    finally:
        client.__exit__(None, None, None)


def test_scan_late_publication_cannot_resurrect_trashed_pack(library, monkeypatch):
    client, media = library
    root = pack_root(client, media)
    image(Path(root["path"]) / "race/1.png")
    sync(client)
    identity = packs(client)["items"][0]["id"]
    ready, release = threading.Event(), threading.Event()
    original = PackScanner.read_pack

    def delayed(self, *args):
        result = original(self, *args)
        ready.set()
        assert release.wait(10)
        return result

    monkeypatch.setattr(PackScanner, "read_pack", delayed)
    response = client.post("/api/v1/scans")
    assert response.status_code == 202
    try:
        assert ready.wait(10)
        task = trash(client, [identity])
        assert task["result"]["succeeded"] == 1
        trashed = state(client, identity)
    finally:
        release.set()
    scan_id = response.json()["id"]
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        result = client.get(f"/api/v1/tasks/{scan_id}").json()
        if result["status"] not in ("queued", "running"):
            break
        time.sleep(0.01)
    assert result["status"] == "completed", result
    assert result["result"]["packs"]["protected_packs"] >= 1
    assert state(client, identity) == trashed
    assert packs(client)["total"] == 0


def test_quick_cleanup_requires_actual_open_and_rechecks_queued_progress(library, monkeypatch):
    client, media = library
    _, ids = setup(client, media)
    value = create(client)
    command(
        client,
        "packs/trash",
        {"request_id": "unopened", "pack_ids": [ids[0]], "reading": scene(value, value["resume"])},
        422,
    )
    saved = opened(client, value)
    command(
        client,
        "packs/trash",
        {"request_id": "many", "pack_ids": ids, "reading": scene(value, saved)},
        422,
    )
    ops = client.app.state.pack_files
    monkeypatch.setattr(ops, "enqueue", lambda _: None)
    queued = command(
        client,
        "packs/trash",
        {"request_id": "queued", "pack_ids": [ids[0]], "reading": scene(value, saved)},
    )
    assert (
        client.patch(
            f"/api/v1/packs/{ids[0]}/progress", json=progress_body(value, saved)
        ).status_code
        == 200
    )
    ops.run(queued["id"])
    result = wait(client, queued["id"])
    assert result["status"] == "failed" and result["error"] == "pack_changed"
    assert result["result"]["reading_transition"] is None
    assert state(client, ids[0])[0] == "available"
    current = client.get(f"/api/v1/pack-sessions/{value['id']}").json()
    assert current["cursor"] == value["cursor"] and current["revision"] == value["revision"]


def test_queued_undo_is_fenced_by_new_delete_and_historical_work_never_executes(
    library, monkeypatch
):
    from video_viewer.models import PackFileOperation

    client, media = library
    _, ids = setup(client, media)
    first = trash(client, [ids[0]])
    ops = client.app.state.pack_files
    monkeypatch.setattr(ops, "enqueue", lambda _: None)
    queued_undo = command(
        client, f"pack-operations/{first['id']}/undo", {"request_id": "queued-undo"}
    )
    historical = command(client, "packs/trash", {"request_id": "history", "pack_ids": [ids[1]]})
    with client.app.state.db.write() as db:
        db.get(PackFileOperation, historical["id"]).historical = True
    ops.run(queued_undo["id"])
    assert wait(client, queued_undo["id"])["error"] == "stale_delete"
    assert state(client, ids[0])[0] == "trash"
    called = []
    monkeypatch.setattr(ops, "enqueue", called.append)
    ops.start()
    assert historical["id"] not in called
    ops.run(historical["id"])
    assert state(client, ids[1])[0] == "available"
    assert client.get("/api/v1/pack-file-requests/history").json()["status"] == "queued"
    assert not called


def test_undo_restores_content_without_overwriting_newer_progress_or_preferences(library):
    from video_viewer.models import PackPreferences, PackProgress

    client, media = library
    _, ids = setup(client, media)
    value = create(client)
    saved = opened(client, value)
    task = trash(client, [ids[0]], reading=scene(value, saved))
    with client.app.state.db.write() as db:
        progress = db.get(PackProgress, ids[0])
        progress.offset_ratio, progress.revision = 0.81, progress.revision + 1
        prefs = db.get(PackPreferences, ids[0])
        prefs.mode, prefs.revision = "vertical", prefs.revision + 1
    result = undo(client, task["id"])
    assert result["result"]["succeeded"] == 1 and not result["result"]["reading_restored"]
    with client.app.state.db.read() as db:
        assert db.get(PackProgress, ids[0]).offset_ratio == 0.81
        assert db.get(PackPreferences, ids[0]).mode == "vertical"
    current = client.get(f"/api/v1/pack-sessions/{value['id']}").json()
    assert current["current"]["id"] == ids[1]


def test_random_fixed_range_skips_unavailable_members_and_does_not_refilter(library):
    from video_viewer.models import Root

    client, media = library
    root, ids = setup(client, media, count=27)
    label = pack_tag(client)
    client.patch(
        "/api/v1/pack-tag-links",
        json={"request_id": "link", "pack_ids": ids, "tag_ids": [label["id"]]},
    )
    value = create(client, order="random", source="tags", scope={"tag_ids": [label["id"]]})
    entries = client.get(
        f"/api/v1/pack-sessions/{value['id']}/entries", params={"limit": 100}
    ).json()["items"]
    fixed_ids = [row["pack"]["id"] for row in entries]
    saved = opened(client, value)
    client.patch(
        "/api/v1/pack-tag-links",
        json={"request_id": "unlink", "pack_ids": ids, "tag_ids": [label["id"]], "mode": "remove"},
    )
    with client.app.state.db.write() as db:
        db.get(ImagePack, fixed_ids[1]).status = "missing"
        assert db.get(Root, root["id"]).enabled
    task = trash(client, [fixed_ids[0]], reading=scene(value, saved))
    assert task["result"]["reading_transition"]["pack_id"] == fixed_ids[2]
    assert task["result"]["reading_transition"]["cursor"] == 2
    current = client.get(f"/api/v1/pack-sessions/{value['id']}").json()
    assert current["candidate_count"] == 27 and current["available_count"] == 25


def test_cross_page_trash_selection_is_complete_and_escaped_search_is_literal(library):
    client, media = library
    _, ids = setup(client, media, count=27)
    task = trash(client, ids)
    assert task["result"]["succeeded"] == 27
    first = client.get("/api/v1/pack-trash", params={"limit": 24}).json()
    second = client.get("/api/v1/pack-trash", params={"limit": 24, "offset": 24}).json()
    assert first["total"] == second["total"] == 27 and len(second["items"]) == 3
    selected = client.get("/api/v1/pack-trash/selection").json()
    assert len(set(selected["ids"])) == selected["total"] == 27
    assert client.get("/api/v1/pack-trash/selection", params={"search": "%"}).json()["total"] == 0
    assert restore(client, selected["ids"])["result"]["succeeded"] == 27
    assert packs(client)["total"] == 27
