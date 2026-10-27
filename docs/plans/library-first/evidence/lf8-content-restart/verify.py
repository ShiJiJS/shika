#!/usr/bin/env python3
"""Read-only audit of owned active-content force-stop and explicit reopen."""

import hashlib
import json
import struct
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SOURCE = "395bf7c"
FIRST_SOURCE = "434278a"
DRIVER = "apps/mobile/integration_test/server_content_restart_test.dart"
STATES = [
    "content-start",
    "content-stop-ready",
    "content-cold-library",
    "content-cold-recent",
    "content-readonly-complete",
    "content-reopened",
    "content-return",
]
TABLES = {
    "playback_rounds",
    "round_entries",
    "recent_entries",
    "pack_sessions",
    "pack_session_entries",
    "pack_progress",
    "pack_preferences",
}


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def verify():
    manifest = read(HERE / "manifest.json")
    for path, digest in manifest.items():
        assert sha(HERE / path) == digest, path
        assert git("ls-files", "--error-unmatch", str((HERE / path).relative_to(ROOT)))
    scope = read(HERE / "checks/source-scope.json")
    assert scope["source"] == git("rev-parse", SOURCE)
    assert git("diff", "--name-only", FIRST_SOURCE, SOURCE).splitlines() == [DRIVER]
    assert git("rev-parse", FIRST_SOURCE + ":apps/mobile/lib") == git(
        "rev-parse", SOURCE + ":apps/mobile/lib"
    )
    assert scope["component_tests"] == 18
    for path, digest in scope["files"].items():
        assert sha(ROOT / path) == digest, path
    assert "+18: All tests passed!" in (HERE / "checks/components.log").read_text()
    assert "No issues found!" in (HERE / "checks/analyze.log").read_text()
    assert "0 changed" in (HERE / "checks/format.log").read_text()
    assert "All checks passed!" in (HERE / "checks/ruff.log").read_text()
    summary = {}
    for case in ("reader", "video"):
        folder = HERE / case
        source = read(folder / "source.json")
        case_source = SOURCE if case == "fullscreen" else FIRST_SOURCE
        assert source["commit"] == git("rev-parse", case_source)
        assert source["prototype_tree"] == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
        for path, digest in source["files"].items():
            if case_source == FIRST_SOURCE and path == DRIVER:
                original = subprocess.check_output(
                    ["git", "show", case_source + ":" + path], cwd=ROOT
                )
                assert hashlib.sha256(original).hexdigest() == digest
            else:
                assert sha(ROOT / path) == digest, path
        result = read(folder / "result.json")
        assert result["passed"] and result["screens"] == STATES
        assert result["window"] == [390, 844] and result["scale"] == "1"
        rows = read(folder / "metrics.json")
        assert [r["state"] for r in rows] == STATES
        by = {r["state"]: r for r in rows}
        for row in rows:
            state = row["state"]
            assert row["case"] == case and row["preload"] is False
            expected = (
                (2532, 1170)
                if case == "fullscreen" and state == "content-stop-ready"
                else (1170, 2532)
            )
            assert (
                struct.unpack(">II", (folder / (state + ".png")).read_bytes()[16:24])
                == expected
            )
            assert (
                "io.github.shijijs.video_viewer"
                in (folder / (state + "-window.txt")).read_text()
            )
        for state in STATES[2:5]:
            row = by[state]
            assert not row["fullscreen"] and not row["movie_visible"]
            assert not row["players"] and row["reading"] is None
        events = read(folder / "restart-events.json")
        assert len(events) == 2
        assert events[0]["event"] == "force-stop" and events[0]["absent"]
        assert events[0]["case"] == case
        assert events[1]["event"] == "new-process"
        assert events[0]["old_pid"] == events[1]["old_pid"] != events[1]["new_pid"]
        assert read(folder / "phase-0-exit.json")["intentional_force_stop"]
        assert read(folder / "phase-1-exit.json") == {
            "code": 0,
            "intentional_force_stop": False,
        }
        sql = read(folder / "sql-after-stop.json")
        assert set(sql) == TABLES and sql == read(folder / "sql-after-readonly.json")
        prefix = read(folder / "requests-before-resume.json")
        all_requests = read(folder / "requests-readonly-boundary.json")
        assert all_requests[: len(prefix)] == prefix
        resumed = all_requests[len(prefix) :]
        assert resumed == read(folder / "resumed-requests-readonly.json") and resumed
        assert all(
            r["method"] == "GET" and not r["path"].endswith(("/stream", "/image"))
            for r in resumed
        )
        original = read(folder / "before-stop.json")
        assert original["case"] == case and original["credential_available"]
        old, new = by["content-stop-ready"], by["content-reopened"]
        after = read(folder / "sql-after-reopen.json")
        if case == "reader":
            assert old["reading"]["range"] != new["reading"]["range"]
            for key in ("page", "index", "mode"):
                assert old["reading"][key] == new["reading"][key] == original[key]
            assert new["reading"]["index"] == 3 and new["reading"]["mode"] == "vertical"
            assert abs(new["reading"]["ratio"] - original["ratio"]) <= 0.01
            assert len(new["reading"]["geometry"]) == len(original["geometry"]) == 4
            assert all(
                abs(a - b) <= 2
                for a, b in zip(new["reading"]["geometry"], original["geometry"])
            )
            assert new["reading"]["decoded"] > 0
            assert (
                len(sql["recent_entries"]) == 1
                and sql["recent_entries"][0]["pack_id"] == original["pack_id"]
            )
            assert len(sql["pack_progress"]) == len(after["pack_progress"]) == 1
            for key in (
                "pack_id",
                "page_id",
                "offset_ratio",
                "completed",
                "content_version",
                "recovery_reason",
            ):
                assert sql["pack_progress"][0][key] == after["pack_progress"][0][key]
            assert (
                after["pack_progress"][0]["revision"]
                == sql["pack_progress"][0]["revision"] + 1
            )
            assert sql["pack_preferences"] == after["pack_preferences"]
            assert len(after["pack_sessions"]) == len(sql["pack_sessions"]) + 1
        else:
            for row in (old, new):
                assert len(row["players"]) == 1 and row["players"][0]["playing"]
                assert (
                    row["players"][0]["initialized"]
                    and row["players"][0]["position_ms"] > 100
                )
                assert row["current_video"] == original["video_id"]
            assert old["fullscreen"] == (case == "fullscreen") and not new["fullscreen"]
            assert old["range"] == original["range"] != new["range"]
            assert (
                len(sql["recent_entries"]) == 1
                and sql["recent_entries"][0]["video_id"] == original["video_id"]
            )
            frames = read(folder / "video-frames.json")
            assert set(frames) == {"content-stop-ready", "content-reopened"}
            assert all(
                f["longest_green_run"] == 0 and f["sampled_distinct_colors"] > 1000
                for f in frames.values()
            )
            assert len(after["playback_rounds"]) == len(sql["playback_rounds"]) + 1
        media = read(folder / "media-before.json")
        assert len(media) == 26 and media == read(folder / "media-after.json")
        restored = read(folder / "restored-viewport.json")
        assert restored["before"] == restored["after"] and not restored["errors"]
        assert restored["font_before"] == restored["font_after"]
        log = (folder / "flutter.log").read_text()
        assert "All tests passed!" in log and "CONTENT_RESTART_VERIFIED" in log
        assert "PROTOTYPE_FIDELITY_VERIFIED" in log
        summary[case] = {
            "checkpoints": 7,
            "new_pid": events[1]["new_pid"],
            "readonly_requests": len(resumed),
            "tables_equal": 7,
        }
    diagnostic = HERE / "diagnostics/independent-kind-driver"
    assert (
        "Content restart timeout: pack library"
        in (diagnostic / "flutter.log").read_text()
    )
    assert not (diagnostic / "result.json").exists()
    advanced = HERE / "diagnostics/short-clip-advanced"
    verdict = read(advanced / "review-verdict.json")
    assert not verdict["accepted"] and verdict["raw_runner_passed"]
    assert verdict["requested_video_id"] != verdict["captured_video_id"]
    guarded = HERE / "diagnostics/short-clip-identity-guard"
    assert not (guarded / "result.json").exists()
    assert "Expected:" in (guarded / "flutter.log").read_text()
    assert "line 443" in (guarded / "flutter.log").read_text()
    assert read(guarded / "phase-0-exit.json")["code"] != 0
    assert read(HERE / "checks/shutdown.json")["pid_absent"]
    return {
        "evidence_verified": True,
        "stage_acceptance": "partial; fullscreen pending",
        "source": git("rev-parse", SOURCE),
        "cases": summary,
        "accepted_checkpoints": 14,
        "component_tests": 18,
        "manifest_inputs": len(manifest),
        "scope": "reader/video each one two-process run; fullscreen diagnostics excluded; no release or target-device claim",
    }


if __name__ == "__main__":
    print(json.dumps(verify(), ensure_ascii=False, indent=2))
