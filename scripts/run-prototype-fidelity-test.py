#!/usr/bin/env python3
"""Capture the actual AVD against public reference media on an owned 8768."""

import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

from video_probe_pixels import inspect as inspect_video_frame

ROOT = Path(__file__).resolve().parents[1]
ADB = ROOT / ".dev/android-sdk/platform-tools/adb"
p = argparse.ArgumentParser()
p.add_argument("--output", type=Path, required=True)
p.add_argument("--reference-input", type=Path, required=True)
p.add_argument("--height", type=int, default=905)
p.add_argument("--width", type=int, default=390)
p.add_argument("--scale", choices=("1", "2"), default="1")
p.add_argument("--expected-columns", choices=(2, 4), type=int, default=2)
p.add_argument(
    "--scenario",
    choices=("fidelity", "continuation", "counts", "presentation", "cards", "video-order", "recent", "reader", "preview", "settings", "preview-lifecycle", "preview-stability", "video-tag-definitions"),
    default="fidelity",
)
args = p.parse_args()
scenes = {
    "video-tag-definitions": ["tagdef-video", "tagdef-create-keyboard", "tagdef-create-conflict", "tagdef-created", "tagdef-rename-conflict", "tagdef-rename-failure", "tagdef-renamed", "tagdef-pack", "tagdef-remove-confirm", "tagdef-remove-cancel", "tagdef-remove-failure", "tagdef-removed", "tagdef-reopened", "tagdef-pack-final", "tagdef-library"],
    "preview-stability": ["stability-library", "stability-filter", "stability-preview", "stability-editor", "stability-saved", "stability-readback", "stability-added", "stability-frozen-queue", "stability-return", "stability-second-preview", "stability-tag-deleted", "stability-second-queue", "stability-empty", "stability-cleared"],
    "preview-lifecycle": ["lifecycle-library", "lifecycle-playing", "lifecycle-paused", "lifecycle-fullscreen-paused", "lifecycle-fullscreen-playing", "lifecycle-device-levels", "lifecycle-boost", "lifecycle-fullscreen-recovered", "lifecycle-inline-restored", "lifecycle-inline-recovered", "lifecycle-swipes", "lifecycle-preload-off", "lifecycle-single-decoder", "lifecycle-single-swiped", "lifecycle-return"],
    "settings": ["settings-home", "settings-connection", "settings-connection-keyboard", "settings-connection-invalid", "settings-roots", "settings-scan-details", "settings-root-add", "settings-root-keyboard", "settings-root-invalid", "settings-root-edit", "settings-root-conflict", "settings-playback", "settings-playback-draft", "settings-reader", "settings-reader-draft", "settings-reader-saved", "settings-reader-restored", "settings-dark", "settings-dark-roots", "settings-dark-reader", "settings-return"],
    "preview": ["preview-library", "preview-filter", "preview-preview", "preview-filter-return", "preview-paused", "preview-seek", "preview-speed-menu", "preview-boost", "preview-quick", "preview-tags", "preview-more", "preview-details", "preview-dark", "preview-light", "preview-queue", "preview-queue-bottom", "preview-last", "preview-end", "preview-return", "preview-recent"],
    "reader": ["reader-paged", "reader-overview", "reader-jump", "reader-settings", "reader-vertical", "reader-strip-scroll", "reader-immersive", "reader-restored", "reader-range", "reader-quick", "reader-quick-exit", "reader-return", "reader-reopen"],
    "recent": [
        "recent-empty-video", "recent-empty-pack", "recent-keyboard-video", "recent-video-one",
        "recent-video-preview", "recent-video-queue", "recent-video-two",
        "recent-video-error", "recent-video-retry", "recent-keyboard-pack", "recent-packs-two",
        "recent-pack-reader", "recent-pack-range", "recent-pack-return",
        "recent-pack-error", "recent-pack-retry", "recent-isolation",
    ],
    "video-order": [
        "video-order-library", "video-order-filter", "video-order-preview",
        "video-order-filter-return", "video-order-queue", "video-order-last",
        "video-order-return", "video-order-recent",
    ],
    "fidelity": [
        "home",
        "packs",
        "video-tags",
        "pack-tags",
        "settings",
        "settings-bottom",
        "dark",
        "dark-bottom",
    ],
    "continuation": [
        "continue-empty",
        "continue-read",
        "continue-library",
        "continue-reader",
        "continue-return",
        "continue-scope",
        "continue-multi",
        "continue-error",
        "continue-retry",
        "continue-recent",
    ],
    "cards": [
        "cards-video",
        "cards-video-meta",
        "cards-packs",
        "cards-pack-meta",
        "cards-filter",
        "cards-return",
    ],
    "presentation": [
        "presentation-library",
        "presentation-author",
        "presentation-title",
        "presentation-reader",
        "presentation-details",
        "presentation-return",
        "presentation-newest",
        "presentation-queue",
        "presentation-back",
        "presentation-recent",
    ],
    "counts": [
        "counts-home",
        "counts-packs",
        "counts-filter",
        "counts-tags",
        "counts-recent",
        "counts-trash",
        "counts-restore",
        "counts-error",
        "counts-retry",
    ],
}[args.scenario]
integration_file = {
    "video-tag-definitions": "server_video_tag_definitions_test.dart",
    "preview-stability": "server_preview_state_stability_test.dart",
    "preview-lifecycle": "server_preview_lifecycle_test.dart",
    "settings": "server_settings_panels_test.dart",
    "preview": "server_preview_panels_test.dart",
    "reader": "server_reader_chrome_test.dart",
    "recent": "server_recent_history_test.dart",
    "video-order": "server_video_name_order_test.dart",
    "fidelity": "prototype_fidelity_test.dart",
    "continuation": "server_pack_continuation_test.dart",
    "counts": "server_catalog_counts_test.dart",
    "presentation": "server_pack_presentation_test.dart",
    "cards": "server_catalog_cards_test.dart",
}[args.scenario]

