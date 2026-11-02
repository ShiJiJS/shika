#!/usr/bin/env python3
"""One isolated Android authority round, with optional verified process stop.

Uses only the generated port-8761 fixture and the dedicated API-36 emulator.
All original viewport settings are restored, even after a failed round.
"""

import argparse
import importlib.util
import json
import subprocess
import threading
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("connection_runner", ROOT / "scripts/run-client-connection-test.py")
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
PACKAGE = "io.github.shijijs.video_viewer"


def control(path, method="GET"):
    request = urllib.request.Request("http://127.0.0.1:8761" + path, headers=common.HEADERS, method=method)
    with urllib.request.urlopen(request, timeout=45) as response:
        return json.load(response)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--viewport", choices=["360", "390"], default="390")
    parser.add_argument("--text-scale", choices=["1", "2"], default="1")
    parser.add_argument("--strong-stop", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    events, errors = [], []
    stop = threading.Event()

    def save(name, value):
        (output / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")

    def device(*command):
        return subprocess.check_output([common.ADB, "-s", "emulator-5554", "shell", *command], text=True, timeout=15).strip()

    def pid():
        result = subprocess.run([common.ADB, "-s", "emulator-5554", "shell", "pidof", PACKAGE], capture_output=True, text=True, timeout=10)
        return result.stdout.strip()

    def watch():
        seen = set()
        try:
            while not stop.wait(.25):
                phase = control("/__fixture/checkpoint")["phase"]
                if phase in seen or not phase.startswith("authority-"):
                    continue
                seen.add(phase)
                windows = device("dumpsys", "window")
                focus = "\n".join(line.strip() for line in windows.splitlines() if "mCurrentFocus=" in line or "mFocusedApp=" in line)
                (output / f"{phase}-window.txt").write_text(focus + "\n")
                assert any("mCurrentFocus=" in line and PACKAGE in line for line in focus.splitlines()), focus
                png = subprocess.check_output([common.ADB, "-s", "emulator-5554", "exec-out", "screencap", "-p"], timeout=15)
                (output / f"{phase}.png").write_bytes(png)
                save(f"{phase}-requests.json", control("/__fixture/trace"))
                save(f"{phase}-stats.json", control("/__fixture/authority/stats"))
                events.append({"phase": phase, "pid": pid(), "time": time.time()})
        except Exception as error:
            errors.append(repr(error))

    common.prepare_emulator()
    old_size, old_density = device("wm", "size"), device("wm", "density")
    old_scale = device("settings", "get", "system", "font_scale")
    width, height = (390, 844) if args.viewport == "390" else (360, 740)
    watcher = None
    try:
        device("wm", "size", f"{width * 3}x{height * 3}")
        device("wm", "density", "480")
        device("settings", "put", "system", "font_scale", args.text_scale)
        events.append({"phase": "viewport", "width_dp": width, "height_dp": height, "text_scale": args.text_scale})
        subprocess.run(["bash", str(ROOT / "scripts/prepare-client-e2e.sh"), "--reset"], check=True)
        watcher = threading.Thread(target=watch, daemon=True)
        watcher.start()
        killed_pid = None
        for phase in range(2 if args.strong_stop else 1):
            command = [common.FLUTTER, "test", "integration_test/server_client_authority_test.dart", "-d", "emulator-5554", "--no-uninstall", "--reporter", "expanded"]
            if args.strong_stop:
                command.append("--dart-define=E2E_STRONG_STOP=true")
            if phase:
                command.append("--dart-define=E2E_RESUME=true")
            forced = False
            reopened = False
            with (output / f"phase-{phase}.log").open("w") as log:
                process = subprocess.Popen(command, cwd=ROOT / "apps/mobile", stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                timer = threading.Timer(420, process.kill)
                timer.start()
                try:
                    for line in process.stdout:
                        log.write(line)
                        log.flush()
                        print(line, end="", flush=True)
                        if "VV_E2E_AUTHORITY_FORCE_STOP" in line:
                            assert args.strong_stop and phase == 0
                            killed_pid = pid()
                            assert killed_pid
                            device("am", "force-stop", PACKAGE)
                            assert not pid()
                            forced = True
                            events.append({"phase": "verified-force-stop", "old_pid": killed_pid, "absent": True})
                            restored = control("/__fixture/authority/restore", "POST")
                            assert not pid()
                            save("restore-while-absent.json", restored)
                            events.append({"phase": "restored-while-absent", "absent": True})
                        if "VV_E2E_AUTHORITY_REOPENED" in line:
                            fresh_pid = pid()
                            assert phase == 1 and fresh_pid and fresh_pid != killed_pid
                            reopened = True
                            events.append({"phase": "verified-new-process", "old_pid": killed_pid, "new_pid": fresh_pid})
                    code = process.wait(timeout=30)
                finally:
                    timer.cancel()
                    if process.poll() is None:
                        process.kill()
                events.append({"phase": f"runner-{phase}", "exit_code": code, "intentional_stop": forced})
                if phase == 0 and args.strong_stop:
                    assert forced and killed_pid, "First phase never reached verified force-stop"
                else:
                    assert code == 0, f"Native phase failed: {code}"
                    assert not args.strong_stop or reopened, "No verified replacement process"
        assert not errors, errors
        save("final-requests.json", control("/__fixture/trace"))
        save("final-stats.json", control("/__fixture/authority/stats"))
    finally:
        stop.set()
        if watcher:
            watcher.join(timeout=5)
        for name, previous in (("size", old_size), ("density", old_density)):
            override = next((line.split(":", 1)[1].strip() for line in previous.splitlines() if line.startswith("Override")), "reset")
            device("wm", name, override)
        if old_scale == "null":
            device("settings", "delete", "system", "font_scale")
        else:
            device("settings", "put", "system", "font_scale", old_scale)
        save("events.json", {"events": events, "watcher_errors": errors, "restored_viewport": {"size": device("wm", "size"), "density": device("wm", "density"), "font_scale": device("settings", "get", "system", "font_scale")}})


if __name__ == "__main__":
    main()
