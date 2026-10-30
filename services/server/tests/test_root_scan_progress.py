"""Independent root facts and serial, explicitly scoped scans on disposable media."""

import os
import shutil
import threading
import time
from pathlib import Path

from sqlalchemy import select

from video_viewer.authority import Authority
from video_viewer.models import ImagePack, PackPage, Root, Task, Video

from .conftest import connect, put, scan
from .test_backups import wait_task
from .test_management_archives import export, inspect, restore
from .test_packs import image, sync


def roots(client, media):
    found = []
    for name in ["A", "B"]:
        path = media / name
        path.mkdir()
        response = client.post(
            "/api/v1/roots", json={"name": name, "path": str(path), "kind": "pack"}
        )
        assert response.status_code == 201, response.text
        found.append(response.json())
    return found


def start(client, root_id):
    response = client.post("/api/v1/scans", json={"root_id": root_id})
    assert response.status_code == 202, response.text
    return response.json()


def state(client):
    value = client.get("/api/v1/library-state").json()
    return value, {r["id"]: r for r in value["roots"]}


def completed(client, task):
    result = wait_task(client, task["id"])
    assert result["status"] == "completed", result
    return result


def test_live_two_roots_keep_distinct_pack_and_image_units(library, samples, monkeypatch):
    from video_viewer.pack_scanner import inspect_image as inspect

    client, media = library
    a, b = roots(client, media)
    put(samples / "h264.mov", media / "video.mov")
    for root in [a, b]:
        for number in [1, 2]:
            image(Path(root["path"]) / "one" / f"{number}.png")
    entered, release = threading.Event(), threading.Event()

    def held(fd, *args):
        if os.readlink(f"/proc/self/fd/{fd}") == b["path"] + "/one/2.png":
            entered.set()
            assert release.wait(10)
        return inspect(fd, *args)

    monkeypatch.setattr("video_viewer.pack_scanner.inspect_image", held)
    time.sleep(0.05)
    task = client.post("/api/v1/scans").json()
    try:
        assert entered.wait(10)
        all_state, by_id = state(client)
        av, bv = by_id[a["id"]]["scan"], by_id[b["id"]]["scan"]
        assert av["status"] == "completed"  # cold import needs no old cross-root identity match
        assert by_id[a["id"]]["last_scan"] is not None
        assert av["discovered"] == av["processed"] == 1
        assert av["progress"]["discovered"] == av["progress"]["processed"] == 2
        assert bv["discovered"] == 1 and bv["processed"] == 0
        assert bv["progress"]["discovered"] == 2 and bv["progress"]["processed"] == 1
        assert bv["progress"]["packs_discovered"] == 1
        assert bv["progress"]["packs_processed"] == 0
        assert not bv["progress"]["discovery_complete"]
        assert bv["progress"]["packs_discovery_complete"]
        assert av["task_id"] == bv["task_id"] == task["id"]
        assert all_state["media"]["pack"]["scanning"]
        assert not all_state["media"]["video"]["scanning"]
        assert by_id["main"]["scan"]["progress"]["processed"] == 1
    finally:
        release.set()
    result = completed(client, task)
    assert result["result"]["packs"]["progress"]["processed"] == 4
    for root in [a, b]:
        item = state(client)[1][root["id"]]["scan"]
        assert item["status"] == "completed" and item["finished_at"] >= item["updated_at"]
        assert item["progress"]["discovery_complete"]
        assert item["progress"]["processed"] == 2
        assert item["counts"]["imported"] == 1


