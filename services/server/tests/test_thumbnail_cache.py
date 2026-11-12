import os
import threading
import time
from contextlib import contextmanager
from types import SimpleNamespace

import pytest
from sqlalchemy import select

from shika import thumbnail_cache
from shika.authority import Authority
from shika.errors import LibraryError
from shika.models import ImagePack, PackPage, Video, uid


def cached(settings, folder, name=None):
    directory = settings.data_dir / folder
    directory.mkdir(exist_ok=True)
    path = directory / (name or (uid() + ".jpg"))
    path.write_bytes(b"disposable cached preview")
    return path


def reference(db, path, status="available"):
    with db.write() as session:
        if path.parent.name == "image-thumbnails":
            pack = ImagePack(root_id="main", path="/unused/" + uid(), name="test", status=status)
            session.add(pack)
            session.flush()
            session.add(
                PackPage(
                    pack_id=pack.id,
                    path=pack.path + "/1.jpg",
                    relative_path="1.jpg",
                    ordinal=0,
                    width=10,
                    height=10,
                    size=1,
                    format="JPEG",
                    thumbnail=path.name,
                )
            )
        else:
            session.add(
                Video(
                    root_id="main",
                    path="/unused/" + uid(),
                    name="test",
                    status=status,
                    size=1,
                    device="1",
                    inode="1",
                    mtime_ns="1",
                    ctime_ns="1",
                    sha256="a" * 64,
                    quick_hash="b" * 64,
                    duration=1,
                    width=10,
                    height=10,
                    type="mp4",
                    video_codec="h264",
                    container="mp4",
                    thumbnail=path.name,
                    seen_scan="test",
                )
            )


def age_cache(monkeypatch):
    monkeypatch.setattr(thumbnail_cache, "time", SimpleNamespace(time=lambda: time.time() + 7200))


def test_cleanup_only_retires_unreferenced_and_permanently_deleted_previews(library, monkeypatch):
    client, media = library
    db, settings = client.app.state.db, client.app.state.settings
    protected, retired = set(), set()
    for folder in ("image-thumbnails", "thumbnails"):
        for status in ("available", "trash", "missing", "discovered", "deleted"):
            path = cached(settings, folder)
            reference(db, path, status)
            (retired if status == "deleted" else protected).add(path)
        retired.add(cached(settings, folder))
        retired.add(cached(settings, folder, uid() + ".jpg.tmp.jpg"))
        shared = cached(settings, folder)
        reference(db, shared, "deleted")
        reference(db, shared, "trash")
        protected.add(shared)
        protected.add(cached(settings, folder, "unrecognized.jpg"))
        nested = settings.data_dir / folder / (uid() + ".jpg")
        nested.mkdir()
        protected.add(nested)
    original = media / (uid() + ".jpg")
    original.write_bytes(b"original stays")
    symlink = settings.data_dir / "image-thumbnails" / (uid() + ".jpg")
    symlink.symlink_to(original)
    protected.add(symlink)
    hardlink = settings.data_dir / "thumbnails" / (uid() + ".jpg")
    os.link(original, hardlink)
    protected.add(hardlink)
    backup = settings.data_dir / "backups" / (uid() + ".jpg")
    backup.parent.mkdir(exist_ok=True)
    backup.write_bytes(b"backup stays")
    age_cache(monkeypatch)
    result = thumbnail_cache.collect_thumbnails(db, settings.data_dir, threading.Event())
    assert result["files"] == len(retired) and result["errors"] == 0
    assert not any(path.exists() for path in retired)
    assert all(path.exists() for path in protected)
    assert original.read_bytes() == b"original stays" and backup.read_bytes() == b"backup stays"
    assert (
        thumbnail_cache.collect_thumbnails(db, settings.data_dir, threading.Event())["files"] == 0
    )


def test_recent_or_backdated_new_files_and_symlinked_cache_directories_are_kept(
    library, monkeypatch
):
    client, media = library
    settings, db = client.app.state.settings, client.app.state.db
    recent = cached(settings, "image-thumbnails")
    os.utime(recent, (time.time() - 7200, time.time() - 7200))
    assert (
        thumbnail_cache.collect_thumbnails(db, settings.data_dir, threading.Event())["files"] == 0
    )
    outside = media / "not-cache"
    outside.mkdir()
    original = outside / (uid() + ".jpg")
    original.write_bytes(b"keep original")
    (settings.data_dir / "thumbnails").symlink_to(outside, target_is_directory=True)
    age_cache(monkeypatch)
    thumbnail_cache.collect_thumbnails(db, settings.data_dir, threading.Event())
    assert original.read_bytes() == b"keep original"


