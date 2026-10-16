"""Windows host runner for the disposable Android/public-API connection test.

Prepares/resets the dedicated fixture using prepare-client-e2e.sh --reset.
Only the explicitly named e2e container may be stopped by this runner.
"""
import json
import os
from pathlib import Path
import subprocess
import threading
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
EVIDENCE = ROOT / "tmp" / "client-e2e"
DEVELOP = Path.home() / "develop"
HEADERS = {"X-Fixture-Key": "isolated-emulator-control"}
CONTAINER = "video-viewer-client-e2e-server-1"
stop = threading.Event()
events = []
errors = []


def docker(*args):
    return subprocess.run(["wsl", "-d", "Ubuntu-24.04", "--", "docker", *args],
                          check=True, capture_output=True, text=True, timeout=30)


def watch():
    seen = set()
    try:
        while not stop.wait(0.3):
            try:
                request = urllib.request.Request("http://127.0.0.1:8761/__fixture/checkpoint", headers=HEADERS)
                with urllib.request.urlopen(request, timeout=2) as response:
                    phase = json.load(response)["phase"]
            except (OSError, ValueError):
                continue
            if phase in seen:
                continue
            seen.add(phase)
            events.append({"phase": phase, "time": time.time()})
            if phase in {"library", "roots", "recovered"}:
                request = urllib.request.Request("http://127.0.0.1:8761/__fixture/trace", headers=HEADERS)
                with urllib.request.urlopen(request, timeout=2) as response:
                    (EVIDENCE / f"i1-{phase}-requests.json").write_text(
                        json.dumps(json.load(response), ensure_ascii=False, indent=2), encoding="utf-8")
                result = subprocess.run([str(DEVELOP / "android-sdk/platform-tools/adb.exe"),
                                         "-s", "emulator-5554", "exec-out", "screencap", "-p"],
                                        capture_output=True, check=True, timeout=15)
                (EVIDENCE / f"i1-{phase}.png").write_bytes(result.stdout)
            if phase == "outage":
                docker("stop", "--time", "0", CONTAINER)
                events.append({"phase": "docker-stopped", "time": time.time()})
                stop.wait(8)
                docker("start", CONTAINER)
                events.append({"phase": "docker-started", "time": time.time()})
    except Exception as error:
        errors.append(str(error))


def main():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    linux_root = "/mnt/" + ROOT.drive.rstrip(":").lower() + ROOT.as_posix()[2:]
    subprocess.run(["wsl", "-d", "Ubuntu-24.04", "--", "bash",
                    linux_root + "/scripts/prepare-client-e2e.sh", "--reset"], check=True)
    env = os.environ.copy()
    env.update(PUB_CACHE=str(DEVELOP / "pub-cache"), PUB_HOSTED_URL="https://pub.flutter-io.cn",
               FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn")
    watcher = threading.Thread(target=watch, daemon=True)
    watcher.start()
    try:
        command = [str(DEVELOP / "flutter/bin/flutter.bat"), "test",
                   "integration_test/server_connection_test.dart", "-d", "emulator-5554",
                   "--no-uninstall", "--reporter", "expanded"]
        with (EVIDENCE / "i1-android-test.log").open("w", encoding="utf-8") as log:
            code = 0
            for resume in (False, True):
                if resume:
                    subprocess.run([str(DEVELOP / "android-sdk/platform-tools/adb.exe"),
                                    "-s", "emulator-5554", "shell", "am", "force-stop",
                                    "io.github.shijijs.video_viewer"], check=True, timeout=15)
                    events.append({"phase": "android-force-stopped", "time": time.time()})
                process = subprocess.Popen(command + (["--dart-define=E2E_RESUME=true"] if resume else []),
                                           cwd=ROOT / "apps/mobile", env=env, stdout=subprocess.PIPE,
                                           stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
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
        (EVIDENCE / "i1-host-events.json").write_text(
            json.dumps({"events": events, "errors": errors}, ensure_ascii=False, indent=2), encoding="utf-8")
    if errors:
        raise SystemExit("Fixture host controller failed: " + "; ".join(errors))
    raise SystemExit(code)


if __name__ == "__main__":
    main()
