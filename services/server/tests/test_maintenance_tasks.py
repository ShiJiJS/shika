"""Public task browsing is bounded, typed and strictly read-only."""

import json

import pytest
from sqlalchemy import event, func, select
from sqlalchemy.orm import Session

from video_viewer.models import FileOperation, FileStep, PackFileOperation, Task

from .test_pack_operations import command, wait
from .test_pack_purge_execution import execute, plan
from .test_pack_purge_plans import fixture


def seed(client, identity, kind, status="completed", *, result=None, historical=False):
    with client.app.state.db.write() as session:
        session.add(
            Task(
                id=identity,
                kind=kind,
                status=status,
                phase="historical" if historical else status,
                created_at=4000000000,
                result=result or {},
                error="restored_history" if historical else None,
            )
        )
        session.flush()
        if kind.startswith("pack_"):
            session.add(
                PackFileOperation(
                    id=identity,
                    kind=kind[5:],
                    request_key=identity,
                    request_hash="hash",
                    historical=historical,
                )
            )
        elif kind in ("trash", "restore", "permanent", "undo"):
            session.add(
                FileOperation(
                    id=identity,
                    kind=kind,
                    request_key=identity,
                    request_hash="hash",
                    historical=historical,
                )
            )


def test_task_metadata_page_filters_ties_and_large_result_projection(library):
    client, _ = library
    huge = [{"private_manifest": "do-not-return" * 40} for _ in range(80000)]
    for index in range(27):
        seed(
            client,
            f"paged-{index:03}",
            "pack_restore",
            "running",
            result={"total": 80000, "processed": 3, "items": huge} if index == 26 else {},
        )
    loaded = []

    def observe(_session, instance):
        if isinstance(instance, Task):
            loaded.append(instance.id)

    event.listen(Session, "loaded_as_persistent", observe)
    try:
        first = client.get("/api/v1/maintenance-tasks", params={"family": "pack"}).json()
        tail = client.get(
            "/api/v1/maintenance-tasks", params={"family": "pack", "offset": 24}
        ).json()
    finally:
        event.remove(Session, "loaded_as_persistent", observe)
    assert first["total"] == tail["total"] == 27
    assert len(first["items"]) == 24 and len(tail["items"]) == 3
    assert first["items"][0]["id"] == "paged-026"
    assert first["items"][0]["total"] == 80000
    assert len(json.dumps(first)) < 16000 and "do-not-return" not in json.dumps(first)
    assert len({r["id"] for r in first["items"] + tail["items"]}) == 27
    assert loaded == []


def test_distinct_partial_attention_historical_and_other_task_states(library):
    client, _ = library
    seed(
        client,
        "partial",
        "pack_permanent",
        result={
            "total": 1,
            "processed": 1,
            "succeeded": 0,
            "failed": 1,
            "partial": True,
            "pages_total": 3,
            "pages_deleted": 2,
            "pages_pending_reconciliation": 0,
        },
        status="failed",
    )
    seed(
        client,
        "uncertain",
        "pack_permanent",
        status="failed",
        result={
            "partial": False,
            "needs_attention": True,
            "pages_deleted": 0,
            "pages_total": 3,
            "pages_pending_reconciliation": 1,
        },
    )
    seed(client, "old", "permanent", status="interrupted", historical=True)
    seed(client, "backup", "backup_restore", status="running")
    seed(
        client,
        "scan",
        "scan",
        result={
            "progress": {"discovered": 90, "processed": 90},
            "packs": {"progress": {"packs_discovered": 27, "packs_processed": 27}},
        },
    )
    seed(
        client,
        "future",
        "future_operation",
        status="new_status",
        result={"roots": ["/media/not-json", 9, None]},
    )
    seed(client, "broken", "pack_restore", status="completed")
    seed(
        client,
        "boolean-files",
        "pack_restore",
        status="completed",
        result={
            "total": True,
            "processed": True,
            "succeeded": True,
            "failed": False,
        },
    )
    values = {row["id"]: row for row in client.get("/api/v1/maintenance-tasks").json()["items"]}
    assert values["partial"]["state"] == "partial"
    assert values["uncertain"]["state"] == "attention"
    assert values["uncertain"]["pages_deleted"] == 0
    assert values["old"]["state"] == "historical" and values["old"]["historical"]
    assert values["backup"]["family"] == "backup"
    assert values["scan"]["processed"] == 90 and values["scan"]["pack_total"] == 27
    assert values["future"]["state"] == "attention"
    attention = client.get("/api/v1/maintenance-tasks", params={"state": "attention"}).json()
    assert {row["id"] for row in attention["items"]} == {
        "partial",
        "uncertain",
        "future",
        "broken",
        "boolean-files",
    }
    assert (
        client.get("/api/v1/maintenance-tasks", params={"state": "historical"}).json()["total"] == 1
    )
    assert client.get("/api/v1/maintenance-tasks", params={"family": "video"}).json()["total"] == 1


