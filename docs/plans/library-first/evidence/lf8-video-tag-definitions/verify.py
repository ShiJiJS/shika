#!/usr/bin/env python3
"""Read-only checks for the frozen native video tag definition evidence."""

import hashlib
import json
import struct
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SOURCE = "6f7ce97"
BASE = "0da68b82"
SUPPLEMENT = "68ce0fb"
KEYBOARD = "a40dc0f"
DRIVER = "apps/mobile/integration_test/server_video_tag_definitions_test.dart"
STATES = [
    "tagdef-video",
    "tagdef-create-keyboard",
    "tagdef-create-conflict",
    "tagdef-created",
    "tagdef-rename-conflict",
    "tagdef-rename-failure",
    "tagdef-renamed",
    "tagdef-pack",
    "tagdef-remove-confirm",
    "tagdef-remove-cancel",
    "tagdef-remove-failure",
    "tagdef-removed",
    "tagdef-reopened",
    "tagdef-pack-final",
    "tagdef-library",
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
    value = subprocess.check_output(["git", *args], cwd=ROOT)
    return value if binary else value.decode().strip()


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
    assert scope["source"] == source
    assert (
        scope["tests_tree"]
        == git("rev-parse", SOURCE + ":apps/mobile/test")
        == git("rev-parse", "HEAD:apps/mobile/test")
    )
    assert git("diff", "--name-only", BASE, SOURCE, "--", *PRODUCTION).splitlines() == [
        "apps/mobile/lib/features/library/tag_catalog_page.dart"
    ]
    supplement = git("rev-parse", SUPPLEMENT)
    keyboard = git("rev-parse", KEYBOARD)
    assert scope["supplement"] == supplement and scope["keyboard_driver"] == keyboard
    assert not git(
        "diff", "--name-only", SOURCE, KEYBOARD, "--", *PRODUCTION, "apps/mobile/test"
    )
    assert not git(
        "diff", "--name-only", SOURCE, SUPPLEMENT, "--", *PRODUCTION, "apps/mobile/test"
    )
    expected_files = None
    checked_commits = set()
    report = {}
    fixture_packs = read(HERE / "checks/public-packs.json")
    for label, window, scale in [
        ("normal-1", [390, 844], "1"),
        ("normal-2", [390, 844], "1"),
        ("normal-3", [390, 844], "1"),
        ("large", [360, 740], "2"),
        ("landscape", [844, 390], "1"),
    ]:
        p = HERE / label
        result, provenance = read(p / "result.json"), read(p / "source.json")
        assert result["passed"] and result["screens"] == STATES
        assert (
            result["scenario"] == "video-tag-definitions"
            and result["window"] == window
            and result["scale"] == scale
        )
        producer = (
            source
            if label.startswith("normal-")
            else supplement
            if label == "large"
            else keyboard
        )
        assert (
            provenance["commit"] == producer
            and provenance["prototype_tree"]
            == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
        )
        if expected_files is None:
            expected_files = provenance["files"]
        if producer not in checked_commits:
            for name, value in provenance["files"].items():
                assert sha(git("show", producer + ":" + name, binary=True)) == value
                if name != DRIVER or producer == keyboard:
                    assert sha((ROOT / name).read_bytes()) == value
            checked_commits.add(producer)
        assert {k: v for k, v in provenance["files"].items() if k != DRIVER} == {
            k: v for k, v in expected_files.items() if k != DRIVER
        }
        env = read(p / "environment.json")
        assert (
            env["avd"] == "video_viewer_api_36"
            and env["api"] == "36"
            and env["abi"] == "arm64-v8a"
        )
        assert env["host_avc_decoder"] == "2" and not env["renderer_override"]
        assert len(env["emulator_process"]) == 1
        assert all(
            s in env["emulator_process"][0]
            for s in [
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
        assert read(p / "control-guard.json") == {
            "invalid_key_status": 403,
            "mode_after": "off",
        }
        media = read(p / "media-before.json")
        assert len(media) == 26 and media == read(p / "media-after.json")
        metrics = read(p / "metrics.json")
        assert [m["state"] for m in metrics] == STATES
        by = {m["state"]: m for m in metrics}
        for m in metrics:
            state = m["state"]
            png = (p / (state + ".png")).read_bytes()
            assert png[:8] == b"\x89PNG\r\n\x1a\n" and list(
                struct.unpack(">II", png[16:24])
            ) == [v * 3 for v in window]
            assert (
                m["physical"] == [v * 3 for v in window]
                and m["dpr"] == 3
                and m["text_scale"] == float(scale)
            )
            assert (
                "io.github.shijijs.video_viewer"
                in (p / (state + "-window.txt")).read_text()
            )
            assert not m["saving"]
        assert by["tagdef-create-keyboard"]["keyboard"] > 0
        if label == "landscape":
            x, y, w, h = by["tagdef-create-keyboard"]["boxes"]["tag-editable"]
            assert (
                y >= 0 and y + h <= window[1] - by["tagdef-create-keyboard"]["keyboard"]
            )
        for state in [
            "tagdef-create-conflict",
            "tagdef-rename-conflict",
            "tagdef-rename-failure",
            "tagdef-remove-failure",
        ]:
            x, y, w, h = by[state]["boxes"]["tag-definition-error"]
            assert 0 <= x < x + w <= window[0] + 1 and 0 <= y < y + h <= window[1]
        log = (p / "flutter.log").read_text()
        assert (
            "All tests passed!" in log
            and "PROTOTYPE_FIDELITY_VERIFIED" in log
            and "EXCEPTION CAUGHT" not in log
        )
        records = [
            json.loads(row.split("VIDEO_TAG_DEFINITIONS_VERIFIED:", 1)[1])
            for row in log.splitlines()
            if "VIDEO_TAG_DEFINITIONS_VERIFIED:" in row
        ]
        (record,) = records
        video, pack, created = (
            record["video_tag"],
            record["pack_tag"],
            record["created_tag"],
        )
        assert video != pack and created != record["pack_kimono_tag"]
        assert (
            next(t["count"] for t in by["tagdef-created"]["tags"] if t["id"] == created)
            == 0
        )
        assert (
            record["playback_before"]
            == record["playback_after"]
            == {"status": 404, "code": "round_not_started"}
        )
        assert (
            by["tagdef-create-conflict"]["draft"] == "户外"
            and by["tagdef-rename-conflict"]["draft"] == "自然"
        )
        assert (
            by["tagdef-rename-failure"]["draft"] == "户外视频改名"
            and by["tagdef-remove-cancel"]["draft"] == "取消后的草稿"
        )
        for state in ["tagdef-video", "tagdef-renamed", "tagdef-remove-failure"]:
            assert by[state]["selected"] == [video] and by[state]["matching"] == 2
        for state in ["tagdef-removed", "tagdef-reopened"]:
            assert by[state]["selected"] == [] and all(
                t["id"] != video for t in by[state]["tags"]
            )
        assert by["tagdef-pack"]["tags"] == by["tagdef-pack-final"]["tags"]
        assert (
            by["tagdef-pack-final"]["selected"] == [pack]
            and by["tagdef-pack-final"]["matching"] == 2
        )
        requests = read(p / "requests.json")
        writes = [
            r
            for r in requests
            if r["method"] in {"POST", "PATCH", "DELETE"}
            and r["path"] != "/api/v1/auth/login"
        ]
        assert [(r["method"], r["path"], r["status"]) for r in writes] == [
            ("POST", "/api/v1/tags", 409),
            ("POST", "/api/v1/tags", 201),
            ("PATCH", "/api/v1/tags/" + video, 409),
            ("PATCH", "/api/v1/tags/" + video, 503),
            ("PATCH", "/api/v1/tags/" + video, 200),
            ("DELETE", "/api/v1/tags/" + video, 503),
            ("DELETE", "/api/v1/tags/" + video, 200),
        ]
        assert (
            writes[0]["body"]["name"] == "户外"
            and writes[1]["body"]["name"] == "和服"
            and writes[2]["body"]["name"] == "自然"
        )
        assert (
            writes[3]["body"] == writes[4]["body"]
            and writes[3]["body"]["name"] == "户外视频改名"
        )
        assert writes[5]["body"] == writes[6]["body"]
        assert all(
            "取消后的草稿" not in json.dumps(r, ensure_ascii=False) for r in writes
        )
        fault = read(p / "fixture-final.json")
        assert (
            fault["tag_definition_failure"] == "off"
            and len(fault["tag_definition_failures"]) == 2
        )
        assert fault["tag_definition_failures"] == [
            {k: writes[i][k] for k in ["method", "path", "body"]} for i in [3, 5]
        ]
        sql = read(p / "sql.json")
        assert {t["id"]: t["name"] for t in sql["tags"]} == {
            **{
                t["id"]: t["name"]
                for t in by["tagdef-video"]["tags"]
                if t["id"] != video
            },
            created: "和服",
        }
        assert len(sql["video_tags"]) == 2 and all(
            t["tag_id"] not in {video, created} for t in sql["video_tags"]
        )
        names = {t["id"]: t["name"] for t in sql["pack_tag_definitions"]}
        assert (
            names == {t["id"]: t["name"] for t in by["tagdef-pack"]["tags"]}
            and names[pack] == "户外"
            and names[record["pack_kimono_tag"]] == "和服"
        )
        actual_links = {
            (
                Path(
                    next(v["path"] for v in sql["packs"] if v["id"] == t["pack_id"])
                ).name,
                names[t["tag_id"]],
            )
            for t in sql["pack_tag_links"]
        }
        assert (
            actual_links
            == {(p["folder"], tag) for p in fixture_packs for tag in p["tags"]}
            and len(actual_links) == 8
        )
        assert not any(
            sql[t]
            for t in [
                "playback_rounds",
                "round_entries",
                "recent_entries",
                "pack_sessions",
            ]
        )
        (progress,) = sql["pack_progress"]
        assert (
            progress["revision"] == 1
            and progress["updated_at"] == 1000
            and progress["offset_ratio"] == 0
            and not progress["completed"]
        )
        assert {r["id"] for r in sql["request_records"]} == {
            prefix + writes[i]["body"]["request_id"]
            for prefix, i in [
                ("tag.create:", 1),
                ("tag.rename:", 4),
                ("tag.delete:", 6),
            ]
        }
        assert len(sql["videos"]) == 2 and len(sql["packs"]) == 4
        report[label] = {
            "points": len(metrics),
            "writes": len(writes),
            "accepted_commands": len(sql["request_records"]),
            "media": len(media),
        }
    assert (
        "+0 -4: Some tests failed."
        in (HERE / "checks/lifecycle-red-valid.log").read_text()
    )
    assert "+51: All tests passed!" in (HERE / "checks/components.log").read_text()
    assert "No issues found!" in (HERE / "checks/analyze.log").read_text()
    assert "All checks passed!" in (HERE / "checks/ruff.log").read_text()
    after = read(HERE / "checks/environment-after.json")
    assert (
        after["size"] == "Physical size: 1080x2400"
        and after["density"] == "Physical density: 420"
        and after["font"] == "1.0"
    )
    shutdown = read(HERE / "checks/shutdown.json")
    assert shutdown["pid"] == after["pid"] and not shutdown["process_exists"]
    return {
        "passed": True,
        "source": source,
        "supplement": supplement,
        "keyboard_driver": keyboard,
        "manifest_files": len(manifest),
        "runs": report,
        "normal_points": 45,
        "additional_points": 30,
        "component_tests": 51,
    }


if __name__ == "__main__":
    print(json.dumps(main(), ensure_ascii=False, indent=2))
