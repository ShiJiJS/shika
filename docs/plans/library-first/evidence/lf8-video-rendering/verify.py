#!/usr/bin/env python3
"""Read-only check of the current-preview native lifecycle evidence."""

import hashlib
import json
import re
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
sys.path.insert(0, str(ROOT / "scripts"))
from video_probe_pixels import inspect

SOURCE = "7740f4d"
SETTINGS_SOURCE = "eb5cc46"
SETTINGS_DRIVER = "apps/mobile/integration_test/server_settings_panels_test.dart"
SCENES = [
    "lifecycle-library",
    "lifecycle-playing",
    "lifecycle-paused",
    "lifecycle-fullscreen-paused",
    "lifecycle-fullscreen-playing",
    "lifecycle-device-levels",
    "lifecycle-boost",
    "lifecycle-fullscreen-recovered",
    "lifecycle-inline-restored",
    "lifecycle-inline-recovered",
    "lifecycle-swipes",
    "lifecycle-preload-off",
    "lifecycle-single-decoder",
    "lifecycle-single-swiped",
    "lifecycle-return",
]


def read(p):
    return json.loads(p.read_text())


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def lines(text, prefix):
    return [
        json.loads(row.split(prefix, 1)[1])
        for row in text.splitlines()
        if prefix in row
    ]


