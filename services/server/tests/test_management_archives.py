"""Public HTTP management archive restore over real current media and SQLite."""

import hashlib
import threading

from video_viewer.authority import Authority
from video_viewer.db import Database
from video_viewer.models import Setting

from .test_backup_restore_graph import seed
from .test_backups import wait_task
from .test_pack_operations import tree
from .test_tags import tag

PREFIX = "/api/v1/management-backups"


def export(client, key="export-v2"):
    response = client.post(PREFIX, json={"request_id": key})
    assert response.status_code == 202, response.text
    task = wait_task(client, response.json()["id"])
    assert task["status"] == "completed", task
    response = client.get(f"{PREFIX}/{task['id']}/download")
    assert response.status_code == 200, response.text
    assert hashlib.sha256(response.content).hexdigest() == task["result"]["file_sha256"]
    return response.content, task


def inspect(client, raw, key="inspect-v2"):
    response = client.post(
        PREFIX + "/imports",
        content=raw,
        headers={"Idempotency-Key": key, "Content-Type": "application/x-ndjson"},
    )
    assert response.status_code == 202, response.text
    task = wait_task(client, response.json()["id"])
    assert task["status"] == "completed", task
    return task


def restore(client, preview, mapping, key="restore-v2"):
    response = client.post(
        PREFIX + "/restores",
        json={
            "preview_id": preview["id"],
            "root_mapping": mapping,
            "request_id": key,
            "confirmed": True,
        },
    )
    assert response.status_code == 202, response.text
    return wait_task(client, response.json()["id"])


def test_public_complete_replacement_keeps_history_snapshot_credentials_and_source_bytes(
    library, samples
):
    client, media = library
    root, pack = seed(client, media, samples)
    original = tag(client, "恢复目标")
    raw, _ = export(client)
    preview = inspect(client, raw)
    assert preview["result"]["counts"]["packs"] == 1
    roots = client.get(f"{PREFIX}/{preview['id']}/roots", params={"limit": 1}).json()
    assert roots["total"] == 2 and len(roots["items"]) == 1
    later = tag(client, "不合并到活动库", request_id="later-label")
    old_epoch = client.get("/api/v1/info").json()["management_epoch"]
    before = tree(media)
    outcome = restore(client, preview, {"main": str(media), root["id"]: root["path"]})
    assert outcome["status"] == "completed", outcome
    assert tree(media) == before
    current = client.get("/api/v1/info").json()["management_epoch"]
    assert current != old_epoch
    assert (
        client.post(
            "/api/v1/tags", json={"request_id": "stale-write", "name": "不应执行"}
        ).status_code
        == 409
    )
    client.headers["X-Management-Epoch"] = current
    assert [v["id"] for v in client.get("/api/v1/tags").json()["items"]] == [original["id"]]
    actual = client.get("/api/v1/packs").json()["items"][0]
    assert actual["id"] == pack["id"] and actual["status"] == "available"
    snapshot = client.get(f"{PREFIX}/{outcome['result']['pre_snapshot_id']}/download")
    assert snapshot.status_code == 200 and later["id"].encode() in snapshot.content
    history = client.app.state.backups.archives.history()
    assert history is not None
    retired = history.receipt("request_records", "tag.create:later-label")
    assert retired["historical"] and retired["record"]["result"]["id"] == later["id"]
    blocked = client.post(
        "/api/v1/tags", json={"request_id": "later-label", "name": "不合并到活动库"}
    )
    assert blocked.status_code == 409 and blocked.json()["error"]["code"] == "historical_request"
    assert (
        client.post(
            PREFIX + "/restores",
            json={
                "preview_id": preview["id"],
                "root_mapping": {"main": str(media), root["id"]: root["path"]},
                "request_id": "restore-v2",
                "confirmed": True,
            },
        ).json()["id"]
        == outcome["id"]
    )
    exported, _ = export(client, "export-after-restore")
    assert b'"kind":"history"' in exported
    with client.app.state.db.read() as session:
        assert session.get(Setting, "management_history_epochs")


