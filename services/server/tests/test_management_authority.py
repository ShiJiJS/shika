"""Actual HTTP/transaction fencing across restore, lock races and old clients."""

import hashlib
import json
import sqlite3
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FutureTimeout
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from argon2 import PasswordHasher
from sqlalchemy import event, func, select
from sqlalchemy.orm import Session

from shika.authority import HEADER, KEY, Authority, valid_epoch
from shika.backup_archive import freeze_graph, write_v2
from shika.backup_v2_schema import mounts_from
from shika.db import Database
from shika.errors import LibraryError
from shika.models import AccessToken, Root, Setting, Task
from shika.security import Authentication

from .conftest import put, scan
from .test_backups import export, restore


def epoch(client):
    response = client.get("/api/v1/info")
    assert response.status_code == 200, response.text
    value = response.json()[KEY]
    assert valid_epoch(value) and response.headers[HEADER] == value
    return value


def rotate(client):
    with client.app.state.db.write() as session:
        return Authority.rotate(session)


def body(media):
    path = media / "new-root"
    path.mkdir(exist_ok=True)
    return {"name": "新目录", "path": str(path)}


def test_legacy_and_explicit_clients_keep_reads_but_must_acknowledge_new_writes(library):
    client, media = library
    old = epoch(client)
    latest = rotate(client)
    assert latest != old and epoch(client) == latest
    for headers in ({}, {HEADER: old}):
        response = client.post("/api/v1/roots", json=body(media), headers=headers)
        assert (
            response.status_code == 409 and response.json()["error"]["code"] == "management_changed"
        )
        assert response.headers[HEADER] == latest
        assert client.get("/api/v1/maintenance-tasks", headers=headers).status_code == 200
        # This legacy GET may create/repair a range, and is fenced at its write.
        changed = client.get("/api/v1/playback", headers=headers)
        assert (
            changed.status_code == 409 and changed.json()["error"]["code"] == "management_changed"
        )
    fresh = client.post("/api/v1/roots", json=body(media), headers={HEADER: latest})
    assert fresh.status_code == 201
    # Context from either an old GET or POST must not leak into the next request.
    assert client.get("/api/v1/playback", headers={HEADER: latest}).status_code == 200
    login = client.post(
        "/api/v1/auth/login", json={"passphrase": client.app.state.settings.passphrase}
    )
    assert login.status_code == 200 and login.json()[KEY] == latest
    token = login.json()["access_token"]
    assert (
        client.patch(
            "/api/v1/playback-defaults",
            headers={"Authorization": "Bearer " + token},
            json={"request_id": "fresh-token", "expected_revision": 0, "order": "sequential"},
        ).status_code
        == 200
    )


@pytest.mark.parametrize("explicit", [False, True])
def test_restore_between_admission_and_actual_write_rejects_old_http_request(
    library, monkeypatch, explicit
):
    client, media = library
    old = epoch(client)
    entered, release = threading.Event(), threading.Event()
    catalog = client.app.state.catalog
    original = catalog.save_root

    def gated(*args, **kwargs):
        entered.set()
        assert release.wait(15)
        return original(*args, **kwargs)

    monkeypatch.setattr(catalog, "save_root", gated)
    with ThreadPoolExecutor() as pool:
        pending = pool.submit(
            client.post,
            "/api/v1/roots",
            json=body(media),
            headers={HEADER: old} if explicit else {},
        )
        assert entered.wait(15)
        latest = rotate(client)
        release.set()
        response = pending.result(15)
    assert response.status_code == 409, response.text
    assert response.json()["error"]["code"] == "management_changed"
    assert response.headers[HEADER] == latest
    with client.app.state.db.read() as session:
        assert (
            session.scalar(select(func.count()).select_from(Root).where(Root.name == "新目录")) == 0
        )
    print(
        "VV_AUTHORITY_RACE",
        json.dumps({"explicit": explicit, "old_request_rejected": True, "new_root_rows": 0}),
    )


def test_write_holding_the_lock_commits_before_epoch_rotation(library):
    client, media = library
    old = epoch(client)
    entered, release = threading.Event(), threading.Event()

    def gate(session, _context, _instances):
        if any(isinstance(item, Root) and item.name == "新目录" for item in session.new):
            entered.set()
            assert release.wait(15)

    event.listen(Session, "before_flush", gate)
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            pending = pool.submit(
                client.post, "/api/v1/roots", json=body(media), headers={HEADER: old}
            )
            assert entered.wait(15)
            rotation = pool.submit(rotate, client)
            with pytest.raises(FutureTimeout):
                rotation.result(0.05)
            release.set()
            assert pending.result(15).status_code == 201
            assert rotation.result(15) != old
    finally:
        release.set()
        event.remove(Session, "before_flush", gate)
    assert client.post("/api/v1/scans", headers={HEADER: old}).status_code == 409