def test_new_references_and_replaced_files_are_checked_again_before_unlink(library, monkeypatch):
    client, _ = library
    settings, db = client.app.state.settings, client.app.state.db
    acquired = cached(settings, "image-thumbnails")
    replaced = cached(settings, "image-thumbnails")
    age_cache(monkeypatch)
    open_directory = thumbnail_cache.open_directory
    original_stat = os.stat

    @contextmanager
    def before_listing(path):
        if path.name == "image-thumbnails":
            reference(db, acquired)
        with open_directory(path) as fd:
            yield fd

    def change_before_last_stat(path, *args, **kwargs):
        if path == replaced.name and kwargs.get("dir_fd") is not None:
            replaced.write_bytes(b"replacement must survive")
        return original_stat(path, *args, **kwargs)

    monkeypatch.setattr(thumbnail_cache, "open_directory", before_listing)
    monkeypatch.setattr(thumbnail_cache.os, "stat", change_before_last_stat)
    result = thumbnail_cache.collect_thumbnails(db, settings.data_dir, threading.Event())
    assert result["files"] == 0
    assert acquired.exists() and replaced.read_bytes() == b"replacement must survive"


def test_restore_reservation_generation_change_and_shutdown_stop_cleanup(library, monkeypatch):
    client, _ = library
    settings, db = client.app.state.settings, client.app.state.db
    path = cached(settings, "image-thumbnails")
    age_cache(monkeypatch)
    db.maintenance_task = "restore-test"
    try:
        with pytest.raises(LibraryError) as caught:
            thumbnail_cache.collect_thumbnails(db, settings.data_dir, threading.Event())
        assert caught.value.code == "restore_in_progress"
    finally:
        db.maintenance_task = None
    assert path.exists()
    stopped = threading.Event()
    stopped.set()
    assert thumbnail_cache.collect_thumbnails(db, settings.data_dir, stopped)["files"] == 0
    open_directory = thumbnail_cache.open_directory

    @contextmanager
    def restored_before_listing(directory):
        with db.write() as session:
            Authority.rotate(session)
        with open_directory(directory) as fd:
            yield fd

    monkeypatch.setattr(thumbnail_cache, "open_directory", restored_before_listing)
    assert (
        thumbnail_cache.collect_thumbnails(db, settings.data_dir, threading.Event())["files"] == 0
    )
    assert path.exists()


def test_cleanup_waits_for_unpublished_thumbnail_before_checking_references(library, monkeypatch):
    from shika.pack_scanner import inspect_image

    from .test_backups import wait_task
    from .test_media_types import pack_root
    from .test_packs import image

    client, media = library
    settings, db, scanner = client.app.state.settings, client.app.state.db, client.app.state.scanner
    root = pack_root(client, media)
    image(media / "packs" / "new" / "1.png")
    reached, release = threading.Event(), threading.Event()
    generated = []

    def pause(*args):
        result = inspect_image(*args)
        generated.append(settings.data_dir / "image-thumbnails" / result["thumbnail"])
        reached.set()
        assert release.wait(10)
        return result

    monkeypatch.setattr("shika.pack_scanner.inspect_image", pause)
    age_cache(monkeypatch)
    try:
        time.sleep(0.04)
        task = client.post("/api/v1/scans", json={"root_id": root["id"]}).json()
        assert reached.wait(5)
        scanner.last_cache_cleanup = None
        queued = scanner.executor.submit(scanner.clean_cache)
        assert not queued.done()
        assert client.get("/api/v1/info").status_code == 200
    finally:
        release.set()
    assert wait_task(client, task["id"])["status"] == "completed"
    queued.result(timeout=10)
    with db.read() as session:
        assert {row.thumbnail for row in session.scalars(select(PackPage))} == {
            path.name for path in generated
        }
    assert all(path.exists() for path in generated)


def test_startup_cleans_abandoned_previews_even_without_automatic_scans(environment, monkeypatch):
    from .conftest import connect

    settings, _ = environment
    settings.data_dir.mkdir()
    orphan = cached(settings, "image-thumbnails")
    age_cache(monkeypatch)
    client, _ = connect(settings)
    try:
        deadline = time.monotonic() + 5
        while orphan.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        assert not orphan.exists()
        assert client.get("/api/v1/info").status_code == 200
    finally:
        client.__exit__(None, None, None)


def test_cache_io_failure_does_not_fail_the_scan(library, monkeypatch):
    from .conftest import scan

    client, _ = library
    scanner = client.app.state.scanner

    def unavailable(*args):
        raise OSError("cache unavailable")

    monkeypatch.setattr("shika.scanner.collect_thumbnails", unavailable)
    scanner.last_cache_cleanup = None
    assert scan(client)["status"] == "completed"
    scanner.future.result(timeout=5)
    assert scanner.last_cache_cleanup is None
    assert client.get("/api/v1/info").status_code == 200
