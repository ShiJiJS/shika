#!/usr/bin/env python3
"""Read-only verification of the fixed-scope native state transitions."""

import hashlib
import json
import struct
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SOURCE = "76a2f95"
BASE = "b94754f"
STATES = [
    "stability-library",
    "stability-filter",
    "stability-preview",
    "stability-editor",
    "stability-saved",
    "stability-readback",
    "stability-added",
    "stability-frozen-queue",
    "stability-return",
    "stability-second-preview",
    "stability-tag-deleted",
    "stability-second-queue",
    "stability-empty",
    "stability-cleared",
]
PRODUCTION = (
    "apps/mobile/lib",
    "apps/mobile/android",
    "apps/mobile/assets",
    "services/server/video_viewer",
)


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def output(text, prefix):
    return [
        json.loads(line.split(prefix, 1)[1])
        for line in text.splitlines()
        if prefix in line
    ]


def screens(folder, states):
    for state in states:
        data = (folder / (state + ".png")).read_bytes()
        assert data[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(
            ">II", data[16:24]
        ) == (1170, 2532)
        assert (
            "io.github.shijijs.video_viewer"
            in (folder / (state + "-window.txt")).read_text()
        )


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
        assert sha(HERE / name) == expected, name
    source = git("rev-parse", SOURCE)
    scope = read(HERE / "checks/source-scope.json")
    assert scope["source"] == source and scope["component_test_tree"] == git(
        "rev-parse", source + ":apps/mobile/test"
    )
    assert git("rev-parse", "HEAD:apps/mobile/test") == scope["component_test_tree"]
    changed_production = set(
        git("diff", "--name-only", BASE, source, "--", *PRODUCTION).splitlines()
    )
    assert changed_production == {
        "apps/mobile/lib/features/library/video_catalog_page.dart",
        "apps/mobile/lib/features/library/pack_catalog_page.dart",
    }
    during, after = (
        read(HERE / "checks/environment-during-corrected-batch.json"),
        read(HERE / "checks/after-corrected-batch.json"),
    )
    assert during["avd"] == after["avd"] == "video_viewer_api_36"
    assert (
        during["api"] == "36"
        and during["abi"] == "arm64-v8a"
        and during["host_avc_decoder"] == "2"
    )
    assert after["process"] == [during["process"]]
    assert all(
        s in during["process"]
        for s in (
            "-gpu software",
            "-feature -Vulkan",
            "-feature -GLDMA",
            "-feature HardwareDecoder",
        )
    )
    assert (
        after["size"] == "Physical size: 1080x2400"
        and after["density"] == "Physical density: 420"
    )
    assert after["font"] == "1.0" and "volume is 5 in range [0..15]" in after["music"]
    assert "No issues found!" in (HERE / "checks/analyze-counts-fix.log").read_text()
    assert (
        "+0 -4: Some tests failed." in (HERE / "checks/counts-before.log").read_text()
    )
    assert (
        "+25: All tests passed!"
        in (HERE / "checks/counts-after-related-final.log").read_text()
    )
    assert "All checks passed!" in (HERE / "checks/ruff.log").read_text()
    end = read(HERE / "checks/final-device-baseline.json")
    assert (
        end["size"] == after["size"]
        and end["density"] == after["density"]
        and end["font"] == after["font"]
    )
    shutdown = read(HERE / "checks/shutdown.json")
    assert (
        shutdown["process_absent"]
        and shutdown["shutdown_exit"] == 0
        and shutdown["pid"] == end["pid"]
    )
    baseline = HERE / "baseline/current-geometry"
    baseline_source = read(baseline / "source.json")
    assert baseline_source["commit"] == git("rev-parse", BASE)
    base_result = read(baseline / "result.json")
    assert (
        base_result["passed"]
        and base_result["scenario"] == "preview"
        and len(base_result["screens"]) == 20
    )
    screens(baseline, base_result["screens"])
    geometry = {v["state"]: v for v in read(baseline / "metrics.json")}
    assert abs(geometry["preview-queue"]["keys"]["preview-queue-frame"][2] - 390) < 0.1
    assert abs(geometry["preview-queue"]["keys"]["preview-queue-frame"][3] - 435) < 0.1
    reports, shared = [], None
    for number in range(1, 4):
        folder = HERE / f"native/normal-{number}"
        fixed = read(folder / "source.json")
        assert (
            fixed["commit"] == source
            and fixed["prototype_tree"] == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
        )
        if shared is None:
            shared = fixed["files"]
        assert fixed["files"] == shared
        result = read(folder / "result.json")
        assert (
            result["passed"]
            and result["scenario"] == "preview-stability"
            and result["screens"] == STATES
        )
        screens(folder, STATES)
        runtime = read(folder / "runtime.json")[0]
        assert runtime["HostConfig"]["ReadonlyRootfs"]
        assert runtime["HostConfig"]["PortBindings"]["8760/tcp"] == [
            {"HostIp": "127.0.0.1", "HostPort": "8768"}
        ]
        assert "VV_FIDELITY_PREVIEW_MUTATION=enabled" in runtime["Config"]["Env"]
        guard = read(folder / "control-guard.json")
        assert guard == {
            "invalid_key_status": 403,
            "files_before_authorized_addition": 26,
        }
        text = (folder / "flutter.log").read_text()
        assert "+1: All tests passed!" in text and "PROTOTYPE_FIDELITY_VERIFIED" in text
        assert not any(
            s in text
            for s in ("EXCEPTION CAUGHT", "Some tests failed", "stability timeout")
        )
        values = read(folder / "metrics.json")
        assert (
            values == output(text, "FIDELITY_METRICS:")
            and [v["state"] for v in values] == STATES
        )
        by = {v["state"]: v for v in values}
        (final,) = output(text, "PREVIEW_STABILITY_VERIFIED:")
        original, new = final["original"], final["new_video"]
        tag, liked = final["outdoor_tag"], final["liked_tag"]
        first, second = final["first_round"], final["second_round"]
        assert len(set(original)) == 2 and new not in original and first != second
        assert set(final["first_members"]) == set(original)
        assert (
            set(final["second_members"])
            == set(final["refreshed"])
            == {original[1], new}
        )
        assert set(final["final_ids"]) == {*original, new}
        assert {v["id"] for v in final["recent"]["items"]} == set(original)
        for index, value in enumerate(values):
            assert value["physical"] == [1170, 2532] and value["dpr"] == 3
            if index == 0 or index == 13:
                assert not value["entry_tags"]
            else:
                assert value["entry_tags"] == [tag]
            players = value["players"] or []
            assert len(players) <= 3
            audible = [p for p in players if p["playing"] and p["volume"] > 0]
            assert len(audible) <= 1
            if audible:
                assert audible[0]["source"] == value["visible_video"]
            if 2 <= index <= 7:
                assert (
                    value["round"] == first
                    and value["current"] == original[0]
                    and value["cursor"] == final["first_cursor"]
                    and value["total"] == 2
                )
            if 9 <= index <= 11:
                assert (
                    value["round"] == second
                    and value["current"] == original[1]
                    and value["cursor"] == final["second_cursor"]
                    and value["total"] == 2
                )
        assert by["stability-saved"]["current_tags"] == [liked]
        preloaded = [
            p
            for value in values
            for p in (value["players"] or [])
            if f"/videos/{new}/stream" in p["source"]
        ]
        assert preloaded and all(
            p["initialized"] and not p["playing"] and p["volume"] == 0
            for p in preloaded
        )
        for state in ["stability-return", "stability-empty", "stability-cleared"]:
            assert by[state]["inventory"] == [3, 4]
        assert set(by["stability-return"]["catalog_ids"]) == {original[1], new}
        assert (
            by["stability-empty"]["catalog_total"] == 0
            and not by["stability-empty"]["catalog_ids"]
        )
        assert by["stability-cleared"]["catalog_total"] == 3 and set(
            by["stability-cleared"]["catalog_ids"]
        ) == {*original, new}
        before, after_media = (
            read(folder / "media-before.json"),
            read(folder / "media-after.json"),
        )
        (addition,) = read(folder / "fixture-final.json")["public_additions"]
        assert len(before) == 26 and len(after_media) == 27
        assert addition == final["addition"] and addition["id"] == new
        assert (
            addition["file"] == "videos/外部新增/晨光新视频.mp4"
            and addition["file"] not in before
        )
        assert addition["sha256"] == sha(
            ROOT / "apps/mobile/assets/media/flower-landscape.mp4"
        )
        assert after_media == {**before, addition["file"]: addition["sha256"]}
        db = read(folder / "database-projection.json")
        rounds = {r["id"]: r for r in db["playback_rounds"]}
        assert set(rounds) == {first, second}
        for identity, members, ordered, cursor in [
            (first, final["first_members"], original, final["first_cursor"]),
            (
                second,
                final["second_members"],
                final["refreshed"],
                final["second_cursor"],
            ),
        ]:
            r = rounds[identity]
            assert (
                r["membership"] == "fixed"
                and r["source"] == "library"
                and r["candidate_count"] == 2
            )
            assert r["cursor"] == cursor and json.loads(r["scope"])["tag_ids"] == [tag]
            rows = sorted(
                [e for e in db["round_entries"] if e["round_id"] == identity],
                key=lambda e: e["ordinal"],
            )
            assert [e["video_id"] for e in rows] == members
            assert [e["source_ordinal"] for e in rows] == [
                ordered.index(i) for i in members
            ]
        assert {v["id"] for v in db["videos"]} == {*original, new} and all(
            v["status"] == "available" for v in db["videos"]
        )
        assert tag not in {t["id"] for t in db["tags"]} and len(db["tags"]) == 2
        assert {
            (v["video_id"], v["tag_id"])
            for v in db["video_tags"]
            if v["video_id"] in {original[0], new}
        } == {(original[0], liked)}
        assert {
            v["video_id"] for v in db["recent_entries"] if v["kind"] == "video"
        } == set(original)
        assert len(db["pack_tag_definitions"]) == 5 and len(db["packs"]) == 4
        assert any(
            t["name"] == "户外" and t["id"] != tag for t in db["pack_tag_definitions"]
        )
        (progress,) = db["pack_progress"]
        assert progress["revision"] == 1 and progress["updated_at"] == 1000
        requests = read(folder / "requests.json")
        posts = [
            r
            for r in requests
            if r["method"] == "POST" and r["path"] == "/api/v1/rounds"
        ]
        assert len(posts) == 2 and all(
            r["status"] == 201
            and r["body"]["membership"] == "fixed"
            and r["body"]["scope"]["tag_ids"] == [tag]
            for r in posts
        )
        writes = [
            r
            for r in requests
            if r["method"] == "PATCH" and r["path"] == "/api/v1/video-tags"
        ]
        assert len(writes) == 2 and all(r["status"] == 200 for r in writes)
        assert [
            (r["body"]["video_ids"], r["body"]["tag_ids"], r["body"]["mode"])
            for r in writes
        ] == [([original[0]], [liked], "replace"), ([new], [tag], "add")]
        deletes = [r for r in requests if r["method"] == "DELETE"]
        assert (
            len(deletes) == 1
            and deletes[0]["path"] == "/api/v1/tags/" + tag
            and deletes[0]["status"] == 200
        )
        for request in requests:
            if request["method"] in {"GET", "HEAD"}:
                continue
            assert request["status"] in {200, 201}
            assert request["path"] in {
                "/api/v1/auth/login",
                "/api/v1/rounds",
                "/api/v1/video-tags",
                "/api/v1/tags/" + tag,
            } or any(
                request["path"] == f"/api/v1/rounds/{r}/{action}"
                for r in [first, second]
                for action in ["opened", "position", "order"]
            )
        viewport = read(folder / "restored-viewport.json")
        assert (
            not viewport["errors"]
            and viewport["before"] == viewport["after"]
            and viewport["font_before"] == viewport["font_after"] == "1.0"
        )
        reports.append(
            {
                "round": number,
                "screens": len(values),
                "fixed_ranges": 2,
                "old_source_files_unchanged": 26,
                "intentional_public_additions": 1,
            }
        )
    reader = HERE / "adjacent/reader"
    result = read(reader / "result.json")
    assert (
        result["passed"]
        and result["scenario"] == "reader"
        and len(result["screens"]) == 13
    )
    assert (
        read(reader / "source.json")["commit"] == source
        and read(reader / "source.json")["files"] == shared
    )
    screens(reader, result["screens"])
    assert read(reader / "media-before.json") == read(reader / "media-after.json")
    assert any(
        r["path"] == "/api/v1/library-state" and r["phase"] == "reader-quick-exit"
        for r in read(reader / "requests.json")
    )
    for n in range(1, 4):
        old = HERE / f"diagnostics/before-counts-fix-{n}"
        assert read(old / "source.json")["commit"] == git("rev-parse", "a339392")
        assert (
            read(old / "result.json")["passed"]
            and read(old / "result.json")["screens"] == STATES
        )
        assert "inventory" not in read(old / "metrics.json")[0]
    for name, expected in shared.items():
        assert sha(ROOT / name) == expected
        assert (
            hashlib.sha256(
                subprocess.check_output(["git", "show", source + ":" + name], cwd=ROOT)
            ).hexdigest()
            == expected
        )
    for name, expected in baseline_source["files"].items():
        if (
            any(name.startswith(prefix + "/") for prefix in PRODUCTION)
            and name not in changed_production
        ):
            assert shared[name] == expected
    for label, error in [
        ("development-1", "Bad state: No element"),
        ("development-2", "Bad state: Too many elements"),
    ]:
        folder = HERE / "diagnostics" / label
        assert (
            not (folder / "result.json").exists()
            and error in (folder / "flutter.log").read_text()
        )
    print(
        json.dumps(
            {
                "verified": True,
                "source": source,
                "manifest_inputs": len(manifest),
                "baseline_preview_points": 20,
                "rounds": reports,
                "production_changed_files": sorted(changed_production),
                "target_phone_nas_verified": False,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
