"""Real HTTP/SQLite/descriptor previews over disposable generated pack trees."""

import os
import sqlite3
import threading
import time
from pathlib import Path

import pytest
from sqlalchemy import func, select

from video_viewer.models import (
    ImagePack,
    PackFileOperation,
    PackFileStep,
    PackPurgeEntry,
    PackPurgePlan,
    Root,
    Task,
)
from video_viewer.pack_purge_manifest import digest_json

from .conftest import connect
from .test_media_types import pack_root, pack_tag
from .test_pack_operations import command, restore, trash, tree
from .test_packs import image, packs, sync


def fixture(client, media, count=1):
    root = pack_root(client, media)
    for number in range(count):
        folder = Path(root["path"]) / f"pack-{number}"
        image(folder / "1.png")
        image(folder / "nested/2.jpg", color="blue")
        (folder / "notes.txt").write_text("retain attachment")
        (folder / "empty").mkdir()
    sync(client)
    catalog = packs(client)["items"]
    assert trash(client, [p["id"] for p in catalog])["result"]["succeeded"] == count
    rows = client.get("/api/v1/pack-trash").json()["items"]
    return root, catalog, rows


def prepare(client, ids, key="prepare", status=202):
    return command(client, "pack-purge-plans", {"trash_ids": ids, "request_id": key}, status)


def wait(client, identity):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        response = client.get(f"/api/v1/pack-purge-plans/{identity}")
        assert response.status_code == 200, response.text
        task = response.json()
        if task["status"] not in ("queued", "running"):
            return task
        time.sleep(0.01)
    raise AssertionError(task)


def test_precise_persisted_manifest_files_pagination_attachments_and_readonly(library):
    client, media = library
    root, catalog, rows = fixture(client, media)
    before = tree(media)
    plan = wait(client, prepare(client, [rows[0]["id"]])["id"])
    assert plan["status"] == "completed" and plan["phase"] == "ready" and plan["ready"]
    assert plan["result"]["image_count"] == 2
    assert plan["result"]["failed"] == 0
    assert plan["items"][0]["retained_entries"] == 1
    endpoint = f"/api/v1/pack-purge-plans/{plan['id']}/files"
    first = client.get(endpoint, params={"trash_id": rows[0]["id"], "limit": 1}).json()
    second = client.get(
        endpoint, params={"trash_id": rows[0]["id"], "limit": 1, "offset": 1}
    ).json()
    assert first["total"] == 2 and first["offset"] == 0 and first["limit"] == 1
    files = first["items"] + second["items"]
    assert [p["relative_path"] for p in files] == ["1.png", "nested/2.jpg"]
    assert all(p["sha256"] == before[str(Path(p["path"]).relative_to(media))] for p in files)
    assert sum(p["size"] for p in files) == plan["result"]["image_bytes"]
    assert client.get(endpoint, params={"trash_id": "other"}).status_code == 404
    assert client.get(endpoint, params={"trash_id": rows[0]["id"], "offset": -1}).status_code == 422
    assert client.get(endpoint, params={"trash_id": rows[0]["id"], "limit": 201}).status_code == 422
    assert tree(media) == before
    with client.app.state.db.read() as db:
        stored = db.scalar(select(PackPurgeEntry).where(PackPurgeEntry.plan_id == plan["id"]))
        assert stored.digest == digest_json(stored.manifest) == plan["items"][0]["digest"]
        assert stored.manifest["tree"]["notes.txt"]["kind"] == "file"
        assert stored.manifest["tree"]["empty"]["kind"] == "directory"
        assert stored.source["content_version"] == catalog[0]["content_version"]
        assert db.get(ImagePack, catalog[0]["id"]).status == "trash"
        assert db.scalar(select(func.count()).select_from(PackFileOperation)) == 1
        assert db.scalar(select(func.count()).select_from(PackFileStep)) == 1
    assert client.get("/api/v1/pack-trash").json()["total"] == 1
    # Preview capability does not advertise or expose a permanent-delete command.
    capabilities = client.get("/api/v1/info").json()["capabilities"]
    assert "pack_purge_preview" in capabilities and "pack_permanent_delete" not in capabilities
    assert client.post("/api/v1/pack-trash/permanent", json={}).status_code == 404
    assert root["path"] in str(files[0]["path"])


