"""Confirmed physical image purges over authenticated APIs and disposable files."""

import errno
from pathlib import Path

import pytest

from video_viewer.models import PackPurgeStep

from .conftest import connect
from .test_pack_operations import command, restore, tree, wait
from .test_pack_purge_plans import fixture, prepare
from .test_pack_purge_plans import wait as wait_plan
from .test_packs import image, packs, sync


def plan(client, ids, key="plan"):
    value = wait_plan(client, prepare(client, ids, key)["id"])
    assert value["ready"], value
    return value


def execute(client, value, key="execute", status=202, **extra):
    task = command(
        client,
        "pack-trash/permanent",
        {
            "request_id": key,
            "plan_id": value["id"],
            "digest": value["digest"],
            "confirmed": True,
            **extra,
        },
        status,
    )
    return wait(client, task["id"]) if status == 202 else task


def test_confirmed_images_deleted_attachments_retained_and_precise_results(library):
    client, media = library
    root, catalog, rows = fixture(client, media)
    before = tree(media)
    value = plan(client, [rows[0]["id"]])
    result = execute(client, value)
    assert result["status"] == "completed", result
    assert result["result"]["pages_deleted"] == result["result"]["pages_total"] == 2
    assert result["result"]["succeeded"] == 1 and not result["result"]["partial"]
    after = tree(media)
    assert after == {name: sha for name, sha in before.items() if name.endswith("notes.txt")}
    base = Path(root["path"]) / "pack-0"
    assert base.is_dir() and (base / "notes.txt").read_text() == "retain attachment"
    assert not (base / "nested").exists() and not (base / "empty").exists()
    assert client.get("/api/v1/pack-trash").json()["total"] == 0
    page = client.get(f"/api/v1/pack-operations/{result['id']}/pages", params={"limit": 1}).json()
    assert page["total"] == 5 and len(page["items"]) == 1
    assert client.get(f"/api/v1/packs/{catalog[0]['id']}/pages").status_code == 404
    assert execute(client, value)["id"] == result["id"]
    assert (
        execute(client, value, key="second", status=409)["error"]["code"] == "purge_plan_consumed"
    )


def test_entirely_empty_pack_directory_removed_without_recursive_delete(library):
    client, media = library
    root, _, rows = fixture(client, media)
    base = Path(root["path"]) / "pack-0"
    # Attachment removal predates the confirmation, so the exact tree contains none.
    (base / "notes.txt").unlink()
    result = execute(client, plan(client, [rows[0]["id"]]))
    assert result["status"] == "completed", result
    assert not base.exists() and tree(media) == {}


def test_partial_page_failure_restores_claim_and_remaining_pack_can_be_restored(library):
    client, media = library
    root, catalog, rows = fixture(client, media)
    value = plan(client, [rows[0]["id"]])
    purge = client.app.state.pack_purge

    def fail(phase, identity):
        if phase == "purge_purging":
            with client.app.state.db.read() as db:
                row = db.get(PackPurgeStep, identity)
                if row.relative_path == "nested/2.jpg":
                    raise OSError(errno.EACCES, "fixture permission failure")

    purge.fault_hook = fail
    result = execute(client, value)
    assert result["status"] == "failed" and result["result"]["partial"], result
    assert result["result"]["pages_deleted"] == 1
    base = Path(root["path"]) / "pack-0"
    assert not (base / "1.png").exists() and (base / "nested/2.jpg").exists()
    listing = client.get("/api/v1/pack-trash").json()["items"][0]
    assert listing["page_count"] == listing["pack"]["page_count"] == 1
    assert listing["purged_pages"] == 1
    purge.fault_hook = None
    restored = restore(client, [rows[0]["id"]])
    assert restored["result"]["succeeded"] == 1
    assert packs(client)["items"][0]["page_count"] == 1
    sync(client)
    assert packs(client)["items"][0]["id"] == catalog[0]["id"]
    assert packs(client)["items"][0]["page_count"] == 1
    # Retrying the old confirmed operation cannot delete a subsequently restored pack.
    retried = command(client, f"pack-operations/{result['id']}/retry", {"request_id": "old-retry"})
    assert wait(client, retried["id"])["status"] == "failed"
    assert (base / "nested/2.jpg").exists()


