import hashlib
import json
import shutil
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace

import pytest

from video_viewer.config import Mount

from .conftest import connect, put, scan, wait_phase
from .test_file_operations import operation, trash
from .test_playback import create_round
from .test_tags import assign, tag


def wait_task(client, task_id):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        response = client.get(f"/api/v1/tasks/{task_id}")
        assert response.status_code == 200, response.text
        task = response.json()
        if task["status"] in {"completed", "failed", "interrupted"}:
            return task
        time.sleep(0.01)
    raise AssertionError(f"backup timeout: {task}")


def export(client):
    key = str(uuid.uuid4())
    response = client.post("/api/v1/backups", json={"request_id": key})
    assert response.status_code == 202, response.text
    found = client.get(f"/api/v1/backup-requests/export/{key}")
    assert found.status_code == 200 and found.json()["id"] == response.json()["id"]
    task = wait_task(client, response.json()["id"])
    assert task["status"] == "completed", task
    response = client.get(f"/api/v1/backups/{task['id']}/download")
    assert response.status_code == 200, response.text
    assert hashlib.sha256(response.content).hexdigest() == task["result"]["file_sha256"]
    return response.content, task


def inspect(client, raw):
    key = str(uuid.uuid4())
    response = client.post(
        "/api/v1/backup-imports",
        content=raw,
        headers={"Content-Type": "application/json", "Idempotency-Key": key},
    )
    assert response.status_code == 202, response.text
    found = client.get(f"/api/v1/backup-requests/inspect/{key}")
    assert found.status_code == 200 and found.json()["id"] == response.json()["id"]
    return wait_task(client, response.json()["id"])


def restore(client, raw, mapping, *, request_id=None):
    preview = inspect(client, raw)
    assert preview["status"] == "completed", preview
    body = {
        "request_id": request_id or str(uuid.uuid4()),
        "preview_id": preview["id"],
        "root_mapping": mapping,
        "confirmed": True,
    }
    response = client.post("/api/v1/backup-restores", json=body)
    assert response.status_code == 202, response.text
    return wait_task(client, response.json()["id"]), body


def resign(document):
    signed = {key: value for key, value in document.items() if key != "sha256"}
    document["sha256"] = hashlib.sha256(
        json.dumps(
            signed, sort_keys=True, ensure_ascii=False, separators=(",", ":"), allow_nan=False
        ).encode()
    ).hexdigest()
    return json.dumps(document, ensure_ascii=False).encode()


def test_complete_snapshot_restore_replaces_data_preserves_auth_and_round(environment, samples):
    settings, media = environment
    original = put(samples / "h264.mov", media / "one.mov")
    put(samples / "portrait.mp4", media / "two.mp4")
    client, token = connect(settings)
    try:
        scan(client)
        videos = client.get("/api/v1/videos").json()["items"]
        marked = tag(client, "原标签")["id"]
        assign(client, [video["id"] for video in videos], [marked])
        active, _ = create_round(client, "random", {"tag_ids": [marked]})
        server_id = client.get("/api/v1/info").json()["server_id"]
        raw, _ = export(client)
        document = json.loads(raw)
        assert document["format"] == "video-viewer-management" and document["version"] == 1
        assert settings.passphrase.encode() not in raw
        assert all(
            secret not in raw
            for secret in (b'"access_tokens"', b'"passphrase_hash"', b'"server_id"')
        )
        assert all(video["thumbnail"] is None for video in document["payload"]["tables"]["videos"])
        client.patch(
            f"/api/v1/tags/{marked}", json={"request_id": "rename-after-backup", "name": "后来改名"}
        )
        extra = tag(client, "不应合并")
        restored, body = restore(client, raw, {"main": str(media)})
        assert restored["status"] == "completed", restored
        assert (
            restored["result"]["available"] == 2
            and restored["result"]["historical_operations_replayed"] == 0
        )
        assert client.get("/api/v1/tags").json()["items"][0]["name"] == "原标签"
        assert client.get("/api/v1/tags").json()["total"] == 1
        scan(client)
        current = client.get("/api/v1/playback").json()
        assert current["id"] == active["id"] and current["current"]["id"] == active["current"]["id"]
        assert client.get("/api/v1/info").json()["server_id"] == server_id
        before = client.get(f"/api/v1/backups/{restored['result']['pre_snapshot_id']}/download")
        assert before.status_code == 200
        assert any(item["id"] == extra["id"] for item in before.json()["payload"]["tables"]["tags"])
        assert client.post("/api/v1/backup-restores", json=body).json()["id"] == restored["id"]
        found = client.get(f"/api/v1/backup-requests/restore/{body['request_id']}")
        assert found.status_code == 200 and found.json()["id"] == restored["id"]
        assert client.get("/api/v1/backup-requests/restore/never-submitted").status_code == 404
        assert hashlib.sha256((media / "one.mov").read_bytes()).hexdigest() == original
    finally:
        client.__exit__(None, None, None)
    client, _ = connect(settings, token=token)
    try:
        assert client.get("/api/v1/tags").json()["items"][0]["name"] == "原标签"
        assert client.get("/api/v1/playback").json()["id"] == active["id"]
    finally:
        client.__exit__(None, None, None)