def test_scoped_scan_preserves_other_root_rows_and_last_facts(library):
    client, media = library
    a, b = roots(client, media)
    for root in [a, b]:
        image(Path(root["path"]) / "one/1.png")
    sync(client)
    before = state(client)[1]
    db = client.app.state.db
    with db.read() as session:
        pack = session.scalar(select(ImagePack).where(ImagePack.root_id == b["id"]))
        bid = pack.id
        old_pack = {c.name: getattr(pack, c.name) for c in ImagePack.__table__.columns}
        old_pages = [
            {c.name: getattr(p, c.name) for c in PackPage.__table__.columns}
            for p in session.scalars(select(PackPage).where(PackPage.pack_id == bid))
        ]
    # Removing a disposable B directory must not let an A-only scan classify B missing.
    shutil.rmtree(Path(b["path"]) / "one")
    image(Path(a["path"]) / "two/1.png", color="blue")
    time.sleep(0.05)
    task = completed(client, start(client, a["id"]))
    assert task["result"]["scope"] == {"all": False, "root_ids": [a["id"]]}
    assert [r["id"] for r in task["result"]["roots"]] == [a["id"]]
    after = state(client)[1]
    assert after[b["id"]] == before[b["id"]]
    assert after["main"] == before["main"]
    assert after[a["id"]]["scan"]["task_id"] == task["id"]
    with db.read() as session:
        pack = session.get(ImagePack, bid)
        assert {c.name: getattr(pack, c.name) for c in ImagePack.__table__.columns} == old_pack
        assert [
            {c.name: getattr(p, c.name) for c in PackPage.__table__.columns}
            for p in session.scalars(select(PackPage).where(PackPage.pack_id == bid))
        ] == old_pages


def test_scans_queue_once_and_execute_serially(library, monkeypatch):
    from video_viewer.pack_scanner import inspect_image as inspect

    client, media = library
    a, b = roots(client, media)
    for root in [a, b]:
        image(Path(root["path"]) / "one/1.png")
    entered, release = threading.Event(), threading.Event()
    live = peak = 0
    lock = threading.Lock()

    def held(fd, *args):
        nonlocal live, peak
        with lock:
            live += 1
            peak = max(peak, live)
        try:
            if os.readlink(f"/proc/self/fd/{fd}").startswith(a["path"]):
                entered.set()
                assert release.wait(10)
            return inspect(fd, *args)
        finally:
            with lock:
                live -= 1

    monkeypatch.setattr("video_viewer.pack_scanner.inspect_image", held)
    time.sleep(0.05)
    first = start(client, a["id"])
    try:
        assert entered.wait(10)
        second = start(client, b["id"])
        assert second["status"] == "queued"
        assert start(client, b["id"])["id"] == second["id"]
        assert start(client, a["id"])["id"] == first["id"]
        all_task = client.post("/api/v1/scans").json()
        assert len({first["id"], second["id"], all_task["id"]}) == 3
        assert client.post("/api/v1/scans").json()["id"] == all_task["id"]
        value, by_id = state(client)
        assert [x["task_id"] for x in value["scan_queue"]] == [second["id"], all_task["id"]]
        assert by_id[b["id"]]["queued_task_ids"] == [second["id"], all_task["id"]]
        assert value["task_id"] == first["id"]
        response = client.put(
            "/api/v1/roots/" + a["id"], json={"name": "changed", "path": a["path"]}
        )
        assert response.status_code == 409 and response.json()["error"]["code"] == "scan_busy"
    finally:
        release.set()
    for task in [first, second, all_task]:
        completed(client, task)
    assert peak == 1
    assert not state(client)[0]["scan_queue"]
    assert {"root_scan_progress", "scoped_scans"} <= set(
        client.get("/api/v1/info").json()["capabilities"]
    )


