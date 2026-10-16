import hashlib
import os
import tempfile
import threading
import time
import uuid
from dataclasses import replace
from pathlib import Path

import pytest

from .conftest import connect, put, scan
from .test_playback import create_round, move
from .test_tags import assign, tag


def wait_operation(client, operation_id):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        response = client.get(f"/api/v1/operations/{operation_id}")
        assert response.status_code == 200, response.text
        task = response.json()
        if task["status"] in ("completed", "failed", "interrupted"):
            return task
        time.sleep(0.01)
    raise AssertionError(f"operation timeout: {task}")


def operation(client, path, body):
    request = {"request_id": str(uuid.uuid4()), **body}
    response = client.post(path, json=request)
    assert response.status_code == 202, response.text
    return wait_operation(client, response.json()["id"]), request


def trash(client, ids):
    return operation(client, "/api/v1/videos/trash", {"video_ids": ids})


def test_real_trash_and_precise_undo_preserve_identity_tags_and_round(library, samples):
    client, media = library
    original = {}
    for i in range(3):
        original[media / f"{i}.mov"] = put(samples / "h264.mov", media / f"{i}.mov")
    scan(client)
    videos = client.get("/api/v1/videos").json()["items"]
    marked = tag(client, "保留标签")["id"]
    assign(client, [v["id"] for v in videos], [marked])
    round, _ = create_round(client, "sequential")
    round = move(client, round, videos[1]["id"])
    deleted, request = trash(client, [videos[1]["id"]])
    assert deleted["status"] == "completed", deleted
    assert deleted["result"]["succeeded"] == 1
    assert not (media / "1.mov").exists()
    listed = client.get("/api/v1/trash").json()
    assert listed["total"] == 1 and listed["items"][0]["video"]["id"] == videos[1]["id"]
    assert listed["items"][0]["video"]["tag_ids"] == [marked]
    assert [
        hashlib.sha256(path.read_bytes()).hexdigest()
        for path in (media / ".video-viewer-trash").rglob("*.mov")
    ] == [original[media / "1.mov"]]
    replay = client.post("/api/v1/videos/trash", json=request)
    assert replay.status_code == 202 and replay.json()["id"] == deleted["id"]
    assert client.get("/api/v1/videos").json()["total"] == 2
    assert client.get("/api/v1/playback").json()["current"]["id"] != videos[1]["id"]
    undo, undo_request = operation(client, f"/api/v1/operations/{deleted['id']}/undo", {})
    assert undo["status"] == "completed", undo
    assert undo["result"]["playback_restored"]
    assert client.get("/api/v1/trash").json()["total"] == 0
    restored = client.get("/api/v1/playback").json()
    assert (
        restored["id"] == round["id"]
        and restored["current"]["id"] == videos[1]["id"]
        and restored["position"] == 1
    )
    assert all(
        hashlib.sha256(path.read_bytes()).hexdigest() == digest for path, digest in original.items()
    )
    assert (
        client.post(f"/api/v1/operations/{deleted['id']}/undo", json=undo_request).json()["id"]
        == undo["id"]
    )


def test_old_undo_and_completed_retry_cannot_target_newer_deletion(library, samples):
    client, media = library
    for name in ("a.mov", "b.mov"):
        put(samples / "h264.mov", media / name)
    scan(client)
    videos = client.get("/api/v1/videos").json()["items"]
    first, _ = trash(client, [videos[0]["id"]])
    second, _ = trash(client, [videos[1]["id"]])
    assert first["status"] == second["status"] == "completed"
    assert (
        client.post(
            f"/api/v1/operations/{first['id']}/undo", json={"request_id": "old-undo"}
        ).status_code
        == 409
    )
    retried = client.post(
        f"/api/v1/operations/{first['id']}/retry", json={"request_id": "finished-retry"}
    )
    assert retried.status_code == 202
    assert (
        client.post(
            f"/api/v1/operations/{first['id']}/undo", json={"request_id": "still-old"}
        ).status_code
        == 409
    )
    undo, _ = operation(client, f"/api/v1/operations/{second['id']}/undo", {})
    assert undo["status"] == "completed"
    assert not (media / "a.mov").exists() and (media / "b.mov").exists()
    assert client.get("/api/v1/trash").json()["total"] == 1


