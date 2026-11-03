import threading
import time
from pathlib import Path

import pytest
from sqlalchemy import event, select

from video_viewer.models import ImagePack, PackPurgePlan, PackTrashItem, Root

from .test_pack_purge_plans import fixture


def submit(client, ids, key="directory-delete"):
    return client.post(
        "/api/v1/pack-trash/directories/permanent",
        json={"request_id": key, "trash_ids": ids, "confirmed": True},
    )


def wait(client, identity):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        task = client.get("/api/v1/pack-operations/" + identity).json()
        if task["status"] not in ("queued", "running"):
            return task
        time.sleep(0.01)
    raise AssertionError(task)


def test_deletes_entire_directory_with_attachments_new_files_and_links_without_hashing(
    library, monkeypatch
):
    client, media = library
    root, packs, rows = fixture(client, media)
    path = Path(packs[0]["path"])
    outside = media / "outside"
    outside.mkdir()
    (outside / "keep.txt").write_text("outside link target")
    (path / "external").symlink_to(outside, target_is_directory=True)
    (path / "new-after-trash.jpg").write_bytes(b"no image inspection needed")
    (path / ".hidden").write_text("delete with folder")
    monkeypatch.setattr(
        client.app.state.pack_purge_plans.inspector,
        "hash_file",
        lambda *_: pytest.fail("must not read images"),
    )
    result = submit(client, [rows[0]["id"]])
    assert result.status_code == 202, result.text
    task = wait(client, result.json()["id"])
    assert task["kind"] == "pack_directory_delete" and task["status"] == "completed", task
    assert not path.exists() and (outside / "keep.txt").read_text() == "outside link target"
    assert Path(root["path"]).exists()
    assert client.get("/api/v1/pack-trash").json()["total"] == 0
    with client.app.state.db.read() as db:
        assert db.get(ImagePack, packs[0]["id"]).status == "deleted"
        assert db.get(PackTrashItem, rows[0]["id"]).status == "purged"
        assert list(db.scalars(select(PackPurgePlan))) == []
    summary = client.get("/api/v1/maintenance-tasks/" + task["id"]).json()
    assert summary["state"] == "completed" and summary["total"] == summary["processed"] == 1


def test_acceptance_returns_while_worker_is_blocked_and_repeated_key_does_not_delete_again(library):
    client, media = library
    _, packs, rows = fixture(client, media)
    reached, release = threading.Event(), threading.Event()

    def pause(phase, _):
        if phase == "before_directory":
            reached.set()
            assert release.wait(10)

    client.app.state.pack_files.directory_delete.fault_hook = pause
    try:
        accepted = submit(client, [rows[0]["id"]])
        assert accepted.status_code == 202 and reached.wait(3)
        assert Path(packs[0]["path"]).exists()
        assert submit(client, [rows[0]["id"]]).json()["id"] == accepted.json()["id"]
        assert client.get("/api/v1/pack-trash").json()["total"] == 0
        assert client.get("/api/v1/info").status_code == 200
    finally:
        release.set()
    assert wait(client, accepted.json()["id"])["result"]["succeeded"] == 1


def test_large_acceptance_uses_only_directory_columns_and_bounded_query_count(library, monkeypatch):
    client, media = library
    root, packs, rows = fixture(client, media)
    monkeypatch.setattr(client.app.state.pack_files, "enqueue", lambda _: None)
    ids = [rows[0]["id"]]
    with client.app.state.db.write() as db:
        for i in range(621):
            path = root["path"] + "/synthetic-" + str(i)
            p = ImagePack(
                id="synthetic-" + str(i),
                root_id=root["id"],
                name=str(i),
                path=path,
                status="trash",
                device="1",
                inode=str(i + 10),
                page_count=100,
            )
            db.add(p)
            db.flush()
            item = PackTrashItem(
                pack_id=p.id,
                operation_id=rows[0]["operation_id"],
                root_path=root["path"],
                original_path=path,
                manifest={"private_media_manifest": "x" * 20000},
            )
            db.add(item)
            db.flush()
            ids.append(item.id)
    reads = []

    def observe(_, __, statement, ___, ____, _____):
        if statement.lstrip().upper().startswith("SELECT"):
            reads.append(statement)

    event.listen(client.app.state.db.engine, "before_cursor_execute", observe)
    try:
        accepted = submit(client, ids)
    finally:
        event.remove(client.app.state.db.engine, "before_cursor_execute", observe)
    assert accepted.status_code == 202 and accepted.json()["result"]["total"] == 622
    assert len(reads) < 20, len(reads)
    assert not any("pack_pages" in s or "pack_trash_items.manifest" in s for s in reads)
    assert len(accepted.content) < 2048


