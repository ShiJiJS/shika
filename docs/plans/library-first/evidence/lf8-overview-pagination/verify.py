#!/usr/bin/env python3
"""Read-only evidence checks for bounded thumbnail capacity and real pagination."""

import hashlib
import json
import struct
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
PAGINATION_SOURCE = "26aceab"
REGRESSION_SOURCE = "56b2a74"
LEGACY_DRIVER = "apps/mobile/integration_test/server_thumbnail_recovery_test.dart"
STATES = [
    "pages-reader",
    "pages-held",
    "pages-next-pending",
    "pages-second",
    "pages-first-return",
    "pages-close-pending",
    "pages-cancelled",
    "pages-reopened",
    "pages-jump-list",
    "pages-jump",
    "pages-return",
]
SIX = [
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


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def run_checks(folder, states, source, media_count):
    runtime = read(folder / "source.json")
    assert runtime["commit"] == git("rev-parse", source)
    assert runtime["prototype_tree"] == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
    for path, digest in runtime["files"].items():
        if source == PAGINATION_SOURCE and path == LEGACY_DRIVER:
            assert git("show", source + ":" + path) != git(
                "show", REGRESSION_SOURCE + ":" + path
            )
        else:
            assert sha(ROOT / path) == digest, path
    result = read(folder / "result.json")
    assert result["passed"] and result["screens"] == states
    metrics = read(folder / "metrics.json")
    assert [row["state"] for row in metrics] == states
    assert result["window"] == [390, 844] and result["scale"] == "1"
    for state in states:
        assert struct.unpack(
            ">II", (folder / (state + ".png")).read_bytes()[16:24]
        ) == (1170, 2532)
        assert (
            "io.github.shijijs.video_viewer"
            in (folder / (state + "-window.txt")).read_text()
        )
    before = read(folder / "media-before.json")
    assert len(before) == media_count and before == read(folder / "media-after.json")
    restored = read(folder / "restored-viewport.json")
    assert (
        restored["before"] == restored["after"]
        and restored["font_before"] == restored["font_after"]
    )
    assert not restored["errors"]
    log = (folder / "flutter.log").read_text()
    assert "All tests passed!" in log and "PROTOTYPE_FIDELITY_VERIFIED" in log
    return metrics, read(folder / "requests.json"), read(folder / "fixture-final.json")


def verify():
    manifest = read(HERE / "manifest.json")
    for path, digest in manifest.items():
        assert sha(HERE / path) == digest, path
        assert git("ls-files", "--error-unmatch", str((HERE / path).relative_to(ROOT)))
    changed = git(
        "diff", "--name-only", PAGINATION_SOURCE, REGRESSION_SOURCE
    ).splitlines()
    assert [p for p in changed if not p.startswith("docs/")] == [LEGACY_DRIVER]
    assert git("rev-parse", PAGINATION_SOURCE + ":apps/mobile/lib") == git(
        "rev-parse", REGRESSION_SOURCE + ":apps/mobile/lib"
    )
    scope = read(HERE / "checks/source-scope.json")
    assert (
        scope["source"] == git("rev-parse", REGRESSION_SOURCE)
        and scope["component_tests"] == 24
    )
    for path, digest in scope["files"].items():
        assert sha(ROOT / path) == digest, path
    assert (
        "+24: All tests passed!" in (HERE / "checks/components-final.log").read_text()
    )
    assert "No issues found!" in (HERE / "checks/analyze.log").read_text()
    assert "0 changed" in (HERE / "checks/format.log").read_text()
    assert "All checks passed!" in (HERE / "checks/ruff.log").read_text()
    assert read(HERE / "checks/control-guard.json")["invalid_key_status"] == 403
    for n in [1, 2, 3]:
        folder = HERE / f"normal-{n}"
        metrics, requests, final = run_checks(folder, STATES, PAGINATION_SOURCE, 50)
        by = {row["state"]: row for row in metrics}
        for row in metrics[:-2]:
            assert (
                row["reading"]["index"] == 2 and row["reading"]["mode"] == "horizontal"
            )
        assert by["pages-jump"]["reading"]["index"] == 29
        assert (
            len({row["reading"]["range"] for row in metrics if "reading" in row}) == 1
        )
        for state in [
            "pages-held",
            "pages-next-pending",
            "pages-first-return",
            "pages-close-pending",
            "pages-reopened",
        ]:
            assert [c["ordinal"] for c in by[state]["overview_cells"]] == list(
                range(24)
            ), state
        for state in ["pages-second", "pages-jump-list"]:
            assert [c["ordinal"] for c in by[state]["overview_cells"]] == list(
                range(24, 30)
            ), state
        for state in ["pages-next-pending", "pages-close-pending"]:
            assert not any(c["active"] for c in by[state]["overview_cells"])
        old = {c["id"] for c in by["pages-held"]["overview_cells"]}
        last = [c["id"] for c in by["pages-second"]["overview_cells"]]
        assert old.isdisjoint(last)
        streams = final["thumbnail_streams"]
        assert len(streams) == 3 and all(s["cancelled"] for s in streams)
        events = final["manifest_events"]
        assert len(events) == 2 and all(e["offset"] == "24" for e in events)
        assert events[0]["released"] and not events[0]["cancelled"]
        assert events[1]["cancelled"] and not events[1]["released"]
        thumbs = [r for r in requests if r["path"].endswith("/thumbnail")]
        assert all(r["status"] == 200 for r in thumbs)
        assert len([r for r in thumbs if r["phase"] == "pages-reader"]) == 3
        assert not [
            r
            for r in thumbs
            if r["phase"]
            in {
                "pages-held",
                "pages-first-return",
                "pages-close-pending",
                "pages-device-back",
            }
        ]
        for phase, count in [
            ("pages-next-pending", 6),
            ("pages-second", 24),
            ("pages-cancelled", 24),
            ("pages-reopened", 30),
        ]:
            assert len([r for r in thumbs if r["phase"] == phase]) == count, (
                phase,
                count,
            )
        writes = [r for r in requests if r["method"] != "GET"]
        assert len(writes) == 4 and all(r["phase"] is None for r in writes[:3])
        assert (
            writes[-1]["phase"] == "pages-jump-list" and writes[-1]["method"] == "PATCH"
        )
        assert (
            writes[-1]["body"]["page_id"] == last[-1]
            and writes[-1]["body"]["completed"]
        )
        assert "PAGINATION_READING_UNCHANGED:" in (folder / "flutter.log").read_text()
        actions = read(folder / "device-actions.json")
        assert len(actions) == 1 and actions[0]["command"] == ["input", "keyevent", "4"]
    folder = HERE / "six-cell-regression"
    metrics, requests, final = run_checks(folder, SIX, REGRESSION_SOURCE, 26)
    streams = final["thumbnail_streams"]
    assert len(streams) == 3 and all(s["cancelled"] for s in streams)
    assert len([r for r in requests if r["method"] != "GET"]) == 3
    for phase, count in [
        ("thumb-reader", 6),
        ("thumb-auto-recovered", 6),
        ("thumb-bounded", 6),
        ("thumb-manual-recovered", 3),
        ("thumb-cancelled", 6),
    ]:
        grouped = {}
        for r in requests:
            if r["phase"] == phase and r["path"].endswith("/thumbnail"):
                grouped.setdefault(r["path"], []).append(r["status"])
        assert len(grouped) == count, (phase, grouped)
        if phase == "thumb-auto-recovered":
            assert all(v == [503, 503, 503] for v in grouped.values())
        elif phase == "thumb-reader":
            assert all(
                v[0] == 503 and v[-1] == 200 and len(v) <= 3 for v in grouped.values()
            )
        else:
            assert all(v == [200] for v in grouped.values())
    assert not [
        r
        for r in requests
        if r["phase"] in {"thumb-hold", "thumb-device-back"}
        and r["path"].endswith("/thumbnail")
    ]
    assert read(HERE / "checks/shutdown.json")["pid_absent"]
    return {
        "passed": True,
        "pagination_source": git("rev-parse", PAGINATION_SOURCE),
        "regression_source": git("rev-parse", REGRESSION_SOURCE),
        "production_equal": True,
        "component_tests": 24,
        "native_points": 41,
        "pagination_runs": 3,
        "media_per_pagination_run": 50,
        "cancelled_streams_per_run": 3,
        "cancelled_queued_cells_per_pagination_run": 21,
        "manifest_files": len(manifest),
    }


if __name__ == "__main__":
    print(json.dumps(verify(), ensure_ascii=False, indent=2))