def test_request_receipt_idempotency_conflict_and_atomic_wrong_type(library, monkeypatch):
    client, media = library
    _, catalog, rows = fixture(client, media, 2)
    plans = client.app.state.pack_purge_plans
    monkeypatch.setattr(plans, "enqueue", lambda _: None)
    ids = [row["id"] for row in rows]
    first = prepare(client, ids)
    assert first["status"] == "queued"
    assert prepare(client, ids[::-1] + ids)["id"] == first["id"]
    assert prepare(client, ids[:1], status=409)["error"]["code"] == "idempotency_conflict"
    receipt = client.get("/api/v1/pack-purge-requests/prepare").json()
    assert receipt["server_time"] >= first["server_time"]
    assert {k: v for k, v in receipt.items() if k != "server_time"} == {
        k: v for k, v in first.items() if k != "server_time"
    }
    assert client.get("/api/v1/pack-purge-requests/missing").status_code == 404
    with client.app.state.db.read() as db:
        count = db.scalar(select(func.count()).select_from(Task))
    prepare(client, [ids[0], catalog[0]["id"]], key="wrong-type", status=404)
    with client.app.state.db.read() as db:
        assert db.scalar(select(func.count()).select_from(Task)) == count
    for path, method in [
        ("pack-purge-plans", "post"),
        (f"pack-purge-plans/{first['id']}", "get"),
        ("pack-purge-requests/prepare", "get"),
        (f"pack-purge-plans/{first['id']}/files?trash_id={ids[0]}", "get"),
    ]:
        response = getattr(client, method)("/api/v1/" + path, headers={"Authorization": ""})
        assert response.status_code == 401


@pytest.mark.parametrize(
    "change,code",
    [
        ("replace-image", "image_changed"),
        ("append", "image_changed"),
        ("touch", "image_changed"),
        ("new-image", "unindexed_image"),
        ("missing-image", "indexed_image_missing"),
        ("replace-directory", "pack_changed"),
        ("image-link", "ambiguous_pack_entry"),
        ("fifo", "ambiguous_pack_entry"),
    ],
)
def test_changes_or_ambiguity_refuse_ready_manifest_without_file_writes(library, change, code):
    client, media = library
    root, _, rows = fixture(client, media)
    base = Path(root["path"]) / "pack-0"
    file = base / "1.png"
    if change == "replace-image":
        replacement = base / "replacement.tmp"
        replacement.write_bytes(file.read_bytes())
        os.replace(replacement, file)
    elif change == "append":
        with file.open("ab") as target:
            target.write(b"changed")
    elif change == "touch":
        info = file.stat()
        os.utime(file, ns=(info.st_atime_ns, info.st_mtime_ns + 1_000_000))
    elif change == "new-image":
        image(base / "new.png")
    elif change == "missing-image":
        file.unlink()
    elif change == "replace-directory":
        base.rename(base.with_name("original"))
        image(file)
        image(base / "nested/2.jpg", color="blue")
    elif change == "image-link":
        file.unlink()
        file.symlink_to(base / "nested/2.jpg")
    elif change == "fifo":
        os.mkfifo(base / "pipe")
    before = tree(media) if change != "fifo" else None
    result = wait(client, prepare(client, [rows[0]["id"]])["id"])
    assert result["status"] == "failed" and not result["ready"] and result["digest"] is None
    assert result["items"][0]["error"] == code, result
    assert result["result"]["failed"] == 1 and result["result"]["image_count"] == 0
    assert (
        client.get(
            f"/api/v1/pack-purge-plans/{result['id']}/files", params={"trash_id": rows[0]["id"]}
        ).status_code
        == 409
    )
    if before is not None:
        assert tree(media) == before
    else:
        assert file.exists() and (base / "pipe").exists()


@pytest.mark.parametrize("phase", ["purge_page_fingerprinted", "purge_pack_fingerprinted"])
def test_change_during_fingerprint_cannot_publish_old_snapshot(library, phase):
    client, media = library
    root, _, rows = fixture(client, media)
    base = Path(root["path"]) / "pack-0"
    changed = []

    def hook(current, _):
        if current == phase and not changed:
            changed.append(True)
            with (base / "1.png").open("ab") as target:
                target.write(b"during preparation")

    client.app.state.pack_purge_plans.fault_hook = hook
    result = wait(client, prepare(client, [rows[0]["id"]])["id"])
    assert changed and result["status"] == "failed" and result["digest"] is None
    assert result["items"][0]["error"] in ("image_changed", "pack_changed")
    assert (base / "notes.txt").read_text() == "retain attachment"


def test_metadata_restore_during_preparation_rejects_stale_manifest(library):
    client, media = library
    _, _, rows = fixture(client, media)
    changed = []
    before = tree(media)

    def hook(phase, _):
        if phase == "purge_before_manifest_commit" and not changed:
            changed.append(True)
            assert restore(client, [rows[0]["id"]])["result"]["succeeded"] == 1

    client.app.state.pack_purge_plans.fault_hook = hook
    result = wait(client, prepare(client, [rows[0]["id"]])["id"])
    assert result["status"] == "failed" and result["digest"] is None
    assert result["items"][0]["error"] == "stale_pack_state"
    assert tree(media) == before


