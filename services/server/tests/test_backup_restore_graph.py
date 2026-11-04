"""Actual video/pack files and task graphs through private restore reconciliation."""

import errno
import shutil
from contextlib import contextmanager
from pathlib import Path

import pytest
from sqlalchemy import select

from shika.backup_archive import _readonly, file_hash, freeze_graph, inspect_v2
from shika.backup_restore_graph import prepare_graph
from shika.backup_v2_schema import TABLE_MAP, mounts_from, settings_from, validate_graph
from shika.errors import LibraryError
from shika.models import PackPurgeStep

from .conftest import put, scan
from .test_backup_archive import MAXIMUM, archive
from .test_file_operations import trash as trash_video
from .test_media_types import pack_root
from .test_pack_operations import trash, tree
from .test_pack_purge_execution import execute, plan
from .test_packs import image, packs, sync


def seed(client, media, samples):
    put(samples / "h264.mov", media / "video.mov")
    root = pack_root(client, media)
    base = Path(root["path"]) / "one"
    image(base / "1.png")
    image(base / "nested/2.jpg", color="blue")
    (base / "notes.txt").write_text("retain attachment")
    scan(client)
    return root, packs(client)["items"][0]


def staged(client, directory):
    directory.mkdir()
    source, _ = archive(client, directory)
    return next(inspect_v2(source, directory / "stage", maximum_bytes=MAXIMUM).graphs())


@contextmanager
def prepared(client, imported, directory, mapping=None, check=None):
    settings, db = client.app.state.settings, client.app.state.db
    with _readonly(imported.database).connect() as source:
        roots = source.execute(select(TABLE_MAP["roots"])).mappings().all()
        mapping = mapping if mapping is not None else {r["id"]: r["path"] for r in roots}
    before = file_hash(imported.database)
    with freeze_graph(db, mounts_from(settings), directory) as current:
        graph, counts = prepare_graph(
            imported, current, directory / "restored.sqlite3", mapping, settings, check=check
        )
    assert file_hash(imported.database) == before
    engine = _readonly(graph.database)
    try:
        with engine.connect() as connection:
            validate_graph(connection, settings_from(connection))
            yield connection, counts
    finally:
        engine.dispose()


def rows(connection, name):
    return list(connection.execute(select(TABLE_MAP[name])).mappings())


def test_mapped_video_and_pack_get_fresh_hash_verified_identity_without_writing_sources(
    library, samples, tmp_path
):
    client, media = library
    root, pack = seed(client, media, samples)
    original = staged(client, tmp_path / "original")
    destination = media / "relocated"
    destination.mkdir()
    shutil.copyfile(media / "video.mov", destination / "video.mov")
    shutil.copytree(Path(root["path"]), destination / "packs")
    before = tree(media)
    with prepared(
        client,
        original,
        tmp_path,
        {"main": str(destination), root["id"]: str(destination / "packs")},
    ) as (conn, counts):
        video, bundle = rows(conn, "videos")[0], rows(conn, "packs")[0]
        assert video["status"] == bundle["status"] == "available"
        assert video["path"] == str(destination / "video.mov")
        assert bundle["path"] == str(destination / "packs/one")
        assert video["device"] and bundle["directory_signature"]
        assert bundle["content_version"] > pack["content_version"]
        assert {k: counts[k] for k in ("videos", "packs", "pack_pages")} == {
            "videos": 1,
            "packs": 1,
            "pack_pages": 2,
        }
        assert all(
            p["signature"] and p["error"] is None and p["thumbnail"] is None
            for p in rows(conn, "pack_pages")
        )
    assert tree(media) == before


def test_explicit_null_roots_disable_both_media_without_dropping_relations(
    library, samples, tmp_path
):
    client, media = library
    root, _ = seed(client, media, samples)
    original = staged(client, tmp_path / "original")
    before = tree(media)
    with prepared(client, original, tmp_path, {"main": None, root["id"]: None}) as (conn, counts):
        assert all(not r["enabled"] and r["error"] == "root_unmapped" for r in rows(conn, "roots"))
        assert all(
            r["status"] == "missing" and r["location_key"] is None
            for name in ("videos", "packs")
            for r in rows(conn, name)
        )
        assert counts["pack_pages"] == 2
        assert all(not p["signature"] and p["error"] for p in rows(conn, "pack_pages"))
    assert tree(media) == before