@pytest.mark.parametrize(
    "change",
    [
        "new-image",
        "new-attachment",
        "replace-image",
        "touch-image",
        "replace-pack",
        "replace-nested",
        "image-link",
    ],
)
def test_post_confirmation_changes_stop_before_any_image_is_deleted(library, change):
    import os

    client, media = library
    root, _, rows = fixture(client, media)
    value = plan(client, [rows[0]["id"]])
    base = Path(root["path"]) / "pack-0"
    target = base / "1.png"
    if change == "new-image":
        image(base / "new.png")
    elif change == "new-attachment":
        (base / "new.txt").write_text("new attachment")
    elif change == "replace-image":
        other = base / "replacement"
        other.write_bytes(target.read_bytes())
        os.replace(other, target)
    elif change == "touch-image":
        info = target.stat()
        os.utime(target, ns=(info.st_atime_ns, info.st_mtime_ns + 1_000_000))
    elif change == "replace-pack":
        base.rename(base.with_name("old-pack"))
        image(target)
    elif change == "replace-nested":
        (base / "nested").rename(base / "original-nested")
        image(base / "nested/2.jpg")
    elif change == "image-link":
        target.unlink()
        target.symlink_to(base / "nested/2.jpg")
    before = tree(media)
    result = execute(client, value)
    assert result["status"] == "failed", result
    assert result["result"]["pages_deleted"] == 0 and tree(media) == before


@pytest.mark.parametrize("confirmed", [False, "true", 1, None])
def test_strict_second_confirmation_requires_boolean_true(library, confirmed):
    client, media = library
    _, _, rows = fixture(client, media)
    value = plan(client, [rows[0]["id"]])
    before = tree(media)
    execute(client, value, status=422, confirmed=confirmed)
    assert tree(media) == before
    assert client.get("/api/v1/pack-trash").json()["total"] == 1


def test_expired_and_wrong_digest_are_refused_without_starting_file_work(library):
    client, media = library
    _, _, rows = fixture(client, media)
    value = plan(client, [rows[0]["id"]])
    before = tree(media)
    assert (
        execute(client, value, status=409, digest="0" * 64)["error"]["code"] == "purge_plan_changed"
    )
    client.app.state.pack_files.clock = lambda: value["expires_at"] + 1
    assert execute(client, value, status=409)["error"]["code"] == "purge_plan_expired"
    assert tree(media) == before


def test_queued_receipt_only_query_and_plan_consumption_are_durable(library, monkeypatch):
    client, media = library
    _, _, rows = fixture(client, media)
    value = plan(client, [rows[0]["id"]])
    ops = client.app.state.pack_files
    monkeypatch.setattr(ops, "enqueue", lambda _: None)
    body = {
        "request_id": "pending",
        "plan_id": value["id"],
        "digest": value["digest"],
        "confirmed": True,
    }
    before = tree(media)
    response = client.post("/api/v1/pack-trash/permanent", json=body)
    assert response.status_code == 202
    identity = response.json()["id"]
    assert response.json()["status"] == "queued"
    assert client.get("/api/v1/pack-file-requests/pending").json()["id"] == identity
    assert client.post("/api/v1/pack-trash/permanent", json=body).json()["id"] == identity
    consumed = client.get(f"/api/v1/pack-purge-plans/{value['id']}").json()
    assert consumed["operation_id"] == identity and not consumed["ready"]
    assert client.get("/api/v1/pack-file-requests/not-found").status_code == 404
    assert (
        client.get(
            f"/api/v1/pack-operations/{identity}/pages", headers={"Authorization": ""}
        ).status_code
        == 401
    )
    assert (
        client.post(
            "/api/v1/pack-trash/permanent", headers={"Authorization": ""}, json=body
        ).status_code
        == 401
    )
    assert (
        client.post("/api/v1/pack-trash/permanent", json={**body, "digest": "0" * 64}).status_code
        == 409
    )
    assert tree(media) == before


