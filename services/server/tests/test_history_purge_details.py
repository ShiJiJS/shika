"""Original purge evidence, strict graph/parent identity and SQL JSON paging."""

import copy
import errno
import json
import tracemalloc
import uuid
from pathlib import Path

import pytest
from sqlalchemy import select

from shika.backup_history import HistoryArchive
from shika.errors import LibraryError
from shika.models import ImagePack, PackPurgeEntry, PackPurgePlan, PackPurgeStep, Task
from shika.pack_purge_manifest import digest_json

from .test_backup_history import hashes, stage
from .test_management_archives import export, inspect, restore
from .test_media_types import pack_root
from .test_pack_operations import trash, tree
from .test_pack_purge_execution import execute, plan
from .test_pack_purge_plans import fixture
from .test_packs import image, packs, sync


def prepared(client, media, count=2):
    root, packs, rows = fixture(client, media, count)
    preview = plan(client, [v["id"] for v in rows])

    def fail(phase, identity):
        if phase == "purge_purging":
            with client.app.state.db.read() as db:
                row = db.get(PackPurgeStep, identity)
                if row.relative_path == "nested/2.jpg":
                    raise OSError(errno.EACCES, "isolated original permission failure")

    client.app.state.pack_purge.fault_hook = fail
    operation = execute(client, preview)
    client.app.state.pack_purge.fault_hook = None
    assert operation["result"]["pages_deleted"] == count
    assert operation["result"]["pages_total"] - operation["result"]["pages_deleted"] == count
    return root, packs, rows, preview, operation


def mutate_evidence(client, preview, pack_id):
    with client.app.state.db.write() as db:
        entry = db.scalar(select(PackPurgeEntry).where(PackPurgeEntry.pack_id == pack_id))
        entry.name = db.get(ImagePack, pack_id).name = "new graph title"
        manifest = copy.deepcopy(entry.manifest)
        manifest["files"][0]["sha256"] = "f" * 64
        entry.manifest, entry.digest = manifest, digest_json(manifest)
        db.flush()
        db.get(PackPurgePlan, preview["id"]).digest = digest_json(
            [
                {"trash_id": r.trash_id, "digest": r.digest}
                for r in db.scalars(select(PackPurgeEntry).order_by(PackPurgeEntry.trash_id))
            ]
        )
        for row in db.scalars(select(PackPurgeStep).where(PackPurgeStep.error.is_not(None))):
            row.error = "different_error_in_later_graph"


def test_original_graph_plan_files_results_and_wrong_parent_never_fall_back(library, tmp_path):
    client, media = library
    _, packs, rows, preview, operation = prepared(client, media)
    old = stage(client, tmp_path / "old")
    mutate_evidence(client, preview, packs[0]["id"])
    new = stage(client, tmp_path / "new")
    bundle = HistoryArchive.prepare([old, new], tmp_path / "history")
    older, newer = [v.identity for v in bundle.graphs()]
    before, files_before = hashes(bundle.directory), tree(media)
    first = bundle.purge_review(operation["id"], limit=1, graph_id=older)
    second = bundle.purge_review(operation["id"], offset=1, limit=1, graph_id=older)
    assert first["plan_id"] == preview["id"] and first["operation_id"] == operation["id"]
    assert first["total"] == 2 and first["image_count"] == 4 and first["ready"] is False
    assert len(first["items"]) == len(second["items"]) == 1
    assert first["items"][0]["trash_id"] != second["items"][0]["trash_id"]
    original = bundle.purge_review(preview["id"], graph_id=older)
    changed = bundle.purge_review(preview["id"], graph_id=newer)
    assert "new graph title" not in str(original["items"]) and "new graph title" in str(
        changed["items"]
    )
    selected = next(v for v in original["items"] if v["pack_id"] == packs[0]["id"])
    old_files = bundle.purge_files(operation["id"], selected["trash_id"], limit=1, graph_id=older)
    new_files = bundle.purge_files(operation["id"], selected["trash_id"], limit=1, graph_id=newer)
    assert old_files["total"] == 2 and new_files["items"][0]["sha256"] == "f" * 64
    assert old_files["items"][0]["sha256"] != new_files["items"][0]["sha256"]
    results = bundle.purge_pages(
        operation["id"], kind="image", outcome="unfinished", limit=1, graph_id=older
    )
    latest = bundle.purge_pages(
        operation["id"], kind="image", outcome="unfinished", limit=1, graph_id=newer
    )
    assert results["total"] == 2 and len(results["items"]) == 1
    assert results["items"][0]["error"] != latest["items"][0]["error"]
    assert latest["items"][0]["error"] == "different_error_in_later_graph"
    assert all(
        v["kind"] == "directory"
        for v in bundle.purge_pages(operation["id"], kind="directory", graph_id=older)["items"]
    )
    for action in (
        lambda: bundle.purge_review(operation["id"]),
        lambda: bundle.purge_review(operation["id"], graph_id=str(uuid.uuid4())),
        lambda: bundle.purge_review("absent-parent", graph_id=older),
        lambda: bundle.purge_review(
            client.get("/api/v1/pack-file-requests/trash").json()["id"], graph_id=older
        ),
        lambda: bundle.purge_files(operation["id"], "not-in-this-plan", graph_id=older),
        lambda: bundle.purge_pages(preview["id"], graph_id=older),
    ):
        with pytest.raises(LibraryError):
            action()
    with pytest.raises(ValueError):
        bundle.purge_review(operation["id"], offset=-1, graph_id=older)
    with pytest.raises(ValueError):
        bundle.purge_pages(operation["id"], kind="video", graph_id=older)
    assert hashes(bundle.directory) == before and tree(media) == files_before


