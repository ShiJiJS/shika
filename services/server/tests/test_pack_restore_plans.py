"""Whole-selection restore over real HTTP/SQLite and disposable image trees."""

import threading
import time
from concurrent.futures import ThreadPoolExecutor

import pytest
from sqlalchemy import func, select

from shika.errors import LibraryError
from shika.models import (
    ImagePack,
    PackFileOperation,
    PackRestoreBatch,
    PackRestoreMember,
    PackRestorePlan,
    PackTrashItem,
    Task,
)
from shika.pack_scanner import reserved_packs

from .conftest import connect
from .test_media_types import pack_root
from .test_pack_operations import restore, tree
from .test_pack_purge_plans import fixture


def submit(client, ids, key="whole", status=202):
    response = client.post("/api/v1/pack-restore-plans", json={"trash_ids": ids, "request_id": key})
    assert response.status_code == status, response.text
    return response.json()


def wait(client, identity):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        response = client.get(f"/api/v1/pack-restore-plans/{identity}")
        assert response.status_code == 200, response.text
        value = response.json()
        if value["status"] not in ("queued", "running"):
            return value
        time.sleep(0.01)
    raise AssertionError(value)


def totals(client):
    with client.app.state.db.read() as session:
        return tuple(
            session.scalar(select(func.count()).select_from(model))
            for model in (PackRestorePlan, PackRestoreMember, PackRestoreBatch)
        )


def gate(client):
    entered, release = threading.Event(), threading.Event()

    def hook(phase, _identity):
        if phase == "restore_child_accepted" and not entered.is_set():
            entered.set()
            assert release.wait(30), "restore test gate timed out"

    client.app.state.pack_restore_plans.fault_hook = hook
    return entered, release


def test_complete_selection_outlives_request_and_paginates_original_members(library):
    client, media = library
    _, catalog, rows = fixture(client, media, 9)
    before = tree(media)
    client.app.state.pack_restore_plans.batch_size = 2
    ids = [r["id"] for r in rows]
    value = submit(client, ids)
    result = wait(client, value["id"])
    assert result["result"] == {
        "operation_id": value["id"],
        "total": 9,
        "processed": 9,
        "succeeded": 9,
        "failed": 0,
        "stopped": 0,
        "remaining": 0,
        "partial": False,
        "batches": 5,
    }
    assert totals(client) == (1, 9, 5)
    assert tree(media) == before
    with client.app.state.db.read() as session:
        assert {p.generation for p in session.scalars(select(ImagePack))} == {3}
    # Reordered identical acceptance and repeated GETs never create more work.
    assert submit(client, list(reversed(ids)))["id"] == value["id"]
    assert client.get("/api/v1/pack-restore-requests/whole").json() == result
    endpoint = f"/api/v1/maintenance-tasks/{value['id']}"
    summary = client.get(endpoint).json()
    assert summary["state"] == "completed" and summary["total"] == 9
    first = client.get(endpoint + "/items", params={"limit": 4, "unfinished": False}).json()
    tail = client.get(
        endpoint + "/items", params={"offset": 4, "limit": 5, "unfinished": False}
    ).json()
    assert first["total"] == tail["total"] == 9
    assert [r["requested_id"] for r in first["items"] + tail["items"]] == sorted(ids)
    assert all(r["outcome"] == "succeeded" for r in first["items"] + tail["items"])
    assert totals(client) == (1, 9, 5)
    assert len(catalog) == 9
    listed = client.get("/api/v1/maintenance-tasks", params={"family": "pack"}).json()
    assert len([v for v in listed["items"] if v["kind"] == "pack_restore_plan"]) == 1
    assert not any(v["kind"] == "pack_restore" for v in listed["items"])
    late_stop = client.post(
        f"/api/v1/pack-restore-plans/{value['id']}/stop", json={"request_id": "too-late"}
    )
    assert late_stop.json()["phase"] == "completed" and not late_stop.json()["stop_requested"]


def test_atomic_admission_auth_unknown_receipts_and_idempotency(library):
    client, media = library
    _, _, rows = fixture(client, media, 2)
    ids = [r["id"] for r in rows]
    submit(client, ids + ["missing"], status=404)
    assert totals(client) == (0, 0, 0)
    for body in (
        {"trash_ids": [], "request_id": "bad"},
        {"trash_ids": ids, "request_id": "bad", "execute": True},
    ):
        assert client.post("/api/v1/pack-restore-plans", json=body).status_code == 422
    assert (
        client.post(
            "/api/v1/pack-restore-plans",
            headers={"Authorization": ""},
            json={"trash_ids": ids, "request_id": "bad"},
        ).status_code
        == 401
    )
    assert client.get("/api/v1/pack-restore-requests/never").status_code == 404
    value = submit(client, ids)
    wait(client, value["id"])
    submit(client, ids[:1], status=409)
    assert totals(client) == (1, 2, 1)