@pytest.mark.parametrize("damage", ["checksum", "version", "foreign_key", "uuid", "unknown_field"])
def test_bad_packages_are_rejected_without_changing_management(library, samples, damage):
    client, media = library
    put(samples / "h264.mov", media / "one.mov")
    scan(client)
    saved = tag(client, "保留当前")
    raw, _ = export(client)
    document = json.loads(raw)
    if damage == "checksum":
        document["payload"]["tables"]["tags"][0]["name"] = "损坏"
        raw = json.dumps(document).encode()
    else:
        if damage == "version":
            document["version"] = 999
        elif damage == "foreign_key":
            document["payload"]["tables"]["videos"][0]["root_id"] = "does-not-exist"
        elif damage == "uuid":
            document["payload"]["tables"]["videos"][0]["id"] = "../outside"
        else:
            document["payload"]["tables"]["videos"][0]["execute"] = "delete"
        raw = resign(document)
    preview = inspect(client, raw)
    assert preview["status"] == "failed", preview
    assert preview["error"] in {
        "backup_checksum_mismatch",
        "backup_version_unsupported",
        "invalid_backup",
    }, preview
    assert client.get("/api/v1/tags").json()["items"][0]["id"] == saved["id"]
    assert client.get("/api/v1/videos").json()["total"] == 1 and (media / "one.mov").exists()


def test_new_instance_mapping_and_new_credentials_preserve_video_identity(environment, samples):
    settings, media = environment
    put(samples / "h264.mov", media / "one.mov")
    client, old_token = connect(settings)
    scan(client)
    old = client.get("/api/v1/videos").json()["items"][0]
    marked = tag(client, "带到新环境")["id"]
    assign(client, [old["id"]], [marked])
    raw, _ = export(client)
    client.__exit__(None, None, None)
    target = media.with_name("new-media")
    target.mkdir()
    shutil.copyfile(media / "one.mov", target / "one.mov")
    changed = replace(
        settings,
        data_dir=settings.data_dir.with_name("new-data"),
        mounts=(Mount("new-mount", "新挂载", target),),
        passphrase="another-environment-passphrase",
    )
    client, token = connect(changed)
    try:
        assert (
            client.get("/api/v1/info", headers={"Authorization": "Bearer " + old_token}).status_code
            == 401
        )
        restored, _ = restore(client, raw, {"main": str(target)})
        assert restored["status"] == "completed", restored
        fresh = client.get("/api/v1/videos").json()["items"][0]
        assert fresh["id"] == old["id"] and fresh["tag_ids"] == [marked]
        assert fresh["path"] == str(target / "one.mov")
        scan(client)
        assert client.get(fresh["media_url"]).content == (target / "one.mov").read_bytes()
        assert (
            client.post("/api/v1/auth/login", json={"passphrase": settings.passphrase}).status_code
            == 401
        )
    finally:
        client.__exit__(None, None, None)
    client, _ = connect(changed, token=token)
    try:
        assert len(client.get("/api/v1/roots").json()["items"]) == 1
        assert client.get("/api/v1/videos").json()["items"][0]["id"] == old["id"]
    finally:
        client.__exit__(None, None, None)


