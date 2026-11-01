"""Read verified returned images after restore without weakening normal identity checks."""

import hashlib
import io
import json
import os
import sqlite3
import stat

import pytest
from PIL import Image
from sqlalchemy import select

from video_viewer.models import PackFileOperation, PackPurgeStep

from .test_pack_operations import command, tree, wait
from .test_pack_purge_plans import fixture
from .test_pack_purge_rollback_retry import partial
from .test_pack_restore_plans import submit
from .test_pack_restore_plans import wait as wait_plan


def restored(client, media):
    task, remaining = partial(client, media)
    info = remaining.stat()
    os.chmod(remaining, stat.S_IMODE(info.st_mode))
    assert remaining.stat().st_ctime_ns != info.st_ctime_ns
    result = wait_plan(client, submit(client, [task["result"]["items"][0]["trash_id"]])["id"])
    assert result["status"] == "completed"
    pack = client.get("/api/v1/packs").json()["items"][0]
    page = client.get(f"/api/v1/packs/{pack['id']}/pages").json()["items"][0]
    assert page["relative_path"] == "nested/2.jpg"
    return task, pack, page, remaining


def catalogue(client):
    path = client.app.state.settings.data_dir / "library.sqlite3"
    with sqlite3.connect(f"file:{path}?mode=ro", uri=True) as db:
        db.execute("BEGIN")
        names = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")]
        return {
            name: hashlib.sha256(
                json.dumps(
                    sorted(db.execute(f'SELECT * FROM "{name}"').fetchall(), key=repr)
                ).encode()
            ).hexdigest()
            for name in names
        }


def routes(pack, page):
    return [pack["cover_url"], page["image_url"], page["thumbnail_url"]]


def test_normal_image_without_purge_history_still_rejects_ctime_change(library):
    client, media = library
    root, _, rows = fixture(client, media)
    result = wait_plan(client, submit(client, [rows[0]["id"]])["id"])
    assert result["status"] == "completed"
    pack = client.get("/api/v1/packs").json()["items"][0]
    page = client.get(f"/api/v1/packs/{pack['id']}/pages").json()["items"][0]
    from pathlib import Path

    original = Path(root["path"]) / "pack-0/1.png"
    before = original.stat()
    os.chmod(original, stat.S_IMODE(before.st_mode))
    assert original.stat().st_ctime_ns != before.st_ctime_ns
    snapshot = catalogue(client)
    for path in routes(pack, page):
        response = client.get(path)
        assert response.status_code == 409 and response.json()["error"]["code"] == "image_changed"
    assert catalogue(client) == snapshot


def test_restored_returned_page_original_cover_thumbnail_range_and_old_purge_guard(library):
    client, media = library
    task, pack, page, remaining = restored(client, media)
    before, files = catalogue(client), tree(media)
    raw = remaining.read_bytes()
    for path in routes(pack, page):
        response = client.get(path)
        assert response.status_code == 200, response.text
        with Image.open(io.BytesIO(response.content)) as image:
            assert image.width > 0 and image.height > 0
    assert client.get(page["image_url"]).content == raw
    ranged = client.get(page["image_url"], headers={"Range": "bytes=2-17"})
    assert ranged.status_code == 206 and ranged.content == raw[2:18]
    assert catalogue(client) == before and tree(media) == files
    result = wait(
        client,
        command(client, f"pack-operations/{task['id']}/retry", {"request_id": "old-purge"})["id"],
    )
    assert result["status"] == "failed"
    assert result["result"]["items"][0]["error"] == "stale_pack_state"
    assert remaining.read_bytes() == raw


