#!/usr/bin/env python3
"""Exercise generated 500-page/4K/8K packs on one owned localhost 8769."""

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
APP = "io.github.shijijs.video_viewer"
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--output", type=Path, required=True)
p.add_argument("--skia", action="store_true", help="Record a test-only renderer override")
args = p.parse_args()
out = args.output.resolve()
if out.exists() or not out.is_relative_to((ROOT / ".dev").resolve()):
    p.error("Use a new directory beneath .dev")
out.mkdir(parents=True)
base = out / "fixture"
for name in ("data", "config", "packs"):
    (base / name).mkdir(parents=True)
(base / "config/passphrase").write_text("reader-long-pack-owned-only")
(base / "config/mounts.json").write_text(
    json.dumps([{"id": "packs", "name": "Long synthetic packs", "path": "/media/packs"}])
)


def run(*command):
    return subprocess.check_output(command, cwd=ROOT, text=True).strip()


def device(*command, timeout=25):
    return subprocess.check_output([str(ADB), "-s", "emulator-5554", *command], timeout=timeout)


def shell(*command):
    return device("shell", *command).decode().strip()


def save(name, value):
    (out / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def state(path="/state", post=False):
    req = urllib.request.Request(
        "http://127.0.0.1:8769/__long_reader" + path,
        headers={"X-Fixture-Key": "reader-long-pack-owned-control"},
        method="POST" if post else "GET",
    )
    with urllib.request.urlopen(req, timeout=15) as response:
        return json.load(response)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def media():
    return {
        str(path.relative_to(base / "packs")): sha(path)
        for path in sorted((base / "packs").rglob("*"))
        if path.is_file()
    }


assert shell("getprop", "sys.boot_completed") == "1"
assert "video_viewer_api_36" in shell("getprop", "ro.boot.qemu.avd_name")
original = {name: shell("wm", name) for name in ("size", "density")}
font = shell("settings", "get", "system", "font_scale")
source_paths = run(
    "git", "ls-files", "apps/mobile/lib", "services/server/video_viewer"
).splitlines()
source_paths += [
    "scripts/run-reader-long-pack-test.py",
    "scripts/fixtures/generate-lf0-packs.py",
    "services/server/tests/reader_long_pack_fixture.py",
    "apps/mobile/integration_test/server_reader_long_pack_test.dart",
]
source_files = {name: sha(ROOT / name) for name in source_paths}
save(
    "source.json",
    {
        "commit": run("git", "rev-parse", "HEAD"),
        "files": source_files,
        "prototype_tree": run("git", "rev-parse", "HEAD:design/reference/library-first"),
    },
)
run(
    "python3", str(ROOT / "scripts/fixtures/generate-lf0-packs.py"), "--output", str(base / "packs")
)
before = media()
save("media-before.json", before)
container = None
stop = threading.Event()
errors, screens, recordings = [], [], []
record_process = None
record_pid = None
record_path = None
started = time.monotonic()
save("result.json", {"status": "running", "source": run("git", "rev-parse", "HEAD")})


def begin_record():
    global record_process, record_pid, record_path
    existing = subprocess.run(
        [str(ADB), "-s", "emulator-5554", "shell", "pidof", "screenrecord"],
        capture_output=True,
        text=True,
    )
    if existing.stdout.strip():
        raise RuntimeError("Another screenrecord is running; preserve it")
    record_path = f"/sdcard/long-reader-{time.time_ns()}.mp4"
    record_process = subprocess.Popen(
        [
            str(ADB),
            "-s",
            "emulator-5554",
            "shell",
            "screenrecord",
            "--size",
            "390x844",
            "--bit-rate",
            "1000000",
            "--time-limit",
            "180",
            record_path,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        value = subprocess.run(
            [str(ADB), "-s", "emulator-5554", "shell", "pidof", "screenrecord"],
            capture_output=True,
            text=True,
        ).stdout.strip()
        if value:
            assert value.isdigit()
            record_pid = value
            return
        time.sleep(0.1)
    raise RuntimeError("Owned screenrecord did not start")


def end_record():
    global record_process, record_pid, record_path
    if record_process is None:
        return
    if record_process.poll() is None:
        subprocess.run(
            [str(ADB), "-s", "emulator-5554", "shell", "kill", "-2", record_pid],
            capture_output=True,
            timeout=10,
            check=False,
        )
    record_process.wait(timeout=15)
    filename = f"gesture-{len(recordings) + 1:02d}.mp4"
    device("pull", record_path, str(out / filename), timeout=40)
    assert (out / filename).stat().st_size > 1000
    recordings.append(
        {"file": filename, "bytes": (out / filename).stat().st_size, "sha256": sha(out / filename)}
    )
    device("shell", "rm", record_path)
    record_process = record_pid = record_path = None


def watch():
    last_sample = 0
    try:
        while not stop.wait(0.2):
            current = state()
            name = current["display"]
            if name and name != "verified" and record_process is None:
                begin_record()
            if record_process is not None and record_process.poll() is not None:
                end_record()
                if not stop.is_set():
                    begin_record()
            if name and name != "verified" and name not in screens and not current["ack"]:
                focus = "\n".join(
                    row.strip()
                    for row in shell("dumpsys", "window").splitlines()
                    if "mCurrentFocus=" in row or "mFocusedApp=" in row
                )
                assert any("mCurrentFocus=" in row and APP in row for row in focus.splitlines())
                (out / (name + "-window.txt")).write_text(focus + "\n")
                (out / (name + ".png")).write_bytes(device("exec-out", "screencap", "-p"))
                (out / (name + "-memory.txt")).write_text(shell("dumpsys", "meminfo", "-s", APP))
                screens.append(name)
                state("/ack/" + name, post=True)
                print(json.dumps({"checkpoint": name}), flush=True)
            now = time.monotonic()
            if now - last_sample >= 3 and name:
                last_sample = now
                sample = {
                    "elapsed_seconds": round(now - started, 3),
                    "phase": name,
                    "pid": shell("pidof", APP),
                    "raw": shell("dumpsys", "meminfo", "-s", APP),
                }
                with (out / "memory-samples.jsonl").open("a") as stream:
                    stream.write(json.dumps(sample) + "\n")
    except Exception as error:
        errors.append(repr(error))


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
        "video-viewer-long-reader-" + str(time.time_ns()),
        "-p",
        "127.0.0.1:8769:8760",
        "-v",
        str(ROOT / "services/server") + ":/source:ro",
        "-v",
        str(base / "data") + ":/data",
        "-v",
        str(base / "config") + ":/fixture:ro",
        "-v",
        str(base / "packs") + ":/media/packs:ro",
        "-w",
        "/source",
        "-e",
        "VV_LONG_READER_FIXTURE=enabled",
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
        "video-viewer-reference-check:7c70e5983f8e",
        "tests.reader_long_pack_fixture:create_long_reader_app",
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
            assert state()["fixture"] == "reader-long-pack-owned-8769"
            break
        except (urllib.error.URLError, ConnectionError):
            if time.monotonic() > deadline:
                raise
            time.sleep(0.2)
    shell("wm", "size", "1170x2532")
    shell("wm", "density", "480")
    shell("settings", "put", "system", "font_scale", "1")
    save(
        "device.json",
        {
            "size": shell("wm", "size"),
            "density": shell("wm", "density"),
            "font": shell("settings", "get", "system", "font_scale"),
            "android": shell("getprop", "ro.build.version.release"),
            "avd": shell("getprop", "ro.boot.qemu.avd_name"),
            "renderer_override_skia": args.skia,
        },
    )
    watcher = threading.Thread(target=watch, daemon=True)
    watcher.start()
    command = [
        "bash",
        str(ROOT / "scripts/dev.sh"),
        "flutter",
        "test",
        "integration_test/server_reader_long_pack_test.dart",
        "--no-uninstall",
        "-d",
        "emulator-5554",
        "--reporter",
        "expanded",
    ]
    if args.skia:
        command.append("--no-enable-impeller")
    with (out / "flutter.log").open("w") as log:
        process = subprocess.Popen(
            command, cwd=ROOT / "apps/mobile", stdout=log, stderr=subprocess.STDOUT
        )
        save("process.json", {"pid": process.pid, "command": command})
        try:
            code = process.wait(timeout=1800)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
            raise
    final = state("/state?include_requests=true")
    save("fixture-final.json", final)
    assert code == 0 and not errors, {"code": code, "watcher_errors": errors}
    assert final["display"] == "verified"
    assert set(screens) == {
        "long-horizontal",
        "long-vertical-start",
        "long-page-101",
        "long-page-201",
        "long-page-301",
        "long-page-401",
        "long-vertical-end",
        "long-horizontal-end",
        "large-page-1",
        "large-page-2",
        "large-page-3",
        "long-return",
        "long-reopened",
    }
    verified = final["measurements"][-1]["client"]
    assert verified["visited_indexes"] == list(range(500))
    assert len(verified["large_frames"]) == 9
    assert {row["index"] for row in verified["large_frames"]} == {0, 1, 2}
    after = media()
    save("media-after.json", after)
    assert before == after
    assert source_files == {name: sha(ROOT / name) for name in source_paths}
    with sqlite3.connect((base / "data/library.sqlite3").as_uri() + "?mode=ro", uri=True) as db:
        rows = db.execute(
            "SELECT pack_id,page_id,completed,revision FROM pack_progress ORDER BY pack_id"
        ).fetchall()
        assert {row[0] for row in rows} == {verified["long_pack"], verified["large_pack"]}
        assert (
            next(row for row in rows if row[0] == verified["long_pack"])[1]
            == verified["last_page_id"]
        )
        save(
            "database-proof.json",
            {
                "progress": rows,
                "packs": db.execute(
                    "SELECT id,name,page_count FROM packs ORDER BY name"
                ).fetchall(),
                "recent": db.execute(
                    "SELECT kind,pack_id FROM recent_entries ORDER BY pack_id"
                ).fetchall(),
            },
        )
    save(
        "result.json",
        {
            "status": "passed",
            "source_files": source_files,
            "screens": screens,
            "verified": verified,
            "elapsed_seconds": round(time.monotonic() - started, 2),
        },
    )
    print(json.dumps({"passed": True, "screens": len(screens)}), flush=True)
except BaseException as error:
    save(
        "result.json",
        {
            "status": "failed",
            "error": repr(error),
            "watcher_errors": errors,
            "screens": screens,
            "elapsed_seconds": round(time.monotonic() - started, 2),
        },
    )
    raise
finally:
    stop.set()
    if "watcher" in globals():
        watcher.join(timeout=30)
        if watcher.is_alive():
            errors.append("Watcher did not finish")
    try:
        end_record()
    except Exception as error:
        errors.append("recording cleanup: " + repr(error))
    save("recordings.json", recordings)
    try:
        (out / "android.log").write_bytes(device("logcat", "-d", "-t", "6000"))
        for name, value in original.items():
            shell(
                "wm",
                name,
                value.split("Override " + name + ":")[-1].strip()
                if "Override " in value
                else "reset",
            )
        shell("settings", "put", "system", "font_scale", font)
        restored = {name: shell("wm", name) for name in original}
        restored_font = shell("settings", "get", "system", "font_scale")
        assert restored == original and restored_font == font
        save(
            "restored-viewport.json",
            {
                "before": original,
                "after": restored,
                "font_before": font,
                "font_after": restored_font,
                "errors": errors,
            },
        )
    except Exception as error:
        errors.append("device restore: " + repr(error))
        save("restore-failure.json", {"before": original, "font": font, "errors": errors})
    if container:
        try:
            logs = subprocess.run(
                ["docker", "logs", container],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            ).stdout
            (out / "server.log").write_bytes(logs)
        finally:
            try:
                run("docker", "rm", "-f", container)
            except Exception as error:
                errors.append("container cleanup: " + repr(error))
    if errors:
        current = json.loads((out / "result.json").read_text())
        current.update(status="failed", cleanup_or_watcher_errors=errors)
        save("result.json", current)
        raise RuntimeError(errors)