def test_bad_pages_offline_and_disabled_roots_remain_distinct(library):
    client, media = library
    a, b = roots(client, media)
    image(Path(a["path"]) / "one/good.png")
    (Path(a["path"]) / "one/bad.png").write_bytes(b"not an image")
    image(Path(b["path"]) / "one/1.png")
    sync(client)
    by_id = state(client)[1]
    assert by_id[a["id"]]["scan"]["status"] == "partial"
    assert by_id[a["id"]]["scan"]["page_errors"] == 1
    assert by_id[a["id"]]["scan"]["progress"]["processed"] == 2
    assert by_id[b["id"]]["scan"]["status"] == "completed"
    # A cached corrupt page is still reported on the next inspection.
    completed(client, start(client, a["id"]))
    assert state(client)[1][a["id"]]["scan"]["page_errors"] == 1
    Path(b["path"]).rename(media / "B-offline")
    completed(client, start(client, b["id"]))
    assert state(client)[1][b["id"]]["scan"]["status"] == "unavailable"
    response = client.put(
        "/api/v1/roots/" + a["id"], json={"name": "A", "path": a["path"], "enabled": False}
    )
    assert response.status_code == 200
    scan(client)
    assert state(client)[1][a["id"]]["scan"]["status"] == "disabled"
    last_task = client.get("/api/v1/tasks").json()["items"][0]
    assert a["id"] not in {r["id"] for r in last_task["result"]["roots"]}
    assert (
        next(r for r in last_task["result"]["root_scans"] if r["id"] == a["id"])["status"]
        == "disabled"
    )
    response = client.post("/api/v1/scans", json={"root_id": a["id"]})
    assert response.status_code == 409 and response.json()["error"]["code"] == "root_disabled"


def test_changed_page_is_deferred_without_fake_completion(library, monkeypatch):
    from video_viewer.pack_scanner import inspect_image as inspect

    client, media = library
    a, _ = roots(client, media)
    file = Path(a["path"]) / "one/1.png"
    image(file)

    def changing(fd, *args):
        value = inspect(fd, *args)
        image(file, color="blue", size=(41, 61))
        return value

    monkeypatch.setattr("video_viewer.pack_scanner.inspect_image", changing)
    time.sleep(0.05)
    completed(client, start(client, a["id"]))
    value = state(client)[1][a["id"]]["scan"]
    assert value["status"] == "deferred"
    assert value["progress"]["packs_processed"] == value["progress"]["packs_discovered"] == 1
    assert value["progress"]["processed"] == 0 and not value["progress"]["discovery_complete"]
    assert value["counts"]["deferred"] == 1


def test_scoped_video_overlap_rejects_expansion_and_counts_owner_once(library, samples):
    client, media = library
    nested = media / "nested"
    nested.mkdir()
    response = client.post("/api/v1/roots", json={"name": "nested", "path": str(nested)})
    child = response.json()
    put(samples / "h264.mov", nested / "one.mov")
    scan(client)
    by_id = state(client)[1]
    assert by_id["main"]["scan"]["progress"]["processed"] == 1
    assert by_id[child["id"]]["scan"]["status"] == "covered"
    assert by_id[child["id"]]["scan"]["owner_root_id"] == "main"
    assert state(client)[0]["media"]["video"]["ready"]
    last_task = client.get("/api/v1/tasks").json()["items"][0]
    assert child["id"] not in {r["id"] for r in last_task["result"]["roots"]}
    assert (
        next(r for r in last_task["result"]["root_scans"] if r["id"] == child["id"])["status"]
        == "covered"
    )
    response = client.post("/api/v1/scans", json={"root_id": child["id"]})
    assert response.status_code == 409 and response.json()["error"]["code"] == "scan_root_covered"
    assert client.post("/api/v1/scans", json={"root_id": "missing"}).status_code == 404
    for body in [{"root_id": ""}, {"root_ids": ["main"]}, {"root_id": 1}, {"scope": "all"}]:
        assert client.post("/api/v1/scans", json=body).status_code == 422


def test_scoped_pack_respects_nested_root_boundary(library):
    client, media = library
    a, _ = roots(client, media)
    nested = Path(a["path"]) / "one/nested"
    nested.mkdir(parents=True)
    child = client.post(
        "/api/v1/roots", json={"name": "nested", "path": str(nested), "kind": "pack"}
    ).json()
    image(Path(a["path"]) / "one/own.png")
    image(nested / "child/1.png")
    sync(client)
    before = state(client)[1][child["id"]]
    value = completed(client, start(client, a["id"]))
    assert value["result"]["packs"]["progress"]["processed"] == 1
    assert state(client)[1][child["id"]] == before
    assert client.get("/api/v1/packs", params={"search": "child"}).json()["total"] == 1