def test_null_mapping_disables_pack_and_precommit_failure_keeps_original_library(library, samples):
    client, media = library
    root, _ = seed(client, media, samples)
    raw, _ = export(client)
    preview = inspect(client, raw)
    marked = tag(client, "保留本次管理状态")
    epoch = client.get("/api/v1/info").json()["management_epoch"]
    before = tree(media)

    def fail(phase, identity):
        if phase == "after_replace_before_commit":
            raise OSError("isolated precommit failure")

    client.app.state.backups.fault_hook = fail
    outcome = restore(client, preview, {"main": str(media), root["id"]: None})
    assert outcome["status"] == "failed", outcome
    assert client.get("/api/v1/info").json()["management_epoch"] == epoch
    assert client.get("/api/v1/tags").json()["items"][0]["id"] == marked["id"]
    assert client.app.state.backups.archives.history() is None
    assert not (client.app.state.settings.data_dir / "management-history" / outcome["id"]).exists()
    assert tree(media) == before
    client.app.state.backups.fault_hook = None
    outcome = restore(client, preview, {"main": str(media), root["id"]: None}, "second-restore")
    assert outcome["status"] == "completed", outcome
    roots = client.get("/api/v1/roots").json()["items"]
    assert not next(r for r in roots if r["id"] == root["id"])["enabled"]


def test_reservation_is_seen_by_another_database_connection(library, samples):
    client, media = library
    root, _ = seed(client, media, samples)
    raw, _ = export(client)
    preview = inspect(client, raw)
    entered, release = threading.Event(), threading.Event()

    def pause(phase, identity):
        if phase == "history_prepared":
            entered.set()
            assert release.wait(15)

    client.app.state.backups.fault_hook = pause
    response = client.post(
        PREFIX + "/restores",
        json={
            "preview_id": preview["id"],
            "root_mapping": {"main": str(media), root["id"]: root["path"]},
            "request_id": "reserved",
            "confirmed": True,
        },
    )
    assert response.status_code == 202, response.text
    try:
        assert entered.wait(15)
        login = client.post(
            "/api/v1/auth/login", json={"passphrase": client.app.state.settings.passphrase}
        )
        assert login.status_code == 200
        assert (
            client.delete(
                "/api/v1/auth/session",
                headers={"Authorization": "Bearer " + login.json()["access_token"]},
            ).status_code
            == 204
        )
        assert (
            client.post(
                "/api/v1/tags", json={"request_id": "during-restore", "name": "不能执行"}
            ).status_code
            == 503
        )
        other = Database(client.app.state.settings.data_dir)
        try:
            import pytest

            from video_viewer.errors import LibraryError

            with pytest.raises(LibraryError, match="管理数据正在恢复"):
                with other.write() as session:
                    Authority.rotate(session)
        finally:
            other.engine.dispose()
        assert client.get("/api/v1/tasks/" + response.json()["id"]).status_code == 200
    finally:
        release.set()
    assert wait_task(client, response.json()["id"])["status"] == "completed"


