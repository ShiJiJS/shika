"""Read-only checks of this phase's pinned native evidence; run at repository root."""

import hashlib
import json
import struct
import subprocess
from pathlib import Path

root = Path.cwd()
evidence = Path(__file__).resolve().parent


def read(path):
    return json.loads(path.read_text())


def sha(data):
    return hashlib.sha256(data).hexdigest()


def source_check(metadata, current=True):
    for path, digest in metadata["files"].items():
        if current:
            assert sha((root / path).read_bytes()) == digest, path
        assert sha(subprocess.check_output(["git", "show", f"{metadata['commit']}:{path}"])) == digest, path


def image_check(base, size):
    pixels = base.with_suffix(".png").read_bytes()
    assert pixels[:8] == b"\x89PNG\r\n\x1a\n"
    assert struct.unpack(">II", pixels[16:24]) == tuple(v * 3 for v in size)
    focus = Path(str(base) + "-window.txt").read_text()
    assert "Application Not Responding" not in focus
    assert any("mCurrentFocus=" in line and "io.github.shijijs.video_viewer" in line
               for line in focus.splitlines())


def metrics_check(log, prefix, states, size, text13):
    assert "All tests passed!" in log and "Some tests failed" not in log
    metrics = [json.loads(line.split(prefix + ":", 1)[1])
               for line in log.splitlines() if prefix + ":" in line]
    assert [m["state"] for m in metrics] == states
    assert all(m["window"] == size and m["dpr"] == 3 and m["text13"] == text13 for m in metrics)
    assert all(len(m["viewPadding"]) == 4 for m in metrics)
    assert all(m["dark"] == m["state"].endswith("-dark") for m in metrics)
    assert next(m for m in metrics if m["state"].endswith("-keyboard"))["keyboard"] > 0


original_display = {"size": "Physical size: 1080x2400", "density": "Physical density: 420", "font_scale": "1.0"}
states = ["backup", "backup-cancel", "backup-saved", "restore-preview", "restore-keyboard", "backup-error",
          "pending", "detail", "list", "paged", "dark", "historical", "task-backup-saved"]
archive_states = ["backup-start", "backup-dark", "restore-first-page", "restore-keyboard", "restore-confirm-off",
                  "backup-restore-point", "snapshot-preview", "snapshot-confirm-off"]
source = read(evidence / "source.json")
archive_source = read(evidence / "archive-source.json")
assert all(archive_source["files"][p] == digest for p, digest in source["files"].items()
           if p in archive_source["files"]), "Production and shared harness bytes must match"
