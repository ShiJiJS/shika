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
APP_COMPONENT = "io.github.shijijs.video_viewer/.MainActivity"


def docker(*args):
    return subprocess.run(
        host_command("docker", *args),
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )


def prepare_emulator():
    avd = (
        subprocess.check_output(
            [ADB, "-s", "emulator-5554", "emu", "avd", "name"], text=True, timeout=10
        )
        .splitlines()[0]
        .strip()
    )
    if avd != os.environ.get("VV_AVD_NAME", "video_viewer_api_36"):
        raise SystemExit(
            f"Refusing to change guidance settings on an unexpected AVD: {avd}"
        )
    # Cold boots can show an Android-owned immersive guide over the app. It
    # steals focus and is outside Flutter's widget tree, so prepare only this AVD.
    subprocess.run(
        [
            ADB,
            "-s",
            "emulator-5554",
            "shell",
            "settings",
            "put",
            "secure",
            "immersive_mode_confirmations",
            "confirmed",
        ],
        check=True,
        timeout=10,
    )
    confirmed = subprocess.check_output(
        [
            ADB,
            "-s",
            "emulator-5554",
            "shell",
            "settings",
            "get",
            "secure",
            "immersive_mode_confirmations",
        ],
        text=True,
        timeout=10,
    ).strip()
    if confirmed != "confirmed":
        raise SystemExit(
            "Could not prepare the dedicated emulator's immersive guidance"
        )
    events.append(
        {"phase": "emulator-immersive-guidance-confirmed", "time": time.time()}
    )