def test_complete_33_table_restore_and_continuous_epochs_keep_original_graphs(library, samples):
    from sqlalchemy import func, select

    from video_viewer.backup_v2_schema import TABLES

    from .test_backup_archive import seed_complete_graph
    from .test_pack_operations import trash
    from .test_packs import sync

    client, media = library
    root = seed_complete_graph(client, media, samples)
    with client.app.state.db.read() as session:
        expected_counts = {
            t.name: session.scalar(select(func.count()).select_from(t)) for t in TABLES
        }
    assert all(expected_counts.values()), expected_counts
    # Enable the real pack root before export, then mark it after the backup.
    assert (
        client.put(
            "/api/v1/roots/" + root["id"],
            json={
                "name": root["name"],
                "path": root["path"],
                "kind": "pack",
                "enabled": True,
            },
        ).status_code
        == 200
    )
    sync(client)
    stable_names = {
        "playback_rounds",
        "round_entries",
        "tags",
        "video_tags",
        "file_steps",
        "pack_tag_definitions",
        "pack_tag_links",
        "pack_progress",
        "pack_preferences",
        "recent_entries",
        "pack_sessions",
        "pack_session_entries",
        "pack_file_steps",
        "pack_missing_members",
        "pack_restore_members",
        "pack_restore_batches",
        "pack_purge_entries",
        "pack_purge_executions",
        "pack_purge_steps",
    }
    with client.app.state.db.read() as session:
        stable = {
            table.name: [
                dict(row)
                for row in session.execute(
                    select(table).order_by(*table.primary_key.columns)
                ).mappings()
            ]
            for table in TABLES
            if table.name in stable_names
        }
    raw, first_export = export(client, "full-export")
    preview = inspect(client, raw, "full-inspect")
    pack = client.get("/api/v1/packs").json()["items"][0]
    late_operation = trash(client, [pack["id"]], "late-pack-mark")
    epoch_a = client.get("/api/v1/info").json()["management_epoch"]
    before = tree(media)
    first = restore(client, preview, {"main": str(media), root["id"]: root["path"]}, "full-first")
    assert first["status"] == "completed", first
    assert all(first["result"]["imported_counts"].values())
    with client.app.state.db.read() as session:
        for table in TABLES:
            if table.name in stable:
                actual = [
                    dict(row)
                    for row in session.execute(
                        select(table).order_by(*table.primary_key.columns)
                    ).mappings()
                ]
                assert actual == stable[table.name], table.name
        assert session.get(Setting, "device_theme").value == "NOT-IN-MANAGEMENT-BACKUP"
    assert client.get("/api/v1/reading-defaults").json()["mode"] == "vertical"
    assert client.get("/api/v1/playback-defaults").json()["order"] == "sequential"

    epoch_b = client.get("/api/v1/info").json()["management_epoch"]
    client.headers["X-Management-Epoch"] = epoch_b
    old = client.get("/api/v1/management-history/epochs/" + epoch_a)
    assert old.status_code == 200, old.text
    graph_a = old.json()["graph_id"]
    original = client.get(
        "/api/v1/management-history/tasks/" + late_operation["id"] + "/record",
        params={"epoch": epoch_a},
    ).json()
    assert original["result"] == late_operation["result"] and original["error"] is None
    for path in (
        "/api/v1/pack-file-requests/late-pack-mark",
        "/api/v1/pack-operations/" + late_operation["id"],
    ):
        response = client.get(path)
        assert response.status_code == 200, response.text
        assert (
            response.json()["historical"] and response.json()["result"] == late_operation["result"]
        )
    legacy_summary = client.get("/api/v1/maintenance-tasks/" + late_operation["id"])
    assert legacy_summary.status_code == 200 and legacy_summary.json()["graph_id"] == graph_a
    members = client.get("/api/v1/maintenance-tasks/" + late_operation["id"] + "/items").json()
    assert members["graph_id"] == graph_a and members["total"] == 1
    second_raw, _ = export(client, "second-export")
    second_preview = inspect(client, second_raw, "second-inspect")
    second = restore(
        client, second_preview, {"main": str(media), root["id"]: root["path"]}, "full-second"
    )
    assert second["status"] == "completed", second
    epoch_c = client.get("/api/v1/info").json()["management_epoch"]
    assert len({epoch_a, epoch_b, epoch_c}) == 3
    client.headers["X-Management-Epoch"] = epoch_c
    assert client.get("/api/v1/management-history/epochs/" + epoch_a).json()["graph_id"] == graph_a
    assert client.get("/api/v1/management-history/epochs/" + epoch_b).status_code == 200
    assert client.get("/api/v1/management-history/epochs/" + "0" * 32).status_code == 404
    original_again = client.get(
        "/api/v1/management-history/tasks/" + late_operation["id"] + "/record"
    ).json()
    assert original_again["result"] == late_operation["result"] and original_again["error"] is None
    # Explicit graph selection stays exact: the B projection retains its marker.
    projection = client.get(
        "/api/v1/management-history/tasks/" + late_operation["id"] + "/record",
        params={"epoch": epoch_b},
    ).json()
    assert projection["error"] == "restored_history"
    assert (
        client.get(
            "/api/v1/management-history/tasks/" + late_operation["id"],
            params={"epoch": epoch_a, "graph_id": projection["graph_id"]},
        ).status_code
        == 422
    )
    assert (
        client.get(
            "/api/v1/management-history/tasks/" + late_operation["id"], params={"epoch": "0" * 32}
        ).status_code
        == 404
    )
    for job in (first_export, first, second):
        current = client.get("/api/v1/tasks/" + job["id"]).json()
        assert current["status"] == "completed" and current["finished_at"] == job["finished_at"]
    for snapshot in (first["result"]["pre_snapshot_id"], second["result"]["pre_snapshot_id"]):
        assert client.get(PREFIX + "/" + snapshot + "/download").status_code == 200
    assert client.get(PREFIX + "/requests/restore/full-first").json()["id"] == first["id"]
    history_page = client.get(
        "/api/v1/management-history/tasks", params={"family": "backup", "limit": 100}
    ).json()
    assert {first_export["id"], first["id"], second["id"]}.isdisjoint(
        {v["id"] for v in history_page["items"]}
    )
    assert (
        client.post(
            "/api/v1/packs/trash", json={"pack_ids": [pack["id"]], "request_id": "late-pack-mark"}
        ).status_code
        == 409
    )
    assert tree(media) == before