def test_stop_waits_for_current_child_and_releases_only_unstarted_selection(library):
    client, media = library
    _, _, rows = fixture(client, media, 9)
    before = tree(media)
    plans = client.app.state.pack_restore_plans
    plans.batch_size = 2
    entered, release = gate(client)
    ids = sorted(r["id"] for r in rows)
    try:
        value = submit(client, ids)
        assert entered.wait(10)
        with client.app.state.db.read() as session:
            assert len(set(session.scalars(reserved_packs()))) == 9
            batch = session.scalar(select(PackRestoreBatch))
            child = batch.operation_id
            with pytest.raises(LibraryError, match="图包已有待执行操作"):
                client.app.state.pack_purge_plans.source(session, ids[-1])
        assert (
            client.post(
                f"/api/v1/pack-operations/{child}/retry", json={"request_id": "forged-child"}
            ).status_code
            == 409
        )
        blocked = restore(client, [ids[-1]], "other-restore")
        assert blocked["result"]["items"][0]["error"] == "operation_busy"
        stop = client.post(
            f"/api/v1/pack-restore-plans/{value['id']}/stop", json={"request_id": "stop"}
        )
        assert stop.status_code == 202
        assert stop.json()["stop_requested"]
    finally:
        release.set()
    result = wait(client, value["id"])
    assert result["status"] == "completed" and result["phase"] == "stopped"
    assert result["result"]["succeeded"] == 2 and result["result"]["stopped"] == 7
    assert result["result"]["processed"] == 2 and result["result"]["remaining"] == 0
    assert result["result"]["batches"] == 1
    assert client.get(f"/api/v1/maintenance-tasks/{value['id']}").json()["state"] == "partial"
    with client.app.state.db.read() as session:
        assert set(session.scalars(reserved_packs())) == set()
    assert (
        wait(client, submit(client, ids[2:], "explicit-new-plan")["id"])["result"]["succeeded"] == 7
    )
    assert tree(media) == before


def test_changed_member_fails_without_replacing_identity_or_blocking_later_batches(library):
    client, media = library
    _, _, rows = fixture(client, media, 7)
    ids = sorted(r["id"] for r in rows)
    client.app.state.pack_restore_plans.batch_size = 2
    entered, release = gate(client)
    try:
        value = submit(client, ids)
        assert entered.wait(10)
        with client.app.state.db.write() as session:
            item = session.get(PackTrashItem, ids[3])
            session.get(ImagePack, item.pack_id).generation += 1
    finally:
        release.set()
    result = wait(client, value["id"])
    assert result["result"]["succeeded"] == 6 and result["result"]["failed"] == 1
    assert result["result"]["batches"] == 4
    failed = client.get(
        f"/api/v1/maintenance-tasks/{value['id']}/items", params={"unfinished": True}
    ).json()
    assert failed["total"] == 1 and failed["items"][0]["requested_id"] == ids[3]
    assert failed["items"][0]["error"] == "stale_pack_state"


def test_stop_before_first_child_keeps_all_members_unexecuted_and_repeat_is_readonly(
    library, monkeypatch
):
    client, media = library
    _, _, rows = fixture(client, media, 3)
    plans = client.app.state.pack_restore_plans
    enqueue = plans.enqueue
    monkeypatch.setattr(plans, "enqueue", lambda identity: None)
    original = submit(client, [r["id"] for r in rows])
    monkeypatch.setattr(plans, "enqueue", enqueue)
    identity = original["id"]
    endpoint = f"/api/v1/pack-restore-plans/{identity}/stop"
    assert client.post(endpoint, json={"request_id": "early-stop"}).status_code == 202
    result = wait(client, identity)
    assert result["result"]["stopped"] == 3
    assert (
        result["result"]["processed"]
        == result["result"]["succeeded"]
        == result["result"]["failed"]
        == 0
    )
    assert result["phase"] == "stopped" and result["status"] == "completed"
    assert client.get(f"/api/v1/maintenance-tasks/{identity}").json()["state"] == "partial"
    previous_future = plans.futures[identity]
    previous_future.result(timeout=10)
    assert client.post(endpoint, json={"request_id": "early-stop"}).json() == {
        **result,
        "stop_request_id": "early-stop",
    }
    assert client.get("/api/v1/pack-restore-stop-requests/early-stop").json() == {
        **result,
        "stop_request_id": "early-stop",
    }
    assert client.get("/api/v1/pack-restore-stop-requests/unknown-stop").status_code == 404
    assert (
        client.get(
            "/api/v1/pack-restore-stop-requests/early-stop", headers={"Authorization": ""}
        ).status_code
        == 401
    )
    assert plans.futures[identity] is previous_future
    assert totals(client) == (1, 3, 0)
    with client.app.state.db.read() as session:
        assert {p.generation for p in session.scalars(select(ImagePack))} == {2}


