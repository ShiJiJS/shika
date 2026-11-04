#!/usr/bin/env python3
"""Real DocumentsUI + App + HTTP archive roundtrip on an owned disposable 8769."""

import argparse
import hashlib
import json
import re
import sqlite3
import subprocess
import sys
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
    parser.add_argument("--large", action="store_true")
    parser.add_argument("--cancel-first", action="store_true")
    parser.add_argument("--diagnose", action="store_true")
    parser.add_argument("--truncate-upload-response", action="store_true")
    args = parser.parse_args()
    if args.truncate_upload_response and not args.diagnose:
        parser.error("--truncate-upload-response requires --diagnose")
    scenes = list(SCENES)
    if args.cancel_first:
        scenes[2:2] = ["save-cancelled", "pick-cancelled"]
    system_stages = (
        ["cancel-save", "save", "cancel-pick", "pick"]
        if args.cancel_first
        else ["save", "pick"]
    )
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

    def app_pid():
        return subprocess.run(
            [str(ADB), "-s", "emulator-5554", "shell", "pidof", PACKAGE],
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        ).stdout.strip()

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
        "services/server/shika",
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
    fault_stopped = threading.Event()
    events, errors, system_events = [], [], []
    before_trace = before_media = None
    created_name = None
    unique_name = "shika-backup-" + str(time.time_ns()) + ".vvbackup"
    before_downloads = download_names()
    save_descriptor = None

    def notes_snapshot():
        digest = hashlib.sha256()
        count = 0
        minimum = maximum = None
        with sqlite3.connect(
            "file:" + str(base / "data/library.sqlite3") + "?mode=ro", uri=True
        ) as connection:
            for identity, kind, status, phase, raw in connection.execute(
                "SELECT id,kind,status,phase,result FROM tasks WHERE json_type(result,'$.note')='text' ORDER BY id"
            ):
                note = json.loads(raw)["note"]
                count += 1
                minimum = len(note) if minimum is None else min(minimum, len(note))
                maximum = len(note) if maximum is None else max(maximum, len(note))
                digest.update(
                    json.dumps(
                        [identity, kind, status, phase, note], separators=(",", ":")
                    ).encode()
                )
                digest.update(b"\n")
        return {
            "count": count,
            "min_note": minimum,
            "max_note": maximum,
            "sha256": digest.hexdigest(),
        }

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
            ready = any(n.get("package") == "com.google.android.documentsui" for n in nodes)
            if stage in {"save", "save-named"}:
                ready = ready and any(
                    n.get("class") == "android.widget.EditText"
                    and n.get("resource-id") == "android:id/title"
                    and (stage == "save" or n.get("text") == unique_name)
                    for n in nodes
                ) and any(
                    n.get("resource-id") == "android:id/button1"
                    and n.get("text") == "SAVE"
                    for n in nodes
                )
            if stage == "pick":
                ready = ready and any(
                    n.get("resource-id") == "android:id/title"
                    and n.get("text") == created_name
                    for n in nodes
                )
            if ready:
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
        assert name.startswith("shika-backup") and name.endswith(".vvbackup")
        assert all(c.isalnum() or c in " .()-_" for c in name), name
        assert name == unique_name, name
        return name

    def watch():
        try:
            while not stop.wait(0.2):
                state = control("/status")
                name = state["display"]
                if not name or state["display_ack"]:
                    continue
                failure = args.diagnose and name == "archive-ui-unexpected-failure"
                if not failure:
                    assert name == "archive-ui-" + scenes[len(events)], name
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
                if failure:
                    save("upload-failure-capture.json", {"state": name, "epoch": state["epoch"]})
                    if args.truncate_upload_response:
                        old_pid = app_pid()
                        assert old_pid, "Failure frame must belong to the live App"
                        shell("am", "force-stop", PACKAGE)
                        assert not app_pid()
                        control("/ack/" + name, "POST")
                        save("failure-force-stop.json", {"old_pid": old_pid, "after_pid": ""})
                        fault_stopped.set()
                        continue
                else:
                    events.append({"state": name, "epoch": state["epoch"]})
                    if name == "archive-ui-resume-start":
                        save("resumed-app-pid.json", {"pid": app_pid()})
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
            "VV_ARCHIVE_NATIVE_LARGE=" + ("enabled" if args.large else "disabled"),
            "-e",
            "VV_ARCHIVE_UPLOAD_TRUNCATION=" + ("enabled" if args.truncate_upload_response else "disabled"),
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
            "shika-server:e2e",
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
        assert "backup_v2" in info["capabilities"]
        save("public-info-before.json", info)
        headers["X-Management-Epoch"] = info["management_epoch"]
        deadline = time.monotonic() + 90
        preparation = api("library-state")
        while preparation["scanning"]:
            assert time.monotonic() < deadline, "Initial fixture scan did not finish"
            time.sleep(0.1)
            preparation = api("library-state")
        save("initial-scan.json", preparation)
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
        if args.large:
            rejected = urllib.request.Request(
                BASE + "/__archive_fixture/seed-large",
                method="POST",
                headers={"X-Fixture-Key": "not-the-owned-key"},
            )
            try:
                urllib.request.urlopen(rejected, timeout=10)
                raise AssertionError("Large fixture accepted an invalid key")
            except urllib.error.HTTPError as error:
                assert error.code == 403
                save("control-guard.json", {"invalid_key_status": error.code})
            save("large-seed.json", control("/seed-large", "POST"))
        before_notes = notes_snapshot()
        save("notes-before.json", before_notes)
        assert before_notes["count"] == (18000 if args.large else 0)
        before_media, before_trace = media(), control("/trace")["items"]
        save("media-before.json", before_media)
        shell("wm", "size", "1170x2532")
        shell("wm", "density", "480")
        shell("settings", "put", "system", "font_scale", "1")
        old_focus = focus()
        old_pid = app_pid()
        shell("am", "force-stop", PACKAGE)
        if "com.google.android.documentsui" in focus():
            shell("input", "keyevent", "4")
        save(
            "launch-preparation.json",
            {
                "old_focus": old_focus,
                "old_pid": old_pid,
                "after_focus": focus(),
                "app_pid_after_stop": app_pid(),
            },
        )
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
        if args.large:
            command.append("--dart-define=ARCHIVE_LARGE_DOCUMENT=true")
        if args.cancel_first:
            command.append("--dart-define=ARCHIVE_CANCEL_INPUTS=true")
        if args.diagnose:
            command.append("--dart-define=ARCHIVE_CAPTURE_FAILURES=true")
        process = subprocess.Popen(
            command,
            cwd=ROOT / "apps/mobile",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        timer = threading.Timer(900 if args.large else 480, process.kill)
        timer.start()
        with (out / "android-test.log").open("w") as log:
            for line in process.stdout:
                log.write(line)
                log.flush()
                if "ARCHIVE_SYSTEM_STAGE:" in line:
                    event = json.loads(line.split("ARCHIVE_SYSTEM_STAGE:", 1)[1])
                    stage = event["stage"]
                    assert stage == system_stages[len(system_events)], stage
                    nodes = capture_system(stage)
                    if stage in {"cancel-save", "cancel-pick"}:
                        shell("input", "keyevent", "4")
                    elif stage == "save":
                        save_descriptor = event
                        (field,) = [
                            n
                            for n in nodes
                            if n.get("class") == "android.widget.EditText"
                            and n.get("resource-id") == "android:id/title"
                        ]
                        tap(field)
                        shell("input", "keycombination", "113", "29")
                        shell("input", "text", unique_name)
                        nodes = capture_system("save-named")
                        assert (
                            len(
                                [
                                    n
                                    for n in nodes
                                    if n.get("class") == "android.widget.EditText"
                                    and n.get("text") == unique_name
                                ]
                            )
                            == 1
                        )
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
                    if event["stage"] == "cancel-save":
                        assert event["saved"] is False
                        assert download_names() == before_downloads
                    if event["stage"] == "cancel-pick":
                        assert event["cancelled"] is True
                        assert download_names() == before_downloads | {created_name}
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
                        actual_hash = hashlib.sha256()
                        with target.open("rb") as incoming:
                            for chunk in iter(lambda: incoming.read(65536), b""):
                                actual_hash.update(chunk)
                        assert target.stat().st_size == save_descriptor["bytes"]
                        assert actual_hash.hexdigest() == save_descriptor["sha256"]
                        save(
                            "saved-document.json",
                            {
                                "name": created_name,
                                "bytes": target.stat().st_size,
                                "sha256": save_descriptor["sha256"],
                            },
                        )
        code = process.wait(timeout=20)
        save("exit.json", {"code": code})
        if args.truncate_upload_response:
            assert code != 0 and not errors and fault_stopped.wait(30), errors
            timer.cancel()
            text = (out / "android-test.log").read_text()
            failures = [json.loads(line.split("ARCHIVE_TRANSPORT_FAILURE:", 1)[1]) for line in text.splitlines() if "ARCHIVE_TRANSPORT_FAILURE:" in line]
            (failure,) = failures
            assert failure["phase"] == "readingResponse" and failure["cause_type"] == "HttpException", failure
            save("transport-failure.json", failure)
            books = [json.loads(line.split("ARCHIVE_FAILURE_JOURNAL:", 1)[1]) for line in text.splitlines() if "ARCHIVE_FAILURE_JOURNAL:" in line]
            (book,) = books
            save("failure-journal.json", book)
            (scope,) = list(book["scopes"].values())
            original_command = scope["inspect"]
            assert original_command.get("task") is None and original_command["digest"] == save_descriptor["sha256"]
            state = control("/status")
            assert state["upload_truncated"] and state["upload_task"]
            first_trace = control("/trace")["items"]
            first_requests = first_trace[len(before_trace):]
            imports = [r for r in first_requests if r["method"] == "POST" and r["path"] == "/api/v1/management-backups/imports"]
            assert len(imports) == 1 and imports[0]["idempotency_key"] == original_command["key"]
            assert not any(r["method"] == "POST" and "/restores" in r["path"] for r in first_requests)
            save("first-requests.json", first_requests)
            save("first-host-events.json", events.copy())
            file_id = original_command["file"]["id"]
            assert re.fullmatch(r"[a-f0-9]{32}", file_id)
            candidates = shell("run-as", PACKAGE, "find", "files/management-archives", "-name", file_id + ".vvbackup").splitlines()
            (owned_input,) = candidates
            assert re.fullmatch(r"files/management-archives/[a-f0-9]{64}/" + file_id + r"\.vvbackup", owned_input)
            assert int(shell("run-as", PACKAGE, "stat", "-c", "%s", owned_input)) == original_command["file"]["bytes"]
            shell("run-as", PACKAGE, "rm", owned_input)
            assert not shell("run-as", PACKAGE, "find", "files/management-archives", "-name", file_id + ".vvbackup")
            save("removed-owned-input.json", {"path": owned_input, "id": file_id, "removed": True})
            first_points = len(events)
            events.clear()
            scenes[:] = ["resume-start", "resume-preview", "resume-confirm-off"]
            command = command + ["--dart-define=ARCHIVE_RESUME_FAILURE=true"]
            process = subprocess.Popen(command, cwd=ROOT / "apps/mobile", stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            timer = threading.Timer(480, process.kill)
            timer.start()
            with (out / "resume-test.log").open("w") as log:
                for line in process.stdout:
                    log.write(line)
                    log.flush()
            resumed_code = process.wait(timeout=20)
            save("resume-exit.json", {"code": resumed_code})
            assert resumed_code == 0 and not errors and len(events) == 3, errors
            resumed_text = (out / "resume-test.log").read_text()
            verified = [json.loads(line.split("ARCHIVE_RESUME_VERIFIED:", 1)[1]) for line in resumed_text.splitlines() if "ARCHIVE_RESUME_VERIFIED:" in line]
            (verified,) = verified
            assert verified["original_key"] == original_command["key"] and verified["task"] == state["upload_task"]
            assert verified["epoch"] == info["management_epoch"] and verified["confirmation_off"]
            assert verified["sha256"] == save_descriptor["sha256"] and verified["roots"] == 27
            save("resume-verified.json", verified)
            resumed_pid = json.loads((out / "resumed-app-pid.json").read_text())["pid"]
            killed_pid = json.loads((out / "failure-force-stop.json").read_text())["old_pid"]
            assert resumed_pid and resumed_pid != killed_pid
            resumed_requests = control("/trace")["items"][len(first_trace):]
            assert resumed_requests and all(r["method"] == "GET" for r in resumed_requests)
            assert any(r["path"] == "/api/v1/management-backups/requests/inspect/" + original_command["key"] for r in resumed_requests)
            save("resumed-requests.json", resumed_requests)
            assert api("tasks/" + state["upload_task"])["status"] == "completed"
            assert api("info")["management_epoch"] == info["management_epoch"]
            for route in ("tags", "pack-tags"):
                assert len(api(route)["items"]) == 2
            assert before_media == media()
            save("media-after.json", media())
            save("result.json", {"passed": True, "injected_response_truncation": True, "original_issue_reproduced": False, "native_points": first_points + 1 + len(events), "system_points": len(system_events), "restore_posts": 0, "resume_posts": 0, "local_input_removed": True})
            print(json.dumps({"passed": True, "controlled_failure_and_restart": True, "native_points": first_points + 1 + len(events), "system_points": len(system_events)}), flush=True)
            return
        assert code == 0 and not errors, errors
        assert len(system_events) == len(system_stages) and len(events) == len(scenes)
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
        assert row["state"] == "completed" and row["kind"] == "backup_restore_v2"
        final_info = api("info")
        assert "backup_v2" in final_info["capabilities"]
        assert final_info["management_history_available"] is True
        assert final_info["management_epoch"] != info["management_epoch"]
        save("public-info-after.json", final_info)
        assert (save_descriptor["bytes"] > 32 * 1024 * 1024) == args.large
        journals = [
            json.loads(r.split("ARCHIVE_JOURNAL:", 1)[1])
            for r in text.splitlines()
            if "ARCHIVE_JOURNAL:" in r
        ]
        journal_stages = [
            "before-system-save",
            "before-restore-confirmation",
            "after-restore-and-snapshot",
        ]
        if args.cancel_first:
            journal_stages[1:1] = [
                "after-system-save-cancelled",
                "before-system-save",
                "after-system-pick-cancelled",
            ]
        assert [r["stage"] for r in journals] == journal_stages
        save("journals.json", journals)
        save("notes-after.json", notes_snapshot())
        assert notes_snapshot() == before_notes
        save("media-after.json", media())
        assert before_media == media()
        assert download_names() == before_downloads | {created_name}
        save(
            "document-cleanup.json",
            {"retained_owned_document": created_name, "other_names_unchanged": True},
        )
        save(
            "result.json",
            {
                "passed": True,
                "native_points": len(scenes),
                "system_points": len(system_stages),
                "window": [390, 844],
                "document": read_saved(out),
                "restore_posts": 1,
                "snapshot_preview_only": True,
                "large_document": args.large,
                "cancel_inputs": args.cancel_first,
            },
        )
        print(
            json.dumps(
                {
                    "passed": True,
                    "native_points": len(scenes),
                    "system_points": len(system_stages),
                }
            ),
            flush=True,
        )
    finally:
        cleanup_errors = []
        stop.set()
        if timer:
            timer.cancel()
        if process and process.poll() is None:
            process.kill()
            process.wait(timeout=20)
        if watcher:
            watcher.join(timeout=20)
        try:
            shell("am", "force-stop", PACKAGE)
            if "com.google.android.documentsui" in focus():
                shell("input", "keyevent", "4")
            save(
                "app-cleanup.json",
                {"app_pid": app_pid(), "focus": focus()},
            )
        except Exception as error:  # noqa: BLE001 - preserve cleanup alongside original failure
            save("app-cleanup-error.json", {"error": repr(error)})
            cleanup_errors.append("App cleanup: " + repr(error))
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
            restored = viewport()
            save("restored-viewport.json", {"before": original, "after": restored})
            assert restored == original, "Display configuration was not restored"
        except Exception as error:  # noqa: BLE001 - preserve cleanup alongside original failure
            save("restore-error.json", {"original": original, "error": repr(error)})
            cleanup_errors.append("Display cleanup: " + repr(error))
        finally:
            if container:
                try:
                    save("fixture-final.json", control("/status"))
                    save("requests-final.json", control("/trace")["items"])
                except Exception as error:  # noqa: BLE001 - service may already have failed
                    save("fixture-error.json", {"error": repr(error)})
                    cleanup_errors.append("Fixture evidence: " + repr(error))
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
        if cleanup_errors:
            save("cleanup-errors.json", cleanup_errors)
            if sys.exc_info()[0] is None:
                raise AssertionError("; ".join(cleanup_errors))


def read_saved(out):
    return json.loads((out / "saved-document.json").read_text())


if __name__ == "__main__":
    main()
