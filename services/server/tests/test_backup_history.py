"""Historical graphs stay distinct, queryable, bounded and incapable of replay."""

import errno
import hashlib
import json
import sqlite3
import stat
import subprocess
import sys
import tracemalloc
import uuid
from contextlib import closing
from dataclasses import replace
from pathlib import Path

import pytest
from sqlalchemy import insert, select

import video_viewer.backup_history as history
from video_viewer.backup_archive import freeze_graph, inspect_v2, write_v2
from video_viewer.backup_history import HistoryArchive
from video_viewer.backup_v2_schema import mounts_from
from video_viewer.errors import LibraryError
from video_viewer.models import PackFileOperation, PackRestoreBatch, RequestRecord, Task

from .conftest import put, scan
from .test_backup_archive import MAXIMUM, archive
from .test_file_operations import trash as video_trash
from .test_media_types import pack_root
from .test_pack_missing import missing
from .test_pack_missing import submit as submit_missing
from .test_pack_missing import wait as wait_missing
from .test_pack_operations import trash, tree
from .test_pack_purge_execution import execute, plan
from .test_pack_restore_plans import submit, wait
from .test_packs import image, packs, sync
from .test_playback import create_round


def stage(client, folder):
    folder.mkdir()
    source, _ = archive(client, folder)
    return inspect_v2(source, folder / "staged", maximum_bytes=MAXIMUM)


def hashes(folder):
    result = {}
    for path in folder.rglob("*"):
        if path.is_file():
            with path.open("rb") as source:
                result[path.relative_to(folder).as_posix()] = hashlib.file_digest(
                    source, "sha256"
                ).hexdigest()
    return result


def seed(client, identity, *, status="running", value="old", key="same:key", count=1):
    with client.app.state.db.write() as session:
        session.add_all(
            Task(
                id=identity if index == 0 else str(uuid.uuid4()),
                kind="backup_export",
                status=status,
                phase=status,
                created_at=4000000000,
                result={"marker": value},
            )
            for index in range(count)
        )
        session.add(RequestRecord(id=key, fingerprint="hash-" + value, result={"marker": value}))


def test_real_parent_members_children_receipts_roundtrip_and_no_source_actions(library, tmp_path):
    client, media = library
    root = pack_root(client, media)
    for number in range(28):
        folder = Path(root["path"]) / f"pack-{number}"
        image(folder / "1.png")
        image(folder / "nested/2.jpg", color="blue")
        (folder / "notes.txt").write_text("retain attachment")
    sync(client)
    catalog = packs(client, limit=100)["items"]
    assert len(catalog) == 28
    assert trash(client, [p["id"] for p in catalog])["result"]["succeeded"] == 28
    response = client.get("/api/v1/pack-trash", params={"limit": 100})
    assert response.status_code == 200, response.text
    rows = response.json()["items"]
    assert len(rows) == 28
    purged = execute(client, plan(client, [rows[0]["id"]]))
    parent = wait(client, submit(client, [r["id"] for r in rows[1:]])["id"])
    assert parent["status"] == purged["status"] == "completed"
    expected = tree(media)
    staged = stage(client, tmp_path / "original")
    inspected_hashes = hashes(staged.directory)
    bundle = HistoryArchive.prepare([staged], tmp_path / "history")
    before = hashes(bundle.directory)
    assert hashes(staged.directory) == inspected_hashes
    assert stat.S_IMODE(bundle.directory.stat().st_mode) == 0o700
    assert all(stat.S_IMODE(p.stat().st_mode) == 0o600 for p in bundle.directory.iterdir())
    first = bundle.members(parent["id"])
    tail = bundle.members(parent["id"], offset=24)
    assert first["historical"] and first["total"] == tail["total"] == 27
    assert len(first["items"]) == 24 and len(tail["items"]) == 3
    assert {r["id"] for r in first["items"] + tail["items"]} == {r["id"] for r in rows[1:]}
    assert bundle.members(parent["id"], unfinished=True)["total"] == 0
    with client.app.state.db.read() as session:
        children = set(session.scalars(select(PackRestoreBatch.operation_id)))
        operation = session.get(PackFileOperation, purged["id"])
        original_key = operation.request_key
        expected_hash = operation.request_hash
    listing = bundle.tasks(family="pack", limit=100)
    assert {r["id"] for r in listing["items"]}.isdisjoint(children)
    assert all(r["historical"] and r["state"] == "historical" for r in listing["items"])
    assert all(bundle.task(child)["historical"] for child in children)
    receipt = bundle.receipt("pack_file_operations", original_key)
    assert receipt["fingerprint"] == expected_hash and receipt["task"]["result"] == purged["result"]
    assert receipt["historical"] and receipt["record"]["id"] == purged["id"]
    assert receipt["record"]["historical"] and receipt["task"]["historical"]
    result = bundle.members(purged["id"])
    assert result["total"] == 1 and result["items"][0]["outcome"] == "succeeded"
    reopened = HistoryArchive(bundle.directory)
    assert reopened.tasks() == bundle.tasks()
    # The complete graph, not just the projected tasks, survives another export.
    target = tmp_path / "again.vvbackup"
    with freeze_graph(
        client.app.state.db, mounts_from(client.app.state.settings), tmp_path
    ) as active:
        write_v2(target, _with_history(active, reopened), maximum_bytes=MAXIMUM)
    second = inspect_v2(target, tmp_path / "again", maximum_bytes=MAXIMUM)
    historical = next(g for g in second.graphs() if g.kind == "history")
    assert second.counts(historical.identity) == staged.counts()
    assert hashes(bundle.directory) == before and tree(media) == expected
    with client.app.state.db.read() as session:
        assert not session.get(PackFileOperation, purged["id"]).historical
    assert not hasattr(bundle, "submit") and not hasattr(bundle, "run")


