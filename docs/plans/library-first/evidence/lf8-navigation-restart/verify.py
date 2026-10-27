#!/usr/bin/env python3
"""Read-only checks of source isolation and three genuine native cold starts."""

import hashlib
import json
import struct
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SOURCE = "c994273"
BASE = "28656eb0"
STATES = [
    "nav-start",
    "nav-sort-menu",
    "nav-sort-selected",
    "nav-video-draft",
    "nav-pack-draft",
    "nav-library-video-preview",
    "nav-library-video-panel",
    "nav-library-video-panel-return",
    "nav-library-video-return",
    "nav-library-pack-reader",
    "nav-library-pack-panel",
    "nav-library-pack-panel-return",
    "nav-library-pack-return",
    "nav-tag-video-preview",
    "nav-tag-video-return",
    "nav-tag-pack-reader",
    "nav-tag-pack-return",
    "nav-recent-video-preview",
    "nav-recent-video-return",
    "nav-recent-pack-reader",
    "nav-recent-pack-return",
    "nav-library-isolation",
    "nav-stop-ready",
    "nav-cold-library",
    "nav-cold-tags",
    "nav-cold-recent-video",
    "nav-cold-recent-pack",
    "nav-cold-final-library",
]
PRODUCTION = [
    "apps/mobile/lib",
    "apps/mobile/android",
    "apps/mobile/assets",
    "services/server/video_viewer",
]


def read(path):
    return json.loads(path.read_text())


