"""A published terminal restore must agree with its write reservation."""

import threading
from concurrent.futures import ThreadPoolExecutor

import pytest

from shika.db import Database
from shika.errors import LibraryError
from shika.models import Setting

from .conftest import connect, put, scan
from .test_backups import export as export_v1
from .test_backups import inspect as inspect_v1
from .test_backups import wait_task
from .test_management_archives import PREFIX
from .test_management_archives import export as export_v2
from .test_management_archives import inspect as inspect_v2
from .test_pack_operations import tree
from .test_tags import tag


def prepare(client, media, samples, version):
    put(samples / "h264.mov", media / "one.mov")
    scan(client)
    original = tag(client, "restore target")
    raw, _ = (export_v1 if version == 1 else export_v2)(client)
    preview = (inspect_v1 if version == 1 else inspect_v2)(client, raw)
    later = tag(client, "snapshot only", request_id="snapshot-only")
    body = {
        "preview_id": preview["id"],
        "root_mapping": {"main": str(media)},
        "request_id": "restore-gate",
        "confirmed": True,
    }
    return {
        "path": "/api/v1/backup-restores" if version == 1 else PREFIX + "/restores",
        "receipt": "/api/v1/backup-requests/restore/"
        if version == 1
        else PREFIX + "/requests/restore/",
        "body": body,
        "original": original,
        "later": later,
        "epoch": client.get("/api/v1/info").json()["management_epoch"],
        "files": tree(media),
    }


def hold_committed(owner, version, monkeypatch, entered, release):
    def hold():
        entered.set()
        assert release.wait(15), "controlled post-commit pause was not released"

    if version == 2:

        def hook(phase, identity):
            if phase == "restore_committed":
                hold()

        owner.fault_hook = hook
    else:
        restore = owner.restore

        def pause_after_commit(identity):
            result = restore(identity)
            hold()
            return result

        monkeypatch.setattr(owner, "restore", pause_after_commit)


@pytest.mark.parametrize("version", [1, 2])
def test_committed_restore_accepts_snapshot_inspection_before_cleanup_finishes(
    library, samples, monkeypatch, version
):
    client, media = library
    prepared = prepare(client, media, samples, version)
    owner = client.app.state.backups
    entered, release = threading.Event(), threading.Event()
    hold_committed(owner, version, monkeypatch, entered, release)
    identity = None
    try:
        response = client.post(prepared["path"], json=prepared["body"])
        assert response.status_code == 202, response.text
        identity = response.json()["id"]
        assert entered.wait(15)
        outcome = wait_task(client, identity)
        assert outcome["status"] == "completed"
        current = client.get("/api/v1/info").json()["management_epoch"]
        assert current != prepared["epoch"]
        stale = client.post(
            "/api/v1/tags", json={"request_id": "stale-after-commit", "name": "must reject"}
        )
        assert stale.status_code == 409 and stale.json()["error"]["code"] == "management_changed"
        client.headers["X-Management-Epoch"] = current
        point = client.get(PREFIX + "/latest-restore").json()["item"]
        assert point["restore_id"] == identity
        accepted = client.post(
            PREFIX + "/from-snapshot/" + point["snapshot_id"],
            json={"request_id": "immediate-snapshot"},
        )
        assert accepted.status_code == 202, accepted.text
        inspected = accepted.json()["id"]
        assert client.get(PREFIX + "/requests/inspect/immediate-snapshot").json()["id"] == inspected
        assert owner.db.maintenance_task is None and owner.db.maintenance_owner is None
        assert not owner.futures[identity].done()
        assert tree(media) == prepared["files"]
    finally:
        release.set()
        if identity:
            owner.futures[identity].result(timeout=15)
    assert wait_task(client, inspected)["status"] == "completed"
    assert [r["id"] for r in client.get("/api/v1/tags").json()["items"]] == [
        prepared["original"]["id"]
    ]
    final = client.get(prepared["receipt"] + "restore-gate").json()
    assert final["finished_at"] == outcome["finished_at"]
    assert tree(media) == prepared["files"]


