#!/usr/bin/env python3
"""Read-only history UI proof against owned 8763 and already-running AVD."""

import argparse
import hashlib
import json
import subprocess
import threading
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "io.github.shijijs.video_viewer"
ADB = ROOT / ".dev/android-sdk/platform-tools/adb"
parser = argparse.ArgumentParser()
parser.add_argument("--viewport", choices=("360", "390"), required=True)
parser.add_argument("--scale", choices=("1", "2"), required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)


def control(path, method="GET"):
    req = urllib.request.Request(
        "http://127.0.0.1:8763/__history_fixture" + path,
        headers={"X-Fixture-Key": "history-purge-isolated-control"},
        method=method,
    )
    with urllib.request.urlopen(req, timeout=20) as response:
        return json.load(response)


def save(name, value):
    (out / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def device(*command):
    return subprocess.check_output(
        [str(ADB), "-s", "emulator-5554", *command], timeout=20
    )


def shell(*command):
    return device("shell", *command).decode().strip()


def focus():
    raw = shell("dumpsys", "window")
    return "\n".join(
        row.strip()
        for row in raw.splitlines()
        if "mCurrentFocus=" in row or "mFocusedApp=" in row
    )


def hashes(paths, base):
    return {
        str(p.relative_to(base)): {
            "bytes": p.stat().st_size,
            "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
        }
        for p in sorted(paths)
        if p.is_file()
    }


def media():
    base = ROOT / ".dev/history-purge-app/media"
    return hashes(base.rglob("*"), base)


def history_files():
    base = ROOT / ".dev/history-purge-app/data"
    files = set()
    for index in base.rglob("index.sqlite3"):
        files.update(index.parent.glob("*.sqlite3"))
    assert files, "No completed original history graph found"
    return hashes(files, base)


assert control("/status")["fixture"] == "purge-history-owned-8763"
control("/reset", "POST")
setup = control("/setup")
save("setup.json", setup)
before_trace = control("/trace")["items"]
before_media, before_history = media(), history_files()
assert len(before_media) == setup["source_files_expected"]
save("media-before.json", before_media)
save("history-before.json", before_history)
original = {n: shell("wm", n) for n in ("size", "density")}
font = shell("settings", "get", "system", "font_scale")
source = subprocess.check_output(
    ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
).strip()
tracked = subprocess.check_output(
    [
        "git",
        "ls-files",
        "apps/mobile/lib",
        "services/server/video_viewer",
        "apps/mobile/integration_test/server_purge_history_test.dart",
        "services/server/tests/history_purge_app_fixture.py",
        "scripts/run-history-purge-app-test.py",
    ],
    cwd=ROOT,
    text=True,
).splitlines()
# Include newly authored harness files during development; final evidence also
# checks them against the fixed Git commit.
tracked = sorted(
    set(tracked)
    | {
        "apps/mobile/integration_test/server_purge_history_test.dart",
        "services/server/tests/history_purge_app_fixture.py",
        "scripts/run-history-purge-app-test.py",
    }
)
source_files = {
    name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in tracked
}
stop = threading.Event()
errors = []
screens = []


def watch():
    seen = set()
    try:
        while not stop.wait(0.2):
            state = control("/status")
            name = state["display"]
            if not name or name in seen or state["display_ack"]:
                continue
            actual = focus()
            assert any(
                "mCurrentFocus=" in row and PACKAGE in row
                for row in actual.splitlines()
            ), actual
            (out / (name + "-window.txt")).write_text(actual + "\n")
            (out / (name + ".png")).write_bytes(device("exec-out", "screencap", "-p"))
            screens.append(name)
            seen.add(name)
            control("/ack/" + name, "POST")
    except Exception as error:  # noqa: BLE001 - surfaced by the main acceptance assertion
        errors.append(repr(error))


watcher = threading.Thread(target=watch, daemon=True)
started = time.monotonic()
try:
    width, height = (360, 740) if args.viewport == "360" else (390, 844)
    shell("wm", "size", f"{width * 3}x{height * 3}")
    shell("wm", "density", "480")
    shell("settings", "put", "system", "font_scale", args.scale)
    watcher.start()
    command = [
        "bash",
        str(ROOT / "scripts/dev.sh"),
        "flutter",
        "test",
        "integration_test/server_purge_history_test.dart",
        "--no-uninstall",
        "-d",
        "emulator-5554",
        "--reporter",
        "expanded",
    ]
    with (out / "flutter.log").open("w") as log:
        result = subprocess.run(
            command,
            cwd=ROOT / "apps/mobile",
            stdout=log,
            stderr=subprocess.STDOUT,
            timeout=660,
            check=False,
        )
    assert result.returncode == 0, "Actual Android history test failed; see flutter.log"
    assert not errors, errors
    assert len(screens) == 7, screens
    log = (out / "flutter.log").read_text()
    marker = next(
        row.split("HISTORY_PURGE_VERIFIED:", 1)[1]
        for row in log.splitlines()
        if "HISTORY_PURGE_VERIFIED:" in row
    )
    verified = json.loads(marker)
    assert (
        verified["graph_id"] == setup["graph_id"]
        and verified["purge_id"] == setup["purge_id"]
    )
    after = control("/trace")["items"]
    assert after[: len(before_trace)] == before_trace
    requests = after[len(before_trace) :]
    save("requests.json", requests)
    writes = [v for v in requests if v["method"] != "GET"]
    assert (
        sum(v["method"] == "POST" and v["path"] == "/api/v1/auth/login" for v in writes)
        == 1
    )
    assert all(
        v["method"] == "POST" and v["path"] in ("/api/v1/auth/login", "/api/v1/scan")
        for v in writes
    ), writes
    history_reads = [
        v for v in requests if v["path"].startswith("/api/v1/management-history/tasks/")
    ]
    assert history_reads and all(
        v["query"].get("graph_id") == setup["graph_id"]
        for v in history_reads
        if not v["path"].endswith("/tasks")
    )
    failures = [v for v in history_reads if v["status"] == 503]
    assert (
        len(failures) == 1
        and failures[0]["path"].endswith("/purge-pages")
        and failures[0]["query"]["offset"] == "24"
    )
    failed_at = requests.index(failures[0])
    assert any(
        v["path"] == failures[0]["path"]
        and v["query"] == failures[0]["query"]
        and v["status"] == 200
        for v in requests[failed_at + 1 :]
    )
    assert any(
        v["path"].endswith("/purge-review") and v["query"].get("offset") == "24"
        for v in history_reads
    )
    assert any(
        v["path"].endswith("/purge-review/files") and v["query"].get("offset") == "100"
        for v in history_reads
    )
    after_media, after_history = media(), history_files()
    save("media-after.json", after_media)
    save("history-after.json", after_history)
    assert after_media == before_media and after_history == before_history
    save(
        "result.json",
        {
            "source": source,
            "source_files": source_files,
            "viewport": [width, height],
            "scale": int(args.scale),
            "elapsed_seconds": round(time.monotonic() - started, 2),
            "exit_code": 0,
            "verified": verified,
            "screens": screens,
        },
    )
    print(
        json.dumps(
            {
                "passed": True,
                "screens": len(screens),
                "elapsed_seconds": round(time.monotonic() - started, 2),
            },
            ensure_ascii=False,
        )
    )
finally:
    stop.set()
    if watcher.is_alive():
        watcher.join(timeout=5)
    for name in ("size", "density"):
        value = next(
            (
                v.split(":", 1)[1].strip()
                for v in original[name].splitlines()
                if v.startswith("Override")
            ),
            "reset",
        )
        shell("wm", name, value)
    if font == "null":
        shell("settings", "delete", "system", "font_scale")
    else:
        shell("settings", "put", "system", "font_scale", font)
    save(
        "restored-viewport.json",
        {
            "before": original,
            "before_font": font,
            "after": {n: shell("wm", n) for n in ("size", "density")},
            "after_font": shell("settings", "get", "system", "font_scale"),
            "watcher_errors": errors,
        },
    )