def test_revoked_token_waiting_for_write_cannot_change_library(library, monkeypatch):
    client, media = library
    entered, release = threading.Event(), threading.Event()
    original = client.app.state.catalog.save_root

    def gate(*args, **kwargs):
        entered.set()
        assert release.wait(15)
        return original(*args, **kwargs)

    monkeypatch.setattr(client.app.state.catalog, "save_root", gate)
    with ThreadPoolExecutor() as pool:
        request = pool.submit(client.post, "/api/v1/roots", json=body(media))
        assert entered.wait(15)
        client.app.state.auth.revoke(
            client.app.state.auth.digest(client.headers["Authorization"][7:])
        )
        release.set()
        response = request.result(15)
    assert response.status_code == 401
    with client.app.state.db.read() as session:
        assert (
            session.scalar(select(func.count()).select_from(Root).where(Root.name == "新目录")) == 0
        )


def test_other_database_connection_cannot_rotate_between_check_and_commit(library):
    client, _ = library
    primary = client.app.state.db
    other = Database(primary.path.parent)
    principal = client.app.state.auth.authenticate(client.headers["Authorization"])
    entered, release = threading.Event(), threading.Event()

    def old_write():
        with primary.authority.bind(principal), primary.write() as session:
            entered.set()
            assert release.wait(15)
            session.add(Setting(key="authority-race-canary", value="committed-before-rotation"))

    def other_rotation():
        with other.write() as session:
            return Authority.rotate(session)

    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            request = pool.submit(old_write)
            assert entered.wait(15)
            pending = pool.submit(other_rotation)
            with pytest.raises(FutureTimeout):
                pending.result(0.1)
            release.set()
            request.result(15)
            assert pending.result(15) != principal.issued_epoch
        with primary.authority.bind(principal), pytest.raises(LibraryError, match="管理数据已恢复"):
            with primary.write():
                raise AssertionError("old cross-connection lease committed")
        with primary.read() as session:
            assert (
                session.get(Setting, "authority-race-canary").value == "committed-before-rotation"
            )
    finally:
        release.set()
        other.close()


def test_stale_async_upload_is_rejected_before_body_or_task_acceptance(library):
    client, _ = library
    old = epoch(client)
    rotate(client)
    response = client.post(
        "/api/v1/backup-imports",
        content=b"not-a-backup",
        headers={HEADER: old, "Idempotency-Key": "old-upload"},
    )
    assert response.status_code == 409 and response.json()["error"]["code"] == "management_changed"
    assert client.get("/api/v1/backup-requests/inspect/old-upload").status_code == 404
    with client.app.state.db.read() as session:
        assert (
            session.scalar(
                select(func.count()).select_from(Task).where(Task.kind == "backup_inspect")
            )
            == 0
        )


@pytest.mark.parametrize("value", ["", "A" * 32, "a" * 31, "z" * 32])
def test_epoch_header_shape_is_strict_and_does_not_disable_auth(library, value):
    client, _ = library
    response = client.get("/api/v1/info", headers={HEADER: value})
    assert response.status_code == 422 and response.json()["error"]["code"] == "invalid_request"
    assert (
        client.get("/api/v1/info", headers={HEADER: "0" * 32, "Authorization": ""}).status_code
        == 401
    )


def test_old_token_can_explicitly_revoke_itself_after_restore(library):
    client, _ = library
    old = epoch(client)
    rotate(client)
    assert client.delete("/api/v1/auth/session", headers={HEADER: old}).status_code == 204
    assert client.get("/api/v1/info").status_code == 401


def test_duplicate_epoch_headers_are_not_silently_selected(library):
    client, _ = library
    current = epoch(client)
    response = client.get("/api/v1/info", headers=[(HEADER, current), (HEADER, "0" * 32)])
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "invalid_management_epoch"


def test_rolled_back_replacement_keeps_epoch_and_original_client_writable(library):
    client, media = library
    old = epoch(client)
    with pytest.raises(InterruptedError):
        with client.app.state.db.write() as session:
            Authority.rotate(session)
            session.add(Setting(key="uncommitted-replacement", value="must-rollback"))
            session.flush()
            raise InterruptedError("after SQL epoch update before commit")
    assert epoch(client) == old
    assert client.post("/api/v1/roots", json=body(media)).status_code == 201
    with client.app.state.db.read() as session:
        assert session.get(Setting, "uncommitted-replacement") is None