def _with_history(active, bundle):
    yield active
    yield from bundle.graphs()


def test_latest_source_wins_without_losing_explicit_old_graph(library, tmp_path):
    client, _ = library
    identity = str(uuid.uuid4())
    seed(client, identity)
    old = stage(client, tmp_path / "old")
    with client.app.state.db.write() as session:
        task = session.get(Task, identity)
        task.status = task.phase = "completed"
        task.result = {"marker": "new"}
        record = session.get(RequestRecord, "same:key")
        record.result, record.fingerprint = {"marker": "new"}, "hash-new"
    new = stage(client, tmp_path / "new")
    bundle = HistoryArchive.prepare([old, new], tmp_path / "history")
    assert bundle.tasks()["total"] == 1
    assert bundle.task(identity)["status"] == "completed"
    assert bundle.receipt("request_records", "same:key")["record"]["result"] == {"marker": "new"}
    older = next(bundle.graphs()).identity
    assert bundle.task(identity, graph_id=older)["status"] == "running"
    assert bundle.receipt("request_records", "same:key", graph_id=older)["record"]["result"] == {
        "marker": "old"
    }
    assert bundle.members(identity, graph_id=older)["items"] == []
    with pytest.raises(LibraryError, match="原历史记录"):
        bundle.task("missing")
    with pytest.raises(LibraryError, match="原历史记录"):
        bundle.receipt("request_records", "missing")
    with pytest.raises(ValueError):
        bundle.receipt("unknown_table", "same:key")
    assert bundle.tasks(graph_id="unknown")["total"] == 0


def test_all_receipt_families_are_distinct_and_missing_members_keep_original_paths(
    library, samples, tmp_path
):
    client, media = library
    _, pack, folder = missing(client, media)
    cleanup = wait_missing(client, submit_missing(client))
    assert cleanup["result"]["succeeded"] == 1
    put(samples / "h264.mov", media / "video.mov")
    scan(client)
    video, request = create_round(client, "sequential")
    removed, command = video_trash(client, [video["current"]["id"]])
    key = "files:" + command["request_id"]
    with client.app.state.db.write() as session:
        session.add(RequestRecord(id=key, fingerprint="other-family", result={"settings": True}))
    source = stage(client, tmp_path / "source")
    expected = tree(media)
    bundle = HistoryArchive.prepare([source], tmp_path / "history")
    assert bundle.receipt("file_operations", key)["task"]["id"] == removed["id"]
    assert bundle.receipt("request_records", key)["record"]["result"] == {"settings": True}
    assert bundle.receipt("playback_rounds", request["request_id"])["record"]["id"] == video["id"]
    assert bundle.receipt("pack_sessions", "session")["record"]["request_id"] == "session"
    assert (
        bundle.receipt("request_records", "pack.opened:open")["record"]["result"]["page"]["pack_id"]
        == pack["id"]
    )
    old_cleanup = bundle.receipt("pack_missing_cleanups", "cleanup")
    assert old_cleanup["task"]["id"] == cleanup["id"]
    members = bundle.members(cleanup["id"])
    assert members["total"] == 1 and members["items"][0]["path"] == str(folder)
    assert members["items"][0]["media_id"] == pack["id"]
    assert bundle.members(removed["id"])["items"][0]["outcome"] == "succeeded"
    assert tree(media) == expected