def foreground_app():
    return subprocess.run(
        [
            ADB,
            "-s",
            "emulator-5554",
            "shell",
            "am",
            "start",
            "-W",
            "-n",
            APP_COMPONENT,
            "--activity-single-top",
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=15,
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
                "workspace-video", "workspace-packs", "workspace-video-tags",
                "workspace-pack-tags", "workspace-settings", "workspace-dark",
                "tag-catalog-retry", "tag-catalog-paged", "tag-catalog-renamed",
                "selection-videos", "selection-packs",
                "pack-names-card", "pack-names-retry", "pack-names-saved", "pack-names-renamed",
                "pack-anchor-before", "pack-anchor-error", "pack-anchor-return", "pack-anchor-prepend", "pack-anchor-inserted",
                "reader-horizontal", "reader-vertical", "reader-reopen", "reader-overview", "reader-next", "reader-return",
                "recent-initial", "recent-tail", "recent-reading", "recent-return", "recent-library",
                "controls-rtl", "controls-zoom", "controls-immersive", "controls-width", "controls-reopen", "controls-vertical", "controls-next", "controls-return",
                "trash-read-error", "trash-reader", "trash-selected", "trash-unknown", "trash-restored", "trash-recent",
                "purge-selected", "purge-review", "purge-files", "purge-saved", "purge-saved-reopened", "purge-unknown", "purge-result", "purge-finished",
                "bulk-selected", "bulk-review", "bulk-unknown", "bulk-receipt", "bulk-paged", "bulk-selection", "bulk-next-review",
                "defaults-video", "defaults-reader", "defaults-unknown", "defaults-reopened", "defaults-migration",
                "tasks-list", "tasks-pending", "tasks-detail", "tasks-paged", "tasks-historical", "tasks-backup-saved",
                "restore-selected", "restore-unknown", "restore-reopened", "restore-paged", "restore-stop-unknown", "restore-stopped",
                "cleanup-ready", "cleanup-unknown", "cleanup-next", "cleanup-undo", "cleanup-normal", "cleanup-resumed", "cleanup-tail", "cleanup-return",
                "recovery-image-error", "recovery-image-ready", "recovery-unknown", "recovery-receipt", "recovery-background", "recovery-tags", "recovery-queue", "recovery-return",
            }:
                request = urllib.request.Request(
                    "http://127.0.0.1:8761/__fixture/trace", headers=HEADERS
                )
                with urllib.request.urlopen(request, timeout=2) as response:
                    (EVIDENCE / f"{PREFIX}-{phase}-requests.json").write_text(
                        json.dumps(json.load(response), ensure_ascii=False, indent=2),
                        encoding="utf-8",
                    )
                if PREFIX in {"lf6-trash", "lf6-purge", "lf7-tasks", "lf7-restore", "lf7-purge-restart", "lf7-defaults"}:
                    request = urllib.request.Request(
                        "http://127.0.0.1:8761/__fixture/actions/pack-trash-hashes",
                        headers=HEADERS, method="POST",
                    )
                    with urllib.request.urlopen(request, timeout=2) as response:
                        (EVIDENCE / f"{PREFIX}-{phase}-files.json").write_text(
                            json.dumps(json.load(response), ensure_ascii=False, indent=2),
                            encoding="utf-8",
                        )
                if PREFIX == "lf7-restore":
                    request = urllib.request.Request("http://127.0.0.1:8761/__fixture/actions/restore-plan-stats", headers=HEADERS, method="POST")
                    with urllib.request.urlopen(request, timeout=2) as response:
                        (EVIDENCE / f"{PREFIX}-{phase}-plan.json").write_text(json.dumps(json.load(response),ensure_ascii=False,indent=2),encoding="utf-8")
                if PREFIX == "lf7-purge-restart":
                    request = urllib.request.Request("http://127.0.0.1:8761/__fixture/actions/purge-restart-stats", headers=HEADERS, method="POST")
                    with urllib.request.urlopen(request, timeout=5) as response:
                        (EVIDENCE / f"{PREFIX}-{phase}-stats.json").write_text(json.dumps(json.load(response), ensure_ascii=False, indent=2), encoding="utf-8")
                if PREFIX == "lf5-recovery":
                    request = urllib.request.Request(
                        "http://127.0.0.1:8761/__fixture/reader/stats",
                        headers=HEADERS, method="POST",
                    )
                    with urllib.request.urlopen(request, timeout=2) as response:
                        (EVIDENCE / f"{PREFIX}-{phase}-faults.json").write_text(
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
    mode.add_argument("--workspace", action="store_true")
    mode.add_argument("--tag-catalog", action="store_true")
    mode.add_argument("--selection", action="store_true")
    mode.add_argument("--pack-names", action="store_true")
    mode.add_argument("--pack-anchor", action="store_true")
    mode.add_argument("--pack-reader", action="store_true")
    mode.add_argument("--pack-recent", action="store_true")
    mode.add_argument("--pack-controls", action="store_true")
    mode.add_argument("--pack-trash", action="store_true")
    mode.add_argument("--pack-purge", action="store_true")
    mode.add_argument("--purge-restart", action="store_true")
    mode.add_argument("--managed-defaults", action="store_true")
    mode.add_argument("--maintenance-tasks", action="store_true")
    mode.add_argument("--restore-plans", action="store_true")
    mode.add_argument("--pack-cleanup", action="store_true")
    mode.add_argument("--pack-recovery", action="store_true")
    parser.add_argument("--workspace-viewport", choices=("390", "360"), default="390")
    parser.add_argument("--workspace-text-scale", choices=("1", "2"), default="1")
    parser.add_argument("--pack-cleanup-rounds", type=int, choices=(1, 8), default=1)
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
    if args.managed_defaults:
        PREFIX = "lf7-defaults"
    elif args.purge_restart:
        PREFIX = "lf7-purge-restart"
    elif args.restore_plans:
        PREFIX = "lf7-restore"
    elif args.maintenance_tasks:
        PREFIX = "lf7-tasks"
    elif args.pack_purge:
        PREFIX = "lf6-purge"
    elif args.pack_trash:
        PREFIX = "lf6-trash"
    elif args.pack_cleanup:
        PREFIX = "lf6-cleanup"
    elif args.pack_recovery:
        PREFIX = "lf5-recovery"
    elif args.pack_controls:
        PREFIX = "lf5-controls"
    elif args.pack_recent:
        PREFIX = "lf5-recent"
    elif args.pack_reader:
        PREFIX = "lf5-reader"
    elif args.pack_anchor:
        PREFIX = "lf4-pack-anchor"
    elif args.pack_names:
        PREFIX = "lf4-pack-names"
    elif args.selection:
        PREFIX = "lf4-selection"
    elif args.tag_catalog:
        PREFIX = "lf4-tag-catalog"
    elif args.workspace:
        PREFIX = "lf4-workspace"
    elif args.anchor:
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
    prepare_emulator()
    if args.workspace or args.tag_catalog or args.selection or args.pack_names or args.pack_anchor or args.pack_reader or args.pack_recent or args.pack_controls or args.pack_recovery or args.pack_cleanup or args.pack_trash or args.pack_purge or args.purge_restart or args.maintenance_tasks or args.restore_plans or args.managed_defaults:
        def device(*command):
            return subprocess.check_output(
                [ADB, "-s", "emulator-5554", "shell", *command], text=True, timeout=10
            ).strip()

        old_size, old_density = device("wm", "size"), device("wm", "density")
        old_scale = device("settings", "get", "system", "font_scale")

        def restore_workspace_viewport():
            for name, previous in (("size", old_size), ("density", old_density)):
                override = next((line.split(":", 1)[1].strip() for line in previous.splitlines() if line.startswith("Override")), "reset")
                device("wm", name, override)
            if old_scale == "null":
                device("settings", "delete", "system", "font_scale")
            else:
                device("settings", "put", "system", "font_scale", old_scale)

        atexit.register(restore_workspace_viewport)
        width, height = (390, 844) if args.workspace_viewport == "390" else (360, 740)
        device("wm", "size", f"{width * 3}x{height * 3}")
        device("wm", "density", "480")
        device("settings", "put", "system", "font_scale", args.workspace_text_scale)
        events.append({"phase": "workspace-viewport", "width_dp": width, "height_dp": height, "density_dpi": 480, "text_scale": args.workspace_text_scale})
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
    android_in_background = False
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
                "lf4-workspace": "integration_test/server_workspace_test.dart",
                "lf4-tag-catalog": "integration_test/server_tag_catalog_test.dart",
                "lf4-selection": "integration_test/server_catalog_selection_test.dart",
                "lf4-pack-names": "integration_test/server_pack_names_test.dart",
                "lf4-pack-anchor": "integration_test/server_pack_anchor_test.dart",
                "lf5-reader": "integration_test/server_pack_reader_test.dart",
                "lf5-recent": "integration_test/server_pack_recent_test.dart",
                "lf5-controls": "integration_test/server_pack_reader_controls_test.dart",
                "lf6-trash": "integration_test/server_pack_trash_test.dart",
                "lf6-purge": "integration_test/server_pack_purge_test.dart",
                "lf7-tasks": "integration_test/server_maintenance_tasks_test.dart",
                "lf7-restore": "integration_test/server_restore_plans_test.dart",
                "lf7-purge-restart": "integration_test/server_purge_restart_test.dart",
                "lf7-defaults": "integration_test/server_defaults_test.dart",
                "lf6-cleanup": "integration_test/server_pack_cleanup_test.dart",
                "lf5-recovery": "integration_test/server_pack_reader_recovery_test.dart",
            }[PREFIX],
            "-d",
            "emulator-5554",
            "--no-uninstall",
            "--reporter",
            "expanded",
        ]
        if args.pack_cleanup and args.pack_cleanup_rounds > 1:
            command.append(f"--dart-define=PACK_CLEANUP_ROUNDS={args.pack_cleanup_rounds}")
        if args.plain_name:
            command.extend(["--plain-name", args.plain_name])
        with (EVIDENCE / f"{PREFIX}-android-test.log").open(
            "w", encoding="utf-8"
        ) as log:
            code = 0
            killed_restore_pid = None
            killed_purge_pid = None
            for phase in range(
                1
                if args.plain_name
                or args.preparation
                or args.interactions
                or args.preview
                or args.anchor
                or args.workspace
                or args.tag_catalog
                or args.selection
                or args.pack_names
                or args.pack_anchor
                or args.pack_reader
                or args.pack_recent
                or args.pack_controls
                or args.pack_recovery
                or args.pack_cleanup
                or args.pack_trash
                or args.pack_purge
                or args.maintenance_tasks
                or args.managed_defaults
                else 3
                if args.backups
                else 2
            ):
                forced_restore_kill = False
                forced_purge_kill = False
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
                    if line.strip() == "VV_E2E_DEVICE_BACK":
                        subprocess.run(
                            [ADB, "-s", "emulator-5554", "shell", "input", "keyevent", "KEYCODE_BACK"],
                            check=True, capture_output=True, timeout=10,
                        )
                        events.append({"phase": "android-back", "time": time.time()})
                    elif line.strip() == "VV_E2E_PURGE_FORCE_STOP":
                        if not args.purge_restart or phase != 0:
                            raise RuntimeError("Unexpected purge force-stop signal")
                        killed_purge_pid = subprocess.check_output([ADB,"-s","emulator-5554","shell","pidof","io.github.shijijs.video_viewer"],text=True,timeout=10).strip()
                        if not killed_purge_pid:
                            raise RuntimeError("Purge App was not live at forced interruption")
                        subprocess.run([ADB,"-s","emulator-5554","shell","am","force-stop","io.github.shijijs.video_viewer"],check=True,timeout=10)
                        absent = subprocess.run([ADB,"-s","emulator-5554","shell","pidof","io.github.shijijs.video_viewer"],capture_output=True,text=True,timeout=10)
                        if absent.stdout.strip():
                            raise RuntimeError("Purge App survived forced interruption")
                        forced_purge_kill = True
                        events.append({"phase":"purge-app-force-stopped","pid":killed_purge_pid,"pid_absent":True,"time":time.time()})
                        request = urllib.request.Request("http://127.0.0.1:8761/__fixture/actions/release-purge-restart",headers=HEADERS,method="POST")
                        with urllib.request.urlopen(request,timeout=5) as response:
                            json.load(response)
                        deadline = time.monotonic()+300
                        while True:
                            request = urllib.request.Request("http://127.0.0.1:8761/__fixture/actions/purge-restart-stats",headers=HEADERS,method="POST")
                            with urllib.request.urlopen(request,timeout=5) as response:
                                stats = json.load(response)
                            if stats["task"] and stats["task"]["status"] in {"completed","failed","interrupted"}:
                                break
                            if time.monotonic()>deadline:
                                raise RuntimeError("Accepted 1000-pack purge did not settle while App was absent")
                            stop.wait(.5)
                        if stats["task"]["status"] != "completed" or stats["members"] != {"succeeded":1000} or stats["active_trash"] != 3:
                            raise RuntimeError("Purge did not preserve the unsubmitted three packs: " + json.dumps(stats))
                        still_absent = subprocess.run([ADB,"-s","emulator-5554","shell","pidof","io.github.shijijs.video_viewer"],capture_output=True,text=True,timeout=10)
                        if still_absent.stdout.strip():
                            raise RuntimeError("App restarted before its accepted batch completed")
                        (EVIDENCE/f"{PREFIX}-without-app-stats.json").write_text(json.dumps(stats,ensure_ascii=False,indent=2),encoding="utf-8")
                        request = urllib.request.Request("http://127.0.0.1:8761/__fixture/actions/pack-trash-hashes",headers=HEADERS,method="POST")
                        with urllib.request.urlopen(request,timeout=10) as response:
                            hashes = json.load(response)
                        (EVIDENCE/f"{PREFIX}-without-app-files.json").write_text(json.dumps(hashes,ensure_ascii=False,indent=2),encoding="utf-8")
                        events.append({"phase":"purge-completed-without-app","members":1000,"unsubmitted":3,"pid_absent":True,"time":time.time()})
                    elif line.strip() == "VV_E2E_PURGE_REOPENED":
                        reopened = subprocess.check_output([ADB,"-s","emulator-5554","shell","pidof","io.github.shijijs.video_viewer"],text=True,timeout=10).strip()
                        if not args.purge_restart or not killed_purge_pid or not reopened or reopened == killed_purge_pid:
                            raise RuntimeError("Purge did not reopen in a different Android process")
                        events.append({"phase":"purge-app-reopened","old_pid":killed_purge_pid,"new_pid":reopened,"time":time.time()})
                    elif line.strip() == "VV_E2E_RESTORE_FORCE_STOP":
                        if not args.restore_plans or phase != 0:
                            raise RuntimeError("Unexpected restore force-stop signal")
                        killed_restore_pid = subprocess.check_output([ADB,"-s","emulator-5554","shell","pidof","io.github.shijijs.video_viewer"],text=True,timeout=10).strip()
                        if not killed_restore_pid:
                            raise RuntimeError("App was not live at forced interruption")
                        subprocess.run([ADB,"-s","emulator-5554","shell","am","force-stop","io.github.shijijs.video_viewer"],check=True,timeout=10)
                        absent = subprocess.run([ADB,"-s","emulator-5554","shell","pidof","io.github.shijijs.video_viewer"],capture_output=True,text=True,timeout=10)
                        if absent.stdout.strip():
                            raise RuntimeError("App survived forced interruption")
                        forced_restore_kill = True
                        events.append({"phase":"restore-app-force-stopped","pid":killed_restore_pid,"pid_absent":True,"time":time.time()})
                        request = urllib.request.Request("http://127.0.0.1:8761/__fixture/actions/release-restore-plan",headers=HEADERS,method="POST")
                        with urllib.request.urlopen(request,timeout=3) as response:
                            json.load(response)
                        deadline = time.monotonic()+30
                        while True:
                            request = urllib.request.Request("http://127.0.0.1:8761/__fixture/actions/restore-plan-stats",headers=HEADERS,method="POST")
                            with urllib.request.urlopen(request,timeout=3) as response:
                                stats = json.load(response)
                            if stats["plan"]["status"] == "completed":
                                break
                            if time.monotonic()>deadline:
                                raise RuntimeError("Server did not finish whole plan while app was absent")
                            stop.wait(.1)
                        if stats["member_counts"] != {"succeeded":27} or len(stats["batches"]) != 14:
                            raise RuntimeError("Whole-selection continuation did not finish unique batches")
                        still_absent = subprocess.run([ADB,"-s","emulator-5554","shell","pidof","io.github.shijijs.video_viewer"],capture_output=True,text=True,timeout=10)
                        if still_absent.stdout.strip():
                            raise RuntimeError("App restarted before the server completed its plan")
                        (EVIDENCE/f"{PREFIX}-without-app-plan.json").write_text(json.dumps(stats,ensure_ascii=False,indent=2),encoding="utf-8")
                        events.append({"phase":"restore-completed-without-app","members":27,"batches":14,"pid_absent":True,"time":time.time()})
                    elif line.strip() == "VV_E2E_RESTORE_REOPENED":
                        reopened = subprocess.check_output([ADB,"-s","emulator-5554","shell","pidof","io.github.shijijs.video_viewer"],text=True,timeout=10).strip()
                        if not args.restore_plans or not killed_restore_pid or not reopened or reopened == killed_restore_pid:
                            raise RuntimeError("Restore did not reopen in a different Android process")
                        events.append({"phase":"restore-app-reopened","old_pid":killed_restore_pid,"new_pid":reopened,"time":time.time()})
                    elif line.strip() == "VV_E2E_DEVICE_BACKGROUND":
                        subprocess.run(
                            [
                                ADB,
                                "-s",
                                "emulator-5554",
                                "shell",
                                "input",
                                "keyevent",
                                "KEYCODE_HOME",
                            ],
                            check=True,
                            capture_output=True,
                            timeout=10,
                        )
                        android_in_background = True
                        events.append(
                            {"phase": "android-backgrounded", "time": time.time()}
                        )
                    elif line.strip() == "VV_E2E_DEVICE_FOREGROUND":
                        foreground_app()
                        android_in_background = False
                        events.append(
                            {"phase": "android-foregrounded", "time": time.time()}
                        )
                code = process.wait()
                if args.restore_plans and phase == 0:
                    if not forced_restore_kill or code == 0:
                        raise RuntimeError("First restore phase ended without a forced live-process interruption")
                    events.append({"phase":"restore-expected-test-interruption","runner_exit_code":code,"time":time.time()})
                    code = 0
                if args.purge_restart and phase == 0:
                    if not forced_purge_kill or code == 0:
                        raise RuntimeError("First purge phase ended without forced live-process interruption")
                    events.append({"phase":"purge-expected-test-interruption","runner_exit_code":code,"time":time.time()})
                    code = 0
                if code:
                    break
    finally:
        if android_in_background:
            try:
                foreground_app()
            except subprocess.SubprocessError as error:
                errors.append(f"Could not restore the emulator app: {error}")
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
