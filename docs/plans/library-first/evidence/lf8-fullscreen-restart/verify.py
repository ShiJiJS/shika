#!/usr/bin/env python3
"""Read-only evidence audit of exact video identity and active content restart."""

import hashlib
import json
import struct
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SOURCE = "f6a565e"
BASE = "9c599afd"
DIAGNOSTIC = "fb663a6"
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
SOURCE_HASHES = {}


def read(path):
    return json.loads(path.read_text())


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).strip()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def events(folder, marker):
    return [
        json.loads(line.split(marker, 1)[1])
        for line in (folder / "flutter.log").read_text().splitlines()
        if marker in line
    ]


def source_check(folder, source):
    metadata = read(folder / "source.json")
    assert metadata["commit"] == git("rev-parse", source).decode()
    assert metadata["prototype_tree"] == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
    for path, sha in metadata["files"].items():
        key = (source, path)
        if key not in SOURCE_HASHES:
            SOURCE_HASHES[key] = digest(
                subprocess.check_output(["git", "show", source + ":" + path], cwd=ROOT)
            )
        assert SOURCE_HASHES[key] == sha, path


def verify():
    manifest = read(HERE / "manifest.json")
    for path, sha in manifest.items():
        assert digest((HERE / path).read_bytes()) == sha, path
        assert git("ls-files", "--error-unmatch", str((HERE / path).relative_to(ROOT)))
    for tree in (
        "apps/mobile/lib",
        "apps/mobile/android",
        "apps/mobile/test",
        "services/server/video_viewer",
    ):
        assert git("rev-parse", BASE + ":" + tree) == git(
            "rev-parse", SOURCE + ":" + tree
        )
    changes = git("diff", "--name-only", BASE, SOURCE).decode().splitlines()
    assert [p for p in changes if not p.startswith("docs/")] == [DRIVER]
    assert "No issues found!" in (HERE / "checks/analyze-final.log").read_text()
    assert "0 changed" in (HERE / "checks/format-final.log").read_text()
    assert "All checks passed!" in (HERE / "checks/ruff.log").read_text()
    assert "+4: All tests passed!" in (HERE / "checks/player-checks.log").read_text()

    diagnostic = HERE / "diagnostics/reveal-moves-video"
    source_check(diagnostic, DIAGNOSTIC)
    before = next(
        e for e in events(diagnostic, "CONTENT_TAP_BEFORE:") if "暂停" in e["target"]
    )
    revealed = next(
        e for e in events(diagnostic, "CONTENT_TAP_REVEALED:") if "暂停" in e["target"]
    )
    assert before["hittable"] == 1 and before["page"] == 0
    assert revealed["page"] > 0.8 and before["video"] == revealed["video"]
    assert "Bad state: No element" in (diagnostic / "flutter.log").read_text()
    assert read(diagnostic / "phase-0-exit.json")["code"] != 0
    assert any(
        r["method"] == "PATCH" and r["path"].endswith("/position")
        for r in read(diagnostic / "requests.json")
    )
    assert not (diagnostic / "result.json").exists()
    crash = HERE / "diagnostics/emulator-exit"
    source_check(crash, SOURCE)
    assert (
        "detected a hanging thread 'QEMU2 main loop'"
        in (crash / "emulator.log").read_text()
    )
    assert not (crash / "result.json").exists()
    ownership = read(crash / "emulator-crash.json")
    assert ownership["launcher_pid_absent"] and ownership["qemu_log_pid_absent"]
    recovered = read(HERE / "checks/recovered-display.json")
    assert recovered["after"] == recovered["original"]["display"]
    assert recovered["font_after"] == recovered["original"]["font"]

    summary = {}
    for case in ("fullscreen", "video", "reader"):
        folder = HERE / case
        source_check(folder, SOURCE)
        result = read(folder / "result.json")
        assert result["passed"] and result["screens"] == STATES
        assert result["window"] == [390, 844] and result["scale"] == "1"
        metrics = read(folder / "metrics.json")
        assert [m["state"] for m in metrics] == STATES
        by = {m["state"]: m for m in metrics}
        for state in STATES:
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
            assert row["reading"] is None and not row["players"]
            assert row["preload"] is False
        restart = read(folder / "restart-events.json")
        assert (
            len(restart) == 2
            and restart[0]["event"] == "force-stop"
            and restart[0]["absent"]
        )
        assert (
            restart[1]["event"] == "new-process"
            and restart[0]["old_pid"] == restart[1]["old_pid"] != restart[1]["new_pid"]
        )
        assert read(folder / "phase-0-exit.json")["intentional_force_stop"]
        assert read(folder / "phase-1-exit.json") == {
            "code": 0,
            "intentional_force_stop": False,
        }
        sql = read(folder / "sql-after-stop.json")
        assert set(sql) == TABLES and sql == read(folder / "sql-after-readonly.json")
        prefix = read(folder / "requests-before-resume.json")
        boundary = read(folder / "requests-readonly-boundary.json")
        assert boundary[: len(prefix)] == prefix
        readonly = boundary[len(prefix) :]
        assert readonly == read(folder / "resumed-requests-readonly.json") and readonly
        assert all(
            r["method"] == "GET" and not r["path"].endswith(("/stream", "/image"))
            for r in readonly
        )
        original = read(folder / "before-stop.json")
        old, new = by["content-stop-ready"], by["content-reopened"]
        after = read(folder / "sql-after-reopen.json")
        if case == "reader":
            for key in ("page", "index", "mode"):
                assert old["reading"][key] == new["reading"][key] == original[key]
            assert new["reading"]["mode"] == "vertical" and new["reading"]["index"] >= 3
            assert abs(new["reading"]["ratio"] - original["ratio"]) <= 0.01
            assert len(new["reading"]["geometry"]) == len(original["geometry"]) == 4
            assert all(
                abs(a - b) <= 2
                for a, b in zip(new["reading"]["geometry"], original["geometry"])
            )
            assert (
                new["reading"]["decoded"] > 0
                and new["reading"]["range"] != old["reading"]["range"]
            )
            assert (
                len(sql["recent_entries"]) == 1
                and sql["recent_entries"][0]["pack_id"] == original["pack_id"]
            )
            assert len(after["pack_sessions"]) == len(sql["pack_sessions"]) + 1
        else:
            assert original["playback"]["current"]["id"] == original["video_id"]
            for row in (old, new):
                assert row["current_video"] == original["video_id"]
                (player,) = row["players"]
                assert player["initialized"] and player["playing"] and player["looping"]
                assert player["position_ms"] > 100 and player["source"].endswith(
                    "/" + original["video_id"] + "/stream"
                )
            assert old["range"] == original["range"] != new["range"]
            assert old["fullscreen"] == (case == "fullscreen") and not new["fullscreen"]
            assert (
                len(sql["recent_entries"]) == 1
                and sql["recent_entries"][0]["video_id"] == original["video_id"]
            )
            assert len(after["playback_rounds"]) == len(sql["playback_rounds"]) + 1
            frames = read(folder / "video-frames.json")
            assert set(frames) == {"content-stop-ready", "content-reopened"}
            assert all(
                f["longest_green_run"] == 0 and f["sampled_distinct_colors"] > 1000
                for f in frames.values()
            )
            if case == "fullscreen":
                identities = events(folder, "CONTENT_VIDEO_IDENTITY:")
                assert [e["step"] for e in identities] == [
                    "initial-playing",
                    "paused-before-rotation",
                    "fullscreen-paused",
                ]
                assert all(
                    e["video_id"] == e["current_video"] == original["video_id"]
                    and e["looping"]
                    for e in identities
                )
                pause = next(
                    e
                    for e in events(folder, "CONTENT_TAP_REVEALED:")
                    if "暂停" in e["target"]
                )
                assert pause["hittable"] == 1 and pause["page"] == 0
                assert (
                    original["playback"]["position"] == 0
                    and original["recent"]["total"] == 1
                )
                assert not any(
                    r["method"] == "PATCH" and r["path"].endswith("/position")
                    for r in prefix
                )
        media = read(folder / "media-before.json")
        assert len(media) == 26 and media == read(folder / "media-after.json")
        restore = read(folder / "restored-viewport.json")
        assert restore["before"] == restore["after"] and not restore["errors"]
        assert restore["font_before"] == restore["font_after"]
        assert "All tests passed!" in (folder / "phase-1.log").read_text()
        summary[case] = {
            "checkpoints": 7,
            "new_pid": restart[1]["new_pid"],
            "readonly_requests": len(readonly),
        }
    assert read(HERE / "checks/shutdown.json")["pid_absent"]
    return {
        "evidence_verified": True,
        "source": git("rev-parse", SOURCE).decode(),
        "checkpoints": 21,
        "cases": summary,
        "manifest_inputs": len(manifest),
        "production_changes": False,
        "scope": "one run per case; full app/release/NAS acceptance still open",
    }


if __name__ == "__main__":
    print(json.dumps(verify(), ensure_ascii=False, indent=2))