def test_public_routes_after_two_complete_restores_keep_exact_epoch_and_no_writes(library):
    client, media = library
    root = pack_root(client, media)
    for i in range(27):
        base = Path(root["path"]) / f"pack-{i}"
        image(base / "1.png")
        image(base / "nested/2.jpg", color="blue")
        (base / "notes.txt").write_text("retain attachment")
        (base / "empty").mkdir()
    sync(client)
    ids = [v["id"] for v in packs(client, limit=100)["items"]]
    assert len(ids) == 27
    assert trash(client, ids)["result"]["succeeded"] == 27
    rows = client.get("/api/v1/pack-trash", params={"limit": 100}).json()["items"]
    assert len(rows) == 27
    raw, _ = export(client)
    imported = inspect(client, raw)
    preview = plan(client, [v["id"] for v in rows])
    outcome = execute(client, preview)
    original_files = client.get(
        f"/api/v1/pack-purge-plans/{preview['id']}/files", params={"trash_id": rows[0]["id"]}
    ).json()
    original_pages = client.get(
        f"/api/v1/pack-operations/{outcome['id']}/pages", params={"limit": 100}
    ).json()
    old_epoch = client.get("/api/v1/info").json()["management_epoch"]
    expected_media = tree(media)
    first = restore(client, imported, {"main": str(media), root["id"]: root["path"]})
    assert first["status"] == "completed", first
    client.app.state.backups.futures[first["id"]].result(timeout=30)
    current = client.get("/api/v1/info").json()["management_epoch"]
    client.headers["X-Management-Epoch"] = current
    raw, _ = export(client, "next-export")
    imported = inspect(client, raw, "next-inspect")
    second = restore(
        client, imported, {"main": str(media), root["id"]: root["path"]}, "next-restore"
    )
    assert second["status"] == "completed", second
    client.app.state.backups.futures[second["id"]].result(timeout=30)
    client.headers["X-Management-Epoch"] = client.get("/api/v1/info").json()["management_epoch"]
    assert "management_purge_history" in client.get("/api/v1/info").json()["capabilities"]
    graph = client.get(f"/api/v1/management-history/epochs/{old_epoch}").json()["graph_id"]
    history = client.app.state.backups.archives.history()
    immutable = hashes(history.directory)
    with client.app.state.db.read() as db:
        tasks_before = set(db.scalars(select(Task.id)))
    base = f"/api/v1/management-history/tasks/{outcome['id']}"
    query = {"epoch": old_epoch}
    a = client.get(base + "/purge-review", params={**query, "limit": 24}).json()
    b = client.get(base + "/purge-review", params={**query, "offset": 24, "limit": 24}).json()
    assert a["historical"] is True and a["ready"] is False and a["graph_id"] == graph
    assert a["total"] == 27 and len(a["items"]) == 24 and len(b["items"]) == 3
    files = client.get(
        base + "/purge-review/files", params={**query, "trash_id": rows[0]["id"]}
    ).json()
    assert files["items"] == original_files["items"]
    result = client.get(base + "/purge-pages", params={**query, "limit": 100}).json()
    assert result["items"] == original_pages["items"] and result["total"] == 135
    assert (
        client.get(base + "/purge-pages", params={**query, "outcome": "unfinished"}).json()["total"]
        == 0
    )
    assert client.get(base + "/purge-review").status_code == 422
    assert (
        client.get(base + "/purge-review", params={"graph_id": str(uuid.uuid4())}).status_code
        == 404
    )
    assert (
        client.get(
            base + "/purge-review", params={**query, "graph_id": str(uuid.uuid4())}
        ).status_code
        == 422
    )
    assert (
        client.get(base + "/purge-review/files", params={**query, "trash_id": "other"}).status_code
        == 404
    )
    assert client.get(base + "/purge-pages", params={**query, "kind": "video"}).status_code == 422
    assert client.get(base + "/purge-pages", params={**query, "limit": 101}).status_code == 422
    assert client.post(base + "/purge-pages", json={}).status_code == 405
    assert hashes(history.directory) == immutable and tree(media) == expected_media
    with client.app.state.db.read() as db:
        assert set(db.scalars(select(Task.id))) == tasks_before


