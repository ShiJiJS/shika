"""LF1: upgrades preserve video state; media boundaries cannot cross types."""

import sqlite3
from pathlib import Path

import pytest
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from video_viewer.db import Database
from video_viewer.models import ImagePack, PackPage, PackProgress, PackTagLink, RecentEntry, Root

from .conftest import put, scan
from .test_backups import export, inspect
from .test_tags import assign, tag


def pack_root(client, media):
    path = media / "packs"
    path.mkdir(exist_ok=True)
    response = client.post(
        "/api/v1/roots", json={"name": "图包", "path": str(path), "kind": "pack"}
    )
    assert response.status_code == 201, response.text
    return response.json()


def pack_tag(client, name="共同名称", key="create-pack"):
    response = client.post("/api/v1/pack-tags", json={"name": name, "request_id": key})
    assert response.status_code == 201, response.text
    return response.json()


def seed_pack(client, root, name="one", status="available"):
    with client.app.state.db.write() as session:
        session.get(Root, root["id"]).available = True
        pack = ImagePack(
            root_id=root["id"], path=f"{root['path']}/{name}", name=name, status=status
        )
        session.add(pack)
        session.flush()
        return pack.id


def test_pack_tags_independent_counts_atomic_validation_and_retries(library, samples):
    client, media = library
    put(samples / "h264.mov", media / "video.mov")
    scan(client)
    video_id = client.get("/api/v1/videos").json()["items"][0]["id"]
    root = pack_root(client, media)
    pack_id = seed_pack(client, root)
    seed_pack(client, root, "missing", "missing")
    video_tag = tag(client, "共同名称", "create-pack")
    label = pack_tag(client)
    assert label["id"] != video_tag["id"] and label["kind"] == "pack"
    assert pack_tag(client) == label
    body = {"pack_ids": [pack_id], "tag_ids": [label["id"]], "mode": "add", "request_id": "links"}
    assert client.patch("/api/v1/pack-tag-links", json=body).status_code == 200
    assert client.patch("/api/v1/pack-tag-links", json=body).status_code == 200
    assert (
        client.patch("/api/v1/pack-tag-links", json={**body, "mode": "remove"}).status_code == 409
    )
    for changes in ({"tag_ids": [video_tag["id"]]}, {"pack_ids": [pack_id, video_id]}):
        bad = {**body, **changes, "mode": "replace", "request_id": "bad"}
        assert client.patch("/api/v1/pack-tag-links", json=bad).status_code == 404
    assert (
        client.patch(
            "/api/v1/video-tags",
            json={
                "video_ids": [video_id],
                "tag_ids": [label["id"]],
                "mode": "add",
                "request_id": "bad-video",
            },
        ).status_code
        == 404
    )
    with client.app.state.db.read() as session:
        assert [(link.pack_id, link.tag_id) for link in session.scalars(select(PackTagLink))] == [
            (pack_id, label["id"])
        ]
    listing = client.get("/api/v1/pack-tags").json()
    assert listing["items"][0]["pack_count"] == 1
    assert client.get("/api/v1/tags").json()["items"][0]["video_count"] == 0
    assert client.get("/api/v1/pack-tags", params={"search": "%"}).json()["total"] == 0
    assert client.get("/api/v1/pack-tags", headers={"Authorization": ""}).status_code == 401
    assert (
        client.post("/api/v1/pack-tags", json={"name": "   ", "request_id": "blank"}).status_code
        == 422
    )
    assert (
        client.post(
            "/api/v1/pack-tags", json={"name": label["name"], "request_id": "dup"}
        ).status_code
        == 409
    )
    assert (
        client.patch(
            f"/api/v1/pack-tags/{label['id']}", json={"name": "改名", "request_id": "rename"}
        ).json()["id"]
        == label["id"]
    )
    # Disabling hides counts but retains links and progress.
    update = {"name": root["name"], "path": root["path"], "enabled": False}
    assert client.put(f"/api/v1/roots/{root['id']}", json=update).status_code == 200
    assert client.get("/api/v1/pack-tags").json()["items"][0]["pack_count"] == 0
    assert (
        client.request(
            "DELETE", f"/api/v1/pack-tags/{label['id']}", json={"request_id": "delete"}
        ).status_code
        == 200
    )
    assert (
        client.request(
            "DELETE", f"/api/v1/pack-tags/{label['id']}", json={"request_id": "delete"}
        ).status_code
        == 200
    )
    with client.app.state.db.read() as session:
        assert list(session.scalars(select(PackTagLink))) == []
        assert session.get(ImagePack, pack_id).status == "available"