def test_lost_authority_with_bound_tokens_fails_without_reauthorizing_them(library):
    client, _ = library
    db = client.app.state.db
    with db.write() as session:
        old = Authority.current(session)
        session.delete(session.get(Setting, KEY))
    with pytest.raises(RuntimeError, match="authority is missing"):
        Authentication(db, client.app.state.settings)
    with db.write() as session:
        assert session.get(Setting, KEY) is None
        assert all(token.issued_epoch == old for token in session.scalars(select(AccessToken)))
        session.add(Setting(key=KEY, value=old))


def test_real_v1_restore_rotates_atomically_preserves_original_gets_and_excludes_authority(
    library, samples, tmp_path
):
    client, media = library
    put(samples / "h264.mov", media / "one.mov")
    scan(client)
    old = epoch(client)
    raw, _ = export(client)
    assert KEY.encode() not in raw and b"issued_epoch" not in raw
    path = tmp_path / "v2.vvbackup"
    with freeze_graph(
        client.app.state.db, mounts_from(client.app.state.settings), tmp_path
    ) as graph:
        write_v2(path, [graph], maximum_bytes=64 * 1024 * 1024)
    assert KEY.encode() not in path.read_bytes() and b"issued_epoch" not in path.read_bytes()
    before = hashlib.sha256((media / "one.mov").read_bytes()).hexdigest()
    task, request = restore(client, raw, {"main": str(media)}, adopt=False)
    assert task["status"] == "completed", task
    latest = epoch(client)
    assert old != latest
    assert client.post("/api/v1/backup-restores", json=request).status_code == 409
    assert client.post("/api/v1/scans", headers={HEADER: old}).status_code == 409
    found = client.get(
        "/api/v1/backup-requests/restore/" + request["request_id"], headers={HEADER: old}
    )
    assert found.status_code == 200 and found.json()["id"] == task["id"]
    assert (
        client.get(
            "/api/v1/backups/" + task["result"]["pre_snapshot_id"] + "/download",
            headers={HEADER: old},
        ).status_code
        == 200
    )
    assert hashlib.sha256((media / "one.mov").read_bytes()).hexdigest() == before
    with client.app.state.db.read() as session:
        assert (
            session.scalar(
                select(func.count()).select_from(Task).where(Task.kind == "backup_restore")
            )
            == 1
        )
    print(
        "VV_AUTHORITY_RESTORE",
        json.dumps(
            {"changed": True, "original_get": True, "restore_tasks": 1, "media_unchanged": True}
        ),
    )


def test_0013_upgrade_binds_existing_tokens_once_and_restart_keeps_identity(environment):
    settings, _ = environment
    settings.data_dir.mkdir()
    db = Database(settings.data_dir)
    config = Config(str(Path(__file__).parents[1] / "alembic.ini"))
    config.set_main_option("script_location", str(Path(__file__).parents[1] / "migrations"))
    with db.engine.begin() as connection:
        config.attributes["connection"] = connection
        command.upgrade(config, "0013")
    token = "isolated-old-token"
    digest, expires = Authentication.digest(token), time.time() + 3600
    with sqlite3.connect(db.path) as connection:
        connection.execute(
            "INSERT INTO settings VALUES('passphrase_hash',?)",
            (PasswordHasher().hash(settings.passphrase),),
        )
        connection.execute("INSERT INTO access_tokens VALUES(?,?)", (digest, expires))
    db.migrate()
    auth = Authentication(db, settings)
    first = auth.authenticate("Bearer " + token)
    assert valid_epoch(first.issued_epoch)
    assert db.last_migration_snapshot.is_file()
    with db.write() as session:
        after = Authority.rotate(session)
    db.close()
    reopened = Database(settings.data_dir)
    reopened.migrate()
    try:
        auth = Authentication(reopened, settings)
        assert auth.authenticate("Bearer " + token) == first
        with reopened.read() as session:
            assert Authority.current(session) == after != first.issued_epoch
            assert session.get(AccessToken, digest).expires_at == expires
        with reopened.authority.bind(first), pytest.raises(LibraryError, match="管理数据已恢复"):
            with reopened.write():
                raise AssertionError("stale write escaped fencing")
    finally:
        reopened.close()
