#!/usr/bin/env python3
"""Real DocumentsUI + App + HTTP archive roundtrip on an owned disposable 8769."""

import argparse
import hashlib
import json
import re
import shlex
import subprocess
import threading
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADB = ROOT / ".dev/android-sdk/platform-tools/adb"
PACKAGE = "io.github.shijijs.video_viewer"
BASE = "http://127.0.0.1:8769"
CONTROL_KEY = "archive-app-isolated-control"
SCENES = [
    "backup-start",
    "backup-dark",
    "restore-first-page",
    "restore-keyboard",
    "restore-confirm-off",
    "backup-restore-point",
    "snapshot-preview",
    "snapshot-confirm-off",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    base = ROOT / ".dev/archive-native-roundtrip" / out.name
    for name in ("config", "data", "packs", "videos"):
        (base / name).mkdir(parents=True, exist_ok=False)
    (base / "config/passphrase").write_text("archive-app-isolated-only")
    (base / "config/mounts.json").write_text(
        json.dumps(
            [
                {"id": "videos", "name": "Videos", "path": "/media/videos"},
                {"id": "packs", "name": "Packs", "path": "/media/packs"},
            ]
        )
    )

    def save(name, value):
        (out / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")

    def run(*command):
        return subprocess.check_output(command, cwd=ROOT, text=True).strip()

    def device(*command):
        return subprocess.check_output(
            [str(ADB), "-s", "emulator-5554", *command], timeout=25
        )

    def shell(*command):
        return device("shell", *command).decode().strip()

    def viewport():
        return {
            "size": shell("wm", "size"),
            "density": shell("wm", "density"),
            "font_scale": shell("settings", "get", "system", "font_scale"),
        }

    def control(path, method="GET"):
        request = urllib.request.Request(
            BASE + "/__archive_fixture" + path,
            headers={"X-Fixture-Key": CONTROL_KEY},
            method=method,
        )
        with urllib.request.urlopen(request, timeout=10) as response:
            return json.load(response)

    def media():
        return {
            str(p.relative_to(base)): {
                "bytes": p.stat().st_size,
                "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
            }
            for folder in ("videos", "packs")
            for p in sorted((base / folder).rglob("*"))
            if p.is_file()
        }

    def download_names():
        return set(shell("ls", "-1", "/sdcard/Download").splitlines())

    assert shell("getprop", "ro.boot.qemu.avd_name") == "video_viewer_api_36"
    assert shell("getprop", "sys.boot_completed") == "1"
    original = viewport()
    save("original-viewport.json", original)
    save(
        "environment.json",
        {
            "avd": shell("getprop", "ro.boot.qemu.avd_name"),
            "api": shell("getprop", "ro.build.version.sdk"),
            "abi": shell("getprop", "ro.product.cpu.abi"),
            "host_avc_decoder": shell("getprop", "ro.boot.qemu.hwcodec.avcdec"),
            "emulator_process": [
                r
                for r in run("ps", "-axo", "command").splitlines()
                if "qemu-system-aarch64" in r and "-avd video_viewer_api_36" in r
            ],
        },
    )
    paths = run(
        "git",
        "ls-files",
        "apps/mobile/lib",
        "apps/mobile/android",
        "services/server/video_viewer",
    ).splitlines()
    paths += [
        "apps/mobile/integration_test/server_archive_management_test.dart",
        "apps/mobile/test/support/reveal_action.dart",
        "scripts/run-native-archive-roundtrip.py",
        "services/server/tests/archive_app_fixture.py",
        "apps/mobile/pubspec.lock",
    ]
    save(
        "source.json",
        {
            "commit": run("git", "rev-parse", "HEAD"),
            "files": {
                p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths
            },
            "prototype_tree": run(
                "git", "rev-parse", "HEAD:design/reference/library-first"
            ),
        },
    )
    container = process = watcher = timer = None
    stop = threading.Event()
    events, errors, system_events = [], [], []
    before_trace = before_media = None
    created_name = None
    before_downloads = download_names()
    save_descriptor = None

    def focus():
        return "\n".join(
            r.strip()
            for r in shell("dumpsys", "window").splitlines()
            if "mCurrentFocus=" in r or "mFocusedApp=" in r
        )

    def capture_system(stage):
        deadline = time.monotonic() + 40
        while True:
            device(
                "shell", "uiautomator", "dump", "/sdcard/lf8-archive-native-window.xml"
            )
            raw = device("exec-out", "cat", "/sdcard/lf8-archive-native-window.xml")
            tree = ET.fromstring(raw)
            nodes = list(tree.iter("node"))
            if any(n.get("package") == "com.google.android.documentsui" for n in nodes):
                (out / ("system-" + stage + ".xml")).write_bytes(raw)
                (out / ("system-" + stage + ".png")).write_bytes(
                    device("exec-out", "screencap", "-p")
                )
                current = focus()
                assert "com.google.android.documentsui" in current, current
                (out / ("system-" + stage + "-window.txt")).write_text(current + "\n")
                return nodes
            assert time.monotonic() < deadline, "DocumentsUI did not appear"
            time.sleep(0.2)

    def tap(node):
        assert node.get("package") == "com.google.android.documentsui"
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.get("bounds")))
        assert x2 > x1 and y2 > y1
        shell("input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))

    def new_document():
        names = download_names() - before_downloads
        assert len(names) == 1, names
        (name,) = names
        assert name.startswith("video-viewer-backup") and name.endswith(".vvbackup")
        assert all(c.isalnum() or c in " .()-_" for c in name), name
        return name

    def watch():
        try:
            while not stop.wait(0.2):
                state = control("/status")
                name = state["display"]
                if not name or state["display_ack"]:
                    continue
                assert name == "archive-ui-" + SCENES[len(events)], name
                current = focus()
                assert any(
                    "mCurrentFocus=" in r and PACKAGE in r for r in current.splitlines()
                ), current
                (out / (name + "-window.txt")).write_text(current + "\n")
                (out / (name + ".png")).write_bytes(
                    device("exec-out", "screencap", "-p")
                )
                save(
                    name + "-requests.json",
                    control("/trace")["items"][len(before_trace) :],
                )
                events.append({"state": name, "epoch": state["epoch"]})
                control("/ack/" + name, "POST")
        except Exception as failure:  # noqa: BLE001 - preserve capture failure
            errors.append(repr(failure))

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
            "video-viewer-native-archive-" + str(time.time_ns()),
            "-p",
            "127.0.0.1:8769:8760",
            "-v",
            str(ROOT / "services/server") + ":/source:ro",
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
            "VV_ARCHIVE_APP_FIXTURE=enabled",
            "-e",
            "VV_PASSPHRASE_FILE=/fixture/passphrase",
            "-e",
            "VV_MOUNTS_FILE=/fixture/mounts.json",
            "-e",
            "VV_BACKUP_MAX_BYTES=67108864",
            "-e",
            "VV_SCAN_INTERVAL=0",
            "-e",
            "VV_STABILITY_SECONDS=0",
            "--entrypoint",
            "uvicorn",
            "video-viewer-server:e2e",
            "tests.archive_app_fixture:create_archive_app",
            "--factory",
            "--host",
            "0.0.0.0",
            "--port",
            "8760",
            "--no-access-log",
        )
        save("runtime.json", json.loads(run("docker", "inspect", container)))
        deadline = time.monotonic() + 45
        while True:
            try:
                assert control("/status")["armed"] is None
                break
            except (urllib.error.URLError, ConnectionError):
                if time.monotonic() >= deadline:
                    raise
                time.sleep(0.2)
        headers = {"Content-Type": "application/json"}

        def api(path, method="GET", body=None):
            request = urllib.request.Request(
                BASE + "/api/v1/" + path,
                headers=headers,
                method=method,
                data=None if body is None else json.dumps(body).encode(),
            )
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)

        login = api("auth/login", "POST", {"passphrase": "archive-app-isolated-only"})
        headers["Authorization"] = "Bearer " + login["access_token"]
        info = api("info")
        headers["X-Management-Epoch"] = info["management_epoch"]
        api(
            "roots/packs",
            "PUT",
            {"name": "Pack test root", "path": "/media/packs", "kind": "pack"},
        )
        for n in range(25):
            api(
                "roots",
                "POST",
                {
                    "name": f"Paged root {n:02d}",
                    "path": f"/media/videos/目录{n:02d}",
                    "kind": "pack" if n % 2 else "video",
                    "enabled": n % 3 != 0,
                },
            )
        for route in ("tags", "pack-tags"):
            api(
                route,
                "POST",
                {"name": "Initial " + route, "request_id": "native-initial-" + route},
            )
        job = api("scans", "POST", {})
        deadline = time.monotonic() + 30
        while job["status"] not in {"completed", "failed"}:
            assert time.monotonic() < deadline
            time.sleep(0.1)
            job = api("tasks/" + job["id"])
        assert job["status"] == "completed"
        prepared = {
            "roots": len(api("roots")["items"]),
            "packs": api("packs")["total"],
            "max_bytes": info["management_backups"]["max_bytes"],
        }
        assert prepared == {"roots": 27, "packs": 1, "max_bytes": 67108864}
        save("prepared.json", prepared)
        before_media, before_trace = media(), control("/trace")["items"]
        save("media-before.json", before_media)
        shell("wm", "size", "1170x2532")
        shell("wm", "density", "480")
        shell("settings", "put", "system", "font_scale", "1")
        watcher = threading.Thread(target=watch, daemon=True)
        watcher.start()
        command = [
            "bash",
            str(ROOT / "scripts/dev.sh"),
            "flutter",
            "test",
            "integration_test/server_archive_management_test.dart",
            "--no-uninstall",
            "-d",
            "emulator-5554",
            "--reporter",
            "expanded",
            "--dart-define=ARCHIVE_NATIVE_DOCUMENTS=true",
            "--dart-define=ARCHIVE_SERVER_PORT=8769",
        ]
        process = subprocess.Popen(
            command,
            cwd=ROOT / "apps/mobile",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        timer = threading.Timer(480, process.kill)
        timer.start()
        with (out / "android-test.log").open("w") as log:
            for line in process.stdout:
                log.write(line)
                log.flush()
                if "ARCHIVE_SYSTEM_STAGE:" in line:
                    event = json.loads(line.split("ARCHIVE_SYSTEM_STAGE:", 1)[1])
                    stage = event["stage"]
                    assert stage == ["save", "pick"][len(system_events)], stage
                    nodes = capture_system(stage)
                    if stage == "save":
                        save_descriptor = event
                        (button,) = [
                            n
                            for n in nodes
                            if n.get("resource-id") == "android:id/button1"
                            and n.get("text") == "SAVE"
                        ]
                        tap(button)
                    else:
                        created_name = new_document()
                        (title,) = [
                            n
                            for n in nodes
                            if n.get("resource-id") == "android:id/title"
                            and n.get("text") == created_name
                        ]
                        tap(title)
                    system_events.append(event)
                    save("system-events.json", system_events)
                if "ARCHIVE_SYSTEM_DONE:" in line:
                    event = json.loads(line.split("ARCHIVE_SYSTEM_DONE:", 1)[1])
                    if event["stage"] == "save":
                        assert event["saved"]
                        created_name = new_document()
                        target = out / "exported-document.vvbackup"
                        pulled = subprocess.run(
                            [
                                str(ADB),
                                "-s",
                                "emulator-5554",
                                "pull",
                                "/sdcard/Download/" + created_name,
                                str(target),
                            ],
                            capture_output=True,
                            text=True,
                            timeout=25,
                            check=True,
                        )
                        save(
                            "document-pull.json",
                            {"stdout": pulled.stdout, "stderr": pulled.stderr},
                        )
                        raw = target.read_bytes()
                        assert len(raw) == save_descriptor["bytes"]
                        assert (
                            hashlib.sha256(raw).hexdigest() == save_descriptor["sha256"]
                        )
                        save(
                            "saved-document.json",
                            {
                                "name": created_name,
                                "bytes": len(raw),
                                "sha256": save_descriptor["sha256"],
                            },
                        )
        code = process.wait(timeout=20)
        save("exit.json", {"code": code})
        assert code == 0 and not errors, errors
        assert len(system_events) == 2 and len(events) == 8
        final_trace = control("/trace")["items"]
        assert final_trace[: len(before_trace)] == before_trace
        requests = final_trace[len(before_trace) :]
        save("requests.json", requests)
        for path in (
            "/api/v1/management-backups",
            "/api/v1/management-backups/imports",
            "/api/v1/management-backups/restores",
            "/api/v1/auth/login",
        ):
            assert (
                sum(r["method"] == "POST" and r["path"] == path for r in requests) == 1
            ), path
        assert (
            sum(
                r["method"] == "POST" and "/from-snapshot/" in r["path"]
                for r in requests
            )
            == 1
        )
        text = (out / "android-test.log").read_text()
        verified = [
            json.loads(r.split("ARCHIVE_UI_VERIFIED:", 1)[1])
            for r in text.splitlines()
            if "ARCHIVE_UI_VERIFIED:" in r
        ]
        (row,) = verified
        assert (
            row["native_documents"]
            and row["epoch_changed"]
            and row["replacement_removed_late_tags"]
            and row["snapshot_not_confirmed"]
        )
        assert (
            row["document_sha256"] == save_descriptor["sha256"]
            and row["document_bytes"] == save_descriptor["bytes"]
        )
        assert "All tests passed!" in text
        save("media-after.json", media())
        assert before_media == media()
        shell("rm", "--", shlex.quote("/sdcard/Download/" + created_name))
        assert download_names() == before_downloads
        save(
            "document-cleanup.json",
            {"removed_owned_document": created_name, "other_names_unchanged": True},
        )
        save(
            "result.json",
            {
                "passed": True,
                "native_points": 8,
                "system_points": 2,
                "window": [390, 844],
                "document": read_saved(out),
                "restore_posts": 1,
                "snapshot_preview_only": True,
            },
        )
        print(
            json.dumps({"passed": True, "native_points": 8, "system_points": 2}),
            flush=True,
        )
    finally:
        stop.set()
        if timer:
            timer.cancel()
        if process and process.poll() is None:
            process.kill()
            process.wait(timeout=20)
        if watcher:
            watcher.join(timeout=20)
        save("host-events.json", {"events": events, "errors": errors})
        try:
            for kind in ("size", "density"):
                old = original[kind]
                value = next(
                    (
                        v.split(":", 1)[1].strip()
                        for v in old.splitlines()
                        if v.startswith("Override")
                    ),
                    "reset",
                )
                shell("wm", kind, value)
            if original["font_scale"] == "null":
                shell("settings", "delete", "system", "font_scale")
            else:
                shell("settings", "put", "system", "font_scale", original["font_scale"])
            save("restored-viewport.json", {"before": original, "after": viewport()})
        except Exception as error:  # noqa: BLE001 - preserve cleanup alongside original failure
            save("restore-error.json", {"original": original, "error": repr(error)})
        finally:
            if container:
                try:
                    save("fixture-final.json", control("/status"))
                    save("requests-final.json", control("/trace")["items"])
                except Exception as error:  # noqa: BLE001 - service may already have failed
                    save("fixture-error.json", {"error": repr(error)})
                result = subprocess.run(
                    ["docker", "logs", container],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                (out / "server.log").write_text(result.stdout + result.stderr)
                subprocess.run(
                    ["docker", "rm", "-f", container],
                    check=True,
                    capture_output=True,
                    timeout=30,
                )


def read_saved(out):
    return json.loads((out / "saved-document.json").read_text())


if __name__ == "__main__":
    main()