def test_current_logical_marks_keep_real_parents_without_merging_other_media(
    library, samples, tmp_path
):
    client, media = library
    root, pack = seed(client, media, samples)
    original = staged(client, tmp_path / "original")
    image(Path(root["path"]) / "later/1.png")
    sync(client)
    catalog = packs(client)["items"]
    operation = trash(client, [p["id"] for p in catalog])
    video = client.get("/api/v1/videos").json()["items"][0]
    video_operation, _ = trash_video(client, [video["id"]])
    before = tree(media)
    with prepared(client, original, tmp_path) as (conn, _):
        assert len(rows(conn, "packs")) == 1
        assert rows(conn, "packs")[0]["id"] == pack["id"]
        assert rows(conn, "packs")[0]["status"] == rows(conn, "videos")[0]["status"] == "trash"
        assert rows(conn, "pack_trash_items")[0]["operation_id"] == operation["id"]
        assert rows(conn, "trash_items")[0]["operation_id"] == video_operation["id"]
        assert all(
            r["historical"]
            for r in rows(conn, "pack_file_operations") + rows(conn, "file_operations")
        )
        assert all(r["error"] == "restored_history" for r in rows(conn, "tasks"))
    assert tree(media) == before


def test_partial_real_purge_retires_deleted_page_id_even_if_bytes_reappear(
    library, samples, tmp_path
):
    client, media = library
    root, pack = seed(client, media, samples)
    base = Path(root["path"]) / "one"
    original_bytes = (base / "1.png").read_bytes()
    original = staged(client, tmp_path / "original")
    trash(client, [pack["id"]])
    item = client.get("/api/v1/pack-trash").json()["items"][0]

    def failure(phase, identity):
        if phase == "purge_purging":
            with client.app.state.db.read() as session:
                step = session.get(PackPurgeStep, identity)
                if step.relative_path == "nested/2.jpg":
                    raise OSError(errno.EACCES, "isolated second-image failure")

    client.app.state.pack_purge.fault_hook = failure
    outcome = execute(client, plan(client, [item["id"]]))
    assert outcome["result"]["pages_deleted"] == 1
    (base / "1.png").write_bytes(original_bytes)
    before = tree(media)
    with prepared(client, original, tmp_path) as (conn, counts):
        assert counts["pack_pages"] == 1
        assert rows(conn, "pack_pages")[0]["relative_path"] == "nested/2.jpg"
        assert rows(conn, "packs")[0]["status"] == "trash"
        assert rows(conn, "pack_trash_items")[0]["purged_pages"] == 1
    assert tree(media) == before


def test_changed_and_symlinked_images_cannot_receive_imported_signatures(
    library, samples, tmp_path
):
    client, media = library
    root, _ = seed(client, media, samples)
    original = staged(client, tmp_path / "original")
    base = Path(root["path"]) / "one"
    (base / "1.png").write_bytes(b"changed")
    outside = tmp_path / "outside.jpg"
    shutil.copyfile(base / "nested/2.jpg", outside)
    (base / "nested/2.jpg").unlink()
    (base / "nested/2.jpg").symlink_to(outside)
    with prepared(client, original, tmp_path) as (conn, _):
        assert all(
            not p["signature"] and p["error"] == "image_unavailable"
            for p in rows(conn, "pack_pages")
        )


def test_mapping_failure_and_cancellation_leave_no_replacement(library, samples, tmp_path):
    client, media = library
    root, _ = seed(client, media, samples)
    original = staged(client, tmp_path / "original")
    with pytest.raises(LibraryError):
        with prepared(client, original, tmp_path, {"main": str(media), root["id"]: str(tmp_path)}):
            pass
    assert not (tmp_path / "restored.sqlite3").exists()

    def cancelled():
        raise InterruptedError("isolated cancellation")

    with pytest.raises(InterruptedError):
        with prepared(client, original, tmp_path, check=cancelled):
            pass
    assert not (tmp_path / "restored.sqlite3").exists()


def test_explicit_current_restore_does_not_resurrect_imported_trash(library, samples, tmp_path):
    from .test_file_operations import operation as video_operation
    from .test_pack_operations import restore as restore_pack

    client, media = library
    _, pack = seed(client, media, samples)
    video = client.get("/api/v1/videos").json()["items"][0]
    trash(client, [pack["id"]])
    trash_video(client, [video["id"]])
    original = staged(client, tmp_path / "trashed")
    pack_marks = client.get("/api/v1/pack-trash").json()["items"]
    restore_pack(client, [pack_marks[0]["id"]])
    marks = client.get("/api/v1/trash").json()["items"]
    result, _ = video_operation(client, "/api/v1/trash/restore", {"trash_ids": [marks[0]["id"]]})
    assert result["result"]["succeeded"] == 1
    before = tree(media)
    with prepared(client, original, tmp_path) as (connection, _):
        assert rows(connection, "videos")[0]["status"] == "available"
        assert rows(connection, "packs")[0]["status"] == "available"
        assert all(
            r["status"] == "restored"
            for name in ("trash_items", "pack_trash_items")
            for r in rows(connection, name)
        )
    assert tree(media) == before