def test_library_precedence_and_repeated_immutable_history_deduplication(library, tmp_path):
    client, _ = library
    identity = str(uuid.uuid4())
    seed(client, identity)
    old = stage(client, tmp_path / "old")
    original = HistoryArchive.prepare([old], tmp_path / "original")
    with client.app.state.db.write() as session:
        session.get(Task, identity).kind = "scan"
    path = tmp_path / "source.vvbackup"
    with freeze_graph(
        client.app.state.db, mounts_from(client.app.state.settings), tmp_path
    ) as active:
        write_v2(path, _with_history(active, original), maximum_bytes=MAXIMUM)
    newer = inspect_v2(path, tmp_path / "newer", maximum_bytes=MAXIMUM)
    bundle = HistoryArchive.prepare([newer, newer], tmp_path / "history")
    assert len(list(bundle.graphs())) == 3  # Two current snapshots, one shared immutable history.
    assert bundle.task(identity)["family"] == "scan"
    assert bundle.tasks(family="backup")["total"] == 0  # Don't fall through to the older ID.
    assert bundle.tasks(family="scan")["total"] == 1
    old_graph = next(original.graphs()).identity
    assert bundle.tasks(family="backup", graph_id=old_graph)["total"] == 1


def test_conflicting_history_identity_never_publishes(library, tmp_path):
    client, _ = library
    identity, graph_id = str(uuid.uuid4()), str(uuid.uuid4())
    seed(client, identity)
    sources = []
    for index in range(2):
        with client.app.state.db.write() as session:
            session.get(Task, identity).result = {"marker": index}
        path = tmp_path / f"source-{index}.vvbackup"
        with freeze_graph(
            client.app.state.db, mounts_from(client.app.state.settings), tmp_path
        ) as active:
            write_v2(
                path,
                [active, replace(active, kind="history", identity=graph_id)],
                maximum_bytes=MAXIMUM,
            )
        sources.append(inspect_v2(path, tmp_path / f"staged-{index}", maximum_bytes=MAXIMUM))
    with pytest.raises(LibraryError) as failure:
        HistoryArchive.prepare(sources, tmp_path / "history")
    assert failure.value.code == "history_identity_conflict"
    assert not (tmp_path / "history").exists() and not list(tmp_path.glob("history-prepare-*"))


@pytest.mark.parametrize("failure", ["cancel", "disk", "changed"])
def test_prepare_failures_preserve_sources_and_never_publish(
    library, tmp_path, monkeypatch, failure
):
    client, _ = library
    seed(client, str(uuid.uuid4()), count=30)
    source = stage(client, tmp_path / "source")
    before = hashes(source.directory)
    calls = 0

    def check():
        nonlocal calls
        calls += 1
        if calls == 12:
            raise InterruptedError("cancel indexing")

    if failure == "disk":

        def no_space(*args):
            raise OSError(errno.ENOSPC, "injected index disk full")

        monkeypatch.setattr(history, "_index_graph", no_space)
    elif failure == "changed":
        original = history._copy_graph

        def changed(graph, path, callback):
            with graph.database.open("ab") as file:
                file.write(b"changed-after-manifest-verification")
            return original(graph, path, callback)

        monkeypatch.setattr(history, "_copy_graph", changed)
    with pytest.raises((InterruptedError, OSError, LibraryError)):
        HistoryArchive.prepare(
            [source], tmp_path / "history", check=check if failure == "cancel" else None
        )
    assert not (tmp_path / "history").exists() and not list(tmp_path.glob("history-prepare-*"))
    if failure != "changed":
        assert hashes(source.directory) == before