def test_old_backup_reconciles_current_trash_and_never_replays_purge(library, samples):
    client, media = library
    put(samples / "h264.mov", media / "one.mov")
    put(samples / "portrait.mp4", media / "two.mp4")
    scan(client)
    videos = client.get("/api/v1/videos").json()["items"]
    raw, _ = export(client)
    deleted, _ = trash(client, [videos[0]["id"]])
    restored, _ = restore(client, raw, {"main": str(media)})
    assert restored["status"] == "completed" and restored["result"]["trash"] == 1, restored
    assert (media / "one.mov").exists()  # Logical trash keeps the original in place.
    assert client.get("/api/v1/trash").json()["items"][0]["video"]["id"] == videos[0]["id"]
    assert (
        client.post(
            f"/api/v1/operations/{deleted['id']}/undo", json={"request_id": "old-backup-undo"}
        ).status_code
        == 409
    )
    item = client.get("/api/v1/trash").json()["items"][0]
    assert (
        operation(
            client, "/api/v1/trash/permanent", {"trash_ids": [item["id"]], "confirmed": True}
        )[0]["status"]
        == "completed"
    )
    restored, _ = restore(client, raw, {"main": str(media)})
    assert restored["status"] == "completed" and restored["result"]["missing"] == 1, restored
    assert client.get("/api/v1/trash").json()["total"] == 0
    assert not (media / "one.mov").exists() and (media / "two.mp4").exists()
    assert client.get("/api/v1/videos").json()["total"] == 1


