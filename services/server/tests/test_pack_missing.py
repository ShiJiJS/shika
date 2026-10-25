import json
import shutil
import threading
import time
from pathlib import Path

import pytest
from sqlalchemy import func, select

from video_viewer.models import (
    ImagePack,
    PackMissingCleanup,
    PackMissingMember,
    PackPreferences,
    PackProgress,
    PackSessionEntry,
    PackTagLink,
    RecentEntry,
    Root,
    Task,
)

from .conftest import connect
from .test_media_types import pack_root, pack_tag
from .test_pack_operations import tree
from .test_packs import image, packs, sync
from .test_reading import create, opened


def missing(client, media):
    root = pack_root(client, media)
    folder = Path(root["path"]) / "gone"
    image(folder / "1.png")
    image(Path(root["path"]) / "keep" / "1.png", color="blue")
    sync(client)
    pack = next(p for p in packs(client)["items"] if p["name"] == "gone")
    label = pack_tag(client, "保留历史")
    assert (
        client.patch(
            "/api/v1/pack-tag-links",
            json={
                "request_id": "tag-before",
                "pack_ids": [pack["id"]],
                "tag_ids": [label["id"]],
            },
        ).status_code
        == 200
    )
    reading = create(client, anchor_pack_id=pack["id"])
    opened(client, reading)
    shutil.rmtree(folder)
    sync(client)
    assert client.get("/api/v1/packs?status=missing").json()["total"] == 1
    return root, pack, folder


def submit(client, key="cleanup"):
    response = client.post(
        "/api/v1/packs/forget-missing", json={"request_id": key, "confirmed": True}
    )
    assert response.status_code == 202, response.text
    return response.json()["id"]


def wait(client, identity):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        task = client.get("/api/v1/tasks/" + identity).json()
        if task["status"] not in ("queued", "running"):
            return task
        time.sleep(0.01)
    raise AssertionError(task)


def hold(client):
    started, release = threading.Event(), threading.Event()

    def hook(phase, _identity):
        if phase == "before_cleanup":
            started.set()
            assert release.wait(20)

    client.app.state.pack_missing.fault_hook = hook
    return started, release


def test_cleanup_removes_only_live_metadata_retains_history_and_never_reuses_identity(library):
    client, media = library
    root, pack, folder = missing(client, media)
    before = tree(media)
    identity = submit(client)
    task = wait(client, identity)
    assert task["status"] == "completed" and task["result"]["succeeded"] == 1, task
    assert task["result"]["skipped"] == 0
    assert submit(client) == identity
    receipt = client.get("/api/v1/pack-missing-requests/cleanup")
    assert receipt.json()["request_id"] == "cleanup"
    assert receipt.status_code == 200 and receipt.json()["id"] == identity
    assert client.get("/api/v1/packs?status=missing").json()["total"] == 0
    assert tree(media) == before
    with client.app.state.db.read() as db:
        assert db.get(ImagePack, pack["id"]).status == "deleted"
        for model in (PackTagLink, PackPreferences, PackProgress, RecentEntry):
            assert (
                db.scalar(
                    select(func.count()).select_from(model).where(model.pack_id == pack["id"])
                )
                == 0
            )
        assert db.scalar(
            select(PackSessionEntry.pack_id).where(PackSessionEntry.pack_id == pack["id"])
        )
    image(folder / "1.png")
    sync(client)
    fresh = next(p for p in packs(client)["items"] if p["name"] == "gone")
    assert fresh["id"] != pack["id"] and fresh["tag_ids"] == [] and fresh["progress"] is None


@pytest.mark.parametrize("condition", ["disabled", "offline", "returned", "symlink", "unscanned"])
def test_unreliable_or_returned_members_are_preserved_with_explicit_reason(library, condition):
    client, media = library
    root, pack, folder = missing(client, media)
    started, release = hold(client)
    identity = submit(client)
    assert started.wait(10)
    away = Path(root["path"]).with_name("offline")
    try:
        if condition == "disabled":
            assert (
                client.put(
                    "/api/v1/roots/" + root["id"],
                    json={
                        "name": root["name"],
                        "path": root["path"],
                        "kind": "pack",
                        "enabled": False,
                    },
                ).status_code
                == 200
            )
        elif condition == "offline":
            Path(root["path"]).rename(away)
        elif condition == "returned":
            image(folder / "1.png")
        elif condition == "symlink":
            folder.symlink_to(Path(root["path"]) / "keep", target_is_directory=True)
        else:
            with client.app.state.db.write() as db:
                db.get(Root, root["id"]).last_scan = None
        before = tree(media) if condition != "symlink" else None
        release.set()
        task = wait(client, identity)
        assert task["result"]["succeeded"] == 0 and task["result"]["skipped"] == 1, task
        if before is not None:
            assert tree(media) == before
        items = client.get(f"/api/v1/maintenance-tasks/{identity}/items").json()["items"]
        assert items[0]["outcome"] == "skipped" and items[0]["error"]
        with client.app.state.db.read() as db:
            assert db.get(ImagePack, pack["id"]).status == "missing"
            assert db.get(PackProgress, pack["id"]) and db.get(PackPreferences, pack["id"])
            assert db.scalar(select(PackTagLink.pack_id).where(PackTagLink.pack_id == pack["id"]))
    finally:
        release.set()
        if away.exists():
            away.rename(root["path"])