def git(*args, binary=False):
    result = subprocess.check_output(["git", *args], cwd=ROOT)
    return result if binary else result.decode().strip()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    manifest = read(HERE / "manifest.json")
    actual = {
        str(p.relative_to(HERE))
        for p in HERE.rglob("*")
        if p.is_file()
        and p.name not in {"manifest.json", "verification.json"}
        and "__pycache__" not in p.parts
    }
    assert actual == set(manifest)
    tracked = set(git("ls-files", str(HERE)).splitlines())
    assert {
        str((HERE / n).relative_to(ROOT)) for n in [*manifest, "manifest.json"]
    } <= tracked
    for name, expected in manifest.items():
        assert sha((HERE / name).read_bytes()) == expected, name
    source = git("rev-parse", SOURCE)
    scope = read(HERE / "checks/source-scope.json")
    assert source == scope["source"]
    assert not git(
        "diff", "--name-only", BASE, SOURCE, "--", *PRODUCTION, "apps/mobile/test"
    )
    assert (
        scope["tests_tree"]
        == git("rev-parse", "64588e7:apps/mobile/test")
        == git("rev-parse", "HEAD:apps/mobile/test")
    )
    expected_files = None
    report = {}
    for cold_source in ["library", "tags", "recent"]:
        p = HERE / cold_source
        result, provenance = read(p / "result.json"), read(p / "source.json")
        assert (
            result["passed"]
            and result["screens"] == STATES
            and result["cold_source"] == cold_source
        )
        assert (
            result["scenario"] == "navigation-restart"
            and result["window"] == [390, 844]
            and result["scale"] == "1"
        )
        assert (
            provenance["commit"] == source
            and provenance["prototype_tree"]
            == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
        )
        if expected_files is None:
            expected_files = provenance["files"]
            for name, value in expected_files.items():
                assert sha(git("show", source + ":" + name, binary=True)) == value
                assert sha((ROOT / name).read_bytes()) == value
        assert provenance["files"] == expected_files
        env = read(p / "environment.json")
        assert (
            env["avd"] == "video_viewer_api_36"
            and env["api"] == "36"
            and env["abi"] == "arm64-v8a"
        )
        assert env["host_avc_decoder"] == "2" and not env["renderer_override"]
        assert len(env["emulator_process"]) == 1 and all(
            flag in env["emulator_process"][0]
            for flag in [
                "-gpu software",
                "-feature -Vulkan",
                "-feature -GLDMA",
                "-feature HardwareDecoder",
            ]
        )
        restored = read(p / "restored-viewport.json")
        assert (
            not restored["errors"]
            and restored["before"] == restored["after"]
            and restored["font_before"] == restored["font_after"] == "1.0"
        )
        assert read(p / "prepared.json") == {"videos": 27, "packs": 27, "pages": 162}
        media = read(p / "media-before.json")
        assert len(media) == 189 and media == read(p / "media-after.json")
        metrics = read(p / "metrics.json")
        assert [m["state"] for m in metrics] == STATES
        by = {m["state"]: m for m in metrics}
        for m in metrics:
            state = m["state"]
            png = (p / (state + ".png")).read_bytes()
            assert png[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(
                ">II", png[16:24]
            ) == (1170, 2532)
            assert (
                m["physical"] == [1170, 2532] and m["dpr"] == 3 and m["text_scale"] == 1
            )
            assert m["cold_source"] == cold_source and not m["preload"]
            assert (
                "io.github.shijijs.video_viewer"
                in (p / (state + "-window.txt")).read_text()
            )
            if m["video"]:
                assert m["video"]["entry"] == m["video"]["loaded_entry"]
            if m["pack"]:
                assert m["pack"]["query"] == m["pack"]["loaded_query"]
        assert by["nav-sort-menu"]["video"]["entry"]["sort"] == "name"
        assert by["nav-sort-selected"]["video"]["entry"]["sort"] == "newest"
        assert (
            by["nav-video-draft"]["video"]["selecting"]
            and len(by["nav-video-draft"]["video"]["selected"]) == 1
        )
        assert (
            by["nav-pack-draft"]["pack"]["selecting"]
            and len(by["nav-pack-draft"]["pack"]["selected"]) == 1
        )
        original = read(p / "before-stop.json")
        assert (
            original["cold_source"] == cold_source and original["credential_available"]
        )
        assert original["video_tag"] != original["pack_tag"]
        assert (
            original["preferences"]["dark"]
            and not original["preferences"]["preloadAdjacent"]
        )
        assert original["preferences"]["videoOrder"] == "sequential"
        visits = original["visits"]
        assert [(v["kind"], v["source"]) for v in visits] == [
            ("video", "library"),
            ("pack", "library"),
            ("video", "tags"),
            ("pack", "tags"),
            ("video", "recent"),
            ("pack", "recent"),
        ]
        sql = read(p / "sql-before-stop.json")
        assert sql == read(p / "sql-after-resume.json")
        assert len(sql["playback_rounds"]) == 4 and len(sql["pack_sessions"]) == 3
        for i, visit in enumerate(visits):
            members = visit["members"]
            assert (
                len(members) == len(set(members))
                and members[visit["index"]] == visit["id"]
            )
            if i < 4:
                assert (
                    len(members) == 27 and visit["index"] == 25 and visit["scroll"] > 0
                )
            else:
                assert visit["index"] == 0 and visit["scroll"] == 0
            video = visit["kind"] == "video"
            rows = sorted(
                (
                    r
                    for r in sql["round_entries" if video else "pack_session_entries"]
                    if r["round_id" if video else "session_id"] == visit["range"]
                ),
                key=lambda r: r["ordinal"],
            )
            assert [r["video_id" if video else "pack_id"] for r in rows] == members
            parent = next(
                r
                for r in sql["playback_rounds" if video else "pack_sessions"]
                if r["id"] == visit["range"]
            )
            assert (
                parent["candidate_count"] == len(members)
                and parent["cursor"] == visit["index"]
                and parent["order"] == "sequential"
            )
            assert (
                parent["source"] if video else json.loads(parent["source"])["kind"]
            ) == visit["source"]
        cold = by["nav-cold-library"]["video"]
        assert cold["total"] == (1 if cold_source == "library" else 27)
        assert cold["entry"]["source"] == "library"
        assert cold["entry"]["search"] == (
            "导航视频 01" if cold_source == "library" else ""
        )
        assert cold["entry"]["query"]["tags"] == (
            [original["video_tag"]] if cold_source == "library" else []
        )
        assert cold["entry"]["sort"] == (
            "newest" if cold_source == "library" else "name"
        )
        for state in STATES[-5:]:
            assert (
                by[state]["dark"]
                and by[state]["reading"] is None
                and by[state]["round"] == original["playback"]["id"]
            )
        events = read(p / "restart-events.json")
        assert (
            len(events) == 2
            and events[0]["event"] == "force-stop"
            and events[0]["absent"]
        )
        assert (
            events[1]["event"] == "new-process"
            and events[0]["old_pid"] == events[1]["old_pid"]
        )
        assert (
            events[1]["old_pid"].isdigit()
            and events[1]["new_pid"].isdigit()
            and events[1]["old_pid"] != events[1]["new_pid"]
        )
        actions = read(p / "device-actions.json")
        assert len(actions) == 7 and all(
            a["command"] == ["input", "keyevent", "4"] for a in actions
        )
        requests = read(p / "requests.json")
        resumed = read(p / "resumed-requests.json")
        before = read(p / "requests-before-resume.json")
        assert requests == before + resumed
        assert resumed and all(r["method"] == "GET" for r in resumed)
        assert all(not r["path"].endswith("/stream") for r in resumed)
        assert len([r for r in requests if r["path"] == "/api/v1/auth/login"]) == 1
        assert (
            len(
                [
                    r
                    for r in requests
                    if r["method"] == "POST" and r["path"] == "/api/v1/rounds"
                ]
            )
            == 4
        )
        assert (
            len(
                [
                    r
                    for r in requests
                    if r["method"] == "POST" and r["path"] == "/api/v1/pack-sessions"
                ]
            )
            == 3
        )
        defaults = [
            r
            for r in requests
            if r["method"] == "PATCH" and r["path"] == "/api/v1/playback-defaults"
        ]
        assert (
            len(defaults) == 1
            and defaults[0]["body"]["order"] == "sequential"
            and defaults[0]["status"] == 200
        )
        catalogs = read(p / "catalog-sql.json")
        assert len(catalogs["videos"]) == len(catalogs["packs"]) == 27
        video_names = {r["id"]: r["name"] for r in catalogs["tags"]}
        pack_names = {r["id"]: r["name"] for r in catalogs["pack_tag_definitions"]}
        assert (
            video_names[original["video_tag"]]
            == pack_names[original["pack_tag"]]
            == "户外"
        )
        assert (
            len(catalogs["video_tags"]) == 54 and len(catalogs["pack_tag_links"]) == 67
        )
        assert len(sql["pack_progress"]) == 2 and len(sql["pack_preferences"]) == 1
        assert any(
            r["revision"] == 1 and r["updated_at"] == 1000 for r in sql["pack_progress"]
        )
        assert {
            r["video_id"] for r in sql["recent_entries"] if r["kind"] == "video"
        } == set(original["recent_video_ids"])
        assert {
            r["pack_id"] for r in sql["recent_entries"] if r["kind"] == "pack"
        } == set(original["recent_pack_ids"])
        phase0, phase1 = (
            (p / "phase-0.log").read_text(),
            (p / "phase-1.log").read_text(),
        )
        assert (
            "NAVIGATION_STOP_READY:" in phase0
            and "EXCEPTION CAUGHT" not in phase0.split("NAVIGATION_STOP_READY:", 1)[0]
        )
        assert (
            "NAVIGATION_NEW_PROCESS" in phase1
            and "NAVIGATION_RESTART_VERIFIED:" in phase1
            and "All tests passed!" in phase1
            and "EXCEPTION CAUGHT" not in phase1
        )
        report[cold_source] = {
            "points": len(metrics),
            "old_pid": events[1]["old_pid"],
            "new_pid": events[1]["new_pid"],
            "media": len(media),
            "sql_unchanged_after_restart": True,
        }
    assert "+25: All tests passed!" in (HERE / "checks/components.log").read_text()
    assert "No issues found!" in (HERE / "checks/analyze.log").read_text()
    assert "All checks passed!" in (HERE / "checks/ruff.log").read_text()
    after, shutdown = (
        read(HERE / "checks/environment-after.json"),
        read(HERE / "checks/shutdown.json"),
    )
    assert (
        after["size"] == "Physical size: 1080x2400"
        and after["density"] == "Physical density: 420"
        and after["font"] == "1.0"
    )
    assert shutdown["pid"] == after["pid"] and not shutdown["process_exists"]
    return {
        "passed": True,
        "source": source,
        "production_changed": False,
        "component_tests": 25,
        "manifest_files": len(manifest),
        "points": 84,
        "runs": report,
    }


if __name__ == "__main__":
    print(json.dumps(main(), ensure_ascii=False, indent=2))