def test_v1_upload_uses_complete_replacement_and_keeps_original_receipt(library, samples):
    from .conftest import put, scan
    from .test_backups import export as export_v1

    client, media = library
    put(samples / "h264.mov", media / "legacy.mov")
    scan(client)
    old = tag(client, "旧格式目标")
    raw, old_export = export_v1(client)
    tag(client, "不合并当前")
    preview = inspect(client, raw, "v1-convert")
    assert preview["result"]["version"] == 1
    outcome = restore(client, preview, {"main": str(media)}, "v1-restore-v2")
    assert outcome["status"] == "completed", outcome
    assert client.get("/api/v1/tags").json()["items"][0]["id"] == old["id"]
    assert client.get("/api/v1/backups/" + old_export["id"] + "/download").status_code == 200


def test_imported_pending_jobs_remain_retired_after_cold_start(environment, samples):
    import uuid

    from sqlalchemy import delete

    from video_viewer.models import Task

    from .conftest import connect
    from .test_pack_operations import trash

    settings, media = environment
    client, token = connect(settings)
    try:
        root, pack = seed(client, media, samples)
        operation = trash(client, [pack["id"]], "original-pack-job")
        pending = [str(uuid.uuid4()), str(uuid.uuid4())]
        with client.app.state.db.write() as session:
            session.add_all(
                [
                    Task(id=pending[0], kind="scan", status="running", phase="walking", result={}),
                    Task(
                        id=pending[1],
                        kind="backup_export_v2",
                        status="queued",
                        phase="queued",
                        result={},
                    ),
                ]
            )
            job = session.get(Task, operation["id"])
            job.status, job.phase = "running", "committing"
        raw, _ = export(client, "with-pending-foreign-jobs")
        with client.app.state.db.write() as session:
            session.execute(delete(Task).where(Task.id.in_(pending)))
            job = session.get(Task, operation["id"])
            job.status, job.phase = "completed", "completed"
        preview = inspect(client, raw)
        before = tree(media)
        outcome = restore(client, preview, {"main": str(media), root["id"]: root["path"]})
        assert outcome["status"] == "completed", outcome
    finally:
        client.__exit__(None, None, None)
    client, _ = connect(settings, token=token)
    try:
        for identity in [*pending, operation["id"]]:
            with client.app.state.db.read() as session:
                job = session.get(Task, identity)
                assert job.status == "interrupted" and job.error == "restored_history"
            assert identity not in client.app.state.backups.futures
            assert identity not in client.app.state.pack_files.futures
        assert client.app.state.scanner.active_id not in pending
        assert client.get("/api/v1/tasks/" + pending[1]).json()["historical"]
        assert tree(media) == before
    finally:
        client.__exit__(None, None, None)