@pytest.mark.parametrize("version", [1, 2])
def test_terminal_failure_releases_reservation_before_worker_returns(
    library, samples, monkeypatch, version
):
    client, media = library
    prepared = prepare(client, media, samples, version)
    owner = client.app.state.backups
    entered, release = threading.Event(), threading.Event()
    original_fail = owner.fail

    def fail_after_snapshot(phase, identity):
        if phase == "snapshot_written":
            raise OSError("controlled failure before replacement")

    def pause_after_failure(*args):
        original_fail(*args)
        entered.set()
        assert release.wait(15)

    owner.fault_hook = fail_after_snapshot
    monkeypatch.setattr(owner, "fail", pause_after_failure)
    identity = None
    try:
        response = client.post(prepared["path"], json=prepared["body"])
        assert response.status_code == 202, response.text
        identity = response.json()["id"]
        assert entered.wait(15)
        assert wait_task(client, identity)["status"] == "failed"
        assert client.get("/api/v1/info").json()["management_epoch"] == prepared["epoch"]
        response = client.post(
            "/api/v1/tags", json={"request_id": "after-failure", "name": "can continue"}
        )
        assert response.status_code == 201, response.text
        assert owner.db.maintenance_task is None and owner.db.maintenance_owner is None
    finally:
        release.set()
        if identity:
            owner.futures[identity].result(timeout=15)
    current = {r["id"] for r in client.get("/api/v1/tags").json()["items"]}
    assert {prepared["original"]["id"], prepared["later"]["id"]} <= current
    assert tree(media) == prepared["files"]


@pytest.mark.parametrize("version", [1, 2])
def test_commit_keeps_reservation_until_replacement_is_durable(
    library, samples, monkeypatch, version
):
    client, media = library
    prepared = prepare(client, media, samples, version)
    owner = client.app.state.backups
    entered, release, attempted = threading.Event(), threading.Event(), threading.Event()

    def hold_before_commit(phase, identity):
        if phase == "after_replace_before_commit":
            entered.set()
            assert release.wait(15)

    owner.fault_hook = hold_before_commit
    response = client.post(prepared["path"], json=prepared["body"])
    assert response.status_code == 202, response.text
    identity = response.json()["id"]
    original_check = owner.db.check_authority

    def observe_write_attempt():
        attempted.set()
        return original_check()

    with ThreadPoolExecutor(max_workers=1) as executor:
        try:
            assert entered.wait(15)
            assert owner.db.maintenance_task == identity
            assert client.get("/api/v1/info").json()["management_epoch"] == prepared["epoch"]
            assert client.get("/api/v1/tasks/" + identity).json()["status"] == "running"
            assert {r["id"] for r in client.get("/api/v1/tags").json()["items"]} == {
                prepared["original"]["id"],
                prepared["later"]["id"],
            }
            monkeypatch.setattr(owner.db, "check_authority", observe_write_attempt)
            writer = executor.submit(
                client.post,
                "/api/v1/tags",
                json={"request_id": "blocked-before-commit", "name": "stale must not land"},
            )
            assert attempted.wait(5) and not writer.done()
        finally:
            release.set()
            owner.futures[identity].result(timeout=15)
        rejected = writer.result(timeout=10)
    assert rejected.status_code == 409 and rejected.json()["error"]["code"] == "management_changed"
    client.headers["X-Management-Epoch"] = client.get("/api/v1/info").json()["management_epoch"]
    assert (
        client.post(
            "/api/v1/tags", json={"request_id": "after-commit", "name": "new generation"}
        ).status_code
        == 201
    )
    assert tree(media) == prepared["files"]


