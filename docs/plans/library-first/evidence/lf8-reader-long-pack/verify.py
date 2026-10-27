#!/usr/bin/env python3
"""Read-only verification of all three native long-pack rounds."""

import hashlib
import json
import re
import struct
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SOURCE = "df9d80ce8ceff54e1d8ce4e5182541f05fa8e487"
SCENES = {
    "long-horizontal",
    "long-vertical-start",
    "long-page-101",
    "long-page-201",
    "long-page-301",
    "long-page-401",
    "long-vertical-end",
    "long-horizontal-end",
    "large-page-1",
    "large-page-2",
    "large-page-3",
    "long-return",
    "long-reopened",
}


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


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
    for name, expected in manifest.items():
        assert sha(HERE / name) == expected, name
    environment = read(HERE / "checks/environment.json")
    assert "-gpu software" in environment["emulator_process_command"]
    assert "-no-window" in environment["emulator_process_command"]
    assert any("SwiftShader" in line for line in environment["graphics_boot_lines"])
    assert not environment["renderer_override_skia"]
    recovered = read(HERE / "checks/recovered-display.json")
    assert recovered["matches_failed_round_original"]
    assert recovered["after"] == {
        "size": "Physical size: 1080x2400",
        "density": "Physical density: 420",
        "font": "1.0",
    }
    reports, shared_files, shared_media = [], None, None
    source = subprocess.check_output(
        ["git", "rev-parse", SOURCE], cwd=ROOT, text=True
    ).strip()
    apk = read(HERE / "checks/release-apk.json")
    assert apk["source"] == source and apk["build_mode"] == "release"
    assert apk["flutter_engine_abis"] == ["arm64-v8a"] and apk["prototype_paths"] == []
    assert not apk["integration_test_plugin_dex_path"] and not apk["published"]
    assets = read(HERE / "checks/release-apk-assets.json")
    assert len(assets) == apk["assets_count"]
    assert not any("design/reference/" in name for name in assets)
    assert (
        "Built build/app/outputs/flutter-apk/app-release.apk"
        in (HERE / "checks/android-release.log").read_text()
    )
    decoded = read(HERE / "checks/recordings-decoded.json")
    assert decoded and all(
        r["exit_code"] == 0 and not r["errors"] and r["preserve_input_time_base"]
        for r in decoded
    )
    assert {r["file"] for r in decoded} == {
        str(p.relative_to(HERE)) for p in (HERE / "native").rglob("*.mp4")
    }
    assert len(decoded) == 6
    for recording in decoded:
        assert sha(HERE / recording["file"]) == recording["sha256"]
    baseline = read(HERE / "checks/final-device-baseline.json")
    assert baseline["avd"] == "video_viewer_api_36" and baseline["font"] == "1.0"
    assert (
        baseline["size"] == "Physical size: 1080x2400"
        and baseline["density"] == "Physical density: 420"
    )
    regression = read(HERE / "checks/regression-source.json")
    assert (
        regression["source"] == "f8631aeb62a678cc48d9569c7c034349af52c12a"
        and regression["client_total"] == 646
    )
    subprocess.run(
        [
            "git",
            "diff",
            "--exit-code",
            regression["source"],
            source,
            "--",
            "apps/mobile/lib",
            "apps/mobile/test",
            "services/server/video_viewer",
        ],
        cwd=ROOT,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    assert (
        "+646: All tests passed!"
        in (HERE / "checks/flutter-full-after.log").read_text()
    )
    assert "+12: All tests passed!" in (HERE / "checks/transport-after.log").read_text()
    assert (
        "+1 -2: Some tests failed."
        in (HERE / "checks/transport-before.log").read_text()
    )
    assert "No issues found!" in (HERE / "checks/analyze-frozen.log").read_text()
    for name, expected in regression["files"].items():
        assert sha(ROOT / name) == expected, name
        blob = subprocess.check_output(["git", "show", source + ":" + name], cwd=ROOT)
        assert hashlib.sha256(blob).hexdigest() == expected, name
    for number in range(1, 4):
        folder = HERE / f"native/normal-{number}"
        result = read(folder / "result.json")
        fixed = read(folder / "source.json")
        assert result["status"] == "passed" and set(result["screens"]) == SCENES
        assert fixed["commit"] == source
        assert fixed["prototype_tree"] == "1cbf605af8f03fa067a4ce8e914bb809e3a487ca"
        assert result["source_files"] == fixed["files"]
        runtime = read(folder / "runtime.json")[0]
        assert runtime["HostConfig"]["PortBindings"]["8760/tcp"] == [
            {"HostIp": "127.0.0.1", "HostPort": "8769"}
        ]
        mount = next(m for m in runtime["Mounts"] if m["Destination"] == "/media/packs")
        assert not mount["RW"]
        if shared_files is None:
            shared_files = fixed["files"]
        assert shared_files == fixed["files"]
        before, after = (
            read(folder / "media-before.json"),
            read(folder / "media-after.json"),
        )
        assert before == after
        assert len([name for name in before if name.startswith("04-long/")]) == 500
        if shared_media is None:
            shared_media = before
        assert shared_media == before
        device = read(folder / "device.json")
        command = read(folder / "process.json")["command"]
        assert "--no-enable-impeller" not in command and "--no-uninstall" in command
        assert "integration_test/server_reader_long_pack_test.dart" in command
        assert "1170x2532" in device["size"] and "480" in device["density"]
        assert device["font"] == "1" and not device["renderer_override_skia"]
        restored = read(folder / "restored-viewport.json")
        assert restored["before"] == restored["after"] and not restored["errors"]
        assert restored["font_before"] == restored["font_after"]
        text = (folder / "flutter.log").read_text()
        assert (
            "+1: All tests passed!" in text and "LONG_READER_FLUTTER_ERROR" not in text
        )
        assert "EXCEPTION CAUGHT BY" not in text
        fixture = read(folder / "fixture-final.json")
        assert fixture["display"] == "verified" and fixture["active_images"] == 0
        scans = [
            r
            for r in fixture["requests"]
            if r["method"] == "POST" and r["path"] == "/api/v1/scans"
        ]
        assert len(scans) == 1 and scans[0]["status"] == 202
        tasks = {
            r["path"]
            for r in fixture["requests"]
            if r["method"] == "GET" and r["path"].startswith("/api/v1/tasks/")
        }
        assert len(tasks) == 1
        value = result["verified"]
        assert fixture["measurements"][-1]["client"] == value
        assert value["visited_indexes"] == list(range(500)) and value["frame_count"] > 0
        scroll = [s for s in value["samples"] if s["phase"] == "scroll"]
        assert len(scroll) == value["gestures"]
        assert all(
            0 <= scroll[i]["index"] - scroll[i - 1]["index"] <= 1
            for i in range(1, len(scroll))
        )
        assert scroll[-1]["index"] == 499
        pages = read(folder / "pages-projection.json")
        long = {
            row["ordinal"]: row for row in pages if row["pack_id"] == value["long_pack"]
        }
        large = {
            row["ordinal"]: row
            for row in pages
            if row["pack_id"] == value["large_pack"]
        }
        assert set(long) == set(range(500)) and set(large) == {0, 1, 2}
        assert all(
            p["relative_path"] == f"{i + 1}.png"
            and p["width"] == 240
            and p["height"] == 360
            and p["error"] is None
            for i, p in long.items()
        )
        for s in value["samples"]:
            assert s["metadata"] <= 120 and s["providers"] <= 6
            assert s["estimated_bytes"] <= 48 * 1024 * 1024
            assert s["window"][0] <= s["index"] <= s["window"][1]
            assert s["window"][1] - s["window"][0] + 1 <= 120
            row = (long if s["pack_id"] == value["long_pack"] else large)[s["index"]]
            assert s["page_id"] == row["id"]
            assert s["source_dimensions"] == [row["width"], row["height"]]
            assert s["decoded"] and all(0 < w * h <= 2105000 for w, h in s["decoded"])
        shown = {
            s["index"] for s in value["samples"] if s["pack_id"] == value["long_pack"]
        }
        assert shown == set(range(500))
        assert len(value["large_frames"]) == 9
        assert [s["index"] for s in value["large_frames"]] == [0, 1, 2] * 3
        assert {tuple(s["source_dimensions"]) for s in value["large_frames"]} == {
            (4000, 6000),
            (6000, 4000),
            (8000, 8000),
        }
        for page in list(long.values()) + list(large.values()):
            requests = [
                r
                for r in fixture["requests"]
                if r["path"] == f"/api/v1/pages/{page['id']}/image"
                and r["method"] == "GET"
                and r.get("status") == 200
                and r["bytes"] > 0
            ]
            assert requests, page["ordinal"]
        preferences = read(folder / "preferences-projection.json")
        assert {row["pack_id"] for row in preferences} == {
            value["long_pack"],
            value["large_pack"],
        }
        assert all(row["mode"] == "vertical" for row in preferences)
        database = read(folder / "database-proof.json")
        assert {row[0] for row in database["progress"]} == {
            value["long_pack"],
            value["large_pack"],
        }
        progress = next(
            row for row in database["progress"] if row[0] == value["long_pack"]
        )
        assert progress[1] == value["last_page_id"] == long[499]["id"]
        assert {row[1] for row in database["recent"]} == {
            value["long_pack"],
            value["large_pack"],
        }
        for name in SCENES:
            png = (folder / (name + ".png")).read_bytes()
            assert png[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(
                ">II", png[16:24]
            ) == (
                1170,
                2532,
            )
            assert (
                "io.github.shijijs.video_viewer"
                in (folder / (name + "-window.txt")).read_text()
            )
        recordings = read(folder / "recordings.json")
        assert recordings
        probes = read(folder / "recordings-probe.json")
        assert {p["file"] for p in probes} == {p["file"] for p in recordings}
        for probe in probes:
            video = next(s for s in probe["streams"] if s.get("codec_name") == "h264")
            assert video["width"] == 390 and video["height"] == 844
            assert (
                int(video["nb_frames"]) > 0 and float(probe["format"]["duration"]) > 0
            )
        for recording in recordings:
            path = folder / recording["file"]
            assert (
                path.stat().st_size == recording["bytes"]
                and sha(path) == recording["sha256"]
            )
        memory = [
            json.loads(line)
            for line in (folder / "memory-samples.jsonl").read_text().splitlines()
        ]
        assert len(memory) >= 10 and len({row["pid"] for row in memory}) == 1
        pss = [int(re.search(r"TOTAL PSS:\s*(\d+)", row["raw"])[1]) for row in memory]
        rss = [int(re.search(r"TOTAL RSS:\s*(\d+)", row["raw"])[1]) for row in memory]
        checkpoint_pss, checkpoint_rss = {}, {}
        for name in SCENES:
            raw = (folder / (name + "-memory.txt")).read_text()
            checkpoint_pss[name] = int(re.search(r"TOTAL PSS:\s*(\d+)", raw)[1])
            checkpoint_rss[name] = int(re.search(r"TOTAL RSS:\s*(\d+)", raw)[1])
        warnings = re.findall(r"READER_IMAGE_FAILURE (.*?): (.*)", text)
        for identity, error in warnings:
            assert identity in {p["id"] for p in pages}
            assert error.startswith(("SocketException:", "HttpException:"))
        reports.append(
            {
                "round": number,
                "gestures": value["gestures"],
                "first_frame_ms": value["first_frame_ms"],
                "scroll_ms": value["scroll_ms"],
                "observed_peaks": value["peaks"],
                "sampled_pss_kib": {"first": pss[0], "max": max(pss), "last": pss[-1]},
                "sampled_rss_kib_max": max(rss),
                "all_observed_pss_kib_max": max(*pss, *checkpoint_pss.values()),
                "all_observed_rss_kib_max": max(*rss, *checkpoint_rss.values()),
                "checkpoint_pss_kib": checkpoint_pss,
                "scan_wait_continuations": value["resumed_scan_waits"],
                "memory_samples": len(memory),
                "observed_image_requests_peak": fixture["peak_active_images"],
                "handled_image_warnings": warnings,
                "screens": len(SCENES),
                "recordings": len(recordings),
            }
        )
    for name, expected in shared_files.items():
        assert sha(ROOT / name) == expected, name
        blob = subprocess.check_output(["git", "show", source + ":" + name], cwd=ROOT)
        assert hashlib.sha256(blob).hexdigest() == expected, name
    print(
        json.dumps(
            {
                "verified": True,
                "source": source,
                "manifest_inputs": len(manifest),
                "rounds": reports,
                "target_phone_nas_performance_verified": False,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