def test_partial_interruption_persists_and_restart_does_not_replay(environment, monkeypatch):
    from video_viewer.pack_scanner import inspect_image as inspect
    from video_viewer.root_scan_progress import entry

    settings, media = environment
    client, token = connect(settings)
    a, b = roots(client, media)
    for number in [1, 2]:
        image(Path(a["path"]) / "one" / f"{number}.png")
    calls = 0

    def interrupted(fd, *args):
        nonlocal calls
        calls += 1
        if calls == 2:
            raise InterruptedError("test service stop")
        return inspect(fd, *args)

    monkeypatch.setattr("video_viewer.pack_scanner.inspect_image", interrupted)
    time.sleep(0.05)
    task = start(client, a["id"])
    result = wait_task(client, task["id"])
    assert result["status"] == "interrupted"
    before = state(client)[1][a["id"]]["scan"]
    assert before["status"] == "interrupted" and before["progress"]["processed"] == 1
    client.__exit__(None, None, None)
    client, _ = connect(settings, token=token)
    try:
        assert state(client)[1][a["id"]]["scan"] == before
        assert calls == 2 and not state(client)[0]["scanning"]
        # Seed the durable states a hard exit could leave, without simulating
        # a process crash or inventing execution of a queued B operation.
        with client.app.state.db.write() as session:
            root = session.get(Root, a["id"])
            pending = Task(kind="scan", status="running", phase="pack_inspecting", result={})
            session.add(pending)
            session.flush()
            item = entry(root, pending.id, list(session.scalars(select(Root))))
            item["status"] = item["phase"] = "processing_media"
            item["progress"]["processed"] = item["progress"]["discovered"] = 1
            pending.result = {"scope": {"all": False, "root_ids": [root.id]}, "roots": [item]}
            running_id = pending.id
        # Scanner.close only interrupts queued futures; this seeded running row
        # is intentionally left for next startup recovery.
    finally:
        client.__exit__(None, None, None)
    from video_viewer.db import Database

    db = Database(settings.data_dir)
    with db.write() as session:
        root = session.get(Root, b["id"])
        pending = Task(kind="scan", status="queued", phase="queued", result={})
        session.add(pending)
        session.flush()
        pending.result = {
            "scope": {"all": False, "root_ids": [root.id]},
            "roots": [entry(root, pending.id, list(session.scalars(select(Root))))],
        }
        queued_id = pending.id
    db.close()
    client, _ = connect(settings, token=token)
    try:
        recovered = client.get("/api/v1/tasks/" + running_id).json()
        assert recovered["status"] == "interrupted" and recovered["error"] == "service_restarted"
        assert recovered["result"]["root_scans"][0]["status"] == "interrupted"
        queued = client.get("/api/v1/tasks/" + queued_id).json()
        assert queued["status"] == "interrupted" and queued["error"] == "service_restarted"
        assert queued["result"]["root_scans"][0]["status"] == "interrupted"
        assert state(client)[1][a["id"]]["scan"]["task_id"] == running_id
        assert state(client)[1][b["id"]]["scan"] is None
        assert calls == 2
    finally:
        client.__exit__(None, None, None)


def test_restore_or_root_configuration_change_invalidates_local_index(library):
    client, media = library
    a, b = roots(client, media)
    image(Path(a["path"]) / "one/1.png")
    image(Path(b["path"]) / "one/1.png")
    sync(client)
    assert state(client)[1][a["id"]]["scan"]
    raw, _ = export(client)
    assert b"root_scan_progress_v1:" not in raw
    preview = inspect(client, raw)
    restored = restore(
        client, preview, {r["id"]: r["path"] for r in client.get("/api/v1/roots").json()["items"]}
    )
    assert restored["status"] == "completed", restored
    client.headers["X-Management-Epoch"] = client.get("/api/v1/info").json()["management_epoch"]
    assert all(r["scan"] is None for r in state(client)[1].values())
    completed(client, start(client, a["id"]))
    alternate = media / "alternate"
    alternate.mkdir()
    response = client.put("/api/v1/roots/" + a["id"], json={"name": "A", "path": str(alternate)})
    assert response.status_code == 200, response.text
    assert state(client)[1][a["id"]]["scan"] is None
    # A generation change invalidates any other cached facts as well.
    with client.app.state.db.write() as session:
        Authority.rotate(session)
    assert state(client)[1][a["id"]]["scan"] is None