def selected(value):
    matches = [
        p
        for p in value["players"]
        if f"/videos/{value['current']}/stream" in p["source"]
    ]
    assert len(matches) == 1
    return matches[0]


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
    tracked = set(
        subprocess.check_output(
            ["git", "ls-files", str(HERE)], cwd=ROOT, text=True
        ).splitlines()
    )
    assert {
        str((HERE / name).relative_to(ROOT))
        for name in [*manifest, "manifest.json", "verification.json"]
    } <= tracked
    for name, expected in manifest.items():
        assert sha(HERE / name) == expected, name
    source = subprocess.check_output(
        ["git", "rev-parse", SOURCE], cwd=ROOT, text=True
    ).strip()
    settings_source = subprocess.check_output(
        ["git", "rev-parse", SETTINGS_SOURCE], cwd=ROOT, text=True
    ).strip()
    changed = subprocess.check_output(
        ["git", "diff", "--name-only", source, settings_source], cwd=ROOT, text=True
    ).splitlines()
    assert changed == [SETTINGS_DRIVER]
    scope = read(HERE / "checks/source-scope.json")
    assert scope["source"] == source and scope["related_client"] == 15
    assert "+15: All tests passed!" in (HERE / "checks/related-client.log").read_text()
    subprocess.run(
        [
            "git",
            "diff",
            "--exit-code",
            "605badb",
            source,
            "--",
            "apps/mobile/lib",
            "apps/mobile/test",
            "services/server/video_viewer",
        ],
        cwd=ROOT,
        check=True,
    )
    shutdown = read(HERE / "checks/owned-emulator-shutdown.json")
    assert shutdown["process_absent"] and shutdown["shutdown_command_exit_code"] == 0
    assert not shutdown["qemu_exit_code_observed"]
    baseline = read(HERE / "checks/final-device-baseline.json")
    assert baseline["avd"] == "video_viewer_api_36"
    assert (
        baseline["size"] == "Physical size: 1080x2400"
        and baseline["density"] == "Physical density: 420"
    )
    assert (
        baseline["font"] == "1.0"
        and "volume is 5 in range [0..15]" in baseline["music"]
    )
    assert "No issues found!" in (HERE / "checks/analyze-app-final.log").read_text()
    observation = read(HERE / "checks/render-observation.json")
    assert (
        observation["picture_integrity_passed"] and not observation["root_cause_proven"]
    )
    assert sha(ROOT / observation["source_asset"]) == observation["source_sha256"]
    blob = subprocess.check_output(
        ["git", "show", source + ":" + observation["source_asset"]], cwd=ROOT
    )
    assert hashlib.sha256(blob).hexdigest() == observation["source_sha256"]
    for name, bad in (
        ("minimal-impeller-final", True),
        ("minimal-skia-final", True),
        ("minimal-host-codec-no-dma", False),
    ):
        folder = HERE / "diagnostics" / name
        fixed = read(folder / "source.json")
        for name, expected in fixed["files"].items():
            blob = subprocess.check_output(
                ["git", "show", fixed["commit"] + ":" + name], cwd=ROOT
            )
            assert hashlib.sha256(blob).hexdigest() == expected
        pixels = read(folder / "png-inspection.json")
        assert pixels["expectation_matched"] and pixels["picture_integrity_passed"] == (
            not bad
        )
        assert pixels["inspector_sha256"] == sha(ROOT / "scripts/video_probe_pixels.py")
        for row in pixels["images"]:
            assert inspect(folder / row["file"]) == row
            assert row["sampled_distinct_colors"] > 1000
            assert row["longest_green_run"] == (
                129 if bad and row["file"] == "flutter-textureView.png" else 0
            )
        if bad:
            for mode in ("surface", "texture", "codec"):
                value = read(folder / ("native-" + mode + ".json"))
                assert (
                    value["status"] == "ready"
                    and value["source_sha256"] == observation["source_sha256"]
                )
            codec = read(folder / "native-codec.json")["details"]
            assert codec["decoder"] == "c2.android.avc.decoder"
            assert codec["image_width"] == 960 and codec["image_height"] == 540
            assert (
                codec["crop"] == "[0,0][960,540]"
                and codec["planes"][0]["row_stride"] == 1024
            )
    assert "OK" in (HERE / "checks/launcher-detach-after.log").read_text()
    reuse = read(HERE / "checks/launcher-real-reuse.json")
    assert reuse["boot_completed"] == "1" and reuse["host_avc_decoder"] == "2"
    reports, shared_files, shared_media, all_clips = [], None, None, set()
    for number in range(1, 4):
        folder = HERE / f"native/normal-{number}"
        fixed = read(folder / "source.json")
        assert (
            fixed["commit"] == source
            and fixed["prototype_tree"] == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
        )
        if shared_files is None:
            shared_files = fixed["files"]
        assert fixed["files"] == shared_files
        runtime = read(folder / "runtime.json")[0]
        assert runtime["HostConfig"]["ReadonlyRootfs"]
        assert (
            runtime["HostConfig"]["PortBindings"]["8760/tcp"][0]["HostIp"]
            == "127.0.0.1"
        )
        assert (
            runtime["HostConfig"]["PortBindings"]["8760/tcp"][0]["HostPort"] == "8768"
        )
        assert "VV_FIDELITY_PREVIEW_LIFECYCLE=enabled" in runtime["Config"]["Env"]
        environment = read(folder / "environment.json")
        assert (
            environment["avd"] == "video_viewer_api_36"
            and environment["api"] == "36"
            and environment["abi"] == "arm64-v8a"
        )
        assert not environment["renderer_override"]
        assert environment["host_avc_decoder"] == "2"
        assert "-feature HardwareDecoder" in environment["emulator_process"][0]
        assert "-feature -GLDMA" in environment["emulator_process"][0]
        assert (
            len(environment["emulator_process"]) == 1
            and "-gpu software" in environment["emulator_process"][0]
            and "-no-window" in environment["emulator_process"][0]
        )
        result = read(folder / "result.json")
        assert (
            result["passed"]
            and result["screens"] == SCENES
            and result["scenario"] == "preview-lifecycle"
        )
        frames = read(folder / "video-frames.json")
        assert result["known_video_frame_checks"] == len(frames) == 5
        assert set(frames) == set(SCENES[3:8])
        for state, frame in frames.items():
            assert inspect(folder / (state + ".png")) == frame
            assert (
                frame["longest_green_run"] == 0
                and frame["sampled_distinct_colors"] > 1000
            )
        text = (folder / "flutter.log").read_text()
        assert "+1: All tests passed!" in text and "PROTOTYPE_FIDELITY_VERIFIED" in text
        assert not any(
            marker in text
            for marker in (
                "EXCEPTION CAUGHT",
                "PREVIEW_LIFECYCLE_TIMEOUT",
                "Some tests failed",
            )
        )
        values = read(folder / "metrics.json")
        assert values == lines(text, "FIDELITY_METRICS:")
        assert [v["state"] for v in values] == SCENES
        by = {v["state"]: v for v in values}
        (final,) = lines(text, "PREVIEW_LIFECYCLE_RESULT:")
        assert (
            final["peak_players"] == 3
            and final["swipes"] == 7
            and final["home_count"] == 2
        )
        ids = final["catalog_ids"]
        assert len(ids) == len(set(ids)) == 3 and len(set(final["rounds"])) == 2
        assert (
            not by["lifecycle-library"]["players"]
            and not by["lifecycle-library"]["round"]
        )
        assert (
            not by["lifecycle-preload-off"]["players"]
            and not by["lifecycle-return"]["players"]
        )
        for v in values:
            landscape = v["state"] in SCENES[3:8]
            assert v["physical"] == ([2532, 1170] if landscape else [1170, 2532])
            assert v["dpr"] == 3 and v["lifecycle"] == "resumed"
            assert len(v["players"]) <= (3 if v["preload"] else 1)
            audible = [p for p in v["players"] if p["playing"] and p["volume"] > 0]
            assert len(audible) <= 1
            if v["players"]:
                p = selected(v)
                assert p["initialized"] and min(p["size"]) > 0
                if audible:
                    assert audible == [p]
                assert v["current"] in ids and v["total"] == 3
                assert not p["playing"] or v["play_requested"]
                if not v["play_requested"]:
                    assert not p["playing"]
            png = (folder / (v["state"] + ".png")).read_bytes()
            assert (
                png[:8] == b"\x89PNG\r\n\x1a\n"
                and list(struct.unpack(">II", png[16:24])) == v["physical"]
            )
            focus = (folder / (v["state"] + "-window.txt")).read_text()
            assert any(
                "mCurrentFocus=" in line and "io.github.shijijs.video_viewer" in line
                for line in focus.splitlines()
            )
        a, b = (
            selected(by["lifecycle-paused"]),
            selected(by["lifecycle-fullscreen-paused"]),
        )
        assert a["controller_identity"] == b["controller_identity"]
        assert a["position_ms"] == b["position_ms"] and a["position_ms"] > 1000
        assert not a["playing"] and not b["playing"] and a["speed"] == b["speed"] == 1.5
        assert selected(by["lifecycle-boost"])["speed"] == 2
        for name in (
            "lifecycle-fullscreen-recovered",
            "lifecycle-inline-restored",
            "lifecycle-inline-recovered",
        ):
            p = selected(by[name])
            assert not p["playing"] and p["speed"] == 1.5
            assert (
                by[name]["round"] == final["rounds"][0]
                and by[name]["current"] == ids[0]
            )
        assert (
            selected(by["lifecycle-fullscreen-recovered"])["controller_identity"]
            != a["controller_identity"]
        )
        assert (
            len(by["lifecycle-single-decoder"]["players"])
            == len(by["lifecycle-single-swiped"]["players"])
            == 1
        )
        assert (
            by["lifecycle-single-decoder"]["position"] == 0
            and by["lifecycle-single-swiped"]["position"] == 1
        )
        swipes = lines(text, "PREVIEW_NATIVE_SWIPE:")
        assert len(swipes) == 6 and [v["position"] for v in swipes] == [
            1,
            2,
            1,
            0,
            1,
            0,
        ]
        for v in swipes:
            assert (
                v["round"] == final["rounds"][0] and v["current"] == ids[v["position"]]
            )
            assert f"/videos/{v['current']}/stream" in v["visible_source"]
            assert len(v["players"]) <= 3
            if v["position"] == 1:
                assert len(v["players"]) == 3
            audible = [p for p in v["players"] if p["playing"] and p["volume"] > 0]
            assert len(audible) == 1 and audible[0]["source"] == v["visible_source"]
        assert len(lines(text, "PREVIEW_BACKGROUND_RELEASED:")) == 2
        lifecycle = re.findall(r"PREVIEW_NATIVE_LIFECYCLE:(\w+)", text)
        assert lifecycle.count("paused") == 2 and lifecycle.count("hidden") == 4
        actions = read(folder / "device-actions.json")
        assert [a["name"] for a in actions] == [
            "lifecycle-device-home",
            "lifecycle-device-foreground",
            "lifecycle-device-back",
            "lifecycle-device-home",
            "lifecycle-device-foreground",
        ]
        (restored,) = lines(text, "PREVIEW_DEVICE_RESTORED:")
        assert restored == final["original_levels"]
        viewport = read(folder / "restored-viewport.json")
        assert (
            not viewport["errors"]
            and viewport["before"] == viewport["after"]
            and viewport["font_before"] == viewport["font_after"] == "1.0"
        )
        before, after = (
            read(folder / "media-before.json"),
            read(folder / "media-after.json"),
        )
        assert before == after and len(before) == 27
        if shared_media is None:
            shared_media = before
        assert shared_media == before
        database = read(folder / "database-projection.json")
        rounds = {r["id"]: r for r in database["playback_rounds"]}
        assert set(rounds) == set(final["rounds"])
        for identity in final["rounds"]:
            r = rounds[identity]
            assert (
                r["candidate_count"] == 3
                and r["membership"] == "fixed"
                and r["source"] == "library"
                and r["order"] == "sequential"
            )
            entries = sorted(
                [e for e in database["round_entries"] if e["round_id"] == identity],
                key=lambda e: e["ordinal"],
            )
            assert [e["video_id"] for e in entries] == ids and [
                e["source_ordinal"] for e in entries
            ] == [0, 1, 2]
            assert [
                e["video"]["id"] for e in final["members"][identity]["items"]
            ] == ids
        assert (
            rounds[final["rounds"][0]]["cursor"] == 0
            and rounds[final["rounds"][1]]["cursor"] == 1
        )
        assert len(database["videos"]) == len(database["recent_entries"]) == 3
        assert all(v["status"] == "available" for v in database["videos"])
        requests = read(folder / "requests.json")
        posts = [
            r
            for r in requests
            if r["method"] == "POST" and r["path"] == "/api/v1/rounds"
        ]
        assert len(posts) == 2 and all(r["status"] == 201 for r in posts)
        for request in requests:
            if request["method"] in {"GET", "HEAD"}:
                continue
            assert request["status"] in {200, 201}
            assert request["path"] in {"/api/v1/auth/login", "/api/v1/rounds"} or any(
                request["path"] == f"/api/v1/rounds/{identity}/{action}"
                for identity in final["rounds"]
                for action in ("opened", "order", "position")
            )
        assert all(
            r["body"]["membership"] == "fixed" and r["body"]["source"] == "library"
            for r in posts
        )
        for identity in ids:
            assert any(
                r["path"] == f"/api/v1/videos/{identity}/stream"
                and r["status"] in (200, 206)
                for r in requests
            )
        clips = read(folder / "recordings.json")
        probes = read(folder / "recordings-probe.json")
        assert len(clips) == len(probes) >= 3
        assert {r["shape"] for r in clips} == {"390x844", "844x390"}
        for clip, probe in zip(clips, probes):
            assert (
                sha(folder / clip["file"]) == clip["sha256"]
                and (folder / clip["file"]).stat().st_size == clip["bytes"]
            )
            video = next(s for s in probe["streams"] if s.get("codec_name") == "h264")
            assert (
                f"{video['width']}x{video['height']}" == clip["shape"]
                and int(video["nb_read_frames"]) > 0
            )
            all_clips.add(str((folder / clip["file"]).relative_to(HERE)))
        reports.append(
            {
                "round": number,
                "screens": len(values),
                "native_swipes": final["swipes"],
                "actual_home_cycles": 2,
                "native_controller_peak": 3,
                "recordings": len(clips),
                "requested_play_without_playing_snapshot": [
                    v["state"]
                    for v in values
                    if v["players"]
                    and v["play_requested"]
                    and not selected(v)["playing"]
                ],
            }
        )
    for scenario, count in (("reader", 13), ("settings", 21)):
        folder = HERE / "adjacent" / scenario
        result = read(folder / "result.json")
        assert (
            result["passed"]
            and result["scenario"] == scenario
            and len(result["screens"]) == count
        )
        fixed = read(folder / "source.json")
        assert fixed["commit"] == (
            settings_source if scenario == "settings" else source
        )
        expected_files = dict(shared_files)
        if scenario == "settings":
            blob = subprocess.check_output(
                ["git", "show", settings_source + ":" + SETTINGS_DRIVER], cwd=ROOT
            )
            expected_files[SETTINGS_DRIVER] = hashlib.sha256(blob).hexdigest()
        assert fixed["files"] == expected_files
        assert "+1: All tests passed!" in (folder / "flutter.log").read_text()
        viewport = read(folder / "restored-viewport.json")
        assert not viewport["errors"] and viewport["before"] == viewport["after"]
        assert read(folder / "media-before.json") == read(folder / "media-after.json")
        for state in result["screens"]:
            png = (folder / (state + ".png")).read_bytes()
            assert png[:8] == b"\x89PNG\r\n\x1a\n"
    for name in ("adjacent-settings-ime-timeout", "adjacent-settings-ime-observed"):
        folder = HERE / "diagnostics" / name
        assert "Settings timeout: real root IME" in (folder / "flutter.log").read_text()
        assert not (folder / "result.json").exists()
        assert not read(folder / "restored-viewport.json")["errors"]
    observed = HERE / "diagnostics/adjacent-settings-ime-observed"
    assert "mInputShown=true" in (observed / "ime-observe-2-ime.txt").read_text()
    settings_metrics = read(HERE / "adjacent/settings/metrics.json")
    for value in settings_metrics:
        if value["state"] not in {
            "settings-connection-keyboard",
            "settings-root-keyboard",
        }:
            continue
        assert value["viewInsets"][3] > 0
        name = (
            "root-name"
            if value["state"] == "settings-root-keyboard"
            else "connection-port"
        )
        rect = value["keys"][name]
        assert rect[1] + rect[3] <= value["size"][1] - value["viewInsets"][3]
    release = read(HERE / "checks/release-apk.json")
    assert (
        release["build_exit_code"] == 0
        and release["version"] == "0.1.4"
        and release["version_code"] == 5
    )
    assert (
        not release["diagnostic_activity_in_manifest"]
        and not release["diagnostic_activity_in_dex"]
    )
    assert (
        not release["integration_test_plugin_in_dex"]
        and not release["prototype_entries"]
    )
    assert (
        release["certificate_sha256"]
        == "f5abd3bd11d94b3aaee66ab65e6a666a228a4d64edf4b86de9327ae9b8a59161"
    )
    assert (
        "c2.goldfish.h264.decoder"
        in (HERE / "checks/current-app-codec-observation.txt").read_text()
    )
    decoded = read(HERE / "checks/recordings-decoded.json")
    assert {r["file"] for r in decoded} == all_clips
    assert all(
        r["exit_code"] == 0
        and not r["errors"]
        and r["preserve_input_time_base"]
        and sha(HERE / r["file"]) == r["sha256"]
        for r in decoded
    )
    for name, expected in shared_files.items():
        assert sha(ROOT / name) == (
            expected_files[name] if name == SETTINGS_DRIVER else expected
        )
        blob = subprocess.check_output(["git", "show", source + ":" + name], cwd=ROOT)
        assert hashlib.sha256(blob).hexdigest() == expected
    print(
        json.dumps(
            {
                "verified": True,
                "source": source,
                "settings_driver_source": settings_source,
                "manifest_inputs": len(manifest),
                "rounds": reports,
                "target_phone_nas_verified": False,
                "picture_integrity_passed": True,
                "local_configuration_issue": "https://github.com/ShiJiJS/video_viewer/issues/78",
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