@pytest.mark.parametrize("mutation", ["new-image", "attachment", "claimed-content"])
def test_mutation_after_claim_preserves_changed_files_and_returns_owned_claim(library, mutation):
    client, media = library
    root, _, rows = fixture(client, media)
    value = plan(client, [rows[0]["id"]])
    base = Path(root["path"]) / "pack-0"
    purge = client.app.state.pack_purge
    changed = []

    def hook(phase, identity):
        if phase == "purge_claimed" and not changed:
            changed.append(True)
            if mutation == "new-image":
                image(base / "new.png")
            elif mutation == "attachment":
                (base / "notes.txt").write_text("changed attachment")
            else:
                stage = purge.tree.staging(purge.rows[identity])
                stage.write_bytes(b"changed after claim")

    purge.fault_hook = hook
    result = execute(client, value)
    assert changed and result["status"] == "failed" and result["result"]["pages_deleted"] == 0, (
        result
    )
    assert (base / "1.png").exists() and (base / "nested/2.jpg").exists()
    assert not list((Path(root["path"]) / ".video-viewer-tmp").rglob("*.png"))
    if mutation == "new-image":
        assert (base / "new.png").exists()
    elif mutation == "attachment":
        assert (base / "notes.txt").read_text() == "changed attachment"
    else:
        assert (base / "1.png").read_bytes() == b"changed after claim"


def test_source_collision_preserves_both_versions_until_explicit_retry_after_resolution(library):
    client, media = library
    root, _, rows = fixture(client, media)
    value = plan(client, [rows[0]["id"]])
    base = Path(root["path"]) / "pack-0"
    purge = client.app.state.pack_purge
    claimed = []

    def hook(phase, identity):
        if phase == "purge_purging" and not claimed:
            stage = purge.tree.staging(purge.rows[identity])
            claimed.append((stage, stage.read_bytes()))
            (base / "1.png").write_bytes(b"new unconfirmed file")

    purge.fault_hook = hook
    result = execute(client, value)
    assert result["status"] == "failed" and result["result"]["pages_deleted"] == 0
    assert result["result"]["items"][0]["phase"] == "needs_attention"
    assert claimed[0][0].read_bytes() == claimed[0][1]
    assert (base / "1.png").read_bytes() == b"new unconfirmed file"
    assert restore(client, [rows[0]["id"]])["result"]["succeeded"] == 0
    (
        base / "1.png"
    ).unlink()  # Fixture resolves the external collision; the service never overwrites it.
    purge.fault_hook = None
    retried = command(client, f"pack-operations/{result['id']}/retry", {"request_id": "resolved"})
    completed = wait(client, retried["id"])
    assert completed["status"] == "completed" and completed["result"]["pages_deleted"] == 2, (
        completed
    )
    assert (base / "notes.txt").exists()


@pytest.mark.parametrize(
    "phase",
    [
        "purge_claiming",
        "purge_claimed",
        "purge_verified",
        "purge_purging",
        "purge_unlinked_before_commit",
        "purge_image_committed",
        "purge_directory_claiming",
        "purge_directory_claimed",
        "purge_removing",
        "purge_directory_removed",
    ],
)
def test_cold_service_recovery_reconciles_each_durable_phase(environment, phase):
    settings, media = environment
    first, token = connect(settings)
    second = None
    try:
        root, _, rows = fixture(first, media)
        base = Path(root["path"]) / "pack-0"
        value = plan(first, [rows[0]["id"]])
        interrupted = []

        def hook(current, _):
            if current == phase and not interrupted:
                interrupted.append(True)
                raise InterruptedError("fixture cold restart")

        first.app.state.pack_purge.fault_hook = hook
        result = execute(first, value)
        assert interrupted and result["status"] == "interrupted", result
        identity = result["id"]
        first.__exit__(None, None, None)
        first = None
        second, _ = connect(settings, token=token)
        recovered = wait(second, identity)
        assert recovered["status"] == "completed", recovered
        assert recovered["result"]["pages_deleted"] == recovered["result"]["pages_total"] == 2
        assert (base / "notes.txt").read_text() == "retain attachment"
        assert not (base / "1.png").exists() and not (base / "nested").exists()
        assert execute(second, value)["id"] == identity
    finally:
        if first:
            first.__exit__(None, None, None)
        if second:
            second.__exit__(None, None, None)


