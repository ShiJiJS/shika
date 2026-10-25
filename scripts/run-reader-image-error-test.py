#!/usr/bin/env python3
"""Own one disposable 8764 fixture; retain the existing installed AVD."""

import argparse
import hashlib
import json
import sqlite3
import subprocess
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADB = ROOT / ".dev/android-sdk/platform-tools/adb"
parser = argparse.ArgumentParser()
parser.add_argument("--viewport", choices=("360", "390", "844"), required=True)
parser.add_argument("--scale", choices=("1", "2"), required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
base = ROOT / ".dev/reader-image-errors" / out.name
base.mkdir(parents=True, exist_ok=False)
for directory in ("data", "config", "packs"):
    (base / directory).mkdir()
(base / "config/passphrase").write_text("reader-image-errors-owned-only")
(base / "config/mounts.json").write_text(
    json.dumps(
        [{"id": "packs", "name": "Synthetic reader packs", "path": "/media/packs"}]
    )
)


def save(name, value):
    (out / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def run(*command):
    return subprocess.check_output(command, cwd=ROOT, text=True).strip()


def device(*command):
    return subprocess.check_output(
        [str(ADB), "-s", "emulator-5554", *command], timeout=20
    )


def shell(*command):
    return device("shell", *command).decode().strip()


def state(path="/state", post=False):
    req = urllib.request.Request(
        "http://127.0.0.1:8764/__reader_errors" + path,
        headers={"X-Fixture-Key": "reader-image-errors-owned-control"},
        method="POST" if post else "GET",
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.load(response)


def media():
    return {
        str(p.relative_to(base / "packs")): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted((base / "packs").rglob("*.png"))
    }


assert "device" in run(str(ADB), "-s", "emulator-5554", "get-state")
original = {name: shell("wm", name) for name in ("size", "density")}
font = shell("settings", "get", "system", "font_scale")
width, height = {"360": (360, 740), "390": (390, 844), "844": (844, 390)}[args.viewport]
container = None
stop, watcher_errors, screens = threading.Event(), [], []
started = time.monotonic()
source = run("git", "rev-parse", "HEAD")
paths = run(
    "git",
    "ls-files",
    "apps/mobile/lib",
    "services/server/video_viewer",
    "apps/mobile/integration_test/server_reader_image_error_test.dart",
    "services/server/tests/reader_image_error_fixture.py",
    "scripts/run-reader-image-error-test.py",
).splitlines()
paths = sorted(
    set(paths)
    | {
        "apps/mobile/integration_test/server_reader_image_error_test.dart",
        "services/server/tests/reader_image_error_fixture.py",
        "scripts/run-reader-image-error-test.py",
    }
)
source_files = {
    name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in paths
}


def watch():
    seen = set()
    try:
        while not stop.wait(0.15):
            current = state()
            name = current["display"]
            if not name or name in seen or current["ack"]:
                continue
            focus = "\n".join(
                row.strip()
                for row in shell("dumpsys", "window").splitlines()
                if "mCurrentFocus=" in row or "mFocusedApp=" in row
            )
            assert any(
                "mCurrentFocus=" in row and "io.github.shijijs.video_viewer" in row
                for row in focus.splitlines()
            )
            (out / (name + "-window.txt")).write_text(focus + "\n")
            (out / (name + ".png")).write_bytes(device("exec-out", "screencap", "-p"))
            screens.append(name)
            seen.add(name)
            state("/ack/" + name, post=True)
    except Exception as error:  # noqa: BLE001 - host proof reports the actual failure
        watcher_errors.append(repr(error))


try:
    container = run(
        "docker",
        "run",
        "-d",
        "--read-only",
        "--shm-size=64m",
        "--tmpfs",
        "/tmp:mode=1777",
        "--name",
        "video-viewer-reader-errors-" + str(time.time_ns()),
        "-p",
        "127.0.0.1:8764:8760",
        "-v",
        str(ROOT / "services/server") + ":/source:ro",
        "-v",
        str(base / "data") + ":/data",
        "-v",
        str(base / "config") + ":/fixture:ro",
        "-v",
        str(base / "packs") + ":/media/packs",
        "-w",
        "/source",
        "-e",
        "VV_READER_ERROR_FIXTURE=enabled",
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
        "tests.reader_image_error_fixture:create_reader_error_app",
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
            assert state()["fixture"] == "reader-errors-owned-8764"
            break
        except (urllib.error.URLError, ConnectionError):
            if time.monotonic() > deadline:
                raise
            time.sleep(0.2)
    before = media()
    assert len(before) == 6
    save("media-before.json", before)
    shell("wm", "size", f"{width * 3}x{height * 3}")
    shell("wm", "density", "480")
    shell("settings", "put", "system", "font_scale", args.scale)
    watcher = threading.Thread(target=watch, daemon=True)
    watcher.start()
    with (out / "flutter.log").open("w") as log:
        process = subprocess.run(
            [
                "bash",
                str(ROOT / "scripts/dev.sh"),
                "flutter",
                "test",
                "integration_test/server_reader_image_error_test.dart",
                "--no-uninstall",
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
    assert process.returncode == 0 and not watcher_errors
    assert len(screens) == 6
    after = media()
    save("media-after.json", after)
    assert before == after
    text = (out / "flutter.log").read_text()
    verified = json.loads(
        next(
            row.split("READER_ERRORS_VERIFIED:", 1)[1]
            for row in text.splitlines()
            if "READER_ERRORS_VERIFIED:" in row
        )
    )
    db_file = base / "data/library.sqlite3"
    with sqlite3.connect(db_file.as_uri() + "?mode=ro", uri=True) as db:
        assert (
            db.execute(
                "SELECT count(*) FROM pack_progress WHERE pack_id=?",
                (verified["failed_pack"],),
            ).fetchone()[0]
            == 0
        )
        assert db.execute(
            "SELECT pack_id FROM recent_entries WHERE kind='pack'"
        ).fetchall() == [(verified["good_pack"],)]
        assert (
            db.execute(
                "SELECT count(*) FROM pack_progress WHERE pack_id=?",
                (verified["good_pack"],),
            ).fetchone()[0]
            == 1
        )
    save("database-proof.json", verified)
    save(
        "result.json",
        {
            "exit_code": 0,
            "source": source,
            "source_files": source_files,
            "screens": screens,
            "viewport": [width, height],
            "scale": int(args.scale),
            "elapsed_seconds": round(time.monotonic() - started, 2),
            "verified": verified,
        },
    )
    print(json.dumps({"passed": True, "screens": len(screens)}))
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
            "after": {name: shell("wm", name) for name in ("size", "density")},
            "font_before": font,
            "font_after": shell("settings", "get", "system", "font_scale"),
            "watcher_errors": watcher_errors,
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