@pytest.mark.parametrize(
    "phase", ["restore_child_accepted", "restore_child_finished", "before_logical_commit"]
)
def test_reopen_recovers_same_child_before_continuing_unstarted_batches(environment, phase):
    settings, media = environment
    client, token = connect(settings)
    try:
        _, _, rows = fixture(client, media, 7)
        ids = [r["id"] for r in rows]
        before = tree(media)
        client.app.state.pack_restore_plans.batch_size = 2

        def fault(current, _identity):
            if current == phase:
                raise RuntimeError("simulated worker loss")

        client.app.state.pack_restore_plans.fault_hook = fault
        client.app.state.pack_files.fault_hook = fault
        value = submit(client, ids)
        failed = wait(client, value["id"])
        assert failed["error"] == "operation_recovery_required"
        with client.app.state.db.read() as session:
            child = session.scalar(select(PackRestoreBatch.operation_id))
    finally:
        client.__exit__(None, None, None)
    client, _ = connect(settings, token=token)
    try:
        original = client.get("/api/v1/pack-restore-requests/whole").json()
        assert original["id"] == value["id"]
        result = wait(client, original["id"])
        assert result["result"]["succeeded"] == 7 and result["result"]["batches"] == 4
        with client.app.state.db.read() as session:
            assert (
                session.scalar(
                    select(PackRestoreBatch.operation_id)
                    .order_by(PackRestoreBatch.ordinal)
                    .limit(1)
                )
                == child
            )
            assert {p.generation for p in session.scalars(select(ImagePack))} == {3}
        assert tree(media) == before
    finally:
        client.__exit__(None, None, None)


def test_production_batch_limit_accepts_more_than_1000_without_loading_page_manifests(library):
    client, media = library
    root = pack_root(client, media)
    ids = []
    with client.app.state.db.write() as session:
        task = Task(kind="pack_trash", status="completed", result={})
        session.add(task)
        session.flush()
        session.add(
            PackFileOperation(
                id=task.id,
                request_key="synthetic:1003",
                request_hash="seed",
                kind="trash",
                session_snapshot={},
            )
        )
        session.flush()
        for number in range(1003):
            pack = ImagePack(
                root_id=root["id"],
                name=str(number),
                path=f"{root['path']}/{number}",
                status="trash",
                generation=1,
            )
            session.add(pack)
            session.flush()
            item = PackTrashItem(
                pack_id=pack.id,
                operation_id=task.id,
                root_path=root["path"],
                original_path=pack.path,
                manifest={"status": "missing", "error": None, "page_count": 0},
            )
            session.add(item)
            session.flush()
            ids.append(item.id)
    assert (
        client.post(
            "/api/v1/pack-trash/restore", json={"trash_ids": ids, "request_id": "too-large"}
        ).status_code
        == 422
    )
    result = wait(client, submit(client, ids)["id"])
    assert result["result"]["succeeded"] == 1003 and result["result"]["batches"] == 2
    assert totals(client) == (1, 1003, 2)
    with client.app.state.db.read() as session:
        assert {p.status for p in session.scalars(select(ImagePack))} == {"missing"}


def test_simultaneous_same_request_has_one_plan_and_unique_children(library):
    client, media = library
    _, _, rows = fixture(client, media, 5)
    plans = client.app.state.pack_restore_plans
    plans.batch_size = 2
    ids = [r["id"] for r in rows]
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: plans.submit(ids, "same-concurrent"), range(2)))
    assert results[0] == results[1]
    assert wait(client, results[0])["result"]["succeeded"] == 5
    assert totals(client) == (1, 5, 3)