@pytest.mark.parametrize(
    "phase,expected_deleted", [("purge_unlinked_before_commit", 0), ("purge_image_committed", 1)]
)
def test_io_failure_after_irreversible_work_does_not_overwrite_committed_steps(
    library, phase, expected_deleted
):
    client, media = library
    root, _, rows = fixture(client, media)
    value = plan(client, [rows[0]["id"]])
    purge = client.app.state.pack_purge
    fired = []

    def hook(current, _):
        if current == phase and not fired:
            fired.append(True)
            raise OSError(errno.EIO, "fixture acknowledgement failure")

    purge.fault_hook = hook
    result = execute(client, value)
    assert result["status"] == "failed", result
    assert result["result"]["partial"] == bool(expected_deleted)
    assert result["result"]["pages_deleted"] == expected_deleted
    if not expected_deleted:
        assert result["result"]["pages_pending_reconciliation"] == 1
        assert result["result"]["items"][0]["phase"] == "needs_attention"
        assert restore(client, [rows[0]["id"]])["result"]["succeeded"] == 0
    purge.fault_hook = None
    retried = command(client, f"pack-operations/{result['id']}/retry", {"request_id": "reconcile"})
    complete = wait(client, retried["id"])
    assert complete["status"] == "completed" and complete["result"]["pages_deleted"] == 2, complete
    assert (Path(root["path"]) / "pack-0/notes.txt").exists()


def test_foreign_replacement_in_staging_is_preserved_and_not_unlinked(library):
    import os

    client, media = library
    root, _, rows = fixture(client, media)
    value = plan(client, [rows[0]["id"]])
    purge = client.app.state.pack_purge
    stages = []

    def hook(phase, identity):
        if phase == "purge_purging" and not stages:
            stage = purge.tree.staging(purge.rows[identity])
            foreign = stage.with_name("foreign")
            foreign.write_bytes(b"do not unlink a replacement")
            os.replace(foreign, stage)
            stages.append(stage)

    purge.fault_hook = hook
    result = execute(client, value)
    assert result["status"] == "failed" and result["result"]["pages_deleted"] == 0
    assert stages[0].read_bytes() == b"do not unlink a replacement"
    assert result["result"]["items"][0]["phase"] == "needs_attention"
    assert (Path(root["path"]) / "pack-0/nested/2.jpg").exists()


def test_file_arriving_during_empty_directory_claim_is_preserved(library):
    client, media = library
    root, _, rows = fixture(client, media)
    base = Path(root["path"]) / "pack-0"
    value = plan(client, [rows[0]["id"]])
    purge = client.app.state.pack_purge
    added = []

    def hook(phase, identity):
        if phase == "purge_directory_claimed" and not added:
            row = purge.rows[identity]
            if row.relative_path == "nested":
                added.append(True)
                image(purge.tree.staging(row) / "new.png", color="green")

    purge.fault_hook = hook
    result = execute(client, value)
    assert added and result["status"] == "failed" and result["result"]["pages_deleted"] == 2
    assert (base / "nested/new.png").exists()
    assert (base / "notes.txt").exists()
    assert restore(client, [rows[0]["id"]])["result"]["succeeded"] == 1
    assert packs(client, status="unreadable")["total"] == 1
    sync(client)
    assert packs(client)["items"][0]["page_count"] == 1
    assert (base / "nested/new.png").exists()