def test_restore_retains_receipts_for_commands_issued_after_backup(library, samples):
    client, media = library
    original = put(samples / "h264.mov", media / "one.mov")
    scan(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    raw, _ = export(client)
    late = tag(client, "后来创建", request_id="late-create")
    deleted, delete_request = trash(client, [video["id"]])
    assert (
        operation(client, f"/api/v1/operations/{deleted['id']}/undo", {})[0]["status"]
        == "completed"
    )
    restored, _ = restore(client, raw, {"main": str(media)})
    assert restored["status"] == "completed", restored
    # Neither a late network replay nor an explicit retry can rerun old deletion.
    assert client.post("/api/v1/videos/trash", json=delete_request).json()["id"] == deleted["id"]
    assert (
        client.post(
            f"/api/v1/operations/{deleted['id']}/retry", json={"request_id": "historical-retry"}
        ).status_code
        == 404
    )
    replay = client.post("/api/v1/tags", json={"request_id": "late-create", "name": "后来创建"})
    assert replay.status_code == 201 and replay.json()["id"] == late["id"]
    assert client.get("/api/v1/tags").json()["total"] == 0
    assert client.get("/api/v1/trash").json()["total"] == 0
    assert hashlib.sha256((media / "one.mov").read_bytes()).hexdigest() == original


def test_unmapped_root_stays_missing_without_scanning_old_environment(environment, samples):
    settings, media = environment
    put(samples / "h264.mov", media / "one.mov")
    client, _ = connect(settings)
    scan(client)
    old = client.get("/api/v1/videos").json()["items"][0]
    marked = tag(client, "未映射保留")["id"]
    assign(client, [old["id"]], [marked])
    raw, _ = export(client)
    client.__exit__(None, None, None)
    target = media.with_name("empty-new-media")
    target.mkdir()
    changed = replace(
        settings,
        data_dir=settings.data_dir.with_name("unmapped-data"),
        mounts=(Mount("new", "new", target),),
    )
    client, token = connect(changed)
    try:
        restored, _ = restore(client, raw, {"main": None})
        assert restored["status"] == "completed", restored
        assert restored["result"]["unmapped_roots"] == ["main"]
        assert client.get("/api/v1/videos").json()["total"] == 0
        missing = client.get("/api/v1/videos?status=missing").json()["items"][0]
        assert (
            missing["id"] == old["id"]
            and missing["tag_ids"] == [marked]
            and missing["error"] == "root_unmapped"
        )
        scan(client)
        assert client.get("/api/v1/videos").json()["total"] == 0
        assert client.get("/api/v1/roots").json()["items"][0]["error"] == "root_unmapped"
    finally:
        client.__exit__(None, None, None)
    client, _ = connect(changed, token=token)
    try:
        assert len(client.get("/api/v1/roots").json()["items"]) == 1
        assert client.get("/api/v1/videos").json()["total"] == 0
    finally:
        client.__exit__(None, None, None)


def test_failure_inside_replacement_rolls_back_and_keeps_pre_restore_snapshot(environment, samples):
    settings, media = environment
    put(samples / "h264.mov", media / "one.mov")

    def fail(phase, _task):
        if phase == "after_replace_before_commit":
            raise RuntimeError("isolated transactional fault")

    client, _ = connect(settings, backup_fault_hook=fail)
    try:
        scan(client)
        saved = tag(client, "备份内容")
        raw, _ = export(client)
        extra = tag(client, "应保留当前状态")
        failed, _ = restore(client, raw, {"main": str(media)})
        assert failed["status"] == "failed", failed
        assert {item["id"] for item in client.get("/api/v1/tags").json()["items"]} == {
            saved["id"],
            extra["id"],
        }
        assert client.get("/api/v1/videos").json()["total"] == 1
        before = client.get(f"/api/v1/backups/{failed['result']['pre_snapshot_id']}/download")
        assert before.status_code == 200 and len(before.json()["payload"]["tables"]["tags"]) == 2
        assert tag(client, "失败后仍可写")["name"] == "失败后仍可写"
    finally:
        client.__exit__(None, None, None)


def test_restore_pauses_writers_keeps_reads_and_accepts_exact_request_replay(environment, samples):
    settings, media = environment
    put(samples / "h264.mov", media / "one.mov")
    reached, release = threading.Event(), threading.Event()

    def pause(phase, _task):
        if phase == "snapshot_written":
            reached.set()
            assert release.wait(10)

    client, _ = connect(settings, backup_fault_hook=pause)
    try:
        scan(client)
        video = client.get("/api/v1/videos").json()["items"][0]
        raw, _ = export(client)
        preview = inspect(client, raw)
        body = {
            "request_id": "paused-restore",
            "preview_id": preview["id"],
            "root_mapping": {"main": str(media)},
            "confirmed": True,
        }
        first = client.post("/api/v1/backup-restores", json=body)
        assert first.status_code == 202 and reached.wait(5)
        assert client.get("/api/v1/info").status_code == 200
        assert client.get(f"/api/v1/tasks/{first.json()['id']}").status_code == 200
        assert client.post("/api/v1/backup-restores", json=body).json()["id"] == first.json()["id"]
        assert client.post("/api/v1/scans").status_code == 503
        assert (
            client.post(
                "/api/v1/tags", json={"request_id": "blocked-tag", "name": "不可写"}
            ).status_code
            == 503
        )
        assert (
            client.post(
                "/api/v1/videos/trash",
                json={"request_id": "blocked-delete", "video_ids": [video["id"]]},
            ).status_code
            == 503
        )
        assert (media / "one.mov").exists()
        release.set()
        assert wait_task(client, first.json()["id"])["status"] == "completed"
        assert client.get("/api/v1/videos").json()["items"][0]["id"] == video["id"]
    finally:
        release.set()
        client.__exit__(None, None, None)


def test_restore_requires_confirmation_and_rejects_unsafe_or_incomplete_mapping(library, samples):
    client, media = library
    put(samples / "h264.mov", media / "one.mov")
    scan(client)
    raw, _ = export(client)
    preview = inspect(client, raw)
    body = {
        "request_id": "mapping-check",
        "preview_id": preview["id"],
        "root_mapping": {"main": str(media)},
        "confirmed": False,
    }
    assert client.post("/api/v1/backup-restores", json=body).status_code == 422
    for mapping in ({}, {"main": "/etc"}, {"main": str(settings_dir := media.parent / "data")}):
        response = client.post(
            "/api/v1/backup-restores", json={**body, "confirmed": True, "root_mapping": mapping}
        )
        assert response.status_code == 422, response.text
    assert settings_dir.exists()
    assert client.get("/api/v1/videos").json()["total"] == 1 and (media / "one.mov").exists()


def test_restored_old_trash_state_accepts_current_restored_file(library, samples):
    client, media = library
    digest = put(samples / "h264.mov", media / "one.mov")
    scan(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    assert trash(client, [video["id"]])[0]["status"] == "completed"
    raw, _ = export(client)
    item = client.get("/api/v1/trash").json()["items"][0]
    assert (
        operation(client, "/api/v1/trash/restore", {"trash_ids": [item["id"]]})[0]["status"]
        == "completed"
    )
    restored, _ = restore(client, raw, {"main": str(media)})
    assert restored["status"] == "completed" and restored["result"]["available"] == 1, restored
    assert client.get("/api/v1/trash").json()["total"] == 0
    assert client.get("/api/v1/videos").json()["items"][0]["id"] == video["id"]
    assert hashlib.sha256((media / "one.mov").read_bytes()).hexdigest() == digest


def test_export_during_tag_writes_produces_consistent_publicly_validated_snapshot(library, samples):
    client, media = library
    digest = put(samples / "h264.mov", media / "one.mov")
    scan(client)
    video = client.get("/api/v1/videos").json()["items"][0]

    def write_tags():
        for i in range(10):
            temporary = tag(client, f"并发标签{i}")
            assign(client, [video["id"]], [temporary["id"]])
            response = client.request(
                "DELETE", f"/api/v1/tags/{temporary['id']}", json={"request_id": str(uuid.uuid4())}
            )
            assert response.status_code == 200

    with ThreadPoolExecutor(max_workers=1) as pool:
        writer = pool.submit(write_tags)
        for _ in range(3):
            raw, _ = export(client)
            preview = inspect(client, raw)
            assert preview["status"] == "completed", preview
            tables = json.loads(raw)["payload"]["tables"]
            assert {link["tag_id"] for link in tables["video_tags"]} <= {
                item["id"] for item in tables["tags"]
            }
        writer.result(timeout=10)
    assert hashlib.sha256((media / "one.mov").read_bytes()).hexdigest() == digest


def test_restore_refuses_active_scan_and_modified_inspected_artifact(environment, samples):
    settings, media = environment
    settings = replace(settings, stability_seconds=0.4)
    put(samples / "h264.mov", media / "one.mov")
    client, _ = connect(settings)
    try:
        scan(client)
        saved = tag(client, "原标签")
        raw, _ = export(client)
        preview = inspect(client, raw)
        body = {
            "request_id": "busy-restore",
            "preview_id": preview["id"],
            "root_mapping": {"main": str(media)},
            "confirmed": True,
        }
        put(samples / "portrait.mp4", media / "arriving.mp4")
        started = client.post("/api/v1/scans").json()
        wait_phase(client, started["id"], "waiting_for_stable_files")
        busy = client.post("/api/v1/backup-restores", json=body)
        assert busy.status_code == 409 and busy.json()["error"]["code"] == "library_busy"
        assert wait_task(client, started["id"])["status"] == "completed"
        altered = json.loads(raw)
        altered["payload"]["tables"]["tags"][0]["name"] = "与预览不同"
        (settings.data_dir / "backups" / (preview["id"] + ".json")).write_bytes(resign(altered))
        rejected = client.post("/api/v1/backup-restores", json=body)
        assert (
            rejected.status_code == 409
            and rejected.json()["error"]["code"] == "backup_artifact_changed"
        )
        assert client.get("/api/v1/tags").json()["items"][0]["id"] == saved["id"]
    finally:
        client.__exit__(None, None, None)


def test_backup_upload_limit_rejects_before_creating_job(environment):
    settings, _ = environment
    client, _ = connect(replace(settings, backup_max_bytes=4096))
    try:
        saved = tag(client, "保留")
        previous = client.get("/api/v1/tasks").json()
        response = client.post("/api/v1/backup-imports", content=b" " * 4097)
        assert (
            response.status_code == 413 and response.json()["error"]["code"] == "backup_too_large"
        )
        assert client.get("/api/v1/tasks").json() == previous
        assert client.get("/api/v1/tags").json()["items"][0]["id"] == saved["id"]
    finally:
        client.__exit__(None, None, None)
