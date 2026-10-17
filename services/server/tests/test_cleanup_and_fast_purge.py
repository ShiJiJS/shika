import os
import shutil
import uuid

from .conftest import put, scan
from .test_file_operations import operation, trash
from .test_tags import assign, tag


def test_unchanged_batch_purge_does_not_read_full_media(library, samples, monkeypatch):
    client, media = library
    for i in range(8):
        put(samples / "h264.mov", media / f"{i}.mov")
    scan(client)
    ids = [row["id"] for row in client.get("/api/v1/videos").json()["items"]]
    trash(client, ids)

    def forbidden(_fd):
        raise AssertionError("Unchanged purge must not rehash original bytes")

    monkeypatch.setattr(client.app.state.files.transfer, "digest", forbidden)
    rows = client.get("/api/v1/trash").json()["items"]
    result, _ = operation(client, "/api/v1/trash/permanent", {
        "trash_ids": [row["id"] for row in rows], "confirmed": True
    })
    assert result["result"]["succeeded"] == 8, result
    assert not list(media.glob("*.mov"))


def test_changed_same_size_with_restored_mtime_is_not_fast_deleted(library, samples):
    client, media = library
    path = media / "changed.mov"
    put(samples / "h264.mov", path)
    scan(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    trash(client, [video["id"]])
    before = path.stat()
    content = path.read_bytes()
    modified = bytes([content[0] ^ 255]) + content[1:]
    path.write_bytes(modified)
    os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))
    row = client.get("/api/v1/trash").json()["items"][0]
    result, _ = operation(client, "/api/v1/trash/permanent", {
        "trash_ids": [row["id"]], "confirmed": True
    })
    assert result["result"]["succeeded"] == 0
    assert path.read_bytes() == modified


def test_external_folder_deletion_sync_and_confirmed_metadata_cleanup(library, samples):
    client, media = library
    path = media / "removed-folder" / "gone.mov"
    put(samples / "h264.mov", path)
    put(samples / "portrait.mp4", media / "keep.mp4")
    scan(client)
    video = next(v for v in client.get("/api/v1/videos").json()["items"] if v["name"] == "gone.mov")
    marked = tag(client, "旧标签")
    assign(client, [video["id"]], [marked["id"]])
    shutil.rmtree(path.parent)  # Only this test's generated directory.
    scan(client)
    assert client.get("/api/v1/videos?status=missing").json()["total"] == 1
    request = {"request_id": str(uuid.uuid4()), "confirmed": True}
    route = "/api/v1/videos/forget-missing"
    assert client.post(route, json={"request_id": "not-confirmed"}).status_code == 422
    assert client.post(route, json=request).json() == {"removed": 1, "skipped": 0}
    assert client.post(route, json=request).json() == {"removed": 1, "skipped": 0}
    assert client.get("/api/v1/videos?status=missing").json()["total"] == 0
    assert (media / "keep.mp4").exists()
    assert not path.exists()
    assert next(t for t in client.get("/api/v1/tags").json()["items"] if t["id"] == marked["id"])["video_count"] == 0
    put(samples / "h264.mov", path)
    scan(client)
    fresh = next(v for v in client.get("/api/v1/videos").json()["items"] if v["name"] == "gone.mov")
    assert fresh["id"] != video["id"] and fresh["tag_ids"] == []


def test_offline_root_or_returned_file_is_not_forgotten(library, samples):
    client, media = library
    path = media / "gone.mov"
    put(samples / "h264.mov", path)
    scan(client)
    path.unlink()
    scan(client)
    assert client.get("/api/v1/videos?status=missing").json()["total"] == 1
    away = media.with_name("offline")
    media.rename(away)
    scan(client)
    response = client.post("/api/v1/videos/forget-missing", json={"request_id": "offline", "confirmed": True})
    assert response.json()["removed"] == 0
    assert response.json()["skipped"] == 1
    away.rename(media)
    scan(client)
    put(samples / "h264.mov", path)
    response = client.post("/api/v1/videos/forget-missing", json={"request_id": "returned", "confirmed": True})
    assert response.json() == {"removed": 0, "skipped": 1}
    assert path.exists()