def test_background_hash_has_no_database_write_lock_and_queries_do_not_enqueue(library):
    client, media = library
    _, _, rows = fixture(client, media)
    plans = client.app.state.pack_purge_plans
    reached, release = threading.Event(), threading.Event()

    def hook(phase, _):
        if phase == "purge_page_fingerprinted" and not reached.is_set():
            reached.set()
            assert release.wait(5)

    plans.fault_hook = hook
    first = prepare(client, [rows[0]["id"]])
    try:
        assert reached.wait(5)
        assert client.get("/api/v1/info").status_code == 200
        assert pack_tag(client, name="while preparing")["name"] == "while preparing"
        receipt = client.get("/api/v1/pack-purge-requests/prepare").json()
        assert receipt["status"] == "running" and not receipt["ready"]
        assert prepare(client, [rows[0]["id"]])["id"] == first["id"]
        assert len(plans.futures) == 1
    finally:
        release.set()
    assert wait(client, first["id"])["ready"]


def test_expiry_is_server_based_and_receipt_does_not_refresh_or_rebuild(library):
    client, media = library
    _, _, rows = fixture(client, media)
    plans = client.app.state.pack_purge_plans
    clock = [100.0]
    plans.clock = lambda: clock[0]
    result = wait(client, prepare(client, [rows[0]["id"]])["id"])
    assert result["ready"] and result["expires_at"] == 1000
    clock[0] = 1000.01
    expired = client.get("/api/v1/pack-purge-requests/prepare").json()
    assert expired["status"] == "completed" and not expired["ready"]
    assert expired["digest"] == result["digest"] and expired["expires_at"] == 1000
    assert prepare(client, [rows[0]["id"]])["expires_at"] == 1000


@pytest.mark.parametrize("state", ["queued", "interrupted", "ready"])
def test_restart_resumes_only_unfinished_readonly_plans_and_preserves_ready(
    environment, monkeypatch, state
):
    settings, media = environment
    first, token = connect(settings)
    second = None
    try:
        _, _, rows = fixture(first, media)
        plans = first.app.state.pack_purge_plans
        if state != "ready":
            monkeypatch.setattr(plans, "enqueue", lambda _: None)
        original = prepare(first, [rows[0]["id"]])
        if state == "ready":
            original = wait(first, original["id"])
        if state == "interrupted":
            with first.app.state.db.write() as db:
                task = db.get(Task, original["id"])
                task.status, task.error = "interrupted", "preview_interrupted"
                row = db.scalar(
                    select(PackPurgeEntry).where(PackPurgeEntry.plan_id == original["id"])
                )
                row.manifest, row.digest = {"bad": "partial old process"}, "not-a-real-digest"
        before = tree(media)
        first.__exit__(None, None, None)
        first = None
        second, _ = connect(settings, token=token)
        result = wait(second, original["id"])
        assert result["ready"] and result["result"]["image_count"] == 2
        assert second.get("/api/v1/pack-purge-requests/prepare").json()["id"] == original["id"]
        assert tree(media) == before
        if state == "ready":
            assert result["digest"] == original["digest"]
            assert result["expires_at"] == original["expires_at"]
            assert not second.app.state.pack_purge_plans.futures
    finally:
        if first:
            first.__exit__(None, None, None)
        if second:
            second.__exit__(None, None, None)


def test_failed_pack_does_not_publish_a_partially_ready_plan(library):
    client, media = library
    root, _, rows = fixture(client, media, 2)
    image(Path(root["path"]) / "pack-1/new.png")
    result = wait(client, prepare(client, [row["id"] for row in rows])["id"])
    assert result["status"] == "failed" and result["digest"] is None and not result["ready"]
    assert result["result"]["succeeded"] == result["result"]["failed"] == 1
    assert result["result"]["image_count"] == 2
    assert sum(bool(row["digest"]) for row in result["items"]) == 1