def test_replaced_directory_refuses_deletion_and_keeps_original_and_replacement(
    library, monkeypatch
):
    client, media = library
    _, packs, rows = fixture(client, media)
    ops = client.app.state.pack_files
    monkeypatch.setattr(ops, "enqueue", lambda _: None)
    accepted = submit(client, [rows[0]["id"]]).json()
    path = Path(packs[0]["path"])
    original = path.with_name("original-retained")
    path.rename(original)
    path.mkdir()
    (path / "replacement.txt").write_text("keep")
    ops.directory_delete.run(accepted["id"])
    result = wait(client, accepted["id"])
    assert result["result"]["failed"] == 1
    assert (path / "replacement.txt").read_text() == "keep" and (original / "1.png").exists()


def test_restart_after_claim_resumes_original_folder_without_new_request(library):
    client, media = library
    _, packs, rows = fixture(client, media)
    ops = client.app.state.pack_files

    def stop(phase, _):
        if phase == "claimed":
            raise InterruptedError()

    ops.directory_delete.fault_hook = stop
    accepted = submit(client, [rows[0]["id"]]).json()
    assert wait(client, accepted["id"])["status"] == "interrupted"
    ops.directory_delete.fault_hook = None
    ops.start()
    assert wait(client, accepted["id"])["result"]["succeeded"] == 1
    assert not Path(packs[0]["path"]).exists()


def test_restart_after_rmtree_before_commit_preserves_a_new_original_path(library):
    client, media = library
    _, packs, rows = fixture(client, media)
    path = Path(packs[0]["path"])
    ops = client.app.state.pack_files

    def stop(phase, _):
        if phase == "removed_before_commit":
            path.mkdir()
            (path / "new-folder.txt").write_text("never delete this replacement")
            raise InterruptedError()

    ops.directory_delete.fault_hook = stop
    accepted = submit(client, [rows[0]["id"]]).json()
    assert wait(client, accepted["id"])["status"] == "interrupted"
    ops.directory_delete.fault_hook = None
    ops.start()
    assert wait(client, accepted["id"])["result"]["succeeded"] == 1
    assert (path / "new-folder.txt").read_text() == "never delete this replacement"


def test_nested_configured_root_and_unconfirmed_request_do_not_remove(library):
    client, media = library
    root, packs, rows = fixture(client, media)
    path = Path(packs[0]["path"])
    with client.app.state.db.write() as db:
        db.add(
            Root(
                id="protected",
                name="separate",
                kind="pack",
                path=str(path / "nested"),
                mount_id=db.get(Root, root["id"]).mount_id,
                enabled=True,
                available=True,
            )
        )
    response = submit(client, [rows[0]["id"]])
    assert response.status_code == 409 and path.exists()
    for flag in (False, 1, "true"):
        response = client.post(
            "/api/v1/pack-trash/directories/permanent",
            json={"request_id": "not-confirmed", "trash_ids": [rows[0]["id"]], "confirmed": flag},
        )
        assert response.status_code == 422


def test_directory_deletion_records_export_and_import_without_image_plan(library):
    from .test_management_archives import export, inspect

    client, media = library
    _, _, rows = fixture(client, media)
    accepted = submit(client, [rows[0]["id"]]).json()
    assert wait(client, accepted["id"])["result"]["succeeded"] == 1
    raw, _ = export(client)
    assert b"pack_directory_delete" in raw
    inspected = inspect(client, raw)
    assert inspected["result"]["counts"]["pack_file_operations"] == 2
    assert inspected["result"]["counts"]["pack_purge_plans"] == 0


def test_retired_legacy_preparation_does_not_restart_hashing(library, monkeypatch):
    from dataclasses import replace

    from .test_pack_purge_plans import prepare

    client, media = library
    _, _, rows = fixture(client, media)
    plans = client.app.state.pack_purge_plans
    monkeypatch.setattr(plans, "enqueue", lambda _: None)
    old = prepare(client, [rows[0]["id"]])
    monkeypatch.setattr(plans, "settings", replace(plans.settings, legacy_purge_previews=False))
    plans.start()
    result = client.get("/api/v1/pack-purge-plans/" + old["id"]).json()
    assert result["status"] == "interrupted" and result["error"] == "preview_superseded"
    assert (
        prepare(client, [rows[0]["id"]], key="another", status=410)["error"]["code"]
        == "preview_superseded"
    )
