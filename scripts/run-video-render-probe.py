#!/usr/bin/env python3
"""Compare fixed public media through Flutter and debug-only Android renderers."""

import argparse
import hashlib
import http.server
import json
import subprocess
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADB = ROOT / ".dev/android-sdk/platform-tools/adb"
APP = "io.github.shijijs.video_viewer"
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--output", type=Path, required=True)
p.add_argument("--renderer", choices=("default", "skia"), default="default")
p.add_argument("--skip-native", action="store_true")
args = p.parse_args()
out = args.output.resolve()
if out.exists() or not out.is_relative_to((ROOT / ".dev").resolve()):
    p.error("Use a new directory beneath .dev")
out.mkdir(parents=True)


def device(*a, timeout=25):
    return subprocess.check_output(
        [str(ADB), "-s", "emulator-5554", *a], timeout=timeout, stderr=subprocess.PIPE
    )


def shell(*a):
    return device("shell", *a).decode().strip()


def save(name, value):
    (out / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


assert shell("getprop", "ro.boot.qemu.avd_name") == "video_viewer_api_36"
assert shell("getprop", "sys.boot_completed") == "1"
original = {k: shell("wm", k) for k in ("size", "density")}
font = shell("settings", "get", "system", "font_scale")
save("original.json", {"display": original, "font": font})
paths = [
    "apps/mobile/integration_test/video_render_probe_test.dart",
    "apps/mobile/android/app/src/debug/AndroidManifest.xml",
    "apps/mobile/android/app/src/debug/kotlin/io/github/shijijs/video_viewer/VideoRenderProbeActivity.kt",
    "scripts/run-video-render-probe.py",
    "apps/mobile/assets/media/flower-landscape.mp4",
]
save(
    "source.json",
    {
        "commit": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
        ).strip(),
        "files": {n: sha(ROOT / n) for n in paths},
    },
)
save(
    "environment.json",
    {
        "api": shell("getprop", "ro.build.version.sdk"),
        "abi": shell("getprop", "ro.product.cpu.abi"),
        "hardware": shell("getprop", "ro.hardware"),
        "host_avc_decoder": shell("getprop", "ro.boot.qemu.hwcodec.avcdec"),
        "process": [
            s
            for s in subprocess.check_output(
                ["ps", "-axo", "command"], text=True
            ).splitlines()
            if "qemu-system-aarch64" in s and "-avd video_viewer_api_36" in s
        ],
        "flutter_renderer": args.renderer,
    },
)
state = {"name": None, "ack": False}
lock = threading.Lock()
stop = threading.Event()
errors = []


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def handle_request(self):
        if self.headers.get("X-Fixture-Key") != "owned-public-render-probe":
            self.send_error(403)
            return
        with lock:
            if self.command == "POST" and self.path.startswith("/checkpoint/"):
                name = self.path.rsplit("/", 1)[-1]
                if name not in {"textureView", "platformView"}:
                    self.send_error(400)
                    return
                state.update(name=name, ack=False)
            elif self.command != "GET" or self.path != "/state":
                self.send_error(404)
                return
            payload = json.dumps(state).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = handle_request
    do_POST = handle_request


server = http.server.ThreadingHTTPServer(("127.0.0.1", 8770), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()


def capture(name):
    window = "\n".join(
        s.strip()
        for s in shell("dumpsys", "window").splitlines()
        if "mCurrentFocus=" in s or "mFocusedApp=" in s
    )
    assert APP in window, window
    (out / (name + ".png")).write_bytes(device("exec-out", "screencap", "-p"))
    (out / (name + "-window.txt")).write_text(window + "\n")


def watch():
    seen = set()
    try:
        while not stop.wait(0.15):
            with lock:
                name = state["name"]
                ack = state["ack"]
            if not name or ack or name in seen:
                continue
            capture("flutter-" + name)
            seen.add(name)
            with lock:
                state["ack"] = True
    except Exception as error:  # noqa: BLE001 - diagnostic receipt
        errors.append(repr(error))


watcher = threading.Thread(target=watch, daemon=True)
try:
    shell("wm", "size", "1170x2532")
    shell("wm", "density", "480")
    shell("settings", "put", "system", "font_scale", "1.0")
    watcher.start()
    command = [
        "bash",
        str(ROOT / "scripts/dev.sh"),
        "flutter",
        "test",
        "integration_test/video_render_probe_test.dart",
        "--no-uninstall",
        "-d",
        "emulator-5554",
        "--reporter",
        "expanded",
    ]
    if args.renderer == "skia":
        command.append("--no-enable-impeller")
    save("command.json", command)
    with (out / "flutter.log").open("w") as log:
        result = subprocess.run(
            command,
            cwd=ROOT / "apps/mobile",
            stdout=log,
            stderr=subprocess.STDOUT,
            timeout=300,
            check=False,
        )
    log = (out / "flutter.log").read_text()
    assert result.returncode == 0 and "RENDER_PROBE_VERIFIED" in log and not errors
    if not args.skip_native:
        for mode in ("surface", "texture", "codec"):
            identity = f"{mode}-{time.time_ns()}"
            shell(
                "am",
                "start",
                "-W",
                "-n",
                APP + "/.VideoRenderProbeActivity",
                "--es",
                "fixture",
                "owned-public-video-probe",
                "--es",
                "mode",
                mode,
                "--es",
                "run_id",
                identity,
            )
            deadline = time.monotonic() + 35
            while True:
                try:
                    value = json.loads(
                        device(
                            "exec-out",
                            "run-as",
                            APP,
                            "cat",
                            "cache/video-render-probe.json",
                        )
                    )
                except (subprocess.CalledProcessError, json.JSONDecodeError):
                    value = {}
                if value.get("run_id") == identity and value.get("status") in {
                    "ready",
                    "error",
                }:
                    break
                if time.monotonic() > deadline:
                    raise RuntimeError("Native probe deadline " + mode)
                time.sleep(0.2)
            save("native-" + mode + ".json", value)
            assert value["status"] == "ready", value
            if mode != "codec":
                assert value["details"]["rendering_started"] and value["details"]["seek_completed"]
                assert value["details"]["view_width"] > value["details"]["view_height"]
                assert value["details"]["root_width"] > value["details"]["root_height"]
            assert value["source_sha256"] == sha(
                ROOT / "apps/mobile/assets/media/flower-landscape.mp4"
            )
            capture("native-" + mode)
            shell("input", "keyevent", "4")
    save(
        "result.json",
        {"passed": True, "renderer": args.renderer, "native": not args.skip_native},
    )
    print(json.dumps({"passed": True, "output": str(out)}))
finally:
    stop.set()
    if watcher.is_alive():
        watcher.join(timeout=10)
    server.shutdown()
    server.server_close()
    try:
        for k, value in original.items():
            shell(
                "wm",
                k,
                value.split("Override " + k + ":")[-1].strip()
                if "Override " in value
                else "reset",
            )
        shell("settings", "put", "system", "font_scale", font)
        save(
            "restored.json",
            {
                "before": original,
                "after": {k: shell("wm", k) for k in original},
                "font_before": font,
                "font_after": shell("settings", "get", "system", "font_scale"),
                "errors": errors,
            },
        )
    finally:
        (out / "native.log").write_bytes(
            device(
                "logcat",
                "-d",
                "-s",
                "CCodec",
                "MediaCodec",
                "VV_RENDER_PROBE",
                "flutter",
                "FlutterJNI",
                "AndroidRuntime",
            )
        )