def test_0009_upgrade_keeps_existing_tables_byte_values_and_adds_only_preview_tables(environment):
    from alembic import command as migrate
    from alembic.config import Config

    from video_viewer.db import Database

    settings, media = environment
    client, _ = connect(settings)
    try:
        fixture(client, media)
    finally:
        client.__exit__(None, None, None)
    db = Database(settings.data_dir)
    config = Config(str(Path(__file__).parents[1] / "alembic.ini"))
    config.set_main_option("script_location", str(Path(__file__).parents[1] / "migrations"))
    with db.engine.begin() as connection:
        config.attributes["connection"] = connection
        migrate.downgrade(config, "0009")
    with sqlite3.connect(db.path) as connection:
        connection.execute("INSERT INTO settings VALUES ('keep', 'old value')")
        tables = [
            row[0]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name!='alembic_version'"
            )
        ]
        before = {name: connection.execute(f'SELECT * FROM "{name}"').fetchall() for name in tables}
    db.migrate()
    with sqlite3.connect(db.path) as connection:
        assert {
            name: connection.execute(f'SELECT * FROM "{name}"').fetchall() for name in tables
        } == before
        assert connection.execute("SELECT version_num FROM alembic_version").fetchone() == ("0010",)
        assert connection.execute("PRAGMA foreign_key_check").fetchall() == []
        for name in ["pack_purge_plans", "pack_purge_entries"]:
            assert connection.execute(f'SELECT COUNT(*) FROM "{name}"').fetchone() == (0,)
    assert db.last_migration_snapshot is not None
    db.close()


@pytest.mark.parametrize(
    "change,code",
    [
        ("outside-path", "image_outside_pack"),
        ("traversal", "image_outside_pack"),
        ("forged-hash", "image_changed"),
        ("root-disabled", "root_unavailable"),
    ],
)
def test_index_and_authority_changes_are_not_sufficient_deletion_evidence(
    library, monkeypatch, change, code
):
    from video_viewer.models import PackPage

    client, media = library
    root, catalog, rows = fixture(client, media)
    plans = client.app.state.pack_purge_plans
    enqueue = plans.enqueue
    monkeypatch.setattr(plans, "enqueue", lambda _: None)
    if change in ("outside-path", "traversal", "forged-hash"):
        with client.app.state.db.write() as db:
            page = db.scalar(select(PackPage).where(PackPage.pack_id == catalog[0]["id"]))
            if change == "outside-path":
                page.path = str(media / "outside.png")
            elif change == "traversal":
                page.relative_path = "../outside.png"
            else:
                page.sha256 = "0" * 64
    result = prepare(client, [rows[0]["id"]])
    if change == "root-disabled":
        with client.app.state.db.write() as db:
            db.get(Root, root["id"]).enabled = False
    before = tree(media)
    enqueue(result["id"])
    result = wait(client, result["id"])
    assert result["status"] == "failed" and result["items"][0]["error"] == code
    assert not result["ready"] and result["digest"] is None and tree(media) == before


def test_nested_root_and_excluded_directory_are_preserved_scopes(library):
    client, media = library
    root, _, rows = fixture(client, media)
    base = Path(root["path"]) / "pack-0"
    image(base / "separate/unindexed.png")
    image(base / ".video-viewer-tmp/unindexed.png")
    outside = media / "outside"
    image(outside / "unindexed.png")
    (base / ".video-viewer-trash").symlink_to(outside, target_is_directory=True)
    with client.app.state.db.write() as db:
        db.add(
            Root(
                id="separate-root",
                name="separate",
                path=str(base / "separate"),
                mount_id=db.get(Root, root["id"]).mount_id,
                kind="pack",
                enabled=True,
                available=True,
            )
        )
    result = wait(client, prepare(client, [rows[0]["id"]])["id"])
    assert result["ready"] and result["result"]["image_count"] == 2
    with client.app.state.db.read() as db:
        row = db.scalar(select(PackPurgeEntry).where(PackPurgeEntry.plan_id == result["id"]))
        for name in ("separate", ".video-viewer-tmp", ".video-viewer-trash"):
            assert row.manifest["tree"][name]["kind"] == "preserve_scope"
        assert all("unindexed.png" not in p["path"] for p in row.manifest["files"])
    assert (outside / "unindexed.png").exists()


def test_attachment_change_after_hash_is_detected_by_second_tree_inspection(library):
    client, media = library
    root, _, rows = fixture(client, media)
    note = Path(root["path"]) / "pack-0/notes.txt"

    def hook(phase, _):
        if phase == "purge_pack_fingerprinted":
            note.write_text("attachment changed after images were fingerprinted")

    client.app.state.pack_purge_plans.fault_hook = hook
    result = wait(client, prepare(client, [rows[0]["id"]])["id"])
    assert result["status"] == "failed" and result["items"][0]["error"] == "pack_changed"
    assert note.read_text() == "attachment changed after images were fingerprinted"


