import hashlib
import os
import sqlite3
import time
from dataclasses import replace

from video_viewer.config import Mount

from .conftest import connect, put, scan, wait_phase


def test_formats_pagination_directory_scope_and_authorized_thumbnails(library, samples):
    client, media = library
    originals = {}
    for source in samples.iterdir():
        target = media / ("纵向" if source.name == "portrait.mp4" else "横向") / source.name
        originals[target] = put(source, target)
    (media / "空目录").mkdir()
    (media / "broken.mov").write_bytes(b"not a media file")
    job = scan(client)
    assert job["result"]["imported"] == 8, job
    assert job["result"]["failed"] == 1
    videos = client.get("/api/v1/videos").json()
    assert videos["total"] == 8
    pages = [
        client.get("/api/v1/videos", params={"limit": 3, "offset": offset}).json()["items"]
        for offset in (0, 3, 6)
    ]
    assert len({v["id"] for page in pages for v in page}) == 8
    assert {v["type"] for v in videos["items"]} == {"MP4", "MOV", "MKV", "WEBM", "AVI"}
    assert {v["video_codec"] for v in videos["items"]} == {"h264", "hevc", "vp9", "mpeg4", "prores"}
    assert client.get("/api/v1/videos", params={"file_type": "mov"}).json()["total"] == 4
    portraits = client.get("/api/v1/videos", params={"orientation": "portrait"}).json()
    assert {v["name"] for v in portraits["items"]} == {"portrait.mp4", "rotated.mov"}
    root = client.get("/api/v1/roots").json()["items"][0]
    children = client.get("/api/v1/directories", params={"parent_id": root["directory_id"]}).json()[
        "items"
    ]
    assert {d["name"] for d in children} == {"横向", "纵向", "空目录"}
    folder = next(d for d in children if d["name"] == "纵向")
    assert client.get("/api/v1/videos", params={"directory_id": folder["id"]}).json()["total"] == 1
    assert client.get("/api/v1/videos", params={"search": "%"}).json()["total"] == 0
    assert client.get("/api/v1/videos", params={"limit": 100000}).status_code == 422
    video = videos["items"][0]
    thumb = client.get(video["thumbnail_url"])
    assert thumb.status_code == 200 and thumb.content.startswith(b"\xff\xd8")
    assert client.get(video["thumbnail_url"], headers={"Authorization": ""}).status_code == 401
    assert "access_token" not in str(video) and "passphrase" not in str(video)
    assert all(
        hashlib.sha256(p.read_bytes()).hexdigest() == digest for p, digest in originals.items()
    )
    again = scan(client)
    assert again["result"]["unchanged"] == 8
    assert {v["id"] for v in client.get("/api/v1/videos").json()["items"]} == {
        v["id"] for v in videos["items"]
    }


def test_authentication_recreation_migration_and_revocation(environment, samples):
    settings, media = environment
    put(samples / "h264.mov", media / "one.mov")
    client, token = connect(settings)
    assert client.post("/api/v1/auth/login", json={"passphrase": "wrong"}).status_code == 401
    assert client.get("/api/v1/videos", headers={"Authorization": ""}).status_code == 401
    malformed = client.post(
        "/api/v1/auth/login", json={"passphrase": {"secret": "never-return-this"}}
    )
    assert malformed.status_code == 422 and "never-return-this" not in malformed.text
    scan(client)
    original = client.get("/api/v1/videos").json()["items"][0]
    server_id = client.get("/api/v1/info").json()["server_id"]
    client.__exit__(None, None, None)
    client, _ = connect(settings, token=token)
    assert client.get("/api/v1/info").json()["server_id"] == server_id
    assert client.get("/api/v1/videos").json()["items"][0]["id"] == original["id"]
    assert client.delete("/api/v1/auth/session").status_code == 204
    assert client.get("/api/v1/videos").status_code == 401
    client.__exit__(None, None, None)
    database = sqlite3.connect(settings.data_dir / "library.sqlite3")
    assert database.execute("select version_num from alembic_version").fetchone()[0] == "0011"
    assert database.execute("pragma integrity_check").fetchone()[0] == "ok"
    assert (
        database.execute("select value from settings where key='passphrase_hash'").fetchone()[0]
        != settings.passphrase
    )
    database.close()


def test_changed_passphrase_revokes_existing_tokens(environment):
    settings, _ = environment
    client, token = connect(settings)
    client.__exit__(None, None, None)
    settings = replace(settings, passphrase="changed-test-secret")
    client, _ = connect(settings, token=token)
    assert client.get("/api/v1/info").status_code == 401
    assert (
        client.post("/api/v1/auth/login", json={"passphrase": settings.passphrase}).status_code
        == 200
    )
    client.__exit__(None, None, None)