def test_one_changed_pack_does_not_stop_independent_confirmed_pack(library):
    client, media = library
    root, _, rows = fixture(client, media, count=2)
    value = plan(client, [r["id"] for r in rows])
    base = Path(root["path"])
    image(base / "pack-0/new.png")
    failed_pack_before = tree(base / "pack-0")
    result = execute(client, value)
    assert result["status"] == "completed" and result["result"]["partial"], result
    assert result["result"]["succeeded"] == result["result"]["failed"] == 1
    assert tree(base / "pack-0") == failed_pack_before
    assert tree(base / "pack-1") == {"notes.txt": tree(base / "pack-1")["notes.txt"]}
    assert result["result"]["pages_deleted"] == 2


@pytest.mark.parametrize("change", ["disabled-root", "historical-plan"])
def test_accepted_execution_rechecks_authority_before_any_file_work(library, monkeypatch, change):
    from video_viewer.models import PackPurgePlan, Root

    client, media = library
    root, _, rows = fixture(client, media)
    value = plan(client, [rows[0]["id"]])
    ops = client.app.state.pack_files
    enqueue = ops.enqueue
    monkeypatch.setattr(ops, "enqueue", lambda _: None)
    task = command(
        client,
        "pack-trash/permanent",
        {
            "request_id": "held",
            "plan_id": value["id"],
            "digest": value["digest"],
            "confirmed": True,
        },
    )
    with client.app.state.db.write() as db:
        if change == "disabled-root":
            db.get(Root, root["id"]).enabled = False
        else:
            db.get(PackPurgePlan, value["id"]).historical = True
    before = tree(media)
    enqueue(task["id"])
    result = wait(client, task["id"])
    assert result["status"] == "failed" and result["result"]["pages_deleted"] == 0, result
    assert tree(media) == before


def test_physical_hash_and_claim_do_not_hold_global_database_write_lock(library):
    import threading

    from .test_media_types import pack_tag

    client, media = library
    _, _, rows = fixture(client, media)
    value = plan(client, [rows[0]["id"]])
    reached, release = threading.Event(), threading.Event()

    def hook(phase, _):
        if phase == "purge_claimed" and not reached.is_set():
            reached.set()
            assert release.wait(5)

    client.app.state.pack_purge.fault_hook = hook
    task = command(
        client,
        "pack-trash/permanent",
        {
            "request_id": "background",
            "plan_id": value["id"],
            "digest": value["digest"],
            "confirmed": True,
        },
    )
    try:
        assert reached.wait(5)
        assert client.get("/api/v1/info").status_code == 200
        assert (
            pack_tag(client, name="during physical operation")["name"]
            == "during physical operation"
        )
        assert client.get("/api/v1/pack-file-requests/background").json()["id"] == task["id"]
    finally:
        release.set()
    assert wait(client, task["id"])["status"] == "completed"


def test_expiry_after_acceptance_does_not_cancel_the_accepted_operation(library, monkeypatch):
    client, media = library
    _, _, rows = fixture(client, media)
    value = plan(client, [rows[0]["id"]])
    ops = client.app.state.pack_files
    enqueue = ops.enqueue
    monkeypatch.setattr(ops, "enqueue", lambda _: None)
    body = {
        "request_id": "accepted-before-expiry",
        "plan_id": value["id"],
        "digest": value["digest"],
        "confirmed": True,
    }
    task = command(client, "pack-trash/permanent", body)
    ops.clock = lambda: value["expires_at"] + 100
    enqueue(task["id"])
    assert wait(client, task["id"])["status"] == "completed"
    assert client.post("/api/v1/pack-trash/permanent", json=body).json()["id"] == task["id"]


