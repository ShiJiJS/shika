#!/usr/bin/env python3
"""Cross-platform host runner for the disposable Android/public-API connection test.

Prepares/resets the dedicated fixture using prepare-client-e2e.sh --reset.
Only the explicitly named e2e container may be stopped by this runner.
"""

import argparse
import atexit
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
WINDOWS = os.name == "nt"
DEVELOP = (
    Path.home() / "develop"
    if WINDOWS
    else Path(os.environ.get("VV_DEV_HOME", ROOT / ".dev"))
)
SDK = Path(os.environ.get("ANDROID_HOME", DEVELOP / "android-sdk"))
FLUTTER_ROOT = Path(os.environ.get("FLUTTER_ROOT", DEVELOP / "flutter"))
ADB = str(SDK / "platform-tools" / ("adb.exe" if WINDOWS else "adb"))
FLUTTER = str(FLUTTER_ROOT / "bin" / ("flutter.bat" if WINDOWS else "flutter"))
WSL = ["wsl", "-d", "Ubuntu-24.04", "--"] if WINDOWS else []


def host_path(path):
    if not WINDOWS:
        return str(path)
    return subprocess.check_output(
        WSL + ["wslpath", "-a", str(path)], text=True
    ).strip()


def host_command(*args):
    return WSL + list(args)


HEADERS = {"X-Fixture-Key": "isolated-emulator-control"}
CONTAINER = "video-viewer-client-e2e-server-1"
stop = threading.Event()
events = []
errors = []
PREFIX = "i1"


def docker(*args):
    return subprocess.run(
        host_command("docker", *args),
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )


def fresh_instance():
    docker("stop", "--time", "0", CONTAINER)
    events.append({"phase": "fresh-instance-stopped", "time": time.time()})
    result = subprocess.run(
        host_command(
            "python3", host_path(ROOT / "scripts/reset-client-e2e-instance.py")
        ),
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    events.append(
        {
            "phase": "fresh-instance-prepared",
            "time": time.time(),
            **json.loads(result.stdout),
        }
    )
    if WINDOWS:
        docker("start", CONTAINER)
    else:
        # OrbStack keeps the old bind-mounted directory after host-side rename.
        # Recreate only this disposable container to mount the new empty data.
        subprocess.run(
            [
                "docker",
                "compose",
                "-f",
                str(ROOT / "compose.client-e2e.yaml"),
                "up",
                "-d",
                "--no-build",
                "--force-recreate",
                "server",
            ],
            env={**os.environ, "VV_E2E_ASSETS": str(ROOT / "apps/mobile/assets/media")},
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )
        events.append({"phase": "fresh-instance-recreated", "time": time.time()})
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
                        ADB,
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
    mode.add_argument("--interactions", action="store_true")
    mode.add_argument("--preview", action="store_true")
    mode.add_argument("--anchor", action="store_true")
    parser.add_argument("--plain-name")
    args = parser.parse_args()
    if not Path(ADB).is_file() or not Path(FLUTTER).is_file():
        parser.error(
            "Flutter or ADB missing. On Mac use: bash scripts/dev.sh python3 scripts/run-client-connection-test.py"
        )
    # Only Windows needs a keepalive for its WSL VM.
    if WINDOWS:
        keepalive = subprocess.Popen(
            WSL + ["python3", "-c", "import sys; sys.stdin.buffer.read()"],
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        def release_wsl():
            keepalive.stdin.close()
            try:
                keepalive.wait(timeout=5)
            except subprocess.TimeoutExpired:
                keepalive.terminate()

        atexit.register(release_wsl)
    if args.anchor:
        PREFIX = "lf3-anchor"
    elif args.preview:
        PREFIX = "lf3-preview"
    elif args.interactions:
        PREFIX = "v1-interactions"
    elif args.preparation:
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
    subprocess.run(
        host_command(
            "bash", host_path(ROOT / "scripts/prepare-client-e2e.sh"), "--reset"
        ),
        check=True,
    )
    env = os.environ.copy()
    env.update(
        PUB_CACHE=os.environ.get("PUB_CACHE", str(DEVELOP / "pub-cache")),
    )
    watcher = threading.Thread(target=watch, daemon=True)
    watcher.start()
    try:
        command = [
            FLUTTER,
            "test",
            {
                "i1": "integration_test/server_connection_test.dart",
                "i2": "integration_test/server_playback_test.dart",
                "i3": "integration_test/server_tags_test.dart",
                "i4": "integration_test/server_files_test.dart",
                "i5": "integration_test/server_external_test.dart",
                "i6": "integration_test/server_backups_test.dart",
                "v1-preparation": "integration_test/server_preparation_test.dart",
                "v1-interactions": "integration_test/nonblocking_server_test.dart",
                "lf3-preview": "integration_test/server_preview_test.dart",
                "lf3-anchor": "integration_test/server_anchor_test.dart",
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
            for phase in range(
                1
                if args.plain_name
                or args.preparation
                or args.interactions
                or args.preview
                or args.anchor
                else 3
                if args.backups
                else 2
            ):
                if phase:
                    subprocess.run(
                        [
                            ADB,
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
                        {
                            "phase": "android-force-stopped",
                            "resume_phase": phase,
                            "time": time.time(),
                        }
                    )
                process = subprocess.Popen(
                    command
                    + (["--dart-define=E2E_RESUME=true"] if phase else [])
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