def test_disabled_root_is_retained_but_not_scanned_playable_or_forgotten(library, samples):
    client, media = library
    path = media / "one.mov"
    put(samples / "h264.mov", path)
    scan(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    label = tag(client, "保留")
    assign(client, [video["id"]], [label["id"]])
    root = client.get("/api/v1/roots").json()["items"][0]
    assert root["kind"] == "video" and root["enabled"]
    update = {"name": root["name"], "path": root["path"], "enabled": False}
    assert client.put(f"/api/v1/roots/{root['id']}", json=update).status_code == 200
    # Old clients omit the new flags; this must not re-enable a root.
    response = client.put(
        f"/api/v1/roots/{root['id']}", json={"name": "旧客户端", "path": root["path"]}
    )
    assert response.json()["enabled"] is False
    assert response.json()["available"] is True
    assert client.get("/api/v1/videos").json()["total"] == 0
    assert client.head(video["media_url"]).status_code == 409
    path.unlink()
    scan(client)
    assert client.get("/api/v1/videos", params={"status": "missing"}).json()["total"] == 0
    assert client.get("/api/v1/tags").json()["items"][0]["video_count"] == 0
    assert client.get("/api/v1/library-state").json()["indexed"] == 0
    assert (
        client.put(f"/api/v1/roots/{root['id']}", json={**update, "kind": "pack"}).status_code
        == 409
    )
    put(samples / "h264.mov", path)
    assert (
        client.put(f"/api/v1/roots/{root['id']}", json={**update, "enabled": True}).status_code
        == 200
    )
    scan(client)
    restored = client.get("/api/v1/videos").json()["items"][0]
    assert restored["id"] == video["id"] and restored["tag_ids"] == [label["id"]]
    path.unlink()
    scan(client)
    client.put(f"/api/v1/roots/{root['id']}", json=update)
    cleaned = client.post(
        "/api/v1/videos/forget-missing", json={"request_id": "clean-disabled", "confirmed": True}
    )
    assert cleaned.json() == {"removed": 0, "skipped": 1}


def test_nested_type_barriers_and_typed_directory_contract(library, samples):
    client, media = library
    root = pack_root(client, media)
    put(samples / "h264.mov", Path(root["path"]) / "video.mov")
    put(samples / "portrait.mp4", media / "outside.mp4")
    scan(client)
    assert [v["name"] for v in client.get("/api/v1/videos").json()["items"]] == ["outside.mp4"]
    assert len(client.get("/api/v1/directories").json()["items"]) == 1
    assert (
        client.get("/api/v1/directories", params={"kind": "pack"}).json()["items"][0]["root_id"]
        == root["id"]
    )
    assert client.get("/api/v1/library-state").json()["ready"] is True
    # Old client cannot use a pack directory as a video scope.
    assert client.get(f"/api/v1/directories/{root['directory_id']}").json()["available"] is False
    assert (
        client.get(
            "/api/v1/directories/resolve", params={"path": root["path"], "kind": "pack"}
        ).status_code
        == 200
    )
    info = client.get("/api/v1/info").json()
    assert info["schema_version"] == "0005"
    assert set(info["capabilities"]) == {"typed_roots", "pack_tags"}
    schema = client.get("/openapi.json").json()
    assert schema["components"]["schemas"]["RootInput"]["properties"]["enabled"]
    assert (
        schema["components"]["schemas"]["PackTagResponse"]["properties"]["kind"]["const"] == "pack"
    )


def test_legacy_backup_never_silently_drops_typed_data(library):
    client, media = library
    raw, _ = export(client)
    preview = inspect(client, raw)
    pack_root(client, media)
    rejected = client.post("/api/v1/backups", json={"request_id": "unsafe-export"})
    assert (
        rejected.status_code == 409
        and rejected.json()["error"]["code"] == "backup_upgrade_required"
    )
    rejected = client.post(
        "/api/v1/backup-restores",
        json={
            "request_id": "unsafe-restore",
            "preview_id": preview["id"],
            "root_mapping": {"main": str(media)},
            "confirmed": True,
        },
    )
    assert rejected.status_code == 409
    assert len(client.get("/api/v1/roots").json()["items"]) == 2


def test_progress_page_and_recent_kind_are_enforced_by_database(library):
    client, media = library
    root = pack_root(client, media)
    a, b = seed_pack(client, root, "a"), seed_pack(client, root, "b")
    db = client.app.state.db
    with db.write() as session:
        page = PackPage(
            pack_id=a,
            path=f"{root['path']}/a/1.jpg",
            relative_path="1.jpg",
            ordinal=0,
            width=10,
            height=10,
            size=1,
            format="JPEG",
        )
        session.add(page)
        session.flush()
        page_id = page.id
    with pytest.raises(IntegrityError), db.write() as session:
        session.add(PackProgress(pack_id=b, page_id=page_id))
        session.flush()
    with pytest.raises(IntegrityError), db.write() as session:
        session.add(RecentEntry(kind="video", pack_id=a))
        session.flush()


def test_failed_upgrade_restores_complete_private_snapshot(tmp_path, monkeypatch):
    fixture = Path(__file__).parent / "fixtures" / "lf0-management-0004.sql"
    path = tmp_path / "library.sqlite3"
    with sqlite3.connect(path) as connection:
        connection.executescript(fixture.read_text())
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("INSERT INTO settings VALUES ('wal-proof','retained')")
    db = Database(tmp_path)

    def fail(config, revision):
        # Simulate SQLite DDL that committed before a later migration failure.
        with sqlite3.connect(path) as connection:
            connection.execute("CREATE TABLE partially_migrated (id TEXT)")
            connection.execute("DELETE FROM settings WHERE key='wal-proof'")
        raise RuntimeError("injected migration failure")

    monkeypatch.setattr("video_viewer.db.command.upgrade", fail)
    with pytest.raises(RuntimeError, match="injected"):
        db.migrate()
    snapshot = db.last_migration_snapshot
    assert snapshot and snapshot.stat().st_mode & 0o777 == 0o600
    assert snapshot.parent.stat().st_mode & 0o777 == 0o700
    with sqlite3.connect(path) as connection:
        assert connection.execute("SELECT version_num FROM alembic_version").fetchone() == ("0004",)
        assert connection.execute(
            "SELECT value FROM settings WHERE key='wal-proof'"
        ).fetchone() == ("retained",)
        assert (
            connection.execute(
                "SELECT name FROM sqlite_master WHERE name='partially_migrated'"
            ).fetchone()
            is None
        )
        assert connection.execute("PRAGMA integrity_check").fetchone() == ("ok",)
    db.close()


def test_crash_recovery_uses_journal_before_retrying_upgrade(tmp_path):
    import json

    fixture = Path(__file__).parent / "fixtures" / "lf0-management-0004.sql"
    path = tmp_path / "library.sqlite3"
    folder = tmp_path / "migration-snapshots"
    folder.mkdir()
    snapshot = folder / "before-crash.sqlite3"
    with sqlite3.connect(snapshot) as connection:
        connection.executescript(fixture.read_text())
    with sqlite3.connect(snapshot) as source, sqlite3.connect(path) as target:
        source.backup(target)
        target.execute("CREATE TABLE partially_migrated (id TEXT)")
        target.execute("DELETE FROM video_tags")
    (tmp_path / "migration-pending.json").write_text(json.dumps({"snapshot": snapshot.name}))
    db = Database(tmp_path)
    db.migrate()
    with sqlite3.connect(path) as connection:
        assert connection.execute("SELECT count(*) FROM video_tags").fetchone() == (2,)
        assert (
            connection.execute(
                "SELECT name FROM sqlite_master WHERE name='partially_migrated'"
            ).fetchone()
            is None
        )
        assert connection.execute("SELECT version_num FROM alembic_version").fetchone() == ("0005",)
    assert not (tmp_path / "migration-pending.json").exists()
    db.close()


def test_static_migration_matches_orm_schema(library):
    from alembic.autogenerate import compare_metadata
    from alembic.migration import MigrationContext

    from video_viewer.models import Base

    client, _ = library
    with client.app.state.db.engine.connect() as connection:
        changes = compare_metadata(MigrationContext.configure(connection), Base.metadata)
        # 0004 already owns this index; the legacy ORM omitted its declaration.
        assert all(
            change[0] == "remove_index" and change[1].name == "trash_active_video"
            for change in changes
        )