@pytest.mark.parametrize("version", [1, 2])
def test_interrupted_restore_keeps_durable_gate_and_resumes_same_task(
    environment, samples, version
):
    settings, media = environment
    client, token = connect(settings)
    try:
        prepared = prepare(client, media, samples, version)
        owner = client.app.state.backups

        def stop_before_commit(phase, identity):
            if phase == "snapshot_written":
                owner.stop.set()

        owner.fault_hook = stop_before_commit
        response = client.post(prepared["path"], json=prepared["body"])
        assert response.status_code == 202, response.text
        identity = response.json()["id"]
        owner.futures[identity].result(timeout=15)
        assert wait_task(client, identity)["status"] == "interrupted"
        assert owner.db.maintenance_task is None
        with owner.db.read() as session:
            assert session.get(Setting, "maintenance_restore").value == identity
        blocked = client.post(
            "/api/v1/tags", json={"request_id": "while-interrupted", "name": "must wait"}
        )
        assert (
            blocked.status_code == 503 and blocked.json()["error"]["code"] == "restore_in_progress"
        )
        other = Database(settings.data_dir)
        try:
            with pytest.raises(LibraryError) as error:
                with other.write():
                    pass
            assert error.value.code == "restore_in_progress"
        finally:
            other.close()
        assert tree(media) == prepared["files"]
    finally:
        client.__exit__(None, None, None)
    client, _ = connect(settings, token=token)
    try:
        outcome = wait_task(client, identity)
        assert (
            outcome["status"] == "completed"
            and outcome["result"]["historical_operations_replayed"] == 0
        )
        assert client.get("/api/v1/info").json()["management_epoch"] != prepared["epoch"]
        client.headers["X-Management-Epoch"] = client.get("/api/v1/info").json()["management_epoch"]
        assert client.post(prepared["path"], json=prepared["body"]).json()["id"] == identity
        assert (
            client.post(
                "/api/v1/tags", json={"request_id": "after-resume", "name": "can continue"}
            ).status_code
            == 201
        )
        assert tree(media) == prepared["files"]
    finally:
        client.__exit__(None, None, None)


@pytest.mark.parametrize("cleanup_raises", [False, True])
def test_resumed_restore_cleanup_cannot_release_a_newer_restore_or_start_workers(
    environment, samples, cleanup_raises
):
    settings, media = environment
    client, token = connect(settings)
    try:
        prepared = prepare(client, media, samples, 2)
        owner = client.app.state.backups
        owner.fault_hook = lambda phase, identity: (
            owner.stop.set() if phase == "snapshot_written" else None
        )
        response = client.post(prepared["path"], json=prepared["body"])
        assert response.status_code == 202, response.text
        first = response.json()["id"]
        owner.futures[first].result(timeout=15)
        assert wait_task(client, first)["status"] == "interrupted"
    finally:
        client.__exit__(None, None, None)
    first_entered, first_release = threading.Event(), threading.Event()
    next_entered, next_release = threading.Event(), threading.Event()

    def pause(phase, identity):
        if phase == "restore_committed" and identity == first:
            first_entered.set()
            assert first_release.wait(15)
            if cleanup_raises:
                raise OSError("controlled cleanup failure after a newer restore was accepted")
        elif phase == "snapshot_written" and identity != first:
            next_entered.set()
            assert next_release.wait(15)

    client, _ = connect(settings, token=token, backup_fault_hook=pause)
    owner = client.app.state.backups
    second = None
    try:
        assert first_entered.wait(15)
        outcome = wait_task(client, first)
        assert outcome["status"] == "completed" and not owner.regular_started
        epoch = client.get("/api/v1/info").json()["management_epoch"]
        client.headers["X-Management-Epoch"] = epoch
        body = {**prepared["body"], "request_id": "next-restore"}
        response = client.post(prepared["path"], json=body)
        assert response.status_code == 202, response.text
        second = response.json()["id"]
        assert second != first and owner.db.maintenance_task == second
        first_release.set()
        owner.futures[first].result(timeout=15)
        assert next_entered.wait(15)
        assert owner.db.maintenance_task == second and not owner.regular_started
        assert client.get("/api/v1/tasks/" + first).json()["finished_at"] == outcome["finished_at"]
        assert client.get("/api/v1/info").json()["management_epoch"] == epoch
        blocked = client.post(
            "/api/v1/tags", json={"request_id": "during-second", "name": "must wait"}
        )
        assert (
            blocked.status_code == 503 and blocked.json()["error"]["code"] == "restore_in_progress"
        )
        next_release.set()
        owner.futures[second].result(timeout=15)
        assert (
            owner.regular_started
            and owner.db.maintenance_task is None
            and owner.db.maintenance_owner is None
        )
        assert wait_task(client, second)["status"] == "completed"
        assert client.get("/api/v1/info").json()["management_epoch"] != epoch
        assert tree(media) == prepared["files"]
    finally:
        first_release.set()
        next_release.set()
        if second:
            owner.futures[second].result(timeout=15)
        client.__exit__(None, None, None)