def test_upload_bad_digest_over_limit_cancel_and_disk_fault_leave_no_incoming_files(
    library, monkeypatch
):
    import errno
    from dataclasses import replace

    import pytest

    import video_viewer.management_backup_api as api

    client, media = library
    archives = client.app.state.backups.archives
    raw, _ = export(client)
    broken = client.post(
        PREFIX + "/imports", content=raw[:-7], headers={"Idempotency-Key": "truncated"}
    )
    assert broken.status_code == 202
    job = wait_task(client, broken.json()["id"])
    assert job["status"] == "failed" and job["error"] == "invalid_backup"
    assert client.get(PREFIX + "/" + job["id"] + "/roots").status_code == 404
    archives.settings = replace(archives.settings, backup_max_bytes=4096)
    over = client.post(
        PREFIX + "/imports", content=b"X" * 4097, headers={"Idempotency-Key": "over-limit"}
    )
    assert over.status_code == 413
    archives.settings = client.app.state.settings

    def cancel():
        yield b'{"incomplete":'
        raise OSError("isolated upload cancelled")

    with pytest.raises((OSError, BaseExceptionGroup)) as failure:
        client.post(
            PREFIX + "/imports", content=cancel(), headers={"Idempotency-Key": "cancel-upload"}
        )
    if isinstance(failure.value, BaseExceptionGroup):
        assert failure.value.subgroup(OSError) is not None
    else:
        assert "isolated upload cancelled" in str(failure.value)

    def no_space(fd, chunk):
        raise OSError(errno.ENOSPC, "isolated upload disk full")

    monkeypatch.setattr(api, "_write", no_space)
    with pytest.raises(OSError, match="isolated upload disk full"):
        client.post(PREFIX + "/imports", content=raw, headers={"Idempotency-Key": "disk-full"})
    assert not list(archives.store.glob(".incoming-*"))
    for key in ("over-limit", "cancel-upload", "disk-full"):
        assert client.get(PREFIX + "/requests/inspect/" + key).status_code == 404
    assert tree(media) == {}


def test_committed_restore_stays_completed_if_postcommit_cleanup_raises(library, samples):
    client, media = library
    root, _ = seed(client, media, samples)
    raw, _ = export(client)
    preview = inspect(client, raw)
    epoch = client.get("/api/v1/info").json()["management_epoch"]

    def fail(phase, identity):
        if phase == "restore_committed":
            raise OSError("isolated after-commit cleanup failure")

    client.app.state.backups.fault_hook = fail
    outcome = restore(client, preview, {"main": str(media), root["id"]: root["path"]})
    assert outcome["status"] == "completed" and outcome["error"] is None
    assert client.get("/api/v1/info").json()["management_epoch"] != epoch
    assert (
        client.get(PREFIX + "/requests/restore/restore-v2").json()["finished_at"]
        == outcome["finished_at"]
    )


def test_historical_graph_tampering_cannot_supply_original_result(library, samples):
    client, media = library
    root, _ = seed(client, media, samples)
    raw, _ = export(client)
    preview = inspect(client, raw)
    tag(client, "old-result", request_id="old-result")
    outcome = restore(client, preview, {"main": str(media), root["id"]: root["path"]})
    assert outcome["status"] == "completed"
    history = client.app.state.backups.archives.history()
    receipt = history.receipt("request_records", "tag.create:old-result")
    graph = next(g for g in history.graphs() if g.identity == receipt["graph_id"])
    with graph.database.open("ab") as changed:
        changed.write(b"changed")
    response = client.get(
        "/api/v1/management-history/receipts/request_records/tag.create:old-result"
    )
    assert (
        response.status_code == 409
        and response.json()["error"]["code"] == "history_artifact_changed"
    )


def test_bare_sqlite_writer_enables_persistent_reservation_after_migration(tmp_path):
    import uuid
    import pytest
    from sqlalchemy import text
    from video_viewer.errors import LibraryError

    database = Database(tmp_path / "initialization")
    try:
        with database.write() as session:
            session.execute(text("CREATE TABLE probe (value TEXT)"))
            session.execute(text("INSERT INTO probe VALUES ('before management schema')"))
        database.migrate()
        with database.write() as session:
            session.add(Setting(key="maintenance_restore", value=str(uuid.uuid4())))
        with pytest.raises(LibraryError, match="管理数据正在恢复"):
            with database.write() as session:
                session.execute(text("UPDATE probe SET value='must not commit'"))
        with database.read() as session:
            assert session.scalar(text("SELECT value FROM probe")) == "before management schema"
    finally:
        database.close()