def test_known_accepted_command_remains_readable_during_maintenance_without_enqueue(
    library, monkeypatch
):
    client, media = library
    _, _, rows = fixture(client, media)
    value = plan(client, [rows[0]["id"]])
    ops = client.app.state.pack_files
    monkeypatch.setattr(ops, "enqueue", lambda _: None)
    body = {
        "request_id": "known",
        "plan_id": value["id"],
        "digest": value["digest"],
        "confirmed": True,
    }
    task = command(client, "pack-trash/permanent", body)
    db = client.app.state.db
    before = tree(media)
    db.maintenance_task = "fixture-restore"
    try:
        assert client.get("/api/v1/pack-file-requests/known").json()["id"] == task["id"]
        assert client.post("/api/v1/pack-trash/permanent", json=body).json()["id"] == task["id"]
        assert (
            client.post(
                "/api/v1/pack-trash/permanent", json={**body, "request_id": "new-key"}
            ).status_code
            == 503
        )
    finally:
        db.maintenance_task = None
    assert tree(media) == before


def test_new_images_at_purged_path_get_a_new_identity_and_do_not_inherit_old_tags(library):
    from .test_media_types import pack_root, pack_tag

    client, media = library
    root = pack_root(client, media)
    target = Path(root["path"]) / "same-name/1.png"
    image(target)
    sync(client)
    original = packs(client)["items"][0]
    tag = pack_tag(client, name="old identity")
    assert (
        client.patch(
            "/api/v1/pack-tag-links",
            json={"request_id": "assign-old", "pack_ids": [original["id"]], "tag_ids": [tag["id"]]},
        ).status_code
        == 200
    )
    queued = command(
        client, "packs/trash", {"request_id": "old-trash", "pack_ids": [original["id"]]}
    )
    assert wait(client, queued["id"])["status"] == "completed"
    entry = client.get("/api/v1/pack-trash").json()["items"][0]
    result = execute(client, plan(client, [entry["id"]]))
    assert result["status"] == "completed" and not target.parent.exists()
    image(target, color="green")
    sync(client)
    current = packs(client)["items"][0]
    assert current["id"] != original["id"] and current["tag_ids"] == []
    assert client.get(f"/api/v1/packs/{original['id']}/pages").status_code == 404
    assert target.exists()


def test_confirming_permanent_delete_invalidates_only_its_original_logical_undo(
    library, monkeypatch
):
    client, media = library
    _, _, rows = fixture(client, media)
    value = plan(client, [rows[0]["id"]])
    ops = client.app.state.pack_files
    ops.clock = lambda: rows[0]["deleted_at"] + 1
    monkeypatch.setattr(ops, "enqueue", lambda _: None)
    before = tree(media)
    task = command(
        client,
        "pack-trash/permanent",
        {
            "request_id": "accepted",
            "plan_id": value["id"],
            "digest": value["digest"],
            "confirmed": True,
        },
    )
    assert task["status"] == "queued"
    result = command(
        client, f"pack-operations/{rows[0]['operation_id']}/undo", {"request_id": "old-undo"}, 409
    )
    assert result["error"]["code"] == "stale_delete" and tree(media) == before


def test_confirming_an_older_pack_does_not_invalidate_unrelated_latest_undo(library, monkeypatch):
    client, media = library
    _, _, rows = fixture(client, media, count=2)
    older, latest = rows
    assert restore(client, [latest["id"]], key="restore-latest")["result"]["succeeded"] == 1
    submitted = command(
        client, "packs/trash", {"request_id": "new-latest", "pack_ids": [latest["pack"]["id"]]}
    )
    current = wait(client, submitted["id"])
    assert current["status"] == "completed"
    value = plan(client, [older["id"]])
    ops = client.app.state.pack_files
    monkeypatch.setattr(ops, "enqueue", lambda _: None)
    command(
        client,
        "pack-trash/permanent",
        {
            "request_id": "purge-older",
            "plan_id": value["id"],
            "digest": value["digest"],
            "confirmed": True,
        },
    )
    untouched = command(
        client, f"pack-operations/{current['id']}/undo", {"request_id": "unrelated-undo"}
    )
    assert untouched["status"] == "queued"