def test_overlap_empty_directories_and_root_edits(environment, samples):
    settings, media = environment
    nested = media / "nested"
    put(samples / "h264.mov", nested / "one.mov")
    (nested / "empty").mkdir()
    settings = replace(settings, mounts=(*settings.mounts, Mount("nested", "嵌套", nested)))
    client, _ = connect(settings)
    scan(client)
    assert client.get("/api/v1/videos").json()["total"] == 1
    roots = client.get("/api/v1/roots").json()["items"]
    nested_root = next(r for r in roots if r["id"] == "nested")
    assert (
        client.get("/api/v1/videos", params={"directory_id": nested_root["directory_id"]}).json()[
            "total"
        ]
        == 1
    )
    assert (
        client.post("/api/v1/roots", json={"name": "same", "path": str(nested)}).status_code == 201
    )
    assert (
        client.put("/api/v1/roots/main", json={"name": "changed", "path": str(media)}).status_code
        == 200
    )
    client.__exit__(None, None, None)


def test_path_and_link_boundaries(library, samples, tmp_path):
    client, media = library
    outside = tmp_path / "outside"
    put(samples / "h264.mov", outside / "secret.mov")
    (media / "linked.mov").symlink_to(outside / "secret.mov")
    (media / "linked-dir").symlink_to(outside, target_is_directory=True)
    put(samples / "portrait.mp4", media / "allowed.mp4")
    for path in (str(outside), str(media / ".." / "outside"), str(media / "linked-dir"), "/etc"):
        assert (
            client.post("/api/v1/roots", json={"name": "invalid", "path": path}).status_code == 422
        )
    scan(client)
    assert client.get("/api/v1/videos").json()["total"] == 1
    assert client.get("/api/v1/directories", params={"parent_id": "../../etc"}).status_code == 404
    root = client.get("/api/v1/roots").json()["items"][0]
    assert not client.get("/api/v1/directories", params={"parent_id": root["directory_id"]}).json()[
        "items"
    ]


def test_reserved_directories_and_manager_data_are_not_imported(environment, samples):
    settings, media = environment
    settings = replace(settings, data_dir=media / "manager")
    for destination in (
        media / ".video-viewer-trash" / "one.mov",
        media / ".video-viewer-tmp" / "one.mov",
        settings.data_dir / "one.mov",
        media / "upload.mov.part",
    ):
        put(samples / "h264.mov", destination)
    client, _ = connect(settings)
    scan(client)
    assert client.get("/api/v1/videos").json()["total"] == 0
    client.__exit__(None, None, None)


def test_root_unavailable_does_not_mark_files_missing(library, samples):
    client, media = library
    put(samples / "h264.mov", media / "one.mov")
    scan(client)
    video_id = client.get("/api/v1/videos").json()["items"][0]["id"]
    moved = media.with_name("temporarily-disconnected")
    media.rename(moved)
    try:
        job = scan(client)
        assert job["result"]["roots"][0]["status"] == "unavailable"
        assert client.get("/api/v1/videos").json()["total"] == 0
        assert client.get("/api/v1/videos", params={"status": "missing"}).json()["total"] == 0
    finally:
        moved.rename(media)
    scan(client)
    assert client.get("/api/v1/videos").json()["items"][0]["id"] == video_id
    (media / "one.mov").unlink()
    scan(client)
    assert (
        client.get("/api/v1/videos", params={"status": "missing"}).json()["items"][0]["id"]
        == video_id
    )


def test_partial_directory_failure_preserves_records(library, samples):
    assert os.getuid() != 0, "File permission checks must run as the production non-root user"
    client, media = library
    child = media / "restricted"
    put(samples / "h264.mov", child / "one.mov")
    scan(client)
    child.chmod(0)
    try:
        scan(client)
        assert client.get("/api/v1/roots").json()["items"][0]["available"] is False
        assert client.get("/api/v1/videos", params={"status": "missing"}).json()["total"] == 0
    finally:
        child.chmod(0o700)


