#!/usr/bin/env python3
"""Capture the actual AVD against public reference media on an owned 8768."""

import argparse
import hashlib
import json
import shutil
import subprocess
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

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
    choices=("fidelity", "continuation", "counts", "presentation", "cards", "video-order", "recent", "reader"),
    default="fidelity",
)
args = p.parse_args()
scenes = {
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
container = None
stop = threading.Event()
errors, screens = [], []
paths = run(
    "git", "ls-files", "apps/mobile/lib", "services/server/video_viewer"
).splitlines()
paths += [
    "apps/mobile/integration_test/prototype_fidelity_test.dart",
    "apps/mobile/integration_test/server_pack_continuation_test.dart",
    "apps/mobile/integration_test/server_catalog_counts_test.dart",
    "apps/mobile/integration_test/server_pack_presentation_test.dart",
    "apps/mobile/integration_test/server_catalog_cards_test.dart",
    "apps/mobile/integration_test/server_video_name_order_test.dart",
    "apps/mobile/integration_test/server_recent_history_test.dart",
    "apps/mobile/integration_test/server_reader_chrome_test.dart",
    "services/server/tests/prototype_fidelity_fixture.py",
    "scripts/run-prototype-fidelity-test.py",
]
save(
    "source.json",
    {
        "commit": run("git", "rev-parse", "HEAD"),
        "files": {
            path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
            for path in paths
        },
        "prototype_tree": run(
            "git", "rev-parse", "HEAD:design/reference/library-first"
        ),
    },
)


def watch():
    try:
        while not stop.wait(0.15):
            current = state()
            name = current["display"]
            if not name or current["ack"] or name in screens:
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
            (out / (name + ".png")).write_bytes(device("exec-out", "screencap", "-p"))
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
    before = media()
    assert len(before) == 26
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
    after = media()
    save("media-after.json", after)
    assert before == after
    save(
        "result.json",
        {
            "passed": True,
            "screens": screens,
            "window": [args.width, args.height],
            "scale": args.scale,
            "scenario": args.scenario,
        },
    )
    print(json.dumps({"passed": True, "screens": screens, "output": str(out)}))
finally:
    stop.set()
    if "watcher" in globals():
        watcher.join(timeout=12)
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