def test_restore_conflict_preserves_both_files_and_retry_uses_same_item(library, samples):
    client, media = library
    digest = put(samples / "h264.mov", media / "one.mov")
    scan(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    deleted, _ = trash(client, [video["id"]])
    assert deleted["status"] == "completed", deleted
    item = client.get("/api/v1/trash").json()["items"][0]
    replacement_digest = put(samples / "portrait.mp4", media / "one.mov")
    failed, _ = operation(client, "/api/v1/trash/restore", {"trash_ids": [item["id"]]})
    assert (
        failed["status"] == "failed"
        and failed["result"]["items"][0]["error"] == "destination_conflict"
    ), failed
    assert hashlib.sha256((media / "one.mov").read_bytes()).hexdigest() == replacement_digest
    assert client.get("/api/v1/trash").json()["total"] == 1
    (media / "one.mov").unlink()
    retried, _ = operation(client, f"/api/v1/operations/{failed['id']}/retry", {})
    assert retried["status"] == "completed", retried
    assert hashlib.sha256((media / "one.mov").read_bytes()).hexdigest() == digest
    assert client.get("/api/v1/videos").json()["items"][0]["id"] == video["id"]


def test_permanent_delete_requires_confirmation_and_is_precise(library, samples):
    client, media = library
    for name in ("a.mov", "b.mov"):
        put(samples / "h264.mov", media / name)
    scan(client)
    ids = [v["id"] for v in client.get("/api/v1/videos").json()["items"]]
    assert trash(client, ids)[0]["status"] == "completed"
    items = client.get("/api/v1/trash").json()["items"]
    invalid = {"request_id": "unconfirmed", "trash_ids": [items[0]["id"]], "confirmed": False}
    assert client.post("/api/v1/trash/permanent", json=invalid).status_code == 422
    done, request = operation(
        client, "/api/v1/trash/permanent", {"trash_ids": [items[0]["id"]], "confirmed": True}
    )
    assert done["status"] == "completed", done
    assert client.get("/api/v1/trash").json()["total"] == 1
    assert client.get("/api/v1/trash").json()["items"][0]["id"] == items[1]["id"]
    assert len(list((media / ".video-viewer-trash").rglob("*.mov"))) == 1
    assert client.post("/api/v1/trash/permanent", json=request).json()["id"] == done["id"]
    assert client.get("/api/v1/trash").json()["total"] == 1


def test_partial_permission_failure_reports_items_and_retains_original(library, samples):
    assert os.getuid() != 0
    client, media = library
    put(samples / "h264.mov", media / "a.mov")
    locked = media / "locked"
    digest = put(samples / "portrait.mp4", locked / "b.mp4")
    scan(client)
    ids = [v["id"] for v in client.get("/api/v1/videos").json()["items"]]
    locked.chmod(0o500)
    try:
        task, _ = trash(client, ids)
        assert task["status"] == "completed" and task["result"]["partial"], task
        assert task["result"]["succeeded"] == 1 and task["result"]["failed"] == 1
        assert any(item["error"] == "permission_denied" for item in task["result"]["items"])
        assert hashlib.sha256((locked / "b.mp4").read_bytes()).hexdigest() == digest
        assert client.get("/api/v1/videos").json()["total"] == 1
    finally:
        locked.chmod(0o700)


def test_cross_filesystem_copy_and_restore_preserve_content_and_identity(environment, samples):
    settings, media = environment
    original = put(samples / "h264.mov", media / "one.mov")
    with tempfile.TemporaryDirectory(prefix="video-viewer-cross-", dir="/dev/shm") as destination:
        assert Path(destination).stat().st_dev != media.stat().st_dev
        settings = replace(settings, trash_dir=Path(destination))
        client, _ = connect(settings)
        try:
            scan(client)
            video = client.get("/api/v1/videos").json()["items"][0]
            task, _ = trash(client, [video["id"]])
            assert task["status"] == "completed", task
            assert not (media / "one.mov").exists()
            assert [
                hashlib.sha256(p.read_bytes()).hexdigest() for p in Path(destination).rglob("*.mov")
            ] == [original]
            item = client.get("/api/v1/trash").json()["items"][0]
            restored, _ = operation(client, "/api/v1/trash/restore", {"trash_ids": [item["id"]]})
            assert restored["status"] == "completed", restored
            assert hashlib.sha256((media / "one.mov").read_bytes()).hexdigest() == original
            assert client.get("/api/v1/videos").json()["items"][0]["id"] == video["id"]
        finally:
            client.__exit__(None, None, None)


class SimulatedCrash(BaseException):
    pass


@pytest.mark.parametrize("phase", ["claimed", "publish_ready", "published", "source_removed"])
def test_restart_recovers_each_durable_move_phase(environment, samples, phase):
    settings, media = environment
    digest = put(samples / "h264.mov", media / "one.mov")
    reached = threading.Event()

    def crash(current, _step):
        if current == phase:
            reached.set()
            raise SimulatedCrash()

    client, token = connect(settings, file_fault_hook=crash)
    scan(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    request = {"request_id": "lost-response", "video_ids": [video["id"]]}
    submitted = client.post("/api/v1/videos/trash", json=request).json()
    assert reached.wait(5)
    client.__exit__(None, None, None)
    client, _ = connect(settings, token=token)
    try:
        result = wait_operation(client, submitted["id"])
        assert result["status"] == "completed", result
        assert client.post("/api/v1/videos/trash", json=request).json()["id"] == submitted["id"]
        assert not (media / "one.mov").exists()
        assert [
            hashlib.sha256(p.read_bytes()).hexdigest()
            for p in (media / ".video-viewer-trash").rglob("*.mov")
        ] == [digest]
        assert client.get("/api/v1/trash").json()["total"] == 1
        scan(client)
        assert client.get("/api/v1/videos").json()["total"] == 0
        restored, _ = operation(client, f"/api/v1/operations/{submitted['id']}/undo", {})
        assert restored["status"] == "completed", restored
        assert hashlib.sha256((media / "one.mov").read_bytes()).hexdigest() == digest
        assert client.get("/api/v1/videos").json()["items"][0]["id"] == video["id"]
    finally:
        client.__exit__(None, None, None)


def test_scanner_and_overlapping_delete_respect_pending_claim(environment, samples):
    settings, media = environment
    put(samples / "h264.mov", media / "one.mov")
    reached, release = threading.Event(), threading.Event()

    def pause(phase, _step):
        if phase == "claimed":
            reached.set()
            assert release.wait(10)

    client, _ = connect(settings, file_fault_hook=pause)
    try:
        scan(client)
        video = client.get("/api/v1/videos").json()["items"][0]
        task = client.post(
            "/api/v1/videos/trash", json={"request_id": "paused-delete", "video_ids": [video["id"]]}
        ).json()
        assert reached.wait(5)
        duplicate = client.post(
            "/api/v1/videos/trash",
            json={"request_id": "overlapping-delete", "video_ids": [video["id"]]},
        ).json()
        scan(client)
        assert client.get("/api/v1/videos?status=missing").json()["total"] == 0
        release.set()
        assert wait_operation(client, task["id"])["status"] == "completed"
        rejected = wait_operation(client, duplicate["id"])
        assert rejected["result"]["items"][0]["error"] == "operation_busy", rejected
        assert client.get("/api/v1/trash").json()["total"] == 1
        scan(client)
        assert client.get("/api/v1/videos").json()["total"] == 0
    finally:
        release.set()
        client.__exit__(None, None, None)


def test_replaced_source_and_symlink_are_never_deleted(library, samples, tmp_path):
    client, media = library
    put(samples / "h264.mov", media / "one.mov")
    scan(client)
    old = client.get("/api/v1/videos").json()["items"][0]
    outside = tmp_path / "outside.mov"
    outside_digest = put(samples / "portrait.mp4", outside)
    (media / "one.mov").unlink()
    (media / "one.mov").symlink_to(outside)
    failed, _ = trash(client, [old["id"]])
    assert failed["status"] == "failed", failed
    assert (media / "one.mov").is_symlink()
    assert hashlib.sha256(outside.read_bytes()).hexdigest() == outside_digest
    (media / "one.mov").unlink()
    replacement = put(samples / "portrait.mp4", media / "one.mov")
    failed, _ = trash(client, [old["id"]])
    assert failed["status"] == "failed", failed
    assert hashlib.sha256((media / "one.mov").read_bytes()).hexdigest() == replacement
    assert client.get("/api/v1/trash").json()["total"] == 0


def test_cross_filesystem_enospc_retains_complete_source(environment, samples):
    settings, media = environment
    source = media / "large.mp4"
    put(samples / "portrait.mp4", source)
    with tempfile.TemporaryDirectory(prefix="video-viewer-full-", dir="/dev/shm") as destination:
        capacity = os.statvfs(destination)
        size = capacity.f_bavail * capacity.f_frsize + 1024 * 1024
        assert size < 256 * 1024 * 1024, "expected disposable Docker shared memory limit"
        with source.open("ab") as output:
            output.truncate(size)
        with source.open("rb") as original:
            digest = hashlib.file_digest(original, "sha256").hexdigest()
        client, _ = connect(replace(settings, trash_dir=Path(destination)))
        try:
            scan(client)
            video = client.get("/api/v1/videos").json()["items"][0]
            result, _ = trash(client, [video["id"]])
            assert result["status"] == "failed", result
            assert result["result"]["items"][0]["error"] == "insufficient_space", result
            with source.open("rb") as original:
                assert hashlib.file_digest(original, "sha256").hexdigest() == digest
            assert not list(Path(destination).rglob("*.part"))
            assert client.get("/api/v1/trash").json()["total"] == 0
            assert (
                client.get(video["media_url"], headers={"Range": "bytes=0-127"}).status_code == 206
            )
        finally:
            client.__exit__(None, None, None)


def test_undo_after_tag_delete_does_not_reactivate_obsolete_scope(library, samples):
    client, media = library
    put(samples / "h264.mov", media / "one.mov")
    scan(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    marked = tag(client, "将被删除")["id"]
    assign(client, [video["id"]], [marked])
    create_round(client, "sequential", {"tag_ids": [marked]})
    deleted, _ = trash(client, [video["id"]])
    response = client.request("DELETE", f"/api/v1/tags/{marked}", json={"request_id": "remove-tag"})
    assert response.status_code == 200, response.text
    replacement_round = client.get("/api/v1/playback").json()["id"]
    undone, _ = operation(client, f"/api/v1/operations/{deleted['id']}/undo", {})
    assert undone["status"] == "completed" and not undone["result"]["playback_restored"], undone
    assert client.get("/api/v1/playback").json()["id"] == replacement_round
    assert client.get("/api/v1/videos").json()["items"][0]["tag_ids"] == []


def test_old_failed_restore_retry_cannot_damage_new_trash_cycle(library, samples):
    client, media = library
    original = put(samples / "h264.mov", media / "one.mov")
    scan(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    assert trash(client, [video["id"]])[0]["status"] == "completed"
    item = client.get("/api/v1/trash").json()["items"][0]
    put(samples / "portrait.mp4", media / "one.mov")
    failed, _ = operation(client, "/api/v1/trash/restore", {"trash_ids": [item["id"]]})
    assert failed["status"] == "failed"
    (media / "one.mov").unlink()
    assert (
        operation(client, "/api/v1/trash/restore", {"trash_ids": [item["id"]]})[0]["status"]
        == "completed"
    )
    newer, _ = trash(client, [video["id"]])
    assert newer["status"] == "completed"
    retried, _ = operation(client, f"/api/v1/operations/{failed['id']}/retry", {})
    assert retried["status"] == "failed", retried
    assert retried["result"]["items"][0]["error"] == "stale_operation"
    current = client.get("/api/v1/trash").json()["items"][0]
    assert current["id"] != item["id"] and current["video"]["status"] == "trash"
    undone, _ = operation(client, f"/api/v1/operations/{newer['id']}/undo", {})
    assert undone["status"] == "completed", undone
    assert hashlib.sha256((media / "one.mov").read_bytes()).hexdigest() == original


def test_cross_copy_changed_after_publish_preserves_original(environment, samples):
    settings, media = environment
    original = put(samples / "h264.mov", media / "one.mov")
    with tempfile.TemporaryDirectory(prefix="video-viewer-corrupt-", dir="/dev/shm") as destination:
        damaged = []

        def corrupt(phase, _step):
            if phase == "published":
                path = next(Path(destination).rglob("*.mov"))
                with path.open("r+b") as output:
                    output.write(b"damaged")
                damaged.append(path)

        client, _ = connect(replace(settings, trash_dir=Path(destination)), file_fault_hook=corrupt)
        try:
            scan(client)
            video = client.get("/api/v1/videos").json()["items"][0]
            failed, _ = trash(client, [video["id"]])
            assert failed["status"] == "failed", failed
            assert damaged and damaged[0].exists()
            assert hashlib.sha256((media / "one.mov").read_bytes()).hexdigest() == original
            assert client.get("/api/v1/trash").json()["total"] == 0
            assert (
                client.get(video["media_url"], headers={"Range": "bytes=0-127"}).status_code == 206
            )
        finally:
            client.__exit__(None, None, None)


def test_custom_trash_inside_mount_is_excluded_from_scan(environment, samples):
    settings, media = environment
    put(samples / "h264.mov", media / "one.mov")
    client, _ = connect(replace(settings, trash_dir=media / "custom-trash"))
    try:
        scan(client)
        video = client.get("/api/v1/videos").json()["items"][0]
        assert trash(client, [video["id"]])[0]["status"] == "completed"
        scan(client)
        assert client.get("/api/v1/videos").json()["total"] == 0
        assert client.get("/api/v1/trash").json()["total"] == 1
    finally:
        client.__exit__(None, None, None)
