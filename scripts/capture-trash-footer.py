#!/usr/bin/env python3
"""Supplement existing native evidence with actual large/short footer views.

Uses only the dedicated emulator and public 8761 fixture. Derives the existing
native flow up to its lost restore receipt, then scrolls to the pending footer.
The fixed-source 45-point run remains separate. Only the explicit 26-pack restore
is submitted; no receipt query or duplicate submission is performed.
"""

import argparse
import hashlib
import importlib.util
import json
import subprocess
import threading
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=["large", "landscape"], required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location(
        "connection_runner", ROOT / "scripts/run-client-connection-test.py"
    )
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runner.EVIDENCE = args.output.resolve()
    runner.EVIDENCE.mkdir(parents=True, exist_ok=False)
    runner.PREFIX = "lf8-trash"

    def device(*command):
        return subprocess.check_output(
            [runner.ADB, "-s", "emulator-5554", "shell", *command],
            text=True,
            timeout=10,
        ).strip()

    def viewport():
        return {
            "size": device("wm", "size"),
            "density": device("wm", "density"),
            "font_scale": device("settings", "get", "system", "font_scale"),
        }

    runner.prepare_emulator()
    original = viewport()
    width, height, scale = (
        (360, 740, "2.0") if args.profile == "large" else (844, 390, "1.0")
    )
    original_test = ROOT / "apps/mobile/integration_test/server_trash_management_test.dart"
    generated = ROOT / "apps/mobile/integration_test/lf8_trash_footer_generated_test.dart"
    assert not generated.exists(), "Do not overwrite a pre-existing test"
    text = original_test.read_text()
    tail = (ROOT / "scripts/trash-footer-tail.dart.txt").read_text()
    derived = text.split("      await shot('unknown');", 1)[0] + tail
    generated.write_text(derived)
    (runner.EVIDENCE / "generated-test.dart.txt").write_text(derived)
    (runner.EVIDENCE / "capture-source.py.txt").write_text(Path(__file__).read_text())
    (runner.EVIDENCE / "tail-source.dart.txt").write_text(tail)
    source_paths = subprocess.check_output(
        ["git", "ls-files", "apps/mobile/lib", "services/server/video_viewer"],
        cwd=ROOT,
        text=True,
    ).splitlines() + [
        "apps/mobile/integration_test/server_trash_management_test.dart",
        "scripts/trash-footer-tail.dart.txt",
        "scripts/capture-trash-footer.py",
        "scripts/run-client-connection-test.py",
        "services/server/tests/e2e_server.py",
    ]
    source = {
        "production_commit": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
        ).strip(),
        "generated_sha256": hashlib.sha256(derived.encode()).hexdigest(),
        "profile": args.profile,
        "window": [width, height],
        "files": {
            name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
            for name in source_paths
        },
    }
    (runner.EVIDENCE / "source.json").write_text(json.dumps(source, indent=2) + "\n")
    watcher = None
    try:
        with (runner.EVIDENCE / "preparation.log").open("w") as setup_log:
            subprocess.run(
                ["bash", str(ROOT / "scripts/prepare-client-e2e.sh"), "--reset"],
                cwd=ROOT,
                stdout=setup_log,
                stderr=subprocess.STDOUT,
                check=True,
                timeout=180,
            )
        device("wm", "size", f"{width * 3}x{height * 3}")
        device("wm", "density", "480")
        device("settings", "put", "system", "font_scale", scale)
        request = urllib.request.Request(
            "http://127.0.0.1:8761/__fixture/checkpoint/ready",
            headers=runner.HEADERS,
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=10) as response:
            response.read()
        watcher = threading.Thread(target=runner.watch, daemon=True)
        watcher.start()
        with (runner.EVIDENCE / "android-test.log").open("w") as log:
            result = subprocess.run(
                [
                    "bash",
                    str(ROOT / "scripts/dev.sh"),
                    "flutter",
                    "test",
                    "integration_test/lf8_trash_footer_generated_test.dart",
                    "-d",
                    "emulator-5554",
                    "--no-uninstall",
                    "--reporter",
                    "expanded",
                ],
                cwd=ROOT / "apps/mobile",
                stdout=log,
                stderr=subprocess.STDOUT,
                timeout=300,
                check=False,
            )
        assert result.returncode == 0, "See android-test.log"
    finally:
        generated.unlink(missing_ok=True)
        runner.stop.set()
        if watcher is not None:
            watcher.join(timeout=30)
        for name in ["size", "density"]:
            override = next(
                (
                    line.split(":", 1)[1].strip()
                    for line in original[name].splitlines()
                    if line.startswith("Override")
                ),
                "reset",
            )
            device("wm", name, override)
        if original["font_scale"] == "null":
            device("settings", "delete", "system", "font_scale")
        else:
            device("settings", "put", "system", "font_scale", original["font_scale"])
        (runner.EVIDENCE / "restored-viewport.json").write_text(
            json.dumps({"before": original, "after": viewport()}, indent=2) + "\n"
        )
        (runner.EVIDENCE / "host-events.json").write_text(
            json.dumps({"events": runner.events, "errors": runner.errors}, indent=2)
            + "\n"
        )
    assert not runner.errors, runner.errors
    text = (runner.EVIDENCE / "android-test.log").read_text()
    assert "All tests passed!" in text and "TRASH_FOOTER_VERIFIED:" in text
    metrics = [json.loads(line.split("TRASH_METRICS:", 1)[1])
               for line in text.splitlines() if "TRASH_METRICS:" in line]
    assert len(metrics) == 11 and metrics[-1]["state"] == "trash-unknown"
    for suffix in [".png", "-window.txt", "-files.json", "-requests.json", "-plan.json"]:
        assert (runner.EVIDENCE / f"lf8-trash-trash-unknown{suffix}").is_file()
    (runner.EVIDENCE / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
    print(json.dumps({"profile": args.profile, "supplemental_footer": 1,
                      "production_commit": source["production_commit"]}))


if __name__ == "__main__":
    main()