@pytest.mark.parametrize("change", ["content", "replacement", "mtime", "missing", "symlink"])
def test_returned_page_read_refuses_external_changes(library, change):
    client, media = library
    _, pack, page, remaining = restored(client, media)
    old = remaining.stat()
    if change == "content":
        raw = bytearray(remaining.read_bytes())
        raw[len(raw) // 2] ^= 1
        remaining.write_bytes(raw)
        os.utime(remaining, ns=(old.st_atime_ns, old.st_mtime_ns))
    elif change == "replacement":
        other = remaining.with_name("replacement")
        other.write_bytes(remaining.read_bytes())
        os.utime(other, ns=(old.st_atime_ns, old.st_mtime_ns))
        os.replace(other, remaining)
    elif change == "mtime":
        os.utime(remaining, ns=(old.st_atime_ns, old.st_mtime_ns + 1_000_000))
    else:
        remaining.unlink()
        if change == "symlink":
            other = remaining.with_name("other.jpg")
            other.write_bytes(b"untrusted target")
            remaining.symlink_to(other)
    before = catalogue(client)
    for path in routes(pack, page):
        response = client.get(path)
        assert response.status_code == (422 if change == "symlink" else 409)
        if change == "symlink":
            assert response.json()["error"]["code"] == "symlink_not_allowed"
    assert catalogue(client) == before


def test_returned_read_cache_checks_changed_bytes_and_current_journal(library, monkeypatch):
    client, media = library
    task, pack, page, remaining = restored(client, media)
    reads = client.app.state.images.returned
    original, calls = reads.digest, []

    def counted(fd, observed):
        calls.append(tuple(observed))
        return original(fd, observed)

    monkeypatch.setattr(reads, "digest", counted)
    before = catalogue(client)
    for path in routes(pack, page):
        assert client.get(path).status_code == 200
    assert len(calls) == 1  # A thumbnail and original reuse the verified inode attributes.
    with client.app.state.db.write() as db:
        db.get(PackFileOperation, task["id"]).historical = True
    assert client.get(page["image_url"]).status_code == 409
    with client.app.state.db.write() as db:
        db.get(PackFileOperation, task["id"]).historical = False
    assert catalogue(client) == before
    old = remaining.stat()
    data = bytearray(remaining.read_bytes())
    data[len(data) // 2] ^= 1
    remaining.write_bytes(data)
    os.utime(remaining, ns=(old.st_atime_ns, old.st_mtime_ns))
    assert client.get(page["image_url"]).status_code == 409
    assert len(calls) == 2 and catalogue(client) == before


def test_mutation_during_returned_image_hash_is_not_cached_or_served(library, monkeypatch):
    client, media = library
    _, _, page, remaining = restored(client, media)
    original = os.pread
    changed = []

    def change_after_read(fd, size, offset):
        chunk = original(fd, size, offset)
        if not changed:
            changed.append(True)
            data = bytearray(remaining.read_bytes())
            data[len(data) // 2] ^= 1
            remaining.write_bytes(data)
        return chunk

    monkeypatch.setattr("video_viewer.rollback_images.os.pread", change_after_read)
    before = catalogue(client)
    response = client.get(page["image_url"])
    assert response.status_code == 409 and response.json()["error"]["code"] == "image_changed"
    assert changed and not client.app.state.images.returned.verified
    assert catalogue(client) == before


@pytest.mark.parametrize("evidence", ["no-verified-return", "wrong-state", "historical"])
def test_ctime_exception_requires_current_verified_return_journal(library, evidence):
    client, media = library
    task, pack, page, _ = restored(client, media)
    with client.app.state.db.write() as db:
        row = db.scalar(select(PackPurgeStep).where(PackPurgeStep.page_id == page["id"]))
        if evidence == "no-verified-return":
            row.state = {k: v for k, v in row.state.items() if k != "source_signature"}
        elif evidence == "wrong-state":
            row.phase = "prepared"
        else:
            db.get(PackFileOperation, task["id"]).historical = True
    before = catalogue(client)
    for path in routes(pack, page):
        response = client.get(path)
        assert response.status_code == 409 and response.json()["error"]["code"] == "image_changed"
    assert catalogue(client) == before