out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
base = ROOT / ".dev/prototype-fidelity" / out.name
base.mkdir(parents=True, exist_ok=False)
for name in ("config", "data", "videos", "packs"):
    (base / name).mkdir()
source = args.reference_input.resolve()
assert len(list((source / "raster").glob("*.png"))) == 24
shutil.copyfile(source / "packs.json", base / "config/packs.json")
shutil.copytree(source / "raster", base / "config/raster")
(base / "config/passphrase").write_text("prototype-fidelity-owned-only")
(base / "config/mounts.json").write_text(
    json.dumps(
        [
            {"id": "videos", "name": "短视频", "path": "/media/videos"},
            {"id": "packs", "name": "图包", "path": "/media/packs"},
        ]
    )
)


def run(*cmd):
    return subprocess.check_output(cmd, cwd=ROOT, text=True).strip()


def device(*cmd):
    return subprocess.check_output([str(ADB), "-s", "emulator-5554", *cmd], timeout=20)


def shell(*cmd):
    return device("shell", *cmd).decode().strip()


def save(name, value):
    (out / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def state(path="/state", post=False):
    req = urllib.request.Request(
        "http://127.0.0.1:8768/__fidelity" + path,
        headers={"X-Fixture-Key": "prototype-fidelity-owned-control"},
        method="POST" if post else "GET",
    )
    with urllib.request.urlopen(req, timeout=120) as response:
        return json.load(response)


def media():
    return {
        str(f.relative_to(base)): hashlib.sha256(f.read_bytes()).hexdigest()
        for name in ("packs", "videos")
        for f in sorted((base / name).rglob("*"))
        if f.is_file()
    }


original = {name: shell("wm", name) for name in ("size", "density")}
font = shell("settings", "get", "system", "font_scale")
save("original-viewport.json", {"display":original, "font":font})
if args.scenario in {"preview-lifecycle", "video-tag-definitions"}:
    assert shell("getprop", "ro.boot.qemu.avd_name") == "video_viewer_api_36"
    assert shell("getprop", "sys.boot_completed") == "1"
    save("environment.json", {
        "avd": shell("getprop", "ro.boot.qemu.avd_name"),
        "api": shell("getprop", "ro.build.version.sdk"),
        "abi": shell("getprop", "ro.product.cpu.abi"),
        "emulator_process": [line for line in run("ps", "-axo", "command").splitlines() if "qemu-system-aarch64" in line and "-avd video_viewer_api_36" in line],
        "renderer_override": False,
        "host_avc_decoder": shell("getprop", "ro.boot.qemu.hwcodec.avcdec"),
        "host_vpx_decoder": shell("getprop", "ro.boot.qemu.hwcodec.vpxdec"),
    })
container = None
stop = threading.Event()
errors, screens = [], []
actions, recordings = [], []
video_frames = {}
landscape_video_states = {"lifecycle-fullscreen-paused", "lifecycle-fullscreen-playing", "lifecycle-device-levels", "lifecycle-boost", "lifecycle-fullscreen-recovered"}
record_process = record_path = record_shape = None
paths = run(
    "git", "ls-files", "apps/mobile/lib", "apps/mobile/android", "apps/mobile/assets", "services/server/video_viewer"
).splitlines()
paths += [
    "apps/mobile/pubspec.yaml",
    "apps/mobile/pubspec.lock",
    "scripts/start-android-emulator.sh",
    "scripts/video_probe_pixels.py",
    "apps/mobile/integration_test/video_render_probe_test.dart",
    "apps/mobile/integration_test/prototype_fidelity_test.dart",
    "apps/mobile/integration_test/server_pack_continuation_test.dart",
    "apps/mobile/integration_test/server_catalog_counts_test.dart",
    "apps/mobile/integration_test/server_pack_presentation_test.dart",
    "apps/mobile/integration_test/server_catalog_cards_test.dart",
    "apps/mobile/integration_test/server_video_name_order_test.dart",
    "apps/mobile/integration_test/server_recent_history_test.dart",
    "apps/mobile/integration_test/server_reader_chrome_test.dart",
    "apps/mobile/integration_test/server_preview_panels_test.dart",
    "apps/mobile/integration_test/server_preview_lifecycle_test.dart",
    "apps/mobile/integration_test/server_preview_state_stability_test.dart",
    "apps/mobile/integration_test/server_video_tag_definitions_test.dart",
    "apps/mobile/test/viewer_return_counts_test.dart",
    "apps/mobile/integration_test/server_settings_panels_test.dart",
    "apps/mobile/integration_test/server_connection_test.dart",
    "apps/mobile/integration_test/server_defaults_test.dart",
    "apps/mobile/integration_test/server_roots_missing_test.dart",
    "services/server/tests/prototype_fidelity_fixture.py",
    "scripts/run-prototype-fidelity-test.py",
]
prototype = run("git", "ls-tree", "HEAD", "design/reference/library-first").split()
save(
    "source.json",
    {
        "commit": run("git", "rev-parse", "HEAD"),
        "files": {
            path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
            for path in paths
        },
        "prototype_tree": prototype[2] if prototype else None,
    },
)


def end_recording():
    global record_process, record_path, record_shape
    if record_process is None:
        return
    if record_process.poll() is None:
        pid = shell("pidof", "screenrecord").split()
        if len(pid) != 1:
            raise RuntimeError("Expected exactly our screenrecord process")
        shell("kill", "-2", pid[0])
    record_process.wait(timeout=15)
    filename = f"gesture-{len(recordings)+1:02d}.mp4"
    device("pull", record_path, str(out / filename))
    path = out / filename
    assert path.stat().st_size > 1000
    recordings.append({"file": filename, "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "shape": record_shape})
    shell("rm", record_path)
    record_process = record_path = record_shape = None


def begin_recording(shape):
    global record_process, record_path, record_shape
    existing = subprocess.run([str(ADB), "-s", "emulator-5554", "shell", "pidof", "screenrecord"], capture_output=True, text=True, check=False)
    if existing.stdout.strip():
        raise RuntimeError("Preserve an existing screenrecord")
    record_shape = shape
    record_path = f"/sdcard/preview-lifecycle-{time.time_ns()}.mp4"
    record_process = subprocess.Popen([str(ADB), "-s", "emulator-5554", "shell", "screenrecord", "--size", shape, "--bit-rate", "1000000", "--time-limit", "180", record_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def watch():
    try:
        while not stop.wait(0.15):
            current = state()
            name = current["display"]
            if not name or current["ack"]:
                continue
            if args.scenario == "preview-lifecycle" and name.startswith("lifecycle-device-") and name != "lifecycle-device-levels":
                if name == "lifecycle-device-home":
                    command = ["input", "keyevent", "3"]
                elif name == "lifecycle-device-foreground":
                    command = ["am", "start", "-n", "io.github.shijijs.video_viewer/.MainActivity"]
                elif name == "lifecycle-device-back":
                    command = ["input", "keyevent", "4"]
                else:
                    raise RuntimeError("Unknown device action " + name)
                response = shell(*command)
                actions.append({"name": name, "command": command, "response": response, "time": time.time(), "window": shell("dumpsys", "window")})
                save("device-actions.json", actions)
                state("/ack/" + name, post=True)
                continue
            if name in screens:
                continue
            assert name in scenes
            window = "\n".join(
                line.strip()
                for line in shell("dumpsys", "window").splitlines()
                if "mCurrentFocus=" in line or "mFocusedApp=" in line
            )
            assert any(
                "mCurrentFocus=" in line and "io.github.shijijs.video_viewer" in line
                for line in window.splitlines()
            )
            (out / (name + "-window.txt")).write_text(window + "\n")
            png = device("exec-out", "screencap", "-p")
            (out / (name + ".png")).write_bytes(png)
            if args.scenario == "preview-lifecycle" and name in landscape_video_states:
                frame = inspect_video_frame(out / (name + ".png"))
                video_frames[name] = frame
                save("video-frames.json", video_frames)
                assert frame["longest_green_run"] == 0 and frame["sampled_distinct_colors"] > 1000, frame
            if args.scenario == "preview-lifecycle":
                width, height = struct.unpack(">II", png[16:24])
                shape = "844x390" if width > height else "390x844"
                if record_process is not None and (record_shape != shape or record_process.poll() is not None or name == "lifecycle-fullscreen-recovered"):
                    end_recording()
                if record_process is None and name != "lifecycle-return":
                    begin_recording(shape)
                (out / (name + "-memory.txt")).write_text(shell("dumpsys", "meminfo", "io.github.shijijs.video_viewer"))
            screens.append(name)
            state("/ack/" + name, post=True)
    except Exception as error:  # noqa: BLE001 - persisted as evidence
        errors.append(repr(error))


try:
    container = run(
        "docker",
        "run",
        "-d",
        "--read-only",
        "--shm-size=256m",
        "--tmpfs",
        "/tmp:mode=1777",
        "--name",
        "video-viewer-prototype-fidelity-" + str(time.time_ns()),
        "-p",
        "127.0.0.1:8768:8760",
        "-v",
        str(ROOT / "services/server") + ":/source:ro",
        "-v",
        str(ROOT / "apps/mobile/assets/media") + ":/public:ro",
        "-v",
        str(base / "config") + ":/fixture:ro",
        "-v",
        str(base / "data") + ":/data",
        "-v",
        str(base / "packs") + ":/media/packs",
        "-v",
        str(base / "videos") + ":/media/videos",
        "-w",
        "/source",
        "-e",
        "VV_FIDELITY_FIXTURE=enabled",
        "-e",
        "VV_FIDELITY_PREVIEW_LIFECYCLE=" + ("enabled" if args.scenario == "preview-lifecycle" else "disabled"),
        "-e",
        "VV_FIDELITY_PREVIEW_MUTATION=" + ("enabled" if args.scenario == "preview-stability" else "disabled"),
        "-e",
        "VV_FIDELITY_TAG_DEFINITIONS=" + ("enabled" if args.scenario == "video-tag-definitions" else "disabled"),
        "-e",
        "VV_PASSPHRASE_FILE=/fixture/passphrase",
        "-e",
        "VV_MOUNTS_FILE=/fixture/mounts.json",
        "-e",
        "VV_SCAN_INTERVAL=0",
        "-e",
        "VV_STABILITY_SECONDS=0",
        "--entrypoint",
        "uvicorn",
        "video-viewer-server:e2e",
        "tests.prototype_fidelity_fixture:create_fidelity_app",
        "--factory",
        "--host",
        "0.0.0.0",
        "--port",
        "8760",
        "--no-access-log",
    )
    save("runtime.json", json.loads(run("docker", "inspect", container)))
    deadline = time.monotonic() + 40
    while True:
        try:
            assert state()["fixture"] == "prototype-fidelity-owned-8768"
            break
        except (urllib.error.URLError, ConnectionError):
            if time.monotonic() > deadline:
                raise
            time.sleep(0.2)
    save("prepared.json", state("/prepare", post=True))
    if args.scenario == "preview-stability":
        rejected = urllib.request.Request(
            "http://127.0.0.1:8768/__fidelity/add-public-video",
            method="POST",
            headers={"X-Fixture-Key": "not-the-owned-fixture-key"},
        )
        try:
            urllib.request.urlopen(rejected, timeout=20)
            raise AssertionError("Public addition accepted an invalid fixture key")
        except urllib.error.HTTPError as error:
            assert error.code == 403
            save("control-guard.json", {"invalid_key_status": error.code, "files_before_authorized_addition": len(media())})
    if args.scenario == "video-tag-definitions":
        rejected = urllib.request.Request(
            "http://127.0.0.1:8768/__fidelity/tag-definition-failure/rename",
            method="POST", headers={"X-Fixture-Key": "not-the-owned-fixture-key"},
        )
        try:
            urllib.request.urlopen(rejected, timeout=20)
            raise AssertionError("Tag failure control accepted an invalid fixture key")
        except urllib.error.HTTPError as error:
            assert error.code == 403
            save("control-guard.json", {"invalid_key_status": error.code, "mode_after": state()["tag_definition_failure"]})
    before = media()
    assert len(before) == (27 if args.scenario == "preview-lifecycle" else 26)
    save("media-before.json", before)
    shell("wm", "size", f"{args.width * 3}x{args.height * 3}")
    shell("wm", "density", "480")
    shell("settings", "put", "system", "font_scale", args.scale)
    watcher = threading.Thread(target=watch, daemon=True)
    watcher.start()
    with (out / "flutter.log").open("w") as log:
        result = subprocess.run(
            [
                "bash",
                str(ROOT / "scripts/dev.sh"),
                "flutter",
                "test",
                "integration_test/" + integration_file,
                "--no-uninstall",
                f"--dart-define=GRID_COLUMNS={args.expected_columns}",
                "-d",
                "emulator-5554",
                "--reporter",
                "expanded",
            ],
            cwd=ROOT / "apps/mobile",
            stdout=log,
            stderr=subprocess.STDOUT,
            timeout=480,
            check=False,
        )
    end_recording()
    save("recordings.json", recordings)
    save("fixture-final.json", state())
    save("requests.json", state()["requests"])
    log = (out / "flutter.log").read_text()
    metrics = [
        json.loads(row.split("FIDELITY_METRICS:", 1)[1])
        for row in log.splitlines()
        if "FIDELITY_METRICS:" in row
    ]
    save("metrics.json", metrics)
    assert (
        result.returncode == 0 and "PROTOTYPE_FIDELITY_VERIFIED" in log and not errors
    )
    assert screens == scenes and len(metrics) == len(scenes)
    if args.scenario == "preview-lifecycle":
        assert set(video_frames) == landscape_video_states
    after = media()
    save("media-after.json", after)
    if args.scenario == "preview-stability":
        (addition,) = state()["public_additions"]
        expected = {**before, addition["file"]: addition["sha256"]}
        assert addition["file"] == "videos/外部新增/晨光新视频.mp4"
        assert addition["file"] not in before
        assert addition["sha256"] == hashlib.sha256((ROOT / "apps/mobile/assets/media/flower-landscape.mp4").read_bytes()).hexdigest()
        assert after == expected
    else:
        assert before == after
    save(
        "result.json",
        {
            "passed": True,
            "screens": screens,
            "window": [args.width, args.height],
            "scale": args.scale,
            "scenario": args.scenario,
            "known_video_frame_checks": len(video_frames),
        },
    )
    print(json.dumps({"passed": True, "screens": screens, "output": str(out)}))
finally:
    stop.set()
    if "watcher" in globals():
        watcher.join(timeout=12)
    try:
        end_recording()
    except Exception as error:  # noqa: BLE001 - continue device/container cleanup
        errors.append("recording cleanup: " + repr(error))
        save("recording-cleanup-error.json", {"error":repr(error)})
    save("recordings.json", recordings)
    try:
        for name in ("size", "density"):
            value = original[name]
            shell(
                "wm",
                name,
                value.split("Override " + name + ":")[-1].strip()
                if "Override " in value
                else "reset",
            )
        shell("settings", "put", "system", "font_scale", font)
        save(
            "restored-viewport.json",
            {
                "before": original,
                "after": {name: shell("wm", name) for name in original},
                "font_before": font,
                "font_after": shell("settings", "get", "system", "font_scale"),
                "errors": errors,
            },
        )
    except Exception as exc:
        save("restore-error.json", {"before": original, "font_before": font, "error": str(exc), "errors": errors})
        raise
    finally:
        if container:
            (out / "server.log").write_text(
                subprocess.run(
                    ["docker", "logs", container],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    check=False,
                ).stdout
            )
            run("docker", "rm", "-f", container)