def test_growing_file_is_deferred_then_discovered(environment, samples):
    settings, media = environment
    settings = replace(settings, stability_seconds=0.4)
    path = media / "copying.mov"
    put(samples / "h264.mov", path)
    client, _ = connect(settings)
    task = client.post("/api/v1/scans").json()
    wait_phase(client, task["id"], "waiting_for_stable_files")
    with path.open("ab") as stream:
        stream.write(b"copy-still-in-progress")
    # Even an old preserved mtime cannot bypass the second stat observation.
    os.utime(path, (100, 100))
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        final = client.get(f"/api/v1/tasks/{task['id']}").json()
        if final["status"] == "completed":
            break
        time.sleep(0.02)
    assert final["status"] == "completed" and final["result"]["deferred"] == 1, final
    assert client.get("/api/v1/videos").json()["total"] == 0
    scan(client)
    assert client.get("/api/v1/videos").json()["total"] == 1
    client.__exit__(None, None, None)


def test_scan_merge_foreground_queries_and_interruption(environment, samples):
    settings, media = environment
    settings = replace(settings, stability_seconds=0.5)
    put(samples / "h264.mov", media / "old.mov")
    client, token = connect(settings)
    scan(client)
    old_id = client.get("/api/v1/videos").json()["items"][0]["id"]
    (media / "old.mov").unlink()
    put(samples / "h264.mov", media / "new.mov")
    job = client.post("/api/v1/scans").json()
    wait_phase(client, job["id"], "waiting_for_stable_files")
    assert client.post("/api/v1/scans").json()["id"] == job["id"]
    assert client.get("/api/v1/info").status_code == 200
    client.__exit__(None, None, None)
    client, _ = connect(settings, token=token)
    assert client.get(f"/api/v1/tasks/{job['id']}").json()["status"] == "interrupted"
    assert client.get("/api/v1/videos", params={"status": "missing"}).json()["total"] == 0
    scan(client)
    assert client.get("/api/v1/videos").json()["total"] == 1
    assert client.get("/api/v1/videos").json()["items"][0]["id"] == old_id
    assert client.get("/api/v1/videos", params={"status": "missing"}).json()["total"] == 0
    client.__exit__(None, None, None)


def test_periodic_scan_discovers_external_addition(environment, samples):
    settings, media = environment
    settings = replace(settings, startup_scan=True, scan_interval=0.15)
    client, _ = connect(settings)
    put(samples / "h264.mov", media / "external.mov")
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        listing = client.get("/api/v1/videos").json()
        if listing["total"] == 1:
            break
        time.sleep(0.04)
    assert listing["total"] == 1
    assert client.get("/api/v1/tasks").json()["items"]
    client.__exit__(None, None, None)


def test_root_scope_edit_is_persistent_and_restricted(environment, samples):
    settings, media = environment
    put(samples / "h264.mov", media / "outside-selection.mov")
    put(samples / "portrait.mp4", media / "selected" / "inside.mp4")
    client, _ = connect(settings)
    scan(client)
    assert client.get("/api/v1/videos").json()["total"] == 2
    update = client.put(
        "/api/v1/roots/main", json={"name": "选定范围", "path": str(media / "selected")}
    )
    assert update.status_code == 200, update.text
    scan(client)
    assert client.get("/api/v1/videos").json()["total"] == 1
    client.__exit__(None, None, None)
    client, _ = connect(settings)
    assert client.get("/api/v1/roots").json()["items"][0]["path"] == str(media / "selected")
    assert client.get("/api/v1/videos").json()["total"] == 1
    client.__exit__(None, None, None)


def test_multiple_independent_mounts_and_disconnect_during_scan(environment, samples):
    settings, media = environment
    second = media.with_name("second-mount")
    put(samples / "h264.mov", media / "first.mov")
    put(samples / "vp9.webm", second / "second.webm")
    settings = replace(
        settings,
        stability_seconds=0.4,
        mounts=(*settings.mounts, Mount("second", "第二个目录", second)),
    )
    client, _ = connect(settings)
    first_scan = scan(client)
    assert client.get("/api/v1/videos").json()["total"] == 2, str(first_scan)
    put(samples / "portrait.mp4", media / "arriving.mp4")
    job = client.post("/api/v1/scans").json()
    wait_phase(client, job["id"], "waiting_for_stable_files")
    disconnected = media.with_name("disconnected-mid-scan")
    media.rename(disconnected)
    try:
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            result = client.get(f"/api/v1/tasks/{job['id']}").json()
            if result["status"] == "completed":
                break
            time.sleep(0.02)
        assert result["status"] == "completed", result
        roots = {r["id"]: r for r in client.get("/api/v1/roots").json()["items"]}
        assert roots["main"]["available"] is False and roots["second"]["available"] is True
        assert client.get("/api/v1/videos").json()["total"] == 1
        assert client.get("/api/v1/videos", params={"status": "missing"}).json()["total"] == 0
    finally:
        disconnected.rename(media)
        client.__exit__(None, None, None)