def test_root_policy_change_before_publish_does_not_publish_stale_authority(library):
    client, media = library
    root, _, rows = fixture(client, media)
    changed = []

    def hook(phase, _):
        if phase == "purge_before_manifest_commit" and not changed:
            changed.append(True)
            with client.app.state.db.write() as db:
                db.add(
                    Root(
                        id="new-policy",
                        name="restricted",
                        path=root["path"] + "/pack-0/nested",
                        mount_id=db.get(Root, root["id"]).mount_id,
                        kind="pack",
                        enabled=False,
                        available=True,
                    )
                )

    client.app.state.pack_purge_plans.fault_hook = hook
    result = wait(client, prepare(client, [rows[0]["id"]])["id"])
    assert result["status"] == "failed" and result["items"][0]["error"] == "pack_changed"
    assert result["digest"] is None


def test_accepted_restore_blocks_preview_before_any_fingerprint(library, monkeypatch):
    client, media = library
    _, _, rows = fixture(client, media)
    ops = client.app.state.pack_files
    monkeypatch.setattr(ops, "enqueue", lambda _: None)
    command(
        client, "pack-trash/restore", {"trash_ids": [rows[0]["id"]], "request_id": "restore-queued"}
    )
    before = tree(media)
    result = prepare(client, [rows[0]["id"]], status=409)
    assert result["error"]["code"] == "operation_busy"
    assert tree(media) == before
    with client.app.state.db.read() as db:
        assert db.scalar(select(func.count()).select_from(PackPurgePlan)) == 0


def test_historical_previews_remain_readable_but_are_never_ready_or_requeued(library):
    client, media = library
    _, _, rows = fixture(client, media)
    plans = client.app.state.pack_purge_plans
    result = wait(client, prepare(client, [rows[0]["id"]])["id"])
    assert result["ready"] and not result["historical"]
    with client.app.state.db.write() as db:
        db.get(PackPurgePlan, result["id"]).historical = True
    receipt = client.get("/api/v1/pack-purge-requests/prepare").json()
    assert receipt["digest"] == result["digest"] and receipt["historical"] and not receipt["ready"]
    with client.app.state.db.write() as db:
        db.get(Task, result["id"]).status = "interrupted"
    plans.start()
    assert client.get(f"/api/v1/pack-purge-plans/{result['id']}").json()["status"] == "interrupted"
    assert len(plans.futures) == 1  # Only the original completed preparation.


@pytest.mark.parametrize("limit", ["max_entries", "max_depth"])
def test_manifest_limits_refuse_incomplete_inventory_instead_of_truncating(
    library, monkeypatch, limit
):
    client, media = library
    _, _, rows = fixture(client, media)
    inspector = client.app.state.pack_purge_plans.inspector
    monkeypatch.setattr(inspector, limit, 2 if limit == "max_entries" else 0)
    before = tree(media)
    result = wait(client, prepare(client, [rows[0]["id"]])["id"])
    assert result["status"] == "failed" and result["items"][0]["error"] == "manifest_too_large"
    assert result["digest"] is None and not result["ready"] and tree(media) == before


def test_summary_reads_large_persisted_manifest_without_materializing_its_files(library):
    import json
    import tracemalloc

    client, media = library
    _, _, rows = fixture(client, media)
    plans = client.app.state.pack_purge_plans
    result = wait(client, prepare(client, [rows[0]["id"]])["id"])
    # A stored inventory fixture, not 80,000 scanned images or a NAS benchmark.
    with client.app.state.db.write() as db:
        entry = db.scalar(select(PackPurgeEntry).where(PackPurgeEntry.plan_id == result["id"]))
        manifest = dict(entry.manifest)
        original = manifest["files"][0]
        manifest["files"] = [{**original, "relative_path": f"{i:08d}.png"} for i in range(80_000)]
        entry.manifest = manifest
        entry.image_count = 80_000
        stored_bytes = len(json.dumps(manifest))
    del manifest, original, entry
    assert stored_bytes > 8 * 1024 * 1024
    tracemalloc.start()
    try:
        plans.progress(result["id"])
        response = client.get(f"/api/v1/pack-purge-plans/{result['id']}")
        peak = tracemalloc.get_traced_memory()[1]
    finally:
        tracemalloc.stop()
    assert response.status_code == 200
    body = response.json()
    assert body["result"]["image_count"] == body["items"][0]["image_count"] == 80_000
    assert len(response.content) < 4096
    assert peak < 4 * 1024 * 1024, f"Summary materialized a large file inventory: {peak} bytes"
    print(f"PURGE_PLAN_SUMMARY stored_bytes={stored_bytes} peak_python_bytes={peak}")
