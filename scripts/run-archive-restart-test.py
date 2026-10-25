#!/usr/bin/env python3
"""Prove a real App force-stop, completed restore while absent, and new PID.

Uses only the already-running owned 8762 fixture and emulator-5554. No AVD
restart, SDK changes, pm clear, uninstall, NAS, or production service actions.
"""

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
parser.add_argument(
    "--phase",
    choices=("snapshot_written", "after_replace_before_commit", "restore_committed"),
    required=True,
)
parser.add_argument("--viewport", choices=("360", "390"), default="390")
parser.add_argument("--scale", choices=("1", "2"), default="1")
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)


def control(path, method="GET"):
    req = urllib.request.Request(
        "http://127.0.0.1:8762/__archive_fixture" + path,
        headers={"X-Fixture-Key": "archive-app-isolated-control"},
        method=method,
    )
    with urllib.request.urlopen(req, timeout=20) as response:
        return json.load(response)


def save(name, data):
    (out / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def device(*command):
    return subprocess.check_output(
        [str(ADB), "-s", "emulator-5554", *command], timeout=20
    )


def shell(*command):
    return device("shell", *command).decode().strip()


def pid():
    return subprocess.run(
        [str(ADB), "-s", "emulator-5554", "shell", "pidof", PACKAGE],
        check=False,
        capture_output=True,
        text=True,
        timeout=10,
    ).stdout.strip()


def media():
    base = ROOT / ".dev/archive-app/media"
    return {
        str(p.relative_to(base)): {
            "bytes": p.stat().st_size,
            "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
        }
        for p in sorted(base.rglob("*"))
        if p.is_file()
    }


def focus():
    raw = shell("dumpsys", "window")
    return "\n".join(
        v.strip()
        for v in raw.splitlines()
        if "mCurrentFocus=" in v or "mFocusedApp=" in v
    )


def screenshot(name):
    actual = focus()
    assert any("mCurrentFocus=" in v and PACKAGE in v for v in actual.splitlines()), (
        actual
    )
    (out / (name + "-window.txt")).write_text(actual + "\n")
    (out / (name + ".png")).write_bytes(device("exec-out", "screencap", "-p"))


events = []
errors = []
stop = threading.Event()
old = {n: shell("wm", n) for n in ("size", "density")}
old_font = shell("settings", "get", "system", "font_scale")
control("/release", "POST")
before_trace = control("/trace")["items"]
before_media = media()
save("media-before.json", before_media)
source = subprocess.check_output(
    ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
).strip()
source_files = {
    str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
    for p in (
        Path(__file__).resolve(),
        ROOT / "apps/mobile/integration_test/server_archive_restart_test.dart",
        ROOT / "services/server/tests/archive_app_fixture.py",
    )
}
started = time.monotonic()


def watch():
    seen = set()
    try:
        while not stop.wait(0.2):
            state = control("/status")
            name = state["display"]
            if not name or name in seen or state["display_ack"]:
                continue
            screenshot(name)
            save(name + "-status.json", state)
            events.append({"event": "screenshot", "name": name, "pid": pid()})
            seen.add(name)
            control("/ack/" + name, "POST")
    except Exception as error:  # noqa: BLE001 - propagate watcher failures to the main acceptance assertion
        errors.append(repr(error))


watcher = None
old_pid = None
verified = None
try:
    width, height = (360, 740) if args.viewport == "360" else (390, 844)
    shell("wm", "size", f"{width * 3}x{height * 3}")
    shell("wm", "density", "480")
    shell("settings", "put", "system", "font_scale", args.scale)
    watcher = threading.Thread(target=watch, daemon=True)
    watcher.start()
    resume_trace = None
    for phase in (0, 1):
        if phase:
            resume_trace = control("/trace")["items"]
            save("before-resume-requests.json", resume_trace[len(before_trace) :])
        command = [
            "bash",
            str(ROOT / "scripts/dev.sh"),
            "flutter",
            "test",
            "integration_test/server_archive_restart_test.dart",
            "--no-uninstall",
            "-d",
            "emulator-5554",
            "--reporter",
            "expanded",
            "--dart-define=ARCHIVE_RESTART_PHASE=" + args.phase,
        ]
        if phase:
            command.append("--dart-define=ARCHIVE_RESTART_RESUME=true")
        forced = False
        reopened = False
        with (out / f"phase-{phase}.log").open("w") as log:
            process = subprocess.Popen(
                command,
                cwd=ROOT / "apps/mobile",
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            timer = threading.Timer(480, process.kill)
            timer.start()
            try:
                for line in process.stdout:
                    log.write(line)
                    log.flush()
                    if "ARCHIVE_RESTART_" in line:
                        print(line.strip(), flush=True)
                    if "ARCHIVE_RESTART_STOP_READY:" in line:
                        assert phase == 0
                        original = json.loads(
                            line.split("ARCHIVE_RESTART_STOP_READY:", 1)[1]
                        )
                        state = control("/status")
                        save("before-stop-status.json", state)
                        assert (
                            state["hit"] == args.phase
                            and state["response_held"]
                            and state["request_id"] == original["request_id"]
                        )
                        assert state["task_id"] == state["original_task_id"]
                        old_pid = pid()
                        assert old_pid
                        shell("am", "force-stop", PACKAGE)
                        assert not pid()
                        events.append(
                            {
                                "event": "force-stop",
                                "old_pid": old_pid,
                                "absent": True,
                                "request_id": original["request_id"],
                            }
                        )
                        forced = True
                        control("/release", "POST")
                        deadline = time.monotonic() + 100
                        while True:
                            state = control("/status")
                            assert not pid(), (
                                "App resumed while restore should complete in its absence"
                            )
                            if state["task"]["status"] == "completed":
                                break
                            if time.monotonic() > deadline:
                                raise TimeoutError(
                                    "restore did not finish while App absent"
                                )
                            time.sleep(0.15)
                        assert state["epoch"] != json.loads(original["scope"])[2]
                        assert state["task"]["id"] == state["original_task_id"]
                        save("completed-while-absent.json", state)
                        events.append(
                            {
                                "event": "restore-completed",
                                "absent": not bool(pid()),
                                "task_id": state["task"]["id"],
                            }
                        )
                    if "ARCHIVE_RESTART_NEW_PROCESS" in line:
                        current = pid()
                        assert phase == 1 and current and current != old_pid
                        reopened = True
                        events.append(
                            {
                                "event": "new-process",
                                "old_pid": old_pid,
                                "new_pid": current,
                            }
                        )
                    if "ARCHIVE_RESTART_CANCEL_SAF" in line:
                        deadline = time.monotonic() + 30
                        while not any(
                            "mCurrentFocus=" in row
                            and "com.google.android.documentsui" in row
                            for row in focus().splitlines()
                        ):
                            if time.monotonic() > deadline:
                                raise TimeoutError(
                                    "real snapshot save chooser did not appear"
                                )
                            time.sleep(0.15)
                        (out / "snapshot-system-save-window.txt").write_text(
                            focus() + "\n"
                        )
                        (out / "snapshot-system-save.png").write_bytes(
                            device("exec-out", "screencap", "-p")
                        )
                        shell("input", "keyevent", "KEYCODE_BACK")
                        events.append(
                            {"event": "cancel-real-snapshot-save", "pid": pid()}
                        )
                    if "ARCHIVE_RESTART_VERIFIED:" in line:
                        verified = json.loads(
                            line.split("ARCHIVE_RESTART_VERIFIED:", 1)[1]
                        )
                code = process.wait(timeout=20)
            finally:
                timer.cancel()
                if process.poll() is None:
                    process.kill()
            events.append(
                {
                    "event": "runner",
                    "phase": phase,
                    "exit_code": code,
                    "intentional_stop": forced,
                }
            )
            if phase == 0:
                assert code != 0, "Forced runner unexpectedly reported success"
                assert forced and old_pid, "No verified force-stop reached"
            else:
                assert code == 0 and reopened and verified, (
                    "new process did not complete acceptance"
                )
    assert not errors, errors
    after = control("/trace")["items"]
    assert after[: len(before_trace)] == before_trace, (
        "Fixture trace changed unexpectedly"
    )
    assert resume_trace is not None
    assert after[: len(resume_trace)] == resume_trace
    resumed_requests = after[len(resume_trace) :]
    save("resumed-requests.json", resumed_requests)
    assert all(
        v["method"] == "GET" or (v["method"] == "POST" and v["path"] == "/api/v1/scan")
        for v in resumed_requests
    ), resumed_requests
    trace = after[len(before_trace) :]
    save("requests.json", trace)
    assert (
        sum(v["method"] == "POST" and v["path"] == "/api/v1/auth/login" for v in trace)
        == 1
    )
    assert (
        sum(
            v["method"] == "POST" and v["path"] == "/api/v1/management-backups/restores"
            for v in trace
        )
        == 1
    )
    assert any(
        v["method"] == "GET"
        and v["path"]
        == "/api/v1/management-backups/requests/restore/" + verified["request_id"]
        for v in trace
    )
    for value in verified["graphs"]:
        assert any(
            v["path"] == "/api/v1/management-history/tasks/" + value["id"] + "/items"
            and v["query"].get("graph_id") == value["graph_id"]
            for v in trace
        )
    after_media = media()
    save("media-after.json", after_media)
    assert after_media == before_media
    save(
        "result.json",
        {
            "source": source,
            "source_files": source_files,
            "phase": args.phase,
            "viewport": [width, height],
            "scale": int(args.scale),
            "elapsed_seconds": round(time.monotonic() - started, 2),
            "verified": verified,
            "events": events,
        },
    )
finally:
    stop.set()
    if watcher:
        watcher.join(timeout=5)
    control("/release", "POST")
    for name in ("size", "density"):
        previous = next(
            (
                v.split(":", 1)[1].strip()
                for v in old[name].splitlines()
                if v.startswith("Override")
            ),
            "reset",
        )
        shell("wm", name, previous)
    if old_font == "null":
        shell("settings", "delete", "system", "font_scale")
    else:
        shell("settings", "put", "system", "font_scale", old_font)
    save(
        "events.json",
        {
            "events": events,
            "errors": errors,
            "restored_viewport": {n: shell("wm", n) for n in ("size", "density")},
            "font_scale": shell("settings", "get", "system", "font_scale"),
        },
    )