proof = []
for profile, size, text13 in [("normal", [390, 844], 13), ("large", [360, 740], 26), ("landscape", [844, 390], 13)]:
    folder = evidence / profile
    assert read(folder / "source.json") == source
    events = read(folder / "lf8-management-host-events.json")
    assert not events["errors"]
    assert [e["phase"] for e in events["events"] if e["phase"].startswith("management-")] == ["management-" + s for s in states]
    log = (folder / "lf8-management-android-test.log").read_text()
    metrics_check(log, "MANAGEMENT_METRICS", ["management-" + s for s in states], size, text13)
    assert "MANAGEMENT_VERIFIED:27 pack tasks, one original receipt GET, two original backup downloads, zero task-phase POST, 81 source hashes preserved" in log
    traces = {}
    hashes = None
    for index, state in enumerate(states):
        base = folder / ("lf8-management-management-" + state)
        image_check(base, size)
        files = read(Path(str(base) + "-files.json"))["hashes"]
        if index < 6:
            assert files == {}, "Public pack fixture is seeded after the backup preview phase"
        else:
            if hashes is None:
                hashes = files
                assert len(files) == 81
            assert files == hashes
        traces[state] = read(Path(str(base) + "-requests.json"))["items"]
    backup_writes = [e for e in traces["backup-error"] if e["method"] == "POST"]
    assert sum(e["path"] == "/api/v1/backups" for e in backup_writes) == 2
    assert sum(e["path"] == "/api/v1/backup-imports" for e in backup_writes) == 1
    assert not any("restore" in e["path"] for e in backup_writes)
    trace = traces["task-backup-saved"]
    assert all(e["method"] == "GET" and e["authenticated"] for e in trace)
    receipts = [e for e in trace if e["path"].startswith("/api/v1/pack-file-requests/")]
    assert len(receipts) == 1 and receipts[0]["path"].endswith("native-tasks-unknown") and receipts[0]["status"] == 200
    downloads = [e for e in trace if e["path"].startswith("/api/v1/backups/") and e["path"].endswith("/download")]
    assert len(downloads) == 2 and downloads[0]["path"] == downloads[1]["path"]
    assert all(e["status"] == 200 for e in downloads)
    assert any(e["path"] == "/api/v1/maintenance-tasks" and e["query"].get("offset") == "24"
               and e["query"].get("family") == "pack" for e in trace)
    assert read(folder / "restored-viewport.json") == {"before": original_display, "after": original_display}

    archive = evidence / "archive" / profile
    assert read(archive / "source.json") == archive_source
    log = (archive / "android-test.log").read_text()
    metrics_check(log, "ARCHIVE_UI_METRICS", ["archive-ui-" + s for s in archive_states], size, text13)
    marker = next(json.loads(line.split("ARCHIVE_UI_VERIFIED:", 1)[1]) for line in log.splitlines() if "ARCHIVE_UI_VERIFIED:" in line)
    assert marker["roots"] == 27 and marker["epoch_changed"] and marker["replacement_removed_late_tags"]
    assert marker["snapshot_not_confirmed"] and marker["snapshot"] and marker["restore_task"]
    assert marker["kind"] == "backup_restore_v2" and marker["state"] == "completed"
    events = read(archive / "host-events.json")
    assert not events["errors"]
    assert [e["state"] for e in events["events"]] == ["archive-ui-" + s for s in archive_states]
    epochs = [e["epoch"] for e in events["events"]]
    assert len(set(epochs[:5])) == len(set(epochs[5:])) == 1 and epochs[0] != epochs[-1]
    media = read(archive / "media-before.json")
    assert len(media) >= 2 and read(archive / "media-after.json") == media
    for state in archive_states:
        base = archive / ("archive-ui-" + state)
        image_check(base, size)
        assert read(Path(str(base) + "-media.json")) == media
    trace = read(archive / "requests.json")["items"]
    writes = [e for e in trace if e["method"] == "POST"]
    for path in ["/api/v1/management-backups", "/api/v1/management-backups/imports", "/api/v1/management-backups/restores", "/api/v1/management-backups/from-snapshot/" + marker["snapshot"]]:
        assert sum(e["path"] == path for e in writes) == 1, path
    assert read(archive / "restored-viewport.json") == {"before": original_display, "after": original_display}
    assert read(archive / "result.json")["passed"]
    proof.append({"profile": profile, "v1_task_points": 13, "archive_points": 8, "source_images_preserved": 81})

for metadata in [source, archive_source, read(evidence / "checks/source.json"), read(evidence / "checks/analysis-source.json")]:
    source_check(metadata)
assert source["prototype_tree"] == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
assert subprocess.check_output(["git", "rev-parse", "HEAD:design/reference/library-first"], text=True).strip() == source["prototype_tree"]
for item in read(evidence / "reference/source-sha256.json")["files"]:
    assert sha((root / "design/reference/library-first" / item["path"]).read_bytes()) == item["sha256"]
for index in [1, 2, 3]:
    assert "+37: All tests passed!" in (evidence / f"checks/targeted-{index}.log").read_text()
assert "No issues found!" in (evidence / "checks/analyze.log").read_text()
assert "All checks passed!" in (evidence / "checks/ruff.log").read_text()
assert "0 changed" in (evidence / "checks/format.log").read_text()
for name in ["baseline-backup-before", "baseline-task-body-before", "intermediate-before-review-fixes", "intermediate-archive-normal-before-wait-fix",
             "diagnostics/archive-large-paging-wait"]:
    source_check(read(evidence / name / "source.json"), current=False)
baseline_log = (evidence / "baseline-backup-before/lf8-management-android-test.log").read_text()
assert "Some tests failed" in baseline_log
assert len(list((evidence / "baseline-backup-before").glob("*.png"))) == 6
assert "All tests passed!" in (evidence / "baseline-task-body-before/lf8-management-android-test.log").read_text()
manifest = read(evidence / "manifest.json")
actual = {str(p.relative_to(evidence)) for p in evidence.rglob("*") if p.is_file() and p.name not in {"manifest.json", "verification.json"}}
assert set(manifest) == actual
assert all(sha((evidence / p).read_bytes()) == digest for p, digest in manifest.items())
print(json.dumps({"verified": True, "source": source["commit"], "inputs": len(manifest), "native_checkpoints": 63,
                  "baseline_backup_partial_only": True, "profiles": proof}, ensure_ascii=False, indent=2))