def test_large_actual_manifest_file_is_paged_in_sql_without_python_materialization(
    library, tmp_path
):
    client, media = library
    _, _, rows = fixture(client, media)
    preview = plan(client, [rows[0]["id"]])
    count = 18000
    with client.app.state.db.write() as db:
        entry = db.scalar(select(PackPurgeEntry).where(PackPurgeEntry.plan_id == preview["id"]))
        manifest = copy.deepcopy(entry.manifest)
        template = manifest["files"][0]
        manifest["files"] = [
            {
                **template,
                "id": str(uuid.uuid4()),
                "relative_path": f"{'x' * 1024}/{i}.png",
                "path": f"{entry.path}/{'x' * 1024}/{i}.png",
            }
            for i in range(count)
        ]
        entry.manifest, entry.digest, entry.image_count = manifest, digest_json(manifest), count
        entry.image_bytes = count * template["size"]
        db.flush()
        db.get(Task, preview["id"]).result = client.app.state.pack_purge_plans.result(
            client.app.state.pack_purge_plans.summaries(db, preview["id"])
        )
        db.get(PackPurgePlan, preview["id"]).digest = digest_json(
            [{"trash_id": entry.trash_id, "digest": entry.digest}]
        )
    staged = stage(client, tmp_path / "staged-large")
    bundle = HistoryArchive.prepare([staged], tmp_path / "large-history")
    graph = next(bundle.graphs())
    before = hashes(bundle.directory)
    tracemalloc.start()
    try:
        a = bundle.purge_files(
            preview["id"], rows[0]["id"], offset=100, limit=100, graph_id=graph.identity
        )
        b = bundle.purge_files(
            preview["id"], rows[0]["id"], offset=count - 1, limit=100, graph_id=graph.identity
        )
        peak = tracemalloc.get_traced_memory()[1]
    finally:
        tracemalloc.stop()
    assert a["total"] == b["total"] == count and len(a["items"]) == 100 and len(b["items"]) == 1
    assert a["items"][0]["relative_path"].endswith("/100.png") and b["items"][0][
        "relative_path"
    ].endswith("/17999.png")
    assert peak < 5 * 1024 * 1024
    assert hashes(bundle.directory) == before
    print(
        "PURGE_HISTORY_BOUNDED:"
        + json.dumps(
            {
                "sqlite_bytes": graph.database.stat().st_size,
                "files": count,
                "python_peak_bytes": peak,
            }
        )
    )


def test_unfinished_and_invalid_original_manifest_are_explicit_not_rebuilt(
    library, tmp_path, monkeypatch
):
    from .test_pack_purge_plans import prepare

    client, media = library
    _, _, rows = fixture(client, media)
    monkeypatch.setattr(client.app.state.pack_purge_plans, "enqueue", lambda _: None)
    accepted = prepare(client, [rows[0]["id"]])
    original = stage(client, tmp_path / "unfinished")
    with client.app.state.db.write() as db:
        entry = db.scalar(select(PackPurgeEntry).where(PackPurgeEntry.plan_id == accepted["id"]))
        entry.manifest = {"files": {}}
    invalid = stage(client, tmp_path / "invalid")
    bundle = HistoryArchive.prepare([original, invalid], tmp_path / "unfinished-history")
    graphs = list(bundle.graphs())
    before, media_before = hashes(bundle.directory), tree(media)
    view = bundle.purge_review(accepted["id"], graph_id=graphs[0].identity)
    assert view["status"] == "queued" and view["ready"] is False and view["image_count"] == 0
    assert len(view["items"]) == 1
    for graph, expected in zip(
        graphs, ["pack_purge_plan_not_ready", "invalid_history_manifest"], strict=True
    ):
        with pytest.raises(LibraryError) as failure:
            bundle.purge_files(accepted["id"], rows[0]["id"], graph_id=graph.identity)
        assert failure.value.code == expected
    assert hashes(bundle.directory) == before and tree(media) == media_before
