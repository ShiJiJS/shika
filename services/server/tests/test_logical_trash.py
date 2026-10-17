import os
import shutil
import uuid

from .conftest import put, scan
from .test_backups import export, restore
from .test_file_operations import operation, trash
from .test_tags import assign, tag


def test_mark_restore_and_scan_never_move_or_read_originals(library, samples, monkeypatch):
    client, media = library
    paths = [media / f"logical-{i}.mov" for i in range(4)]
    for path in paths:
        put(samples / "h264.mov", path)
    scan(client)
    videos = client.get("/api/v1/videos").json()["items"]
    ids = [video["id"] for video in videos]
    label = tag(client, "保留")
    assign(client, ids, [label["id"]])
    before = {path: os.stat(path) for path in paths}

    def forbidden(*_args, **_kwargs):
        raise AssertionError("Logical trash must not transfer/hash media")

    monkeypatch.setattr(client.app.state.files.transfer, "execute", forbidden)
    deleted, request = trash(client, ids)
    assert deleted["result"]["succeeded"] == 4, deleted
    assert client.post("/api/v1/videos/trash", json=request).json()["id"] == deleted["id"]
    assert client.get("/api/v1/videos").json()["total"] == 0
    for path, previous in before.items():
        current = os.stat(path)
        assert (current.st_ino, current.st_size, current.st_mtime_ns, current.st_ctime_ns) == (
            previous.st_ino, previous.st_size, previous.st_mtime_ns, previous.st_ctime_ns
        )
    assert not (media / ".video-viewer-trash").exists()
    scan(client)
    assert client.get("/api/v1/videos").json()["total"] == 0
    rows = client.get("/api/v1/trash").json()["items"]
    restored, _ = operation(client, "/api/v1/trash/restore", {"trash_ids": [row["id"] for row in rows]})
    assert restored["result"]["succeeded"] == 4, restored
    assert {video["id"] for video in client.get("/api/v1/videos").json()["items"]} == set(ids)
    assert all(video["tag_ids"] == [label["id"]] for video in client.get("/api/v1/videos").json()["items"])
    assert client.get("/api/v1/trash").json()["total"] == 0


def test_permanent_delete_is_the_only_action_that_removes_logical_source(library, samples):
    client, media = library
    path = media / "permanent.mov"
    put(samples / "h264.mov", path)
    scan(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    trash(client, [video["id"]])
    assert path.exists()
    row = client.get("/api/v1/trash").json()["items"][0]
    assert client.post("/api/v1/trash/permanent", json={"request_id": str(uuid.uuid4()), "trash_ids": [row["id"]]}).status_code == 422
    done, _ = operation(client, "/api/v1/trash/permanent", {"trash_ids": [row["id"]], "confirmed": True})
    assert done["result"]["succeeded"] == 1, done
    assert not path.exists()


def test_permanent_delete_rejects_externally_replaced_marked_file(library, samples):
    client, media = library
    path = media / "replaced.mov"
    put(samples / "h264.mov", path)
    scan(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    trash(client, [video["id"]])
    path.unlink()
    path.write_bytes(b"replacement must survive")
    row = client.get("/api/v1/trash").json()["items"][0]
    done, _ = operation(client, "/api/v1/trash/permanent", {"trash_ids": [row["id"]], "confirmed": True})
    assert done["result"]["succeeded"] == 0
    assert path.read_bytes() == b"replacement must survive"


def test_backup_remapping_preserves_logical_trash_and_original_location(library, samples):
    client, media = library
    put(samples / "h264.mov", media / "marked.mov")
    scan(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    trash(client, [video["id"]])
    raw, _ = export(client)
    mapped = media / "mapped"
    mapped.mkdir()
    shutil.copyfile(media / "marked.mov", mapped / "marked.mov")
    restored, _ = restore(client, raw, {"main": str(mapped)})
    assert restored["status"] == "completed", restored
    item = client.get("/api/v1/trash").json()["items"][0]
    assert item["original_path"] == str(mapped / "marked.mov")
    assert client.get("/api/v1/videos").json()["total"] == 0
    done, _ = operation(client, "/api/v1/trash/restore", {"trash_ids": [item["id"]]})
    assert done["result"]["succeeded"] == 1, done
    assert (mapped / "marked.mov").exists()


def test_backup_keeps_a_logical_mark_when_original_has_disappeared(library, samples):
    client, media = library
    path = media / "missing.mov"
    put(samples / "h264.mov", path)
    scan(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    trash(client, [video["id"]])
    raw, _ = export(client)
    path.unlink()
    restored, _ = restore(client, raw, {"main": str(media)})
    assert restored["status"] == "completed", restored
    assert client.get("/api/v1/trash").json()["total"] == 1
    assert client.get("/api/v1/videos").json()["total"] == 0