def test_real_pack_operation_members_and_permanent_summary_remain_read_only(library):
    client, media = library
    _, _, rows = fixture(client, media)
    task = execute(client, plan(client, [rows[0]["id"]]))
    identity = task["id"]
    summary = client.get(f"/api/v1/maintenance-tasks/{identity}").json()
    assert summary["state"] == "completed" and summary["pages_deleted"] == 2
    page = client.get(f"/api/v1/maintenance-tasks/{identity}/items", params={"limit": 1}).json()
    assert page["operation_id"] == identity and page["total"] == 1
    assert page["items"][0]["name"] and page["items"][0]["outcome"] == "succeeded"
    assert (
        client.get(
            f"/api/v1/maintenance-tasks/{identity}/items", params={"unfinished": True}
        ).json()["total"]
        == 0
    )
    after = wait(client, identity)
    assert after["id"] == task["id"] and after["result"] == task["result"]


def test_task_queries_do_not_create_or_replay_work_and_require_auth(library):
    client, _ = library
    seed(client, "safe", "restore", historical=True, status="interrupted")
    with client.app.state.db.read() as session:
        before = session.scalar(select(func.count()).select_from(Task))
    for path in [
        "/api/v1/maintenance-tasks",
        "/api/v1/maintenance-tasks/safe",
        "/api/v1/maintenance-tasks/safe/items",
    ]:
        assert client.get(path).status_code == 200
        assert client.get(path, headers={"Authorization": ""}).status_code == 401
    assert client.get("/api/v1/maintenance-tasks/unknown").status_code == 404
    assert client.get("/api/v1/maintenance-tasks/safe").json()["state"] == "historical"
    for params in [{"limit": 101}, {"offset": -1}, {"family": "invalid"}, {"state": "invalid"}]:
        assert client.get("/api/v1/maintenance-tasks", params=params).status_code == 422
    with client.app.state.db.read() as session:
        assert session.scalar(select(func.count()).select_from(Task)) == before
        assert session.get(Task, "safe").status == "interrupted"


def test_completed_scan_with_unavailable_root_is_not_reported_as_full_success(library):
    client, _ = library
    seed(
        client,
        "offline-scan",
        "scan",
        result={
            "roots": [{"status": "completed"}, {"status": "unavailable"}],
            "progress": {"discovered": 3, "processed": 3},
        },
    )
    summary = client.get("/api/v1/maintenance-tasks/offline-scan").json()
    assert summary["state"] == "partial" and summary["root_issues"] == 1


def test_failed_logical_pack_items_are_paged_independently(library):
    client, media = library
    _, _, rows = fixture(client, media)
    restored = command(
        client, "pack-trash/restore", {"request_id": "first", "trash_ids": [rows[0]["id"]]}
    )
    wait(client, restored["id"])
    repeated = command(
        client, "pack-trash/restore", {"request_id": "second", "trash_ids": [rows[0]["id"]]}
    )
    wait(client, repeated["id"])
    page = client.get(
        f"/api/v1/maintenance-tasks/{repeated['id']}/items", params={"unfinished": True}
    ).json()
    assert page["total"] == 1 and page["items"][0]["outcome"] == "failed"
    assert client.get(f"/api/v1/maintenance-tasks/{repeated['id']}").json()["state"] == "failed"


def test_real_video_operation_final_result_and_summary_keep_completed_counts(library, samples):
    from .conftest import put, scan
    from .test_file_operations import operation, trash

    client, media = library
    put(samples / "h264.mov", media / "kept.mov")
    scan(client)
    video = client.get("/api/v1/videos").json()["items"][0]
    deleted, _ = trash(client, [video["id"]])
    row = client.get("/api/v1/trash").json()["items"][0]
    restored, _ = operation(client, "/api/v1/trash/restore", {"trash_ids": [row["id"]]})
    for task in [deleted, restored]:
        assert task["result"]["total"] == task["result"]["processed"] == 1
        summary = client.get(f"/api/v1/maintenance-tasks/{task['id']}").json()
        assert summary["state"] == "completed"
        assert summary["total"] == summary["processed"] == summary["succeeded"] == 1
        assert summary["failed"] == 0
    attention = client.get(
        "/api/v1/maintenance-tasks", params={"family": "video", "state": "attention"}
    ).json()
    assert attention["total"] == 0
    partial, _ = trash(client, [video["id"], "missing-video"])
    failed, _ = trash(client, ["missing-only"])
    for task, state, total in [(partial, "partial", 2), (failed, "failed", 1)]:
        assert task["result"]["total"] == task["result"]["processed"] == total
        summary = client.get(f"/api/v1/maintenance-tasks/{task['id']}").json()
        assert summary["state"] == state
    attention = client.get(
        "/api/v1/maintenance-tasks", params={"family": "video", "state": "attention"}
    ).json()
    assert {r["id"] for r in attention["items"]} == {partial["id"], failed["id"]}
    assert (media / "kept.mov").exists()


