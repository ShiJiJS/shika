#!/usr/bin/env python3
"""Profile the photo fixture on owned AVD5558/server8773; never use real NAS.

Prepare the dedicated runtime/fixture before running. Output must be a new .dev
folder. This installs a profile integration APK on this dedicated AVD only.
"""

import argparse
import gzip
import hashlib
import json
import os
import re
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADB = ROOT / ".dev/android-sdk/platform-tools/adb"
PACKAGE = "io.github.shijijs.video_viewer"
SERIAL = "emulator-5558"
IMAGE = "sha256:886b79b72ecb9116087d892f230471943121f24ccef093113cc3197b4607fef4"


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument(
        "--long-diagnostic",
        action="store_true",
        help="One trial per size while debugging the full 500-page path; never final acceptance",
    )
    args = p.parse_args()
    trials = 1 if args.long_diagnostic else 30
    out = args.output.resolve()
    if out.exists() or not out.is_relative_to((ROOT / ".dev").resolve()):
        p.error("Use a new directory below this project .dev")
    out.mkdir(parents=True)

    def save(name, value):
        (out / name).write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")

    def device(*parts, timeout=30):
        return subprocess.check_output([str(ADB), "-s", SERIAL, *parts], timeout=timeout)

    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    assert "video_viewer_reader_perf_36" in device("emu", "avd", "name").decode()
    assert device("shell", "getprop", "sys.boot_completed").decode().strip() == "1"
    assert "uid=0(root)" in device("shell", "id").decode(), (
        "Root only this disposable AVD for passive /proc sampling"
    )
    runtime = json.loads(
        subprocess.check_output(["docker", "inspect", "video-viewer-reader-performance"], text=True)
    )[0]
    assert runtime["State"]["Running"] and runtime["Image"] == IMAGE
    assert runtime["Config"]["Labels"]["video-viewer.lab"] == "lf8-reader-performance"
    if not args.long_diagnostic:
        assert "video_viewer.app:create_app" in runtime["Config"]["Cmd"], (
            "Final timings require the normal runtime entrypoint, without diagnostic middleware"
        )
    assert any(
        m["Destination"] == "/media/packs"
        and not m["RW"]
        and m["Source"] == str(ROOT / ".dev/lf8-reader-performance/packs")
        for m in runtime["Mounts"]
    )
    for port in [8774]:
        with socket.socket() as guard:
            guard.bind(("127.0.0.1", port))
    source = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    relevant = [
        "apps/mobile/lib",
        "apps/mobile/android",
        "apps/mobile/pubspec.yaml",
        "apps/mobile/pubspec.lock",
        "apps/mobile/integration_test/server_reader_performance_test.dart",
        "apps/mobile/test_driver/reader_performance.dart",
        "scripts/run-reader-performance.py",
    ]
    assert not subprocess.check_output(
        ["git", "diff", "--name-only", source, "--", *relevant], cwd=ROOT
    ).strip(), "Freeze source before profiling"
    prototype = subprocess.check_output(
        ["git", "rev-parse", source + ":design/reference/library-first"], cwd=ROOT, text=True
    ).strip()
    qemu = [
        line.strip()
        for line in subprocess.check_output(
            ["ps", "-ax", "-o", "pid=,command="], text=True
        ).splitlines()
        if "qemu-system" in line
        and " -avd video_viewer_reader_perf_36 " in line
        and " -port 5558 " in line
    ]
    assert len(qemu) == 1
    save(
        "source.json",
        {
            "source": source,
            "prototype_tree": prototype,
            "qemu": qemu[0],
            "runtime": IMAGE,
            "runtime_command": runtime["Config"]["Cmd"],
            "runtime_entrypoint": runtime["Config"]["Entrypoint"],
            "profile_entrypoint": True,
            "normal_release_apk": False,
            "final_matrix": not args.long_diagnostic,
            "trial_count": trials,
            "sampling_interval_seconds": 1,
            "memory_definition": "kernel smaps_rollup PSS/RSS and status VmHWM; no meminfo/forced GC",
            "original_display": {
                key: device("shell", "wm", key).decode() for key in ["size", "density"]
            },
        },
    )
    stop = threading.Event()
    records, errors, memory_notes = [], [], []
    started = time.monotonic()

    class Control(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_POST(self):
            if (
                self.path != "/checkpoint"
                or self.headers.get("X-Fixture-Key") != "reader-performance-owned-only"
            ):
                self.send_error(403)
                return
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length < 20000:
                self.send_error(413)
                return
            value = json.loads(self.rfile.read(length))
            name = value["name"]
            if not re.fullmatch(r"[a-z0-9-]{1,80}", name):
                self.send_error(422)
                return
            try:
                focus = device("shell", "dumpsys", "window").decode()
                focus = "\n".join(
                    s.strip()
                    for s in focus.splitlines()
                    if "mCurrentFocus=" in s or "mFocusedApp=" in s
                )
                assert PACKAGE in focus
                (out / (name + "-window.txt")).write_text(focus + "\n")
                (out / (name + ".png")).write_bytes(device("exec-out", "screencap", "-p"))
                pid = device("shell", "pidof", PACKAGE).decode().strip()
                assert pid.isdigit()
                (out / (name + "-memory.txt")).write_bytes(
                    device("shell", "cat", f"/proc/{pid}/smaps_rollup", f"/proc/{pid}/status")
                )
                value.update(
                    elapsed_seconds=time.monotonic() - started,
                    png_sha256=sha(out / (name + ".png")),
                )
                records.append(value)
                save("checkpoints.json", records)
                body = json.dumps({"captured": name}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                print(json.dumps({"checkpoint": name}), flush=True)
            except Exception as error:
                errors.append(repr(error))
                save("observer-errors.json", errors)
                self.send_error(500)

    server = ThreadingHTTPServer(("127.0.0.1", 8774), Control)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    def sample():
        with gzip.open(out / "memory-samples.jsonl.gz", "wt") as stream:
            while not stop.wait(1):
                if (out / "profile-result.json").exists():
                    memory_notes.append(
                        {
                            "event": "terminal_test_report",
                            "elapsed_seconds": time.monotonic() - started,
                        }
                    )
                    save("memory-observation-notes.json", memory_notes)
                    return
                begin = time.monotonic()
                try:
                    query = subprocess.run(
                        [str(ADB), "-s", SERIAL, "shell", "pidof", PACKAGE],
                        capture_output=True,
                        timeout=10,
                    )
                    if query.returncode and query.stderr:
                        raise subprocess.CalledProcessError(query.returncode, query.args)
                    pid = query.stdout.decode().strip()
                    if not pid:
                        continue
                    if not pid.isdigit():
                        raise ValueError("Expected one App process, got " + repr(pid))
                    raw = device(
                        "shell", "cat", f"/proc/{pid}/smaps_rollup", f"/proc/{pid}/status"
                    ).decode()
                    record = {
                        "elapsed_seconds": begin - started,
                        "pid": pid,
                        "raw": raw,
                        "sample_seconds": time.monotonic() - begin,
                    }
                    stream.write(json.dumps(record) + "\n")
                    stream.flush()
                except (subprocess.SubprocessError, OSError, ValueError) as error:
                    if (out / "profile-result.json").exists():
                        memory_notes.append(
                            {
                                "event": "process_read_after_terminal_report",
                                "elapsed_seconds": time.monotonic() - started,
                                "detail": repr(error),
                            }
                        )
                        save("memory-observation-notes.json", memory_notes)
                        return
                    errors.append("memory sample: " + repr(error))
                    save("observer-errors.json", errors)
                    return

    def sample_environment():
        # Capture the verified current runtime, never an earlier lab container
        # ID from a setup file. Recreated diagnostic runtimes have new IDs.
        with gzip.open(out / "environment-samples.jsonl.gz", "wt") as stream:
            while not stop.wait(5):
                try:
                    server_stats = subprocess.run(
                        ["docker", "stats", "--no-stream", "--format", "{{json .}}", runtime["Id"]],
                        capture_output=True,
                        text=True,
                        timeout=10,
                        check=True,
                    )
                    value = json.loads(server_stats.stdout)
                    if not value.get("ID") or not runtime["Id"].startswith(value["ID"]):
                        raise ValueError("Resource sample belongs to another container")
                    qemu_stats = subprocess.run(
                        ["ps", "-p", qemu[0].split()[0], "-o", "pid=,rss=,%cpu=,vsz="],
                        capture_output=True,
                        text=True,
                        timeout=5,
                        check=True,
                    )
                    stream.write(
                        json.dumps(
                            {
                                "elapsed_seconds": time.monotonic() - started,
                                "runtime_id": runtime["Id"],
                                "server": value,
                                "qemu_fields": ["pid", "rss_kib", "cpu_percent", "vsz_kib"],
                                "qemu": qemu_stats.stdout.strip(),
                            }
                        )
                        + "\n"
                    )
                    stream.flush()
                except (subprocess.SubprocessError, OSError, ValueError) as error:
                    errors.append("environment sample: " + repr(error))
                    save("observer-errors.json", errors)
                    return

    sampler = threading.Thread(target=sample, daemon=True)
    environment_sampler = threading.Thread(target=sample_environment, daemon=True)
    sampler.start()
    environment_sampler.start()
    env = os.environ.copy()
    env["VV_READER_BENCH_OUTPUT"] = str(out)
    command = [
        "bash",
        str(ROOT / "scripts/dev.sh"),
        "flutter",
        "drive",
        "--profile",
        "-d",
        SERIAL,
        "--driver=test_driver/reader_performance.dart",
        "--target=integration_test/server_reader_performance_test.dart",
    ]
    if args.long_diagnostic:
        command.append("--dart-define=READER_BENCH_TRIALS=1")
    save("command.json", {"command": command, "cwd": str(ROOT / "apps/mobile")})
    process = None
    try:
        with (out / "flutter-drive.log").open("wb") as log:
            process = subprocess.Popen(
                command, cwd=ROOT / "apps/mobile", env=env, stdout=log, stderr=subprocess.STDOUT
            )
            save("live-process.json", {"pid": process.pid, "command": command})
            try:
                code = process.wait(timeout=3000)
            except subprocess.TimeoutExpired:
                process.terminate()
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=10)
                raise
        stop.set()
        sampler.join(timeout=35)
        environment_sampler.join(timeout=20)
        if sampler.is_alive():
            errors.append("Memory sampler did not stop")
        if environment_sampler.is_alive():
            errors.append("Environment sampler did not stop")
        save(
            "result.json",
            {
                "checks_passed": False,
                "final_matrix": not args.long_diagnostic,
                "exit_code": code,
                "observer_errors": errors,
                "memory_observation_notes": memory_notes,
                "memory_scope": "App process samples through atomic terminal test report; driver closes afterward",
                "elapsed_seconds": time.monotonic() - started,
                "checkpoints": len(records),
            },
        )
        if code or errors:
            raise RuntimeError("Profile run failed; preserve output and inspect flutter-drive.log")
        result = json.loads((out / "profile-result.json").read_text())["reader_benchmark"]
        assert result["trial_count"] == trials
        assert result["final_matrix"] == (not args.long_diagnostic)
        assert result["completed"] and result["reached"] == list(range(500))
        for phase in ["4k-open", "8k-open", "4k-adjacent", "8k-adjacent"]:
            values = [v for v in result["samples"] if v["phase"] == phase]
            assert len(values) == trials and sorted(v["trial"] for v in values) == list(
                range(trials)
            )
        final = json.loads((out / "result.json").read_text())
        final["checks_passed"] = True
        save("result.json", final)
        print(
            json.dumps(
                {"completed": True, "final_matrix": not args.long_diagnostic, "output": str(out)}
            ),
            flush=True,
        )
    finally:
        stop.set()
        sampler.join(timeout=35)
        environment_sampler.join(timeout=20)
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
        # Only release this runner's app; keep dedicated emulator/runtime for next round.
        device("shell", "am", "force-stop", PACKAGE)
        save(
            "runner-cleanup.json",
            {
                "control_closed": True,
                "sampler_stopped": not sampler.is_alive(),
                "environment_sampler_stopped": not environment_sampler.is_alive(),
                "app_stopped": True,
                "runtime_emulator_retained_for_next_round": True,
            },
        )


if __name__ == "__main__":
    main()
