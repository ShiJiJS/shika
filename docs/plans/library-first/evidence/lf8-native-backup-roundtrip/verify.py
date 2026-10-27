#!/usr/bin/env python3
"""Read-only audit of real DocumentsUI + HTTP archive restoration and cancel."""

import copy
import gzip
import hashlib
import json
import struct
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SOURCE = "5373baa"
BASE = "4c2d6ee7"
HASHES = {}
COLUMNS = {
    "roots": ["id", "name", "path", "mount_id", "kind", "enabled"],
    "tags": ["id", "name"],
    "pack_tag_definitions": ["id", "name"],
    "packs": ["id", "root_id", "path", "name", "content_version", "page_count"],
    "pack_pages": [
        "id",
        "pack_id",
        "relative_path",
        "ordinal",
        "width",
        "height",
        "size",
        "format",
        "sha256",
    ],
}
SCENES = [
    "backup-start",
    "backup-dark",
    "restore-first-page",
    "restore-keyboard",
    "restore-confirm-off",
    "backup-restore-point",
    "snapshot-preview",
    "snapshot-confirm-off",
]


def read(path):
    return json.loads(path.read_text())


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def fixed_source(folder, source):
    metadata = read(folder / "source.json")
    assert metadata["commit"] == git("rev-parse", source).decode().strip()
    assert metadata["prototype_tree"] == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
    for path, digest in metadata["files"].items():
        key = (source, path)
        if key not in HASHES:
            HASHES[key] = sha(git("show", source + ":" + path))
        assert HASHES[key] == digest, path


def log_events(folder, marker):
    return [
        json.loads(line.split(marker, 1)[1])
        for line in (folder / "android-test.log").read_text().splitlines()
        if marker in line
    ]


def command(journal, kind):
    rows = [
        state[kind] for state in journal["state"]["scopes"].values() if kind in state
    ]
    (row,) = rows
    return row


def document(folder):
    digest, size = hashlib.sha256(), 0
    rows = {t: [] for t in COLUMNS}
    notes = []
    header = None
    with gzip.open(folder / "exported-document.vvbackup.gz", "rb") as file:
        for line in file:
            digest.update(line)
            size += len(line)
            row = json.loads(line)
            if row["record"] == "header":
                header = row
            if row["record"] == "row":
                table, value = row["table"], row["value"]
                if table in COLUMNS:
                    rows[table].append({c: value[c] for c in COLUMNS[table]})
                if (
                    table == "tasks"
                    and isinstance(value.get("result"), dict)
                    and "note" in value["result"]
                ):
                    assert value["result"]["note"] == "x" * 2048
                    notes.append([value[c] for c in ("id", "kind", "status", "phase")])
    assert header["version"] == 2 and header["format"] == "video-viewer-management"
    for values in rows.values():
        values.sort(key=lambda v: v["id"])
    note_hash = hashlib.sha256()
    for row in sorted(notes):
        note_hash.update(json.dumps([*row, "x" * 2048], separators=(",", ":")).encode())
        note_hash.update(b"\n")
    return size, digest.hexdigest(), rows, len(notes), note_hash.hexdigest()


