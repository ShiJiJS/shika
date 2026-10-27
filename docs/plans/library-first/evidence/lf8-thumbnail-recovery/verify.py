#!/usr/bin/env python3
"""Read-only checks of thumbnail recovery, bounded requests and cancellation."""

import hashlib
import json
import struct
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SOURCE = "7dbf3fd"
STATES = [
    "thumb-reader",
    "thumb-auto-recovered",
    "thumb-bounded",
    "thumb-manual-recovered",
    "thumb-hold",
    "thumb-cancelled",
    "thumb-reopened",
    "thumb-return",
]


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify():
    manifest = read(HERE / "manifest.json")
    for name, digest in manifest.items():
        path = HERE / name
        assert sha(path) == digest, name
        subprocess.check_call(
            ["git", "ls-files", "--error-unmatch", str(path.relative_to(ROOT))],
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
        )
    native = HERE / "native"
    source = read(native / "source.json")
    full_source = subprocess.check_output(
        ["git", "rev-parse", SOURCE], cwd=ROOT, text=True
    ).strip()
    assert source["commit"] == full_source
    assert source["prototype_tree"] == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
    for path, digest in source["files"].items():
        assert sha(ROOT / path) == digest, path
    scope = read(HERE / "checks/source-scope.json")
    assert scope["source"] == full_source and scope["component_tests"] == 22
    for path, digest in scope["files"].items():
        assert sha(ROOT / path) == digest, path
    result = read(native / "result.json")
    assert result["passed"] and result["screens"] == STATES
    assert result["window"] == [390, 844] and result["scale"] == "1"
    metrics = read(native / "metrics.json")
    assert [row["state"] for row in metrics] == STATES
    reading = [row["reading"] for row in metrics if "reading" in row]
    for key in ["range", "pack", "index", "page_id", "mode"]:
        assert len({row[key] for row in reading}) == 1, key
    panels = [
        row["keys"]["reader-overview-sheet"]
        for row in metrics
        if "reader-overview-sheet" in row["keys"]
    ]
    assert len(panels) == 5
    assert all(panel == panels[0] for panel in panels)
    for state in STATES:
        assert struct.unpack(
            ">II", (native / (state + ".png")).read_bytes()[16:24]
        ) == (1170, 2532)
        assert (
            "io.github.shijijs.video_viewer"
            in (native / (state + "-window.txt")).read_text()
        )
    before = read(native / "media-before.json")
    assert len(before) == 26 and before == read(native / "media-after.json")
    final = read(native / "fixture-final.json")
    streams = final["thumbnail_streams"]
    assert len(streams) == 6 and all(row["cancelled"] for row in streams)
    requests = read(native / "requests.json")
    thumbs = [row for row in requests if row["path"].endswith("/thumbnail")]

    def group(phase):
        result = {}
        for row in thumbs:
            if row["phase"] == phase:
                result.setdefault(row["path"], []).append(row["status"])
        assert len(result) == 6, (phase, result)
        return result

    auto = group("thumb-reader")
    assert all(
        statuses[0] == 503 and statuses[-1] == 200 and 2 <= len(statuses) <= 3
        for statuses in auto.values()
    )
    assert all(
        statuses == [503] * 3 for statuses in group("thumb-auto-recovered").values()
    )
    assert all(statuses == [200] for statuses in group("thumb-bounded").values())
    assert all(
        statuses == [200] for statuses in group("thumb-manual-recovered").values()
    )
    assert all(
        statuses[-1] == 200 and len(statuses) <= 3
        for statuses in group("thumb-cancelled").values()
    )
    assert not [
        row for row in thumbs if row["phase"] in {"thumb-hold", "thumb-device-back"}
    ]
    writes = [row for row in requests if row["method"] != "GET"]
    assert len(writes) == 3 and all(row["phase"] is None for row in writes), writes
    actions = read(native / "device-actions.json")
    assert len(actions) == 1 and actions[0]["command"] == ["input", "keyevent", "4"]
    log = (native / "flutter.log").read_text()
    assert "THUMBNAIL_READING_UNCHANGED:" in log and "All tests passed!" in log
    assert "PROTOTYPE_FIDELITY_VERIFIED" in log
    assert (
        "+22: All tests passed!" in (HERE / "checks/components-final.log").read_text()
    )
    assert "No issues found!" in (HERE / "checks/analyze-final.log").read_text()
    assert "0 changed" in (HERE / "checks/format.log").read_text()
    assert "All checks passed!" in (HERE / "checks/ruff.log").read_text()
    restored = read(native / "restored-viewport.json")
    assert (
        restored["before"] == restored["after"]
        and restored["font_before"] == restored["font_after"]
    )
    assert not restored["errors"]
    assert read(HERE / "checks/shutdown.json")["pid_absent"]
    return {
        "passed": True,
        "source": full_source,
        "component_tests": 22,
        "native_points": 8,
        "cancelled_streams": 6,
        "source_media_unchanged": 26,
        "manifest_files": len(manifest),
        "automatic_attempt_counts": sorted(len(statuses) for statuses in auto.values()),
        "overview_writes": 0,
    }


if __name__ == "__main__":
    print(json.dumps(verify(), ensure_ascii=False, indent=2))
