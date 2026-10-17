#!/usr/bin/env python3
"""Windows host runner for the disposable Android/public-API connection test.

Prepares/resets the dedicated fixture using prepare-client-e2e.sh --reset.
Only the explicitly named e2e container may be stopped by this runner.
"""

import argparse
import json
import os
import subprocess
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVIDENCE = ROOT / "tmp" / "client-e2e"
DEVELOP = Path.home() / "develop"
HEADERS = {"X-Fixture-Key": "isolated-emulator-control"}
CONTAINER = "video-viewer-client-e2e-server-1"
stop = threading.Event()
events = []
errors = []
PREFIX = "i1"


def docker(*args):
    return subprocess.run(
        ["wsl", "-d", "Ubuntu-24.04", "--", "docker", *args],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )


def fresh_instance():
    docker("stop", "--time", "0", CONTAINER)
    events.append({"phase": "fresh-instance-stopped", "time": time.time()})
    linux_root = "/mnt/" + ROOT.drive.rstrip(":").lower() + ROOT.as_posix()[2:]
    result = subprocess.run(
        ["wsl", "-d", "Ubuntu-24.04", "--", "python3", linux_root + "/scripts/reset-client-e2e-instance.py"],
        check=True, capture_output=True, text=True, timeout=30,
    )
    events.append({"phase": "fresh-instance-prepared", "time": time.time(), **json.loads(result.stdout)})
    docker("start", CONTAINER)
    events.append({"phase": "fresh-instance-started", "time": time.time()})


def watch():
    seen = set()
    try:
        while not stop.wait(0.3):
            try:
                request = urllib.request.Request(
                    "http://127.0.0.1:8761/__fixture/checkpoint", headers=HEADERS
                )
                with urllib.request.urlopen(request, timeout=2) as response:
                    phase = json.load(response)["phase"]
            except (OSError, ValueError):
                continue
            if phase in seen:
                continue
            seen.add(phase)
            events.append({"phase": phase, "time": time.time()})
            if phase in {
                "library",
                "roots",
                "recovered",
                "playback",
                "formats",
                "error",
                "preview",
                "fresh-done",
                "preparing",
                "loading-more",
                "prepared",
            }:
                request = urllib.request.Request(
                    "http://127.0.0.1:8761/__fixture/trace", headers=HEADERS
                )
                with urllib.request.urlopen(request, timeout=2) as response:
                    (EVIDENCE / f"{PREFIX}-{phase}-requests.json").write_text(
                        json.dumps(json.load(response), ensure_ascii=False, indent=2),
                        encoding="utf-8",
                    )
                result = subprocess.run(
                    [
                        str(DEVELOP / "android-sdk/platform-tools/adb.exe"),
                        "-s",
                        "emulator-5554",
                        "exec-out",
                        "screencap",
                        "-p",
                    ],
                    capture_output=True,
                    check=True,
                    timeout=15,
                )
                (EVIDENCE / f"{PREFIX}-{phase}.png").write_bytes(result.stdout)
            if phase == "outage":
                docker("stop", "--time", "0", CONTAINER)
                events.append({"phase": "docker-stopped", "time": time.time()})
                stop.wait(20 if PREFIX == "i2" else 8)
                docker("start", CONTAINER)
                events.append({"phase": "docker-started", "time": time.time()})
            if phase == "fresh-instance":
                fresh_instance()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        errors.append(str(error))


def main():
    global PREFIX
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--playback", action="store_true")
    mode.add_argument("--tags", action="store_true")
    mode.add_argument("--files", action="store_true")
    mode.add_argument("--external", action="store_true")
    mode.add_argument("--backups", action="store_true")
    mode.add_argument("--preparation", action="store_true")
    parser.add_argument("--plain-name")
    args = parser.parse_args()
    if args.preparation:
        PREFIX = "v1-preparation"
    elif args.backups:
        PREFIX = "i6"
    elif args.external:
        PREFIX = "i5"
    elif args.files:
        PREFIX = "i4"
    elif args.tags:
        PREFIX = "i3"
    elif args.playback:
        PREFIX = "i2"
    else:
        PREFIX = "i1"
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    linux_root = "/mnt/" + ROOT.drive.rstrip(":").lower() + ROOT.as_posix()[2:]
    subprocess.run(
        [
            "wsl",
            "-d",
            "Ubuntu-24.04",
            "--",
            "bash",
            linux_root + "/scripts/prepare-client-e2e.sh",
            "--reset",
        ],
        check=True,
    )
    env = os.environ.copy()
    env.update(
        PUB_CACHE=str(DEVELOP / "pub-cache"),
        PUB_HOSTED_URL="https://pub.flutter-io.cn",
        FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn",
    )
    watcher = threading.Thread(target=watch, daemon=True)
    watcher.start()
    try:
        command = [
            str(DEVELOP / "flutter/bin/flutter.bat"),
            "test",
            {
                "i1": "integration_test/server_connection_test.dart",
                "i2": "integration_test/server_playback_test.dart",
                "i3": "integration_test/server_tags_test.dart",
                "i4": "integration_test/server_files_test.dart",
                "i5": "integration_test/server_external_test.dart",
                "i6": "integration_test/server_backups_test.dart",
                "v1-preparation": "integration_test/server_preparation_test.dart",
            }[PREFIX],
            "-d",
            "emulator-5554",
            "--no-uninstall",
            "--reporter",
            "expanded",
        ]
        if args.plain_name:
            command.extend(["--plain-name", args.plain_name])
        with (EVIDENCE / f"{PREFIX}-android-test.log").open(
            "w", encoding="utf-8"
        ) as log:
            code = 0
            for phase in range(1 if args.plain_name or args.preparation else 3 if args.backups else 2):
                if phase:
                    subprocess.run(
                        [
                            str(DEVELOP / "android-sdk/platform-tools/adb.exe"),
                            "-s",
                            "emulator-5554",
                            "shell",
                            "am",
                            "force-stop",
                            "io.github.shijijs.video_viewer",
                        ],
                        check=True,
                        timeout=15,
                    )
                    events.append(
                        {"phase": "android-force-stopped", "resume_phase": phase, "time": time.time()}
                    )
                process = subprocess.Popen(
                    command + (["--dart-define=E2E_RESUME=true"] if phase else [])
                    + (["--dart-define=E2E_FRESH_RESUME=true"] if phase == 2 else []),
                    cwd=ROOT / "apps/mobile",
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                )
                for line in process.stdout:
                    log.write(line)
                    log.flush()
                    print(line, end="", flush=True)
                code = process.wait()
                if code:
                    break
    finally:
        stop.set()
        watcher.join(timeout=35)
        docker("start", CONTAINER)
        (EVIDENCE / f"{PREFIX}-host-events.json").write_text(
            json.dumps(
                {"events": events, "errors": errors}, ensure_ascii=False, indent=2
            ),
            encoding="utf-8",
        )
    if errors:
        raise SystemExit("Fixture host controller failed: " + "; ".join(errors))
    raise SystemExit(code)


if __name__ == "__main__":
    main()