def test_scoped_video_does_not_transfer_other_roots_missing_identity(library, samples):
    client, media = library
    a, b = media / "VA", media / "VB"
    a.mkdir()
    b.mkdir()
    assert client.put("/api/v1/roots/main", json={"name": "VA", "path": str(a)}).status_code == 200
    root_b = client.post("/api/v1/roots", json={"name": "VB", "path": str(b)}).json()
    put(samples / "h264.mov", b / "old.mov")
    scan(client)
    old_id = client.get("/api/v1/videos").json()["items"][0]["id"]
    (b / "old.mov").unlink()
    completed(client, start(client, root_b["id"]))
    with client.app.state.db.read() as session:
        old = session.get(Video, old_id)
        assert old.status == "missing"
        before = {c.name: getattr(old, c.name) for c in Video.__table__.columns}
    previous_scan = state(client)[1][root_b["id"]]["scan"]
    put(samples / "h264.mov", a / "copy.mov")
    completed(client, start(client, "main"))
    with client.app.state.db.read() as session:
        old = session.get(Video, old_id)
        assert {c.name: getattr(old, c.name) for c in Video.__table__.columns} == before
    assert state(client)[1][root_b["id"]]["scan"] == previous_scan
    assert client.get("/api/v1/videos").json()["items"][0]["id"] != old_id


def test_close_cancels_queued_scan_without_replacing_its_prior_completed_facts(
    library, monkeypatch
):
    from video_viewer.pack_scanner import inspect_image as inspect
    from video_viewer.root_scan_progress import entry

    client, media = library
    a, b = roots(client, media)
    image(Path(b["path"]) / "one/1.png")
    sync(client)
    before = state(client)[1][b["id"]]
    image(Path(a["path"]) / "new/1.png")
    entered, release = threading.Event(), threading.Event()

    def held(fd, *args):
        entered.set()
        assert release.wait(10)
        return inspect(fd, *args)

    monkeypatch.setattr("video_viewer.pack_scanner.inspect_image", held)
    time.sleep(0.05)
    first = start(client, a["id"])
    closer = None
    try:
        assert entered.wait(10)
        second = start(client, b["id"])
        assert second["status"] == "queued"
        scanner = client.app.state.scanner
        closer = threading.Thread(target=scanner.close)
        closer.start()
        assert scanner.stop.wait(5)
    finally:
        release.set()
        if closer:
            closer.join(10)
            assert not closer.is_alive()
    assert client.get("/api/v1/tasks/" + first["id"]).json()["status"] == "interrupted"
    queued = client.get("/api/v1/tasks/" + second["id"]).json()
    assert queued["status"] == "interrupted"
    assert queued["result"]["root_scans"][0]["status"] == "interrupted"
    assert state(client)[1][b["id"]] == before

    assert not state(client)[0]["scan_queue"]
    # Deterministically exercise a future picked up after the stop signal.
    with client.app.state.db.write() as session:
        root = session.get(Root, b["id"])
        late = Task(kind="scan", status="queued", phase="queued", result={})
        session.add(late)
        session.flush()
        late.result = {
            "scope": {"all": False, "root_ids": [root.id]},
            "roots": [entry(root, late.id, list(session.scalars(select(Root))))],
        }
        late_id = late.id
    scanner.run(late_id)
    assert client.get("/api/v1/tasks/" + late_id).json()["status"] == "interrupted"
    assert state(client)[1][b["id"]] == before