def test_existing_destination_and_invalid_pages_do_not_change_any_bytes(library, tmp_path):
    client, _ = library
    seed(client, str(uuid.uuid4()))
    source = stage(client, tmp_path / "source")
    target = tmp_path / "history"
    bundle = HistoryArchive.prepare([source], target)
    before = hashes(target)
    with pytest.raises(FileExistsError):
        HistoryArchive.prepare([source], target)
    for offset, limit in [(-1, 24), (True, 24), (2**63, 24), (0, 101), (0, False)]:
        with pytest.raises(ValueError):
            bundle.tasks(offset=offset, limit=limit)
        with pytest.raises(ValueError):
            bundle.members("missing", offset=offset, limit=limit)
    with pytest.raises(ValueError):
        bundle.tasks(family="bad")
    graph = next(bundle.graphs())
    with closing(
        sqlite3.connect(graph.database.as_uri() + "?mode=ro&immutable=1", uri=True)
    ) as connection:
        with pytest.raises(sqlite3.OperationalError, match="readonly"):
            connection.execute("DELETE FROM tasks")
    alias = tmp_path / "alias"
    alias.symlink_to(target, target_is_directory=True)
    with pytest.raises(FileExistsError):
        HistoryArchive.prepare([source], alias)
    assert hashes(target) == before


@pytest.mark.parametrize("phase", ["before_publish", "after_publish"])
def test_process_kill_cannot_publish_a_partial_history_bundle(library, tmp_path, phase):
    client, _ = library
    identity = str(uuid.uuid4())
    seed(client, identity, count=30)
    source = stage(client, tmp_path / "source")
    before = hashes(source.directory)
    target = tmp_path / "history"
    script = """
import os, signal, sys
import video_viewer.backup_history as history
from video_viewer.backup_archive import StagedArchive
original = history.rename_new
def publish(*args):
    if sys.argv[3] == 'before_publish':
        os.kill(os.getpid(), signal.SIGKILL)
    original(*args)
    os.kill(os.getpid(), signal.SIGKILL)
history.rename_new = publish
history.HistoryArchive.prepare([StagedArchive(sys.argv[1])], sys.argv[2])
"""
    result = subprocess.run(
        [sys.executable, "-c", script, str(source.directory), str(target), phase],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == -9, result.stderr
    assert hashes(source.directory) == before
    if phase == "before_publish":
        assert not target.exists()
        # A parent restore journal must later reap this unreferenced folder.
        assert len(list(tmp_path.glob("history-prepare-*"))) == 1
    else:
        reopened = HistoryArchive(target)
        assert reopened.tasks()["total"] == 30
        assert reopened.task(identity)["historical"]
        assert reopened.receipt("request_records", "same:key")["record"]["result"] == {
            "marker": "old"
        }
    print(
        "VV_HISTORY_KILL",
        json.dumps(
            {
                "phase": phase,
                "returncode": result.returncode,
                "published": target.exists(),
                "source_unchanged": True,
            }
        ),
    )


def test_large_results_are_not_materialized_in_task_index_or_pages(library, tmp_path):
    client, _ = library
    with client.app.state.db.write() as session:
        for start in range(0, 18000, 100):
            session.execute(
                insert(Task),
                [
                    dict(
                        id=str(uuid.uuid4()),
                        kind="backup_export",
                        status="running",
                        phase="exporting",
                        created_at=4000000000 + start + index,
                        result={"private_note": "X" * 2048},
                    )
                    for index in range(100)
                ],
            )
    source = stage(client, tmp_path / "large")
    archive_file = tmp_path / "large/management.vvbackup"
    assert archive_file.stat().st_size > 32 * 1024 * 1024
    tracemalloc.start()
    try:
        bundle = HistoryArchive.prepare([source], tmp_path / "history")
        first, tail = bundle.tasks(), bundle.tasks(offset=17976)
        _, peak = tracemalloc.get_traced_memory()
    finally:
        tracemalloc.stop()
    assert first["total"] == tail["total"] == 18000
    assert len(first["items"]) == len(tail["items"]) == 24
    assert not {r["id"] for r in first["items"]} & {r["id"] for r in tail["items"]}
    assert "private_note" not in json.dumps(first) and len(json.dumps(first)) < 24000
    assert peak < 16 * 1024 * 1024
    with closing(sqlite3.connect(bundle.directory / "index.sqlite3")) as index:
        count, longest = index.execute(
            "SELECT count(*),max(length(summary)) FROM history_tasks"
        ).fetchone()
        assert count == 18000 and 0 < longest < 2048
        assert (
            index.execute(
                "SELECT count(*) FROM history_tasks WHERE instr(summary,'private_note')>0"
            ).fetchone()[0]
            == 0
        )
    print(
        "VV_HISTORY_MEMORY",
        json.dumps(
            {
                "archive_bytes": archive_file.stat().st_size,
                "python_peak_bytes": peak,
                "indexed_tasks": 18000,
                "page_count": 24,
            }
        ),
    )
