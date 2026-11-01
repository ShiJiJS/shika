#!/usr/bin/env python3
"""Real App backup UI on the existing, opt-in public 8762 fixture and owned AVD.

Performs one explicitly confirmed replacement of that fixture's management data.
Does not restart/reset services, delete media, change the SDK, or publish an APK.
"""

import argparse
import hashlib
import importlib.util
import json
import subprocess
import threading
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "io.github.shijijs.video_viewer"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--viewport", choices=("390", "360", "844"), required=True)
    parser.add_argument("--scale", choices=("1", "2"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    spec = importlib.util.spec_from_file_location("client_runner", ROOT / "scripts/run-client-connection-test.py")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runner.prepare_emulator()

    def control(path, method="GET"):
        request = urllib.request.Request("http://127.0.0.1:8762/__archive_fixture" + path,
                                         headers={"X-Fixture-Key": "archive-app-isolated-control"}, method=method)
        with urllib.request.urlopen(request, timeout=10) as response:
            return json.load(response)

    def save(name, value):
        (out / name).write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")

    def device(*command):
        return subprocess.check_output([runner.ADB, "-s", "emulator-5554", *command], timeout=20)

    def shell(*command):
        return device("shell", *command).decode().strip()

    def viewport():
        return {"size": shell("wm", "size"), "density": shell("wm", "density"),
                "font_scale": shell("settings", "get", "system", "font_scale")}

    def media():
        base = ROOT / ".dev/archive-app/media"
        return {str(p.relative_to(base)): {"bytes": p.stat().st_size,
                "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
                for p in sorted(base.rglob("*")) if p.is_file()}

    assert control("/status")["armed"] is None, "Do not interrupt an armed restart test"
    old = viewport()
    before_trace = control("/trace")["items"]
    before_media = media()
    save("media-before.json", before_media)
    paths = subprocess.check_output(["git", "ls-files", "apps/mobile/lib", "services/server/video_viewer"], cwd=ROOT, text=True).splitlines() + [
        "apps/mobile/integration_test/server_archive_management_test.dart", "apps/mobile/test/support/reveal_action.dart",
        "scripts/run-archive-management-test.py", "scripts/run-client-connection-test.py", "services/server/tests/archive_app_fixture.py",
    ]
    save("source.json", {"commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True, cwd=ROOT).strip(),
                          "files": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}})
    stop = threading.Event()
    events, errors = [], []

    def watch():
        seen = set()
        try:
            while not stop.wait(.2):
                state = control("/status")
                name = state["display"]
                if not name or not name.startswith("archive-ui-") or state["display_ack"] or name in seen:
                    continue
                raw = shell("dumpsys", "window")
                focus = "\n".join(line.strip() for line in raw.splitlines() if "mCurrentFocus=" in line or "mFocusedApp=" in line)
                assert any("mCurrentFocus=" in line and PACKAGE in line for line in focus.splitlines()), focus
                (out / (name + "-window.txt")).write_text(focus + "\n")
                (out / (name + ".png")).write_bytes(device("exec-out", "screencap", "-p"))
                save(name + "-requests.json", {"items": control("/trace")["items"][len(before_trace):]})
                save(name + "-media.json", media())
                events.append({"state": name, "epoch": state["epoch"]})
                seen.add(name)
                control("/ack/" + name, "POST")
        except Exception as failure:  # noqa: BLE001 - leave the native test waiting/failing instead of hiding capture failures
            errors.append(repr(failure))

    watcher = None
    try:
        width, height = {"390": (390, 844), "360": (360, 740), "844": (844, 390)}[args.viewport]
        shell("wm", "size", f"{width * 3}x{height * 3}")
        shell("wm", "density", "480")
        shell("settings", "put", "system", "font_scale", args.scale)
        watcher = threading.Thread(target=watch, daemon=True)
        watcher.start()
        with (out / "android-test.log").open("w") as log:
            result = subprocess.run(["bash", str(ROOT / "scripts/dev.sh"), "flutter", "test",
                "integration_test/server_archive_management_test.dart", "--no-uninstall", "-d", "emulator-5554", "--reporter", "expanded"],
                cwd=ROOT / "apps/mobile", stdout=log, stderr=subprocess.STDOUT, timeout=360, check=False)
        assert result.returncode == 0, "See android-test.log"
        after_trace = control("/trace")["items"]
        assert after_trace[:len(before_trace)] == before_trace, "Bounded trace was truncated; cannot prove this run"
        requests = after_trace[len(before_trace):]
        save("requests.json", {"items": requests})
        save("media-after.json", media())
        assert media() == before_media
        assert len(events) == 8 and not errors
        text = (out / "android-test.log").read_text()
        assert "All tests passed!" in text and "ARCHIVE_UI_VERIFIED:" in text
        writes = [e for e in requests if e["method"] == "POST"]
        for path, count in [("/api/v1/management-backups", 1), ("/api/v1/management-backups/imports", 1),
                            ("/api/v1/management-backups/restores", 1), ("/api/v1/auth/login", 1)]:
            assert sum(e["path"] == path for e in writes) == count, (path, writes)
        assert sum("/from-snapshot/" in e["path"] for e in writes) == 1
        save("result.json", {"passed": True, "window": [width, height], "font_scale": args.scale,
                             "native_points": 8, "restore_posts": 1, "snapshot_preview_only": True})
        print(json.dumps({"passed": True, "native_points": 8}), flush=True)
    finally:
        stop.set()
        if watcher is not None:
            watcher.join(timeout=20)
        for name in ["size", "density"]:
            value = next((v.split(":", 1)[1].strip() for v in old[name].splitlines() if v.startswith("Override")), "reset")
            shell("wm", name, value)
        if old["font_scale"] == "null":
            shell("settings", "delete", "system", "font_scale")
        else:
            shell("settings", "put", "system", "font_scale", old["font_scale"])
        save("restored-viewport.json", {"before": old, "after": viewport()})
        save("host-events.json", {"events": events, "errors": errors})


if __name__ == "__main__":
    main()