def test_new_outer_root_invalidates_previous_inner_scope_facts(library, samples):
    client, media = library
    inner = media / "inner"
    inner.mkdir()
    assert (
        client.put("/api/v1/roots/main", json={"name": "inner", "path": str(inner)}).status_code
        == 200
    )
    put(samples / "h264.mov", inner / "one.mov")
    scan(client)
    assert state(client)[1]["main"]["scan"]["status"] == "completed"
    assert (
        client.post("/api/v1/roots", json={"name": "outer", "path": str(media)}).status_code == 201
    )
    assert state(client)[1]["main"]["scan"] is None


def test_completed_root_in_active_full_scan_can_queue_a_real_rescan(library, monkeypatch):
    from video_viewer.pack_scanner import inspect_image as inspect

    client, media = library
    a, b = roots(client, media)
    image(Path(a["path"]) / "one/1.png")
    image(Path(b["path"]) / "one/1.png")
    entered, release = threading.Event(), threading.Event()

    def held(fd, *args):
        if os.readlink(f"/proc/self/fd/{fd}").startswith(b["path"]):
            entered.set()
            assert release.wait(10)
        return inspect(fd, *args)

    monkeypatch.setattr("video_viewer.pack_scanner.inspect_image", held)
    time.sleep(0.05)
    full = client.post("/api/v1/scans").json()
    try:
        assert entered.wait(10)
        previous = state(client)[1][a["id"]]["scan"]
        assert previous["status"] == "completed"
        image(Path(a["path"]) / "one/2.png", color="blue")
        time.sleep(0.05)
        rescan = start(client, a["id"])
        assert rescan["id"] != full["id"] and rescan["status"] == "queued"
        assert start(client, a["id"])["id"] == rescan["id"]
        current = state(client)[1][a["id"]]
        assert current["scan"] == previous
        assert current["queued_task_ids"] == [rescan["id"]]
    finally:
        release.set()
    completed(client, full)
    completed(client, rescan)
    catalog = client.get("/api/v1/packs").json()["items"]
    assert next(p for p in catalog if p["root_id"] == a["id"])["page_count"] == 2
    assert state(client)[1][a["id"]]["scan"]["task_id"] == rescan["id"]
    assert state(client)[1][b["id"]]["scan"]["task_id"] == full["id"]


def test_scoped_outer_uses_current_video_owner_and_preserves_type_boundary(library, samples):
    client, media = library
    inner = media / "inner"
    inner.mkdir()
    assert (
        client.put("/api/v1/roots/main", json={"name": "inner", "path": str(inner)}).status_code
        == 200
    )
    pack_source = media / "packs"
    child_source = pack_source / "video-child"
    child_source.mkdir(parents=True)
    assert (
        client.post(
            "/api/v1/roots", json={"name": "pack", "path": str(pack_source), "kind": "pack"}
        ).status_code
        == 201
    )
    child = client.post(
        "/api/v1/roots", json={"name": "video-child", "path": str(child_source)}
    ).json()
    put(samples / "h264.mov", inner / "one.mov")
    put(samples / "portrait.mp4", child_source / "one.mp4")
    scan(client)
    with client.app.state.db.read() as session:
        protected = session.scalar(select(Video).where(Video.root_id == child["id"]))
        protected_id = protected.id
        old_child = {c.name: getattr(protected, c.name) for c in Video.__table__.columns}
        old_id = session.scalar(select(Video.id).where(Video.root_id == "main"))
    outer = client.post("/api/v1/roots", json={"name": "outer", "path": str(media)}).json()
    (inner / "one.mov").unlink()
    (child_source / "one.mp4").unlink()
    completed(client, start(client, outer["id"]))
    with client.app.state.db.read() as session:
        assert session.get(Video, old_id).status == "missing"
        protected = session.get(Video, protected_id)
        assert {c.name: getattr(protected, c.name) for c in Video.__table__.columns} == old_child