def test_fixed_scope_large_members_paging_and_new_missing_not_in_original_task(library):
    client, media = library
    root = pack_root(client, media)
    with client.app.state.db.write() as db:
        r = db.get(Root, root["id"])
        r.available, r.last_scan = True, time.time()
        for i in range(1003):
            db.add(
                ImagePack(
                    root_id=r.id, path=r.path + f"/gone-{i}", name=f"gone-{i}", status="missing"
                )
            )
    started, release = hold(client)
    identity = submit(client)
    assert started.wait(10)
    with client.app.state.db.write() as db:
        db.add(
            ImagePack(
                root_id=root["id"], path=root["path"] + "/later", name="later", status="missing"
            )
        )
    release.set()
    task = wait(client, identity)
    assert task["result"]["total"] == task["result"]["succeeded"] == 1003
    assert len(json.dumps(task["result"])) < 512
    assert client.get("/api/v1/packs?status=missing").json()["total"] == 1
    page = client.get(f"/api/v1/maintenance-tasks/{identity}/items?offset=24&limit=24").json()
    assert page["total"] == 1003 and len(page["items"]) == 24
    assert all(row["outcome"] == "succeeded" for row in page["items"])
    assert submit(client) == identity  # Original receipt cannot consume the later member.
    assert client.get("/api/v1/packs?status=missing").json()["total"] == 1


def test_restart_continues_original_members_without_double_count(environment):
    settings, media = environment
    client, token = connect(settings)
    root, pack, _ = missing(client, media)
    with client.app.state.db.write() as db:
        for i in range(3):
            db.add(
                ImagePack(
                    root_id=root["id"],
                    path=root["path"] + f"/gone-{i}",
                    name=str(i),
                    status="missing",
                )
            )

    def stop(phase, _identity):
        if phase == "after_member_commit":
            client.app.state.pack_missing.stop.set()

    client.app.state.pack_missing.fault_hook = stop
    identity = submit(client)
    client.app.state.pack_missing.futures[identity].result(timeout=10)
    assert client.get("/api/v1/tasks/" + identity).json()["result"]["processed"] == 1
    client.__exit__(None, None, None)
    client, _ = connect(settings, token=token)
    try:
        task = wait(client, identity)
        assert (
            task["result"]["processed"]
            == task["result"]["succeeded"]
            == task["result"]["total"]
            == 4
        )
        assert client.get("/api/v1/pack-missing-requests/cleanup").json()["id"] == identity
    finally:
        client.__exit__(None, None, None)


def test_historical_scope_is_never_started(library):
    client, media = library
    _, pack, _ = missing(client, media)
    started, release = hold(client)
    identity = submit(client)
    assert started.wait(10)
    with client.app.state.db.write() as db:
        db.get(PackMissingCleanup, identity).historical = True
    release.set()
    client.app.state.pack_missing.futures[identity].result(timeout=10)
    summary = client.get("/api/v1/maintenance-tasks/" + identity).json()
    assert summary["historical"] and summary["state"] == "historical"
    with client.app.state.db.read() as db:
        assert db.get(ImagePack, pack["id"]).status == "missing"
        assert db.get(PackMissingMember, (identity, pack["id"])).outcome == "pending"


def test_scan_gate_confirmation_and_unknown_receipt(library):
    client, _ = library
    assert (
        client.post("/api/v1/packs/forget-missing", json={"request_id": "no-confirm"}).status_code
        == 422
    )
    assert client.get("/api/v1/pack-missing-requests/unknown").status_code == 404
    with client.app.state.db.write() as db:
        db.add(Task(kind="scan", status="running", phase="scan"))
    response = client.post(
        "/api/v1/packs/forget-missing", json={"request_id": "busy", "confirmed": True}
    )
    assert response.status_code == 409
    assert client.get("/api/v1/pack-missing-requests/busy").status_code == 404