def test_legacy_video_final_result_uses_durable_members_without_rewriting_receipt(library):
    client, _ = library
    identity = "old-completed-video"
    result = {
        "operation_id": identity,
        "items": [{"requested_id": "old-video", "outcome": "succeeded"}],
        "succeeded": 1,
        "failed": 0,
        "partial": False,
        "playback_restored": False,
    }
    seed(client, identity, "trash", result=result)
    with client.app.state.db.write() as session:
        session.get(Task, identity).phase = "completed"
        session.add(
            FileStep(
                operation_id=identity,
                requested_id="old-video",
                original_path="/media/old-video.mp4",
                phase="committed",
                outcome="succeeded",
            )
        )
    for path in [
        "/api/v1/maintenance-tasks",
        f"/api/v1/maintenance-tasks/{identity}",
    ]:
        raw = client.get(path).json()
        summary = raw if "state" in raw else next(r for r in raw["items"] if r["id"] == identity)
        assert summary["state"] == "completed"
        assert summary["total"] == summary["processed"] == summary["succeeded"] == 1
    assert (
        client.get(
            "/api/v1/maintenance-tasks", params={"family": "video", "state": "completed"}
        ).json()["total"]
        == 1
    )
    assert (
        client.get(
            "/api/v1/maintenance-tasks", params={"family": "video", "state": "attention"}
        ).json()["total"]
        == 0
    )
    with client.app.state.db.read() as session:
        assert session.get(Task, identity).result == result
        assert session.get(Task, identity).status == "completed"


@pytest.mark.parametrize(
    "outcomes,changes,status,expected",
    [
        (
            ["succeeded", "failed"],
            {"succeeded": 1, "failed": 1, "partial": True},
            "completed",
            "partial",
        ),
        (["failed"], {"succeeded": 0, "failed": 1}, "failed", "failed"),
        (["conflict"], {"succeeded": 0, "failed": 1}, "failed", "failed"),
        (["pending"], {}, "completed", "attention"),
        (["unknown"], {"succeeded": 0, "failed": 1}, "failed", "attention"),
        ([], {"succeeded": 0}, "completed", "attention"),
        (["succeeded"], {"succeeded": True}, "completed", "attention"),
        (["succeeded"], {"succeeded": 0, "failed": 1}, "completed", "attention"),
        (["succeeded"], {"operation_id": "different"}, "completed", "attention"),
        (["succeeded"], {"total": True, "processed": True}, "completed", "attention"),
        (["succeeded"], {"total": 1}, "completed", "attention"),
        (["succeeded"], {"needs_attention": True}, "completed", "attention"),
        (["pending"], {}, "running", "processing"),
    ],
)
def test_legacy_video_summary_only_accepts_coherent_terminal_evidence(
    library, outcomes, changes, status, expected
):
    client, _ = library
    identity = "legacy-guard"
    result = {
        "operation_id": identity,
        "items": [{"outcome": value} for value in outcomes],
        "succeeded": 1,
        "failed": 0,
        "partial": False,
        **changes,
    }
    seed(client, identity, "trash", status, result=result)
    with client.app.state.db.write() as session:
        session.get(Task, identity).phase = (
            "completed" if status != "running" else "processing_files"
        )
        for index, outcome in enumerate(outcomes):
            session.add(
                FileStep(
                    operation_id=identity,
                    requested_id=f"old-{index}",
                    phase="committed" if outcome == "succeeded" else "prepared",
                    outcome=outcome,
                )
            )
    summary = client.get(f"/api/v1/maintenance-tasks/{identity}").json()
    assert summary["state"] == expected
    if expected in {"failed", "partial"}:
        assert summary["total"] == summary["processed"] == len(outcomes)
    with client.app.state.db.read() as session:
        assert session.get(Task, identity).result == result