def verify():
    manifest = read(HERE / "manifest.json")
    for path, digest in manifest.items():
        assert sha((HERE / path).read_bytes()) == digest, path
        assert git("ls-files", "--error-unmatch", str((HERE / path).relative_to(ROOT)))
    for tree in (
        "apps/mobile/lib",
        "apps/mobile/android",
        "apps/mobile/assets",
        "services/server/video_viewer",
    ):
        assert git("rev-parse", BASE + ":" + tree) == git(
            "rev-parse", SOURCE + ":" + tree
        )
    assert "No issues found!" in (HERE / "checks/analyze-final.log").read_text()
    assert "0 changed" in (HERE / "checks/format-final.log").read_text()
    assert "All checks passed!" in (HERE / "checks/ruff-final.log").read_text()
    summary = {}
    for name, cancelled in (("small", False), ("large-cancel", True)):
        folder = HERE / name
        fixed_source(folder, SOURCE)
        result = read(folder / "result.json")
        assert (
            result["passed"]
            and result["large_document"] == cancelled
            and result["cancel_inputs"] == cancelled
        )
        assert result["native_points"] == (10 if cancelled else 8) and result[
            "system_points"
        ] == (4 if cancelled else 2)
        scenes = list(SCENES)
        if cancelled:
            scenes[2:2] = ["save-cancelled", "pick-cancelled"]
        host = read(folder / "host-events.json")
        assert not host["errors"] and [e["state"] for e in host["events"]] == [
            "archive-ui-" + s for s in scenes
        ]
        epochs = {e["epoch"] for e in host["events"]}
        assert (
            len(epochs) == 2
            and host["events"][0]["epoch"] != host["events"][-1]["epoch"]
        )
        assert [e["state"] for e in log_events(folder, "ARCHIVE_UI_METRICS:")] == [
            "archive-ui-" + s for s in scenes
        ]
        stages = (
            ["cancel-save", "save", "cancel-pick", "pick"]
            if cancelled
            else ["save", "pick"]
        )
        events = read(folder / "system-events.json")
        assert [e["stage"] for e in events] == stages
        done = log_events(folder, "ARCHIVE_SYSTEM_DONE:")
        assert [e["stage"] for e in done] == stages
        size, digest, rows, note_count, note_hash = document(folder)
        saved = read(folder / "saved-document.json")
        assert (
            size == saved["bytes"] == result["document"]["bytes"]
            and digest == saved["sha256"]
        )
        assert (size > 32 * 1024 * 1024) == cancelled and size < 64 * 1024 * 1024
        assert saved["name"].startswith("video-viewer-backup-") and saved[
            "name"
        ].endswith(".vvbackup")
        selected = next(e for e in done if e["stage"] == "pick")
        assert selected["bytes"] == size and selected["sha256"] == digest
        for stage in stages + ["save-named"]:
            assert struct.unpack(
                ">II", (folder / ("system-" + stage + ".png")).read_bytes()[16:24]
            ) == (1170, 2532)
            assert (
                "com.google.android.documentsui"
                in (folder / ("system-" + stage + "-window.txt")).read_text()
            )
        named = ET.fromstring((folder / "system-save-named.xml").read_bytes())
        assert (
            len(
                [
                    n
                    for n in named.iter("node")
                    if n.get("class") == "android.widget.EditText"
                    and n.get("text") == saved["name"]
                ]
            )
            == 1
        )
        picked = ET.fromstring((folder / "system-pick.xml").read_bytes())
        assert (
            len(
                [
                    n
                    for n in picked.iter("node")
                    if n.get("resource-id") == "android:id/title"
                    and n.get("text") == saved["name"]
                ]
            )
            == 1
        )
        for scene in scenes:
            assert struct.unpack(
                ">II", (folder / ("archive-ui-" + scene + ".png")).read_bytes()[16:24]
            ) == (1170, 2532)
            assert (
                "io.github.shijijs.video_viewer"
                in (folder / ("archive-ui-" + scene + "-window.txt")).read_text()
            )
        requests = read(folder / "requests.json")

        def posts(path, captured=requests):
            return [r for r in captured if r["method"] == "POST" and r["path"] == path]

        (export,) = posts("/api/v1/management-backups")
        (imported,) = posts("/api/v1/management-backups/imports")
        (restored,) = posts("/api/v1/management-backups/restores")
        assert len(posts("/api/v1/auth/login")) == 1
        assert (
            len(
                [
                    r
                    for r in requests
                    if r["method"] == "POST" and "/from-snapshot/" in r["path"]
                ]
            )
            == 1
        )
        journals = read(folder / "journals.json")
        assert all(
            len(json.dumps(j["state"], ensure_ascii=False).encode()) < 65536
            for j in journals
        )
        original = command(journals[0], "export")
        preview = command(
            next(j for j in journals if j["stage"] == "before-restore-confirmation"),
            "inspect",
        )
        restore = command(journals[-1], "restore")
        assert export["body"]["request_id"] == original["key"]
        assert (
            original["file"]["sha256"] == digest and original["file"]["bytes"] == size
        )
        assert (
            imported["idempotency_key"] == preview["key"]
            and preview["digest"] == digest
        )
        assert (
            restored["body"] == {"request_id": restore["key"], **restore["body"]}
            and restore["settled"]
        )
        assert (
            restored["body"]["confirmed"]
            and len(restored["body"]["root_mapping"]) == 27
        )
        if cancelled:
            assert journals[0]["state"] == journals[1]["state"] == journals[2]["state"]
            assert done[0]["saved"] is False and done[2]["cancelled"]
            assert all(
                "inspect" not in s and "restore" not in s
                for s in journals[3]["state"]["scopes"].values()
            )
            for scene in ("save-cancelled", "pick-cancelled"):
                partial = read(folder / ("archive-ui-" + scene + "-requests.json"))
                assert (
                    sum(
                        r["method"] == "POST"
                        and r["path"] == "/api/v1/management-backups"
                        for r in partial
                    )
                    == 1
                )
                assert not any(
                    r["method"] == "POST"
                    and r["path"]
                    in {
                        "/api/v1/management-backups/imports",
                        "/api/v1/management-backups/restores",
                    }
                    for r in partial
                )
        assert read(folder / "notes-before.json") == read(folder / "notes-after.json")
        notes = read(folder / "notes-before.json")
        assert (
            note_count == notes["count"] == (18000 if cancelled else 0)
            and note_hash == notes["sha256"]
        )
        if cancelled:
            assert notes["min_note"] == notes["max_note"] == 2048
            assert read(folder / "control-guard.json")["invalid_key_status"] == 403
        proof = read(folder / "restored-data.json")
        assert proof["columns"] == COLUMNS and proof["archive_rows"] == rows
        expected = copy.deepcopy(rows)
        for pack in expected["packs"]:
            pack["content_version"] += 1
        assert (
            proof["matching"]
            and proof["restored_rows"] == proof["expected_restored_rows"] == expected
        )
        assert [len(rows[t]) for t in COLUMNS] == [27, 1, 1, 1, 1]
        (task,) = proof["restore_tasks"]
        task_result = json.loads(task["result"])
        assert task["id"] == restore["task"] and task["status"] == "completed"
        assert task_result["historical_operations_replayed"] == 0
        (final,) = log_events(folder, "ARCHIVE_UI_VERIFIED:")
        assert (
            final["restore_task"] == restore["task"]
            and final["snapshot"] == task_result["pre_snapshot_id"]
        )
        assert (
            final["native_documents"]
            and final["snapshot_not_confirmed"]
            and final["replacement_removed_late_tags"]
        )
        assert read(folder / "media-before.json") == read(folder / "media-after.json")
        assert len(read(folder / "media-before.json")) == 2
        assert (
            read(folder / "document-cleanup.json")["retained_owned_document"]
            == saved["name"]
        )
        assert read(folder / "document-cleanup.json")["other_names_unchanged"]
        display = read(folder / "restored-viewport.json")
        assert display["before"] == display["after"]
        assert not read(folder / "app-cleanup.json")["app_pid"]
        assert not read(folder / "launch-preparation.json")["app_pid_after_stop"]
        assert not (folder / "manual-launch-recovery.json").exists()
        assert (
            "All tests passed!" in (folder / "android-test.log").read_text()
            and read(folder / "exit.json")["code"] == 0
        )
        summary[name] = {
            "bytes": size,
            "sha256": digest,
            "app_points": len(scenes),
            "system_actions": len(stages),
            "note_tasks": note_count,
        }
    transport = HERE / "diagnostics/transport-quoting"
    fixed_source(transport, "0d99c23")
    diag = read(transport / "transport-diagnostic.json")
    assert diag["exec_out_bytes"] == 84 and diag["pulled_bytes"] == 19205
    assert (
        sha((transport / "diagnostic-pulled.vvbackup").read_bytes())
        == diag["pulled_sha256"]
    )
    assert not (transport / "result.json").exists()
    duplicate = HERE / "diagnostics/duplicate-provider-name"
    fixed_source(duplicate, "b48f257")
    old = read(duplicate / "saved-document.json")
    xml = ET.fromstring((duplicate / "system-pick.xml").read_bytes())
    assert (
        len(
            [
                n
                for n in xml.iter("node")
                if n.get("resource-id") == "android:id/title"
                and n.get("text") == old["name"]
            ]
        )
        == 2
    )
    assert not (duplicate / "result.json").exists()
    intermediate = HERE / "diagnostics/intermediate-manual-launch"
    fixed_source(intermediate, "13d813f")
    assert read(intermediate / "result.json")["passed"] and read(
        intermediate / "manual-launch-recovery.json"
    )
    assert read(HERE / "checks/shutdown.json")["pid_absent"]
    assert all(r["absent"] for r in read(HERE / "checks/owned-containers-removed.json"))
    preserved = read(HERE / "checks/preserved-services.json")
    assert len(preserved) == 4 and all(
        r["running"] and r["id"].startswith(r["original_id_prefix"]) for r in preserved
    )
    return {
        "evidence_verified": True,
        "source": git("rev-parse", SOURCE).decode().strip(),
        "checkpoints": 24,
        "cases": summary,
        "manifest_inputs": len(manifest),
        "production_changes": False,
        "scope": "one normal small file; one large file with real cancellation; no release/phone/cloud-provider claim",
    }


if __name__ == "__main__":
    print(json.dumps(verify(), ensure_ascii=False, indent=2))
